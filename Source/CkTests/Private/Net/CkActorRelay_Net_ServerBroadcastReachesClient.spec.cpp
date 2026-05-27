// Verifies that ACk_ActorRelay_UE-based actors can multicast from server to all connected
// clients. Multi-PIE: listen-server + 1 client. Server acquires its own probe channel and calls
// Multicast_Ping; assert each PIE world (server and client) observed exactly one Multicast
// receipt with the right value.

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbe.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbeGroup_Subsystem.h"

#include "CkActorRelay/CkActorRelay_Fragment_Data.h"
#include "CkActorRelay/CkActorRelay_GroupSubsystem.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_actorrelay_net_serverbroadcast
{
    constexpr auto kNumPIEClients               = 2;
    constexpr auto kExpectedTotalWorlds         = 2; // listen-server + 1 client (matches kNumPIEClients)
    constexpr auto kReadyTimeoutSeconds         = 60.0f;
    constexpr auto kFramesAfterPIEReady         = 30; // settle channel auto-spawn + replication
    constexpr auto kFramesAfterMulticast        = 30; // give NetMulticast time to propagate
    constexpr auto kProbeValue                  = 42;
    constexpr auto kExpectedReceiveCountPerWorld = 1;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkActorRelayNet_ServerBroadcastReachesClient,
    "Ck.ActorRelay.Net.ServerBroadcastReachesClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkActorRelayNet_ServerBroadcastReachesClient::RunTest(const FString& Parameters)
{
    using namespace ck_actorrelay_net_serverbroadcast;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    ACk_ActorRelay_TestProbe_UE::Reset_Counters();

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(kNumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(kExpectedTotalWorlds, kReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(kFramesAfterPIEReady));

    // Server acquires its own probe channel (the PlayerOwned subsystem also creates a server-side
    // entry) and multicasts. Capture the FCk_ActorRelay_ChannelResult to dispatch via the
    // resolved actor; sync resolution should succeed because PIE is ready and channels spawned.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subsystem = InServer->GetSubsystem<UCk_ActorRelay_TestProbeGroup_Subsystem_UE>();
            if (Subsystem == nullptr)
            { AddError(TEXT("Probe group subsystem missing on server world")); return; }

            auto Pending = Subsystem->Request_AcquireAnyChannel();
            const auto Result = Subsystem->Try_ResolvePending(Pending);
            auto* Probe = Cast<ACk_ActorRelay_TestProbe_UE>(Result.Get_ChannelActor().Get());
            if (Probe == nullptr)
            { AddError(TEXT("Server failed to resolve a probe channel — channels not yet spawned?")); return; }

            Probe->Multicast_Ping(kProbeValue);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(kFramesAfterMulticast));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;

            // Count PIE worlds first — if fewer than expected, the multicast assertion below
            // would silently iterate over a partial set and falsely report success on the
            // worlds that did come up. The harness's WaitForPIEReady logs a warning on timeout
            // but doesn't fail; this check makes the timeout fatal in the assertion phase.
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

            // Walk every PIE world (server + clients) and assert each saw the multicast.
            auto AllGood = true;
            for (const auto& Context : GEngine->GetWorldContexts())
            {
                if (Context.WorldType != EWorldType::PIE)
                { continue; }

                auto* World = Context.World();
                if (World == nullptr)
                { continue; }

                const auto Count = ACk_ActorRelay_TestProbe_UE::Get_MulticastReceiveCount(World);
                const auto Value = ACk_ActorRelay_TestProbe_UE::Get_LastMulticastValue(World);

                const auto Role = World->GetNetMode() == NM_DedicatedServer || World->GetNetMode() == NM_ListenServer
                    ? TEXT("Server")
                    : TEXT("Client");

                if (Count != kExpectedReceiveCountPerWorld)
                {
                    AddError(FString::Printf(
                        TEXT("[%s] expected %d Multicast_Ping receipts, got %d"),
                        Role, kExpectedReceiveCountPerWorld, Count));
                    AllGood = false;
                }

                if (Count > 0 && Value != kProbeValue)
                {
                    AddError(FString::Printf(
                        TEXT("[%s] expected Multicast_Ping value=%d, got %d"),
                        Role, kProbeValue, Value));
                    AllGood = false;
                }
            }
            return AllGood;
        }),
        TEXT("Multicast receipt assertion")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
