// Owning-client-authoritative sub-SM net-identity resolution.
//
// Spawns ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn on the server and possesses it
// with the remote client's PlayerController, so on the client world the pawn is locally-controlled-
// by-player. The bridged entity-script builds a Replicates / OwningClientAuthoritative / WithHistory
// parent SM whose initial state (AS UCk_SmNetSubTest_Parent_Hold) hosts a UCk_SmTask_SubStateMachine.
// The owning client starts the SM; the SubStateMachine task spawns a sub-SM (Sub_Wait → Sub_Reached)
// that advances ONLY through a tick-gated Delay task.
//
// The sub-SM entity is created detached from the pawn (no owning-actor fragment). Before
// FFragment_Sm_NetIdentity, the sub-SM misresolved to NonOwningClient on the owning client, so
// FProcessor_SmTask_Tick gated its Delay off and Sub_Wait never completed. The SubStateMachine task
// now stamps the parent's resolved identity (OwningClient / OwningClientAuthoritative) onto the
// sub-SM, so the Delay ticks on the owning client and the sub-SM reaches Sub_Reached.
//
// The parent never transitions (the sub-SM is KeepRunning) so this test never enqueues a
// replicated-SM transition — it stays surgical to the sub-SM net-identity fix. The sub-SM is
// DoesNotReplicate, so its own Sub_Wait → Sub_Reached transition is self-authoritative on every
// machine and never touches the authority gate.
//
// PASS: the OWNING CLIENT's sub-SM reaches Sub_Reached. (Pre-fix it stays stuck in Sub_Wait.)
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientAuth_SubSmTickGated

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"
#include "CkStateMachine/Task/CkSmTask_Fragment.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_subsm_test
{
    auto Find_PawnSubject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn*
    {
        if (InWorld == nullptr)
        { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn>(InWorld); It; ++It)
        { return *It; }
        return nullptr;
    }

    // Navigate parent SM → current state → the SubStateMachine task → sub-SM handle → current state
    // class name. Returns empty if any link isn't resolved yet (sub-SM not spawned, no current state,
    // etc.). The AS class name has its leading 'U' stripped in the UClass FName.
    constexpr auto k_SubReachedStateName = TEXT("Ck_SmNetSubTest_Sub_Reached");

    auto Get_SubSmCurrentStateName(ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn* InPawn) -> FString
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_OwningClientAuth_SubSmTickGated,
    "Ck.StateMachine.Net.OwningClientAuth_SubSmTickGated",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientAuth_SubSmTickGated::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;     // entity-script Construct on both worlds + SM setup
    constexpr auto FramesAfterPossess = 30;   // possession replication to the client
    constexpr auto FramesAfterStart = 30;     // parent enters Parent_Hold + SubTask spawns the sub-SM

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the SubSm pawn subject on the server --------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn>(
                ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of SubSm pawn returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Possess the pawn with the remote client's PlayerController -----------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Pawn = ck_sm_subsm_test::Find_PawnSubject(InServer);
            if (Pawn == nullptr)
            { AddError(TEXT("server-side SubSm pawn not found at possession time")); return; }

            auto* ClientPC = ck::auto_test::net::Get_RemoteClientPlayerController(InServer, 0);
            if (ClientPC == nullptr)
            { AddError(TEXT("could not resolve remote client[0] PlayerController on the server")); return; }

            ClientPC->Possess(Pawn);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterPossess));

    // ---- Precondition: ownership resolved on the client -----------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { AddError(TEXT("client world unavailable at precondition check")); return false; }

            auto* ClientPawn = ck_sm_subsm_test::Find_PawnSubject(Client);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side SubSm pawn not found — did it replicate?")); return false; }

            const auto LocallyControlled =
                UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ClientPawn);
            TestEqual(TEXT("PRECONDITION: client pawn is locally-controlled-by-player (possession resolved)"),
                static_cast<int32>(LocallyControlled),
                static_cast<int32>(ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled));

            return true;
        }),
        TEXT("ownership precondition — possession resolved on client")));

    // ---- Owning client starts the SM (AutoStart is Disabled for OwningClientAuth) ---------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = ck_sm_subsm_test::Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side SubSm pawn not found at start time")); return; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine))
            { AddError(TEXT("client-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Start(ClientPawn->_TestStateMachine);

            // Pre-warm the owning client's SM relay channel so the run-status push resolves promptly
            // (mirrors the OwningClientAuth local-commit spec).
            UCk_Utils_StateMachine_UE::Acquire_RelayChannel(ClientPawn->_TestStateMachine);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterStart));

    // ---- Wait for the owning client's sub-SM to advance to Sub_Reached --------------------------------------
    // This is the regression target: it can only happen if the sub-SM resolves its net identity to
    // OwningClient / OwningClientAuthoritative on the owning client (via FFragment_Sm_NetIdentity), so
    // its tick-gated Delay task runs. Pre-fix the sub-SM is NonOwningClient → Delay never ticks →
    // Sub_Wait never completes → this never converges (times out).

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }

            auto* ClientPawn = ck_sm_subsm_test::Find_PawnSubject(Client);
            return ck_sm_subsm_test::Get_SubSmCurrentStateName(ClientPawn)
                == ck_sm_subsm_test::k_SubReachedStateName;
        }),
        10.0,
        TEXT("owning-client sub-SM advances to Sub_Reached (tick-gated Delay ran — net identity resolved)")));

    // ---- Assertion: owning client's sub-SM reached Sub_Reached ----------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { AddError(TEXT("client world unavailable at assertion time")); return false; }

            auto* ClientPawn = ck_sm_subsm_test::Find_PawnSubject(Client);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client pawn missing at assertion time")); return false; }

            TestEqual(TEXT("owning-client sub-SM is at Sub_Reached (tick-gated Delay ran on the owning client)"),
                ck_sm_subsm_test::Get_SubSmCurrentStateName(ClientPawn),
                FString{ck_sm_subsm_test::k_SubReachedStateName});

            return true;
        }),
        TEXT("owning-client sub-SM resolved net identity and advanced")));

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
