#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Chunk/CkVoxelNav_Chunk_Adjacency.h"
#include "CkVoxelNav/Chunk/CkVoxelNav_Chunk_Search.h"
#include "CkVoxelNav/Chunk/CkVoxelNav_Chunk_Types.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Raycast.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Repair.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"
#include "CkVoxelNav/Path/CkVoxelNav_Path_Graph.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Chunked volumes, hermetic: the partition math, the adjacency bake over two chunks, a route that crosses
// between them, and the locality of a chunk-local repair. No world, no physics, no PIE - both chunks bake
// through the stub geometry backend and every expected box is computable by hand.
//
// THE FIXTURE, and why its numbers are exact rather than approximate:
//   A volume 3200 x 1600 x 1600, split at a 1600uu max chunk size into TWO 1600uu cubes meeting at x = 0.
//   1600 / 50 = 32 = 2^5, so each chunk's octree cube is exactly its authored box - the power-of-two snap
//   adds no padding at all, and the two bakes abut on the plane the adjacency is looking for rather than
//   overlapping in a region of padded space.
//
//   The only geometry is a floor slab spanning both chunks, 145uu thick, whose top at z = -655 falls INSIDE
//   a 50uu sub-node row rather than on its boundary: FBox::Intersect counts a shared face as an
//   intersection, so a slab ending exactly on a row boundary would occlude the row above it too and every
//   count below would be asserting a tie-break.
//
//   With only a floor, each chunk's upper half is un-subdivided free space addressed at layer 2 (800uu
//   cells) - so the cross-chunk route below crosses coarse cells on both sides and the crossing is the only
//   thing that can produce a boundary, which is exactly what these tests are about.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_chunk
{
    constexpr auto FinestCellSizeUu = 50.0f;
    constexpr auto MaxChunkSizeUu = 1600.0f;
    constexpr auto MaxChunksPerAxis = 8;

    constexpr auto UnlimitedProbeBudget = 1000000;
    constexpr auto SearchIterationCap = 200000;

    const auto VolumeBounds = FBox{FVector{-1600.0, -800.0, -800.0}, FVector{1600.0, 800.0, 800.0}};

    // Hand-computed: ceil(3200/1600) = 2 divisions on X, 1 on Y and Z, chunks 1600uu on every axis, and the
    // last chunk on each axis snapped back onto the authored bound.
    const auto ExpectedChunk0Bounds = FBox{FVector{-1600.0, -800.0, -800.0}, FVector{   0.0, 800.0, 800.0}};
    const auto ExpectedChunk1Bounds = FBox{FVector{    0.0, -800.0, -800.0}, FVector{1600.0, 800.0, 800.0}};

    const auto FloorSlab = FBox{FVector{-1700.0, -900.0, -800.0}, FVector{1700.0, 900.0, -655.0}};

    // Opposite upper corners, one per chunk, each well inside a free layer-2 cell.
    const auto RouteFrom = FVector{-1400.0, -600.0, 600.0};
    const auto RouteTo = FVector{ 1400.0,  600.0, 600.0};

    // Deep inside chunk 0 and far from the shared face, so a repair there cannot change a boundary cell.
    const auto RepairObstacle = FBox{FVector{-1300.0, -700.0, 500.0}, FVector{-1200.0, -600.0, 600.0}};

    const auto TestVolumeId = ck::voxelnav::FVolumeId{7};

    // Distinct per chunk, which is what keeps a cell of one chunk from ever comparing equal to a cell of
    // another. The values themselves carry no meaning beyond that.
    const auto Chunk0CellVolumeId = ck::voxelnav::FVolumeId{101};
    const auto Chunk1CellVolumeId = ck::voxelnav::FVolumeId{102};

    // ----------------------------------------------------------------------------------------------------------------

    static auto
        Make_PartitionParams(
            const FBox& InBounds,
            float InMaxChunkSizeUu)
        -> ck::voxelnav::FChunkPartitionParams
    {
        auto Params = ck::voxelnav::FChunkPartitionParams{};

        Params._VolumeBounds = InBounds;
        Params._MaxChunkSizeUu = InMaxChunkSizeUu;
        Params._MaxChunksPerAxis = MaxChunksPerAxis;

        return Params;
    }

    static auto
        Bake_Octree(
            const FBox& InBounds,
            const TArray<FBox>& InObstacles)
        -> TSharedPtr<const ck::voxelnav::FOctree>
    {
        using namespace ck::voxelnav;

        // Generous enough that a working machine never reaches it, small enough that a machine that stops
        // making progress fails the test instead of hanging the run.
        constexpr auto MaxSlices = 100000;

        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{InObstacles};

        auto Params = FBuildParams{};
        Params._VolumeBounds = InBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;

        auto Budget = FBuildBudget{};
        Budget._MaxOccupancyProbes = UnlimitedProbeBudget;
        Budget._MaxSeconds = 0.0f;

        auto State = FBuildState{};

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceBuild(State, Params, Backend, Budget); }

        return Request_ReleaseBuiltOctree(State);
    }

    static auto
        Make_ChunkSearchInputs(
            const TArray<FBox>& InObstacles)
        -> TArray<ck::voxelnav::FChunkSearchInput>
    {
        using namespace ck::voxelnav;

        auto Chunks = TArray<FChunkSearchInput>{};

        const auto CellVolumeIds = TArray<FVolumeId>{Chunk0CellVolumeId, Chunk1CellVolumeId};
        const auto ChunkBounds = TArray<FBox>{ExpectedChunk0Bounds, ExpectedChunk1Bounds};

        for (auto ChunkIdx = 0; ChunkIdx < ChunkBounds.Num(); ++ChunkIdx)
        {
            auto Chunk = FChunkSearchInput{};

            Chunk._ChunkId = FChunkId{TestVolumeId, ChunkIdx};
            Chunk._CellVolumeId = CellVolumeIds[ChunkIdx];
            Chunk._Bounds = ChunkBounds[ChunkIdx];
            Chunk._Octree = Bake_Octree(ChunkBounds[ChunkIdx], InObstacles);

            Chunks.Emplace(MoveTemp(Chunk));
        }

        return Chunks;
    }

    static auto
        Make_AdjacencyInputs(
            const TArray<ck::voxelnav::FChunkSearchInput>& InChunks)
        -> TArray<ck::voxelnav::FChunkAdjacencyInput>
    {
        auto Inputs = TArray<ck::voxelnav::FChunkAdjacencyInput>{};

        for (const auto& Chunk : InChunks)
        {
            auto Input = ck::voxelnav::FChunkAdjacencyInput{};

            Input._ChunkId = Chunk._ChunkId;
            Input._Bounds = Chunk._Bounds;
            Input._Octree = Chunk._Octree.Get();

            Inputs.Emplace(Input);
        }

        return Inputs;
    }

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

    /** Leaf occupancy keyed by the leaf's MORTON code rather than its array index: index is a position in an
     *  array a rebuild reshuffles, Morton code is the leaf's identity, and only identity can express "this
     *  leaf was left alone". */
    static auto
        Get_LeafOccupancyByMorton(
            const ck::voxelnav::FOctree& InOctree)
        -> TMap<ck::voxelnav::MortonCode, uint64>
    {
        using namespace ck::voxelnav;

        auto Occupancy = TMap<MortonCode, uint64>{};

        if (InOctree.Get_LayerCount() == 0)
        { return Occupancy; }

        const auto& LeafLayer = InOctree.Get_Layer(0);
        const auto& Leaves = InOctree.Get_LeafNodes().Get_LeafNodes();

        for (auto NodeIdx = 0; NodeIdx < LeafLayer.Get_NodeCount(); ++NodeIdx)
        {
            if (NOT Leaves.IsValidIndex(NodeIdx))
            { continue; }

            Occupancy.Emplace(LeafLayer.Get_Node(NodeIdx).Get_MortonCode(), Leaves[NodeIdx].Get_SubNodes());
        }

        return Occupancy;
    }

    static auto
        Get_SegmentIsClearInChunk(
            const ck::voxelnav::FChunkSearchInput& InChunk,
            const FVector& InFrom,
            const FVector& InTo)
        -> bool
    {
        return NOT ck::voxelnav::Get_IsSegmentBlocked(*InChunk._Octree, InFrom, InTo);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Chunk_PartitionSplitsOversizedVolume,
    "Ck.VoxelNav.Chunk.Partition.SplitsOversizedVolumeIntoHandComputedChunks",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Chunk_PartitionSplitsOversizedVolume::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_chunk;

    const auto Partition = Get_ChunkPartition(Make_PartitionParams(VolumeBounds, MaxChunkSizeUu));

    if (NOT TestTrue(TEXT("a volume twice the chunk size on one axis partitions"),
        Partition.Get_IsPartitioned()))
    { return false; }

    TestTrue(TEXT("the volume splits on X only - the other two axes already fit"),
        Partition.Get_Divisions() == FIntVector{2, 1, 1});

    if (NOT TestEqual(TEXT("two divisions produce two chunks"), Partition.Get_ChunkCount(), 2))
    { return false; }

    TestTrue(TEXT("chunk 0 is the lower-X half, hand-computed"),
        Partition.Get_ChunkBounds(0).Min.Equals(ExpectedChunk0Bounds.Min, 0.01) &&
        Partition.Get_ChunkBounds(0).Max.Equals(ExpectedChunk0Bounds.Max, 0.01));

    TestTrue(TEXT("chunk 1 is the upper-X half, hand-computed"),
        Partition.Get_ChunkBounds(1).Min.Equals(ExpectedChunk1Bounds.Min, 0.01) &&
        Partition.Get_ChunkBounds(1).Max.Equals(ExpectedChunk1Bounds.Max, 0.01));

    // The last chunk on an axis is SNAPPED onto the authored bound rather than accumulated, so no sliver of
    // the volume is left outside every chunk.
    TestTrue(TEXT("the chunks together cover the whole authored volume"),
        (Partition.Get_ChunkBounds(0) + Partition.Get_ChunkBounds(1)).Min.Equals(VolumeBounds.Min, 0.01) &&
        (Partition.Get_ChunkBounds(0) + Partition.Get_ChunkBounds(1)).Max.Equals(VolumeBounds.Max, 0.01));

    TestTrue(TEXT("lattice order round-trips: chunk 1 is coordinate (1,0,0)"),
        Get_ChunkCoordFromIndex(Partition.Get_Divisions(), 1) == FIntVector{1, 0, 0});

    TestEqual(TEXT("and back again"),
        Get_ChunkIndexFromCoord(Partition.Get_Divisions(), FIntVector{1, 0, 0}), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Chunk_PartitionLeavesFittingVolumeWhole,
    "Ck.VoxelNav.Chunk.Partition.LeavesFittingVolumeWhole",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Chunk_PartitionLeavesFittingVolumeWhole::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_chunk;

    // Exactly the existing single-volume fixture size, at exactly the chunk size: the boundary case that
    // every existing VoxelNav test depends on NOT partitioning.
    const auto Partition = Get_ChunkPartition(
        Make_PartitionParams(ExpectedChunk0Bounds, MaxChunkSizeUu));

    TestFalse(TEXT("a volume that fits inside one chunk does not partition"), Partition.Get_IsPartitioned());

    if (NOT TestEqual(TEXT("it yields exactly one chunk"), Partition.Get_ChunkCount(), 1))
    { return false; }

    TestTrue(TEXT("and that chunk IS the authored volume, unchanged"),
        Partition.Get_ChunkBounds(0).Min.Equals(ExpectedChunk0Bounds.Min, 0.01) &&
        Partition.Get_ChunkBounds(0).Max.Equals(ExpectedChunk0Bounds.Max, 0.01));

    // Degenerate input must also refuse to partition rather than divide by a zero-sized axis.
    const auto DegeneratePartition = Get_ChunkPartition(Make_PartitionParams(FBox{ForceInit}, MaxChunkSizeUu));

    TestFalse(TEXT("degenerate bounds do not partition"), DegeneratePartition.Get_IsPartitioned());

    const auto ZeroSizePartition = Get_ChunkPartition(Make_PartitionParams(VolumeBounds, 0.0f));

    TestFalse(TEXT("a zero max chunk size does not partition - refusing is always a legal answer"),
        ZeroSizePartition.Get_IsPartitioned());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Chunk_AdjacencyFindsSharedFacePortals,
    "Ck.VoxelNav.Chunk.Adjacency.FindsSharedFacePortals",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Chunk_AdjacencyFindsSharedFacePortals::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_chunk;

    const auto Chunks = Make_ChunkSearchInputs(TArray<FBox>{FloorSlab});

    if (NOT TestTrue(TEXT("both chunks bake a valid octree"),
        Chunks[0]._Octree.IsValid() && Chunks[0]._Octree->Get_IsValid() &&
        Chunks[1]._Octree.IsValid() && Chunks[1]._Octree->Get_IsValid()))
    { return false; }

    // 1600 / 50 = 32 = 2^5 exactly, so the power-of-two snap adds no padding and the two bakes abut on the
    // plane the adjacency is looking for.
    TestTrue(TEXT("chunk 0's octree cube is exactly its authored box"),
        Chunks[0]._Octree->Get_NavigationBounds().Min.Equals(ExpectedChunk0Bounds.Min, 0.01) &&
        Chunks[0]._Octree->Get_NavigationBounds().Max.Equals(ExpectedChunk0Bounds.Max, 0.01));

    const auto Adjacency = Bake_ChunkAdjacency(Make_AdjacencyInputs(Chunks));

    if (NOT TestTrue(TEXT("the two chunks are found adjacent"), Adjacency.Get_AreChunksAdjacent(0, 1)))
    { return false; }

    TestTrue(TEXT("adjacency is symmetric - a search never has to know which side baked the pair"),
        Adjacency.Get_AreChunksAdjacent(1, 0));

    TestEqual(TEXT("both chunks appear in the neighbour graph"), Adjacency.Get_ConnectedChunkCount(), 2);

    const auto ForwardPortals = Adjacency.Get_Portals(0, 1);

    if (NOT TestTrue(TEXT("crossings were found"), ForwardPortals.Num() > 0))
    { return false; }

    TestEqual(TEXT("every forward crossing has a reverse twin"),
        Adjacency.Get_Portals(1, 0).Num(), ForwardPortals.Num());

    constexpr auto SharedFacePlaneX = 0.0;
    constexpr auto PlaneToleranceUu = 0.01;

    auto PortalsOffThePlane = 0;
    auto PortalsNamingABlockedCell = 0;
    auto PortalsOutsideTheirOwnCells = 0;
    auto PortalsNamingTheWrongChunk = 0;

    for (const auto& Portal : ForwardPortals)
    {
        if (FMath::Abs(Portal._ConnectionPoint.X - SharedFacePlaneX) > PlaneToleranceUu)
        { ++PortalsOffThePlane; }

        if (Portal._FromChunk.Get_Index() != 0 || Portal._ToChunk.Get_Index() != 1 ||
            NOT (Portal._FromChunk.Get_Volume() == TestVolumeId))
        { ++PortalsNamingTheWrongChunk; }

        const auto FromCell = FCellId::Make_FromNodeAddress(Chunks[0]._CellVolumeId, Portal.Get_FromCellAddress());
        const auto ToCell = FCellId::Make_FromNodeAddress(Chunks[1]._CellVolumeId, Portal.Get_ToCellAddress());

        if (NOT Get_CellIsFree(*Chunks[0]._Octree, FromCell) ||
            NOT Get_CellIsFree(*Chunks[1]._Octree, ToCell))
        { ++PortalsNamingABlockedCell; }

        // The connection point is CLAMPED into the span both cells cover, which upstream's raw midpoint was
        // not: two cells of different sizes can overlap on a face without their centres' midpoint being
        // inside either of them.
        const auto FromBox = FBox::BuildAABB(
            Get_CellCenter(*Chunks[0]._Octree, FromCell),
            FVector{static_cast<double>(Get_CellExtent(*Chunks[0]._Octree, FromCell))});

        const auto ToBox = FBox::BuildAABB(
            Get_CellCenter(*Chunks[1]._Octree, ToCell),
            FVector{static_cast<double>(Get_CellExtent(*Chunks[1]._Octree, ToCell))});

        if (NOT FromBox.ExpandBy(PlaneToleranceUu).IsInsideOrOn(Portal._ConnectionPoint) ||
            NOT ToBox.ExpandBy(PlaneToleranceUu).IsInsideOrOn(Portal._ConnectionPoint))
        { ++PortalsOutsideTheirOwnCells; }
    }

    TestEqual(TEXT("every crossing sits on the shared face plane"), PortalsOffThePlane, 0);
    TestEqual(TEXT("every crossing names its own chunks by stable id"), PortalsNamingTheWrongChunk, 0);
    TestEqual(TEXT("every crossing names a FREE cell on both sides"), PortalsNamingABlockedCell, 0);
    TestEqual(TEXT("every crossing point lies inside both of the cells it joins"), PortalsOutsideTheirOwnCells, 0);

    // A chunk is never its own neighbour, and there is no third chunk to reach.
    TestFalse(TEXT("a chunk is not adjacent to itself"), Adjacency.Get_AreChunksAdjacent(0, 0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Chunk_SearchFindsRouteAcrossBoundary,
    "Ck.VoxelNav.Chunk.Search.FindsRouteAcrossChunkBoundary",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Chunk_SearchFindsRouteAcrossBoundary::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_chunk;

    const auto Chunks = Make_ChunkSearchInputs(TArray<FBox>{FloorSlab});
    const auto Adjacency = Bake_ChunkAdjacency(Make_AdjacencyInputs(Chunks));

    TestEqual(TEXT("the start point resolves to the chunk that contains it, in 3D"),
        TryGet_ChunkIndexContainingPoint(Chunks, RouteFrom), 0);
    TestEqual(TEXT("and the goal to the other one"),
        TryGet_ChunkIndexContainingPoint(Chunks, RouteTo), 1);

    auto ChunkPath = TArray<int32>{};

    if (NOT TestTrue(TEXT("BFS finds a chunk route"), Get_ChunkPath(Adjacency, 0, 1, ChunkPath)))
    { return false; }

    TestEqual(TEXT("two face-adjacent chunks are one crossing apart"), ChunkPath.Num(), 2);

    const auto Plan = Search_ChunkedPathGraph(Chunks, Adjacency, Make_SearchParams(RouteFrom, RouteTo));

    if (NOT TestTrue(TEXT("a route across the chunk boundary is found"),
        Plan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    if (NOT TestEqual(TEXT("the route is one segment per chunk it crosses"), Plan._Segments.Num(), 2))
    { return false; }

    if (NOT TestEqual(TEXT("and one crossing between them"), Plan._Portals.Num(), 1))
    { return false; }

    TestEqual(TEXT("segment 0 belongs to chunk 0"), Plan._Segments[0]._ChunkIndex, 0);
    TestEqual(TEXT("segment 1 belongs to chunk 1"), Plan._Segments[1]._ChunkIndex, 1);

    TestTrue(TEXT("the route starts at the requested start"),
        Plan._Waypoints[0].Equals(RouteFrom, 0.01));
    TestTrue(TEXT("and ends at the requested goal"),
        Plan._Waypoints.Last().Equals(RouteTo, 0.01));

    // EVERY segment is checked against ITS OWN chunk's octree. There is no structure that could answer for
    // a span reaching across the boundary, which is exactly why the route is planned and refined per chunk.
    auto BlockedSpans = 0;

    for (const auto& Segment : Plan._Segments)
    {
        for (auto WaypointIdx = 1; WaypointIdx < Segment._Waypoints.Num(); ++WaypointIdx)
        {
            if (NOT Get_SegmentIsClearInChunk(Chunks[Segment._ChunkIndex],
                Segment._Waypoints[WaypointIdx - 1], Segment._Waypoints[WaypointIdx]))
            { ++BlockedSpans; }
        }
    }

    TestEqual(TEXT("every span of every segment is clear per its own chunk's bake"), BlockedSpans, 0);

    // The crossing the route took is one the adjacency baked - not a point the search invented.
    const auto& TakenPortal = Plan._Portals[0];
    const auto PortalIsFromTheTable = Adjacency.Get_Portals(0, 1).ContainsByPredicate(
        [&](const FChunkPortal& InPortal) -> bool
        {
            return InPortal._FromCellPacked == TakenPortal._FromCellPacked &&
                   InPortal._ToCellPacked == TakenPortal._ToCellPacked;
        });

    TestTrue(TEXT("the crossing taken is one the adjacency bake produced"), PortalIsFromTheTable);

    if (NOT TestTrue(TEXT("both segments reached at least one cell"),
        Plan._Segments[0]._Cells.Num() > 0 && Plan._Segments[1]._Cells.Num() > 0))
    { return false; }

    // The transition cells ARE the portal's. A segment ends at its portal cell's CENTRE precisely so this
    // holds: a cell centre resolves back to that same cell.
    TestTrue(TEXT("the last cell of segment 0 is the crossing's near-side cell"),
        Get_CellAddressesNameSameCell(*Chunks[0]._Octree,
            Plan._Segments[0]._Cells.Last().Get_NodeAddress(), TakenPortal.Get_FromCellAddress()));

    TestTrue(TEXT("the first cell of segment 1 is the crossing's far-side cell"),
        Get_CellAddressesNameSameCell(*Chunks[1]._Octree,
            Plan._Segments[1]._Cells[0].Get_NodeAddress(), TakenPortal.Get_ToCellAddress()));

    // Cells of different chunks carry different volume qualifiers, so no cell of one can ever compare equal
    // to a cell of the other - which is what stops a stitched route from closing a loop it never walked.
    TestTrue(TEXT("segment cells stay qualified by their own chunk"),
        Plan._Segments[0]._Cells[0].Get_Volume() == Chunk0CellVolumeId &&
        Plan._Segments[1]._Cells[0].Get_Volume() == Chunk1CellVolumeId);

    // Refinement is per segment by necessity, and the crossing waypoints survive it.
    auto RefineParams = FPathRefineParams{};
    RefineParams._VisibilityPruning = ECk_EnableDisable::Enable;

    const auto Refined = Refine_ChunkedWaypoints(Chunks, Plan, RefineParams);

    TestEqual(TEXT("refinement reports the stitched route it was handed as the raw one"),
        Refined._RawWaypointCount, Plan._Waypoints.Num());

    TestTrue(TEXT("refinement never lengthens the route"),
        Refined._RefinedLengthUu <= Refined._RawLengthUu + 0.01f);

    TestTrue(TEXT("the refined route still starts and ends where it was asked to"),
        Refined._Waypoints[0].Equals(RouteFrom, 0.01) && Refined._Waypoints.Last().Equals(RouteTo, 0.01));

    TestTrue(TEXT("the crossing point survives refinement - no octree can prove a span across it"),
        Refined._Waypoints.ContainsByPredicate([&](const FVector& InWaypoint) -> bool
        { return InWaypoint.Equals(TakenPortal._ConnectionPoint, 0.01); }));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Chunk_SearchOverOneChunkMatchesUnpartitioned,
    "Ck.VoxelNav.Chunk.Search.SingleChunkMatchesUnpartitionedSearch",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Chunk_SearchOverOneChunkMatchesUnpartitioned::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_chunk;

    // The degenerate case that pins "unpartitioned behaves exactly as before": one chunk, no crossings, and
    // the chunked seam must come back with what the single-octree search would have produced on its own.
    const auto Octree = Bake_Octree(ExpectedChunk0Bounds, TArray<FBox>{FloorSlab});

    if (NOT TestTrue(TEXT("the fixture bakes"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    auto SoleChunk = FChunkSearchInput{};

    SoleChunk._ChunkId = FChunkId{TestVolumeId, 0};
    SoleChunk._CellVolumeId = Chunk0CellVolumeId;
    SoleChunk._Bounds = ExpectedChunk0Bounds;
    SoleChunk._Octree = Octree;

    const auto Chunks = TArray<FChunkSearchInput>{SoleChunk};

    const auto GoalInSameChunk = FVector{-200.0, 600.0, 600.0};

    const auto Direct = Search_PathGraph(*Octree, Chunk0CellVolumeId,
        Make_SearchParams(RouteFrom, GoalInSameChunk));

    const auto Chunked = Search_ChunkedPathGraph(Chunks, FChunkAdjacencyTable{},
        Make_SearchParams(RouteFrom, GoalInSameChunk));

    if (NOT TestTrue(TEXT("the single-octree search finds a route"),
        Direct._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    if (NOT TestTrue(TEXT("so does the chunked seam over one chunk"),
        Chunked._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    TestEqual(TEXT("one chunk means one segment and no crossing"), Chunked._Segments.Num(), 1);
    TestEqual(TEXT("and no portal was taken"), Chunked._Portals.Num(), 0);

    if (NOT TestEqual(TEXT("the chunked route has the same waypoint count"),
        Chunked._Waypoints.Num(), Direct._Waypoints.Num()))
    { return false; }

    auto DivergentWaypoints = 0;

    for (auto WaypointIdx = 0; WaypointIdx < Direct._Waypoints.Num(); ++WaypointIdx)
    {
        if (NOT Chunked._Waypoints[WaypointIdx].Equals(Direct._Waypoints[WaypointIdx], 0.01))
        { ++DivergentWaypoints; }
    }

    TestEqual(TEXT("and the identical waypoints - the chunked seam adds nothing when there is one chunk"),
        DivergentWaypoints, 0);

    TestEqual(TEXT("the same cells, too"), Chunked._Segments[0]._Cells.Num(), Direct._Cells.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Chunk_RepairIsLocalToItsChunk,
    "Ck.VoxelNav.Chunk.Repair.LocalRepairLeavesOtherChunkUntouched",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Chunk_RepairIsLocalToItsChunk::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_chunk;

    const auto Chunks = Make_ChunkSearchInputs(TArray<FBox>{FloorSlab});
    const auto AdjacencyBefore = Bake_ChunkAdjacency(Make_AdjacencyInputs(Chunks));

    if (NOT TestTrue(TEXT("both chunks bake"),
        Chunks[0]._Octree.IsValid() && Chunks[1]._Octree.IsValid()))
    { return false; }

    const auto Chunk1OccupancyBefore = Get_LeafOccupancyByMorton(*Chunks[1]._Octree);
    const auto* Chunk1OctreeBefore = Chunks[1]._Octree.Get();

    // An obstacle APPEARS deep inside chunk 0, far from the shared face.
    auto RepairState = FRepairState{};

    if (NOT TestTrue(TEXT("a repair opens against the published chunk-0 bake"),
        Request_BeginRepair(RepairState, Chunks[0]._Octree)))
    { return false; }

    const auto RepairBackend = FCk_VoxelNav_GeometryBackend_Stub{TArray<FBox>{FloorSlab, RepairObstacle}};

    auto RepairParams = FRepairParams{};
    RepairParams._VolumeBounds = ExpectedChunk0Bounds;
    RepairParams._FinestCellSizeUu = FinestCellSizeUu;
    RepairParams._DirtyBounds = RepairObstacle;

    auto RepairBudget = FBuildBudget{};
    RepairBudget._MaxOccupancyProbes = UnlimitedProbeBudget;
    RepairBudget._MaxSeconds = 0.0f;

    constexpr auto MaxSlices = 100000;

    for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT RepairState.Get_IsFinished(); ++SliceIdx)
    { Request_AdvanceRepair(RepairState, RepairParams, RepairBackend, RepairBudget); }

    if (NOT TestTrue(TEXT("the repair completes"),
        RepairState.Get_Stage() == ECk_VoxelNav_RepairStage::Complete))
    { return false; }

    const auto RepairedChunk0 = Request_ReleaseRepairedOctree(RepairState);

    if (NOT TestTrue(TEXT("the repair publishes a valid replacement for chunk 0"),
        RepairedChunk0.IsValid() && RepairedChunk0->Get_IsValid()))
    { return false; }

    TestTrue(TEXT("the repair actually changed something in chunk 0"),
        RepairState.Get_Stats().Get_LeavesChanged() > 0);

    TestFalse(TEXT("the point the obstacle arrived at is no longer free in chunk 0"),
        Get_IsPositionFree(*RepairedChunk0, RepairObstacle.GetCenter()));

    // A repair assembles a NEW octree and swaps it in; chunk 1 was never handed to it and is not merely
    // equal to what it was, it is the same structure.
    TestTrue(TEXT("chunk 1's published octree is the very same object"),
        Chunks[1]._Octree.Get() == Chunk1OctreeBefore);

    const auto Chunk1OccupancyAfter = Get_LeafOccupancyByMorton(*Chunks[1]._Octree);

    if (NOT TestEqual(TEXT("chunk 1 still holds the same leaves"),
        Chunk1OccupancyAfter.Num(), Chunk1OccupancyBefore.Num()))
    { return false; }

    auto DivergentLeaves = 0;

    for (const auto& Kvp : Chunk1OccupancyBefore)
    {
        const auto* After = Chunk1OccupancyAfter.Find(Kvp.Key);

        if (After == nullptr || *After != Kvp.Value)
        { ++DivergentLeaves; }
    }

    TestEqual(TEXT("and every one of them bit for bit"), DivergentLeaves, 0);

    // The volume's own epoch is driven by the COMBINED chunk epoch, so one chunk republishing is enough to
    // make every path planned against the volume stale - and nothing else is.
    const auto EpochsBefore = TArray<FChunkPublishState>
    {
        FChunkPublishState{Chunks[0]._ChunkId, true, 1},
        FChunkPublishState{Chunks[1]._ChunkId, true, 1}
    };

    const auto AggregatedSum = Get_ChunkEpochSum(EpochsBefore);

    TestFalse(TEXT("a volume whose chunks have not moved does not re-aggregate"),
        Get_ChunksNeedAggregation(EpochsBefore, AggregatedSum));

    const auto EpochsAfterChunk0Repair = TArray<FChunkPublishState>
    {
        FChunkPublishState{Chunks[0]._ChunkId, true, 2},
        FChunkPublishState{Chunks[1]._ChunkId, true, 1}
    };

    TestTrue(TEXT("one chunk repairing makes the volume re-aggregate and bump its own epoch"),
        Get_ChunksNeedAggregation(EpochsAfterChunk0Repair, AggregatedSum));

    const auto EpochsWithUnbuiltChunk = TArray<FChunkPublishState>
    {
        FChunkPublishState{Chunks[0]._ChunkId, true, 2},
        FChunkPublishState{Chunks[1]._ChunkId, false, 0}
    };

    TestFalse(TEXT("a volume with a chunk still baking does not publish a volume with a hole in it"),
        Get_ChunksNeedAggregation(EpochsWithUnbuiltChunk, AggregatedSum));

    // A volume whose chunk cannot bake never aggregates, so the caller waiting on the fan-out has to be
    // told - the whole "never strand a caller" contract rests on this being distinguishable from waiting.
    auto ChunkStillWorking = TArray<FChunkPublishState>
    {
        FChunkPublishState{Chunks[0]._ChunkId, false, 0},
        FChunkPublishState{Chunks[1]._ChunkId, false, 0}
    };

    ChunkStillWorking[0]._IsBuilding = true;
    ChunkStillWorking[1]._HasFailed = true;

    TestFalse(TEXT("a failed chunk is not reported while any sibling is still working"),
        Get_ChunkBuildFailed(ChunkStillWorking));

    auto ChunksSettledWithOneFailure = ChunkStillWorking;
    ChunksSettledWithOneFailure[0]._IsBuilding = false;
    ChunksSettledWithOneFailure[0]._IsBuilt = true;

    TestTrue(TEXT("once every chunk has stopped, one failure fails the whole volume's build"),
        Get_ChunkBuildFailed(ChunksSettledWithOneFailure));

    TestFalse(TEXT("and a volume whose chunks all baked reports no failure"),
        Get_ChunkBuildFailed(EpochsBefore));

    // Chunk identity is a pure function of the authored params, so re-baking the adjacency over a repaired
    // chunk names the same chunks and finds the same crossings.
    auto RepairedChunks = Chunks;
    RepairedChunks[0]._Octree = RepairedChunk0;

    const auto AdjacencyAfter = Bake_ChunkAdjacency(Make_AdjacencyInputs(RepairedChunks));

    TestEqual(TEXT("the adjacency survives a chunk re-bake with the same crossing count"),
        AdjacencyAfter.Get_PortalCount(), AdjacencyBefore.Get_PortalCount());

    TestTrue(TEXT("and still joins the same two chunks"), AdjacencyAfter.Get_AreChunksAdjacent(0, 1));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
