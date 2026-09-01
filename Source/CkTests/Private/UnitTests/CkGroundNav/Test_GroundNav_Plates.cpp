// Merged-plate decomposition — the collapse from a cell grid to the rectangles everything above it
// addresses.
//
// The failure that matters is asymmetric. Refusing to merge costs memory and nothing else; merging
// cells that should not be merged reports a floor where there is a step, and nothing downstream can
// tell. So the assertions bound plate COUNT from both sides and check the height spread inside each
// plate, not just that a plane fits it.

#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_plates
{
    using ck::groundnav::DoDecompose_Plates;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_SpanField;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;

    struct FBakeResult
    {
        FCk_GroundNav_SpanField _Spans;
        FCk_GroundNav_LayerField _Layers;
        bool _Completed = false;
    };

    // The ledge filter is disabled throughout: the subject here is the decomposition, and the
    // conservative default would trim the fixtures' borders before it ever ran.
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

        Result._Completed = DoExtract_Layers(
            Result._Spans, Connections, Result._Layers).Get_IsCompleted();

        return Result;
    }

    auto Make_Flat(double InExtent) -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{InExtent, InExtent, 10.0}});

        return Geometry;
    }

    // A 1000 uu plane with a 200 uu square hole punched out of its middle, assembled as the four
    // slabs that surround the hole.
    auto Make_HolePlane() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0},     FVector{1000.0, 400.0, 10.0}});
        Geometry.Add_Box(FBox{FVector{0.0, 600.0, 0.0},   FVector{1000.0, 1000.0, 10.0}});
        Geometry.Add_Box(FBox{FVector{0.0, 400.0, 0.0},   FVector{400.0, 600.0, 10.0}});
        Geometry.Add_Box(FBox{FVector{600.0, 400.0, 0.0}, FVector{1000.0, 600.0, 10.0}});

        return Geometry;
    }

    constexpr auto kTreadCount = 12;
    constexpr auto kTreadDepth = 100.0;
    constexpr auto kTreadRise = 15.0;

    // Twelve treads as thin slabs rather than solid blocks: a slab's underside merges with its own
    // top into one span, where a block rising from the ground would leave a second span at its base.
    auto Make_Staircase() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};

        for (auto Tread = 0; Tread < kTreadCount; ++Tread)
        {
            const auto TopZ = kTreadRise * static_cast<double>(Tread + 1);

            Geometry.Add_Box(FBox{
                FVector{kTreadDepth * static_cast<double>(Tread), 0.0, TopZ - 10.0},
                FVector{kTreadDepth * static_cast<double>(Tread + 1), 400.0, TopZ}});
        }

        return Geometry;
    }

    auto Make_Ramp() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};

        const auto A = FVector{0.0, 0.0, 10.0};
        const auto B = FVector{1200.0, 0.0, 200.0};
        const auto C = FVector{1200.0, 400.0, 200.0};
        const auto D = FVector{0.0, 400.0, 10.0};

        Geometry.Add_Triangle(A, B, C);
        Geometry.Add_Triangle(A, C, D);

        return Geometry;
    }

    auto Make_StairRegion() -> FBox
    {
        return FBox{FVector{0.0, 0.0, -50.0}, FVector{1200.0, 400.0, 400.0}};
    }

    auto Get_PlatesMatch(const FCk_GroundNav_PlateField& InLeft, const FCk_GroundNav_PlateField& InRight) -> bool
    {
        if (InLeft._Plates.Num() != InRight._Plates.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft._Plates.Num(); ++Index)
        {
            const auto& Left = InLeft._Plates[Index];
            const auto& Right = InRight._Plates[Index];

            if (Left._MinX == Right._MinX && Left._MinY == Right._MinY &&
                Left._MaxX == Right._MaxX && Left._MaxY == Right._MaxY &&
                Left._LayerIndex == Right._LayerIndex)
            { continue; }

            return false;
        }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Plates_FlatAndHolePlanesCollapse,
    "CkTests.UnitTests.CkGroundNav.Bake.Plates_FlatAndHolePlanesCollapse",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Plates_FlatAndHolePlanesCollapse::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_plates;

    const auto Tunables = FCk_GroundNav_MergeTunables{};

    {
        // 100 x 100 cells of nothing but floor. One rectangle covers it, and any more means the
        // decomposition is splitting where it has no reason to.
        const auto Baked = Bake(Make_Flat(2500.0), FBox{FVector{0.0, 0.0, -50.0}, FVector{2500.0, 2500.0, 400.0}});

        if (NOT TestTrue(TEXT("the flat plane bakes"), Baked._Completed))
        { return false; }

        auto Plates = FCk_GroundNav_PlateField{};

        if (NOT TestTrue(TEXT("the flat plane decomposes"),
            DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, Plates).Get_IsCompleted()))
        { return false; }

        TestEqual(TEXT("a 100x100 cell plane is exactly one plate"), Plates._Plates.Num(), 1);
        TestEqual(TEXT("covering every cell"), Plates._Plates[0].Get_CellCount(), 100 * 100);
    }

    {
        const auto Baked = Bake(Make_HolePlane(), FBox{FVector{0.0, 0.0, -50.0}, FVector{1000.0, 1000.0, 400.0}});

        if (NOT TestTrue(TEXT("the holed plane bakes"), Baked._Completed))
        { return false; }

        auto Plates = FCk_GroundNav_PlateField{};
        DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, Plates);

        TestTrue(FString::Printf(TEXT("a plane with one hole stays at or under five plates (was %d)"),
            Plates._Plates.Num()), Plates._Plates.Num() <= 5);

        // The hole must still be a hole. If the decomposition had merged across it, the count above
        // would look even better while the field claimed floor where there is none.
        TestEqual(TEXT("and no plate covers the hole"),
            Plates.Get_PlateIndexAt(20, 20, 0), ck::groundnav::FCk_GroundNav_Plate::kNoPlate);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Plates_StaircaseCountIsBoundedBothWays,
    "CkTests.UnitTests.CkGroundNav.Bake.Plates_StaircaseCountIsBoundedBothWays",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Plates_StaircaseCountIsBoundedBothWays::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_plates;

    const auto Baked = Bake(Make_Staircase(), Make_StairRegion());

    if (NOT TestTrue(TEXT("the staircase bakes"), Baked._Completed))
    { return false; }

    auto Plates = FCk_GroundNav_PlateField{};
    const auto Tunables = FCk_GroundNav_MergeTunables{};
    DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, Plates);

    TestTrue(FString::Printf(TEXT("a 12-tread staircase lands between 12 and 24 plates (was %d)"),
        Plates._Plates.Num()),
        Plates._Plates.Num() >= kTreadCount && Plates._Plates.Num() <= kTreadCount * 2);

    // No plate may span a riser. This is the assertion that catches an over-merge, and the residual
    // cannot: a plane fits two treads perfectly well by tilting through them.
    TestTrue(FString::Printf(TEXT("no plate spans a riser (worst spread was %f uu)"),
        Plates.Get_MaxHeightRangeUu()),
        Plates.Get_MaxHeightRangeUu() < static_cast<float>(kTreadRise));

    TestTrue(FString::Printf(TEXT("every plate fits its plane within tolerance (worst was %f uu)"),
        Plates.Get_MaxPlaneResidualUu()),
        Plates.Get_MaxPlaneResidualUu() <= Tunables.Get_PlaneFitToleranceUu() + 0.01f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Plates_DecompositionIsStable,
    "CkTests.UnitTests.CkGroundNav.Bake.Plates_DecompositionIsStable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Plates_DecompositionIsStable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_plates;

    const auto Tunables = FCk_GroundNav_MergeTunables{};
    const auto Baked = Bake(Make_Staircase(), Make_StairRegion());

    if (NOT TestTrue(TEXT("the staircase bakes"), Baked._Completed))
    { return false; }

    auto Reference = FCk_GroundNav_PlateField{};
    DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, Reference);

    // Plate indices become part of every id downstream, so a decomposition that varied between runs
    // would make those ids meaningless.
    for (auto Run = 0; Run < 100; ++Run)
    {
        auto Repeat = FCk_GroundNav_PlateField{};
        DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, Repeat);

        if (Get_PlatesMatch(Reference, Repeat))
        { continue; }

        AddError(FString::Printf(TEXT("run %d produced a different decomposition"), Run));
        return false;
    }

    // Submission order is an accident of how geometry was collected, and must not reach the output.
    auto Reversed = FCk_GroundNav_GeometryBatch{};
    {
        const auto Forward = Make_Staircase();

        for (auto Index = Forward.Get_TriangleCount() - 1; Index >= 0; --Index)
        {
            auto A = FVector::ZeroVector;
            auto B = FVector::ZeroVector;
            auto C = FVector::ZeroVector;
            Forward.Get_Triangle(Index, A, B, C);
            Reversed.Add_Triangle(A, B, C);
        }
    }

    const auto ReversedBake = Bake(Reversed, Make_StairRegion());

    if (NOT TestTrue(TEXT("the reversed staircase bakes"), ReversedBake._Completed))
    { return false; }

    auto ReversedPlates = FCk_GroundNav_PlateField{};
    DoDecompose_Plates(ReversedBake._Spans, ReversedBake._Layers, Tunables, ReversedPlates);

    TestTrue(TEXT("reversing geometry submission order changes nothing"),
        Get_PlatesMatch(Reference, ReversedPlates));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Plates_RemainsWellFormedAcrossTheTunableRange,
    "CkTests.UnitTests.CkGroundNav.Bake.Plates_RemainsWellFormedAcrossTheTunableRange",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Plates_RemainsWellFormedAcrossTheTunableRange::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_plates;

    // The two tunables are authored per project, so the decomposition has to stay well-formed across
    // the whole supported range rather than only at whatever pair ships as the default.
    const auto StairBake = Bake(Make_Staircase(), Make_StairRegion());
    const auto RampBake = Bake(Make_Ramp(), Make_StairRegion());

    if (NOT TestTrue(TEXT("both fixtures bake"), StairBake._Completed && RampBake._Completed))
    { return false; }

    for (auto ToleranceStep = 1; ToleranceStep <= 8; ++ToleranceStep)
    {
        const auto Tolerance = kCellHeight * 0.25f * static_cast<float>(ToleranceStep);

        for (auto ConeDegrees = 5; ConeDegrees <= 30; ConeDegrees += 5)
        {
            const auto Tunables = FCk_GroundNav_MergeTunables{Tolerance, static_cast<float>(ConeDegrees)};

            auto StairPlates = FCk_GroundNav_PlateField{};
            auto RampPlates = FCk_GroundNav_PlateField{};

            const auto StairOk = DoDecompose_Plates(
                StairBake._Spans, StairBake._Layers, Tunables, StairPlates).Get_IsCompleted();
            const auto RampOk = DoDecompose_Plates(
                RampBake._Spans, RampBake._Layers, Tunables, RampPlates).Get_IsCompleted();

            if (NOT StairOk || NOT RampOk)
            {
                AddError(FString::Printf(TEXT("tolerance %f cone %d failed to decompose"),
                    Tolerance, ConeDegrees));
                return false;
            }

            // A ramp is one surface however it is sampled, and a staircase is never fewer plates
            // than it has treads. Between them these two bound the decomposition from both sides at
            // every setting a project might author.
            TestEqual(FString::Printf(TEXT("tolerance %.2f cone %d keeps the ramp one plate"),
                Tolerance, ConeDegrees), RampPlates._Plates.Num(), 1);

            // The guarantee a caller actually needs from the tolerance: no plate hides more height
            // than the caller allowed it to. Without this, raising the tolerance to reduce plate
            // count would silently start flattening steps.
            TestTrue(FString::Printf(TEXT("tolerance %.2f cone %d keeps every plate within its own tolerance (worst %.3f)"),
                Tolerance, ConeDegrees, StairPlates.Get_MaxHeightRangeUu()),
                StairPlates.Get_MaxHeightRangeUu() <= Tolerance + 0.01f);
            // Whatever the tunables, every walkable cell belongs to exactly one plate. A cell left
            // out of the decomposition is ground that silently stops existing.
            auto CoveredCells = 0;

            for (const auto& Plate : StairPlates._Plates)
            { CoveredCells += Plate.Get_CellCount(); }

            TestEqual(FString::Printf(TEXT("tolerance %.2f cone %d covers every staircase cell"),
                Tolerance, ConeDegrees),
                CoveredCells, StairBake._Layers.Get_AssignedSpanCount());
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
