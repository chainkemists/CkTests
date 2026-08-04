#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Morton.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Rasterize.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the engine-light octree core: Morton addressing, the packed node-ref (which is also the
// serialization form), layer sizing against hand-computed volumes, neighbour addressing on a hand-built
// two-layer octree, and FCellId's kind dispatch. Fully hermetic - plain values, no world, no PIE.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_octree
{
    constexpr auto FinestCellSizeUu = 50.0f;

    // 400uu across at a 50uu finest cell: leaf size 200uu, voxel exponent 1, exactly two layers.
    // Layer 0 is a 2x2x2 lattice of 200uu leaves; layer 1 is the single 400uu root above them.
    constexpr auto TwoLayerLeafCount = 8;

    static auto
        Make_TwoLayerOctree()
        -> ck::voxelnav::FOctree
    {
        using namespace ck::voxelnav;

        auto Octree = FOctree{};
        Request_InitializeOctree(Octree, FinestCellSizeUu, FBox{FVector{-200.0}, FVector{200.0}});

        for (auto MortonIdx = 0; MortonIdx < TwoLayerLeafCount; ++MortonIdx)
        { Octree.Get_Layer(0).Get_Nodes().Emplace(static_cast<MortonCode>(MortonIdx)); }

        Octree.Get_LeafNodes().Request_SetLeafCount(TwoLayerLeafCount);

        auto RootNode = FNode{0};
        RootNode.Set_FirstChild(FNodeAddress::Make(0, 0));
        Octree.Get_Layer(1).Get_Nodes().Emplace(RootNode);

        for (auto LeafIdx = 0; LeafIdx < TwoLayerLeafCount; ++LeafIdx)
        { Octree.Get_LeafNodes().Get_LeafNode(LeafIdx).Set_Parent(FNodeAddress::Make(1, 0)); }

        Request_MarkOctreeBuilt(Octree);

        return Octree;
    }

    // 1600uu across at a 50uu finest cell: voxel exponent 3, four layers, layer-0 lattice 8x8x8. Layers
    // 3, 2 and 1 each carry the one subdivided node covering the far corner; layer 0 deliberately does
    // NOT, so a lookup there descends the whole way and lands in free space at a Morton code that no
    // six-bit field could hold.
    static auto
        Make_DescendingOctree()
        -> ck::voxelnav::FOctree
    {
        using namespace ck::voxelnav;

        auto Octree = FOctree{};
        Request_InitializeOctree(Octree, FinestCellSizeUu, FBox{FVector{-800.0}, FVector{800.0}});

        auto RootNode = FNode{0};
        RootNode.Set_FirstChild(FNodeAddress::Make(2, 0));
        Octree.Get_Layer(3).Get_Nodes().Emplace(RootNode);

        auto MidNode = FNode{7};
        MidNode.Set_FirstChild(FNodeAddress::Make(1, 0));
        Octree.Get_Layer(2).Get_Nodes().Emplace(MidNode);

        auto LowNode = FNode{63};
        LowNode.Set_FirstChild(FNodeAddress::Make(0, 0));
        Octree.Get_Layer(1).Get_Nodes().Emplace(LowNode);

        Octree.Get_Layer(0).Get_Nodes().Emplace(static_cast<MortonCode>(0));
        Octree.Get_LeafNodes().Request_SetLeafCount(1);
        Octree.Get_LeafNodes().Get_LeafNode(0).Set_Parent(FNodeAddress::Make(1, 0));

        Request_MarkOctreeBuilt(Octree);

        return Octree;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_MortonRoundTripsIncludingBoundaryCoords,
    "Ck.VoxelNav.Octree.MortonRoundTripsIncludingBoundaryCoords",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_MortonRoundTripsIncludingBoundaryCoords::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    struct FMortonCase
    {
        FIntVector _Coords;
        MortonCode _Code;
        const TCHAR* _What;
    };

    const FMortonCase Cases[] =
    {
        {FIntVector{0, 0, 0}, 0,                     TEXT("origin")},
        {FIntVector{1, 0, 0}, 1,                     TEXT("unit X sits in the lowest bit of each triplet")},
        {FIntVector{0, 1, 0}, 2,                     TEXT("unit Y sits one bit above X")},
        {FIntVector{0, 0, 1}, 4,                     TEXT("unit Z sits two bits above X")},
        {FIntVector{1, 1, 1}, 7,                     TEXT("the first octant corner")},
        {FIntVector{3, 3, 3}, 63,                    TEXT("the last sub-node of a leaf")},
        {FIntVector{1023, 1023, 1023}, 0x3FFFFFFFull, TEXT("ten bits per axis")},
        {FIntVector{GMaxMortonCoord, GMaxMortonCoord, GMaxMortonCoord}, 0x7FFFFFFFFFFFFFFFull,
            TEXT("the encoder's boundary coordinate - twenty-one bits per axis")}
    };

    for (const auto& Case : Cases)
    {
        TestEqual(Case._What,
            static_cast<int64>(Get_MortonFromCoords(Case._Coords)),
            static_cast<int64>(Case._Code));

        TestTrue(Case._What, Get_CoordsFromMorton(Case._Code) == Case._Coords);
    }

    TestTrue(TEXT("decoding to a vector agrees with decoding to coordinates"),
        Get_VectorFromMorton(7).Equals(FVector{1.0, 1.0, 1.0}, 0.001));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_MortonWalksParentAndChildCodes,
    "Ck.VoxelNav.Octree.MortonWalksParentAndChildCodes",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_MortonWalksParentAndChildCodes::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    TestEqual(TEXT("a parent code drops three bits"),
        static_cast<int64>(Get_ParentMorton(63)), static_cast<int64>(7));

    TestEqual(TEXT("the first child code adds three bits"),
        static_cast<int64>(Get_FirstChildMorton(7)), static_cast<int64>(56));

    TestEqual(TEXT("the eight children of a parent are contiguous"),
        static_cast<int64>(Get_ParentMorton(Get_FirstChildMorton(7) + 7)), static_cast<int64>(7));

    TestEqual(TEXT("walking two layers coarser drops six bits"),
        static_cast<int64>(Get_ParentMortonAtLayer(511, 2, 0)), static_cast<int64>(7));

    TestEqual(TEXT("a target layer at or below the child's leaves the code untouched"),
        static_cast<int64>(Get_ParentMortonAtLayer(511, 0, 2)), static_cast<int64>(511));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_LayerSizingMatchesHandComputedVolume,
    "Ck.VoxelNav.Octree.LayerSizingMatchesHandComputedVolume",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_LayerSizingMatchesHandComputedVolume::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    // 6400uu across at a 50uu finest cell: leaf 200uu, 6400/200 == 32 leaves, exponent 5, six layers.
    auto Octree = FOctree{};

    if (NOT TestTrue(TEXT("a 6400uu volume initializes"),
        Request_InitializeOctree(Octree, 50.0f, FBox{FVector{-3200.0}, FVector{3200.0}})))
    { return false; }

    TestEqual(TEXT("six layers"), Octree.Get_LayerCount(), 6);

    TestEqual(TEXT("leaf node size is four finest cells"), Octree.Get_LeafNodes().Get_LeafNodeSize(), 200.0f);
    TestEqual(TEXT("leaf node extent"), Octree.Get_LeafNodes().Get_LeafNodeExtent(), 100.0f);
    TestEqual(TEXT("leaf sub-node size is the finest cell"), Octree.Get_LeafNodes().Get_LeafSubNodeSize(), 50.0f);
    TestEqual(TEXT("leaf sub-node extent"), Octree.Get_LeafNodes().Get_LeafSubNodeExtent(), 25.0f);

    TestEqual(TEXT("layer 0 edge node count"), Octree.Get_Layer(0).Get_EdgeNodeCount(), 32);
    TestEqual(TEXT("layer 0 cube capacity"), Octree.Get_Layer(0).Get_MaxNodeCount(), 32768);
    TestEqual(TEXT("layer 0 node size"), Octree.Get_Layer(0).Get_NodeSize(), 200.0f);

    TestEqual(TEXT("layer 1 edge node count"), Octree.Get_Layer(1).Get_EdgeNodeCount(), 16);
    TestEqual(TEXT("layer 1 cube capacity"), Octree.Get_Layer(1).Get_MaxNodeCount(), 4096);
    TestEqual(TEXT("layer 1 node size"), Octree.Get_Layer(1).Get_NodeSize(), 400.0f);

    TestEqual(TEXT("the coarsest layer is a single node"), Octree.Get_Layer(5).Get_EdgeNodeCount(), 1);
    TestEqual(TEXT("the coarsest layer spans the whole volume"), Octree.Get_Layer(5).Get_NodeSize(), 6400.0f);

    TestTrue(TEXT("a volume that is already a power of two needs no snap"),
        Octree.Get_NavigationBounds().GetSize().Equals(FVector{6400.0}, 0.01));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_LayerSizingSnapsNavigationBoundsToPowerOfTwo,
    "Ck.VoxelNav.Octree.LayerSizingSnapsNavigationBoundsToPowerOfTwo",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_LayerSizingSnapsNavigationBoundsToPowerOfTwo::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    // 5000uu across at a 50uu finest cell: 5000/200 == 25 leaves, so the exponent rounds up to 5 and the
    // navigation bounds snap out to 32 leaves == 6400uu, still centred on the authored volume.
    const auto VolumeBounds = FBox{FVector{0.0}, FVector{5000.0}};

    auto Octree = FOctree{};

    if (NOT TestTrue(TEXT("a 5000uu volume initializes"),
        Request_InitializeOctree(Octree, 50.0f, VolumeBounds)))
    { return false; }

    TestEqual(TEXT("six layers"), Octree.Get_LayerCount(), 6);

    TestTrue(TEXT("navigation bounds snap UP to the next power-of-two cube"),
        Octree.Get_NavigationBounds().GetSize().Equals(FVector{6400.0}, 0.01));

    TestTrue(TEXT("the snapped cube stays centred on the authored volume"),
        Octree.Get_NavigationBounds().GetCenter().Equals(VolumeBounds.GetCenter(), 0.01));

    TestTrue(TEXT("the authored bounds are kept verbatim alongside the snapped cube"),
        Octree.Get_VolumeBounds().GetSize().Equals(FVector{5000.0}, 0.01));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_LayerSizingRejectsVolumeSmallerThanOneLeaf,
    "Ck.VoxelNav.Octree.LayerSizingRejectsVolumeSmallerThanOneLeaf",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_LayerSizingRejectsVolumeSmallerThanOneLeaf::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    AddExpectedError(TEXT("smaller than a single leaf node"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("degenerate bounds"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto Octree = FOctree{};

    TestFalse(TEXT("a volume exactly one leaf across is rejected"),
        Request_InitializeOctree(Octree, 50.0f, FBox{FVector{-100.0}, FVector{100.0}}));

    TestEqual(TEXT("a rejected initialize leaves no layers behind"), Octree.Get_LayerCount(), 0);
    TestFalse(TEXT("a rejected octree never reads as valid"), Octree.Get_IsValid());

    TestFalse(TEXT("degenerate bounds are rejected"),
        Request_InitializeOctree(Octree, 50.0f, FBox{ForceInit}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_PackedNodeRefRoundTripsThroughSerializationForm,
    "Ck.VoxelNav.Octree.PackedNodeRefRoundTripsThroughSerializationForm",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_PackedNodeRefRoundTripsThroughSerializationForm::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    const auto Address = FNodeAddress::Make(5, 1234567, 42);

    TestTrue(TEXT("a fully-specified address is valid"), Address.Get_IsValid());
    TestEqual(TEXT("layer round-trips"), static_cast<int32>(Address.Get_LayerIndex()), 5);
    TestEqual(TEXT("node index round-trips"), Address.Get_NodeIndex(), 1234567);
    TestEqual(TEXT("sub-node index round-trips"), static_cast<int32>(Address.Get_SubNodeIndex()), 42);

    const auto ExpectedPacked = (static_cast<uint32>(5) << 28) | (static_cast<uint32>(1234567) << 6) | 42u;

    TestEqual(TEXT("the packed layout is Layer<<28 | Node<<6 | SubNode"),
        static_cast<int64>(Address.Get_Packed()), static_cast<int64>(ExpectedPacked));

    // The serialization form is the packed word, and unpacking it shifts RIGHT back out of each field.
    const auto Restored = FNodeAddress::Make_FromPacked(Address.Get_Packed());

    TestTrue(TEXT("the packed word round-trips to an equal address"), Restored == Address);
    TestEqual(TEXT("the restored layer is extracted, not re-shifted in"),
        static_cast<int32>(Restored.Get_LayerIndex()), 5);
    TestEqual(TEXT("the restored node index is extracted, not re-shifted in"), Restored.Get_NodeIndex(), 1234567);
    TestEqual(TEXT("the restored sub-node index is extracted, not re-shifted in"),
        static_cast<int32>(Restored.Get_SubNodeIndex()), 42);

    const auto MaxAddress = FNodeAddress::Make(
        FNodeAddress::MaxLayerIndex, FNodeAddress::MaxNodeIndex, FNodeAddress::MaxSubNodeIndex);

    TestTrue(TEXT("the widest addressable value round-trips"),
        FNodeAddress::Make_FromPacked(MaxAddress.Get_Packed()) == MaxAddress);

    const auto InvalidAddress = FNodeAddress{};

    TestFalse(TEXT("a default address is invalid"), InvalidAddress.Get_IsValid());
    TestEqual(TEXT("the invalid encoding is the reserved layer nibble"),
        static_cast<int64>(InvalidAddress.Get_Packed()), static_cast<int64>(FNodeAddress::InvalidPacked));
    TestTrue(TEXT("an invalid address round-trips without diagnostics"),
        FNodeAddress::Make_FromPacked(FNodeAddress::InvalidPacked) == InvalidAddress);

    TestEqual(TEXT("the hash is the packed word"),
        static_cast<int64>(GetTypeHash(Address)), static_cast<int64>(Address.Get_Packed()));

    auto Mutated = Address;
    Mutated.Set_NodeIndex(7);

    TestEqual(TEXT("setting the node index rewrites only that field"), Mutated.Get_NodeIndex(), 7);
    TestEqual(TEXT("the layer survives a node-index write"), static_cast<int32>(Mutated.Get_LayerIndex()), 5);
    TestEqual(TEXT("the sub-node survives a node-index write"),
        static_cast<int32>(Mutated.Get_SubNodeIndex()), 42);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_PackedNodeRefRejectsOutOfRangeFields,
    "Ck.VoxelNav.Octree.PackedNodeRefRejectsOutOfRangeFields",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_PackedNodeRefRejectsOutOfRangeFields::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    AddExpectedError(TEXT("Cannot pack a VoxelNav node address"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("does not encode a VoxelNav node address"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    TestFalse(TEXT("the merged-cell layer nibble is not addressable as a node"),
        FNodeAddress::Make(FNodeAddress::MergedCellLayer, 0, 0).Get_IsValid());

    TestFalse(TEXT("a node index wider than 22 bits is rejected"),
        FNodeAddress::Make(0, FNodeAddress::MaxNodeIndex + 1, 0).Get_IsValid());

    TestFalse(TEXT("a sub-node index wider than 6 bits is rejected"),
        FNodeAddress::Make(0, 0, FNodeAddress::MaxSubNodeIndex + 1).Get_IsValid());

    TestFalse(TEXT("unpacking a merged-cell word does not yield a node address"),
        FNodeAddress::Make_FromPacked(static_cast<uint32>(FNodeAddress::MergedCellLayer) << 28).Get_IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_CellIdDispatchesOnKind,
    "Ck.VoxelNav.Octree.CellIdDispatchesOnKind",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_CellIdDispatchesOnKind::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    const auto Volume = FVolumeId{7};
    const auto NodeAddress = FNodeAddress::Make(2, 99, 3);

    const auto NodeCell = FCellId::Make_FromNodeAddress(Volume, NodeAddress);

    TestTrue(TEXT("a node cell is valid"), NodeCell.Get_IsValid());
    TestTrue(TEXT("a node cell reports the OctreeNode kind"), NodeCell.Get_Kind() == ECellKind::OctreeNode);
    TestTrue(TEXT("the volume qualifier round-trips"), NodeCell.Get_Volume() == Volume);
    TestTrue(TEXT("the node address round-trips"), NodeCell.Get_NodeAddress() == NodeAddress);

    const auto MergedCell = FCellId::Make_FromMergedIndex(Volume, 123456);

    TestTrue(TEXT("a merged cell is valid"), MergedCell.Get_IsValid());
    TestTrue(TEXT("a merged cell reports the Merged kind"), MergedCell.Get_Kind() == ECellKind::Merged);
    TestEqual(TEXT("the merged index round-trips"), MergedCell.Get_MergedIndex(), 123456);

    TestTrue(TEXT("the two kinds are distinct identities"), MergedCell != NodeCell);

    const auto OtherVolumeCell = FCellId::Make_FromNodeAddress(FVolumeId{8}, NodeAddress);

    TestTrue(TEXT("the same node in another volume is a different cell"), OtherVolumeCell != NodeCell);
    TestTrue(TEXT("the volume qualifier reaches the hash"),
        GetTypeHash(OtherVolumeCell) != GetTypeHash(NodeCell));

    TestFalse(TEXT("a default cell is invalid"), FCellId{}.Get_IsValid());

    AddExpectedError(TEXT("is not an octree-node cell"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("is not a merged cell"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    TestFalse(TEXT("a merged cell refuses to hand back a node address"),
        MergedCell.Get_NodeAddress().Get_IsValid());

    TestEqual(TEXT("a node cell refuses to hand back a merged index"),
        NodeCell.Get_MergedIndex(), static_cast<int32>(INDEX_NONE));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_NeighbourAddressingOnTwoLayerOctree,
    "Ck.VoxelNav.Octree.NeighbourAddressingOnTwoLayerOctree",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_NeighbourAddressingOnTwoLayerOctree::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_octree;

    auto Octree = Make_TwoLayerOctree();

    if (NOT TestEqual(TEXT("the fixture has two layers"), Octree.Get_LayerCount(), 2))
    { return false; }

    TestEqual(TEXT("layer 0 is a 2x2x2 lattice"), Octree.Get_Layer(0).Get_EdgeNodeCount(), 2);
    TestEqual(TEXT("layer 0 holds all eight leaves"), Octree.Get_Layer(0).Get_NodeCount(), 8);

    TestTrue(TEXT("leaf 0 sits at the volume's min octant centre"),
        Get_NodePositionFromLayerAndMorton(Octree, 0, 0).Equals(FVector{-100.0}, 0.01));
    TestTrue(TEXT("leaf 7 sits at the volume's max octant centre"),
        Get_NodePositionFromLayerAndMorton(Octree, 0, 7).Equals(FVector{100.0}, 0.01));
    TestTrue(TEXT("the root node sits at the volume centre"),
        Get_NodePositionFromAddress(Octree, FNodeAddress::Make(1, 0), ECk_VoxelNav_SubNodePrecision::NodeCenter)
            .Equals(FVector::ZeroVector, 0.01));

    // The step +X from lattice (0,0,0) stays inside the layer and lands on Morton code 1.
    const auto InboundSearch = TryFind_NeighbourInDirection(Octree, 0, 0, 0);

    TestTrue(TEXT("an in-lattice step resolves"), InboundSearch._Resolved);
    TestTrue(TEXT("an in-lattice step names the adjacent node"),
        InboundSearch._NeighbourAddress == FNodeAddress::Make(0, 1));

    // The step +X from lattice (1,0,0) leaves a 2-wide lattice. The bound is the EDGE node count, so it
    // is rejected here; against the cube capacity (8) it would survive, miss the scan, and degrade into a
    // climb to the parent.
    const auto OutOfLatticeSearch = TryFind_NeighbourInDirection(Octree, 0, 1, 0);

    TestTrue(TEXT("a step out of the lattice resolves rather than degrading into a parent climb"),
        OutOfLatticeSearch._Resolved);
    TestFalse(TEXT("a step out of the lattice names no neighbour"),
        OutOfLatticeSearch._NeighbourAddress.Get_IsValid());

    const auto NegativeSearch = TryFind_NeighbourInDirection(Octree, 0, 0, 1);

    TestTrue(TEXT("a step below the lattice resolves"), NegativeSearch._Resolved);
    TestFalse(TEXT("a step below the lattice names no neighbour"),
        NegativeSearch._NeighbourAddress.Get_IsValid());

    auto Scratch = FRasterizeScratch{};
    Request_InitializeScratch(Octree, Scratch);

    const auto LinkResult = Stage_BuildNeighbourLinks(Octree, Scratch, 0);

    TestTrue(TEXT("the neighbour-link stage completes"), LinkResult._StageComplete);

    const auto& CornerNode = Octree.Get_Layer(0).Get_Node(0);

    TestTrue(TEXT("+X links to Morton 1"), CornerNode.Get_Neighbour(0) == FNodeAddress::Make(0, 1));
    TestTrue(TEXT("+Y links to Morton 2"), CornerNode.Get_Neighbour(2) == FNodeAddress::Make(0, 2));
    TestTrue(TEXT("+Z links to Morton 4"), CornerNode.Get_Neighbour(4) == FNodeAddress::Make(0, 4));
    TestFalse(TEXT("-X leaves the volume"), CornerNode.Get_Neighbour(1).Get_IsValid());
    TestFalse(TEXT("-Y leaves the volume"), CornerNode.Get_Neighbour(3).Get_IsValid());
    TestFalse(TEXT("-Z leaves the volume"), CornerNode.Get_Neighbour(5).Get_IsValid());

    auto Neighbours = TArray<FNodeAddress>{};
    Get_NodeNeighbours(Octree, FNodeAddress::Make(0, 0), Neighbours);

    TestEqual(TEXT("the min corner has exactly three in-volume neighbours"), Neighbours.Num(), 3);
    TestTrue(TEXT("neighbour enumeration reports +X"), Neighbours.Contains(FNodeAddress::Make(0, 1)));
    TestTrue(TEXT("neighbour enumeration reports +Y"), Neighbours.Contains(FNodeAddress::Make(0, 2)));
    TestTrue(TEXT("neighbour enumeration reports +Z"), Neighbours.Contains(FNodeAddress::Make(0, 4)));

    auto CellNeighbours = TArray<FCellId>{};
    const auto Volume = FVolumeId{3};
    Get_CellNeighbors(Octree, FCellId::Make_FromNodeAddress(Volume, FNodeAddress::Make(0, 0)), CellNeighbours);

    TestEqual(TEXT("the cell seam reports the same fan-out"), CellNeighbours.Num(), 3);
    TestTrue(TEXT("the cell seam keeps the volume qualifier"),
        CellNeighbours.Num() > 0 && CellNeighbours[0].Get_Volume() == Volume);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_PositionLookupReportsFreeSpaceWithFullWidthMorton,
    "Ck.VoxelNav.Octree.PositionLookupReportsFreeSpaceWithFullWidthMorton",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_PositionLookupReportsFreeSpaceWithFullWidthMorton::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_octree;

    const auto Octree = Make_DescendingOctree();

    if (NOT TestEqual(TEXT("the fixture has four layers"), Octree.Get_LayerCount(), 4))
    { return false; }

    TestEqual(TEXT("layer 0 is an 8x8x8 lattice"), Octree.Get_Layer(0).Get_EdgeNodeCount(), 8);

    // (700,700,700) is lattice cell (7,7,7) on layer 0, whose Morton code is 511.
    const auto Result = TryGet_NodeAddressFromPosition(Octree, FVector{700.0}, 0);

    TestTrue(TEXT("a position inside no node reports free space, not a node"),
        Result._Outcome == ECk_VoxelNav_AddressLookup::FreeSpaceAtLayer);

    TestEqual(TEXT("free space is reported at the finest layer the walk reached"),
        static_cast<int32>(Result._Layer), 0);

    TestEqual(TEXT("the free-space Morton code is carried at full width"),
        static_cast<int64>(Result._Morton), static_cast<int64>(511));

    TestTrue(TEXT("the free-space Morton code does not survive a six-bit field, so it cannot ride in one"),
        Result._Morton != (Result._Morton & 0x3Full));

    TestFalse(TEXT("free space carries no node address"), Result._Address.Get_IsValid());

    const auto OutOfBounds = TryGet_NodeAddressFromPosition(Octree, FVector{100000.0}, 0);

    TestTrue(TEXT("a position outside the navigation bounds reports OutOfBounds"),
        OutOfBounds._Outcome == ECk_VoxelNav_AddressLookup::OutOfBounds);

    const auto EmptyOctree = FOctree{};
    const auto NoLayers = TryGet_NodeAddressFromPosition(EmptyOctree, FVector::ZeroVector, 0);

    TestTrue(TEXT("an uninitialized octree reports NoLayers"),
        NoLayers._Outcome == ECk_VoxelNav_AddressLookup::NoLayers);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_BlockedPropagationDeduplicatesParents,
    "Ck.VoxelNav.Octree.BlockedPropagationDeduplicatesParents",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_BlockedPropagationDeduplicatesParents::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    // 1600uu across at a 50uu finest cell: four layers.
    auto Octree = FOctree{};

    if (NOT TestTrue(TEXT("the fixture initializes"),
        Request_InitializeOctree(Octree, 50.0f, FBox{FVector{-800.0}, FVector{800.0}})))
    { return false; }

    auto Scratch = FRasterizeScratch{};
    Request_InitializeScratch(Octree, Scratch);

    TestEqual(TEXT("the scratch carries one blocked set past the top layer"),
        Scratch._BlockedNodes.Num(), Octree.Get_LayerCount() + 1);

    // All eight children of parent 0 are blocked, plus one child of parent 1.
    for (auto ChildCode = 0; ChildCode < 8; ++ChildCode)
    { Scratch._BlockedNodes[0].Add(static_cast<MortonCode>(ChildCode)); }

    Scratch._BlockedNodes[0].Add(static_cast<MortonCode>(8));

    Stage_PropagateBlockedUpward(Octree, Scratch);

    TestEqual(TEXT("eight blocked siblings contribute their shared parent exactly once"),
        Scratch._BlockedNodes[1].Num(), 2);

    TestTrue(TEXT("the shared parent is recorded"), Scratch._BlockedNodes[1].Contains(0));
    TestTrue(TEXT("the second parent is recorded"), Scratch._BlockedNodes[1].Contains(1));

    TestEqual(TEXT("both parents collapse into a single grandparent"),
        Scratch._BlockedNodes[2].Num(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_LayerRasterizationVisitsOnlyBlockedSubtrees,
    "Ck.VoxelNav.Octree.LayerRasterizationVisitsOnlyBlockedSubtrees",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_LayerRasterizationVisitsOnlyBlockedSubtrees::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;

    // Layer 1 of this octree has a cube capacity of 64; a single blocked parent must produce eight nodes,
    // not a scan of all 64 cells.
    auto Octree = FOctree{};

    if (NOT TestTrue(TEXT("the fixture initializes"),
        Request_InitializeOctree(Octree, 50.0f, FBox{FVector{-800.0}, FVector{800.0}})))
    { return false; }

    TestEqual(TEXT("layer 1 has a cube capacity of 64"), Octree.Get_Layer(1).Get_MaxNodeCount(), 64);

    auto Scratch = FRasterizeScratch{};
    Request_InitializeScratch(Octree, Scratch);

    // One blocked layer-2 parent, whose eight layer-1 children are the nodes to create.
    Scratch._BlockedNodes[1].Add(0);

    const auto Result = Stage_RasterizeLayer(Octree, Scratch, 1);

    TestTrue(TEXT("the layer stage completes"), Result._StageComplete);
    TestEqual(TEXT("the stage spends no occupancy probes"), Result._ProbesSpent, 0);
    TestEqual(TEXT("exactly the eight children of the blocked parent are created"),
        Octree.Get_Layer(1).Get_NodeCount(), 8);

    auto NodesAreMortonOrdered = true;
    for (auto NodeIdx = 0; NodeIdx < Octree.Get_Layer(1).Get_NodeCount(); ++NodeIdx)
    {
        NodesAreMortonOrdered &=
            Octree.Get_Layer(1).Get_Node(NodeIdx).Get_MortonCode() == static_cast<MortonCode>(NodeIdx);
    }

    TestTrue(TEXT("the created nodes are in ascending Morton order"), NodesAreMortonOrdered);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Octree_RandomFreePointSamplesTheTopLayer,
    "Ck.VoxelNav.Octree.RandomFreePointSamplesTheTopLayer",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Octree_RandomFreePointSamplesTheTopLayer::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_octree;

    auto Octree = Make_TwoLayerOctree();
    auto Stream = FRandomStream{1337};

    // The top layer index is LayerCount-1. Reading one past it would index off the end of the layer array.
    const auto Sampled = TryGet_RandomFreePoint(Octree, Stream);

    if (NOT TestTrue(TEXT("a free point is found"), Sampled.IsSet()))
    { return false; }

    TestTrue(TEXT("the sampled point lies inside the navigation bounds"),
        Octree.Get_NavigationBounds().ExpandBy(1.0).IsInside(Sampled.GetValue()));

    auto RepeatStream = FRandomStream{1337};
    const auto Repeated = TryGet_RandomFreePoint(Octree, RepeatStream);

    TestTrue(TEXT("the same seed samples the same point"),
        Repeated.IsSet() && Repeated.GetValue().Equals(Sampled.GetValue(), 0.001));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
