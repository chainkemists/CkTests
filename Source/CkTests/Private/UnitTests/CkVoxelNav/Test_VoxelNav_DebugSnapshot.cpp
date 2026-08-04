#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Debug/CkVoxelNav_DebugSnapshot.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Merge.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Debug snapshots are deliberately built from the same hermetic floor-and-pillar bake used by the octree tests. The
// assertions pin renderer-facing data contracts only: no world, physics scene, Slate widget, or live ECS handle exists
// in this fixture.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_debug_snapshot
{
    using namespace ck::voxelnav;

    constexpr auto FinestCellSizeUu = 50.0f;
    constexpr auto UnlimitedProbeBudget = 1000000;
    constexpr auto MaxSlices = 1000000;
    constexpr auto TestChunkIndex = 7;

    const auto VolumeBounds = FBox{FVector{-800.0}, FVector{800.0}};
    const auto FloorSlab = FBox{FVector{-800.0, -800.0, -800.0}, FVector{800.0, 800.0, -650.0}};
    const auto Pillar = FBox{FVector{100.0, 100.0, -390.0}, FVector{300.0, 300.0, 390.0}};

    auto Bake_Octree() -> TSharedPtr<const FOctree>
    {
        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{TArray<FBox>{FloorSlab, Pillar}};

        auto Params = FBuildParams{};
        Params._VolumeBounds = VolumeBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;
        Params._CellMerging = ECk_EnableDisable::Enable;

        auto Budget = FBuildBudget{};
        Budget._MaxOccupancyProbes = UnlimitedProbeBudget;
        Budget._MaxSeconds = 0.0f;

        auto State = FBuildState{};
        for (auto SliceIndex = 0; SliceIndex < MaxSlices && NOT State.Get_IsFinished(); ++SliceIndex)
        { Request_AdvanceBuild(State, Params, Backend, Budget); }

        return Request_ReleaseBuiltOctree(State);
    }

    auto Make_AllLayersParams() -> FDebugSnapshotBuildParams
    {
        auto Params = FDebugSnapshotBuildParams{};
        Params._RequestedLayers = EDebugSnapshotLayer::MergedFree | EDebugSnapshotLayer::RawFree |
            EDebugSnapshotLayer::Occupied;
        Params._MaxCellsPerLayer = 100000;
        return Params;
    }

    auto Build_Snapshot(const FOctree& InOctree, const FDebugSnapshotBuildParams& InParams) -> FDebugSnapshot
    {
        auto Snapshot = FDebugSnapshot{};
        Append_OctreeDebugSnapshot(InOctree, TestChunkIndex, InParams, Snapshot);
        return Snapshot;
    }

    auto Get_AllCellsValid(const FDebugSnapshotLayerOutput& InLayer, int32 InExpectedLayer) -> bool
    {
        for (const auto& Cell : InLayer._Cells)
        {
            if (Cell._Bounds.IsValid == 0 || Cell._ChunkIndex != TestChunkIndex ||
                (InExpectedLayer != INDEX_NONE && Cell._OctreeLayer != InExpectedLayer))
            { return false; }
        }
        return true;
    }

    auto Get_EqualCells(const TArray<FDebugSnapshotCell>& InLeft, const TArray<FDebugSnapshotCell>& InRight) -> bool
    {
        if (InLeft.Num() != InRight.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft.Num(); ++Index)
        {
            const auto& Left = InLeft[Index];
            const auto& Right = InRight[Index];
            if (Left._Bounds.Min != Right._Bounds.Min || Left._Bounds.Max != Right._Bounds.Max ||
                Left._ChunkIndex != Right._ChunkIndex || Left._OctreeLayer != Right._OctreeLayer)
            { return false; }
        }
        return true;
    }

    auto Make_CacheKey(int32 InEpoch, EDebugSnapshotStatus InStatus, int32 InCap = 100000) -> FDebugSnapshotCacheKey
    {
        auto Key = FDebugSnapshotCacheKey{};
        Key._Source = EDebugSnapshotSource::EditorPreview;
        Key._Status = InStatus;
        Key._Identity = TEXT("DebugSnapshotUnitFixture");
        Key._Epoch = InEpoch;
        Key._Fingerprint = 0xD06E5A0FULL;
        Key._BuildParams = Make_AllLayersParams();
        Key._BuildParams._MaxCellsPerLayer = InCap;
        return Key;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_DebugSnapshot_FidelityAndLayerSelection,
    "Ck.VoxelNav.DebugSnapshot.FidelityAndLayerSelection",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_VoxelNav_DebugSnapshot_FidelityAndLayerSelection::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_debug_snapshot;

    auto Octree = Bake_Octree();
    if (NOT TestTrue(TEXT("fixture bake published an octree"), Octree.IsValid()))
    { return false; }

    const auto Snapshot = Build_Snapshot(*Octree, Make_AllLayersParams());

    const auto LayersHaveData =
        TestTrue(TEXT("merged free cells were copied"), Snapshot._MergedFree._FilteredTotal > 0) &&
        TestTrue(TEXT("raw free cells were copied"), Snapshot._RawFree._FilteredTotal > 0) &&
        TestTrue(TEXT("occupied leaf sub-cells were copied"), Snapshot._Occupied._FilteredTotal > 0);
    const auto HighCapIsNotTruncated =
        TestEqual(TEXT("merged shown equals filtered total"), Snapshot._MergedFree._Cells.Num(), Snapshot._MergedFree._FilteredTotal) &&
        TestEqual(TEXT("raw shown equals filtered total"), Snapshot._RawFree._Cells.Num(), Snapshot._RawFree._FilteredTotal) &&
        TestEqual(TEXT("occupied shown equals filtered total"), Snapshot._Occupied._Cells.Num(), Snapshot._Occupied._FilteredTotal) &&
        TestFalse(TEXT("high cap does not truncate merged cells"), Snapshot._MergedFree._Truncated) &&
        TestFalse(TEXT("high cap does not truncate raw cells"), Snapshot._RawFree._Truncated) &&
        TestFalse(TEXT("high cap does not truncate occupied cells"), Snapshot._Occupied._Truncated);
    const auto MetadataIsRendererSafe =
        TestTrue(TEXT("authored bounds are valid"), Snapshot._AuthoredBounds.IsValid != 0) &&
        TestTrue(TEXT("navigation bounds are valid"), Snapshot._NavigationBounds.IsValid != 0) &&
        TestTrue(TEXT("merged cells carry the requested chunk and no octree layer"),
            Get_AllCellsValid(Snapshot._MergedFree, INDEX_NONE)) &&
        TestTrue(TEXT("occupied cells carry the requested chunk and layer zero"),
            Get_AllCellsValid(Snapshot._Occupied, 0));

    auto RawLayersAreValid = true;
    for (const auto& Cell : Snapshot._RawFree._Cells)
    { RawLayersAreValid &= Cell._Bounds.IsValid != 0 && Cell._ChunkIndex == TestChunkIndex && Cell._OctreeLayer >= 0; }
    TestTrue(TEXT("raw cells carry valid source layer metadata"), RawLayersAreValid);

    auto MergedOnlyParams = FDebugSnapshotBuildParams{};
    MergedOnlyParams._RequestedLayers = EDebugSnapshotLayer::MergedFree;
    MergedOnlyParams._MaxCellsPerLayer = 100000;
    const auto MergedOnly = Build_Snapshot(*Octree, MergedOnlyParams);

    TestTrue(TEXT("merged-only request still contains merged cells"), MergedOnly._MergedFree._Cells.Num() > 0);
    TestEqual(TEXT("merged-only request leaves raw layer empty"), MergedOnly._RawFree._Cells.Num(), 0);
    TestEqual(TEXT("merged-only request leaves occupied layer empty"), MergedOnly._Occupied._Cells.Num(), 0);
    return LayersHaveData && HighCapIsNotTruncated && MetadataIsRendererSafe;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_DebugSnapshot_DeterministicCapDepthAndClip,
    "Ck.VoxelNav.DebugSnapshot.DeterministicCapDepthAndClip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_VoxelNav_DebugSnapshot_DeterministicCapDepthAndClip::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_debug_snapshot;

    const auto Octree = Bake_Octree();
    if (NOT TestTrue(TEXT("fixture bake published an octree"), Octree.IsValid()))
    { return false; }

    auto CappedParams = Make_AllLayersParams();
    CappedParams._RequestedLayers = EDebugSnapshotLayer::RawFree;
    CappedParams._MaxCellsPerLayer = 3;
    const auto CappedA = Build_Snapshot(*Octree, CappedParams);
    const auto CappedB = Build_Snapshot(*Octree, CappedParams);

    const auto CapContract =
        TestEqual(TEXT("cap exposes exactly three raw cells"), CappedA._RawFree._Cells.Num(), 3) &&
        TestTrue(TEXT("cap retains the filtered total"), CappedA._RawFree._FilteredTotal > 3) &&
        TestTrue(TEXT("cap marks the layer truncated"), CappedA._RawFree._Truncated) &&
        TestTrue(TEXT("repeated snapshot has stable cell order and bounds"),
            Get_EqualCells(CappedA._RawFree._Cells, CappedB._RawFree._Cells));

    auto ZeroCapParams = CappedParams;
    ZeroCapParams._MaxCellsPerLayer = 0;
    const auto ZeroCap = Build_Snapshot(*Octree, ZeroCapParams);
    const auto ZeroCapContract =
        TestEqual(TEXT("zero cap emits no cells"), ZeroCap._RawFree._Cells.Num(), 0) &&
        TestEqual(TEXT("zero cap preserves filtered total"), ZeroCap._RawFree._FilteredTotal, CappedA._RawFree._FilteredTotal) &&
        TestTrue(TEXT("zero cap marks the non-empty layer truncated"), ZeroCap._RawFree._Truncated);

    const auto FirstCell = CappedA._RawFree._Cells[0];
    auto FilteredParams = Make_AllLayersParams();
    FilteredParams._RequestedLayers = EDebugSnapshotLayer::RawFree;
    FilteredParams._MinOctreeLayer = FirstCell._OctreeLayer;
    FilteredParams._MaxOctreeLayer = FirstCell._OctreeLayer;
    FilteredParams._ClipBounds = FirstCell._Bounds;
    const auto Filtered = Build_Snapshot(*Octree, FilteredParams);

    auto EveryCellPassesFilters = true;
    for (const auto& Cell : Filtered._RawFree._Cells)
    {
        EveryCellPassesFilters &= Cell._OctreeLayer == FirstCell._OctreeLayer &&
            Cell._Bounds.Intersect(FirstCell._Bounds);
    }
    const auto FilterContract =
        TestTrue(TEXT("depth and clip filters retain at least the selected cell"), Filtered._RawFree._FilteredTotal > 0) &&
        TestTrue(TEXT("depth and clip filters reduce the raw total"),
            Filtered._RawFree._FilteredTotal < CappedA._RawFree._FilteredTotal) &&
        TestTrue(TEXT("every shown cell satisfies depth and clip"), EveryCellPassesFilters);

    return CapContract && ZeroCapContract && FilterContract;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_DebugSnapshot_CacheGenerationAndReplacement,
    "Ck.VoxelNav.DebugSnapshot.CacheGenerationAndReplacement",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_VoxelNav_DebugSnapshot_CacheGenerationAndReplacement::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_debug_snapshot;

    auto Octree = Bake_Octree();
    if (NOT TestTrue(TEXT("fixture bake published an octree"), Octree.IsValid()))
    { return false; }

    const auto FirstSnapshot = Build_Snapshot(*Octree, Make_AllLayersParams());
    const auto FirstCellCount = FirstSnapshot._RawFree._Cells.Num();

    auto Cache = FDebugSnapshotCache{};
    const auto FirstKey = Make_CacheKey(1, EDebugSnapshotStatus::Current);
    TestTrue(TEXT("first key publishes"), Cache.Publish(FirstKey, FirstSnapshot));

    auto KeyedCopy = FDebugSnapshot{};
    TestTrue(TEXT("matching cheap key returns the retained value before another octree enumeration"),
        Cache.TryGet_SnapshotForKey(FirstKey, KeyedCopy));
    TestEqual(TEXT("matching-key lookup returns generation one"), KeyedCopy._Generation, 1ULL);
    TestFalse(TEXT("a changed epoch misses before publication"),
        Cache.TryGet_SnapshotForKey(Make_CacheKey(2, EDebugSnapshotStatus::Current), KeyedCopy));

    const auto FirstCopy = Cache.Get_SnapshotCopy();
    if (NOT TestTrue(TEXT("first whole value can be read"), FirstCopy.IsSet()))
    { return false; }
    TestEqual(TEXT("first publication receives generation one"), FirstCopy->_Generation, 1ULL);

    TestFalse(TEXT("same key does not rebuild or replace the snapshot"), Cache.Publish(FirstKey, FirstSnapshot));
    const auto UnchangedCopy = Cache.Get_SnapshotCopy();
    TestTrue(TEXT("same key retains the old snapshot"), UnchangedCopy.IsSet() && UnchangedCopy->_Generation == 1ULL);

    // The cache must own only the copied value. Once this shared source is released, the retained copy remains usable.
    Octree.Reset();
    const auto RetainedAfterSourceRelease = Cache.Get_SnapshotCopy();
    TestTrue(TEXT("retained snapshot survives source octree release"),
        RetainedAfterSourceRelease.IsSet() && RetainedAfterSourceRelease->_RawFree._Cells.Num() == FirstCellCount);

    auto Replacement = FDebugSnapshot{};
    Replacement._StatusMessage = TEXT("replacement");
    Replacement._RawFree._Cells.Emplace(FDebugSnapshotCell{FBox{FVector{1.0}, FVector{2.0}}, 99, 3});

    TestTrue(TEXT("epoch change publishes a whole replacement"),
        Cache.Publish(Make_CacheKey(2, EDebugSnapshotStatus::Current), Replacement));
    auto ReplacementCopy = Cache.Get_SnapshotCopy();
    TestTrue(TEXT("replacement has exactly its own cells"), ReplacementCopy.IsSet() &&
        ReplacementCopy->_Generation == 2ULL && ReplacementCopy->_RawFree._Cells.Num() == 1 &&
        ReplacementCopy->_RawFree._Cells[0]._ChunkIndex == 99);

    TestTrue(TEXT("filter change publishes once"),
        Cache.Publish(Make_CacheKey(2, EDebugSnapshotStatus::Current, 3), Replacement));
    TestTrue(TEXT("source-status change publishes once"),
        Cache.Publish(Make_CacheKey(2, EDebugSnapshotStatus::StaleCook, 3), Replacement));
    const auto LastCopy = Cache.Get_SnapshotCopy();
    TestTrue(TEXT("each distinct key advanced generation once"), LastCopy.IsSet() && LastCopy->_Generation == 4ULL);

    Cache.Clear();
    TestFalse(TEXT("clear removes the retained value"), Cache.Get_SnapshotCopy().IsSet());
    TestTrue(TEXT("publish after clear accepts a new whole value"),
        Cache.Publish(Make_CacheKey(3, EDebugSnapshotStatus::MissingCook), Replacement));
    const auto AfterClear = Cache.Get_SnapshotCopy();
    TestTrue(TEXT("post-clear value contains no earlier cells"), AfterClear.IsSet() &&
        AfterClear->_Generation == 5ULL && AfterClear->_RawFree._Cells.Num() == 1);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_DebugSnapshot_OccupiedHelperSafetyAndFidelity,
    "Ck.VoxelNav.DebugSnapshot.OccupiedHelperSafetyAndFidelity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_VoxelNav_DebugSnapshot_OccupiedHelperSafetyAndFidelity::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_debug_snapshot;

    const auto Octree = Bake_Octree();
    if (NOT TestTrue(TEXT("fixture bake published an octree"), Octree.IsValid()))
    { return false; }

    auto First = TArray<FNodeAddress>{};
    auto Second = TArray<FNodeAddress>{};
    Get_OccupiedCells(*Octree, First);
    Get_OccupiedCells(*Octree, Second);
    TestTrue(TEXT("occupied addresses have deterministic order"), First == Second);

    auto HasPartialLeaf = false;
    auto HasFullyOccupiedLeaf = false;
    auto OccupancyIsFaithful = true;
    auto AddressesAreLayerZero = true;
    auto CountsByLeaf = TMap<NodeIndex, int32>{};
    for (const auto& Address : First)
    {
        AddressesAreLayerZero &= Address.Get_IsValid() && Address.Get_LayerIndex() == 0;
        ++CountsByLeaf.FindOrAdd(Address.Get_NodeIndex());
        const auto Bounds = Get_NodeBoundsFromAddress(*Octree, Address);
        OccupancyIsFaithful &= Bounds.IsValid != 0 && NOT Get_IsPositionFree(*Octree, Bounds.GetCenter());
    }
    for (const auto& Pair : CountsByLeaf)
    {
        HasPartialLeaf |= Pair.Value > 0 && Pair.Value < 64;
        HasFullyOccupiedLeaf |= Pair.Value == 64;
    }

    TestTrue(TEXT("occupied helper returned cells"), First.Num() > 0);
    TestTrue(TEXT("occupied addresses name layer zero sub-cells"), AddressesAreLayerZero);
    TestTrue(TEXT("every occupied address resolves to a blocked valid sub-cell center"), OccupancyIsFaithful);
    TestTrue(TEXT("pillar creates a partially occupied leaf"), HasPartialLeaf);
    TestTrue(TEXT("floor creates a fully occupied leaf"), HasFullyOccupiedLeaf);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
