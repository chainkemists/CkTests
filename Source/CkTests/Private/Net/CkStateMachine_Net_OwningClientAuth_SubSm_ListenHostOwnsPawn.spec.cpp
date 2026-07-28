// Regression guard: a LISTEN-SERVER HOST that owns its OWN pawn must be able to drive its
// OwningClientAuthoritative sub-SM (the "listen server can't move" bug).
//
// Identical topology to Ck.StateMachine.Net.OwningClientAuth_SubSm_AuthorityGatedTask, but the pawn is
// possessed by the HOST's OWN PlayerController (the listen server's local player) instead of a remote
// client. So on the server world the pawn is BOTH server-authoritative AND locally-controlled-by-player
// — the listen-server-host-owns-own-pawn case the other specs never cover (they all possess with a
// remote client).
//
// WHY IT WAS RED (the regression):
//   The sub-SM is DoesNotReplicate and stamped NetContext == Server (ComputeNetContext of its root, on
//   the host). Get_IsTransitionAuthority's IsHostOwningClient probe called
//   Get_IsEntityLocallyControlled_ByPlayer on the SUB-SM entity — but a sub-SM is a driverless child
//   entity with no owning-actor, so the probe returned IsNotValidPawn → IsHostOwningClient == false →
//   the sub-SM was SUPPRESSED on the host (treated like a dedicated server following a relay that does
//   not exist). Its InputPressed condition never evaluated, so it stayed in Sub_Idle. In the real player
//   HFSM the locomotion sub-SM stuck in Loco_Idle (which has no Movement task) → the host could not move.
//
//   Fix: resolve IsHostOwningClient via the ROOT SM (which IS bridged to the pawn), so a host that owns
//   the pawn its sub-SM belongs to is correctly detected and self-derives.
//
// PASS: the HOST's sub-SM reaches Sub_Active and the authority-gated x1.5 modifier holds (speed 150).
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientAuth_SubSm_ListenHostOwnsPawn

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

namespace ck_sm_subsm_listenhost_test
{
    using PawnType = ACk_AutoTest_NetSubject_StateMachineOwningClientSubSmGated_Pawn;

    constexpr auto k_InputTagName  = TEXT("ByteAttribute.Gyms.Intent.R");
    constexpr auto k_SpeedTagName  = TEXT("FloatAttribute.Gyms.A");
    constexpr auto k_SubActiveName = TEXT("Ck_SmNetSubGatedTest_Sub_Active");
    constexpr auto k_ExpectedSpeedWhenFixed = 150.0f;

