// Walkability filtering — low clearance, ledges, and the connection mask.
//
// These three passes decide what "standable" means for the entire navigation stack: the constrain
// processor that owns grounded agent transforms trusts this answer, so a span wrongly kept is an
// agent walking off a roof.
//
// Every fixture below is a hand-authored box list rasterized headless, and every assertion is a
// count of spans or of connections.

#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"
#include "CkGroundNav/Bake/CkGroundNav_Walkability.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_walkability
{
    using ck::groundnav::DoBuild_Connections;
    using ck::groundnav::DoFilter_Ledges;
    using ck::groundnav::DoFilter_LowClearance;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_Span;
    using ck::groundnav::FCk_GroundNav_SpanField;

    // A capsule of a chosen full standing height: the capsule's total height is twice its half
    // height plus twice its radius, so a fixed radius leaves the half height to carry the number.
    auto Make_ProfileOfHeight(float InStandingHeightUu) -> FCk_GroundNav_AgentProfile
    {
        constexpr auto Radius = 20.0f;
        const auto HalfHeight = (InStandingHeightUu * 0.5f) - Radius;

        return FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{HalfHeight, Radius}}};
    }

    auto Rasterize(
        const FCk_GroundNav_GeometryBatch& InGeometry,
        const FBox&                        InRegion,
        float                              InCellSizeUu,
        const FCk_GroundNav_AgentProfile&  InProfile,
        FCk_GroundNav_SpanField&           OutField) -> bool
    {
        const auto Config = FCk_GroundNav_BakeConfig{InCellSizeUu, 10.0f};

        return DoRasterizeSpans(InGeometry, InRegion, Config, InProfile, OutField).Get_IsCompleted();
    }

    auto Get_WalkableSpanCountAtIndex(const FCk_GroundNav_SpanField& InField, int32 InSpanIndex) -> int32
    {
        auto Count = 0;

        for (const auto& Column : InField._Columns)
        {
            if (Column.IsValidIndex(InSpanIndex) && Column[InSpanIndex]._IsWalkable)
            { ++Count; }
        }

        return Count;
    }

    // Walkable spans in one column of the lattice whose surface sits at the given height. Spans are
    // built from faces, so a column under a plateau also carries the ground beneath it — counting a
    // whole column would conflate two different floors.
    auto Get_WalkableCountAtXAndHeight(
        const FCk_GroundNav_SpanField& InField,
        int32                          InX,
        float                          InTopZ) -> int32
    {
        auto Count = 0;

        for (auto Y = 0; Y < InField._SizeY; ++Y)
        {
            for (const auto& Span : InField.Get_Column(InX, Y))
            {
                if (Span._IsWalkable && FMath::IsNearlyEqual(Span._MaxZ, InTopZ, 1.0f))
                { ++Count; }
            }
        }

        return Count;
    }

    // Directed connections recorded along +X, which for a strip laid out along X is exactly the
    // count of adjacent pairs that stayed joined.
    auto Get_ConnectionCountAlongX(const FCk_GroundNav_ConnectionField& InField) -> int32
    {
        auto Count = 0;

        for (auto Y = 0; Y < InField._SizeY; ++Y)
        {
            for (auto X = 0; X < InField._SizeX; ++X)
            {
                for (const auto& Connections : InField.Get_Column(X, Y))
                {
                    if (Connections.Get_IsConnected(0))
                    { ++Count; }
                }
            }
        }

        return Count;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Walkability_LowClearanceFollowsProfileHeight,
    "CkTests.UnitTests.CkGroundNav.Bake.Walkability_LowClearanceFollowsProfileHeight",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Walkability_LowClearanceFollowsProfileHeight::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_walkability;

    // A floor topping out at 10 under a ceiling starting at 160: exactly 150 uu of headroom.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 200.0, 10.0}});
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 160.0}, FVector{500.0, 200.0, 180.0}});

    const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 200.0, 400.0}};

    // 20 columns across by 8 deep at 25 uu cells.
    constexpr auto ExpectedColumns = 20 * 8;

    const auto RunWithHeight = [&](float InStandingHeight, int32& OutFloorWalkable, int32& OutRoofWalkable) -> bool
    {
        const auto Profile = Make_ProfileOfHeight(InStandingHeight);
        auto Field = FCk_GroundNav_SpanField{};

        if (NOT Rasterize(Geometry, Region, 25.0f, Profile, Field))
        { return false; }

        auto Probes = 0;
        DoFilter_LowClearance(Profile, Field, Probes);

        OutFloorWalkable = Get_WalkableSpanCountAtIndex(Field, 0);
        OutRoofWalkable = Get_WalkableSpanCountAtIndex(Field, 1);

        return true;
    };

    auto FloorWalkable = 0;
    auto RoofWalkable = 0;

    if (NOT TestTrue(TEXT("the 140 uu fixture rasterizes"), RunWithHeight(140.0f, FloorWalkable, RoofWalkable)))
    { return false; }

    TestEqual(TEXT("150 uu of headroom fits a 140 uu agent, so every floor column stays walkable"),
        FloorWalkable, ExpectedColumns);

    if (NOT TestTrue(TEXT("the 160 uu fixture rasterizes"), RunWithHeight(160.0f, FloorWalkable, RoofWalkable)))
    { return false; }

    TestEqual(TEXT("150 uu of headroom does not fit a 160 uu agent, so every floor column is demoted"),
        FloorWalkable, 0);

    // The roof has nothing above it at all. If the filter had demoted it too, the assertion above
    // would be passing for the wrong reason — a filter that demotes everything.
    TestEqual(TEXT("the roof, with unbounded headroom, is untouched"),
        RoofWalkable, ExpectedColumns);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Walkability_LedgeFilterDemotesTheCliffEdge,
    "CkTests.UnitTests.CkGroundNav.Bake.Walkability_LedgeFilterDemotesTheCliffEdge",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Walkability_LedgeFilterDemotesTheCliffEdge::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_walkability;

    // Ground across the whole region, with a 500 uu plateau occupying its western half. The cliff
    // edge therefore falls exactly on the boundary between column 19 and column 20.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{1000.0, 1000.0, 10.0}});
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 1000.0, 500.0}});

    const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 1000.0, 800.0}};
    const auto Profile = Make_ProfileOfHeight(180.0f);

    auto Field = FCk_GroundNav_SpanField{};

    if (NOT TestTrue(TEXT("the cliff fixture rasterizes"), Rasterize(Geometry, Region, 25.0f, Profile, Field)))
    { return false; }

    constexpr auto RowDepth = 40;
    constexpr auto PlateauTop = 500.0f;

    TestEqual(TEXT("the plateau top row is walkable before filtering"),
        Get_WalkableCountAtXAndHeight(Field, 19, PlateauTop), RowDepth);

    auto Probes = 0;
    DoFilter_Ledges(Profile, Field, Probes);

    TestEqual(TEXT("the row on the lip of the drop is demoted"),
        Get_WalkableCountAtXAndHeight(Field, 19, PlateauTop), 0);

    TestEqual(TEXT("the row one cell behind it is not"),
        Get_WalkableCountAtXAndHeight(Field, 18, PlateauTop), RowDepth);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Walkability_LedgeSensitivityRelaxesForNarrowGeometry,
    "CkTests.UnitTests.CkGroundNav.Bake.Walkability_LedgeSensitivityRelaxesForNarrowGeometry",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Walkability_LedgeSensitivityRelaxesForNarrowGeometry::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_walkability;

    // A catwalk one cell wide over open air: it drops away on both of its long sides, which is why
    // the default filter erases it and why the sensitivity knob has to exist at all.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 250.0, 100.0}, FVector{500.0, 275.0, 110.0}});

    const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 500.0, 400.0}};

    constexpr auto CatwalkLength = 20;

    const auto Get_SurvivingSpans = [&](float InSensitivity) -> int32
    {
        auto Profile = Make_ProfileOfHeight(180.0f);
        Profile.Set_LedgeSensitivity(InSensitivity);

        auto Field = FCk_GroundNav_SpanField{};

        if (NOT Rasterize(Geometry, Region, 25.0f, Profile, Field))
        { return -1; }

        auto Probes = 0;
        DoFilter_Ledges(Profile, Field, Probes);

        auto Count = 0;

        for (const auto& Column : Field._Columns)
        {
            for (const auto& Span : Column)
            {
                if (Span._IsWalkable)
                { ++Count; }
            }
        }

        return Count;
    };

    TestEqual(TEXT("at the default one dropping side is enough, so the catwalk is erased"),
        Get_SurvivingSpans(1.0f), 0);

    // Just over a third: three sides must drop. The catwalk has two, so it survives — while a
    // pillar top, dropping on three, still would not.
    TestEqual(TEXT("relaxed to demand three dropping sides, the catwalk survives intact"),
        Get_SurvivingSpans(0.34f), CatwalkLength);

    TestEqual(TEXT("zero disables the filter outright"),
        Get_SurvivingSpans(0.0f), CatwalkLength);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Walkability_RoughPerchHoldsASawtoothTogether,
    "CkTests.UnitTests.CkGroundNav.Bake.Walkability_RoughPerchHoldsASawtoothTogether",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Walkability_RoughPerchHoldsASawtoothTogether::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_walkability;

    // A 5 uu sawtooth whose facets align one-to-one with the columns. Each facet tilts 26.6 degrees
    // and its neighbour tilts the same amount the other way, so consecutive normals disagree by 53
    // degrees — far outside any sane slope-change cone, even though the surface is obviously one
    // continuous floor.
    constexpr auto CellSize = 10.0f;
    constexpr auto ColumnsAcross = 20;
    constexpr auto RowsDeep = 4;
    constexpr auto Depth = 40.0;

    auto Geometry = FCk_GroundNav_GeometryBatch{};

    for (auto Index = 0; Index < ColumnsAcross; ++Index)
    {
        const auto NearX = static_cast<double>(Index) * CellSize;
        const auto FarX = NearX + CellSize;
        const auto NearZ = (Index % 2) == 0 ? 0.0 : 5.0;
        const auto FarZ = (Index % 2) == 0 ? 5.0 : 0.0;

        const auto A = FVector{NearX, 0.0, NearZ};
        const auto B = FVector{FarX, 0.0, FarZ};
        const auto C = FVector{FarX, Depth, FarZ};
        const auto D = FVector{NearX, Depth, NearZ};

        Geometry.Add_Triangle(A, B, C);
        Geometry.Add_Triangle(A, C, D);
    }

    const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{200.0, Depth, 100.0}};

    const auto Get_ConnectionsAtTolerance = [&](float InTolerance) -> int32
    {
        auto Profile = Make_ProfileOfHeight(180.0f);
        Profile.Set_RoughPerchToleranceUu(InTolerance);

        auto Field = FCk_GroundNav_SpanField{};

        if (NOT Rasterize(Geometry, Region, CellSize, Profile, Field))
        { return -1; }

        auto Connections = FCk_GroundNav_ConnectionField{};
        auto Probes = 0;
        DoBuild_Connections(Profile, Field, Connections, Probes);

        return Get_ConnectionCountAlongX(Connections);
    };

    // 19 adjacent pairs per row, across 4 rows.
    constexpr auto ExpectedPairs = (ColumnsAcross - 1) * RowsDeep;

    TestEqual(TEXT("with a rough-perch tolerance the sawtooth stays one connected surface"),
        Get_ConnectionsAtTolerance(5.0f), ExpectedPairs);

    TestEqual(TEXT("with the tolerance at zero it shatters into disconnected facets"),
        Get_ConnectionsAtTolerance(0.0f), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Walkability_ConnectionsAreSymmetricAndSkipDemotedSpans,
    "CkTests.UnitTests.CkGroundNav.Bake.Walkability_ConnectionsAreSymmetricAndSkipDemotedSpans",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Walkability_ConnectionsAreSymmetricAndSkipDemotedSpans::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_walkability;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 500.0, 10.0}});

    const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 500.0, 400.0}};
    const auto Profile = Make_ProfileOfHeight(180.0f);

    auto Field = FCk_GroundNav_SpanField{};

    if (NOT TestTrue(TEXT("the flat fixture rasterizes"), Rasterize(Geometry, Region, 25.0f, Profile, Field)))
    { return false; }

    auto Connections = FCk_GroundNav_ConnectionField{};
    auto Probes = 0;
    DoBuild_Connections(Profile, Field, Connections, Probes);

    // A 20x20 lattice of identical cells: every interior column connects on all four sides, every
    // edge column loses one, every corner two. 4*20*20 - 4*20 = 1520.
    TestEqual(TEXT("a flat plane connects every column to each in-lattice neighbour"),
        Connections.Get_TotalConnectionCount(), 1520);

    for (auto Y = 0; Y < Connections._SizeY; ++Y)
    {
        for (auto X = 0; X < Connections._SizeX; ++X)
        {
            const auto& Column = Connections.Get_Column(X, Y);

            for (auto Index = 0; Index < Column.Num(); ++Index)
            {
                for (auto Direction = 0; Direction < ck::groundnav::kDirectionCount; ++Direction)
                {
                    if (NOT Column[Index].Get_IsConnected(Direction))
                    { continue; }

                    const auto Offset = ck::groundnav::Get_DirectionOffset(Direction);
                    const auto Far = Connections.Get_Column(X + Offset.X, Y + Offset.Y)
                        [Column[Index]._Neighbours[Direction]];

                    if (Far._Neighbours[ck::groundnav::Get_OppositeDirection(Direction)] == Index)
                    { continue; }

                    AddError(FString::Printf(
                        TEXT("column (%d,%d) span %d connects along %d but is not connected back"),
                        X, Y, Index, Direction));
                    return false;
                }
            }
        }
    }

    // Demoting a whole row must remove it from the mask entirely, not merely mark it: the mask is
    // the only adjacency downstream is allowed to consult, so an edge into a demoted span would
    // readmit ground the filters already rejected.
    for (auto Y = 0; Y < Field._SizeY; ++Y)
    {
        for (auto& Span : Field.Get_MutableColumn(10, Y))
        { Span._IsWalkable = false; }
    }

    DoBuild_Connections(Profile, Field, Connections, Probes);

    for (auto Y = 0; Y < Connections._SizeY; ++Y)
    {
        for (const auto& Connections10 : Connections.Get_Column(10, Y))
        {
            TestEqual(TEXT("a demoted span carries no connections of its own"),
                Connections10.Get_ConnectionCount(), 0);
        }

        for (const auto& Connections9 : Connections.Get_Column(9, Y))
        {
            TestFalse(TEXT("and its neighbours no longer connect into it"),
                Connections9.Get_IsConnected(0));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Walkability_LedgeFilterReadsAWallAsSupportNotADrop,
    "CkTests.UnitTests.CkGroundNav.Bake.Walkability_LedgeFilterReadsAWallAsSupportNotADrop",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Walkability_LedgeFilterReadsAWallAsSupportNotADrop::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_walkability;

    // Built by hand rather than rasterized: the distinction under test is between a neighbouring
    // solid that STRADDLES our height and one that hangs above it, and expressing that difference
    // through box geometry would take a taller fixture than the rule it pins.
    const auto Make_ThreeColumnStrip = [](const FCk_GroundNav_Span& InLeftNeighbour) -> FCk_GroundNav_SpanField
    {
        auto Ground = FCk_GroundNav_Span{};
        Ground._MinZ = 0.0f;
        Ground._MaxZ = 10.0f;
        Ground._IsWalkable = true;

        auto Field = FCk_GroundNav_SpanField{};
        Field._SizeX = 3;
        Field._SizeY = 1;
        Field._CellSizeUu = 25.0f;
        Field._Columns.SetNum(3);
        Field._Columns[0].Emplace(InLeftNeighbour);
        Field._Columns[1].Emplace(Ground);
        Field._Columns[2].Emplace(Ground);

        return Field;
    };

    const auto Profile = Make_ProfileOfHeight(180.0f);
    auto Probes = 0;

    {
        // A wall rising past our head from below. The height difference to its top is 490 uu, exactly
        // as at a cliff edge — only the direction differs, and that is the whole point.
        auto Wall = FCk_GroundNav_Span{};
        Wall._MinZ = 0.0f;
        Wall._MaxZ = 500.0f;

        auto Field = Make_ThreeColumnStrip(Wall);
        DoFilter_Ledges(Profile, Field, Probes);

        TestTrue(TEXT("ground at the foot of a wall is standable, not a ledge"),
            Field.Get_Column(1, 0)[0]._IsWalkable);
    }

    {
        // The same height difference, but the solid hangs overhead instead of straddling us. There is
        // nothing between our feet and the fall, so this one IS a ledge.
        auto Overhead = FCk_GroundNav_Span{};
        Overhead._MinZ = 200.0f;
        Overhead._MaxZ = 210.0f;

        auto Field = Make_ThreeColumnStrip(Overhead);
        DoFilter_Ledges(Profile, Field, Probes);

        TestFalse(TEXT("ground beside a void is demoted even with a floor far above it"),
            Field.Get_Column(1, 0)[0]._IsWalkable);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
