#include "CkSnapshot/Snapshot/CkSnapshot_RuntimeSpawnPolicy.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_RuntimeSpawnPolicy_Test,
    "Ck.Snapshot.RuntimeSpawnPolicy.NonPersistedOwnerRequiresRespawnOptIn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_RuntimeSpawnPolicy_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto PersistedOwnerId = 123u;
    const auto NonPersistedOwnerId = 456u;
    const auto PersistedIds = TSet<uint32>{PersistedOwnerId};

    TestFalse(TEXT("a non-persisted owner without the respawn opt-in is skipped"),
        ck::snapshot::runtime_spawn_policy::CanRebuildRuntimeSpawnedWithOwnerPolicy(
            /*InIsSnapshotRespawnable=*/false, NonPersistedOwnerId, PersistedIds));

    TestTrue(TEXT("the respawn opt-in permits a non-persisted owner"),
        ck::snapshot::runtime_spawn_policy::CanRebuildRuntimeSpawnedWithOwnerPolicy(
            /*InIsSnapshotRespawnable=*/true, NonPersistedOwnerId, PersistedIds));

    TestTrue(TEXT("a persisted owner rebuilds without the respawn opt-in"),
        ck::snapshot::runtime_spawn_policy::CanRebuildRuntimeSpawnedWithOwnerPolicy(
            /*InIsSnapshotRespawnable=*/false, PersistedOwnerId, PersistedIds));

    TestTrue(TEXT("a target with no recorded lifetime owner rebuilds without the respawn opt-in"),
        ck::snapshot::runtime_spawn_policy::CanRebuildRuntimeSpawnedWithOwnerPolicy(
            /*InIsSnapshotRespawnable=*/false,
            ck::snapshot::runtime_spawn_policy::k_NoOwnerSavedEntity, PersistedIds));

    return true;
}

#endif
