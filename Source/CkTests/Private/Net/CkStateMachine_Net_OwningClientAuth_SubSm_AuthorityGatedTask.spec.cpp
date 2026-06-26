// Red baseline for the BusterBlock "remote clients can't sprint" bug, distilled to framework
// primitives. Reproduces: an OwningClientAuthoritative + Replicates + WithHistory parent SM hosting a
// (non-replicated) sub-SM whose Sub_Idle -> Sub_Active transition is gated on a byte attribute set
// client-locally, where Sub_Active runs an AUTHORITY-GATED task that applies a Multiply modifier to a
// float attribute.
//
// Spawns ACk_AutoTest_NetSubject_StateMachineOwningClientSubSmGated_Pawn on the server, possesses with
// the remote client's PlayerController (so on the client world the pawn is locally-controlled-by-
// player), starts the SM on the owning client, then sets the byte "input" attribute = 1 ONLY on the
// owning client — exactly how the input profile sets the sprint intent.
//
// WHY IT IS RED:
//   - The sub-SM is DoesNotReplicate (created by UCk_SmTask_SubStateMachine), so it is driven locally
//     on every machine from that machine's own byte-attr copy.
//   - The owning client's copy is 1, so its sub-SM enters Sub_Active — but the modifier task no-ops
//     there (the client lacks entity authority).
//   - The server HAS entity authority, but its byte-attr copy is 0 (the client-local Override never
//     reaches it), so its sub-SM never enters Sub_Active and never runs the task.
//   - The Multiply modifier is therefore added on NO machine; the float "speed" stays at base 100.
//
// Assertions:
//   - PRECONDITION (expect PASS today): the owning client's sub-SM reaches Sub_Active — proves the
//     client side transitions; isolates the failure to the authority-gated effect.
//   - TARGET (RED today, GREEN when the bug is fixed): the owning client's float "speed" FinalValue
//     == base 100 * 1.5 == 150. Fix-agnostic: any correct fix (server sees the input, state lifted to
//     a driver-bearing SM, or client-predicted consequence) makes the remote client's speed reflect
//     the multiplier.
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientAuth_SubSm_AuthorityGatedTask

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"
#include "CkStateMachine/Task/CkSmTask_Fragment.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Utils.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_subsm_gated_test
{
    using PawnType = ACk_AutoTest_NetSubject_StateMachineOwningClientSubSmGated_Pawn;

    constexpr auto k_InputTagName  = TEXT("ByteAttribute.Gyms.Intent.R");
    constexpr auto k_SpeedTagName  = TEXT("FloatAttribute.Gyms.A");
    constexpr auto k_SubActiveName = TEXT("Ck_SmNetSubGatedTest_Sub_Active");

    // base 100 * Multiply 1.5 — the FinalValue the owning client SHOULD observe once a remote client
    // can sprint. Today the modifier is never applied, so the observed value stays at base (100).
    constexpr auto k_ExpectedSpeedWhenFixed = 150.0f;

    auto Find_Pawn(UWorld* InWorld) -> PawnType*
    {
        if (InWorld == nullptr)
        { return nullptr; }
        for (auto It = TActorIterator<PawnType>(InWorld); It; ++It)
        { return *It; }
        return nullptr;
    }

    // Navigate parent SM -> current state -> the SubStateMachine task -> sub-SM handle -> current
    // state class name. Empty if any link isn't resolved yet. The AS class name has its leading 'U'
    // stripped in the UClass FName.
    auto Get_SubSmCurrentStateName(PawnType* InPawn) -> FString
    {
        if (InPawn == nullptr || ck::Is_NOT_Valid(InPawn->_TestStateMachine))
        { return {}; }

        const auto ParentState = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(InPawn->_TestStateMachine);
        if (ck::Is_NOT_Valid(ParentState))
        { return {}; }

        auto SubSm = FCk_Handle_StateMachine{};
        UCk_Utils_StateMachine_UE::RecordOfSmTasks_Utils::ForEach_ValidEntry(ParentState,
        [&](FCk_Handle_SmTask InTask) -> ECk_Record_ForEachIterationResult
        {
            if (InTask.Has<ck::FFragment_SmTask_SubStateMachine>())
            {
                SubSm = InTask.Get<ck::FFragment_SmTask_SubStateMachine>().Get_SubStateMachineHandle();
                return ECk_Record_ForEachIterationResult::Break;
            }
            return ECk_Record_ForEachIterationResult::Continue;
        });

        if (ck::Is_NOT_Valid(SubSm))
        { return {}; }

        const auto* CurrentClass = UCk_Utils_StateMachine_UE::Get_CurrentStateClass(SubSm).Get();
        return CurrentClass != nullptr ? CurrentClass->GetName() : FString{};
    }

    auto Get_SpeedFinalValue(PawnType* InPawn) -> TOptional<float>
    {
        if (InPawn == nullptr)
        { return {}; }

        const auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InPawn);
        if (ck::Is_NOT_Valid(Entity))
        { return {}; }

        const auto SpeedTag = FGameplayTag::RequestGameplayTag(FName{k_SpeedTagName});
        const auto SpeedAttr = UCk_Utils_FloatAttribute_UE::TryGet(Entity, SpeedTag);
        if (ck::Is_NOT_Valid(SpeedAttr))
        { return {}; }

        return UCk_Utils_FloatAttribute_UE::Get_FinalValue(SpeedAttr);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_OwningClientAuth_SubSm_AuthorityGatedTask,
    "Ck.StateMachine.Net.OwningClientAuth_SubSm_AuthorityGatedTask",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientAuth_SubSm_AuthorityGatedTask::RunTest(const FString& Parameters)
{
    using namespace ck_sm_subsm_gated_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterPossess = 30;
    constexpr auto FramesAfterStart = 30;
    constexpr auto FramesAfterInput = 30;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the subject pawn on the server --------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<PawnType>(PawnType::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of SubSmGated pawn returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Possess with the remote client's PlayerController -------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Pawn = Find_Pawn(InServer);
            if (Pawn == nullptr)
            { AddError(TEXT("server-side SubSmGated pawn not found at possession time")); return; }

            auto* ClientPC = ck::auto_test::net::Get_RemoteClientPlayerController(InServer, 0);
            if (ClientPC == nullptr)
            { AddError(TEXT("could not resolve remote client[0] PlayerController on the server")); return; }

            ClientPC->Possess(Pawn);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterPossess));

    // ---- Precondition: possession resolved on the client --------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { AddError(TEXT("client world unavailable at precondition check")); return false; }

            auto* ClientPawn = Find_Pawn(Client);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side SubSmGated pawn not found — did it replicate?")); return false; }

            const auto LocallyControlled = UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ClientPawn);
            TestEqual(TEXT("PRECONDITION: client pawn is locally-controlled-by-player (possession resolved)"),
                static_cast<int32>(LocallyControlled),
                static_cast<int32>(ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled));

            return true;
        }),
        TEXT("ownership precondition — possession resolved on client")));

    // ---- Owning client starts the SM (AutoStart Disabled for OwningClientAuth) -----------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = Find_Pawn(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side SubSmGated pawn not found at start time")); return; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine))
            { AddError(TEXT("client-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Start(ClientPawn->_TestStateMachine);
            UCk_Utils_StateMachine_UE::Acquire_RelayChannel(ClientPawn->_TestStateMachine);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterStart));

    // ---- Set the byte "input" intent = 1 ONLY on the owning client (mirrors the input profile) ------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = Find_Pawn(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side SubSmGated pawn not found at input time")); return; }

            const auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ClientPawn);
            if (ck::Is_NOT_Valid(Entity))
            { AddError(TEXT("client-side pawn has no bridged entity at input time")); return; }

            const auto InputTag = FGameplayTag::RequestGameplayTag(FName{k_InputTagName});
            auto InputAttr = UCk_Utils_ByteAttribute_UE::TryGet(Entity, InputTag);
            if (ck::Is_NOT_Valid(InputAttr))
            { AddError(TEXT("client-side byte 'input' attribute not found — entity-script did not compose it")); return; }

            UCk_Utils_ByteAttribute_UE::Request_Override(InputAttr, static_cast<uint8>(1));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterInput));

    // ---- Precondition: owning client's sub-SM reaches Sub_Active (proves the client side transitions) ------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }
            return Get_SubSmCurrentStateName(Find_Pawn(Client)) == FString{k_SubActiveName};
        }),
        10.0,
        TEXT("owning-client sub-SM advances to Sub_Active (byte input consumed locally)")));

    // ---- Give the round-trip time (client -> root relay -> server sub-SM -> modifier -> replicate back) ----
    // WaitUntil so a slow round-trip can't read as a false-red; if the logic is broken it simply times out
    // and the assertion below fails with the diagnostic logged.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }
            const auto Speed = Get_SpeedFinalValue(Find_Pawn(Client));
            return Speed.IsSet() && FMath::IsNearlyEqual(*Speed, k_ExpectedSpeedWhenFixed, 0.01f);
        }),
        10.0,
        TEXT("owning-client speed reaches 150 (authority-gated modifier applied + replicated)")));

    // ---- TARGET: the owning client's float speed reflects the x1.5 modifier -------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Client == nullptr || Server == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            auto* ClientPawn = Find_Pawn(Client);
            auto* ServerPawn = Find_Pawn(Server);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client pawn missing at assertion time")); return false; }

            const auto ClientSpeed = Get_SpeedFinalValue(ClientPawn);
            const auto ServerSpeed = Get_SpeedFinalValue(ServerPawn);

            // Diagnostics to the editor log (UE_LOG, not AddInfo — AddInfo goes to the test report, not
            // the .log the toolbox captures). Shows where the chain broke: server sub-SM state + speeds.
            UE_LOG(LogTemp, Display,
                TEXT("[SubSmRelayDiag] client sub-SM=[%s] server sub-SM=[%s] | client speed=[%s] server speed=[%s] (expect %.1f)"),
                *Get_SubSmCurrentStateName(ClientPawn),
                *Get_SubSmCurrentStateName(ServerPawn),
                ClientSpeed.IsSet() ? *FString::SanitizeFloat(*ClientSpeed) : TEXT("<none>"),
                ServerSpeed.IsSet() ? *FString::SanitizeFloat(*ServerSpeed) : TEXT("<none>"),
                k_ExpectedSpeedWhenFixed);

            if (NOT ClientSpeed.IsSet())
            { AddError(TEXT("client-side float 'speed' attribute not found at assertion time")); return false; }

            TestEqual(TEXT("owning-client speed reflects the authority-gated x1.5 sprint modifier"),
                *ClientSpeed, k_ExpectedSpeedWhenFixed);

            return true;
        }),
        TEXT("TARGET: remote client's authority-gated sub-SM modifier takes effect")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
