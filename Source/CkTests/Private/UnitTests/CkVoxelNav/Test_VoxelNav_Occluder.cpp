#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkEcsExt/Transform/CkTransform_Fragment.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Occluder/CkVoxelNavOccluder_Fragment.h"
#include "CkVoxelNav/Occluder/CkVoxelNavOccluder_Processor.h"
#include "CkVoxelNav/Occluder/CkVoxelNavOccluder_Utils.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Morton.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Repair.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Fragment.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Processor.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavBake_TestTypes.h"

#include "../CkUnitTest_Common.h"

#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Dynamic occluders and local repair, hermetic: an octree baked through the stub geometry backend, an
// obstacle moved, and the dirty region repaired - no world, no physics, no PIE, and every expected cell,
// probe and occupancy word computable by hand.
//
// Scene, in a 1600uu cube at a 50uu finest cell (leaf 200uu, layer-1 400uu, four layers, layer-0 lattice
// 8x8x8):
//   - a floor slab across the whole footprint, 150uu thick, which never moves. Its 64 occluded leaves are
//     the CONTROL: the local-repair contract says a repair elsewhere in the volume must leave every one of
//     them bit-identical.
//   - one 90uu obstacle cube that moves from the middle of leaf (0,0,7) to the middle of leaf (2,0,7). The
//     destination's layer-1 parent was NEVER subdivided by the bake, so the repair has to GROW structure,
//     which is the case upstream's in-place node edits corrupted the octree on.
//
// Both obstacle poses are centred in their leaf and 90uu across, so they clear every sub-node boundary:
// FBox::Intersect counts a shared face as an intersection, and a pose flush against one would be asserting
// a tie-break rather than the behavior under test.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_occluder
{
    constexpr auto FinestCellSizeUu = 50.0f;
    constexpr auto VolumeHalfSizeUu = 800.0;

    constexpr auto UnlimitedProbeBudget = 1000000;

    const auto VolumeBounds = FBox{FVector{-VolumeHalfSizeUu}, FVector{VolumeHalfSizeUu}};

    const auto FloorSlab = FBox{FVector{-800.0, -800.0, -800.0}, FVector{800.0, 800.0, -650.0}};

    // Centres of leaf (0,0,7) and leaf (2,0,7). Same offset within their own leaf, so the two poses must
    // rasterize to the SAME 64-bit occupancy word - which is the sharpest statement that the repair
    // rasterizes rather than approximates.
    const auto ObstacleCentreBefore = FVector{-700.0, -700.0, 700.0};
    const auto ObstacleCentreAfter = FVector{-300.0, -700.0, 700.0};

    const auto ObstacleHalfExtents = FVector{45.0};

    // Layer 1 is a 4x4x4 lattice of 400uu cells, so a bake always spends exactly 64 probes there.
    constexpr auto Layer1CellCount = 64;

    // The slab's whole k=0 row (16), plus the one cell the obstacle sits in.
    constexpr auto ExpectedBlockedLayer1Cells = 17;
    constexpr auto ExpectedLeafNodeCount = 136;

    // Four leaves under the slab per blocked layer-1 cell (16 x 4), plus the obstacle's own leaf.
    constexpr auto ExpectedOccludedLeafCount = 65;
    constexpr auto ExpectedSlabOccludedLeafCount = 64;

    constexpr auto SubNodesPerLeaf = 64;

    // A 90uu cube centred in a 200uu leaf covers the middle two 50uu sub-node columns on every axis.
    constexpr auto ExpectedObstacleSubNodeCount = 8;

    // The dirty region reaches two layer-1 cells and three leaves, but only ONE of those leaves hangs off a
    // still-blocked parent - the other two belong to the cell the obstacle just vacated, which the cell
    // probe already proved empty.
    constexpr auto ExpectedDirtyCellsProbed = 2;
    constexpr auto ExpectedDirtyLeavesProbed = 1;

    // Two leaves change: the one the obstacle left (cleared) and the one it arrived in.
    constexpr auto ExpectedLeavesChanged = 2;

    constexpr auto ExpectedRepairProbes =
        ExpectedDirtyCellsProbed + ExpectedDirtyLeavesProbed + (1 * SubNodesPerLeaf);

    // ----------------------------------------------------------------------------------------------------------------

    static auto
        Make_ObstacleBox(
            const FVector& InCentre)
        -> FBox
    {
        return FBox{InCentre - ObstacleHalfExtents, InCentre + ObstacleHalfExtents};
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
        Bake_Octree(
            const TArray<FBox>& InObstacles)
        -> TSharedPtr<const ck::voxelnav::FOctree>
    {
        using namespace ck::voxelnav;

        constexpr auto MaxSlices = 100000;

        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{InObstacles};

        auto Params = FBuildParams{};
        Params._VolumeBounds = VolumeBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;

        auto State = FBuildState{};
        const auto Budget = Make_Budget(UnlimitedProbeBudget);

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceBuild(State, Params, Backend, Budget); }

        return Request_ReleaseBuiltOctree(State);
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
            const FBox& InDirtyBounds,
            int32 InMaxProbesPerSlice)
        -> FRepairOutcome
    {
        using namespace ck::voxelnav;

        constexpr auto MaxSlices = 100000;

        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{InObstaclesAfter};

        auto Params = FRepairParams{};
        Params._VolumeBounds = VolumeBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;
        Params._DirtyBounds = InDirtyBounds;

        auto State = FRepairState{};
        const auto Budget = Make_Budget(InMaxProbesPerSlice);

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

    /** Leaf occupancy keyed by the leaf's MORTON code rather than its array index. Index is a position in an
     *  array the repair rebuilds; Morton code is the leaf's identity, and comparing by identity is the only
     *  way to state "this leaf was left alone" across a rebuild. */
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

        for (const auto& LeafLayerNode : LeafLayer.Get_Nodes())
        {
            if (NOT LeafLayerNode.Get_HasChildren())
            { continue; }

            const auto LeafIndex = LeafLayerNode.Get_FirstChild().Get_NodeIndex();

            if (NOT Leaves.IsValidIndex(LeafIndex))
            { continue; }

            const auto Word = Leaves[LeafIndex].Get_SubNodes();

            if (Word == 0)
            { continue; }

            Occupancy.Add(LeafLayerNode.Get_MortonCode(), Word);
        }

        return Occupancy;
    }

    static auto
        Get_LeafMortonAt(
            const ck::voxelnav::FOctree& InOctree,
            const FVector& InPosition)
        -> ck::voxelnav::MortonCode
    {
        using namespace ck::voxelnav;

        const auto& NavigationBounds = InOctree.Get_NavigationBounds();
        const auto LatticeOrigin = NavigationBounds.GetCenter() - NavigationBounds.GetExtent();
        const auto LeafSize = static_cast<double>(InOctree.Get_LeafNodes().Get_LeafNodeSize());

        const auto Local = InPosition - LatticeOrigin;

        return Get_MortonFromCoords(FIntVector
        {
            static_cast<int32>(FMath::FloorToDouble(Local.X / LeafSize)),
            static_cast<int32>(FMath::FloorToDouble(Local.Y / LeafSize)),
            static_cast<int32>(FMath::FloorToDouble(Local.Z / LeafSize))
        });
    }

    /** Field-wise octree equality, down to every packed node ref and every sub-node bit. */
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
    FCkTest_VoxelNav_Occluder_DirtyBoundsMapDirectlyToTheirCells,
    "Ck.VoxelNav.Occluder.Repair.DirtyBoundsMapDirectlyToTheirCells",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_DirtyBoundsMapDirectlyToTheirCells::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_occluder;

    const auto Octree = Bake_Octree(TArray<FBox>{FloorSlab});

    if (NOT TestTrue(TEXT("the fixture bakes"), Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    auto Mortons = TArray<MortonCode>{};

    // A box wholly inside one 400uu layer-1 cell names exactly that cell - no octree scan, no dependence on
    // how many nodes the octree happens to hold.
    Get_CellMortonsIntersectingBounds(*Octree, 1, Make_ObstacleBox(ObstacleCentreBefore), Mortons);

    TestEqual(TEXT("a box inside one layer-1 cell names exactly one cell"), Mortons.Num(), 1);

    if (Mortons.Num() == 1)
    {
        TestTrue(TEXT("and it is the cell the box actually sits in"),
            Get_NodePositionFromLayerAndMorton(*Octree, 1, Mortons[0])
                .Equals(FVector{-600.0, -600.0, 600.0}));
    }

    const auto SpanningBounds = Make_ObstacleBox(ObstacleCentreBefore) + Make_ObstacleBox(ObstacleCentreAfter);

    Get_CellMortonsIntersectingBounds(*Octree, 1, SpanningBounds, Mortons);
    TestEqual(TEXT("the union of the two obstacle poses reaches two layer-1 cells"),
        Mortons.Num(), ExpectedDirtyCellsProbed);

    Get_CellMortonsIntersectingBounds(*Octree, 0, SpanningBounds, Mortons);
    TestEqual(TEXT("and three leaves"), Mortons.Num(), 3);

    // Upstream fed unclamped, possibly negative lattice coordinates straight into the Morton encoder, so a
    // dirty box overhanging the volume aliased onto cells it never touched.
    Get_CellMortonsIntersectingBounds(*Octree, 1,
        FBox{FVector{-100000.0}, FVector{-90000.0}}, Mortons);
    TestEqual(TEXT("a dirty box entirely outside the lattice names NO cell rather than clamping onto its edge"),
        Mortons.Num(), 0);

    Get_CellMortonsIntersectingBounds(*Octree, 1,
        FBox{FVector{-100000.0, -700.0, 700.0}, FVector{-700.0, -650.0, 750.0}}, Mortons);
    TestEqual(TEXT("a dirty box overhanging the lattice is clamped to the cells it really reaches"),
        Mortons.Num(), 1);

    auto DegenerateMortons = TArray<MortonCode>{};
    Get_CellMortonsIntersectingBounds(*Octree, 1, FBox{ForceInit}, DegenerateMortons);
    TestEqual(TEXT("degenerate dirty bounds name no cell"), DegenerateMortons.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Occluder_MovedObstacleFlipsOccupancyOnlyWhereItMoved,
    "Ck.VoxelNav.Occluder.Repair.MovedObstacleFlipsOccupancyOnlyWhereItMoved",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_MovedObstacleFlipsOccupancyOnlyWhereItMoved::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_occluder;

    const auto ObstacleBefore = Make_ObstacleBox(ObstacleCentreBefore);
    const auto ObstacleAfter = Make_ObstacleBox(ObstacleCentreAfter);

    const auto BakedOctree = Bake_Octree(TArray<FBox>{FloorSlab, ObstacleBefore});

    if (NOT TestTrue(TEXT("the fixture bakes"), BakedOctree.IsValid() && BakedOctree->Get_IsValid()))
    { return false; }

    TestTrue(TEXT("the obstacle's original position is blocked before the move"),
        NOT Get_IsPositionFree(*BakedOctree, ObstacleCentreBefore));
    TestTrue(TEXT("its destination is open space before the move"),
        Get_IsPositionFree(*BakedOctree, ObstacleCentreAfter));

    const auto BeforeOccupancy = Get_LeafOccupancyByMorton(*BakedOctree);

    TestEqual(TEXT("the bake occludes the slab's leaves plus the obstacle's own"),
        BeforeOccupancy.Num(), ExpectedOccludedLeafCount);

    const auto Outcome = Run_Repair(
        BakedOctree, TArray<FBox>{FloorSlab, ObstacleAfter},
        ObstacleBefore + ObstacleAfter, UnlimitedProbeBudget);

    if (NOT TestTrue(TEXT("the repair completes"),
        Outcome._Stage == ECk_VoxelNav_RepairStage::Complete &&
        Outcome._Octree.IsValid() && Outcome._Octree->Get_IsValid()))
    { return false; }

    // THE LOCAL-REPAIR CONTRACT, as a probe count. Upstream scanned the whole octree twice per dirty box and
    // then discarded the result; this asserts that the repair pays only for the region that moved.
    TestEqual(TEXT("only the layer-1 cells the dirty region reaches are probed"),
        Outcome._Stats.Get_DirtyCellsProbed(), ExpectedDirtyCellsProbed);
    TestEqual(TEXT("only leaves under a still-blocked parent are probed"),
        Outcome._Stats.Get_DirtyLeavesProbed(), ExpectedDirtyLeavesProbed);
    TestEqual(TEXT("every probe the repair spent is accounted for by the cell/leaf/sub-node cascade"),
        Outcome._Stats.Get_OccupancyProbes(), ExpectedRepairProbes);
    TestTrue(TEXT("a repair costs a small fraction of the bake it repairs"),
        Outcome._Stats.Get_OccupancyProbes() <
            Layer1CellCount + ExpectedLeafNodeCount + (ExpectedOccludedLeafCount * SubNodesPerLeaf));

    TestEqual(TEXT("exactly two leaves change - the one vacated and the one arrived in"),
        Outcome._Stats.Get_LeavesChanged(), ExpectedLeavesChanged);

    TestTrue(TEXT("the vacated cell is free after the repair"),
        Get_IsPositionFree(*Outcome._Octree, ObstacleCentreBefore));
    TestTrue(TEXT("the obstacle's new position is blocked after the repair"),
        NOT Get_IsPositionFree(*Outcome._Octree, ObstacleCentreAfter));

    const auto AfterOccupancy = Get_LeafOccupancyByMorton(*Outcome._Octree);

    TestEqual(TEXT("the occluded-leaf count is unchanged - one leaf freed, one occluded"),
        AfterOccupancy.Num(), ExpectedOccludedLeafCount);

    const auto VacatedLeafMorton = Get_LeafMortonAt(*BakedOctree, ObstacleCentreBefore);
    const auto ArrivedLeafMorton = Get_LeafMortonAt(*BakedOctree, ObstacleCentreAfter);

    TestFalse(TEXT("the vacated leaf holds no occupancy at all - not a residual trail of it"),
        AfterOccupancy.Contains(VacatedLeafMorton));

    const auto* ArrivedWord = AfterOccupancy.Find(ArrivedLeafMorton);
    const auto* VacatedWordBefore = BeforeOccupancy.Find(VacatedLeafMorton);

    if (TestTrue(TEXT("both obstacle poses resolve to a rasterized leaf"),
        ArrivedWord != nullptr && VacatedWordBefore != nullptr))
    {
        TestEqual(TEXT("a 90uu cube centred in a 200uu leaf occludes its middle 2x2x2 sub-nodes"),
            FMath::CountBits(*ArrivedWord), ExpectedObstacleSubNodeCount);

        // The two poses sit identically inside their own leaf, so a repair that RASTERIZES rather than
        // approximates has to produce the identical word.
        TestTrue(TEXT("the arrived leaf's occupancy word is bit-identical to the vacated leaf's"),
            *ArrivedWord == *VacatedWordBefore);
    }

    // THE OTHER HALF OF THE CONTRACT: everything the dirty region did not reach is carried over untouched.
    auto UntouchedLeavesAreIdentical = true;
    auto ComparedUntouchedLeaves = 0;

    for (const auto& BeforeEntry : BeforeOccupancy)
    {
        if (BeforeEntry.Key == VacatedLeafMorton)
        { continue; }

        const auto* AfterWord = AfterOccupancy.Find(BeforeEntry.Key);

        UntouchedLeavesAreIdentical &= AfterWord != nullptr && *AfterWord == BeforeEntry.Value;
        ++ComparedUntouchedLeaves;
    }

    TestEqual(TEXT("the slab's leaves are all still there to compare"),
        ComparedUntouchedLeaves, ExpectedSlabOccludedLeafCount);
    TestTrue(TEXT("every leaf outside the dirty region is BIT-IDENTICAL after the repair"),
        UntouchedLeavesAreIdentical);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Occluder_RepairedOctreeMatchesAFullRebake,
    "Ck.VoxelNav.Occluder.Repair.RepairedOctreeMatchesAFullRebake",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_RepairedOctreeMatchesAFullRebake::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_occluder;

    const auto ObstacleBefore = Make_ObstacleBox(ObstacleCentreBefore);
    const auto ObstacleAfter = Make_ObstacleBox(ObstacleCentreAfter);

    const auto BakedOctree = Bake_Octree(TArray<FBox>{FloorSlab, ObstacleBefore});
    const auto RebakedOctree = Bake_Octree(TArray<FBox>{FloorSlab, ObstacleAfter});

    if (NOT TestTrue(TEXT("both bakes complete"),
        BakedOctree.IsValid() && BakedOctree->Get_IsValid() &&
        RebakedOctree.IsValid() && RebakedOctree->Get_IsValid()))
    { return false; }

    const auto Outcome = Run_Repair(
        BakedOctree, TArray<FBox>{FloorSlab, ObstacleAfter},
        ObstacleBefore + ObstacleAfter, UnlimitedProbeBudget);

    if (NOT TestTrue(TEXT("the repair completes"),
        Outcome._Stage == ECk_VoxelNav_RepairStage::Complete && Outcome._Octree.IsValid()))
    { return false; }

    // The oracle. A repair is only worth having if it lands where a full rebake would - and this is the
    // assertion upstream could not have passed: swap-removing and appending layer-0 nodes in place left
    // parent, child and neighbour links pointing at whatever had moved into their index.
    TestTrue(TEXT("the locally repaired octree is field-for-field what a full rebake of the moved scene "
                  "produces - same nodes, same links, same neighbours, same occupancy words"),
        Get_OctreesAreIdentical(*Outcome._Octree, *RebakedOctree));

    TestTrue(TEXT("and it got there for a fraction of the rebake's probes"),
        Outcome._Stats.Get_OccupancyProbes() * 10 < Layer1CellCount + ExpectedLeafNodeCount +
            (ExpectedOccludedLeafCount * SubNodesPerLeaf));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Occluder_SlicedRepairMatchesOneShotRepair,
    "Ck.VoxelNav.Occluder.Repair.SlicedRepairMatchesOneShotRepair",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_SlicedRepairMatchesOneShotRepair::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_occluder;

    // Small enough to interrupt both probing stages repeatedly, and NOT a divisor of 64, so slices also end
    // part-way through a leaf's sub-node sweep rather than only on leaf boundaries.
    constexpr auto TinyProbeBudget = 3;

    const auto ObstacleBefore = Make_ObstacleBox(ObstacleCentreBefore);
    const auto ObstacleAfter = Make_ObstacleBox(ObstacleCentreAfter);

    const auto BakedOctree = Bake_Octree(TArray<FBox>{FloorSlab, ObstacleBefore});

    if (NOT TestTrue(TEXT("the fixture bakes"), BakedOctree.IsValid() && BakedOctree->Get_IsValid()))
    { return false; }

    const auto ObstaclesAfter = TArray<FBox>{FloorSlab, ObstacleAfter};
    const auto DirtyBounds = ObstacleBefore + ObstacleAfter;

    const auto OneShot = Run_Repair(BakedOctree, ObstaclesAfter, DirtyBounds, UnlimitedProbeBudget);
    const auto Sliced = Run_Repair(BakedOctree, ObstaclesAfter, DirtyBounds, TinyProbeBudget);

    if (NOT TestTrue(TEXT("both repairs complete"),
        OneShot._Stage == ECk_VoxelNav_RepairStage::Complete &&
        Sliced._Stage == ECk_VoxelNav_RepairStage::Complete &&
        OneShot._Octree.IsValid() && Sliced._Octree.IsValid()))
    { return false; }

    TestEqual(TEXT("an unlimited budget finishes the whole repair in a single slice"),
        OneShot._Stats.Get_Slices(), 1);
    TestTrue(TEXT("a tiny budget forces the repair across many slices"),
        Sliced._Stats.Get_Slices() > 1);

    TestEqual(TEXT("resuming costs no extra probes - a resumed stage picks up mid-leaf, it does not re-probe"),
        Sliced._Stats.Get_OccupancyProbes(), OneShot._Stats.Get_OccupancyProbes());
    TestEqual(TEXT("and changes the same leaves"),
        Sliced._Stats.Get_LeavesChanged(), OneShot._Stats.Get_LeavesChanged());

    TestTrue(TEXT("a repair sliced across many budgets produces the identical octree, field for field"),
        Get_OctreesAreIdentical(*OneShot._Octree, *Sliced._Octree));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Occluder_RepairOfAVolumeThatNeverBakedIsRejected,
    "Ck.VoxelNav.Occluder.Repair.RepairOfAVolumeThatNeverBakedIsRejected",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_RepairOfAVolumeThatNeverBakedIsRejected::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_occluder;

    AddExpectedError(TEXT("Cannot repair a VoxelNav octree that was never published"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto State = FRepairState{};

    const auto RepairOpened = Request_BeginRepair(State, TSharedPtr<const FOctree>{});

    TestFalse(TEXT("a repair cannot open against a volume with no published bake"), RepairOpened);
    TestTrue(TEXT("and the rejected repair reports Failed rather than sitting NotStarted"),
        State.Get_Stage() == ECk_VoxelNav_RepairStage::Failed);
    TestTrue(TEXT("a failed repair publishes nothing"),
        NOT Request_ReleaseRepairedOctree(State).IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Occluder_TrackerEmitsOnlyOnMovementPastTheThreshold,
    "Ck.VoxelNav.Occluder.Tracking.EmitsOnlyOnMovementPastTheThreshold",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_TrackerEmitsOnlyOnMovementPastTheThreshold::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_occluder;

    constexpr auto MovementThresholdUu = 100.0f;
    constexpr auto SixtyHertz = 1.0f / 60.0f;

    const auto StartLocation = FVector{0.0, 0.0, 0.0};

    auto EcsWorld = ck::FEcsWorld{};
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    auto TransformHandle = UCk_Utils_Transform_UE::Add(Entity, FTransform{StartLocation},
        ECk_Replication::DoesNotReplicate);

    auto Params = FCk_VoxelNavOccluder_Spec{ObstacleHalfExtents};
    Params.Set_MovementThresholdOverride(ECk_EnableDisable::Enable);
    Params.Set_MovementThresholdUuOverride(MovementThresholdUu);

    auto Occluder = UCk_Utils_VoxelNavOccluder_UE::Add(Entity, Params);

    if (NOT TestTrue(TEXT("Add returns a valid VoxelNavOccluder handle"), ck::IsValid(Occluder)))
    { return false; }

    TestTrue(TEXT("the occluder lives on the entity itself, not on a child"),
        UCk_Utils_VoxelNavOccluder_UE::Has(Entity));
    TestTrue(TEXT("the occluder is stamped NeedsSetup for its Setup processor"),
        Occluder.Has<ck::FTag_VoxelNavOccluder_NeedsSetup>());

    // Driven directly rather than through a scheduler: both processors are pure functions of the arguments
    // the view hands them, so a graph would add ordering machinery without adding coverage.
    ck::FProcessor_VoxelNavOccluder_Setup::ForEachEntity(FCk_Time{SixtyHertz}, Occluder,
        Occluder.Get<ck::FFragment_VoxelNavOccluder_Params>(),
        Occluder.Get<ck::FFragment_VoxelNavOccluder_Current>());

    TestTrue(TEXT("setup seeds the tracked bounds from the entity's own transform"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TrackedBounds(Occluder).GetCenter().Equals(StartLocation));
    TestEqual(TEXT("setup itself dirties nothing - whatever bake exists already saw the occluder here"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(Occluder), 0);

    const auto Tracker = ck::FProcessor_VoxelNavOccluder_Track{EcsWorld.Get_Registry()};

    const auto DoTrack = [&]() -> void
    {
        Tracker.ForEachEntity(FCk_Time{SixtyHertz}, Occluder,
            Occluder.Get<ck::FFragment_VoxelNavOccluder_Params>(),
            Occluder.Get<ck::FFragment_VoxelNavOccluder_Current>());
    };

    const auto DoMoveTo = [&](const FVector& InLocation) -> void
    {
        UCk_Utils_Transform_UE::Apply_SetTransform_DirectWrite(
            TransformHandle.Get<ck::FFragment_Transform>(),
            TransformHandle.Get<ck::FFragment_Transform_Previous>(),
            FTransform{InLocation});
    };

    DoTrack();
    TestEqual(TEXT("a stationary occluder never dirties anything"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(Occluder), 0);

    // Upstream compared transforms with FTransform::Equals at its default epsilon, so an occluder jittering
    // a thousandth of a unit rebuilt navigation data every frame while changing no voxel.
    DoMoveTo(FVector{MovementThresholdUu * 0.5, 0.0, 0.0});
    DoTrack();
    TestEqual(TEXT("sub-threshold drift does NOT dirty"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(Occluder), 0);
    TestTrue(TEXT("and the tracked bounds stay where they were last published"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TrackedBounds(Occluder).GetCenter().Equals(StartLocation));

    // Accumulating against the last PUBLISHED pose rather than against last frame's is what makes slow drift
    // cross the threshold eventually instead of being lost one frame at a time.
    DoMoveTo(FVector{MovementThresholdUu * 1.5, 0.0, 0.0});
    DoTrack();
    TestEqual(TEXT("drift that accumulates past the threshold DOES dirty"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(Occluder), 1);
    TestTrue(TEXT("and the tracked bounds move to the pose that was published"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TrackedBounds(Occluder).GetCenter()
            .Equals(FVector{MovementThresholdUu * 1.5, 0.0, 0.0}));

    DoTrack();
    TestEqual(TEXT("re-running the tracker on an unmoved occluder dirties nothing again"),
        UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(Occluder), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Occluder_MarkingAVolumeDirtyBeforeItBakesIsRejected,
    "Ck.VoxelNav.Occluder.Tracking.MarkingAVolumeDirtyBeforeItBakesIsRejected",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Occluder_MarkingAVolumeDirtyBeforeItBakesIsRejected::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_occluder;

    auto EcsWorld = ck::FEcsWorld{};
    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    auto Volume = UCk_Utils_VoxelNavVolume_UE::Add(Owner,
        FCk_VoxelNavVolume_Spec{VolumeBounds, FinestCellSizeUu});

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    TestTrue(TEXT("the repair state is composed up front, so a repair never allocates it mid-frame"),
        Volume.Has<ck::FFragment_VoxelNavVolume_RepairState>());
    TestFalse(TEXT("a fresh volume has no pending dirty region"),
        UCk_Utils_VoxelNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    // A dynamic delegate can only bind to a UFUNCTION on a UObject, so the outcome is observed through the
    // same counting listener the bake test uses - a count, not a flag, because the contract promises the
    // completion fires EXACTLY once.
    const auto Listener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};

    auto Delegate = FCk_Delegate_Request_OnCompleted{};
    Delegate.BindDynamic(Listener.Get(), &UCk_VoxelNavBakeTest_Listener_UE::OnBuildRequestCompleted);

    UCk_Utils_VoxelNavVolume_UE::Request_MarkDirty(Volume,
        FCk_Request_VoxelNavVolume_MarkDirty{FBox{FVector{-100.0}, FVector{100.0}}}, Delegate);

    ck::FProcessor_VoxelNavVolume_HandleRequests{EcsWorld.Get_Registry()}.ForEachEntity(
        FCk_Time{1.0f / 60.0f}, Volume,
        Volume.Get<ck::FFragment_VoxelNavVolume_Params>(),
        Volume.Get<ck::FFragment_VoxelNavVolume_BuildState>(),
        Volume.Get<ck::FFragment_VoxelNavVolume_RepairState>(),
        Volume.Get<ck::FFragment_VoxelNavVolume_Requests>());

    TestEqual(TEXT("the dirty request completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("marking a volume dirty before it has ever baked reports Failed - a LOCAL repair has no "
                  "occupancy to carry over, and a build is the answer"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);
    TestFalse(TEXT("and no repair is armed"), Volume.Has<ck::FTag_VoxelNavVolume_NeedsRepair>());
    TestFalse(TEXT("and no dirty region is retained"),
        UCk_Utils_VoxelNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
