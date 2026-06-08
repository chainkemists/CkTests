// Isolation test: for an owning-client-authoritative SM entity on a possessed pawn, does the client's
// SM entity HANDLE resolve to a valid server-side handle (cross-machine), without ever starting the
// SM or driving a transition?
//
// Why this test exists (bug-hunt + permanent hardening):
//   The owning client pushes transitions to the server via ACk_StateMachineRelay_UE::Server_Push*,
//   which carry the SM entity's FCk_Handle. The server resolves that handle to its own copy of the
//   entity via the entity's ReplicationDriver before applying. If that cross-machine resolution
//   doesn't hold, the relayed transition lands on nothing and the server SM never advances — the
//   exact failure the flaky OwningClientAuth tests show ("server SM ... not equal").
//
//   The relay CHANNEL itself is already proven reliable (Ck.StateMachine.Net.RelayChannelResolvesOnClient,
//   Ck.ActorRelay.Net.ClientRpcReachesServer). This test isolates the next link in the chain: the
//   cross-machine HANDLE mapping for the possessed-pawn SM entity. It does possession (so the owning
//   client is the authority) but NO Request_Start and NO Request_Transition — purely "is the entity
//   replicated + resolvable across worlds".
//
// If this flakes, the bug is the SM entity's cross-machine replication/handle mapping (the
// possessed-WithActor-entity replication handshake) — i.e. the relayed handle can't be resolved on the
// server. If it is rock-solid, the handle mapping is fine and the flake lives in the push-fire / apply
// / replay logic on top, which the final isolation test should target.
//
// Surface in Session Frontend: Ck.StateMachine.Net.OwningClientHandleResolvesOnServer

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "EngineUtils.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_owningclient_handle_resolve
{
    constexpr auto NumPIEClients       = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn    = 30;
    constexpr auto FramesAfterPossess  = 30;
    constexpr auto ResolveTimeoutSecs  = 10.0;

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
    FCkStateMachineNet_OwningClientHandleResolvesOnServer,
    "Ck.StateMachine.Net.OwningClientHandleResolvesOnServer",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_OwningClientHandleResolvesOnServer::RunTest(const FString& Parameters)
{
    using namespace ck_sm_owningclient_handle_resolve;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the owning-client pawn on the server --------------------------------------------------------

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

    // ---- Possess with the remote client's PlayerController -------------------------------------------------

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

    // ---- Poll until the client's SM handle resolves on the server -----------------------------------------
    // This is the cross-machine mapping the relay push depends on: the client pushes its SM handle, the
    // server must resolve it to its own entity. We wait (rather than asserting at a fixed frame) so a
    // clean pass only requires that the mapping holds *eventually*; a timeout is the isolated repro.

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

            // Possession must have resolved on the client (owning-client authority established).
            if (UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer(ClientPawn)
                != ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled)
            { return false; }

            // The client's SM entity must carry a replication driver and resolve to a valid handle on
            // the server world — exactly what the relay's Server_Push* needs to apply the transition.
            const auto ClientSmHandle = FCk_Handle{ClientPawn->_TestStateMachine};
            if (NOT UCk_Utils_EntityReplicationDriver_UE::Has(ClientSmHandle))
            { return false; }

            const auto ResolvedOnServer =
                UCk_Utils_EntityReplicationDriver_UE::Get_ReplicatedHandleForWorld(ClientSmHandle, Client, Server);
            return ck::IsValid(ResolvedOnServer);
        }),
        ResolveTimeoutSecs,
        TEXT("client SM handle resolves to a valid server-side handle (cross-machine mapping)")));

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
            { AddError(TEXT("client and/or server _TestStateMachine not populated by entity-script Construct")); return false; }

            const auto ClientSmHandle = FCk_Handle{ClientPawn->_TestStateMachine};
            if (NOT UCk_Utils_EntityReplicationDriver_UE::Has(ClientSmHandle))
            {
                AddError(TEXT("client SM entity has no ReplicationDriver — it is not set up for cross-machine relay"));
                return false;
            }

            const auto ResolvedOnServer =
                UCk_Utils_EntityReplicationDriver_UE::Get_ReplicatedHandleForWorld(ClientSmHandle, Client, Server);
            if (ck::Is_NOT_Valid(ResolvedOnServer))
            {
                AddError(TEXT("client SM handle did NOT resolve to a valid server-side handle — the relay push "
                              "would land on nothing and the server SM would never advance"));
                return false;
            }

            return true;
        }),
        TEXT("owning-client SM handle resolves cross-machine to the server")));

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
