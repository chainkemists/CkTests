// Verifies that a client can call a Server_* RPC through its owning relay channel and the
// server actually runs the RPC. Multi-PIE: 1 listen-server + 1 client. Client[0] acquires
// its probe channel and fires Server_Pong; assert the server world observed exactly one
// Server receipt with the right value, and the sending client saw zero (Server RPCs only
// reach the server, not the sender's local world).

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbe.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbeGroup_Subsystem.h"

#include "CkActorRelay/CkActorRelay_Fragment_Data.h"
#include "CkActorRelay/CkActorRelay_GroupSubsystem.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_actorrelay_net_clientrpc
{
    constexpr auto kNumPIEClients                  = 2;
    constexpr auto kExpectedTotalWorlds            = 2; // listen-server + 1 client
    constexpr auto kReadyTimeoutSeconds            = 60.0f;
    constexpr auto kResolveTimeoutSeconds          = 10.0;
    constexpr auto kFramesAfterServerRpc           = 30;
    constexpr auto kProbeValue                     = 99;
    constexpr auto kSendingClientIdx               = 0;
    constexpr auto kExpectedServerReceiveCount     = 1;
    constexpr auto kExpectedClientReceiveCount     = 0; // sender does not receive its own Server_ echo

    // Resolves the channel OWNED by this client's local player. Server_* RPCs are only routed
    // for actors owned by the calling client's connection — Request_AcquireAnyChannel can hand
    // back ANOTHER player's channel (a SimulatedProxy on this client), on which UE silently
    // drops the RPC. Same trap UCk_Utils_StateMachine_UE::Acquire_RelayChannel documents.
    auto Resolve_OwningProbe(UWorld* InClient) -> ACk_ActorRelay_TestProbe_UE*
    {
        if (InClient == nullptr)
        { return nullptr; }

        auto* Subsystem = InClient->GetSubsystem<UCk_ActorRelay_TestProbeGroup_Subsystem_UE>();
        if (Subsystem == nullptr)
        { return nullptr; }

        auto* PlayerController = InClient->GetFirstPlayerController();
        auto* PlayerState = PlayerController != nullptr ? PlayerController->PlayerState.Get() : nullptr;
        if (PlayerState == nullptr)
        { return nullptr; }

        auto Pending = Subsystem->Request_AcquireChannel_ForPlayer(PlayerState);
        const auto Result = Subsystem->Try_ResolvePending(Pending);
        return Cast<ACk_ActorRelay_TestProbe_UE>(Result.Get_ChannelActor().Get());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkActorRelayNet_ClientRpcReachesServer,
    "Ck.ActorRelay.Net.ClientRpcReachesServer",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkActorRelayNet_ClientRpcReachesServer::RunTest(const FString& Parameters)
{
    using namespace ck_actorrelay_net_clientrpc;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    ACk_ActorRelay_TestProbe_UE::Reset_Counters();

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(kNumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(kExpectedTotalWorlds, kReadyTimeoutSeconds));

    // Wait until the client's OWNING channel has replicated, registered with the client's group
    // subsystem, and become ECS-ready — replication has no fixed-frame guarantee, so a fixed
    // tick budget here is a race, not a contract.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return Resolve_OwningProbe(ck::auto_test::net::Get_ClientWorld(kSendingClientIdx)) != nullptr;
        }),
        kResolveTimeoutSeconds,
        TEXT("client resolves its owning probe channel")));

    // Client[0] acquires its own owning channel and fires the Server_ RPC.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(kSendingClientIdx,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Probe = Resolve_OwningProbe(InClient);
            if (Probe == nullptr)
            { AddError(TEXT("Client failed to resolve its owning probe channel")); return; }

            Probe->Server_Pong(kProbeValue);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(kFramesAfterServerRpc));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;

            // Verify the expected number of PIE worlds came up. Catches the case where the
            // PIE-ready latent's timeout was hit and fewer worlds than designed are present —
            // which would let the per-world assertion silently report success on a partial set.
            auto PIEWorldCount = 0;
            for (const auto& Context : GEngine->GetWorldContexts())
            {
                if (Context.WorldType == EWorldType::PIE && Context.World() != nullptr)
                { ++PIEWorldCount; }
            }
            if (PIEWorldCount != kExpectedTotalWorlds)
            {
                AddError(FString::Printf(
                    TEXT("expected %d PIE worlds (listen-server + 1 client), got %d — PIE startup likely timed out"),
                    kExpectedTotalWorlds, PIEWorldCount));
                return false;
            }

            auto AllGood = true;
            for (const auto& Context : GEngine->GetWorldContexts())
            {
                if (Context.WorldType != EWorldType::PIE)
                { continue; }

                auto* World = Context.World();
                if (World == nullptr)
                { continue; }

                const auto IsServer = World->GetNetMode() == NM_DedicatedServer
                                   || World->GetNetMode() == NM_ListenServer;

                const auto Count = ACk_ActorRelay_TestProbe_UE::Get_ServerReceiveCount(World);
                const auto Expected = IsServer ? kExpectedServerReceiveCount : kExpectedClientReceiveCount;
                const auto Role = IsServer ? TEXT("Server") : TEXT("Client");

                if (Count != Expected)
                {
                    AddError(FString::Printf(
                        TEXT("[%s] expected %d Server_Pong receipts, got %d"),
                        Role, Expected, Count));
                    AllGood = false;
                }

                if (IsServer && Count > 0)
                {
                    const auto Value = ACk_ActorRelay_TestProbe_UE::Get_LastServerValue(World);
                    if (Value != kProbeValue)
                    {
                        AddError(FString::Printf(
                            TEXT("[Server] expected Server_Pong value=%d, got %d"),
                            kProbeValue, Value));
                        AllGood = false;
                    }
                }
            }
            return AllGood;
        }),
        TEXT("Server-side Pong receipt assertion")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
