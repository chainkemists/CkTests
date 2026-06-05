// Defensive lifecycle-strip. An entity captured mid-destroy (FTag_DestroyEntity_Initiate) or just-created
// (FTag_EntityJustCreated) must restore WITHOUT that marker and survive (not be resurrected into a destroy flow).
// Each carries a Tier-C value fragment so it outlives orphans(); we assert the value survives and the marker is gone.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_FragmentRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Writer.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Reader.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/Archive.h"
#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// Tier-C value fragment so the test entities survive orphans() after their lifecycle tags are stripped.
struct FFragment_SnapshotStripTest_Value
{
    CK_GENERATED_BODY(FFragment_SnapshotStripTest_Value);
    using IsSnapshotable = void;

public:
    int32 _Value = 0;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& /*InCtx*/) -> void
    {
        InAr << _Value;
    }
};

CK_REGISTER_SNAPSHOTABLE(FFragment_SnapshotStripTest_Value);

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LifecycleStrip_Test,
    "Ck.Snapshot.LifecycleStrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_LifecycleStrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // Request_CreateEntity already stamps FTag_EntityJustCreated on every fresh entity (set-once — re-Adding it
    // would trip a CkEnsure). That auto-stamp IS the non-quiescent capture state we want to exercise, so both
    // entities carry EntityJustCreated implicitly. We additionally mark Destroying with DestroyEntity_Initiate.
    auto Destroying = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto JustMade   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    Destroying.Add<FFragment_SnapshotStripTest_Value>()._Value = 11;
    Destroying.Add<ck::FTag_DestroyEntity_Initiate>();

    JustMade.Add<FFragment_SnapshotStripTest_Value>()._Value = 22;

    // Sanity: both entities carry the auto-stamped just-created marker before capture.
    TestTrue(TEXT("Destroying carries auto-stamped EntityJustCreated pre-capture"),
        Destroying.Has<ck::FTag_EntityJustCreated>());
    TestTrue(TEXT("JustMade carries auto-stamped EntityJustCreated pre-capture"),
        JustMade.Has<ck::FTag_EntityJustCreated>());

    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);
    TestEqual(TEXT("Restore success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));

    const auto CountView = [&](auto View)
    {
        auto N = 0;
        for (const auto Entity : View) { (void)Entity; ++N; }
        return N;
    };

    // Both value-carrying entities survived restore (not resurrected into a destroy flow / not culled).
    TestEqual(TEXT("Both value entities survived restore"),
        CountView(RawRegistry->view<FFragment_SnapshotStripTest_Value>()), 2);

    // The lifecycle markers were stripped post-restore.
    TestEqual(TEXT("DestroyEntity_Initiate stripped"),
        CountView(RawRegistry->view<ck::FTag_DestroyEntity_Initiate>()), 0);
    TestEqual(TEXT("EntityJustCreated stripped"),
        CountView(RawRegistry->view<ck::FTag_EntityJustCreated>()), 0);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
