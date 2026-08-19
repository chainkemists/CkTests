#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h" // CK_IGNORE_PENDING_KILL / CK_IF_END_PLAY
#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkParallelProcessor.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorGroups.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h" // FCk_Snapshot_Session
#include "CkEcs/Tag/CkTag.h"
#include "CkEcs/Tag/CkTag_HydrationQuarantine.h"

#include "CkAutoTest_Snapshot_Ordering.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Ordering fixture: probes that make "construct -> hydrate -> setup/live" observable.
//
// The load holds every restored entity out of every non-kernel processor's view until its payloads have applied.
// That is invisible from the outside, so the probes below record what they saw and WHEN: each observer notes
// whether it was handed the probe while the load still held it, and the probe's Setup notes how many times it ran
// and which value it read. A design that lets a processor peek at a half-hydrated entity shows up here as a
// non-zero count; one that runs Setup before hydration shows up as Setup reading the construct default.
//
// Three observers, one per admission surface that builds a VIEW: ck::TProcessor, ck_exp::TProcessor and
// TParallelProcessor. The fourth surface — the AngelScript script-query join, hand-rolled over the storages
// rather than built through a view — is fenced at source level by Ck.Snapshot.Meta.NoProcessorBypassesQuarantine
// instead of observed here.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // Marks the entity the ordering handlers produce a payload for, so they stay inert in every other test sharing
    // this build.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_Probe);

    // The SECOND probe of the cross-entity pair. Its payload stalls, so its sibling's Setup can only read a
    // hydrated value if the release really was set-wide.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_ProbeB);

    // Session setup marker, stamped at composition and consumed by the probe's Setup — the shape every Ck feature
    // uses, and the thing a registry-wide Clear would otherwise destroy while the load holds the entity.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_NeedsSetup);

    // The same pair again for the marker-clear probe, kept separate so its every-tick registry-wide wipe cannot
    // reach the other tests' probes.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_ClearProbe);
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_ClearProbe_NeedsSetup);

    // The probe destroyed from inside its own hydration.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_DestroyProbe);

    // The handle-rich subtree's owner.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_HandleGraph_Probe);

    // Stamped by that probe's own hydration, immediately before it asks to be destroyed, and required by the
    // EndPlay witness. Without it the witness would also fire for the ordinary teardown of the pre-save world
    // during the load's map travel — which is a different event that looks identical from the outside.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Ordering_DestroyedDuringHydration);
}

// --------------------------------------------------------------------------------------------------------------------

