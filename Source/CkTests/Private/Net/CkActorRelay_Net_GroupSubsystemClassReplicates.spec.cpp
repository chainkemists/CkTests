// Verifies that the relay actor's _GroupSubsystemClass UPROPERTY replicates from server to
// client and OnRep wires the client side into the correct group subsystem. We can't read the
// private _GroupSubsystem TWeakObjectPtr directly, but we can prove the wiring works
// indirectly: count replicated probe actors visible on the client (must be >= 1, via
// TActorIterator) AND assert the subsystem's Get_ChannelCount_Active >= 1 (which requires
// OnRep_GroupSubsystemClass to have fired and registered the probe with the subsystem).

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbe.h"
#include "CkTests/Net/Probes/CkActorRelay_TestProbeGroup_Subsystem.h"

#include "CkActorRelay/CkActorRelay_GroupSubsystem.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_actorrelay_net_grouprep
{
    constexpr auto kNumPIEClients               = 2;
    constexpr auto kExpectedTotalWorlds         = 2; // listen-server + 1 client
    constexpr auto kReadyTimeoutSeconds         = 60.0f;
    constexpr auto kFramesAfterPIEReady         = 30;
    constexpr auto kMinExpectedReplicatedProbes = 1; // each client sees >= 1 probe replicated from server
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkActorRelayNet_GroupSubsystemClassReplicates,
    "Ck.ActorRelay.Net.GroupSubsystemClassReplicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkActorRelayNet_GroupSubsystemClassReplicates::RunTest(const FString& Parameters)
{
    using namespace ck_actorrelay_net_grouprep;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    ACk_ActorRelay_TestProbe_UE::Reset_Counters();

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(kNumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(kExpectedTotalWorlds, kReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(kFramesAfterPIEReady));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;

            // Verify the expected number of PIE worlds came up before walking them.
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

                const auto IsClient = World->GetNetMode() == NM_Client;
                if (NOT IsClient)
                { continue; }

                // Count replicated probe actors visible on this client.
                auto ProbeCount = 0;
                for (TActorIterator<ACk_ActorRelay_TestProbe_UE> It(World); It; ++It)
                { ++ProbeCount; }

                if (ProbeCount < kMinExpectedReplicatedProbes)
                {
                    AddError(FString::Printf(
                        TEXT("[Client] expected >=%d replicated probe actors, got %d"),
                        kMinExpectedReplicatedProbes, ProbeCount));
                    AllGood = false;
                    continue;
                }

                // Each probe on the client must have replicated _GroupSubsystemClass set to the
                // expected subclass. If OnRep_GroupSubsystemClass hadn't fired with the right
                // value, the probe wouldn't have registered with its subsystem and the
                // subsystem's ChannelCount_Active accessor would be 0.
                auto* Subsystem = World->GetSubsystem<UCk_ActorRelay_TestProbeGroup_Subsystem_UE>();
                if (Subsystem == nullptr)
                {
                    AddError(TEXT("[Client] probe group subsystem missing on client world"));
                    AllGood = false;
                    continue;
                }

                const auto ActiveCount = Subsystem->Get_ChannelCount_Active();
                if (ActiveCount < kMinExpectedReplicatedProbes)
                {
                    AddError(FString::Printf(
                        TEXT("[Client] expected >=%d active channels (OnRep wired probes into subsystem), got %d"),
                        kMinExpectedReplicatedProbes, ActiveCount));
                    AllGood = false;
                }
            }
            return AllGood;
        }),
        TEXT("Client-side probe registration via OnRep assertion")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
