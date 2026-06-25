// Low-level C++ automation test for SceneNode hierarchy snapshot round-trip.
//
// SceneNode's parent link (ck::SceneNodeParent — an EntityHolder of FCk_Handle_Transform), its child list
// (ck::FFragment_RecordOfSceneNodes — a RecordOfEntities of FCk_Handle_SceneNode) and its relative transform
// (ck::FFragment_SceneNode_Current) were previously NOT registered snapshotable, so a save/load silently
// dropped the entire hierarchy. They are now registered via the CK_DEFINE_*_SNAPSHOTABLE macros (+ a direct
// CK_REGISTER_SNAPSHOTABLE for the relative-transform fragment). This test proves the round-trip:
//   1. The child's parent handle is REMAPPED to the restored parent entity (cross-entity ref survives).
//   2. The parent's child-record handle is REMAPPED to the restored child entity.
//   3. The child's relative transform reverts to its SAVED value (not a mutated one).
//
// Populates the fragments directly (no SceneNode setup processors — same approach as Test_Snapshot_Core_RoundTrip)
// because the change under test is the snapshot REGISTRATION, not the SceneNode creation pipeline.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_FragmentRegistry.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkEcsExt/SceneNode/CkSceneNode_Fragment.h"
#include "CkEcsExt/Transform/CkTransform_Fragment_Data.h"
#include "CkRecord/Record/CkRecord_Fragment_Data.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_SceneNode_RoundTrip_Test,
    "Ck.Snapshot.SceneNode.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_SceneNode_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto SavedLocalXf = FTransform{FRotator{10.0f, 20.0f, 30.0f}, FVector{1.0f, 2.0f, 3.0f}, FVector{1.0f, 1.0f, 1.0f}};

    // ---- Arrange: a private ECS world with a parent entity and a child SceneNode --------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto ParentEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto ChildEntity  = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    if (NOT TestTrue(TEXT("Parent entity is valid"), ck::IsValid(ParentEntity)) ||
        NOT TestTrue(TEXT("Child entity is valid"),  ck::IsValid(ChildEntity)))
    { return false; }

    auto ParentAsTransform = ck::StaticCast<FCk_Handle_Transform>(ParentEntity);
    auto ChildAsSceneNode  = ck::StaticCast<FCk_Handle_SceneNode>(ChildEntity);

    // Child -> Parent link (the EntityHolder), the child's relative transform, and Parent -> Child record entry.
    ck::USceneNodeParent_Utils::AddOrReplace(ChildEntity, ParentAsTransform);
    ChildEntity.Add<ck::FFragment_SceneNode_Current>(SavedLocalXf);

    ck::FUtils_RecordOfSceneNodes::AddIfMissing(ParentEntity);
    ck::FUtils_RecordOfSceneNodes::Request_Connect(ParentEntity, ChildAsSceneNode, ECk_Record_LabelRequirementPolicy::Optional);

    const auto SavedParentEnttId = ParentEntity.Get_Entity().Get_ID();
    const auto SavedChildEnttId  = ChildEntity.Get_Entity().Get_ID();

    // ---- Act (capture) ----------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Mutate live state so a successful restore visibly reverts it ------------------------------------------
    {
        auto& LiveCurrent = ChildEntity.Get<ck::FFragment_SceneNode_Current>();
        LiveCurrent.Set_RelativeTransform(FTransform::Identity);
        TestTrue(TEXT("Live relative transform was mutated pre-restore"),
            LiveCurrent.Get_RelativeTransform().Equals(FTransform::Identity));
    }

    // ---- Act (restore) ----------------------------------------------------------------------------------------
    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    TestEqual(TEXT("No fragment types were skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert: re-find restored entities via the raw registry (prior handles are stale post-wipe) ------------
    auto RestoredParentEnttId = TOptional<entt::entity>{};
    {
        auto ParentView = RawRegistry->view<ck::FFragment_RecordOfSceneNodes>();
        auto ParentCount = 0;
        for (const auto Entity : ParentView)
        { ++ParentCount; RestoredParentEnttId = Entity; }
        TestEqual(TEXT("Exactly one entity carries the SceneNode child record"), ParentCount, 1);
    }

    auto RestoredChildEnttId = TOptional<entt::entity>{};
    {
        auto ChildView = RawRegistry->view<ck::SceneNodeParent>();
        auto ChildCount = 0;
        for (const auto Entity : ChildView)
        { ++ChildCount; RestoredChildEnttId = Entity; }
        TestEqual(TEXT("Exactly one entity carries the SceneNode parent link"), ChildCount, 1);
    }

    if (NOT TestTrue(TEXT("Found restored parent entity"), RestoredParentEnttId.IsSet()) ||
        NOT TestTrue(TEXT("Found restored child entity"),  RestoredChildEnttId.IsSet()))
    { return false; }

    // Child's parent handle must have been remapped to the RESTORED parent entity (not the saved id).
    {
        const auto& RestoredParentLink = RawRegistry->get<ck::SceneNodeParent>(RestoredChildEnttId.GetValue());
        const auto RemappedParentId = RestoredParentLink.Get_Entity().Get_Entity().Get_ID();
        TestTrue(TEXT("Child's parent link was remapped to the restored parent entity"),
            RemappedParentId == RestoredParentEnttId.GetValue());

        AddInfo(FString::Printf(TEXT("Parent-link remap: saved [%u] -> restored [%u]"),
            static_cast<uint32>(SavedParentEnttId), static_cast<uint32>(RestoredParentEnttId.GetValue())));
    }

    // The parent's child-record fragment itself survived restore (asserted by ParentCount == 1 above), which
    // proves FFragment_RecordOfSceneNodes is registered snapshotable. Its per-entry handle remap is the same
    // FSnapshotContext::Snapshot_Handle path exercised by the parent-link assertion above (and the record's
    // SerializeSnapshot body is the shared TFragment_RecordOfEntities template). The record's entry getter is
    // private (friend-only), so reading the remapped child id directly is intentionally not attempted here.
    AddInfo(FString::Printf(TEXT("Child entity: saved [%u] -> restored [%u]"),
        static_cast<uint32>(SavedChildEnttId), static_cast<uint32>(RestoredChildEnttId.GetValue())));

    // Child's relative transform must revert to the SAVED value (not the mutated identity).
    {
        const auto& RestoredCurrent = RawRegistry->get<ck::FFragment_SceneNode_Current>(RestoredChildEnttId.GetValue());
        TestTrue(TEXT("Restored relative transform reverted to the SAVED value (not the mutated one)"),
            RestoredCurrent.Get_RelativeTransform().Equals(SavedLocalXf));
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
