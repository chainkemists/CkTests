#include "CkTests/Snapshot/CkAutoTest_Snapshot_Quarantine.h"

#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.inl.h" // Register_* entry-point bodies
#include "CkEcs/Persistence/CkPersistenceHydration.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

#include "CkSnapshot/CkSnapshot_Utils.h" // Promise_OnHydrated

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_quarantine
{
    constexpr auto StallMarker = 7331;

    struct FRegistrar
    {
        FRegistrar()
        {
            FCk_PersistenceHandlerRegistry::Register_SaveOnly<FCk_SaveData_AutoTest_QuarantineStall>({
                .Posture = ECk_Snapshot_Posture::Durable,
                // UNSET for everything but the probe: this handler is registered for the whole build, and a payload
                // that never applies has no business being produced for any entity that did not ask for one.
                .Produce = [](FCk_Handle& InEntity) -> TOptional<FInstancedStruct>
                {
                    if (NOT InEntity.Has<ck::FTag_AutoTest_Quarantine_Probe>())
                    { return {}; }

                    auto Payload = FCk_SaveData_AutoTest_QuarantineStall{};
                    Payload.Set_Marker(StallMarker);
                    return FInstancedStruct::Make(Payload);
                },
                // Never Applied, never Rejected — the entry stays queued and its entity stays quarantined until
                // something releases it. That "something" is what the gate exists to prove.
                .HydrationApply = [](FCk_Handle& /*InEntity*/, const FInstancedStruct& /*InNew*/,
                                     const TOptional<FInstancedStruct>& /*InOld*/) -> ECk_Persistence_ApplyResult
                {
                    return ECk_Persistence_ApplyResult::NotReady;
                },
            });
        }
    };

    const FRegistrar GRegistrar{};

    int32 GOnHydratedFireCount = 0;

    auto Get_OnHydratedFireCount() -> int32&
    {
        return GOnHydratedFireCount;
    }
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    InHandle.AddOrGet<ck::FTag_AutoTest_Quarantine_Probe>();
    return ECk_EntityScript_ConstructionFlow::Finished;
}

auto
    UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::
    BeginPlay()
    -> void
{
    Super::BeginPlay();

    auto Self = Get_AssociatedEntity();
    if (ck::Is_NOT_Valid(Self))
    { return; }

    auto Delegate = FCk_Delegate_Hydration_OnHydrated{};
    Delegate.BindUFunction(this, TEXT("OnHydrated"));

    UCk_Utils_Snapshot_UE::Promise_OnHydrated(Self, Delegate);
}

void
    UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::
    OnHydrated(
        FCk_Handle /*InHandle*/)
{
    ++ck_autotest_snapshot_quarantine::GOnHydratedFireCount;
}

auto
    UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
