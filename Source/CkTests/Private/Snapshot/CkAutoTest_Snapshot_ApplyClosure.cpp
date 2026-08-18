#include "CkTests/Snapshot/CkAutoTest_Snapshot_ApplyClosure.h"

#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.inl.h" // Register_* entry-point bodies
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_applyclosure
{
    struct FRegistrar
    {
        FRegistrar()
        {
            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_ApplyClosure_A>({
                .Posture = ECk_Snapshot_Posture::Durable,
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_ApplyClosure_Probe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_ApplyClosure_A{};
                    Payload.Set_Value(InEntity.Get<ck::FFragment_AutoTest_ApplyClosure_Values>()._ValueA);
                    return FInstancedStruct::Make(Payload);
                },
                .HydrationApply = [](FCk_Handle& InEntity, const FInstancedStruct& InNew,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    if (NOT InEntity.Has<ck::FFragment_AutoTest_ApplyClosure_Values>())
                    { return ECk_Persistence_ApplyResult::NotReady; }

                    InEntity.Get<ck::FFragment_AutoTest_ApplyClosure_Values>()._ValueA =
                        InNew.Get<FCk_SaveData_AutoTest_ApplyClosure_A>().Get_Value();
                    return ECk_Persistence_ApplyResult::Applied;
                },
            });

            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_ApplyClosure_B>({
                .Posture = ECk_Snapshot_Posture::Durable,
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_ApplyClosure_Probe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_ApplyClosure_B{};
                    Payload.Set_Value(InEntity.Get<ck::FFragment_AutoTest_ApplyClosure_Values>()._ValueB);
                    return FInstancedStruct::Make(Payload);
                },
                .HydrationApply = [](FCk_Handle& InEntity, const FInstancedStruct& InNew,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    if (NOT InEntity.Has<ck::FFragment_AutoTest_ApplyClosure_Values>())
                    { return ECk_Persistence_ApplyResult::NotReady; }

                    InEntity.Get<ck::FFragment_AutoTest_ApplyClosure_Values>()._ValueB =
                        InNew.Get<FCk_SaveData_AutoTest_ApplyClosure_B>().Get_Value();
                    return ECk_Persistence_ApplyResult::Applied;
                },
            });
        }
    };

    const FRegistrar GRegistrar{};
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& /*InSpawnParams*/)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_ApplyClosure_Probe>();
    InHandle.AddOrGet<ck::FFragment_AutoTest_ApplyClosure_Values>();
    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