// Durable payloads. Two of them for the same entity, so "no processor sees a HALF-hydrated entity" has a half to
// see: the second one stalls for a few passes while the first has already applied.
USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_OrderingA
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_OrderingA);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_OrderingB
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_OrderingB);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_OrderingClearProbe
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_OrderingClearProbe);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_OrderingDestroy
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_OrderingDestroy);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // The probe's restored state. Plain (unregistered) fragments are never captured, so what persists is the
    // payload above and the values below are whatever the handlers wrote.
    struct CKTESTS_API FFragment_AutoTest_Ordering_State
    {
    public:
        CK_GENERATED_BODY(FFragment_AutoTest_Ordering_State);

    public:
        int32 _ValueA = 0;
        int32 _ValueB = 0;
    };

    // Setup's own record, composed fresh every construction — so post-load it counts the LOAD's Setup runs and
    // nothing earlier.
    struct CKTESTS_API FFragment_AutoTest_Ordering_SetupLog
    {
    public:
        CK_GENERATED_BODY(FFragment_AutoTest_Ordering_SetupLog);

    public:
        int32 _RunCount = 0;
        int32 _ObservedA = 0;
        int32 _ObservedSiblingB = 0;
        bool  _SiblingWasResolvable = false;
    };

    // A request enqueued during Construct. The marker-clear probe carries it to prove point 3 of the Clear
    // contract for the harder case: a registry-wide wipe of a REQUEST fragment destroys queued work outright
    // rather than merely deferring a pass.
    struct CKTESTS_API FFragment_AutoTest_Ordering_ClearProbe_Requests
    {
    public:
        CK_GENERATED_BODY(FFragment_AutoTest_Ordering_ClearProbe_Requests);

    public:
        int32 _PendingCount = 0;
        int32 _DrainedCount = 0;
    };
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_ordering
{
    constexpr auto SavedValueA          = 4211;
    constexpr auto SavedValueB          = 8422;
    constexpr auto SavedValueClearProbe = 1337;
    constexpr auto SavedValueDestroy    = 909;

    // The physics/fog probe. Starting values come from the feature params at Add; the saved values are what
    // a mutation writes before the save, so "the restored value survived Setup" is the difference between them.
    const auto StartingVelocity = FVector{1.0, 0.0, 0.0};
    const auto SavedVelocity    = FVector{3.0, 4.0, 5.0};

    // The LOCAL-coordinate probe. Its saved values are deliberately EQUAL to its starting params: that is the
    // one case a "has the value moved off the seed?" test cannot distinguish from an untouched construct seed,
    // so it is the case that decides whether the conversion debt is tracked or guessed at. Under the 90-degree
    // yaw below, a second conversion is loudly visible — {1,0,0} becomes {0,1,0} rather than staying put.
    const auto LocalProbeYaw                 = 90.0;
    const auto LocalProbeStartingVelocity    = FVector{1.0, 0.0, 0.0};
    const auto LocalProbeStartingAcceleration = FVector{2.0, 0.0, 0.0};

    constexpr auto FogCellSize      = 500.0f;
    constexpr auto FogHalfExtent    = 2000.0;

    // How many passes the B payload refuses to apply for, so the half-hydrated window is real rather than
    // theoretical. Well under the apply timeout.
    constexpr auto StallPasses = 3;

    struct CKTESTS_API FObservations
    {
        // Times an observer's view yielded an entity the load was still holding. The whole point: 0.
        int32 SawHeldProbe_Ck       = 0;
        int32 SawHeldProbe_CkExp    = 0;
        int32 SawHeldProbe_Parallel = 0;

        // Positive controls: an observer that never ran at all would report zero above for the wrong reason.
        int32 SawReleasedProbe_Ck       = 0;
        int32 SawReleasedProbe_CkExp    = 0;
        int32 SawReleasedProbe_Parallel = 0;

        // Passes the B payload refused to apply on. Zero means the half-hydrated window never existed and every
        // count above is vacuous.
        int32 StallReturns = 0;

        // Recorded here rather than on the entity: the fragment holding it is the one the marker-clear probe's
        // sibling wipes registry-wide, so a count parked on the entity would vanish with the evidence.
        int32 ClearProbe_RequestsDrained = 0;

        bool DestroyProbe_EndPlayRan = false;

        // What DoBeginPlay was handed. The contract says the construct default, so a restored value showing up
        // here means something started holding BeginPlay for the load.
        bool  BeginPlayRan      = false;
        int32 BeginPlayObservedA = 0;

        // The Promise_OnHydrated bound from that same DoBeginPlay: the other half of the contract. Fired once,
        // with the RESTORED value, and with the stalling sibling's value already applied too — that last part
        // is what makes it an edge about the whole mapped set rather than about one entity.
        int32 OnHydratedFireCount        = 0;
        int32 OnHydratedObservedA        = 0;
        int32 OnHydratedObservedSiblingB = 0;
        bool  OnHydratedSiblingResolved  = false;

        // A bind made AFTER the lift, and one made on an entity no load ever mapped. Both must fire, because
        // "nothing is pending" is an answer, not a reason to stay silent.
        int32 LateBindFireCount   = 0;
        int32 LateBindObservedA   = 0;
        int32 FreshBindFireCount  = 0;

        // The handle-graph probe's Construct-created child, recorded on BOTH sides of the load. The load must
        // produce a DIFFERENT entity id: a Session handle that survives with the SAME id is a saved value that
        // got remapped, which is the aliasing case a validity check alone reports as healthy.
        int32 HandleGraph_PreSaveChildId  = 0;
        int32 HandleGraph_PostLoadChildId = 0;
    };

    CKTESTS_API auto Get_Observations() -> FObservations&;
    CKTESTS_API auto Reset_Observations() -> void;

    // Records one observation against the entity an observer's view just yielded. Templated because the parallel
    // observer is handed a read-only handle: the two share no base, only the Has<> the check needs.
    template <typename T_Handle>
    auto Record_Observation(
        const T_Handle& InHandle,
        int32& InOutHeld,
        int32& InOutReleased) -> void
    {
        if (InHandle.template Has<ck::FTag_Hydration_Quarantine>())
        { ++InOutHeld; }
        else
        { ++InOutReleased; }
    }
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // Observer on the plain generated view. Records rather than acts — the fixture must not perturb what it
    // measures.
    class CKTESTS_API FProcessor_AutoTest_Ordering_Observer_Ck : public TProcessor<
        FProcessor_AutoTest_Ordering_Observer_Ck,
        FTag_AutoTest_Ordering_Probe,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;

    public:
        using TProcessor::TProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };

    class CKTESTS_API FProcessor_AutoTest_Ordering_Observer_CkExp : public ck_exp::TProcessor<
        FProcessor_AutoTest_Ordering_Observer_CkExp,
        FCk_Handle,
        FTag_AutoTest_Ordering_Probe,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;

    public:
        using TProcessor::TProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };

    class CKTESTS_API FProcessor_AutoTest_Ordering_Observer_Parallel : public TParallelProcessor<
        FProcessor_AutoTest_Ordering_Observer_Parallel,
        FCk_Handle,
        FTag_AutoTest_Ordering_Probe,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;

    public:
        using TParallelProcessor::TParallelProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };

    // --------------------------------------------------------------------------------------------------------------------

    // The probe's Setup: consumes the marker, records how many times it ran and what it read. Under the ordering
    // contract that is exactly once, reading the RESTORED value.
    class CKTESTS_API FProcessor_AutoTest_Ordering_Setup : public ck_exp::TProcessor<
        FProcessor_AutoTest_Ordering_Setup,
        FCk_Handle,
        TReadOnly<FFragment_AutoTest_Ordering_State>,
        TReadWrite<FFragment_AutoTest_Ordering_SetupLog>,
        FTag_AutoTest_Ordering_NeedsSetup,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;
        using MarkedDirtyBy = FTag_AutoTest_Ordering_NeedsSetup;

    public:
        using TProcessor::TProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle,
            const FFragment_AutoTest_Ordering_State& InState,
            FFragment_AutoTest_Ordering_SetupLog& InLog) -> void;
    };

    // --------------------------------------------------------------------------------------------------------------------

    // The marker-clear probe's Setup, and the every-tick registry-wide wipe that sits beside it. The wipe is the
    // CkInteractSource shape verbatim — a shadowing DoTick that delegates and then Clears the marker for the whole
    // registry, on the very pass whose view just skipped the entities a load is holding.
    class CKTESTS_API FProcessor_AutoTest_Ordering_ClearProbe_Setup : public ck_exp::TProcessor<
        FProcessor_AutoTest_Ordering_ClearProbe_Setup,
        FCk_Handle,
        TReadOnly<FFragment_AutoTest_Ordering_State>,
        TReadWrite<FFragment_AutoTest_Ordering_SetupLog>,
        FTag_AutoTest_Ordering_ClearProbe_NeedsSetup,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;
        using MarkedDirtyBy = FTag_AutoTest_Ordering_ClearProbe_NeedsSetup;

    public:
        using TProcessor::TProcessor;

    public:
        auto
        DoTick(
            TimeType InDeltaT) -> void;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle,
            const FFragment_AutoTest_Ordering_State& InState,
            FFragment_AutoTest_Ordering_SetupLog& InLog) -> void;
    };

    // Same shape again, but the wiped type is the REQUEST fragment: a Construct-time request destroyed here is
    // gone, not deferred.
    class CKTESTS_API FProcessor_AutoTest_Ordering_ClearProbe_HandleRequests : public ck_exp::TProcessor<
        FProcessor_AutoTest_Ordering_ClearProbe_HandleRequests,
        FCk_Handle,
        TReadWrite<FFragment_AutoTest_Ordering_ClearProbe_Requests>,
        TExclude<FTag_AutoTest_Ordering_ClearProbe_NeedsSetup>,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;
        using RunAfter = TDepList<FProcessor_AutoTest_Ordering_ClearProbe_Setup>;
        using MarkedDirtyBy = FFragment_AutoTest_Ordering_ClearProbe_Requests;

    public:
        using TProcessor::TProcessor;

    public:
        auto
        DoTick(
            TimeType InDeltaT) -> void;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle,
            FFragment_AutoTest_Ordering_ClearProbe_Requests& InRequests) -> void;
    };

    // --------------------------------------------------------------------------------------------------------------------

    // The teardown tripwire's witness: a real FGroup_EndPlay body on the probe destroyed mid-load.
    class CKTESTS_API FProcessor_AutoTest_Ordering_DestroyProbe_EndPlay : public TProcessor<
        FProcessor_AutoTest_Ordering_DestroyProbe_EndPlay,
        FTag_AutoTest_Ordering_DestroyProbe,
        FTag_AutoTest_Ordering_DestroyedDuringHydration,
        CK_IF_END_PLAY>
    {
    public:
        using Group = FGroup_EndPlay;

    public:
        using TProcessor::TProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };
}

