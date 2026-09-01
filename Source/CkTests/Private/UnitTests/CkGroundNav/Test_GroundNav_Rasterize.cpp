// Span rasterization — flat floor, stacked floors, climb-threshold merging, ramp monotonicity, and
// the drop-and-count contract for degenerate input.
//
// Every assertion here is a COUNT or an exact height. Nothing in this file settles for "looks about
// right": a rasterizer that is approximately correct produces a field that is confidently wrong.

#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_raster
{
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_SpanField;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;

    auto Make_Config() -> FCk_GroundNav_BakeConfig
    {
        return FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
    }

    auto Make_Region() -> FBox
    {
        return FBox{FVector{0.0, 0.0, -100.0}, FVector{1000.0, 1000.0, 2000.0}};
    }

    // A thin slab spanning the whole region footprint, with its top surface at InTopZ.
    auto Make_Floor(double InTopZ) -> FBox
    {
        return FBox{FVector{0.0, 0.0, InTopZ - 10.0}, FVector{1000.0, 1000.0, InTopZ}};
    }

    auto Make_Profile(float InStepHeight = 40.0f) -> FCk_GroundNav_AgentProfile
    {
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{56.0f, 34.0f}}};
        Profile.Set_StepHeightUu(InStepHeight);

        return Profile;
    }

    auto Rasterize(
        const FCk_GroundNav_GeometryBatch& InGeometry,
        FCk_GroundNav_SpanField&           OutField,
        float                              InStepHeight = 40.0f) -> FCk_GroundNav_BakeStageResult
    {
        return DoRasterizeSpans(InGeometry, Make_Region(), Make_Config(), Make_Profile(InStepHeight), OutField);
    }

    // The column at the middle of the region, well away from every boundary.
    auto Get_MiddleColumn(const FCk_GroundNav_SpanField& InField) -> const TArray<ck::groundnav::FCk_GroundNav_Span>&
    {
        return InField.Get_Column(InField._SizeX / 2, InField._SizeY / 2);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Rasterize_FlatFloorIsOneSpanPerColumn,
    "CkTests.UnitTests.CkGroundNav.Bake.Rasterize_FlatFloorIsOneSpanPerColumn",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Rasterize_FlatFloorIsOneSpanPerColumn::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_raster;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(Make_Floor(0.0));

    auto Field = FCk_GroundNav_SpanField{};
    const auto Result = Rasterize(Geometry, Field);

    TestTrue(TEXT("rasterization completes"), Result.Get_IsCompleted());
    TestEqual(TEXT("no input was dropped"), Result.Get_DroppedInputCount(), 0);
    TestEqual(TEXT("the lattice covers the region"), Field._SizeX, 40);
    TestEqual(TEXT("in both axes"), Field._SizeY, 40);

    // The box's six faces all rasterize, but its 10uu thickness is inside the step height, so the
    // whole solid collapses to ONE span per column rather than a stack of three.
    auto ColumnsWithOneSpan = 0;
    auto ColumnsWrong = 0;

    for (auto Y = 0; Y < Field._SizeY; ++Y)
    {
        for (auto X = 0; X < Field._SizeX; ++X)
        {
            const auto& Column = Field.Get_Column(X, Y);

            if (Column.Num() == 1)
            { ++ColumnsWithOneSpan; }
            else
            { ++ColumnsWrong; }
        }
    }

    TestEqual(TEXT("every covered column holds exactly one span"), ColumnsWrong, 0);
    TestEqual(TEXT("and that is every column in the lattice"), ColumnsWithOneSpan, Field.Get_ColumnCount());

    const auto& Middle = Get_MiddleColumn(Field);

    if (Middle.Num() == 1)
    {
        // Within half a cell height of the authored surface.
        TestTrue(TEXT("the span's top sits at the authored floor height"),
            FMath::Abs(Middle[0]._MaxZ - 0.0f) <= (kCellHeight * 0.5f));

        TestTrue(TEXT("and it is walkable"), Middle[0]._IsWalkable);

        TestTrue(TEXT("with a normal pointing up"),
            Middle[0]._Normal.Get_UpDot() > 0.99);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Rasterize_TwoFloorsAreTwoSpansPerColumn,
    "CkTests.UnitTests.CkGroundNav.Bake.Rasterize_TwoFloorsAreTwoSpansPerColumn",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Rasterize_TwoFloorsAreTwoSpansPerColumn::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_raster;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(Make_Floor(0.0));
    Geometry.Add_Box(Make_Floor(1000.0));

    auto Field = FCk_GroundNav_SpanField{};
    const auto Result = Rasterize(Geometry, Field);

    TestTrue(TEXT("rasterization completes"), Result.Get_IsCompleted());

    auto ColumnsWrong = 0;

    for (auto Y = 0; Y < Field._SizeY; ++Y)
    {
        for (auto X = 0; X < Field._SizeX; ++X)
        {
            if (Field.Get_Column(X, Y).Num() != 2)
            { ++ColumnsWrong; }
        }
    }

    TestEqual(TEXT("two floors 1000uu apart are exactly two spans in every column"), ColumnsWrong, 0);

    const auto& Middle = Get_MiddleColumn(Field);

    if (Middle.Num() == 2)
    {
        TestTrue(TEXT("spans are ordered bottom-up"), Middle[0]._MaxZ < Middle[1]._MaxZ);

        TestTrue(TEXT("the lower span is the ground floor"),
            FMath::Abs(Middle[0]._MaxZ - 0.0f) <= (kCellHeight * 0.5f));

        TestTrue(TEXT("the upper span is the second storey"),
            FMath::Abs(Middle[1]._MaxZ - 1000.0f) <= (kCellHeight * 0.5f));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Rasterize_StepMergesUnderClimbThreshold,
    "CkTests.UnitTests.CkGroundNav.Bake.Rasterize_StepMergesUnderClimbThreshold",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Rasterize_StepMergesUnderClimbThreshold::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_raster;

    // Two slabs whose surfaces are 30uu apart, stacked in the same columns.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, -10.0}, FVector{1000.0, 1000.0, 0.0}});
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 20.0}, FVector{1000.0, 1000.0, 30.0}});

    // The gap between the lower surface (0) and the upper solid's underside (20) is 20uu.
    {
        auto Field = FCk_GroundNav_SpanField{};
        Rasterize(Geometry, Field, 40.0f);

        const auto& Middle = Get_MiddleColumn(Field);
        TestEqual(TEXT("a 20uu gap merges under a 40uu climb threshold"), Middle.Num(), 1);

        if (Middle.Num() == 1)
        {
            TestTrue(TEXT("and the merged span keeps the HIGHEST surface as its top"),
                FMath::Abs(Middle[0]._MaxZ - 30.0f) <= (kCellHeight * 0.5f));
        }
    }

    {
        auto Field = FCk_GroundNav_SpanField{};
        Rasterize(Geometry, Field, 10.0f);

        const auto& Middle = Get_MiddleColumn(Field);
        TestEqual(TEXT("the same gap does NOT merge under a 10uu climb threshold"), Middle.Num(), 2);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Rasterize_RampIsMonotoneWithAnalyticNormal,
    "CkTests.UnitTests.CkGroundNav.Bake.Rasterize_RampIsMonotoneWithAnalyticNormal",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Rasterize_RampIsMonotoneWithAnalyticNormal::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_raster;

    // A 45-degree ramp climbing along +X: two triangles, rising 1uu per uu travelled.
    const auto Near = 100.0;
    const auto Far = 900.0;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Triangle(
        FVector{Near, 100.0, Near}, FVector{Far, 100.0, Far}, FVector{Far, 900.0, Far});
    Geometry.Add_Triangle(
        FVector{Near, 100.0, Near}, FVector{Far, 900.0, Far}, FVector{Near, 900.0, Near});

    auto Field = FCk_GroundNav_SpanField{};
    // 45 degrees is exactly the default max slope, so a slightly steeper allowance keeps this test
    // about monotonicity and normals rather than about the walkable/not tie-break at the boundary.
    auto Profile = Make_Profile();
    Profile.Set_MaxSlopeDegrees(50.0f);

    const auto Result = DoRasterizeSpans(Geometry, Make_Region(), Make_Config(), Profile, Field);

    TestTrue(TEXT("rasterization completes"), Result.Get_IsCompleted());
    TestEqual(TEXT("no input was dropped"), Result.Get_DroppedInputCount(), 0);

    // Walk one row of the ramp and require the surface height to rise monotonically with X.
    const auto Y = Field._SizeY / 2;
    auto Previous = TNumericLimits<float>::Lowest();
    auto Samples = 0;
    auto MonotonicityBreaks = 0;
    auto NormalBreaks = 0;

    // The analytic normal of a plane rising 1:1 along +X is (-1, 0, 1) normalized.
    const auto Analytic = FVector{-1.0, 0.0, 1.0}.GetSafeNormal();

    for (auto X = 0; X < Field._SizeX; ++X)
    {
        const auto& Column = Field.Get_Column(X, Y);

        if (Column.IsEmpty())
        { continue; }

        const auto& Span = Column.Last();
        ++Samples;

        if (Span._MaxZ < Previous - 0.001f)
        { ++MonotonicityBreaks; }

        Previous = Span._MaxZ;

        // Quantization to signed bytes costs at most a couple of degrees.
        if (FVector::DotProduct(Span._Normal.Get_Normal(), Analytic) < 0.99)
        { ++NormalBreaks; }
    }

    TestTrue(TEXT("the ramp covers a meaningful span of columns"), Samples > 20);
    TestEqual(TEXT("surface height rises monotonically along the ramp"), MonotonicityBreaks, 0);
    TestEqual(TEXT("every sampled normal matches the analytic ramp normal"), NormalBreaks, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Rasterize_DegenerateInputIsDroppedAndCounted,
    "CkTests.UnitTests.CkGroundNav.Bake.Rasterize_DegenerateInputIsDroppedAndCounted",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Rasterize_DegenerateInputIsDroppedAndCounted::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_raster;

    auto Geometry = FCk_GroundNav_GeometryBatch{};

    // Collinear corners: no area, no normal, nothing to stand on.
    Geometry.Add_Triangle(FVector{0, 0, 0}, FVector{100, 0, 0}, FVector{200, 0, 0});

    // A non-finite corner.
    Geometry.Add_Triangle(
        FVector{0, 0, 0},
        FVector{100, 0, 0},
        FVector{0, std::numeric_limits<double>::quiet_NaN(), 0});

    auto Field = FCk_GroundNav_SpanField{};
    const auto Result = Rasterize(Geometry, Field);

    TestTrue(TEXT("the stage still completes"), Result.Get_IsCompleted());

    // Counted, not silently skipped: a silent drop is indistinguishable from an empty region.
    TestEqual(TEXT("both degenerate triangles are dropped AND counted"),
        Result.Get_DroppedInputCount(), 2);

    TestEqual(TEXT("and nothing was rasterized from them"), Field.Get_TotalSpanCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Rasterize_OverBudgetLatticeFailsWithStatus,
    "CkTests.UnitTests.CkGroundNav.Bake.Rasterize_OverBudgetLatticeFailsWithStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Rasterize_OverBudgetLatticeFailsWithStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_raster;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(Make_Floor(0.0));

    // A cell size small enough that the region's column count blows the per-tile ceiling.
    auto Config = FCk_GroundNav_BakeConfig{0.5f, kCellHeight};

    auto Field = FCk_GroundNav_SpanField{};
    const auto Result = DoRasterizeSpans(Geometry, Make_Region(), Config, Make_Profile(), Field);

    // A status, never an allocation attempt and never a half-built field.
    TestTrue(TEXT("an over-budget lattice fails with LimitExceeded"),
        Result.Get_Status() == ECk_GroundNav_BakeStatus::LimitExceeded);

    TestEqual(TEXT("and publishes no columns at all"), Field.Get_ColumnCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
