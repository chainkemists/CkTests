#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Raycast.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the octree ray-marcher against bakes produced by the stub geometry backend: no world, no physics, no
// PIE, and every expected answer computable by hand from the layout below.
//
// Scene, in a 1600uu cube at a 50uu finest cell (leaf 200uu, sub-node 50uu, four layers):
//   - a thin WALL panel standing in the YZ plane, 60uu thick in X and 560uu square
//   - a solid BLOCK large enough to swallow whole leaves, so the fully-occluded-leaf path is exercised
// Both clear every 50uu sub-node boundary, so no assertion below rests on how a probe flush against a cell
// face resolves. Every ray lane is chosen to sit at the centre of a sub-node row for the same reason.
//
// The pairs of rays 50uu apart - one clear, one blocked - are the point of the whole file: at LEAF
// resolution both would read blocked, and only sub-node precision separates them.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_raycast
{
    constexpr auto FinestCellSizeUu = 50.0f;
    constexpr auto VolumeHalfSizeUu = 800.0;

    const auto VolumeBounds = FBox{FVector{-VolumeHalfSizeUu}, FVector{VolumeHalfSizeUu}};

    // Occupies exactly one sub-node column in X - [-50, 0) - on each side of the volume's X midplane.
    const auto Wall = FBox{FVector{-30.0, -280.0, -280.0}, FVector{30.0, 280.0, 280.0}};

    // Wholly contains the leaves [200,400)^3 and [400,600)^3, which is what makes them FULLY occluded
    // rather than sub-node occluded. Well clear of every ray lane below.
    const auto SolidBlock = FBox{FVector{180.0}, FVector{620.0}};

    // Every sweep runs down the centre of the sub-node row y in [-200,-150).
    constexpr auto LaneY = -175.0;

    // Above the wall's top face (280uu) by a full sub-node row, and below it by one.
    constexpr auto ClearOfWallTopZ = 325.0;
    constexpr auto InsideWallTopZ = 275.0;

    // The wall's own sub-node column, and the free one immediately outside it.
    constexpr auto InsideWallColumnX = -25.0;
    constexpr auto ClearOfWallColumnX = -75.0;

    // Above everything the scene contains.
    constexpr auto OpenAirZ = 525.0;

    constexpr auto SweepStart = -700.0;
    constexpr auto SweepEnd = 700.0;

    // The face of the sub-node column the wall occupies - a segment sweeping +X enters the blocking cell
    // here, not at the wall's own surface: the bake resolves no finer than a sub-node.
    constexpr auto ExpectedImpactX = -50.0;

    constexpr auto ToleranceUu = 0.01;

    static auto
        Run_Bake(
            const ICk_VoxelNav_GeometryBackend& InBackend)
        -> TSharedPtr<const ck::voxelnav::FOctree>
    {
        using namespace ck::voxelnav;

        // Generous enough that a working machine never reaches it, small enough that a machine that stops
        // making progress fails the test instead of hanging the run.
        constexpr auto MaxSlices = 100000;

        auto Params = FBuildParams{};
        Params._VolumeBounds = VolumeBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;

        auto Budget = FBuildBudget{};
        Budget._MaxOccupancyProbes = 100000;
        Budget._MaxSeconds = 0.0f;

        auto State = FBuildState{};

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceBuild(State, Params, InBackend, Budget); }

        return Request_ReleaseBuiltOctree(State);
    }

    static auto
        Run_SceneBake()
        -> TSharedPtr<const ck::voxelnav::FOctree>
    {
        return Run_Bake(FCk_VoxelNav_GeometryBackend_Stub{TArray<FBox>{Wall, SolidBlock}});
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Raycast_ClearCorridorsAreUnblocked,
    "Ck.VoxelNav.Raycast.ClearCorridorsAreUnblocked",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Raycast_ClearCorridorsAreUnblocked::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_raycast;

    const auto EmptyOctree = Run_Bake(FCk_VoxelNav_GeometryBackend_Stub{});

    if (NOT TestTrue(TEXT("the empty bake publishes an octree"),
        EmptyOctree.IsValid() && EmptyOctree->Get_IsValid()))
    { return false; }

    TestFalse(TEXT("a segment straight across an empty bake is clear"),
        Get_IsSegmentBlocked(*EmptyOctree,
            FVector{-VolumeHalfSizeUu}, FVector{VolumeHalfSizeUu}));

    const auto Octree = Run_SceneBake();

    if (NOT TestTrue(TEXT("the scene bake publishes an octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    const auto OpenAirResult = Raycast(*Octree,
        FVector{SweepStart, LaneY, OpenAirZ}, FVector{SweepEnd, LaneY, OpenAirZ});

    TestFalse(TEXT("a segment crossing the whole volume above every obstacle is clear"),
        OpenAirResult._IsBlocked);

    TestFalse(TEXT("a clear segment reports no impact"), OpenAirResult._BlockingCell.Get_IsValid());

    // The reverse direction exercises the mirrored traversal space rather than repeating the walk the
    // forward sweep already took.
    TestFalse(TEXT("the same corridor is clear travelled backwards"),
        Get_IsSegmentBlocked(*Octree,
            FVector{SweepEnd, LaneY, OpenAirZ}, FVector{SweepStart, LaneY, OpenAirZ}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Raycast_WallBlocksAndReportsTheEnteredCellFace,
    "Ck.VoxelNav.Raycast.WallBlocksAndReportsTheEnteredCellFace",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Raycast_WallBlocksAndReportsTheEnteredCellFace::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_raycast;

    const auto Octree = Run_SceneBake();

    if (NOT TestTrue(TEXT("the scene bake publishes an octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    const auto From = FVector{SweepStart, LaneY, LaneY};
    const auto To = FVector{SweepEnd, LaneY, LaneY};

    const auto Result = Raycast(*Octree, From, To);

    if (NOT TestTrue(TEXT("a segment driven through the wall is blocked"), Result._IsBlocked))
    { return false; }

    TestEqual(TEXT("the blocking distance is the run up to the occupied sub-node column"),
        Result._Distance, ExpectedImpactX - SweepStart, ToleranceUu);

    TestEqual(TEXT("the impact lands on the entered face of the occupied sub-node"),
        Result._ImpactPoint, FVector{ExpectedImpactX, LaneY, LaneY}, ToleranceUu);

    TestEqual(TEXT("the impact normal is the outward normal of that face"),
        Result._ImpactNormal, FVector{-1.0, 0.0, 0.0}, ToleranceUu);

    TestTrue(TEXT("the blocking cell is a resolved sub-node of the leaf layer"),
        Result._BlockingCell.Get_IsValid() && Result._BlockingCell.Get_LayerIndex() == 0);

    // Travelled the other way the segment must meet the wall's far face at the mirror distance, which is
    // the one assertion that catches a traversal correct only for positive directions.
    const auto ReverseResult = Raycast(*Octree, To, From);

    if (NOT TestTrue(TEXT("the same segment is blocked travelled backwards"), ReverseResult._IsBlocked))
    { return false; }

    TestEqual(TEXT("the reverse impact lands on the far face of the wall's occupied cells"),
        ReverseResult._ImpactPoint, FVector{-ExpectedImpactX, LaneY, LaneY}, ToleranceUu);

    TestEqual(TEXT("the reverse impact normal points back along the reverse segment"),
        ReverseResult._ImpactNormal, FVector{1.0, 0.0, 0.0}, ToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Raycast_SubNodePrecisionSeparatesAdjacentColumns,
    "Ck.VoxelNav.Raycast.SubNodePrecisionSeparatesAdjacentColumns",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Raycast_SubNodePrecisionSeparatesAdjacentColumns::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_raycast;

    const auto Octree = Run_SceneBake();

    if (NOT TestTrue(TEXT("the scene bake publishes an octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    // Both lanes run the length of the wall inside the SAME partly-occluded leaves; only the 50uu column
    // they occupy differs.
    TestTrue(TEXT("a segment running down the wall's own sub-node column is blocked"),
        Get_IsSegmentBlocked(*Octree,
            FVector{InsideWallColumnX, SweepStart, LaneY},
            FVector{InsideWallColumnX, SweepEnd, LaneY}));

    TestFalse(TEXT("the same run one sub-node column clear of the wall is not blocked"),
        Get_IsSegmentBlocked(*Octree,
            FVector{ClearOfWallColumnX, SweepStart, LaneY},
            FVector{ClearOfWallColumnX, SweepEnd, LaneY}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Raycast_GrazingTheWallTopMissesByOneSubNodeRow,
    "Ck.VoxelNav.Raycast.GrazingTheWallTopMissesByOneSubNodeRow",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Raycast_GrazingTheWallTopMissesByOneSubNodeRow::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_raycast;

    const auto Octree = Run_SceneBake();

    if (NOT TestTrue(TEXT("the scene bake publishes an octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    TestTrue(TEXT("a sweep through the wall's topmost occupied sub-node row is blocked"),
        Get_IsSegmentBlocked(*Octree,
            FVector{SweepStart, LaneY, InsideWallTopZ}, FVector{SweepEnd, LaneY, InsideWallTopZ}));

    // The grazing lane crosses the very leaves the row above it occludes, so a marcher that stopped at
    // leaf resolution would report this blocked.
    TestFalse(TEXT("the sweep one sub-node row above the wall's top face grazes past it"),
        Get_IsSegmentBlocked(*Octree,
            FVector{SweepStart, LaneY, ClearOfWallTopZ}, FVector{SweepEnd, LaneY, ClearOfWallTopZ}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Raycast_FullyOccludedLeafBlocksFromInside,
    "Ck.VoxelNav.Raycast.FullyOccludedLeafBlocksFromInside",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Raycast_FullyOccludedLeafBlocksFromInside::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_raycast;

    const auto Octree = Run_SceneBake();

    if (NOT TestTrue(TEXT("the scene bake publishes an octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    // Inside the leaf [200,400)^3, which the solid block swallows whole.
    const auto InsideBlock = FVector{300.0};

    if (NOT TestFalse(TEXT("the point inside the block is not free space"),
        Get_IsPositionFree(*Octree, InsideBlock)))
    { return false; }

    const auto Result = Raycast(*Octree, InsideBlock, InsideBlock + FVector{0.0, 0.0, 400.0});

    if (NOT TestTrue(TEXT("a segment starting inside solid geometry is blocked"), Result._IsBlocked))
    { return false; }

    TestEqual(TEXT("it is blocked at zero distance - the start point is already in the occluded cell"),
        Result._Distance, 0.0, ToleranceUu);

    if (NOT TestTrue(TEXT("the blocking cell is on the leaf layer"),
        Result._BlockingCell.Get_IsValid() && Result._BlockingCell.Get_LayerIndex() == 0))
    { return false; }

    const auto& LeafNodes = Octree->Get_LeafNodes();
    const auto BlockingLeafIdx = Result._BlockingCell.Get_NodeIndex();

    if (NOT TestTrue(TEXT("the blocking cell names a leaf of this octree"),
        LeafNodes.Get_LeafNodes().IsValidIndex(BlockingLeafIdx)))
    { return false; }

    // The distinguishing evidence: a leaf with no free sub-node left is answered by the whole-leaf branch,
    // not by the per-sub-node scan, and only that branch can report the leaf itself as the blocking cell.
    TestTrue(TEXT("the blocking leaf is FULLY occluded, so the whole-leaf branch is what answered"),
        LeafNodes.Get_LeafNode(BlockingLeafIdx).Get_IsFullyOccluded());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Raycast_DegenerateSegmentsFollowTheDocumentedContract,
    "Ck.VoxelNav.Raycast.DegenerateSegmentsFollowTheDocumentedContract",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Raycast_DegenerateSegmentsFollowTheDocumentedContract::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_raycast;

    const auto Octree = Run_SceneBake();

    if (NOT TestTrue(TEXT("the scene bake publishes an octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    // Inside the wall, in the middle of an occluded sub-node rather than on any cell boundary.
    const auto InsideWall = FVector{10.0, LaneY, LaneY};

    TestFalse(TEXT("a zero-length segment traverses no space and is never blocked, even inside geometry"),
        Get_IsSegmentBlocked(*Octree, InsideWall, InsideWall));

    const auto FarOutside = FVector{-4000.0};

    TestFalse(TEXT("a segment wholly outside the navigation bounds is clear - the bake makes no claim there"),
        Get_IsSegmentBlocked(*Octree, FarOutside, FarOutside + FVector{500.0, 0.0, 0.0}));

    // The part of a segment that lies outside contributes nothing, but the part inside still blocks.
    const auto OutsideStart = FVector{-4000.0, LaneY, LaneY};
    const auto InsideVolumeEnd = FVector{125.0, LaneY, LaneY};

    const auto EnteringResult = Raycast(*Octree, OutsideStart, InsideVolumeEnd);

    if (NOT TestTrue(TEXT("a segment entering the volume from outside is blocked by what it meets inside"),
        EnteringResult._IsBlocked))
    { return false; }

    TestEqual(TEXT("and it is blocked at the same cell face a segment starting inside would meet"),
        EnteringResult._ImpactPoint, FVector{ExpectedImpactX, LaneY, LaneY}, ToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
