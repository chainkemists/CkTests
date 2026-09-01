// Portal extraction — the crossings between plates, and the one number that says who fits through.
//
// The number under test is not a plate property and could not be: two rooms wide enough for anyone,
// joined by a doorway narrow enough for nobody, have generous clearance on both plates. Everything
// here exists to pin the value that catches that case, and to pin the cases where a portal must NOT
// appear at all.

#include "CkGroundNav/Bake/CkGroundNav_Clearance.h"
#include "CkGroundNav/Bake/CkGroundNav_Portals.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_portals
{
    using ck::groundnav::DoCompute_Clearance;
    using ck::groundnav::DoDecompose_Plates;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoExtract_Portals;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_Portal;
    using ck::groundnav::FCk_GroundNav_PortalField;
    using ck::groundnav::FCk_GroundNav_SpanField;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;

    struct FBakeResult
    {
        FCk_GroundNav_SpanField _Spans;
        FCk_GroundNav_LayerField _Layers;
        FCk_GroundNav_PlateField _Plates;
        FCk_GroundNav_ClearanceField _Clearance;
        FCk_GroundNav_PortalField _Portals;
        bool _Completed = false;
    };

    // The ledge filter is off throughout. It is conservative by default and would erase a corridor
    // three cells wide before the portal it leads to could be extracted — and that corridor is the
    // whole subject here.
    auto Bake(const FCk_GroundNav_GeometryBatch& InGeometry, const FBox& InRegion) -> FBakeResult
    {
        auto Result = FBakeResult{};

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};

        if (NOT DoRasterizeSpans(InGeometry, InRegion, Config, Profile, Result._Spans).Get_IsCompleted())
        { return Result; }

        auto Connections = FCk_GroundNav_ConnectionField{};

        if (NOT DoFilter_Walkability(Profile, Result._Spans, Connections).Get_IsCompleted())
        { return Result; }

        if (NOT DoExtract_Layers(Result._Spans, Connections, Result._Layers).Get_IsCompleted())
        { return Result; }

        if (NOT DoCompute_Clearance(Result._Layers, kCellSize, Result._Clearance).Get_IsCompleted())
        { return Result; }

        if (NOT DoDecompose_Plates(
            Result._Spans, Result._Layers, FCk_GroundNav_MergeTunables{}, Result._Plates).Get_IsCompleted())
        { return Result; }

        Result._Completed = DoExtract_Portals(
            Result._Spans, Result._Layers, Connections, Result._Plates, Result._Clearance,
            Result._Portals).Get_IsCompleted();

        return Result;
    }

    // A 500 uu square room with a 75 uu corridor running off its east wall — three cells wide, so the
    // corridor mouth is the only place the two plates touch.
    constexpr auto kCorridorWidthUu = 75.0;

    auto Make_RoomAndCorridor() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, -10.0}, FVector{500.0, 500.0, 0.0}});
        Geometry.Add_Box(FBox{FVector{500.0, 200.0, -10.0}, FVector{1000.0, 200.0 + kCorridorWidthUu, 0.0}});

        return Geometry;
    }

    // The same corridor, this time joining two rooms either side of it. Both rooms are wide enough
    // for any agent the corridor rejects, which is the entire point of the fixture.
    auto Make_PinchPoint() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, -10.0}, FVector{500.0, 500.0, 0.0}});
        Geometry.Add_Box(FBox{FVector{500.0, 200.0, -10.0}, FVector{750.0, 200.0 + kCorridorWidthUu, 0.0}});
        Geometry.Add_Box(FBox{FVector{750.0, 0.0, -10.0}, FVector{1250.0, 500.0, 0.0}});

        return Geometry;
    }

    // A floor and an island slab with a four-cell gap between them. Nothing reaches the island.
    auto Make_FloorAndIsland() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, -10.0}, FVector{500.0, 500.0, 0.0}});
        Geometry.Add_Box(FBox{FVector{600.0, 600.0, -10.0}, FVector{800.0, 800.0, 0.0}});

        return Geometry;
    }

    // Two decks sharing every column, joined by a ramp in the strip behind them. One continuous walk
    // that no single layer can hold, so the ramp arrives at the upper deck already on another layer.
    //
    // The shape is taken from the layer-extraction fixture that pins this exact case rather than
    // invented here: a ramp merely climbing over open floor does NOT produce a crossing, because the
    // two runs meet at a height the mutual-agreement rule then severs.
    constexpr auto kDeckLengthUu = 1000.0;
    constexpr auto kDeckDepthUu = 100.0;
    constexpr auto kUpperDeckZUu = 300.0;

    auto Make_StackedDecksWithRamp() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{kDeckLengthUu, kDeckDepthUu, 10.0}});
        Geometry.Add_Box(FBox{
            FVector{0.0, 0.0, kUpperDeckZUu},
            FVector{kDeckLengthUu, kDeckDepthUu, kUpperDeckZUu + 10.0}});

        const auto A = FVector{0.0, kDeckDepthUu, 10.0};
        const auto B = FVector{kDeckLengthUu, kDeckDepthUu, kUpperDeckZUu + 10.0};
        const auto C = FVector{kDeckLengthUu, kDeckDepthUu * 2.0, kUpperDeckZUu + 10.0};
        const auto D = FVector{0.0, kDeckDepthUu * 2.0, 10.0};

        Geometry.Add_Triangle(A, B, C);
        Geometry.Add_Triangle(A, C, D);

        return Geometry;
    }

    auto Get_PortalsMatch(const FCk_GroundNav_PortalField& InLeft, const FCk_GroundNav_PortalField& InRight) -> bool
    {
        if (InLeft._Portals.Num() != InRight._Portals.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft._Portals.Num(); ++Index)
        {
            const auto& Left = InLeft._Portals[Index];
            const auto& Right = InRight._Portals[Index];

            if (Left._PlateA == Right._PlateA && Left._PlateB == Right._PlateB &&
                Left._Direction == Right._Direction &&
                Left._FromMin == Right._FromMin && Left._FromMax == Right._FromMax &&
                Left._MinEndZUu == Right._MinEndZUu && Left._MaxEndZUu == Right._MaxEndZUu &&
                Left._TraversalClearanceUu == Right._TraversalClearanceUu)
            { continue; }

            return false;
        }

        return true;
    }

    /** The most room any single cell of the plate has — what a per-plate admission test would use. */
    auto Get_BestClearanceInPlate(
        const FCk_GroundNav_ClearanceField& InClearance,
        const FCk_GroundNav_Plate&          InPlate) -> float
    {
        auto Best = 0.0f;

        for (auto Y = InPlate._MinY; Y <= InPlate._MaxY; ++Y)
        {
            for (auto X = InPlate._MinX; X <= InPlate._MaxX; ++X)
            { Best = FMath::Max(Best, InClearance.Get_ClearanceAt(X, Y, InPlate._LayerIndex)); }
        }

        return Best;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Portals_OneDoorwayYieldsOnePortal,
    "CkTests.UnitTests.CkGroundNav.Bake.Portals_OneDoorwayYieldsOnePortal",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Portals_OneDoorwayYieldsOnePortal::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_portals;

    const auto Baked = Bake(Make_RoomAndCorridor(), FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 1000.0, 400.0}});

    if (NOT TestTrue(TEXT("the room and corridor bake"), Baked._Completed))
    { return false; }

    if (NOT TestEqual(TEXT("a room and one corridor are two plates"), Baked._Plates._Plates.Num(), 2))
    { return false; }

    TestEqual(TEXT("joined by exactly one portal"), Baked._Portals.Get_PortalCount(), 1);

    if (Baked._Portals.Get_PortalCount() != 1)
    { return false; }

    const auto& Portal = Baked._Portals._Portals[0];

    TestEqual(TEXT("spanning the whole corridor mouth"), Portal.Get_CellCount(),
        static_cast<int32>(kCorridorWidthUu / kCellSize));

    // Half the corridor width is the room a body has at the middle of the doorway. Within one cell,
    // because the field measures in cells and the doorway is only three of them wide.
    const auto Expected = static_cast<float>(kCorridorWidthUu) * 0.5f;

    TestTrue(FString::Printf(
        TEXT("whose traversal clearance is half the corridor width within one cell (%.2f vs %.2f)"),
        Portal._TraversalClearanceUu, Expected),
        FMath::Abs(Portal._TraversalClearanceUu - Expected) <= kCellSize);

    // Both ends of the portal must find it, or a search arriving from the corridor sees a dead end.
    TestEqual(TEXT("and both plates list it"),
        Baked._Portals.Get_PortalsForPlate(Portal._PlateA).Num() +
        Baked._Portals.Get_PortalsForPlate(Portal._PlateB).Num(), 2);

    TestEqual(TEXT("with each end naming the other"),
        Baked._Portals.Get_OppositePlate(0, Portal._PlateA), Portal._PlateB);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Portals_EnclosedPlateHasNone,
    "CkTests.UnitTests.CkGroundNav.Bake.Portals_EnclosedPlateHasNone",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Portals_EnclosedPlateHasNone::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_portals;

    const auto Baked = Bake(Make_FloorAndIsland(), FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 1000.0, 400.0}});

    if (NOT TestTrue(TEXT("the floor and island bake"), Baked._Completed))
    { return false; }

    if (NOT TestEqual(TEXT("a floor and an unreachable island are two plates"),
        Baked._Plates._Plates.Num(), 2))
    { return false; }

    TestEqual(TEXT("with nothing crossing the gap between them"), Baked._Portals.Get_PortalCount(), 0);

    TestEqual(TEXT("so the island lists no portals"),
        Baked._Portals.Get_PortalsForPlate(1).Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Portals_PinchPointRejectsWhatPlateClearanceAdmits,
    "CkTests.UnitTests.CkGroundNav.Bake.Portals_PinchPointRejectsWhatPlateClearanceAdmits",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Portals_PinchPointRejectsWhatPlateClearanceAdmits::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_portals;

    const auto Baked = Bake(Make_PinchPoint(), FBox{FVector{0.0, 0.0, -50.0}, FVector{1300.0, 600.0, 400.0}});

    if (NOT TestTrue(TEXT("the pinch point bakes"), Baked._Completed))
    { return false; }

    if (NOT TestEqual(TEXT("two rooms and the corridor between them are three plates"),
        Baked._Plates._Plates.Num(), 3))
    { return false; }

    if (NOT TestEqual(TEXT("joined by two portals"), Baked._Portals.Get_PortalCount(), 2))
    { return false; }

    // Wider than the corridor can pass and narrower than either room's most open cell. Every claim
    // below is about this one body.
    constexpr auto kAgentRadiusUu = 100.0f;

    for (const auto& Portal : Baked._Portals._Portals)
    {
        TestTrue(FString::Printf(TEXT("the crossing rejects a %.0f uu radius (offers %.2f)"),
            kAgentRadiusUu, Portal._TraversalClearanceUu),
            Portal._TraversalClearanceUu < kAgentRadiusUu);
    }

    // And the mistake the portal exists to prevent: asking the plates instead would have let it
    // through, because both rooms are enormous compared to the doorway joining them.
    auto AdmittingPlateCount = 0;

    for (const auto& Plate : Baked._Plates._Plates)
    {
        if (Get_BestClearanceInPlate(Baked._Clearance, Plate) >= kAgentRadiusUu)
        { ++AdmittingPlateCount; }
    }

    TestEqual(TEXT("while both rooms would have admitted it on their own clearance"),
        AdmittingPlateCount, 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Portals_AreIdenticalAcrossBakes,
    "CkTests.UnitTests.CkGroundNav.Bake.Portals_AreIdenticalAcrossBakes",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Portals_AreIdenticalAcrossBakes::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_portals;

    const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{1300.0, 600.0, 400.0}};
    const auto Reference = Bake(Make_PinchPoint(), Region);

    if (NOT TestTrue(TEXT("the reference bake completes"), Reference._Completed))
    { return false; }

    if (NOT TestTrue(TEXT("and produces portals to compare"), Reference._Portals.Get_PortalCount() > 0))
    { return false; }

    for (auto Run = 0; Run < 8; ++Run)
    {
        const auto Repeat = Bake(Make_PinchPoint(), Region);

        if (NOT TestTrue(FString::Printf(TEXT("run %d reproduces the portals exactly"), Run),
            Get_PortalsMatch(Reference._Portals, Repeat._Portals)))
        { return false; }
    }

    // Submission order is the input most likely to reorder anything downstream, and a portal index
    // that moved would silently repoint every adjacency built on top of it.
    auto Reversed = FCk_GroundNav_GeometryBatch{};
    Reversed.Add_Box(FBox{FVector{750.0, 0.0, -10.0}, FVector{1250.0, 500.0, 0.0}});
    Reversed.Add_Box(FBox{FVector{500.0, 200.0, -10.0}, FVector{750.0, 200.0 + kCorridorWidthUu, 0.0}});
    Reversed.Add_Box(FBox{FVector{0.0, 0.0, -10.0}, FVector{500.0, 500.0, 0.0}});

    const auto FromReversed = Bake(Reversed, Region);

    TestTrue(TEXT("and reversing the geometry order reproduces them too"),
        Get_PortalsMatch(Reference._Portals, FromReversed._Portals));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Portals_CrossLayerCrossingIsFound,
    "CkTests.UnitTests.CkGroundNav.Bake.Portals_CrossLayerCrossingIsFound",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Portals_CrossLayerCrossingIsFound::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_portals;

    const auto Baked = Bake(Make_StackedDecksWithRamp(),
        FBox{FVector{0.0, 0.0, -50.0}, FVector{kDeckLengthUu, kDeckDepthUu * 2.0, 600.0}});

    if (NOT TestTrue(TEXT("the stacked decks bake"), Baked._Completed))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("two decks over one footprint make two layers (made %d)"),
        Baked._Layers._LayerCount), Baked._Layers._LayerCount >= 2))
    { return false; }

    auto CrossLayerCount = 0;

    for (const auto& Portal : Baked._Portals._Portals)
    {
        const auto LayerA = Baked._Plates._Plates[Portal._PlateA]._LayerIndex;
        const auto LayerB = Baked._Plates._Plates[Portal._PlateB]._LayerIndex;

        if (LayerA != LayerB)
        { ++CrossLayerCount; }
    }

    // The connection field names the neighbouring SPAN, so a crossing that changes floor needs no
    // special case to be found. If this ever reads zero, the extraction has started reasoning about
    // plate rectangles instead of about connections.
    TestTrue(FString::Printf(TEXT("and the crossing between them is extracted (found %d)"), CrossLayerCount),
        CrossLayerCount > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
