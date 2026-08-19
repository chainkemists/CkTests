#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h" // CK_IGNORE_PENDING_KILL
#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Persistence/CkLoadConvergence_Registry.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorGroups.h"
#include "CkEcs/Tag/CkTag.h"

#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkAutoTest_Snapshot_LoadHold.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// The load-hold fixture: what a load did to the CLOCKS, and what it had converged, at the exact instant it handed
// the world back.
//
// Every question in this family is asked at one moment — the Promise_OnLoadComplete edge — and every one of them
// is unanswerable a frame later, because the world resumes there and time starts running again. So the sampling
// lives here rather than in each test: a witness arms the promise from OnPreLoad (pre-travel, mid-load) and takes
// ONE reading of game time, wall time, the dilation dial, the accumulator processor's totals and the probe's timer
// the moment the promise fires. The tests then assert against that reading instead of against a world that has
// been running for sixty settle frames by the time an Assert lambda sees it.
//
// The accumulator is a real processor in FGroup_Gameplay — outside the load kernel, and therefore held to zero
// game time for the whole hold while still TICKING. Its tick count is the positive control: an accumulated delta
// of zero is only meaningful if the thing that would have accumulated it actually ran.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // Marks the probe the load-hold handlers and processors act on, so this fixture stays inert in every other
    // test sharing the build.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_LoadHold_Probe);
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // The steady-state fixture. A content world never goes silent during a load — state machines re-evaluate,
    // request queues refill, and processors with a custom DoTick report a pass as work regardless of what they
    // visited — so the convergence rows have to treat "unchanged" as converged. Reproducing that here needs a
    // processor that keeps the pump finding the SAME amount of work every frame, forever.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_LoadHold_SteadyWork);
    CK_DEFINE_ECS_TAG(FTag_AutoTest_LoadHold_SteadyPulse);

    // Custom DoTick on purpose: that is what makes it report a pass as work by contract (the VisitedCount == -1
    // family), and it re-marks its own dirty pulse on the TRANSIENT entity — never on anything the view iterates,
    // so it cannot mutate the storage it is walking.
    class CKTESTS_API FProcessor_AutoTest_LoadHold_SteadyWork : public ck_exp::TProcessor<
        FProcessor_AutoTest_LoadHold_SteadyWork,
        FCk_Handle,
        FTag_AutoTest_LoadHold_SteadyWork,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay;
        using MarkedDirtyBy = FTag_AutoTest_LoadHold_SteadyPulse;

    public:
        using TProcessor::TProcessor;

    public:
        auto
        DoTick(
            TimeType InDeltaT) -> void;

        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };

    // Integrated game time, as the ECS handed it out, for the WORLD rather than for an entity. Registry-scoped on
    // purpose: an entity-scoped counter can only start once the load has respawned that entity and released it
    // from the quarantine, which is the tail of the very window under test.
    struct CKTESTS_API FCtx_AutoTest_LoadHold_TimeAccum
    {
        double _AccumulatedSeconds = 0.0;
        int32  _TickCount = 0;
    };

    // Deliberately NOT RunsDuringLoad: this is the ordinary gameplay-processor case, which is the case the hold is
    // a statement about. Its accumulation lives in a shadowing DoTick so it runs whether or not any entity matches
    // the view — an empty view would otherwise be skipped and the zero would mean "did not run" instead of "ran at
    // zero time", which is the one confusion this fixture exists to rule out.
    class CKTESTS_API FProcessor_AutoTest_LoadHold_TimeAccum : public ck_exp::TProcessor<
        FProcessor_AutoTest_LoadHold_TimeAccum,
        FCk_Handle,
        FTag_AutoTest_LoadHold_Probe,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay;

    public:
        using TProcessor::TProcessor;

    public:
        auto
        DoTick(
            TimeType InDeltaT) -> void;

        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_loadhold
{
    // The probe's timer: CountUp, Running, long enough that nothing terminates it inside a test run. Its elapsed
    // value is the game-time reading a feature actually paces on, as opposed to the raw world clock.
    constexpr auto ProbeTimerDurationSeconds = 600.0;

    // One reading of everything that must not have moved. Taken twice per load: immediately before Request_Load,
    // and inside the promise callback.
    struct CKTESTS_API FLoadHoldSample
    {
        bool   Taken = false;
        double GameTimeSeconds = 0.0;
        double RealTimeSeconds = 0.0;
        float  TimeDilation = 1.0f;
        double AccumulatedSeconds = 0.0;
        int32  AccumTickCount = 0;
        double TimerElapsedSeconds = 0.0;
        bool   TimerResolved = false;
    };

    struct CKTESTS_API FLoadHoldObservations
    {
        // Taken from inside OnPreSave. This is the reading the whole timer question turns on: a load promises the
        // world comes back exactly as it was SAVED, so "did it advance" is measured from the save, never from any
        // point inside the load.
        FLoadHoldSample AtSave;
        // Taken from inside OnPreLoad — the last moment the pre-travel world exists.
        FLoadHoldSample PreLoad;
        // Taken at the global quarantine lift, i.e. the moment the probe's restored values are final. Everything
        // between this and the next reading is the part of the hold a restored feature is alive through.
        FLoadHoldSample AtHydrated;
        FLoadHoldSample AtLoadComplete;

        // What the promise itself reported at the one moment it fired. Read here rather than in the Assert lambda
        // because both of them are true again by then for reasons that have nothing to do with the load.
        int32 FireCount = 0;
        bool  ReadyToResumeAtFire = false;
        bool  LoadInProgressAtFire = false;
        bool  AccountingClosedAtFire = false;
        ECk_SnapshotResult ResultAtFire = ECk_SnapshotResult::Failed_IO;
        int32 ConvergenceUnmetAtFire = 0;

        // Times the probe's Promise_OnHydrated was delivered. Zero means AtHydrated is a default-constructed
        // reading and every delta measured against it is meaningless.
        int32 OnHydratedFireCount = 0;
    };

    CKTESTS_API auto Get_Observations() -> FLoadHoldObservations&;
    CKTESTS_API auto Reset_Observations() -> void;

    // Reads every clock this fixture watches out of InWorld. Resolves the probe by spawn recipe, so it works
    // either side of the load's travel without holding a handle across it.
    CKTESTS_API auto Take_Sample(UWorld* InWorld) -> FLoadHoldSample;

    // The probe's timer, resolved through the probe entity the load respawned.
    CKTESTS_API auto TryGet_ProbeTimerElapsedSeconds(UWorld* InWorld, double& OutElapsedSeconds) -> bool;

    // The two test-only convergence rows. Both are installed by a test and removed by that same test on every
    // exit path: a Pending-forever row left registered would burn the convergence cap of every load in every
    // later test in the shared process.
    CKTESTS_API auto Get_PendingForeverRowName() -> FName;
    CKTESTS_API auto Get_NotApplicableRowName() -> FName;

    CKTESTS_API auto Install_PendingForeverRow() -> void;
    CKTESTS_API auto Install_NotApplicableRow() -> void;
    CKTESTS_API auto Remove_TestConvergenceRows() -> void;
}

