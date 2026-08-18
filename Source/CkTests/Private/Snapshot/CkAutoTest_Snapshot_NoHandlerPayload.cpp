#include "CkTests/Snapshot/CkAutoTest_Snapshot_NoHandlerPayload.h"

#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.inl.h" // Register_* entry-point bodies
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_nohandlerpayload
{
    constexpr auto OrphanMarker = 5150;

    struct FRegistrar
    {
        FRegistrar()
        {
            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_NoHandler_Registered>({
                .Posture = ECk_Snapshot_Posture::Durable,
                // Emits the ORPHAN type on purpose: the registered pairing is what puts this row in the save set,
                // and the emitted type is what the load will fail to resolve. Scoped to the probe so the handler is
                // inert for every other test sharing the build.
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_NoHandlerPayload_Probe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_NoHandler_Orphan{};
                    Payload.Set_Value(OrphanMarker);
                    return FInstancedStruct::Make(Payload);
                },
                // Unreachable by construction — no saved row ever carries the REGISTERED type, because Produce
                // never emits it. Present because the registry requires the pairing, which is the very symmetry
                // that makes this fixture's shape the only in-process way to reach the no-handler drop.
                .HydrationApply = [](FCk_Handle& /*InEntity*/, const FInstancedStruct& /*InNew*/,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    return ECk_Persistence_ApplyResult::Applied;
                },
            });
        }
    };

    const FRegistrar GRegistrar{};
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& /*InSpawnParams*/)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_NoHandlerPayload_Probe>();
    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
