// The one reduction from an authored markup volume to the cells it covers.
//
// Every assertion here is a hand-computed cell index, never a tolerance. The reducer decides the
// closed-square rule and the per-span surface test, and both are exact by construction: a test that
// accepted "close enough" would pass through the off-by-one that makes a volume claim the cell beside
// the one it was painted on, or the floor beneath the storey it was painted on.

#include "CkGroundNav/Bake/CkGroundNav_MarkupMask.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Sphere/CkShapeSphere_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_markupmask
{
    using ck::groundnav::Get_IsMarkupCoveringCell;
    using ck::groundnav::Get_MarkupCellRect;
    using ck::groundnav::Get_MarkupWorldBounds;

    constexpr auto kCellSizeUu = 25.0f;

    // 40 x 40 cells of 25 uu from the world origin, so the lattice covers [0, 1000] on both axes.
    constexpr auto kLatticeSize = 40;

    const auto kLatticeOriginXY = FVector2D::ZeroVector;

    auto Make_Markup(
        const FCk_AnyShape& InShape,
        const FTransform&   InTransform) -> FCk_GroundNav_MarkupRecord
    {
        return FCk_GroundNav_MarkupRecord{
            0,
            InShape,
            InTransform,
            ECk_GroundNav_MarkupKind::Walkability};
    }

    auto Make_Box(const FVector& InHalfExtents) -> FCk_AnyShape
    {
        return FCk_AnyShape{FCk_ShapeBox_Dimensions{InHalfExtents}};
    }

    auto Make_Sphere(float InRadius) -> FCk_AnyShape
    {
        return FCk_AnyShape{FCk_ShapeSphere_Dimensions{InRadius}};
    }

    auto Get_CellMinXY(int32 InX, int32 InY) -> FVector2D
    {
        return FVector2D{
            kLatticeOriginXY.X + (static_cast<double>(InX) * kCellSizeUu),
            kLatticeOriginXY.Y + (static_cast<double>(InY) * kCellSizeUu)};
    }

    auto Get_Covers(
        const FCk_GroundNav_MarkupRecord& InMarkup,
        int32                             InX,
        int32                             InY,
        float                             InSurfaceZUu) -> bool
    {
        return Get_IsMarkupCoveringCell(InMarkup, Get_CellMinXY(InX, InY), kCellSizeUu, InSurfaceZUu);
    }

    auto Get_Rect(const FCk_GroundNav_MarkupRecord& InMarkup)
        -> TOptional<ck::groundnav::FCk_GroundNav_CellRect>
    {
        return Get_MarkupCellRect(InMarkup, kLatticeOriginXY, kCellSizeUu, kLatticeSize, kLatticeSize);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupMask_AxisAlignedBoxCoversItsCellRect,
    "CkTests.UnitTests.CkGroundNav.Bake.MarkupMask_AxisAlignedBoxCoversItsCellRect",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupMask_AxisAlignedBoxCoversItsCellRect::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markupmask;

    // World X [150, 250], Y [225, 375], Z [-20, 20]. Every bound lands exactly on a cell line, which
    // is the case the closed-square rule exists for: cells 5 and 10 in X touch the box and count.
    const auto Markup = Make_Markup(
        Make_Box(FVector{50.0, 75.0, 20.0}),
        FTransform{FVector{200.0, 300.0, 0.0}});

    {
        const auto Bounds = Get_MarkupWorldBounds(Markup);

        if (NOT TestTrue(TEXT("an axis-aligned box has bounds"), static_cast<bool>(Bounds.IsValid)))
        { return false; }

        // Exactly, not within a tolerance: an unrotated, unscaled box's bounds are its own corners
        // and every step producing them is a sum of the values above.
        TestTrue(TEXT("bounds min is the transformed corner"),
            Bounds.Min == FVector{150.0, 225.0, -20.0});

        TestTrue(TEXT("bounds max is the transformed corner"),
            Bounds.Max == FVector{250.0, 375.0, 20.0});
    }

    {
        const auto Rect = Get_Rect(Markup);

        if (NOT TestTrue(TEXT("the box lands on the lattice"), Rect.IsSet()))
        { return false; }

        TestEqual(TEXT("min X counts the cell the bound only touches"), Rect->_MinX, 5);
        TestEqual(TEXT("max X counts the cell the bound only touches"), Rect->_MaxX, 10);
        TestEqual(TEXT("min Y counts the cell the bound only touches"), Rect->_MinY, 8);
        TestEqual(TEXT("max Y counts the cell the bound only touches"), Rect->_MaxY, 15);
    }

    {
        constexpr auto SurfaceZ = 0.0f;

        auto Disagreements = 0;

        for (auto CellX = 3; CellX <= 13; ++CellX)
        {
            for (auto CellY = 6; CellY <= 18; ++CellY)
            {
                const auto Expected = CellX >= 5 && CellX <= 10 && CellY >= 8 && CellY <= 15;

                if (Get_Covers(Markup, CellX, CellY, SurfaceZ) != Expected)
                { ++Disagreements; }
            }
        }

        TestEqual(TEXT("every cell inside the rectangle is covered and every cell outside it is not"),
            Disagreements, 0);
    }

    {
        // Half the box hangs off the lattice's low corner. The rectangle must clamp rather than
        // report negative indices a caller would then index an array with.
        const auto Straddling = Make_Markup(
            Make_Box(FVector{50.0, 75.0, 20.0}),
            FTransform{FVector::ZeroVector});

        const auto Rect = Get_Rect(Straddling);

        if (NOT TestTrue(TEXT("a box straddling the lattice corner still lands on it"), Rect.IsSet()))
        { return false; }

        TestEqual(TEXT("the rectangle clamps to the lattice in X"), Rect->_MinX, 0);
        TestEqual(TEXT("and keeps its unclamped far edge"), Rect->_MaxX, 2);
        TestEqual(TEXT("the rectangle clamps to the lattice in Y"), Rect->_MinY, 0);
        TestEqual(TEXT("and keeps its unclamped far edge"), Rect->_MaxY, 3);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupMask_RotatedBoxCornersAreAnalytic,
    "CkTests.UnitTests.CkGroundNav.Bake.MarkupMask_RotatedBoxCornersAreAnalytic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupMask_RotatedBoxCornersAreAnalytic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markupmask;

    // A 200 x 200 box yawed 45 degrees about (500, 500): a diamond whose tips reach 100 * sqrt(2)
    // along each world axis. Its bounding rectangle is far larger than the diamond, so the corner
    // cells of that rectangle are exactly where an axis-aligned stand-in would lie.
    const auto Markup = Make_Markup(
        Make_Box(FVector{100.0, 100.0, 20.0}),
        FTransform{FRotator{0.0, 45.0, 0.0}, FVector{500.0, 500.0, 0.0}});

    {
        const auto Rect = Get_Rect(Markup);

        if (NOT TestTrue(TEXT("the rotated box lands on the lattice"), Rect.IsSet()))
        { return false; }

        // [358.5786, 641.4214] over 25 uu cells.
        TestEqual(TEXT("the rectangle bounds the diamond in X"), Rect->_MinX, 14);
        TestEqual(TEXT("the rectangle bounds the diamond in X"), Rect->_MaxX, 25);
        TestEqual(TEXT("the rectangle bounds the diamond in Y"), Rect->_MinY, 14);
        TestEqual(TEXT("the rectangle bounds the diamond in Y"), Rect->_MaxY, 25);
    }

    {
        constexpr auto SurfaceZ = 0.0f;

        // Cell (25, 20) spans [625, 650] x [500, 525]. Its near corner sits at local
        // ((125 + 0) / sqrt(2), (0 - 125) / sqrt(2)) = (88.4, -88.4), inside the 100 half-extent.
        TestTrue(TEXT("the cell holding the diamond's +X tip is covered"),
            Get_Covers(Markup, 25, 20, SurfaceZ));

        // Cell (26, 20) spans [650, 675] x [500, 525]. Its nearest point is at local X 150 / sqrt(2)
        // = 106.1, past the half-extent, so no point of the square is inside.
        TestFalse(TEXT("the next cell out along the tip is not"),
            Get_Covers(Markup, 26, 20, SurfaceZ));

        // Cell (24, 21) spans [600, 625] x [525, 550]. Its near corner is at local
        // ((100 + 25) / sqrt(2), (25 - 100) / sqrt(2)) = (88.4, -53.0), inside on both axes.
        TestTrue(TEXT("a cell one step diagonally in is still covered"),
            Get_Covers(Markup, 24, 21, SurfaceZ));

        // Cell (25, 25) spans [625, 650] x [625, 650] — the corner of the bounding rectangle. Its
        // nearest point is at local X 250 / sqrt(2) = 176.8, far outside. This is the assertion an
        // axis-aligned footprint test fails.
        TestFalse(TEXT("the bounding rectangle's corner cell is not covered"),
            Get_Covers(Markup, 25, 25, SurfaceZ));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupMask_SphereOnACellCornerCoversFourSquares,
    "CkTests.UnitTests.CkGroundNav.Bake.MarkupMask_SphereOnACellCornerCoversFourSquares",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupMask_SphereOnACellCornerCoversFourSquares::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markupmask;

    // Centred exactly on the corner shared by cells 9 and 10 on both axes. Every one of the four
    // squares meeting there is closed, so every one of them holds the centre at distance zero.
    const auto Markup = Make_Markup(
        Make_Sphere(10.0f),
        FTransform{FVector{250.0, 250.0, 0.0}});

    {
        const auto Rect = Get_Rect(Markup);

        if (NOT TestTrue(TEXT("the sphere lands on the lattice"), Rect.IsSet()))
        { return false; }

        TestEqual(TEXT("the rectangle is the four cells sharing the corner"), Rect->Get_CellCount(), 4);
        TestEqual(TEXT("starting at cell 9 in X"), Rect->_MinX, 9);
        TestEqual(TEXT("ending at cell 10 in X"), Rect->_MaxX, 10);
        TestEqual(TEXT("starting at cell 9 in Y"), Rect->_MinY, 9);
        TestEqual(TEXT("ending at cell 10 in Y"), Rect->_MaxY, 10);
    }

    {
        constexpr auto SurfaceZ = 0.0f;

        TestTrue(TEXT("the square below-left of the corner is covered"), Get_Covers(Markup, 9, 9, SurfaceZ));
        TestTrue(TEXT("the square below-right of the corner is covered"), Get_Covers(Markup, 10, 9, SurfaceZ));
        TestTrue(TEXT("the square above-left of the corner is covered"), Get_Covers(Markup, 9, 10, SurfaceZ));
        TestTrue(TEXT("the square above-right of the corner is covered"), Get_Covers(Markup, 10, 10, SurfaceZ));

        // A 10 uu sphere reaches nowhere near a square 25 uu away, so nothing beyond the four is.
        TestFalse(TEXT("the square beyond them is not"), Get_Covers(Markup, 8, 9, SurfaceZ));
        TestFalse(TEXT("nor the one on the other side"), Get_Covers(Markup, 10, 11, SurfaceZ));

        // The sphere's own top is 10 uu up; a span at 25 is past it even though the footprint matches.
        TestFalse(TEXT("nor any of them at a height the sphere does not reach"),
            Get_Covers(Markup, 9, 9, 25.0f));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupMask_SurfaceZDecidesPerSpan,
    "CkTests.UnitTests.CkGroundNav.Bake.MarkupMask_SurfaceZDecidesPerSpan",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupMask_SurfaceZDecidesPerSpan::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markupmask;

    // Both boxes share the same XY footprint and differ only in height, so the footprint cannot be
    // what separates them: a column test would cover the ground floor from the upper storey.
    const auto Floating = Make_Markup(
        Make_Box(FVector{50.0, 50.0, 20.0}),
        FTransform{FVector{250.0, 250.0, 300.0}});

    const auto Straddling = Make_Markup(
        Make_Box(FVector{50.0, 50.0, 20.0}),
        FTransform{FVector{250.0, 250.0, 0.0}});

    constexpr auto GroundZ = 0.0f;
    constexpr auto StoreyZ = 300.0f;

    TestFalse(TEXT("a box 300 uu overhead does not cover the ground span"),
        Get_Covers(Floating, 10, 10, GroundZ));

    TestTrue(TEXT("but it does cover the span it straddles"),
        Get_Covers(Floating, 10, 10, StoreyZ));

    TestTrue(TEXT("a box straddling the ground span covers it"),
        Get_Covers(Straddling, 10, 10, GroundZ));

    TestFalse(TEXT("and does not reach the storey above"),
        Get_Covers(Straddling, 10, 10, StoreyZ));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupMask_DegenerateAndOffLatticeYieldNoRect,
    "CkTests.UnitTests.CkGroundNav.Bake.MarkupMask_DegenerateAndOffLatticeYieldNoRect",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupMask_DegenerateAndOffLatticeYieldNoRect::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markupmask;

    {
        const auto ZeroExtent = Make_Markup(
            Make_Box(FVector::ZeroVector),
            FTransform{FVector{250.0, 250.0, 0.0}});

        TestFalse(TEXT("a zero-extent shape has no bounds"),
            static_cast<bool>(Get_MarkupWorldBounds(ZeroExtent).IsValid));

        TestFalse(TEXT("and no cell rectangle"), Get_Rect(ZeroExtent).IsSet());
        TestFalse(TEXT("and covers nothing"), Get_Covers(ZeroExtent, 10, 10, 0.0f));
    }

    {
        const auto NotFinite = std::numeric_limits<double>::infinity();

        const auto NonFiniteExtent = Make_Markup(
            Make_Box(FVector{NotFinite, 50.0, 20.0}),
            FTransform{FVector{250.0, 250.0, 0.0}});

        TestFalse(TEXT("a non-finite extent has no bounds"),
            static_cast<bool>(Get_MarkupWorldBounds(NonFiniteExtent).IsValid));

        TestFalse(TEXT("and no cell rectangle"), Get_Rect(NonFiniteExtent).IsSet());
    }

    {
        const auto Unauthored = Make_Markup(
            FCk_AnyShape{},
            FTransform{FVector{250.0, 250.0, 0.0}});

        TestFalse(TEXT("an unauthored shape has no bounds"),
            static_cast<bool>(Get_MarkupWorldBounds(Unauthored).IsValid));

        TestFalse(TEXT("and no cell rectangle"), Get_Rect(Unauthored).IsSet());
    }

    {
        // The lattice covers [0, 1000]; these sit an order of magnitude past either end of it.
        const auto FarPositive = Make_Markup(
            Make_Box(FVector{50.0, 50.0, 20.0}),
            FTransform{FVector{5000.0, 5000.0, 0.0}});

        const auto FarNegative = Make_Markup(
            Make_Box(FVector{50.0, 50.0, 20.0}),
            FTransform{FVector{-5000.0, -5000.0, 0.0}});

        TestTrue(TEXT("a shape off the lattice still has bounds"),
            static_cast<bool>(Get_MarkupWorldBounds(FarPositive).IsValid));

        TestFalse(TEXT("but no cell rectangle past the far corner"), Get_Rect(FarPositive).IsSet());
        TestFalse(TEXT("nor past the near one"), Get_Rect(FarNegative).IsSet());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
