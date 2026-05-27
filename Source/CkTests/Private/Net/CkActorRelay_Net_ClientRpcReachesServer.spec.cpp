// Verifies that a client can call a Server_* RPC through its owning relay channel and the
// server actually runs the RPC. Multi-PIE: 1 listen-server + 1 client. Client[0] acquires
// its probe channel and fires Server_Pong; assert the server world observed exactly one
// Server receipt with the right value, and the sending client saw zero (Server RPCs only
// reach the server, not the sender's local world).

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

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
    constexpr auto kFramesAfterPIEReady            = 30;
    constexpr auto kFramesAfterServerRpc           = 30;
    constexpr auto kProbeValue                     = 99;
    constexpr auto kSendingClientIdx               = 0;
    constexpr auto kExpectedServerReceiveCount     = 1;
    constexpr auto kExpectedClientReceiveCount     = 0; // sender does not receive its own Server_ echo
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
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(kFramesAfterPIEReady));

    // Client[0] acquires its own owning channel and fires the Server_ RPC.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(kSendingClientIdx,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Subsystem = InClient->GetSubsystem<UCk_ActorRelay_TestProbeGroup_Subsystem_UE>();
            if (Subsystem == nullptr)
            { AddError(TEXT("Probe group subsystem missing on client world")); return; }

            auto Pending = Subsystem->Request_AcquireAnyChannel();
            const auto Result = Subsystem->Try_ResolvePending(Pending);
            auto* Probe = Cast<ACk_ActorRelay_TestProbe_UE>(Result.Get_ChannelActor().Get());
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
