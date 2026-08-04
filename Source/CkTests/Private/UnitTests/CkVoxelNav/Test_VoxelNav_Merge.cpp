#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Merge.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Raycast.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Repair.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"
#include "CkVoxelNav/Path/CkVoxelNav_Path_Graph.h"

#include "../CkUnitTest_Common.h"

#include <HAL/PlatformTime.h>
#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Node merging, hermetic: octrees baked through the stub geometry backend with the merge pass on and off,
// then compared. No world, no physics, no PIE.
//
// Two reference scenes, and they answer different questions:
//   - the KNOWN LAYOUT (1600uu cube, 50uu finest cell, floor slab + pillar) - the same fixture the bake and
//     path tests use, small enough that a failure is inspectable by hand;
//   - a GENERATED scene at 6400uu / 50uu, where the free-cell count is large enough for a merge ratio to
//     mean anything and the bake spans real budget slices.
//
// The invariants are asserted; the timings are RECORDED. A wall-clock number is a property of the machine
// that ran it, and an assertion on one is a flake waiting for a busy build agent - so bake and search
// milliseconds are logged for the A/B record, and only the cell-count reduction, the partition invariants
// and the re-merge locality are pinned.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_merge
{
    constexpr auto FinestCellSizeUu = 50.0f;

    constexpr auto UnlimitedProbeBudget = 1000000;

    // The shipped per-tick default, so the recorded slice count is the number of frames a real bake spans.
    constexpr auto DefaultProbeBudgetPerTick = 2048;

    constexpr auto SearchIterationCap = 200000;

    const auto TestVolumeId = ck::voxelnav::FVolumeId{1};

    // Deliberately loose: the point of the assertion is that merging is a REDUCTION, and the ratio the
    // scenes actually reach is recorded rather than pinned. A floor tight enough to be interesting would be
    // pinning the greedy pass's tie-breaks.
    constexpr auto MaxMergedPercentOfPlain = 25;

    // ----------------------------------------------------------------------------------------------------------------
    // Scene A - the known layout, identical to the bake and path fixtures.

    constexpr auto KnownVolumeHalfSizeUu = 800.0;

    const auto KnownVolumeBounds = FBox{FVector{-KnownVolumeHalfSizeUu}, FVector{KnownVolumeHalfSizeUu}};

    const auto KnownFloorSlab = FBox{FVector{-800.0, -800.0, -800.0}, FVector{800.0, 800.0, -650.0}};
    const auto KnownPillar = FBox{FVector{100.0, 100.0, -390.0}, FVector{300.0, 300.0, 390.0}};

    const auto KnownRouteFrom = FVector{-575.0, -575.0, 575.0};
    const auto KnownRouteTo = FVector{175.0, 175.0, 575.0};

    static auto
        Make_KnownObstacles()
        -> TArray<FBox>
    {
        return TArray<FBox>{KnownFloorSlab, KnownPillar};
    }

    // ----------------------------------------------------------------------------------------------------------------
    // Scene B - generated, 6400uu across at the same 50uu finest cell: leaf 200uu, six layers, a 16x16x16
    // layer-1 lattice. A floor and a 4x4 grid of pillars, all placed CLEAR of every 50uu cell boundary so no
    // occupancy answer in the scene is a tie-break.

    constexpr auto LargeVolumeHalfSizeUu = 3200.0;

    const auto LargeVolumeBounds = FBox{FVector{-LargeVolumeHalfSizeUu}, FVector{LargeVolumeHalfSizeUu}};

    static auto
        Make_LargeObstacles()
        -> TArray<FBox>
    {
        constexpr double PillarCentres[4] = {-2025.0, -675.0, 675.0, 2025.0};
        constexpr auto PillarHalfWidthUu = 155.0;
        constexpr auto PillarBaseUu = -3100.0;
        constexpr auto PillarTopUu = 1005.0;

        auto Obstacles = TArray<FBox>{};

        // Overhangs the volume on every horizontal axis, so no cell column anywhere straddles its edge.
        Obstacles.Emplace(FBox{FVector{-3300.0, -3300.0, -3300.0}, FVector{3300.0, 3300.0, -3055.0}});

        for (const auto CentreX : PillarCentres)
        {
            for (const auto CentreY : PillarCentres)
            {
                Obstacles.Emplace(FBox{
                    FVector{CentreX - PillarHalfWidthUu, CentreY - PillarHalfWidthUu, PillarBaseUu},
                    FVector{CentreX + PillarHalfWidthUu, CentreY + PillarHalfWidthUu, PillarTopUu}});
            }
        }

        return Obstacles;
    }

    struct FBenchmarkRoute
    {
        FVector _From = FVector::ZeroVector;
        FVector _To = FVector::ZeroVector;
    };

    static auto
        Make_LargeRoutes()
        -> TArray<FBenchmarkRoute>
    {
        return TArray<FBenchmarkRoute>
        {
            // Across the pillar field at pillar height, so the route has to weave rather than fly over.
            FBenchmarkRoute{FVector{-2900.0, -2900.0, 500.0}, FVector{2900.0, 2900.0, 500.0}},

            // Low corner to opposite high corner: crosses coarse open cells and the fine cells at the floor.
            FBenchmarkRoute{FVector{-2900.0, -2900.0, -2900.0}, FVector{2900.0, 2900.0, 2400.0}},

            // Straight down the middle between two pillar rows.
            FBenchmarkRoute{FVector{0.0, -2900.0, 800.0}, FVector{0.0, 2900.0, 800.0}}
        };
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FBakeOutcome
    {
        TSharedPtr<const ck::voxelnav::FOctree> _Octree;
        FCk_VoxelNav_BuildStats _Stats;
        ECk_VoxelNav_BuildStage _Stage = ECk_VoxelNav_BuildStage::NotStarted;
    };

    static auto
        Run_Bake(
            const TArray<FBox>& InObstacles,
            const FBox& InBounds,
            ECk_EnableDisable InCellMerging,
            int32 InMaxProbesPerSlice)
        -> FBakeOutcome
    {
        using namespace ck::voxelnav;

        constexpr auto MaxSlices = 1000000;

        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{InObstacles};

        auto Params = FBuildParams{};
        Params._VolumeBounds = InBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;
        Params._CellMerging = InCellMerging;

        auto Budget = FBuildBudget{};
        Budget._MaxOccupancyProbes = InMaxProbesPerSlice;

        // A wall-clock guard would make the slice count machine-dependent, and the slice count is one of the
        // numbers this file records.
        Budget._MaxSeconds = 0.0f;

        auto State = FBuildState{};

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceBuild(State, Params, Backend, Budget); }

        auto Outcome = FBakeOutcome{};

        Outcome._Stage = State.Get_Stage();
        Outcome._Stats = State.Get_Stats();
        Outcome._Octree = Request_ReleaseBuiltOctree(State);

        return Outcome;
    }

    struct FRepairOutcome
    {
        TSharedPtr<const ck::voxelnav::FOctree> _Octree;
        FCk_VoxelNav_RepairStats _Stats;
        ECk_VoxelNav_RepairStage _Stage = ECk_VoxelNav_RepairStage::NotStarted;
    };

    static auto
        Run_Repair(
            const TSharedPtr<const ck::voxelnav::FOctree>& InPublishedOctree,
            const TArray<FBox>& InObstaclesAfter,
            const FBox& InBounds,
            const FBox& InDirtyBounds,
            ECk_EnableDisable InCellMerging)
        -> FRepairOutcome
    {
        using namespace ck::voxelnav;

        constexpr auto MaxSlices = 1000000;

        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{InObstaclesAfter};

        auto Params = FRepairParams{};
        Params._VolumeBounds = InBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;
        Params._DirtyBounds = InDirtyBounds;
        Params._CellMerging = InCellMerging;

        auto Budget = FBuildBudget{};
        Budget._MaxOccupancyProbes = UnlimitedProbeBudget;
        Budget._MaxSeconds = 0.0f;

        auto State = FRepairState{};

        Request_BeginRepair(State, InPublishedOctree);

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceRepair(State, Params, Backend, Budget); }

        auto Outcome = FRepairOutcome{};

        Outcome._Stage = State.Get_Stage();
        Outcome._Stats = State.Get_Stats();
        Outcome._Octree = Request_ReleaseRepairedOctree(State);

        return Outcome;
    }

    // ----------------------------------------------------------------------------------------------------------------

    static auto
        Make_SearchParams(
            const FVector& InFrom,
            const FVector& InTo)
        -> ck::voxelnav::FPathSearchParams
    {
        auto Params = ck::voxelnav::FPathSearchParams{};

        Params._From = InFrom;
        Params._To = InTo;
        Params._MaxIterations = SearchIterationCap;

        return Params;
    }

    static auto
        Get_FreeCellCount(
            const ck::voxelnav::FOctree& InOctree)
        -> int32
    {
        auto Cells = TArray<ck::voxelnav::FNodeAddress>{};
        ck::voxelnav::Get_FreeCells(InOctree, Cells);

        return Cells.Num();
    }

    static auto
        Get_BoxVolume(
            const FBox& InBox)
        -> double
    {
        const auto Size = InBox.GetSize();

        return Size.X * Size.Y * Size.Z;
    }

    /** Every leg of the RAW route, against the octree the route was planned through. A merged route's legs
     *  are the ones this has to prove: a plain route's cell centres are provably inside their cells' union,
     *  while two merged boxes can share a small patch of a large face, which is what the transition points
     *  the seam emits are there to handle. */
    static auto
        Get_EveryLegIsUnblocked(
            const ck::voxelnav::FOctree& InOctree,
            const TArray<FVector>& InWaypoints)
        -> bool
    {
        for (auto WaypointIdx = 0; WaypointIdx + 1 < InWaypoints.Num(); ++WaypointIdx)
        {
            if (ck::voxelnav::Get_IsSegmentBlocked(InOctree, InWaypoints[WaypointIdx], InWaypoints[WaypointIdx + 1]))
            { return false; }
        }

        return true;
    }

    static auto
        Get_SearchSeconds(
            const ck::voxelnav::FOctree& InOctree,
            const ck::voxelnav::FPathSearchParams& InParams,
            int32 InRepeats,
            ck::voxelnav::FPathPlan& OutPlan)
        -> double
    {
        const auto StartSeconds = FPlatformTime::Seconds();

        for (auto Repeat = 0; Repeat < InRepeats; ++Repeat)
        { OutPlan = Search_PathGraph(InOctree, TestVolumeId, InParams); }

        return (FPlatformTime::Seconds() - StartSeconds) / static_cast<double>(InRepeats);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Merge_MergedCellsPartitionTheFreeCellSet,
    "Ck.VoxelNav.Merge.MergedCellsPartitionTheFreeCellSet",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Merge_MergedCellsPartitionTheFreeCellSet::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_merge;

    const auto Plain = Run_Bake(Make_KnownObstacles(), KnownVolumeBounds,
        ECk_EnableDisable::Disable, UnlimitedProbeBudget);
    const auto Merged = Run_Bake(Make_KnownObstacles(), KnownVolumeBounds,
        ECk_EnableDisable::Enable, UnlimitedProbeBudget);

    if (NOT TestTrue(TEXT("both bakes complete and publish an octree"),
        Plain._Octree.IsValid() && Merged._Octree.IsValid()))
    { return false; }

    TestFalse(TEXT("a bake with merging off carries no merged table at all"),
        Plain._Octree->Get_MergedCells().Get_IsMerged());

    const auto& Table = Merged._Octree->Get_MergedCells();

    if (NOT TestTrue(TEXT("a bake with merging on publishes a merged table"), Table.Get_IsMerged()))
    { return false; }

    auto FreeCells = TArray<FNodeAddress>{};
    Get_FreeCells(*Merged._Octree, FreeCells);

    TestEqual(TEXT("merging changes nothing about the octree's own cells - it only adds a table beside them"),
        FreeCells.Num(), Get_FreeCellCount(*Plain._Octree));

    TestEqual(TEXT("the table records the free-cell count it was handed"),
        Table.Get_SourceCellCount(), FreeCells.Num());

    TestEqual(TEXT("the bake's stats report the same A/B pair the table holds"),
        Merged._Stats.Get_PlainCellCount(), FreeCells.Num());
    TestEqual(TEXT("the bake's stats report the merged count"),
        Merged._Stats.Get_MergedCellCount(), Table.Get_CellCount());

    auto EveryCellIsMapped = true;
    auto EveryCellIsContained = true;
    auto CellVolume = 0.0;

    for (const auto& CellAddress : FreeCells)
    {
        const auto MergedIndex = Table.Get_MergedIndexForCell(CellAddress);
        const auto* MergedCell = Table.TryGet_Cell(MergedIndex);

        if (MergedCell == nullptr)
        {
            EveryCellIsMapped = false;
            continue;
        }

        const auto CellBounds = Get_NodeBoundsFromAddress(*Merged._Octree, CellAddress);

        CellVolume += Get_BoxVolume(CellBounds);

        EveryCellIsContained &=
            MergedCell->Get_Bounds().IsInsideOrOn(CellBounds.Min) &&
            MergedCell->Get_Bounds().IsInsideOrOn(CellBounds.Max);
    }

    TestTrue(TEXT("every free cell belongs to a merged cell - an unmapped cell is an endpoint that cannot "
                  "be resolved"), EveryCellIsMapped);
    TestTrue(TEXT("every free cell lies wholly inside the merged box that claims it"), EveryCellIsContained);

    auto MergedCellCountSum = 0;
    auto MergedVolume = 0.0;

    for (const auto& MergedCell : Table.Get_Cells())
    {
        MergedCellCountSum += MergedCell.Get_CellCount();
        MergedVolume += Get_BoxVolume(MergedCell.Get_Bounds());
    }

    TestEqual(TEXT("the merged cells' own counts add up to the whole free-cell set - no cell is claimed twice"),
        MergedCellCountSum, FreeCells.Num());

    // Every cell is inside a box AND the volumes agree, so the boxes tile the free space exactly: an overlap
    // would make the merged volume smaller than the cells', and a gap is impossible once every cell is in.
    constexpr auto VolumeToleranceUu3 = 1.0;

    TestTrue(TEXT("the merged boxes tile the free space exactly - no overlap"),
        FMath::IsNearlyEqual(MergedVolume, CellVolume, VolumeToleranceUu3));

    TestTrue(TEXT("merging reduces the cell count"), Table.Get_CellCount() < FreeCells.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Merge_MergedNeighborsAreSymmetricAndTouch,
    "Ck.VoxelNav.Merge.MergedNeighborsAreSymmetricAndTouch",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Merge_MergedNeighborsAreSymmetricAndTouch::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_merge;

    const auto Merged = Run_Bake(Make_KnownObstacles(), KnownVolumeBounds,
        ECk_EnableDisable::Enable, UnlimitedProbeBudget);

    if (NOT TestTrue(TEXT("the bake publishes a merged octree"),
        Merged._Octree.IsValid() && Merged._Octree->Get_MergedCells().Get_IsMerged()))
    { return false; }

    const auto& Table = Merged._Octree->Get_MergedCells();

    if (NOT TestTrue(TEXT("the table holds merged cells"), Table.Get_CellCount() > 0))
    { return false; }

    auto EveryEdgeIsSymmetric = true;
    auto EveryNeighborTouches = true;
    auto NoCellIsItsOwnNeighbor = true;
    auto AnyCellHasNeighbors = false;

    for (auto MergedIndex = 0; MergedIndex < Table.Get_CellCount(); ++MergedIndex)
    {
        const auto& MergedCell = Table.Get_Cells()[MergedIndex];

        AnyCellHasNeighbors |= MergedCell.Get_Neighbors().Num() > 0;

        for (const auto NeighbourIndex : MergedCell.Get_Neighbors())
        {
            const auto* Neighbour = Table.TryGet_Cell(NeighbourIndex);

            if (Neighbour == nullptr)
            {
                EveryEdgeIsSymmetric = false;
                continue;
            }

            NoCellIsItsOwnNeighbor &= NeighbourIndex != MergedIndex;
            EveryEdgeIsSymmetric &= Neighbour->Get_Neighbors().Contains(MergedIndex);
            EveryNeighborTouches &= MergedCell.Get_Bounds().Intersect(Neighbour->Get_Bounds());
        }
    }

    TestTrue(TEXT("the merged graph has edges at all"), AnyCellHasNeighbors);
    TestTrue(TEXT("no merged cell is its own neighbour"), NoCellIsItsOwnNeighbor);
    TestTrue(TEXT("every merged edge is walkable in both directions"), EveryEdgeIsSymmetric);
    TestTrue(TEXT("every merged neighbour's box touches its own"), EveryNeighborTouches);

    // The seam is what search sees, and it must hand back the same graph the table holds.
    const auto FirstCell = FCellId::Make_FromMergedIndex(TestVolumeId, 0);

    auto SeamNeighbors = TArray<FCellId>{};
    Get_CellNeighbors(*Merged._Octree, FirstCell, SeamNeighbors);

    TestEqual(TEXT("the cell seam enumerates a merged cell's own neighbours"),
        SeamNeighbors.Num(), Table.Get_Cells()[0].Get_Neighbors().Num());

    auto EverySeamNeighborIsMerged = true;

    for (const auto& SeamNeighbor : SeamNeighbors)
    { EverySeamNeighborIsMerged &= SeamNeighbor.Get_Kind() == ECellKind::Merged; }

    TestTrue(TEXT("a merged cell's neighbours are merged cells"), EverySeamNeighborIsMerged);

    TestTrue(TEXT("a merged cell reports free through the seam"),
        Get_CellIsFree(*Merged._Octree, FirstCell));

    TestTrue(TEXT("a merged cell's seam extent is its box's smallest half-extent"),
        FMath::IsNearlyEqual(
            Get_CellExtent(*Merged._Octree, FirstCell),
            Table.Get_Cells()[0].Get_MinExtent()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Merge_SearchOverMergedCellsStaysInFreeSpace,
    "Ck.VoxelNav.Merge.SearchOverMergedCellsStaysInFreeSpace",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Merge_SearchOverMergedCellsStaysInFreeSpace::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_merge;

    const auto Plain = Run_Bake(Make_KnownObstacles(), KnownVolumeBounds,
        ECk_EnableDisable::Disable, UnlimitedProbeBudget);
    const auto Merged = Run_Bake(Make_KnownObstacles(), KnownVolumeBounds,
        ECk_EnableDisable::Enable, UnlimitedProbeBudget);

    if (NOT TestTrue(TEXT("both bakes publish an octree"),
        Plain._Octree.IsValid() && Merged._Octree.IsValid()))
    { return false; }

    const auto SearchParams = Make_SearchParams(KnownRouteFrom, KnownRouteTo);

    const auto PlainPlan = Search_PathGraph(*Plain._Octree, TestVolumeId, SearchParams);
    const auto MergedPlan = Search_PathGraph(*Merged._Octree, TestVolumeId, SearchParams);

    if (NOT TestTrue(TEXT("the plain search finds the route"),
        PlainPlan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    if (NOT TestTrue(TEXT("the merged search finds the same route"),
        MergedPlan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    auto EveryCellIsMerged = true;

    for (const auto& Cell : MergedPlan._Cells)
    { EveryCellIsMerged &= Cell.Get_Kind() == ECellKind::Merged; }

    TestTrue(TEXT("a route over a merged octree is made of merged cells - the seam canonicalises the "
                  "endpoints into the merged space"), EveryCellIsMerged);

    TestTrue(TEXT("the merged route is no longer, in cells, than the plain one"),
        MergedPlan._Cells.Num() <= PlainPlan._Cells.Num());

    TestTrue(TEXT("the merged search costs no more expansions than the plain one"),
        MergedPlan._Iterations <= PlainPlan._Iterations);

    auto EveryCellIsFree = true;

    for (const auto& Cell : MergedPlan._Cells)
    { EveryCellIsFree &= Get_CellIsFree(*Merged._Octree, Cell); }

    TestTrue(TEXT("every cell of the merged route is free"), EveryCellIsFree);

    TestTrue(TEXT("every leg of the plain route is clear of the bake"),
        Get_EveryLegIsUnblocked(*Plain._Octree, PlainPlan._Waypoints));

    // The soundness statement for merging: a route between the centres of two large boxes could cut a
    // corner through geometry if the transition points were not emitted, and the ray-marcher is what proves
    // they were.
    TestTrue(TEXT("every leg of the merged route is clear of the bake"),
        Get_EveryLegIsUnblocked(*Merged._Octree, MergedPlan._Waypoints));

    TestEqual(TEXT("a plain route emits no transition points - its waypoints are still From, one centre per "
                   "cell, and To"),
        PlainPlan._Waypoints.Num(), PlainPlan._Cells.Num() + 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Merge_LocalRepairCarriesOverUntouchedMergedCells,
    "Ck.VoxelNav.Merge.LocalRepairCarriesOverUntouchedMergedCells",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Merge_LocalRepairCarriesOverUntouchedMergedCells::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_merge;

    // The same obstacle move the occluder tests use: one 90uu cube crossing from one leaf to another, in a
    // corner of the volume far from the floor slab that dominates the cell count.
    const auto ObstacleHalfExtents = FVector{45.0};
    const auto ObstacleCentreBefore = FVector{-700.0, -700.0, 700.0};
    const auto ObstacleCentreAfter = FVector{-300.0, -700.0, 700.0};

    const auto ObstacleBefore = FBox{
        ObstacleCentreBefore - ObstacleHalfExtents, ObstacleCentreBefore + ObstacleHalfExtents};
    const auto ObstacleAfter = FBox{
        ObstacleCentreAfter - ObstacleHalfExtents, ObstacleCentreAfter + ObstacleHalfExtents};

    const auto DirtyBounds = ObstacleBefore + ObstacleAfter;

    const auto Baked = Run_Bake(TArray<FBox>{KnownFloorSlab, ObstacleBefore}, KnownVolumeBounds,
        ECk_EnableDisable::Enable, UnlimitedProbeBudget);

    if (NOT TestTrue(TEXT("the bake publishes a merged octree"),
        Baked._Octree.IsValid() && Baked._Octree->Get_MergedCells().Get_IsMerged()))
    { return false; }

    const auto Repaired = Run_Repair(Baked._Octree, TArray<FBox>{KnownFloorSlab, ObstacleAfter},
        KnownVolumeBounds, DirtyBounds, ECk_EnableDisable::Enable);

    if (NOT TestTrue(TEXT("the repair completes and publishes an octree"),
        Repaired._Stage == ECk_VoxelNav_RepairStage::Complete && Repaired._Octree.IsValid()))
    { return false; }

    const auto& PublishedTable = Baked._Octree->Get_MergedCells();
    const auto& RepairedTable = Repaired._Octree->Get_MergedCells();

    if (NOT TestTrue(TEXT("the repaired octree publishes a merged table"), RepairedTable.Get_IsMerged()))
    { return false; }

    const auto CarriedOverCount = RepairedTable.Get_CarriedOverCount();

    TestEqual(TEXT("the repair's stats report what the table carried over"),
        Repaired._Stats.Get_MergedCellsCarriedOver(), CarriedOverCount);

    TestTrue(TEXT("a local repair carries merged boxes over rather than merging the whole volume again"),
        CarriedOverCount > 0);

    // The locality statement, and the merge half of the repair's own contract: what the obstacle never
    // reached is not re-derived, it is the SAME box.
    const auto ReDerivedCount = RepairedTable.Get_CellCount() - CarriedOverCount;

    const auto LocalityRow = FString::Printf(
        TEXT("VoxelNav local re-merge | carried over %d | re-derived %d | total %d | repair probes %d"),
        CarriedOverCount, ReDerivedCount, RepairedTable.Get_CellCount(),
        Repaired._Stats.Get_OccupancyProbes());

    AddInfo(LocalityRow);
    UE_LOG(LogTemp, Display, TEXT("%s"), *LocalityRow);

    // The contract, stated exactly rather than as a ratio: what the dirty bounds did not reach is carried
    // over, and it is the SAME box. A ratio would be pinning how coarse the merge happens to be - a table
    // of a dozen large boxes is easy for any dirty region to intersect, and that is a property of merging,
    // not a defect in the repair. This fixture bakes with zero clearance, so the repair's clearance-expanded
    // dirty bounds are the ones the test computes with.
    auto CarriedOverBoxesAreIdentical = true;
    auto ExpectedCarryOverCount = 0;

    for (const auto& PublishedCell : PublishedTable.Get_Cells())
    {
        if (PublishedCell.Get_Bounds().Intersect(DirtyBounds))
        { continue; }

        if (ExpectedCarryOverCount >= CarriedOverCount)
        {
            CarriedOverBoxesAreIdentical = false;
            break;
        }

        CarriedOverBoxesAreIdentical &=
            RepairedTable.Get_Cells()[ExpectedCarryOverCount].Get_Bounds() == PublishedCell.Get_Bounds();

        ++ExpectedCarryOverCount;
    }

    TestEqual(TEXT("every published merged box the dirty bounds never reached is carried over - nothing "
                   "clear of the obstacle is merged again"),
        CarriedOverCount, ExpectedCarryOverCount);

    TestTrue(TEXT("every carried-over merged box is bit-identical to the published one"),
        CarriedOverBoxesAreIdentical);

    // A carried-over table is worth nothing if it stopped being a partition of the repaired octree's cells.
    auto RepairedFreeCells = TArray<FNodeAddress>{};
    Get_FreeCells(*Repaired._Octree, RepairedFreeCells);

    auto EveryRepairedCellIsMapped = true;
    auto RepairedCellCountSum = 0;

    for (const auto& CellAddress : RepairedFreeCells)
    { EveryRepairedCellIsMapped &= RepairedTable.Get_MergedIndexForCell(CellAddress) != INDEX_NONE; }

    for (const auto& MergedCell : RepairedTable.Get_Cells())
    { RepairedCellCountSum += MergedCell.Get_CellCount(); }

    TestTrue(TEXT("every cell of the repaired octree still belongs to a merged cell"),
        EveryRepairedCellIsMapped);
    TestEqual(TEXT("the re-merged table still claims every cell exactly once"),
        RepairedCellCountSum, RepairedFreeCells.Num());

    // And a route still plans across the repaired representation.
    const auto Plan = Search_PathGraph(*Repaired._Octree, TestVolumeId,
        Make_SearchParams(KnownRouteFrom, KnownRouteTo));

    TestTrue(TEXT("a route still plans across the locally re-merged octree"),
        Plan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded);
    TestTrue(TEXT("every leg of that route is clear of the repaired bake"),
        Get_EveryLegIsUnblocked(*Repaired._Octree, Plan._Waypoints));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Merge_BenchmarkPlainVersusMergedOnReferenceScenes,
    "Ck.VoxelNav.Merge.BenchmarkPlainVersusMergedOnReferenceScenes",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Merge_BenchmarkPlainVersusMergedOnReferenceScenes::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_merge;

    struct FScene
    {
        FString _Name;
        TArray<FBox> _Obstacles;
        FBox _Bounds;
        TArray<FBenchmarkRoute> _Routes;

        // Enough repeats that a search too fast to time once produces a stable average, few enough that the
        // scene whose searches are measured in tens of milliseconds does not dominate the test's runtime.
        int32 _SearchRepeats = 1;
    };

    auto Scenes = TArray<FScene>{};

    Scenes.Emplace(FScene{
        TEXT("KnownLayout-1600uu/50uu"),
        Make_KnownObstacles(),
        KnownVolumeBounds,
        TArray<FBenchmarkRoute>{FBenchmarkRoute{KnownRouteFrom, KnownRouteTo}},
        16});

    Scenes.Emplace(FScene{
        TEXT("Generated-6400uu/50uu"),
        Make_LargeObstacles(),
        LargeVolumeBounds,
        Make_LargeRoutes(),
        2});

    constexpr auto SecondsToMilliseconds = 1000.0;

    auto EveryRouteSucceeds = true;
    auto EveryMergedRouteIsClear = true;
    auto EverySceneReducesCellCount = true;

    AddInfo(TEXT("VoxelNav merge A/B | scene | plain cells | merged cells | ratio | bake ms plain/merged | "
                 "merge ms | search ms plain/merged | budget frames plain/merged"));

    for (const auto& Scene : Scenes)
    {
        const auto PlainBakeStart = FPlatformTime::Seconds();
        const auto Plain = Run_Bake(Scene._Obstacles, Scene._Bounds,
            ECk_EnableDisable::Disable, UnlimitedProbeBudget);
        const auto PlainBakeSeconds = FPlatformTime::Seconds() - PlainBakeStart;

        const auto MergedBakeStart = FPlatformTime::Seconds();
        const auto Merged = Run_Bake(Scene._Obstacles, Scene._Bounds,
            ECk_EnableDisable::Enable, UnlimitedProbeBudget);
        const auto MergedBakeSeconds = FPlatformTime::Seconds() - MergedBakeStart;

        if (NOT TestTrue(FString::Printf(TEXT("[%s] both bakes publish an octree"), *Scene._Name),
            Plain._Octree.IsValid() && Merged._Octree.IsValid()))
        { return false; }

        // The budgeted runs are what the frame counts come from: the same bake, sliced by the shipped
        // per-tick probe budget.
        const auto PlainBudgeted = Run_Bake(Scene._Obstacles, Scene._Bounds,
            ECk_EnableDisable::Disable, DefaultProbeBudgetPerTick);
        const auto MergedBudgeted = Run_Bake(Scene._Obstacles, Scene._Bounds,
            ECk_EnableDisable::Enable, DefaultProbeBudgetPerTick);

        const auto PlainCellCount = Get_FreeCellCount(*Plain._Octree);
        const auto MergedCellCount = Merged._Octree->Get_MergedCells().Get_CellCount();

        EverySceneReducesCellCount &= MergedCellCount * 100 <= PlainCellCount * MaxMergedPercentOfPlain;

        auto PlainSearchMilliseconds = 0.0;
        auto MergedSearchMilliseconds = 0.0;
        auto PlainRouteCells = 0;
        auto MergedRouteCells = 0;

        for (const auto& Route : Scene._Routes)
        {
            const auto SearchParams = Make_SearchParams(Route._From, Route._To);

            auto PlainPlan = FPathPlan{};
            auto MergedPlan = FPathPlan{};

            PlainSearchMilliseconds +=
                Get_SearchSeconds(*Plain._Octree, SearchParams, Scene._SearchRepeats,PlainPlan) * SecondsToMilliseconds;
            MergedSearchMilliseconds +=
                Get_SearchSeconds(*Merged._Octree, SearchParams, Scene._SearchRepeats,MergedPlan) * SecondsToMilliseconds;

            EveryRouteSucceeds &=
                PlainPlan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded &&
                MergedPlan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded;

            EveryMergedRouteIsClear &= Get_EveryLegIsUnblocked(*Merged._Octree, MergedPlan._Waypoints);

            PlainRouteCells += PlainPlan._Cells.Num();
            MergedRouteCells += MergedPlan._Cells.Num();
        }

        const auto Row = FString::Printf(
            TEXT("VoxelNav merge A/B | %s | plain %d | merged %d | ratio %.2fx | bake %.1f/%.1f ms | "
                 "merge %.1f ms | search %.3f/%.3f ms | frames %d/%d | route cells %d/%d | probes %d"),
            *Scene._Name,
            PlainCellCount,
            MergedCellCount,
            MergedCellCount > 0 ? static_cast<double>(PlainCellCount) / static_cast<double>(MergedCellCount) : 0.0,
            PlainBakeSeconds * SecondsToMilliseconds,
            MergedBakeSeconds * SecondsToMilliseconds,
            Merged._Stats.Get_MergeSeconds() * SecondsToMilliseconds,
            PlainSearchMilliseconds,
            MergedSearchMilliseconds,
            PlainBudgeted._Stats.Get_Slices(),
            MergedBudgeted._Stats.Get_Slices(),
            PlainRouteCells,
            MergedRouteCells,
            Plain._Stats.Get_OccupancyProbes());

        AddInfo(Row);
        UE_LOG(LogTemp, Display, TEXT("%s"), *Row);
    }

    TestTrue(TEXT("every benchmark route plans in both representations"), EveryRouteSucceeds);
    TestTrue(TEXT("every merged benchmark route is clear of its bake"), EveryMergedRouteIsClear);
    TestTrue(TEXT("merging reduces the cell count on every reference scene"), EverySceneReducesCellCount);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
