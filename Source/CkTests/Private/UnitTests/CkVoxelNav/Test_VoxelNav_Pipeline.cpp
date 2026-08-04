#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Drives the whole voxelization machine against a hand-authored box layout through the stub geometry
// backend: no world, no physics, no PIE, and every expected cell computable by hand. Pins what the bake
// PRODUCES (occupancy at three layers, which subtrees get subdivided) and what it COSTS (the probe
// accounting), plus the property the resumability is worth nothing without - that a bake sliced into
// hundreds of tiny budgets produces the identical octree.
//
// Scene, in a 1600uu cube at a 50uu finest cell (leaf 200uu, four layers, layer-0 lattice 8x8x8):
//   - a floor slab across the whole footprint, 150uu thick
//   - a 200uu-square pillar rising through the middle of the volume
// Both are placed to CLEAR every cell boundary: FBox::Intersect counts a shared face as an intersection,
// so geometry flush against a boundary would be asserting a tie-break rather than the behavior under test.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_pipeline
{
    constexpr auto FinestCellSizeUu = 50.0f;
    constexpr auto VolumeHalfSizeUu = 800.0;

    // Layer 1 is a 4x4x4 lattice of 400uu cells, so RasterizeL1 always spends exactly 64 probes.
    constexpr auto Layer1CellCount = 64;

    // Blocked layer-1 cells: the whole k=0 row under the slab (16), plus the two the pillar passes through.
    constexpr auto ExpectedBlockedLayer1Cells = 18;

    // Eight leaf children per blocked layer-1 cell.
    constexpr auto ExpectedLeafNodeCount = 144;

    // 64 under the slab (the lower half of each blocked cell's leaves), plus all 8 leaves of each of the
    // two cells the pillar crosses.
    constexpr auto ExpectedOccludedLeafCount = 80;

    // Five distinct layer-2 cells are blocked, and every layer is created as the eight children of each
    // blocked parent one layer above.
    constexpr auto ExpectedLayer1NodeCount = 40;
    constexpr auto ExpectedLayer2NodeCount = 8;
    constexpr auto ExpectedLayer3NodeCount = 1;

    constexpr auto SubNodesPerLeaf = 64;

    const auto VolumeBounds = FBox{FVector{-VolumeHalfSizeUu}, FVector{VolumeHalfSizeUu}};

    const auto FloorSlab = FBox{FVector{-800.0, -800.0, -800.0}, FVector{800.0, 800.0, -650.0}};
    const auto Pillar = FBox{FVector{100.0, 100.0, -390.0}, FVector{300.0, 300.0, 390.0}};

    // Deep inside the slab, and inside the leaf's own sub-cell rather than on any lattice boundary.
    const auto PointInsideSlab = FVector{-575.0, -575.0, -725.0};

    // Open air far from both obstacles, in a layer-2 cell that was never subdivided.
    const auto PointInOpenAir = FVector{-575.0, -575.0, 575.0};

    // Inside the pillar.
    const auto PointInsidePillar = FVector{175.0, 175.0, -25.0};

    // A FREE 50uu cell inside the SAME leaf as PointInsidePillar - the finest resolution the bake carries.
    const auto PointInPillarLeafButFree = FVector{25.0, 25.0, -25.0};

    const auto PointOutsideVolume = FVector{0.0, 0.0, 10000.0};

    // The layer a lookup for open space resolves at: the walk stops at the coarsest node with no children.
    constexpr auto OpenAirResolutionLayer = 2;

    static auto
        Make_BuildParams()
        -> ck::voxelnav::FBuildParams
    {
        auto Params = ck::voxelnav::FBuildParams{};

        Params._VolumeBounds = VolumeBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;

        return Params;
    }

    static auto
        Make_Budget(
            int32 InMaxProbes)
        -> ck::voxelnav::FBuildBudget
    {
        auto Budget = ck::voxelnav::FBuildBudget{};

        Budget._MaxOccupancyProbes = InMaxProbes;

        // A wall-clock guard would make the slice count machine-dependent, which is exactly what these
        // assertions must not be.
        Budget._MaxSeconds = 0.0f;

        return Budget;
    }

    static auto
        Run_Bake(
            const ICk_VoxelNav_GeometryBackend& InBackend,
            int32 InMaxProbesPerSlice)
        -> ck::voxelnav::FBuildState
    {
        using namespace ck::voxelnav;

        // Generous enough that a working machine never reaches it, small enough that a machine that stops
        // making progress fails the test instead of hanging the run.
        constexpr auto MaxSlices = 100000;

        auto State = FBuildState{};
        const auto Params = Make_BuildParams();
        const auto Budget = Make_Budget(InMaxProbesPerSlice);

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceBuild(State, Params, InBackend, Budget); }

        return State;
    }

    static auto
        Get_OctreesAreIdentical(
            const ck::voxelnav::FOctree& InLeft,
            const ck::voxelnav::FOctree& InRight)
        -> bool
    {
        using namespace ck::voxelnav;

        if (InLeft.Get_LayerCount() != InRight.Get_LayerCount())
        { return false; }

        for (auto LayerIdx = 0; LayerIdx < InLeft.Get_LayerCount(); ++LayerIdx)
        {
            const auto& LeftNodes = InLeft.Get_Layer(static_cast<LayerIndex>(LayerIdx)).Get_Nodes();
            const auto& RightNodes = InRight.Get_Layer(static_cast<LayerIndex>(LayerIdx)).Get_Nodes();

            if (LeftNodes.Num() != RightNodes.Num())
            { return false; }

            for (auto NodeIdx = 0; NodeIdx < LeftNodes.Num(); ++NodeIdx)
            {
                const auto& LeftNode = LeftNodes[NodeIdx];
                const auto& RightNode = RightNodes[NodeIdx];

                if (LeftNode.Get_MortonCode() != RightNode.Get_MortonCode() ||
                    NOT (LeftNode.Get_Parent() == RightNode.Get_Parent()) ||
                    NOT (LeftNode.Get_FirstChild() == RightNode.Get_FirstChild()))
                { return false; }

                for (auto Direction = 0; Direction < 6; ++Direction)
                {
                    const auto LeftNeighbour = LeftNode.Get_Neighbour(static_cast<NeighbourDirection>(Direction));
                    const auto RightNeighbour = RightNode.Get_Neighbour(static_cast<NeighbourDirection>(Direction));

                    if (NOT (LeftNeighbour == RightNeighbour))
                    { return false; }
                }
            }
        }

        const auto& LeftLeaves = InLeft.Get_LeafNodes().Get_LeafNodes();
        const auto& RightLeaves = InRight.Get_LeafNodes().Get_LeafNodes();

        if (LeftLeaves.Num() != RightLeaves.Num())
        { return false; }

        for (auto LeafIdx = 0; LeafIdx < LeftLeaves.Num(); ++LeafIdx)
        {
            if (LeftLeaves[LeafIdx].Get_SubNodes() != RightLeaves[LeafIdx].Get_SubNodes() ||
                NOT (LeftLeaves[LeafIdx].Get_Parent() == RightLeaves[LeafIdx].Get_Parent()))
            { return false; }
        }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Pipeline_EmptyVolumeCompletesWithoutRasterizing,
    "Ck.VoxelNav.Pipeline.EmptyVolumeCompletesWithoutRasterizing",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Pipeline_EmptyVolumeCompletesWithoutRasterizing::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_pipeline;

    const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{};

    auto State = Run_Bake(Backend, 2048);

    if (NOT TestTrue(TEXT("a bake over an empty world completes"),
        State.Get_Stage() == ECk_VoxelNav_BuildStage::Complete))
    { return false; }

    TestEqual(TEXT("an empty volume is recognised from ONE broadphase sweep and costs zero occupancy probes"),
        State.Get_Stats().Get_OccupancyProbes(), 0);

    TestEqual(TEXT("the broadphase sweep found no bodies"), State.Get_Stats().Get_BroadphaseBodyCount(), 0);
    TestEqual(TEXT("no leaf is allocated"), State.Get_Stats().Get_LeafNodeCount(), 0);
    TestEqual(TEXT("no node is created at any layer"), State.Get_Stats().Get_TotalNodeCount(), 0);

    const auto Octree = Request_ReleaseBuiltOctree(State);

    if (NOT TestTrue(TEXT("the empty bake still publishes a valid octree"),
        Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    TestTrue(TEXT("every point inside an empty volume is free"),
        Get_IsPositionFree(*Octree, PointInsideSlab) &&
        Get_IsPositionFree(*Octree, PointInsidePillar) &&
        Get_IsPositionFree(*Octree, PointInOpenAir));

    TestFalse(TEXT("a point outside the volume is still not free - the bake makes no claim there"),
        Get_IsPositionFree(*Octree, PointOutsideVolume));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Pipeline_BakesKnownLayoutToExpectedOccupancy,
    "Ck.VoxelNav.Pipeline.BakesKnownLayoutToExpectedOccupancy",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Pipeline_BakesKnownLayoutToExpectedOccupancy::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_pipeline;

    const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{TArray<FBox>{FloorSlab, Pillar}};

    auto State = Run_Bake(Backend, 2048);

    if (NOT TestTrue(TEXT("the bake completes"), State.Get_Stage() == ECk_VoxelNav_BuildStage::Complete))
    { return false; }

    const auto Stats = State.Get_Stats();

    TestEqual(TEXT("both obstacles are found by the whole-volume broadphase sweep"),
        Stats.Get_BroadphaseBodyCount(), 2);
    TestEqual(TEXT("the slab's row plus the pillar's two cells are the blocked layer-1 cells"),
        Stats.Get_BlockedLayer1Cells(), ExpectedBlockedLayer1Cells);
    TestEqual(TEXT("eight leaves are created per blocked layer-1 cell"),
        Stats.Get_LeafNodeCount(), ExpectedLeafNodeCount);
    TestEqual(TEXT("only the leaves actually touching geometry are occluded"),
        Stats.Get_OccludedLeafCount(), ExpectedOccludedLeafCount);

    // The probe count is derived from the octree's own dimensions rather than hardcoded, so this asserts
    // the CASCADE - one probe per layer-1 cell, one per leaf of a blocked cell, 64 per occluded leaf - and
    // fails the moment a regression makes the bake probe cells the hierarchy should have pruned.
    TestEqual(TEXT("every probe the bake spent is accounted for by the three-level cascade"),
        Stats.Get_OccupancyProbes(),
        Layer1CellCount + Stats.Get_LeafNodeCount() + (Stats.Get_OccludedLeafCount() * SubNodesPerLeaf));

    const auto Octree = Request_ReleaseBuiltOctree(State);

    if (NOT TestTrue(TEXT("the bake publishes a valid octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    TestFalse(TEXT("a point deep inside the floor slab is not free"),
        Get_IsPositionFree(*Octree, PointInsideSlab));
    TestFalse(TEXT("a point inside the pillar is not free"),
        Get_IsPositionFree(*Octree, PointInsidePillar));
    TestTrue(TEXT("open air well clear of both obstacles is free"),
        Get_IsPositionFree(*Octree, PointInOpenAir));
    TestTrue(TEXT("a 50uu cell inside the pillar's own leaf, but clear of the pillar, is free"),
        Get_IsPositionFree(*Octree, PointInPillarLeafButFree));
    TestFalse(TEXT("a point outside the baked cube is not free"),
        Get_IsPositionFree(*Octree, PointOutsideVolume));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Pipeline_SubdivisionReachesOnlyOccupiedSubtrees,
    "Ck.VoxelNav.Pipeline.SubdivisionReachesOnlyOccupiedSubtrees",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Pipeline_SubdivisionReachesOnlyOccupiedSubtrees::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_pipeline;

    const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{TArray<FBox>{FloorSlab, Pillar}};

    auto State = Run_Bake(Backend, 2048);

    if (NOT TestTrue(TEXT("the bake completes"), State.Get_Stage() == ECk_VoxelNav_BuildStage::Complete))
    { return false; }

    const auto Octree = Request_ReleaseBuiltOctree(State);

    if (NOT TestTrue(TEXT("the bake publishes a valid octree"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    if (NOT TestEqual(TEXT("the volume sizes to four layers"), Octree->Get_LayerCount(), 4))
    { return false; }

    // Blocked-ness propagates upward and each layer is created as the eight children of every blocked
    // parent, so these counts ARE the propagation: the pillar's two layer-1 cells collapse into two
    // layer-2 parents that the slab already contributed, and everything collapses into the one root.
    TestEqual(TEXT("layer 0 carries one node per allocated leaf"),
        Octree->Get_Layer(0).Get_NodeCount(), ExpectedLeafNodeCount);
    TestEqual(TEXT("layer 1 carries the eight children of each of the five blocked layer-2 cells"),
        Octree->Get_Layer(1).Get_NodeCount(), ExpectedLayer1NodeCount);
    TestEqual(TEXT("layer 2 carries the root's eight children"),
        Octree->Get_Layer(2).Get_NodeCount(), ExpectedLayer2NodeCount);
    TestEqual(TEXT("the top layer is the single root node"),
        Octree->Get_Layer(3).Get_NodeCount(), ExpectedLayer3NodeCount);

    TestTrue(TEXT("layer 1 was NOT scanned as a whole cube - it holds far fewer nodes than its capacity"),
        Octree->Get_Layer(1).Get_NodeCount() < Octree->Get_Layer(1).Get_MaxNodeCount());

    // Open space resolves at the coarsest node that was never subdivided; space near geometry resolves all
    // the way down to a leaf sub-node. That difference is the hierarchy earning its keep.
    const auto OpenAirLookup = TryGet_NodeAddressFromPosition(*Octree, PointInOpenAir, 0);

    TestTrue(TEXT("open air resolves to a node, not to free space below the lattice"),
        OpenAirLookup._Outcome == ECk_VoxelNav_AddressLookup::Found);
    TestEqual(TEXT("open air resolves at a COARSE layer because nothing below it was ever created"),
        static_cast<int32>(OpenAirLookup._Address.Get_LayerIndex()), OpenAirResolutionLayer);

    const auto PillarLookup = TryGet_NodeAddressFromPosition(*Octree, PointInsidePillar, 0);

    TestTrue(TEXT("space at the pillar resolves to a node"),
        PillarLookup._Outcome == ECk_VoxelNav_AddressLookup::Found);
    TestEqual(TEXT("space at the pillar resolves all the way down to the leaf layer"),
        static_cast<int32>(PillarLookup._Address.Get_LayerIndex()), 0);

    const auto& PillarLeaf = Octree->Get_LeafNodes().Get_LeafNode(PillarLookup._Address.Get_NodeIndex());

    TestTrue(TEXT("the pillar's leaf holds occluded sub-nodes"), PillarLeaf.Get_IsAnySubNodeOccluded());
    TestFalse(TEXT("the pillar's leaf is only PARTLY occluded - a 200uu leaf is coarser than the obstacle"),
        PillarLeaf.Get_IsFullyOccluded());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Pipeline_ResumedBakeMatchesOneShotBake,
    "Ck.VoxelNav.Pipeline.ResumedBakeMatchesOneShotBake",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Pipeline_ResumedBakeMatchesOneShotBake::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_pipeline;

    // Small enough to interrupt every budgeted stage repeatedly, and NOT a divisor of 64, so slices also
    // end part-way through a leaf's sub-node sweep rather than only on leaf boundaries.
    constexpr auto TinyProbeBudget = 7;
    constexpr auto UnlimitedProbeBudget = 1000000;

    const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{TArray<FBox>{FloorSlab, Pillar}};

    auto OneShotState = Run_Bake(Backend, UnlimitedProbeBudget);
    auto ResumedState = Run_Bake(Backend, TinyProbeBudget);

    if (NOT TestTrue(TEXT("the one-shot bake completes"),
        OneShotState.Get_Stage() == ECk_VoxelNav_BuildStage::Complete))
    { return false; }

    if (NOT TestTrue(TEXT("the sliced bake completes"),
        ResumedState.Get_Stage() == ECk_VoxelNav_BuildStage::Complete))
    { return false; }

    TestEqual(TEXT("an unlimited budget finishes the whole bake in a single slice"),
        OneShotState.Get_Stats().Get_Slices(), 1);

    TestTrue(TEXT("a tiny budget forces the bake across many slices"),
        ResumedState.Get_Stats().Get_Slices() > 1);

    TestEqual(TEXT("resuming costs no extra probes - a resumed stage picks up, it does not re-probe"),
        ResumedState.Get_Stats().Get_OccupancyProbes(), OneShotState.Get_Stats().Get_OccupancyProbes());

    TestEqual(TEXT("both bakes find the same blocked layer-1 cells"),
        ResumedState.Get_Stats().Get_BlockedLayer1Cells(),
        OneShotState.Get_Stats().Get_BlockedLayer1Cells());

    TestEqual(TEXT("both bakes occlude the same leaves"),
        ResumedState.Get_Stats().Get_OccludedLeafCount(),
        OneShotState.Get_Stats().Get_OccludedLeafCount());

    const auto OneShotOctree = Request_ReleaseBuiltOctree(OneShotState);
    const auto ResumedOctree = Request_ReleaseBuiltOctree(ResumedState);

    if (NOT TestTrue(TEXT("both bakes publish an octree"),
        OneShotOctree.IsValid() && ResumedOctree.IsValid()))
    { return false; }

    // Field-wise, down to every packed node ref and every sub-node bit: budgeting must be invisible in the
    // result, or a bake's output would depend on the frame rate it happened to run at.
    TestTrue(TEXT("the sliced bake produces an octree identical to the one-shot bake, field for field"),
        Get_OctreesAreIdentical(*OneShotOctree, *ResumedOctree));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