// --------------------------------------------------------------------------------------------------------------------

// Probe A of the cross-entity pair, and the single probe every other ordering test uses.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

    // Records what construction observes, then binds the promise that delivers the restored value — the two
    // halves of the ordering contract, written where an author would naturally write them.
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

// Probe B: the sibling whose payload stalls.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// The probe whose feature markers a sibling processor wipes registry-wide every tick.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// Composes Velocity and FogOfWar — two Durable features whose Setup used to re-derive the very fragment their
// handler restores. Neither had a round-trip test, which is why the clobber survived: the Durable value is
// written by hydration and then overwritten by a Setup that runs afterwards under the ordering contract.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE();

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

// A Session dynamic fragment holding a handle to a child its owner's Construct creates — the single most common
// shape in a real feature (a probe node, a SceneNode, a spawned sub-entity), and the one the posture rules exist
// to keep out of the save. The child is an unlabeled ConstructSpawned entity, so it can never round-trip; the
// only correct outcome is that the rebuild makes a NEW one and this handle names it.
USTRUCT()
struct CKTESTS_API FCk_Test_Session_ChildRef
{
    GENERATED_BODY()

    UPROPERTY()
    FCk_Snapshot_Session Posture;

    UPROPERTY(SaveGame)
    FCk_Handle Child;
};

