// Isolation test: when the OWNING CLIENT starts an owning-client-authoritative SM, does the run-status
// (Stopped -> Running) relay to the server so the server SM also reports Running — WITHOUT driving any
// transition?
//
// Why this test exists (bug-hunt + permanent hardening):
//   OwningClientAuth Start buffers a run-status change into FFragment_Sm_PendingClientBatch and flushes
//   it to the server through the SAME relay push path (FProcessor_Sm_PushOwningClientBatch ->
//   ACk_StateMachineRelay_UE::Server_PushRunStatus) that transitions use. There is a documented prior
//   bug where the owning-client run-status was never relayed (Server_PushRunStatus was dead code), so
//   the server SM never went Running and later relayed transitions were dropped. This test pins that
//   relay down permanently and, for the current flake hunt, isolates the *simplest possible
//   client->server SM push* (a run-status change) from the more complex transition push.
//
//   Everything below this layer is already proven solid by sibling tests:
//     - relay channel construction:     Ck.StateMachine.Net.RelayChannelResolvesOnClient (10/10)
//     - cross-machine handle mapping:   Ck.StateMachine.Net.OwningClientHandleResolvesOnServer (10/10)
//   So a failure here points specifically at the owning-client push FLUSH / server APPLY of run-status.
//
// Possesses the pawn (owning-client authority), has the client Request_Start + pre-warm the relay
// channel, then asserts BOTH worlds reach ECk_SmRunStatus::Running. No Request_Transition.
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientStartRelaysRunStatus

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_owningclient_start_runstatus
{
    constexpr auto NumPIEClients       = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn    = 30;
    constexpr auto FramesAfterPossess  = 30;
    constexpr auto RunStatusTimeoutSecs = 10.0;

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
    FCkStateMachineNet_OwningClientStartRelaysRunStatus,
    "Ck.StateMachine.Net.OwningClientStartRelaysRunStatus",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientStartRelaysRunStatus::RunTest(const FString& Parameters)
{
    using namespace ck_sm_owningclient_start_runstatus;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn + possess (owning-client authority) --------------------------------------------------------

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

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Pawn = Find_PawnSubject(InServer);
            if (Pawn == nullptr)
            { AddError(TEXT("server-side pawn not found at possession time")); return; }

            auto* ClientPC = ck::auto_test::net::Get_RemoteClientPlayerController(InServer, 0);
            if (ClientPC == nullptr)
            { AddError(TEXT("could not resolve remote client[0] PlayerController on the server")); return; }

            ClientPC->Possess(Pawn);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterPossess));

    // ---- Gate: wait until the client is the established owning authority BEFORE starting -------------------
    // DoPublishRunStatus only buffers the run-status for the relay when the SM's NetContext resolves to
    // OwningClient (possession-derived). If Start fired before that resolved, the run-status would never
    // be buffered — a test-sequencing artifact, not a product bug. Wait for locally-controlled so Start
    // is issued by the genuine owning authority, mirroring how real game code would gate it.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            { return false; }
            auto* ClientPawn = Find_PawnSubject(Client);
            if (ClientPawn == nullptr)
            { return false; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine))
            { return false; }
            return UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ClientPawn)
                == ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled;
        }),
        RunStatusTimeoutSecs,
        TEXT("client pawn becomes the established owning authority (locally-controlled-by-player) before Start")));

    // ---- Owning client starts the SM + pre-warms the relay channel ----------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientPawn = Find_PawnSubject(InClient);
            if (ClientPawn == nullptr)
            { AddError(TEXT("client-side pawn not found at start time")); return; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine))
            { AddError(TEXT("client-side _TestStateMachine not populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Start(ClientPawn->_TestStateMachine);
            UCk_Utils_StateMachine_UE::Acquire_RelayChannel(ClientPawn->_TestStateMachine);
        })));

    // ---- Poll until BOTH worlds report Running ------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { return false; }

            auto* ClientPawn = Find_PawnSubject(Client);
            auto* ServerPawn = Find_PawnSubject(Server);
            if (ClientPawn == nullptr || ServerPawn == nullptr)
            { return false; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine) || ck::Is_NOT_Valid(ServerPawn->_TestStateMachine))
            { return false; }

            const auto ClientRunning =
                UCk_Utils_StateMachine_UE::Get_RunStatus(ClientPawn->_TestStateMachine) == ECk_SmRunStatus::Running;
            const auto ServerRunning =
                UCk_Utils_StateMachine_UE::Get_RunStatus(ServerPawn->_TestStateMachine) == ECk_SmRunStatus::Running;
            return ClientRunning && ServerRunning;
        }),
        RunStatusTimeoutSecs,
        TEXT("both worlds reach ECk_SmRunStatus::Running (owning-client Start relays run-status to server)")));

    // ---- Definitive assertion -----------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            auto* ClientPawn = Find_PawnSubject(Client);
            auto* ServerPawn = Find_PawnSubject(Server);
            if (ClientPawn == nullptr || ServerPawn == nullptr)
            { AddError(TEXT("client and/or server pawn not found at assertion time")); return false; }
            if (ck::Is_NOT_Valid(ClientPawn->_TestStateMachine) || ck::Is_NOT_Valid(ServerPawn->_TestStateMachine))
            { AddError(TEXT("client and/or server _TestStateMachine not populated")); return false; }

            // Owning client started locally → Running.
            TestEqual(TEXT("owning-client SM is Running (local Start)"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(ClientPawn->_TestStateMachine)),
                static_cast<int32>(ECk_SmRunStatus::Running));

            // Server received the relayed run-status → Running.
            TestEqual(TEXT("server SM is Running (owning-client Start relayed run-status)"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(ServerPawn->_TestStateMachine)),
                static_cast<int32>(ECk_SmRunStatus::Running));

            return true;
        }),
        TEXT("owning-client Start relays run-status to the server")));

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
