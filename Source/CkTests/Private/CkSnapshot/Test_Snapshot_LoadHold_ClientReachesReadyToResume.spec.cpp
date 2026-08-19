// T-C6-12 — a CLIENT reaches ready-to-resume, and does it for the right load.
//
// Request_Load is authority-only and the loader lives on the initiating GameInstance, so a client has no load, no
// report and no completion of its own. On a listen-server reload it nevertheless TRAVELS and REBUILDS alongside
// the server, and its world has to be held for exactly as long as the server's is — otherwise the one machine
// nobody is holding is the one the player is looking at.
//
// The two halves the design splits, and what each is observable by afterwards:
//   arm     the travel URL carries ?CkLoad=<epoch>, readable at the client's OnWorldBeginPlay before anything in
//           its world has ticked. UWorld::URL survives, so the option is still there to be read.
//   release the replicated load-state fact for THIS epoch, on the ActorRelay channel entity, AND that channel's
//           replication-complete signal. If either never arrives the hold escapes at its own frame cap — so a
//           client that came back with the hold OFF and the fact PRESENT released for the designed reason.
//
// The epoch is what makes the fact answerable rather than merely true: a client that travelled for load N must not
// release on a fact load N-1 left standing.
//
// RED before C6: there is no client hold, no ?CkLoad option and no FCk_RepData_SnapshotLoadState — the client
// simulated its own rebuild at full speed while the server held its.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.ClientReachesReadyToResume

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "GameFramework/WorldSettings.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_LoadState.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_client
{
    const auto Client_SlotName = FName{TEXT("CkSnapshot_LoadHoldClient_GateSlot")};

    // The one client the harness's listen-server window brings up.
    constexpr auto ClientIndex = 0;

    auto Get_ClientWorld() -> UWorld*
    {
        return ck::auto_test::net::Get_ClientWorld(ClientIndex);
    }

    // The applied fact, wherever the relay put it. Scanned rather than resolved through the channel because the
    // channel is pooled and shared, and the fragment is the thing the client actually releases on.
    auto TryGet_ClientLoadState(UWorld* InWorld, ck::FFragment_Snapshot_LoadState& OutState) -> bool
    {
        if (InWorld == nullptr)
        { return false; }

        auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs))
        { return false; }

        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr)
        { return false; }

        for (const auto Entity : Raw->view<ck::FFragment_Snapshot_LoadState>())
        {
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            if (ck::Is_NOT_Valid(Handle))
            { continue; }

            OutState = Handle.Get<ck::FFragment_Snapshot_LoadState>();
            return true;
        }

        return false;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_ClientReachesReadyToResume,
    "Ck.Snapshot.LoadHold.ClientReachesReadyToResume",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_Snapshot_LoadHold_ClientReachesReadyToResume::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_client;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = Client_SlotName;

    // Listen server + one client: the whole point is the machine that has no load of its own.
    Spec.NumPIEClients = 2;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto Elapsed = 0.0;
        return ck_autotest_snapshot_loadhold::TryGet_ProbeTimerElapsedSeconds(
            ck::auto_test::snapshot::Get_PostTravelServerWorld(), Elapsed);
    });

    // The client is part of the settle condition, not an afterthought: a client still holding its world has not
    // finished the load, whatever the server thinks.
    Spec.ReloadSettled = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto* Client = Get_ClientWorld();
        if (Client == nullptr || NOT Client->HasBegunPlay())
        { return false; }

        auto* ClientEcs = Client->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        return ck::IsValid(ClientEcs) && ClientEcs->Get_LoadHold() == ECk_EcsWorld_LoadHold::None;
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        auto* Client = Get_ClientWorld();
        if (NOT TestTrue(TEXT("the client world resolves after the reload"), Client != nullptr))
        { return false; }

        const auto ServerEpoch = Subsystem->Get_LoadEpoch();
        auto AllGood = TestTrue(
            FString::Printf(TEXT("the server ran a load (epoch %d)"), ServerEpoch),
            ServerEpoch > 0);

        // The epoch carries a session-unique salt in its high bits, and this is where that is observable end to
        // end rather than only in the composition's own unit test: a bare per-instance load COUNT fits in the
        // low 16 bits, so a value above them is the salt actually riding the wire. It is the difference between
        // "load number one" and "THIS load" — a client that has itself hosted one load must not read a host's
        // first load as its own and decline to arm.
        constexpr auto HighestUnsaltedEpoch = 0xFFFF;
        AllGood &= TestTrue(
            FString::Printf(TEXT("...and its epoch identifies the LOAD rather than its ordinal (epoch %d)"),
                ServerEpoch),
            ServerEpoch > HighestUnsaltedEpoch);

        // ---- ARM: the option rode the travel and is still readable on the client's own world. ------------------
        AllGood &= TestTrue(
            TEXT("the client's world URL carries ?CkLoad — the arm signal a client can read at world begin play, "
                 "before anything in its world has ticked"),
            Client->URL.HasOption(TEXT("CkLoad")));

        const auto OptionValue = Client->URL.GetOption(TEXT("CkLoad="), nullptr);
        AllGood &= TestEqual(
            FString::Printf(TEXT("...naming the epoch the SERVER is running (URL said [%s])"), OptionValue),
            FCString::Atoi(OptionValue), ServerEpoch);

        // ---- RELEASE: the fact arrived, for this epoch, and the hold came off. ---------------------------------
        auto LoadState = ck::FFragment_Snapshot_LoadState{};
        const auto HasLoadState = TryGet_ClientLoadState(Client, LoadState);

        AllGood &= TestTrue(
            TEXT("the replicated load-state fact reached the client on the relay channel — without it the client "
                 "could only ever release through its bounded escape"),
            HasLoadState);

        if (HasLoadState)
        {
            AllGood &= TestTrue(TEXT("...saying ready-to-resume"), LoadState.Get_ReadyToResume());
            AllGood &= TestEqual(
                TEXT("...for THIS load's epoch, not one a previous load left standing"),
                LoadState.Get_LoadEpoch(), ServerEpoch);
        }

        auto* ClientEcs = Client->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (NOT TestTrue(TEXT("the client's ECS world subsystem is present"), ck::IsValid(ClientEcs)))
        { return false; }

        AllGood &= TestTrue(TEXT("the client's hold is released"),
            ClientEcs->Get_LoadHold() == ECk_EcsWorld_LoadHold::None);

        // ...and released for the DESIGNED reason. Every assertion above is equally true of a client that gave up
        // at its 600-frame cap and then received the fact afterwards — the hold is off either way, the dilation is
        // back either way, and the fact is present either way. Without this the test would report the bounded
        // escape as a working client contract, which is the one outcome it exists to rule out.
        // Read off the CLIENT's own subsystem: each PIE instance has its own GameInstance, and the client hold
        // lives on the one that armed it. Note the client never ACQUIRES a relay channel of its own: the pool is
        // per side, so the entity it would acquire is not the one the server's fact replicates onto — it
        // recognises the fact wherever it lands instead, which is what makes this assertion meaningful.
        auto* ClientSubsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Client);
        if (NOT TestTrue(TEXT("the client has its own snapshot subsystem"), ClientSubsystem != nullptr))
        { return false; }

        AllGood &= TestFalse(
            TEXT("the client released because the fact arrived, NOT because its bounded escape fired"),
            ClientSubsystem->TestOnly_Get_ClientHoldReleasedByCap());

        // The dilation owner is the server and the value is replicated, so the client's own clock coming back is
        // the observable half of the freeze reaching it at all.
        const auto* ClientSettings = Client->GetWorldSettings();
        if (NOT TestTrue(TEXT("the client world has world settings"), ClientSettings != nullptr))
        { return false; }

        AllGood &= TestEqual(
            TEXT("the client's global time dilation is back to normal once its hold released"),
            static_cast<double>(ClientSettings->GetEffectiveTimeDilation()), 1.0, 1.0e-3);

        // And the server side of the same load agrees, so a green client cannot come from a load that never ran.
        AllGood &= TestTrue(TEXT("the server reached ready-to-resume too"), Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
