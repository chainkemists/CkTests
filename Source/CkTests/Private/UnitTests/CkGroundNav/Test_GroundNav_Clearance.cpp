// Per-cell clearance — the number that lets one bake serve every agent size.
//
// A query admits a cell by testing its own radius against this value, so an over-estimate here is an
// agent wedged in a doorway and an under-estimate is a corridor nothing can use. The fixtures pin
// exact values, and the last one checks the whole field against an independent brute-force reference
// rather than sampling it.
//
// Every fixture bakes with the ledge filter disabled. The subject is the distance transform, and a
// ledge filter left at its conservative default would erase a one-cell-wide fixture before the
// transform ever saw it.

#include "CkGroundNav/Bake/CkGroundNav_Clearance.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_clearance
{
    using ck::groundnav::DoCompute_Clearance;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_SpanField;
    using ck::groundnav::Get_ChamferDistance;

    constexpr auto kCellSize = 25.0f;

    struct FBakeResult
    {
        FCk_GroundNav_LayerField _Layers;
        FCk_GroundNav_ClearanceField _Clearance;
        bool _Completed = false;
    };

    auto Bake(const FCk_GroundNav_GeometryBatch& InGeometry, const FBox& InRegion) -> FBakeResult
    {
        auto Result = FBakeResult{};

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Config = FCk_GroundNav_BakeConfig{kCellSize, 10.0f};

        auto Spans = FCk_GroundNav_SpanField{};

        if (NOT DoRasterizeSpans(InGeometry, InRegion, Config, Profile, Spans).Get_IsCompleted())
        { return Result; }

        auto Connections = FCk_GroundNav_ConnectionField{};

        if (NOT DoFilter_Walkability(Profile, Spans, Connections).Get_IsCompleted())
        { return Result; }

        if (NOT DoExtract_Layers(Spans, Connections, Result._Layers).Get_IsCompleted())
        { return Result; }

        Result._Completed = DoCompute_Clearance(
            Result._Layers, Connections, kCellSize, Result._Clearance).Get_IsCompleted();

        return Result;
    }

    // Minimum chamfer distance from one cell to any blocked cell, computed by exhaustive scan rather
    // than by sweeping. Everything outside the field is blocked, and the nearest such cell is always
    // within one ring of the border, so the ring is all the scan needs to include.
    auto Get_ReferenceChamfer(
        const FCk_GroundNav_LayerField& InLayers,
        int32                           InLayer,
        int32                           InX,
        int32                           InY) -> int32
    {
        auto Best = TNumericLimits<int32>::Max();

        for (auto Y = -1; Y <= InLayers._SizeY; ++Y)
        {
            for (auto X = -1; X <= InLayers._SizeX; ++X)
            {
                const auto IsInside = X >= 0 && Y >= 0 && X < InLayers._SizeX && Y < InLayers._SizeY;

                if (IsInside && InLayers.Get_OccupancyAt(X, Y, InLayer) > 0)
                { continue; }

                Best = FMath::Min(Best, Get_ChamferDistance(X - InX, Y - InY));
            }
        }

        return Best;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Clearance_OpenSquareAndIsolatedCell,
    "CkTests.UnitTests.CkGroundNav.Bake.Clearance_OpenSquareAndIsolatedCell",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Clearance_OpenSquareAndIsolatedCell::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_clearance;

    {
        // A 1000 uu square of open floor: the middle is 500 uu from the nearest edge in every
        // direction, and the transform has to say so.
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{1000.0, 1000.0, 10.0}});

        const auto Baked = Bake(Geometry, FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 1000.0, 400.0}});

        if (NOT TestTrue(TEXT("the open square bakes"), Baked._Completed))
        { return false; }

        constexpr auto CellDiagonal = 35.36f;

        TestTrue(TEXT("the centre of a 1000 uu square reads 500 uu of clearance"),
            FMath::IsNearlyEqual(Baked._Clearance.Get_ClearanceAt(20, 20, 0), 500.0f, CellDiagonal));

        // A cell against the edge has one cell of room, not zero: the border is the obstacle, and
        // the cell itself is still standable.
        TestTrue(TEXT("a cell against the field border reads exactly one cell size"),
            FMath::IsNearlyEqual(Baked._Clearance.Get_ClearanceAt(0, 20, 0), kCellSize, 0.01f));
    }

    {
        // One cell of floor and nothing else. This is the degenerate case the field must not report
        // as zero — an agent smaller than a cell can stand there.
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{100.0, 100.0, 0.0}, FVector{125.0, 125.0, 10.0}});

        const auto Baked = Bake(Geometry, FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 500.0, 400.0}});

        if (NOT TestTrue(TEXT("the isolated cell bakes"), Baked._Completed))
        { return false; }

        TestTrue(TEXT("an isolated cell reads exactly one cell size of clearance"),
            FMath::IsNearlyEqual(Baked._Clearance.Get_ClearanceAt(4, 4, 0), kCellSize, 0.01f));

        TestTrue(TEXT("and it is the largest value anywhere in the field"),
            FMath::IsNearlyEqual(Baked._Clearance.Get_MaxClearance(), kCellSize, 0.01f));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Clearance_CorridorSpineIsHalfItsWidth,
    "CkTests.UnitTests.CkGroundNav.Bake.Clearance_CorridorSpineIsHalfItsWidth",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Clearance_CorridorSpineIsHalfItsWidth::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_clearance;

    // A 90 uu corridor: the widest agent it admits has a 45 uu radius, and the spine is where that
    // shows up. This is the value a doorway check reads, so being wrong here admits agents that then
    // wedge.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 105.0, 0.0}, FVector{1000.0, 195.0, 10.0}});

    const auto Baked = Bake(Geometry, FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 300.0, 400.0}});

    if (NOT TestTrue(TEXT("the corridor bakes"), Baked._Completed))
    { return false; }

    TestTrue(TEXT("the corridor spine reads half the corridor width, within one cell"),
        FMath::IsNearlyEqual(Baked._Clearance.Get_MaxClearance(), 45.0f, kCellSize));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Clearance_MatchesABruteForceReference,
    "CkTests.UnitTests.CkGroundNav.Bake.Clearance_MatchesABruteForceReference",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Clearance_MatchesABruteForceReference::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_clearance;

    // An L, so the fixture carries a concave corner — the shape a single sweep direction gets wrong
    // and the reason the transform makes two passes.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{1600.0, 800.0, 10.0}});
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{800.0, 1600.0, 10.0}});

    const auto Baked = Bake(Geometry, FBox{FVector{0.0, 0.0, -50.0}, FVector{1600.0, 1600.0, 400.0}});

    if (NOT TestTrue(TEXT("the L-shaped fixture bakes"), Baked._Completed))
    { return false; }

    TestEqual(TEXT("the fixture is 64 cells across"), Baked._Layers._SizeX, 64);
    TestEqual(TEXT("and 64 deep"), Baked._Layers._SizeY, 64);

    const auto WorldPerUnit = kCellSize / static_cast<float>(ck::groundnav::kChamferOrthogonalCost);

    // The two-pass sweep is not an approximation of this metric — it computes it exactly — so the
    // comparison is equality, not a tolerance. Anything else would let a propagation bug hide.
    constexpr auto AdmittedRadius = 100.0f;

    auto WalkableCells = 0;
    auto AdmittedByField = 0;
    auto AdmittedByReference = 0;

    for (auto Y = 0; Y < Baked._Layers._SizeY; ++Y)
    {
        for (auto X = 0; X < Baked._Layers._SizeX; ++X)
        {
            if (Baked._Layers.Get_OccupancyAt(X, Y, 0) == 0)
            { continue; }

            ++WalkableCells;

            const auto Expected = static_cast<float>(Get_ReferenceChamfer(Baked._Layers, 0, X, Y)) * WorldPerUnit;
            const auto Actual = Baked._Clearance.Get_ClearanceAt(X, Y, 0);

            if (NOT FMath::IsNearlyEqual(Expected, Actual, 0.01f))
            {
                AddError(FString::Printf(
                    TEXT("cell (%d,%d): swept clearance %f but the reference says %f"),
                    X, Y, Actual, Expected));
                return false;
            }

            if (Actual >= AdmittedRadius)
            { ++AdmittedByField; }

            if (Expected >= AdmittedRadius)
            { ++AdmittedByReference; }
        }
    }

    // Three quarters of a 64x64 lattice.
    TestEqual(TEXT("the L covers three quarters of the lattice"), WalkableCells, 3072);

    TestEqual(TEXT("a radius filter admits the same set the reference does"),
        AdmittedByField, AdmittedByReference);

    // A filter that admitted everything or nothing would satisfy the equality above while testing
    // nothing at all.
    TestTrue(TEXT("and that set is neither empty nor everything"),
        AdmittedByField > 0 && AdmittedByField < WalkableCells);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_clearance
{
    // A 1000 uu floor with a 200 uu square something standing on its middle, at a height the test
    // chooses. Column 15 is the floor cell just west of it; column 16 is its own western edge; column
    // 20 is its middle. Row 20 crosses it through the centre.
    constexpr auto kRaisedMinUu = 400.0;
    constexpr auto kRaisedMaxUu = 600.0;
    constexpr auto kFloorTopZ = 10.0;

    constexpr auto kBesideX = 15;
    constexpr auto kEdgeX = 16;
    constexpr auto kMiddleX = 20;
    constexpr auto kRowY = 20;

    auto Make_FloorWithSomethingOnIt(double InHeightUu) -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{1000.0, 1000.0, kFloorTopZ}});
        Geometry.Add_Box(FBox{
            FVector{kRaisedMinUu, kRaisedMinUu, kFloorTopZ},
            FVector{kRaisedMaxUu, kRaisedMaxUu, kFloorTopZ + InHeightUu}});

        return Geometry;
    }

    auto Make_BareFloor() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{1000.0, 1000.0, kFloorTopZ}});

        return Geometry;
    }

    auto Get_FloorRegion() -> FBox
    {
        return FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 1000.0, 400.0}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Clearance_ARaisedSolidBesideAFloorIsAnObstacle,
    "CkTests.UnitTests.CkGroundNav.Bake.Clearance_ARaisedSolidBesideAFloorIsAnObstacle",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Clearance_ARaisedSolidBesideAFloorIsAnObstacle::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_clearance;

    // Taller than anything can step onto. Its top is walkable ground of its own and lands in the
    // floor's layer, because the floor has no walkable cell underneath it.
    constexpr auto kSolidHeightUu = 300.0;

    const auto Bare = Bake(Make_BareFloor(), Get_FloorRegion());
    const auto WithSolid = Bake(Make_FloorWithSomethingOnIt(kSolidHeightUu), Get_FloorRegion());

    if (NOT TestTrue(TEXT("both scenes bake"), Bare._Completed && WithSolid._Completed))
    { return false; }

    if (NOT TestEqual(TEXT("the solid's top and the floor share one layer"), WithSolid._Layers._LayerCount, 1))
    { return false; }

    TestTrue(TEXT("the solid's top is walkable ground of its own"),
        WithSolid._Layers.Get_OccupancyAt(kMiddleX, kRowY, 0) > 0);

    // The floor beside the solid: open ground on the bare floor, one cell from a wall with it there.
    TestTrue(FString::Printf(TEXT("without the solid the same cell is open ground (%.1f)"),
        Bare._Clearance.Get_ClearanceAt(kBesideX, kRowY, 0)),
        Bare._Clearance.Get_ClearanceAt(kBesideX, kRowY, 0) > kCellSize);

    TestEqual(TEXT("the floor cell beside the solid reads exactly one cell of room"),
        WithSolid._Clearance.Get_ClearanceAt(kBesideX, kRowY, 0), kCellSize);

    // And the top of the solid is an island: its rim is one cell from a drop, its middle is not.
    TestEqual(TEXT("the solid's own edge cell reads one cell of room"),
        WithSolid._Clearance.Get_ClearanceAt(kEdgeX, kRowY, 0), kCellSize);

    TestTrue(FString::Printf(TEXT("and its middle reads more (%.1f)"),
        WithSolid._Clearance.Get_ClearanceAt(kMiddleX, kRowY, 0)),
        WithSolid._Clearance.Get_ClearanceAt(kMiddleX, kRowY, 0) > kCellSize);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Clearance_ACurbUnderTheStepHeightIsGround,
    "CkTests.UnitTests.CkGroundNav.Bake.Clearance_ACurbUnderTheStepHeightIsGround",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Clearance_ACurbUnderTheStepHeightIsGround::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_clearance;

    // Under the profile's step height, so the floor and the curb's top are linked and it is all one
    // piece of ground as far as clearance is concerned.
    constexpr auto kCurbHeightUu = 30.0;

    const auto Bare = Bake(Make_BareFloor(), Get_FloorRegion());
    const auto WithCurb = Bake(Make_FloorWithSomethingOnIt(kCurbHeightUu), Get_FloorRegion());

    if (NOT TestTrue(TEXT("both scenes bake"), Bare._Completed && WithCurb._Completed))
    { return false; }

    TestEqual(TEXT("a curb the body can step onto does not erode the floor beside it"),
        WithCurb._Clearance.Get_ClearanceAt(kBesideX, kRowY, 0),
        Bare._Clearance.Get_ClearanceAt(kBesideX, kRowY, 0));

    TestEqual(TEXT("nor is the curb's own edge a rim"),
        WithCurb._Clearance.Get_ClearanceAt(kEdgeX, kRowY, 0),
        Bare._Clearance.Get_ClearanceAt(kEdgeX, kRowY, 0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Clearance_AStepOverTheStepHeightErodesBothSides,
    "CkTests.UnitTests.CkGroundNav.Bake.Clearance_AStepOverTheStepHeightErodesBothSides",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Clearance_AStepOverTheStepHeightErodesBothSides::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_clearance;

    // Over the step height but well under the standing height: the body can neither step up nor
    // walk under, so each side is a wall to the other — the low side cannot climb it and the high
    // side has a drop.
    constexpr auto kStepHeightUu = 60.0;

    const auto WithStep = Bake(Make_FloorWithSomethingOnIt(kStepHeightUu), Get_FloorRegion());

    if (NOT TestTrue(TEXT("the scene bakes"), WithStep._Completed))
    { return false; }

    TestEqual(TEXT("the floor beside the step reads one cell of room"),
        WithStep._Clearance.Get_ClearanceAt(kBesideX, kRowY, 0), kCellSize);

    TestEqual(TEXT("the step's own edge reads one cell of room"),
        WithStep._Clearance.Get_ClearanceAt(kEdgeX, kRowY, 0), kCellSize);

    TestTrue(FString::Printf(TEXT("and the middle of the step reads more (%.1f)"),
        WithStep._Clearance.Get_ClearanceAt(kMiddleX, kRowY, 0)),
        WithStep._Clearance.Get_ClearanceAt(kMiddleX, kRowY, 0) > kCellSize);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
