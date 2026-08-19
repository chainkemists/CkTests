// T-C6-5 / T-C6-5b / T-C6-5c — the convergence registry's three contracts.
//
//   5   the bounded escape fires and NAMES what it gave up on. Fail-closed is only safe while something eventually
//       opens it: a fact that never converges must not hold the world hostage, and the loss must reach a consumer
//       rather than being a world that quietly came back early.
//   5b  NotApplicable is not a loss. A question that does not arise in this world (physics facts in a world with no
//       physics) must cost nothing — answering Pending there would make every such load burn the convergence cap
//       and report losses it never had, which is what the tri-state exists to prevent.
//   5c  a SKIPPED tick group reports Pending, never Satisfied. The pump's count is the evidence the quiescence
//       predicate reads, and a group that could not be pumped contributes zero passes — identical to a group that
//       ran and found nothing to do. Reading that as quiescent is failing OPEN on the one predicate whose whole
//       job is to say the world has stopped moving.
//
// RED before C6: FCk_LoadConvergenceRegistry, FCtx_LoadConvergence and _ConvergenceUnmet do not exist — there is
// no convergence phase, no escape to bound and no tri-state to get wrong.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.ConvergenceEscapeFiresAndNames
//                              Ck.Snapshot.LoadHold.NotApplicableNeverBecomesALoss
//                              Ck.Snapshot.LoadHold.SkippedTickGroupReportsPending

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Misc/ScopeExit.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Persistence/CkLoadConvergence_Registry.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_convergence
{
    const auto Escape_SlotName        = FName{TEXT("CkSnapshot_LoadHoldConvergenceEscape_GateSlot")};
    const auto NotApplicable_SlotName = FName{TEXT("CkSnapshot_LoadHoldNotApplicable_GateSlot")};
    const auto SteadyState_SlotName   = FName{TEXT("CkSnapshot_LoadHoldSteadyState_GateSlot")};

    // Generous against a steady-state convergence (the stability threshold plus the loop's own quiescent frames,
    // plus room for the physics grant) and far below the shipping 180 — so a load that reverted to waiting for
    // SILENCE reaches this and names the row instead of passing slowly.
    constexpr auto SteadyStateCap = 12;

    const auto SchedulerQuiescentRowName = FName{TEXT("Ecs.SchedulerQuiescent")};

    // Comfortably above a healthy convergence (a handful of granted physics steps plus the two consecutive quiet
    // frames) and far below the shipping 180, so a run that reaches it reached it because a fact never converged
    // rather than because the fence was drawn too tight.
    constexpr auto ShortenedConvergenceCap = 30;

    auto Set_ConvergenceCapOverride(UWorld* InWorld, int32 InFrameCap) -> void
    {
        // GameInstance-scoped, so an override set here survives the load's travel and governs the very load the
        // test is about.
        if (auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(InWorld))
        { Subsystem->TestOnly_Set_ConvergenceFrameCapOverride(InFrameCap); }
    }

    auto Spawn_Probe(UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    }

    auto ProbeReady() -> bool
    {
        auto Elapsed = 0.0;
        return ck_autotest_snapshot_loadhold::TryGet_ProbeTimerElapsedSeconds(
            ck::auto_test::snapshot::Get_PostTravelServerWorld(), Elapsed);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_ConvergenceEscapeFiresAndNames,
    "Ck.Snapshot.LoadHold.ConvergenceEscapeFiresAndNames",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_ConvergenceEscapeFiresAndNames::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_convergence;

    // Reaching the escape is LOUD by design — that is half of what this test pins — so the noise is declared
    // rather than silenced. Occurrences = 0 accepts any count (one Ck error reaches two log sinks).
    AddExpectedError(TEXT("never reported converged within"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    AddExpectedError(TEXT("the load COMPLETED WITH LOSS"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = Escape_SlotName;
    Spec.NumPIEClients = 1;

    // ONE cycle: a load that deliberately gives up on a fact has nothing further to say on a second pass, and a
    // second escape would double the declared error noise for no additional coverage.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Spawn_Probe(InServer);
        Set_ConvergenceCapOverride(InServer, ShortenedConvergenceCap);

        // The row that can never be satisfied. Registered LAST so nothing else in the build is disturbed, and
        // removed unconditionally in the assert below — a Pending-forever row left registered would burn the
        // convergence cap of every load in every later test in this process.
        ck_autotest_snapshot_loadhold::Install_PendingForeverRow();
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return ProbeReady(); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        ON_SCOPE_EXIT { ck_autotest_snapshot_loadhold::Remove_TestConvergenceRows(); };

        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        Subsystem->TestOnly_Set_ConvergenceFrameCapOverride(0);

        const auto Report = Subsystem->Get_LastLoadReport();

        // Positive control: the load really ran. Without it, "the world came back" would be true of a load that
        // never started.
        auto AllGood = TestTrue(TEXT("the probe was restored (the load ran)"), ProbeReady());

        const auto& Unmet = Report.Get_ConvergenceUnmet();

        AllGood &= TestTrue(
            FString::Printf(TEXT("the load report NAMES the convergence facts it gave up on (found %d)"), Unmet.Num()),
            Unmet.Num() >= 1);

        const auto RowName = ck_autotest_snapshot_loadhold::Get_PendingForeverRowName();
        const auto* Record = Unmet.FindByPredicate(
            [&RowName](const FCk_Snapshot_ConvergenceLossRecord& InRecord) -> bool
            { return InRecord.Get_Name() == RowName; });

        AllGood &= TestTrue(
            FString::Printf(TEXT("the never-converging fact [%s] is one of the named entries"), *RowName.ToString()),
            Record != nullptr);

        if (Record != nullptr)
        {
            AllGood &= TestEqual(
                TEXT("...and its record states how long the escape waited before giving up"),
                Record->Get_FramesWaited(), ShortenedConvergenceCap);
        }

        // The escape is a LOSS, so the verdict has to say so — a world handed back early while the report still
        // read Success would leave every consumer branching on a result that contradicts the record beside it.
        AllGood &= TestTrue(TEXT("the load reports that it completed WITH LOSS"),
            Report.Get_Result() == ECk_SnapshotResult::Succeeded_WithLoss);

        // ...and still reads as completed. A world resumed early is recoverable; a world never handed back is not.
        AllGood &= TestTrue(TEXT("...and still reads as completed — the world came back playable"),
            Report.Get_DidLoadComplete());

        AllGood &= TestTrue(TEXT("the world really was handed back"), Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_NotApplicableNeverBecomesALoss,
    "Ck.Snapshot.LoadHold.NotApplicableNeverBecomesALoss",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_NotApplicableNeverBecomesALoss::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_convergence;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = NotApplicable_SlotName;
    Spec.NumPIEClients = 1;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Spawn_Probe(InServer);

        // The tight cap is the instrument: a NotApplicable answer mistaken for Pending would run this load out of
        // frames at 30 and name the row, which is exactly what the assertions below refuse.
        Set_ConvergenceCapOverride(InServer, ShortenedConvergenceCap);

        ck_autotest_snapshot_loadhold::Install_NotApplicableRow();
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return ProbeReady(); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        ON_SCOPE_EXIT { ck_autotest_snapshot_loadhold::Remove_TestConvergenceRows(); };

        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        Subsystem->TestOnly_Set_ConvergenceFrameCapOverride(0);

        auto AllGood = TestTrue(TEXT("the probe was restored (the load ran)"), ProbeReady());

        const auto Report = Subsystem->Get_LastLoadReport();

        AllGood &= TestEqual(
            FString::Printf(TEXT("a NotApplicable fact costs the load NOTHING — no unmet rows (found %d)"),
                Report.Get_ConvergenceUnmet().Num()),
            Report.Get_ConvergenceUnmet().Num(), 0);

        // Success rather than Succeeded_WithLoss: this is what keeps every Jolt-less load's four BB == Success
        // gates green, which is the reason the tri-state exists at all.
        AllGood &= TestTrue(
            TEXT("...and the load reports Success, not Succeeded_WithLoss"),
            Report.Get_Result() == ECk_SnapshotResult::Success);

        AllGood &= TestTrue(TEXT("...and the world was handed back"), Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_SteadyStateCountsAsQuiescent,
    "Ck.Snapshot.LoadHold.SteadyStateCountsAsQuiescent",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_SteadyStateCountsAsQuiescent::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_convergence;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SteadyState_SlotName;
    Spec.NumPIEClients = 1;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Spawn_Probe(InServer);

        // The world under test never falls silent: this probe's processor keeps the pump finding the same amount
        // of work every frame, which is the shape a real content world has (state machines re-evaluating, request
        // queues refilling) and the shape an absolute-silence predicate can never satisfy.
        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldSteadyWork_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});

        // The instrument. A cap this tight cannot be reached by a load that converges on steady state, and IS
        // reached by one waiting for silence — so the assertions below fail loudly rather than slowly.
        Set_ConvergenceCapOverride(InServer, SteadyStateCap);
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return ProbeReady(); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        Subsystem->TestOnly_Set_ConvergenceFrameCapOverride(0);

        auto AllGood = TestTrue(TEXT("the probe was restored (the load ran)"), ProbeReady());

        const auto Report = Subsystem->Get_LastLoadReport();

        // The whole point: a world doing constant work still converges, and does it quickly.
        AllGood &= TestEqual(
            FString::Printf(TEXT("a world in STEADY STATE converges — no unmet facts (found %d)"),
                Report.Get_ConvergenceUnmet().Num()),
            Report.Get_ConvergenceUnmet().Num(), 0);

        AllGood &= TestTrue(
            TEXT("...and reports Success, not Succeeded_WithLoss — steady per-frame traffic is not a loss"),
            Report.Get_Result() == ECk_SnapshotResult::Success);

        AllGood &= TestTrue(TEXT("...and the world was handed back"), Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_SkippedTickGroupReportsPending,
    "Ck.Snapshot.LoadHold.SkippedTickGroupReportsPending",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_SkippedTickGroupReportsPending::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_convergence;

    // Hermetic: a private registry, the real registered predicate, and the context the driver would have written.
    // The quiescence question is a PURE read of what the pump recorded, so the honest way to ask it is to hand it
    // each recorded outcome directly rather than to try to provoke a re-entrant pump in a live world.
    auto World = ck::FEcsWorld{};
    auto& Registry = World.Get_Registry();

    const auto Get_IsQuiescentRowPending = [&Registry]() -> bool
    {
        return ck::FCk_LoadConvergenceRegistry::Get_Pending(Registry).Contains(SchedulerQuiescentRowName);
    };

    // (a) Nothing driven yet. Zero pumps before the phase has run a frame means "not started", never "settled".
    Registry.SetContext<ck::FCtx_LoadConvergence>() = ck::FCtx_LoadConvergence{};
    auto AllGood = TestTrue(
        TEXT("before the convergence phase has driven a frame, the scheduler is PENDING — a pump count of zero on "
             "a phase that has not run is not a quiet world"),
        Get_IsQuiescentRowPending());

    // (b) Driven, quiet, nothing skipped: the only shape that may answer Satisfied.
    {
        auto& Context = Registry.SetContext<ck::FCtx_LoadConvergence>();
        Context._FramesConverging = 1;
        Context._PumpCountLastFrame = 0;
        Context._PumpSkippedGroupsLastFrame = 0;
    }
    AllGood &= TestFalse(
        TEXT("a driven frame that pumped nothing and skipped nothing reports Satisfied"),
        Get_IsQuiescentRowPending());

    // (c) The fail-open case. A tick group that could not be pumped contributes ZERO passes, which reads exactly
    // like a group that ran and found nothing to do — so the skipped count has to veto the verdict.
    {
        auto& Context = Registry.SetContext<ck::FCtx_LoadConvergence>();
        Context._FramesConverging = 1;
        Context._PumpCountLastFrame = 0;
        Context._PumpSkippedGroupsLastFrame = 1;
    }
    AllGood &= TestTrue(
        TEXT("a SKIPPED tick group reports Pending, never Satisfied — a group that never ran contributes zero "
             "passes, and reading that as quiescence is failing open on the one fact that says the world stopped"),
        Get_IsQuiescentRowPending());

    // (d) Work still draining, nothing skipped: pending for the ordinary reason, so (c) is not passing because
    // the predicate simply always says Pending once it has been driven.
    {
        auto& Context = Registry.SetContext<ck::FCtx_LoadConvergence>();
        Context._FramesConverging = 1;
        Context._PumpCountLastFrame = 3;
        Context._PumpSkippedGroupsLastFrame = 0;
    }
    AllGood &= TestTrue(
        TEXT("a frame whose pump still had passes to run reports Pending"),
        Get_IsQuiescentRowPending());

    // (e) STEADY STATE. A content world never goes silent — state machines re-evaluate, request queues refill,
    // and some processors report a pass as work having visited nothing — so a flat non-zero series has to read as
    // converged or the row is unsatisfiable on exactly the worlds it exists for. Below the threshold it is still
    // Pending: one frame of sameness is a coincidence.
    {
        auto& Context = Registry.SetContext<ck::FCtx_LoadConvergence>();
        Context._FramesConverging = 1;
        Context._PumpCountLastFrame = 3;
        Context._PumpSkippedGroupsLastFrame = 0;
        Context._PumpCountStableFrames = ck::kLoad_ConvergenceStableFrames - 1;
    }
    AllGood &= TestTrue(
        TEXT("a steady pump count BELOW the stability threshold is still Pending"),
        Get_IsQuiescentRowPending());

    {
        auto& Context = Registry.SetContext<ck::FCtx_LoadConvergence>();
        Context._PumpCountStableFrames = ck::kLoad_ConvergenceStableFrames;
    }
    AllGood &= TestFalse(
        TEXT("a pump count that has held steady for the full threshold reports Satisfied — the world has stopped "
             "CHANGING, which is what the hold waits for, and is not the same as having gone silent"),
        Get_IsQuiescentRowPending());

    // ...and a skipped group still vetoes it, so steady state cannot launder an unmeasured tick group.
    {
        auto& Context = Registry.SetContext<ck::FCtx_LoadConvergence>();
        Context._PumpSkippedGroupsLastFrame = 1;
    }
    AllGood &= TestTrue(
        TEXT("a SKIPPED tick group still blocks even at a steady pump count"),
        Get_IsQuiescentRowPending());

    return AllGood;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
