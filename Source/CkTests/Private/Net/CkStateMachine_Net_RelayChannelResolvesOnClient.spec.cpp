// Isolation test: does the StateMachineRelay group's PlayerOwned channel reliably construct on the
// server and register/resolve on the CLIENT?
//
// Why this test exists (bug-hunt + permanent hardening):
//   The OwningClientAuth SM net tests flake because the owning client's transition never reaches the
//   server. The push processor (FProcessor_Sm_PushOwningClientBatch) flushes via
//   UCk_Utils_StateMachine_UE::Acquire_RelayChannel, which calls
//   UCk_StateMachineRelay_Subsystem_UE::Request_AcquireAnyChannel + Try_ResolvePending. If that
//   channel never resolves on the client, the push defers forever and the server SM never advances.
//   The generic ActorRelay probe (Ck.ActorRelay.Net.ClientRpcReachesServer) proves the *pooled
//   PlayerOwned channel + client->server RPC* path is solid for the probe group — this test asks the
//   same question for the *StateMachineRelay* group specifically, with NO state machine, NO pawn,
//   NO possession and NO transition. It isolates "does the SM relay channel construct + replicate +
//   register on the client" from everything the SM layers on top.
//
// If this flakes while the probe test is 100% green, the divergence is in the StateMachineRelay group
// subsystem's per-client channel construction — exactly the suspected fault. If it is rock-solid, the
// SM flake lives one layer up (entity-script/pawn replication or the transition/replay path) and the
// next isolation test should target that.
//
// Surface in Session Frontend: Ck.StateMachine.Net.RelayChannelResolvesOnClient

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkActorRelay/CkActorRelay_Fragment_Data.h"
#include "CkActorRelay/CkActorRelay_GroupSubsystem.h"

#include "CkStateMachine/Net/CkStateMachineRelay_Actor.h"
#include "CkStateMachine/Net/CkStateMachineRelay_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_relay_channel_resolves
{
    constexpr auto NumPIEClients       = 2; // listen-server + 1 client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto ResolveTimeoutSecs  = 10.0; // generous: distinguishes "never resolves" (bug) from slow startup

    // Resolves the StateMachineRelay group's channel for the given world via the exact API the SM push
    // path uses (Request_AcquireAnyChannel + Try_ResolvePending). Returns the channel actor or nullptr.
    auto Resolve_RelayChannelActor(UWorld* InWorld) -> ACk_StateMachineRelay_UE*
    {
        if (InWorld == nullptr)
        { return nullptr; }

        auto* Subsystem = InWorld->GetSubsystem<UCk_StateMachineRelay_Subsystem_UE>();
        if (Subsystem == nullptr)
        { return nullptr; }

        auto Pending = Subsystem->Request_AcquireAnyChannel();
        const auto Result = Subsystem->Try_ResolvePending(Pending);
        return Cast<ACk_StateMachineRelay_UE>(Result.Get_ChannelActor().Get());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_RelayChannelResolvesOnClient,
    "Ck.StateMachine.Net.RelayChannelResolvesOnClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_RelayChannelResolvesOnClient::RunTest(const FString& Parameters)
{
    using namespace ck_sm_relay_channel_resolves;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Poll until BOTH the server and the client can resolve a StateMachineRelay channel. The channels
    // spawn server-side at PostLogin and must replicate + re-register with the client's group
    // subsystem; we wait (rather than asserting at a fixed frame) so a clean pass only requires that
    // the channel resolves *eventually*. A timeout here is the isolated repro of the flake.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { return false; }

            const auto ServerOk = Resolve_RelayChannelActor(Server) != nullptr;
            const auto ClientOk = Resolve_RelayChannelActor(Client) != nullptr;
            return ServerOk && ClientOk;
        }),
        ResolveTimeoutSecs,
        TEXT("StateMachineRelay channel resolves on BOTH server and client")));

    // Definitive, per-world assertion (passes immediately once the wait above converges; on timeout it
    // records exactly which world failed to resolve its channel).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            { AddError(TEXT("server and/or client world unavailable at assertion time")); return false; }

            auto AllGood = true;

            if (Resolve_RelayChannelActor(Server) == nullptr)
            {
                AddError(TEXT("[Server] failed to resolve a StateMachineRelay channel"));
                AllGood = false;
            }

            if (Resolve_RelayChannelActor(Client) == nullptr)
            {
                AddError(TEXT("[Client] failed to resolve a StateMachineRelay channel — the SM relay never "
                              "constructed/registered on the client (the owning-client push would defer forever)"));
                AllGood = false;
            }

            return AllGood;
        }),
        TEXT("StateMachineRelay channel resolved on both worlds")));

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