// --------------------------------------------------------------------------------------------------------------------

// Carries the steady-work tag, so the world it is restored into never falls silent during the load's convergence
// phase. Persisted like every other probe here, so the traffic exists on BOTH sides of the load.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_LoadHoldSteadyWork_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_LoadHoldSteadyWork_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

// The clock probe: an accumulator fragment and a Running timer, both persisted through the load by the ordinary
// rebuild path.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

    // Binds Promise_OnHydrated so the fixture has a reading at the one moment the restored values are final. The
    // window between that reading and the promise edge is the part of the hold a restored feature lives through.
    auto
    BeginPlay() -> void override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;

private:
    UFUNCTION()
    void
    OnHydrated(
        FCk_Handle InHandle);
};

// --------------------------------------------------------------------------------------------------------------------

// The overlap pair. Two separately-persisted entities whose Construct creates a probe each, positioned so the
// shapes intersect: the framework-only reduction of the G1-D46 shape (a restored NPC standing inside a restored
// store's entrance trigger, and the trigger not knowing it yet).
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_loadhold
{
    // The trigger's probe and the occupant's probe, resolved through their owning entities. The overlap set is
    // keyed on the PROBE entity, not the owner, so both sides have to be resolved this way.
    CKTESTS_API auto TryGet_TriggerProbe(UWorld* InWorld) -> FCk_Handle;
    CKTESTS_API auto TryGet_OccupantProbe(UWorld* InWorld) -> FCk_Handle;

    // Whether the trigger's overlap set names the occupant. This is the whole assertion of T-C6-2, extracted so
    // the sampling witness can evaluate it at the promise edge rather than sixty frames later.
    CKTESTS_API auto Get_TriggerContainsOccupant(UWorld* InWorld) -> bool;
}

// --------------------------------------------------------------------------------------------------------------------

// Arms Promise_OnLoadComplete from the pre-travel world and takes the one reading that matters when it fires.
UCLASS()
class CKTESTS_API UCk_AutoTest_Snapshot_LoadHoldWitness_UE final : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void
    OnPreSave(
        FCk_Handle InHandle);

    UFUNCTION()
    void
    OnPreLoad(
        FCk_Handle InHandle);

    UFUNCTION()
    void
    OnLoadComplete(
        FCk_Handle InHandle,
        FCk_Snapshot_LoadReport InReport);

public:
    // Set by the test when the overlap convergence is the subject, so a run that does not compose the pair does
    // not report a missing overlap as a failure.
    bool _SampleOverlap = false;
    bool _OverlapHeldAtFire = false;

private:
    int32 _ArmCount = 0;
};

// --------------------------------------------------------------------------------------------------------------------