    auto Find_Pawn(UWorld* InWorld) -> PawnType*
    {
        if (InWorld == nullptr)
        { return nullptr; }
        for (auto It = TActorIterator<PawnType>(InWorld); It; ++It)
        { return *It; }
        return nullptr;
    }

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
    FCkStateMachineNet_OwningClientAuth_SubSm_ListenHostOwnsPawn,
    "Ck.StateMachine.Net.OwningClientAuth_SubSm_ListenHostOwnsPawn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientAuth_SubSm_ListenHostOwnsPawn::RunTest(const FString& Parameters)
{
    using namespace ck_sm_subsm_listenhost_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // listen server (host) + 1 remote client (establishes NM_ListenServer)
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;
    constexpr auto FramesAfterPossess = 30;
    constexpr auto FramesAfterStart = 30;
    constexpr auto FramesAfterInput = 30;
    constexpr auto FramesAfterSettle = 60;

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

    // ---- Possess with the HOST's OWN PlayerController (listen server local player) -------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Pawn = Find_Pawn(InServer);
            if (Pawn == nullptr)
            { AddError(TEXT("server-side SubSmGated pawn not found at possession time")); return; }

            auto* HostPC = InServer->GetFirstPlayerController();
            if (HostPC == nullptr)
            { AddError(TEXT("could not resolve the listen-server host PlayerController")); return; }

            HostPC->Possess(Pawn);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterPossess));

    // ---- Precondition: the SERVER pawn is locally-controlled-by-player (host owns its own pawn) ------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { AddError(TEXT("server world unavailable at precondition check")); return false; }

            auto* ServerPawn = Find_Pawn(Server);
            if (ServerPawn == nullptr)
            { AddError(TEXT("server-side SubSmGated pawn not found at precondition")); return false; }

            const auto LocallyControlled = UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ServerPawn);
            TestEqual(TEXT("PRECONDITION: server pawn is locally-controlled-by-player (host owns its own pawn)"),
                static_cast<int32>(LocallyControlled),
                static_cast<int32>(ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled));

            return true;
        }),
        TEXT("ownership precondition — host possesses its own pawn")));

    // ---- Host starts the SM ------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* ServerPawn = Find_Pawn(InServer);
            if (ServerPawn == nullptr)
            { AddError(TEXT("server-side SubSmGated pawn not found at start time")); return; }
            if (ck::Is_NOT_Valid(ServerPawn->_TestStateMachine))
            { AddError(TEXT("server-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Start(ServerPawn->_TestStateMachine, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterStart));

    // ---- Set the byte "input" intent = 1 on the HOST -----------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* ServerPawn = Find_Pawn(InServer);
            if (ServerPawn == nullptr)
            { AddError(TEXT("server-side SubSmGated pawn not found at input time")); return; }

            const auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(ServerPawn);
            if (ck::Is_NOT_Valid(Entity))
            { AddError(TEXT("server-side pawn has no bridged entity at input time")); return; }

            const auto InputTag = FGameplayTag::RequestGameplayTag(FName{k_InputTagName});
            auto InputAttr = UCk_Utils_ByteAttribute_UE::TryGet(Entity, InputTag);
            if (ck::Is_NOT_Valid(InputAttr))
            { AddError(TEXT("server-side byte 'input' attribute not found — entity-script did not compose it")); return; }

            UCk_Utils_ByteAttribute_UE::Request_Override(InputAttr, static_cast<uint8>(1), ECk_MinMaxCurrent::Current, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterInput));

    // ---- Wait for the HOST's sub-SM to advance to Sub_Active (the regression target) ---------------------
    // RED before the fix: the host's sub-SM is suppressed (IsHostOwningClient probed the sub-SM entity,
    // which has no owning-actor) so its InputPressed condition never evaluates and it stays in Sub_Idle.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { return false; }
            return Get_SubSmCurrentStateName(Find_Pawn(Server)) == FString{k_SubActiveName};
        }),
        10.0,
        TEXT("listen-host sub-SM advances to Sub_Active (host self-derives its own OwningClientAuth sub-SM)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSettle));

    // ---- TARGET: host holds Sub_Active and the authority-gated modifier applies (speed 150) --------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { AddError(TEXT("server world unavailable at assertion time")); return false; }

            auto* ServerPawn = Find_Pawn(Server);
            if (ServerPawn == nullptr)
            { AddError(TEXT("server pawn missing at assertion time")); return false; }

            const auto ServerSub   = Get_SubSmCurrentStateName(ServerPawn);
            const auto ServerSpeed = Get_SpeedFinalValue(ServerPawn);

            UE_LOG(LogTemp, Display,
                TEXT("[SubSmListenHostDiag] host sub-SM=[%s] host speed=[%s] (expect %.1f)"),
                *ServerSub,
                ServerSpeed.IsSet() ? *FString::SanitizeFloat(*ServerSpeed) : TEXT("<none>"),
                k_ExpectedSpeedWhenFixed);

            TestEqual(TEXT("listen-host sub-SM holds Sub_Active (host drives its own sub-SM)"),
                ServerSub, FString{k_SubActiveName});

            if (NOT ServerSpeed.IsSet())
            { AddError(TEXT("server-side float 'speed' attribute not found at assertion time")); return false; }

            TestEqual(TEXT("listen-host speed holds the authority-gated x1.5 modifier"),
                *ServerSpeed, k_ExpectedSpeedWhenFixed);

            return true;
        }),
        TEXT("TARGET: listen host drives its own sub-SM and the modifier holds")));

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
