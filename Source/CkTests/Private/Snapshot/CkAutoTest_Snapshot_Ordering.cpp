#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.inl.h" // Register_* entry-point bodies
#include "CkEcs/Scheduler/CkProcessorRegistration.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

#include "CkMinimap/CkFogOfWar_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_Observer_Ck);
CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_Observer_CkExp);
CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_Observer_Parallel);
CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_Setup);
CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_ClearProbe_Setup);
CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_ClearProbe_HandleRequests);
CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_Ordering_DestroyProbe_EndPlay);

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_ordering
{
    // Process-wide because the observations have to survive the load's map travel, which every entity does not.
    // Each test resets them in its own Mutate stage, immediately before the save.
    FObservations GObservations{};

    auto Get_Observations() -> FObservations&
    {
        return GObservations;
    }

    auto Reset_Observations() -> void
    {
        GObservations = FObservations{};
    }

    // --------------------------------------------------------------------------------------------------------------------

    struct FRegistrar
    {
        FRegistrar()
        {
            // Probe A's first payload: applies immediately, so by the time B is still stalling the entity is
            // genuinely HALF hydrated — which is the state no observer may be handed.
            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_OrderingA>({
                .Posture = ECk_Snapshot_Posture::Durable,
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_Ordering_Probe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_OrderingA{};
                    Payload.Set_Value(InEntity.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA);
                    return FInstancedStruct::Make(Payload);
                },
                // Composition is the only thing it waits for. Setup runs afterwards and reads what this wrote.
                .HydrationApply = [](FCk_Handle& InEntity, const FInstancedStruct& InNew,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    if (NOT InEntity.Has<ck::FFragment_AutoTest_Ordering_State>())
                    { return ECk_Persistence_ApplyResult::NotReady; }

                    InEntity.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA =
                        InNew.Get<FCk_SaveData_AutoTest_OrderingA>().Get_Value();
                    return ECk_Persistence_ApplyResult::Applied;
                }});

            // Probe B's payload: refuses to apply for a few passes, so the window in which the set is half
            // hydrated is real and long enough for every observer to tick inside it. The stall count is what
            // proves the window existed at all.
            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_OrderingB>({
                .Posture = ECk_Snapshot_Posture::Durable,
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has_Any<ck::FTag_AutoTest_Ordering_Probe, ck::FTag_AutoTest_Ordering_ProbeB>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_OrderingB{};
                    Payload.Set_Value(InEntity.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueB);
                    return FInstancedStruct::Make(Payload);
                },
                .HydrationApply = [](FCk_Handle& InEntity, const FInstancedStruct& InNew,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    if (NOT InEntity.Has<ck::FFragment_AutoTest_Ordering_State>())
                    { return ECk_Persistence_ApplyResult::NotReady; }

                    // NotReady BEFORE the write, so a retry cannot stack.
                    if (GObservations.StallReturns < StallPasses)
                    {
                        ++GObservations.StallReturns;
                        return ECk_Persistence_ApplyResult::NotReady;
                    }

                    InEntity.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueB =
                        InNew.Get<FCk_SaveData_AutoTest_OrderingB>().Get_Value();
                    return ECk_Persistence_ApplyResult::Applied;
                }});

            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_OrderingClearProbe>({
                .Posture = ECk_Snapshot_Posture::Durable,
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_Ordering_ClearProbe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_OrderingClearProbe{};
                    Payload.Set_Value(InEntity.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA);
                    return FInstancedStruct::Make(Payload);
                },
                .HydrationApply = [](FCk_Handle& InEntity, const FInstancedStruct& InNew,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    if (NOT InEntity.Has<ck::FFragment_AutoTest_Ordering_State>())
                    { return ECk_Persistence_ApplyResult::NotReady; }

                    InEntity.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA =
                        InNew.Get<FCk_SaveData_AutoTest_OrderingClearProbe>().Get_Value();
                    return ECk_Persistence_ApplyResult::Applied;
                }});

            // Destroys its own entity from inside the load's own window — the teardown tripwire. It applies
            // rather than stalling, so the drain still closes and the destruction runs on the settle.
            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_OrderingDestroy>({
                .Posture = ECk_Snapshot_Posture::Durable,
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_Ordering_DestroyProbe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_OrderingDestroy{};
                    Payload.Set_Value(SavedValueDestroy);
                    return FInstancedStruct::Make(Payload);
                },
                .HydrationApply = [](FCk_Handle& InEntity, const FInstancedStruct& /*InNew*/,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_Ordering_DestroyProbe>())
                    { return ECk_Persistence_ApplyResult::NotReady; }

                    // Stamped before the request, so the EndPlay witness can tell THIS destruction from the
                    // ordinary teardown of the pre-save world during the load's travel.
                    InEntity.AddOrGet<ck::FTag_AutoTest_Ordering_DestroyedDuringHydration>();

                    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(InEntity);
                    return ECk_Persistence_ApplyResult::Applied;
                }});
        }
    };

    const FRegistrar GRegistrar{};
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    auto
        FProcessor_AutoTest_Ordering_Observer_Ck::
        ForEachEntity(
            TimeType,
            HandleType InHandle)
        -> void
    {
        auto& Observations = ck_autotest_snapshot_ordering::Get_Observations();
        ck_autotest_snapshot_ordering::Record_Observation(
            InHandle, Observations.SawHeldProbe_Ck, Observations.SawReleasedProbe_Ck);
    }

    // --------------------------------------------------------------------------------------------------------------------

    auto
        FProcessor_AutoTest_Ordering_Observer_CkExp::
        ForEachEntity(
            TimeType,
            HandleType InHandle)
        -> void
    {
        auto& Observations = ck_autotest_snapshot_ordering::Get_Observations();
        ck_autotest_snapshot_ordering::Record_Observation(
            InHandle, Observations.SawHeldProbe_CkExp, Observations.SawReleasedProbe_CkExp);
    }

    // --------------------------------------------------------------------------------------------------------------------

    // One probe entity, so the counters below are only ever touched by one worker at a time.
    auto
        FProcessor_AutoTest_Ordering_Observer_Parallel::
        ForEachEntity(
            TimeType,
            HandleType InHandle)
        -> void
    {
        auto& Observations = ck_autotest_snapshot_ordering::Get_Observations();
        ck_autotest_snapshot_ordering::Record_Observation(
            InHandle, Observations.SawHeldProbe_Parallel, Observations.SawReleasedProbe_Parallel);
    }

    // --------------------------------------------------------------------------------------------------------------------

    auto
        FProcessor_AutoTest_Ordering_Setup::
        ForEachEntity(
            TimeType,
            HandleType InHandle,
            const FFragment_AutoTest_Ordering_State& InState,
            FFragment_AutoTest_Ordering_SetupLog& InLog)
        -> void
    {
        InHandle.Remove<MarkedDirtyBy>();

        ++InLog._RunCount;
        InLog._ObservedA = InState._ValueA;

        // The cross-entity half: read the SIBLING's restored value from inside this entity's Setup. A per-entity
        // release would let this run while B was still held, and the value read would be B's construct default.
        InLog._SiblingWasResolvable = false;
        InHandle.View<FFragment_AutoTest_Ordering_State, FTag_AutoTest_Ordering_ProbeB>().ForEach(
            [&](FCk_Entity, const FFragment_AutoTest_Ordering_State& InSiblingState)
            {
                InLog._SiblingWasResolvable = true;
                InLog._ObservedSiblingB = InSiblingState._ValueB;
            });
    }

    // --------------------------------------------------------------------------------------------------------------------

    // The CkInteractSource shape verbatim: delegate, then wipe the marker for the WHOLE registry on the very pass
    // whose view just skipped whatever a load is holding.
    auto
        FProcessor_AutoTest_Ordering_ClearProbe_Setup::
        DoTick(
            TimeType InDeltaT)
        -> void
    {
        TProcessor::DoTick(InDeltaT);
        _TransientEntity.Clear<MarkedDirtyBy>();
    }

    auto
        FProcessor_AutoTest_Ordering_ClearProbe_Setup::
        ForEachEntity(
            TimeType,
            HandleType InHandle,
            const FFragment_AutoTest_Ordering_State& InState,
            FFragment_AutoTest_Ordering_SetupLog& InLog)
        -> void
    {
        InHandle.Remove<MarkedDirtyBy>();

        ++InLog._RunCount;
        InLog._ObservedA = InState._ValueA;
    }

    // --------------------------------------------------------------------------------------------------------------------

    // The harder half of the same shape: the wiped type is the request queue itself, so a wipe destroys queued
    // work rather than deferring a pass.
    auto
        FProcessor_AutoTest_Ordering_ClearProbe_HandleRequests::
        DoTick(
            TimeType InDeltaT)
        -> void
    {
        TProcessor::DoTick(InDeltaT);
        _TransientEntity.Clear<MarkedDirtyBy>();
    }

    auto
        FProcessor_AutoTest_Ordering_ClearProbe_HandleRequests::
        ForEachEntity(
            TimeType,
            HandleType,
            FFragment_AutoTest_Ordering_ClearProbe_Requests& InRequests)
        -> void
    {
        ck_autotest_snapshot_ordering::Get_Observations().ClearProbe_RequestsDrained += InRequests._PendingCount;

        InRequests._DrainedCount += InRequests._PendingCount;
        InRequests._PendingCount = 0;
    }

    // --------------------------------------------------------------------------------------------------------------------

    auto
        FProcessor_AutoTest_Ordering_DestroyProbe_EndPlay::
        ForEachEntity(
            TimeType,
            HandleType)
        -> void
    {
        ck_autotest_snapshot_ordering::Get_Observations().DestroyProbe_EndPlayRan = true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct&)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_Ordering_Probe>();
    InHandle.AddOrGet<ck::FFragment_AutoTest_Ordering_State>();
    InHandle.AddOrGet<ck::FFragment_AutoTest_Ordering_SetupLog>();
    InHandle.AddOrGet<ck::FTag_AutoTest_Ordering_NeedsSetup>();

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE::
    UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct&)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_Ordering_ProbeB>();
    InHandle.AddOrGet<ck::FFragment_AutoTest_Ordering_State>();

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct&)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_Ordering_ClearProbe>();
    InHandle.AddOrGet<ck::FFragment_AutoTest_Ordering_State>();
    InHandle.AddOrGet<ck::FFragment_AutoTest_Ordering_SetupLog>();
    InHandle.AddOrGet<ck::FTag_AutoTest_Ordering_ClearProbe_NeedsSetup>();

    // Enqueued during Construct, exactly like a feature request raised while the world is still rebuilding. It
    // may not be drained until Setup has run, and it may not be destroyed in the meantime.
    InHandle.AddOrGet<ck::FFragment_AutoTest_Ordering_ClearProbe_Requests>()._PendingCount = 1;

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct&)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_Ordering_DestroyProbe>();

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct&)
    -> ECk_EntityScript_ConstructionFlow
{
    using namespace ck_autotest_snapshot_ordering;

    // World coordinates deliberately: the LOCAL path would need a Transform, and what is under test is the
    // Durable value surviving Setup, not the coordinate conversion.
    UCk_Utils_Velocity_UE::Add(InHandle,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, StartingVelocity},
        ECk_Replication::DoesNotReplicate);

    auto FogParams = FCk_Fragment_FogOfWar_ParamsData{
        FCk_Minimap_WorldBounds{FVector2D::ZeroVector, FVector2D{FogHalfExtent, FogHalfExtent}}};
    FogParams.Set_CellSize(FogCellSize);
    UCk_Utils_FogOfWar_UE::Add(InHandle, FogParams);

    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