// --------------------------------------------------------------------------------------------------------------------

// A bindable target for the two Promise_OnHydrated cases that have no entity script to hang off: a bind made
// after the lift, and a bind on an entity no load ever mapped. Both must fire immediately — the promise answers
// "is anything still pending for this handle", and "no" is an answer.
UCLASS()
class CKTESTS_API UCk_AutoTest_Snapshot_OnHydratedWitness_UE final : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void
    OnLateBind(
        FCk_Handle InHandle);

    UFUNCTION()
    void
    OnFreshBind(
        FCk_Handle InHandle);
};

// --------------------------------------------------------------------------------------------------------------------

// A handle-rich subtree: a persisted owner, a LABELED child (which the load rebuilds and re-identifies), and an
// UNLABELED ConstructSpawned child (which it cannot, and must not try to). The owner carries a Session fragment
// naming the unlabeled one. Two things are asked of it after a load — that no stored handle in the structural
// backbone dangles, and that the Session handle names a NEW child rather than a remapped old id.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_HandleGraphProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_HandleGraphProbe_EntityScript_UE();

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

// Composes Velocity and Acceleration in LOCAL coordinates under a rotated Transform. Both features defer their
// local->world conversion to Setup because the Transform may not exist at Add time; under the ordering contract
// Setup runs AFTER hydration, so it must be able to tell "this entity still owes a conversion" from "this value
// was restored and is already world-space". A restored value that happens to equal the starting param is the
// case where those two look identical from the value alone.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_PhysicsLocalProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_PhysicsLocalProbe_EntityScript_UE();

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

// The probe that destroys itself from inside its own hydration, while the load is still holding it.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE();

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
