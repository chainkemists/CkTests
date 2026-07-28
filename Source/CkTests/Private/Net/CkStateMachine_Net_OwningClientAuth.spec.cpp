// Owning-client-authoritative local-commit replication.
//
// Spawns ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn on the server and possesses it with
// the remote client's PlayerController (Get_RemoteClientPlayerController), so on the client world
// the pawn reports locally-controlled-by-player. The bridged entity-script builds a Replicates /
// OwningClientAuthoritative / WithHistory SM (initial state A). The OWNING CLIENT then drives a
// transition A→B via Request_Transition; the SM commits locally on the client AND publishes through
// ACk_StateMachineRelay_UE → server applies → re-publishes. Both worlds should converge to B.
//
// A precondition gate asserts the ownership handshake resolved on the client BEFORE the transition
// is driven — otherwise an unresolved possession would surface as an opaque "SM never reached B"
// timeout instead of "ownership didn't resolve".
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientAuth_LocalCommitReplicates

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_owningclient_test
{
    auto Find_PawnSubject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn*
    {
        if (InWorld == nullptr)
        { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn>(InWorld); It; ++It)
        { return *It; }
        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_OwningClientAuth_LocalCommitReplicates,
    "Ck.StateMachine.Net.OwningClientAuth_LocalCommitReplicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientAuth_LocalCommitReplicates::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;        // entity-script Construct on both worlds + SM setup
    constexpr auto FramesAfterPossess = 30;      // possession replication to the client
    constexpr auto FramesAfterTransition = 40;   // owning-client commit → relay → server → re-publish

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the pawn subject on the server ---------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn>(
                ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of OwningClient pawn returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Possess the pawn with the remote client's PlayerController -----------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Pawn = ck_sm_owningclient_test::Find_PawnSubject(InServer);
            if (Pawn == nullptr)
            { AddError(TEXT("server-side OwningClient pawn not found at possession time")); return; }

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

            auto* ClientPawn = ck_sm_owningclient_test::Find_PawnSubject(Client);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn subject not found — did it replicate?")); return false; }

            const auto LocallyControlled =
                UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ClientPawn);
            TestEqual(TEXT("PRECONDITION: client pawn is locally-controlled-by-player (possession resolved)"),
                static_cast<int32>(LocallyControlled),
                static_cast<int32>(ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled));

            return true;
        }),
        TEXT("ownership precondition — possession resolved on client")));

    // ---- Owning client starts the SM (AutoStart is Disabled for OwningClientAuth) ---------------------------
    // Setup ran during Construct, before possession, so the auto-Start would have been dropped by
    // the single-authority gate. Now that the client is the established owning authority, it starts
    // the SM explicitly, then transitions A→B in a separate action (one frame later) so Start's
    // initial-state entry lands before the transition is evaluated.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = ck_sm_owningclient_test::Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn not found at start time")); return; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine))
            { AddError(TEXT("client-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Start(ClientPawn->_TestStateMachine, {});

            // Pre-warm the owning client's SM relay channel. The push processor that flushes the
            // owning-client batch (FProcessor_Sm_PushOwningClientBatch) acquires the channel on the
            // commit frame and DEFERS if it isn't replicated yet — but its MarkedDirtyBy only
            // re-fires while the batch fragment is dirty, so a first-frame miss can strand the batch.
            // Acquiring here triggers per-connection channel spawn + gives it frames to replicate
            // before the transition's push, so the push's acquire resolves immediately.
            UCk_Utils_StateMachine_UE::Acquire_RelayChannel(ClientPawn->_TestStateMachine);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    // ---- Owning client commits A → B ------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = ck_sm_owningclient_test::Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn not found at transition time")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(ClientPawn->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass(), {});
        })));

    // Wait for actual convergence rather than a fixed frame budget: the owning client commits locally
    // at once, but the relay → server-apply chain can land a few frames later. Push retries every tick
    // (no MarkedDirtyBy) and the rep-driver subtree now constructs reliably (PendingOwnerRetry), so
    // convergence is guaranteed — we just wait for it. The assert below then passes immediately.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { return false; }

            auto* ClientPawn = ck_sm_owningclient_test::Find_PawnSubject(Client);
            auto* ServerPawn = ck_sm_owningclient_test::Find_PawnSubject(Server);
            if (ClientPawn == nullptr || ServerPawn == nullptr)
            { return false; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine) || ck::Is_NOT_Valid(ServerPawn->_TestStateMachine))
            { return false; }

            auto* ExpectedClass = UCk_AutoTest_Sm_RecordingState_B::StaticClass();
            const auto ClientAtB =
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ClientPawn->_TestStateMachine).Get() == ExpectedClass;
            const auto ServerAtB =
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerPawn->_TestStateMachine).Get() == ExpectedClass;
            return ClientAtB && ServerAtB;
        }),
        10.0,
        TEXT("both worlds converge to B (owning-client local commit replicates to server)")));

    // ---- Assertions: both worlds converged to B -------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            const auto ExpectedClass =
                TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_B::StaticClass()};

            // Owning client (authority) committed locally → should be at B.
            auto* ClientPawn = ck_sm_owningclient_test::Find_PawnSubject(Client);
            if (ClientPawn != nullptr && ck::IsValid(ClientPawn->_TestStateMachine))
            {
                TestEqual(TEXT("owning-client SM is at B (local commit)"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ClientPawn->_TestStateMachine).Get(),
                    ExpectedClass.Get());
            }
            else
            { AddError(TEXT("client pawn / _TestStateMachine missing at assertion time")); }

            // Server applied the relayed transition → should also be at B.
            auto* ServerPawn = ck_sm_owningclient_test::Find_PawnSubject(Server);
            if (ServerPawn != nullptr && ck::IsValid(ServerPawn->_TestStateMachine))
            {
                TestEqual(TEXT("server SM applied relayed transition → at B"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerPawn->_TestStateMachine).Get(),
                    ExpectedClass.Get());
            }
            else
            { AddError(TEXT("server pawn / _TestStateMachine missing at assertion time")); }

            return true;
        }),
        TEXT("owning-client local commit replicates to server")));

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
