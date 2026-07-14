#include "Misc/AutomationTest.h"

#include "CkPathNetwork/Network/CkPathNetwork_Types.h"
#include "CkPathNetwork/Network/CkPathNetwork_Vectorize.h"

// --------------------------------------------------------------------------------------------------------------------
// Pure-math vectorizer tests: ASCII-art masks in, ribbon topology out. No world, no ECS.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pathnetwork_vectorize
{
    constexpr auto CellSize = 50.0f;

    // '#' = occupied, anything else = empty. Row 0 is Y=0.
    auto MakeMask(const TArray<FString>& InRows) -> FCk_PathNetwork_DetectionMask
    {
        const auto SizeY = InRows.Num();
        const auto SizeX = InRows[0].Len();

        auto Mask = FCk_PathNetwork_DetectionMask{FVector::ZeroVector, CellSize, SizeX, SizeY};

        auto Occupancy = TArray<uint8>{};
        Occupancy.SetNumZeroed(SizeX * SizeY);

        for (auto Y = 0; Y < SizeY; ++Y)
        {
            for (auto X = 0; X < SizeX; ++X)
            { Occupancy[Y * SizeX + X] = InRows[Y][X] == TEXT('#') ? 1 : 0; }
        }

        Mask.Set_Occupancy(Occupancy);
        return Mask;
    }

    auto DefaultParams() -> FCk_PathNetwork_VectorizeParams
    {
        auto Params = FCk_PathNetwork_VectorizeParams{};
        Params.Set_MinHalfWidth(25.0f);
        Params.Set_SimplifyTolerance(30.0f);
        Params.Set_MinRibbonLength(200.0f);
        return Params;
    }

    auto Get_RibbonLength(const FCk_PathNetwork_Ribbon& InRibbon) -> float
    {
        auto Length = 0.0f;
        const auto& Points = InRibbon.Get_Points();
        for (auto Index = 0; Index < Points.Num() - 1; ++Index)
        { Length += static_cast<float>(FVector::Dist(Points[Index].Get_Location(), Points[Index + 1].Get_Location())); }
        return Length;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_StraightCorridor,
    "Ck.PathNetwork.Vectorize.StraightCorridor",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_StraightCorridor::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    // 30-cell horizontal stripe, 3 cells wide, padded with empty border.
    auto Rows = TArray<FString>{};
    Rows.Add(TEXT("................................"));
    Rows.Add(TEXT("................................"));
    Rows.Add(TEXT(".##############################."));
    Rows.Add(TEXT(".##############################."));
    Rows.Add(TEXT(".##############################."));
    Rows.Add(TEXT("................................"));
    Rows.Add(TEXT("................................"));

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(MakeMask(Rows), DefaultParams());

    TestEqual(TEXT("one ribbon"), Ribbons.Num(), 1);
    if (Ribbons.Num() != 1)
    { return false; }

    const auto& Ribbon = Ribbons[0];
    TestEqual(TEXT("source is Generated"), Ribbon.Get_Source(), ECk_PathNetwork_RibbonSource::Generated);
    TestTrue(TEXT("ribbon id assigned"), Ribbon.Get_RibbonId().IsValid());
    TestTrue(TEXT("simplified to few points"), Ribbon.Get_Points().Num() >= 2 && Ribbon.Get_Points().Num() <= 4);

    // Stripe runs x-cells [1..30] -> centerline length ~29 cells = 1450cm. Thinning eats a pixel
    // or two at the ends; allow a generous band.
    const auto Length = Get_RibbonLength(Ribbon);
    TestTrue(FString::Printf(TEXT("length ~stripe length (got %.0f)"), Length), Length > 1200.0f && Length < 1550.0f);

    // 3-wide stripe: centerline to paint boundary = 1.5 cells = 75cm.
    for (const auto& Point : Ribbon.Get_Points())
    {
        TestTrue(FString::Printf(TEXT("half-width ~75cm (got %.0f)"), Point.Get_HalfWidth()),
            Point.Get_HalfWidth() >= 60.0f && Point.Get_HalfWidth() <= 90.0f);
    }

    // Centerline should sit on the stripe's middle row (y=3 -> world Y = 175).
    for (const auto& Point : Ribbon.Get_Points())
    {
        TestTrue(FString::Printf(TEXT("centerline on middle row (got Y=%.0f)"), Point.Get_Location().Y),
            FMath::Abs(Point.Get_Location().Y - 175.0) <= CellSize);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_LCorridor,
    "Ck.PathNetwork.Vectorize.LCorridor",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_LCorridor::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    // L: horizontal arm + vertical arm, 3 cells wide.
    auto Rows = TArray<FString>{};
    Rows.Add(TEXT("......................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".###..................."));
    Rows.Add(TEXT(".#####################."));
    Rows.Add(TEXT(".#####################."));
    Rows.Add(TEXT(".#####################."));
    Rows.Add(TEXT("......................."));

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(MakeMask(Rows), DefaultParams());

    TestEqual(TEXT("one ribbon (elbow is degree-2)"), Ribbons.Num(), 1);
    if (Ribbons.Num() != 1)
    { return false; }

    // The elbow must survive simplification: at least 3 points, one of them near the corner
    // (cell ~(2, 9) -> world ~(125, 475)).
    const auto& Points = Ribbons[0].Get_Points();
    TestTrue(TEXT("at least 3 points (corner retained)"), Points.Num() >= 3);

    auto HasCornerPoint = false;
    for (const auto& Point : Points)
    {
        if (FVector::Dist2D(Point.Get_Location(), FVector{125.0, 475.0, 0.0}) <= 3.0 * CellSize)
        { HasCornerPoint = true; }
    }
    TestTrue(TEXT("a point sits near the elbow"), HasCornerPoint);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_TJunction,
    "Ck.PathNetwork.Vectorize.TJunction",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_TJunction::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    // T: horizontal bar with a vertical stem dropping from its middle.
    auto Rows = TArray<FString>{};
    Rows.Add(TEXT("........................."));
    Rows.Add(TEXT(".#######################."));
    Rows.Add(TEXT(".#######################."));
    Rows.Add(TEXT(".#######################."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("...........###..........."));
    Rows.Add(TEXT("........................."));

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(MakeMask(Rows), DefaultParams());

    // Three chains meet at the junction: left arm, right arm, stem.
    TestEqual(TEXT("three ribbons"), Ribbons.Num(), 3);
    if (Ribbons.Num() != 3)
    { return false; }

    // Each ribbon must have one endpoint near the junction (cell ~(12, 2..4) -> world ~(625, 150)).
    const auto JunctionArea = FVector{625.0, 150.0, 0.0};
    auto EndpointsNearJunction = 0;

    for (const auto& Ribbon : Ribbons)
    {
        const auto& First = Ribbon.Get_Points()[0].Get_Location();
        const auto& Last = Ribbon.Get_Points().Last().Get_Location();

        if (FVector::Dist2D(First, JunctionArea) <= 4.0 * CellSize ||
            FVector::Dist2D(Last, JunctionArea) <= 4.0 * CellSize)
        { ++EndpointsNearJunction; }
    }

    TestEqual(TEXT("every ribbon touches the junction"), EndpointsNearJunction, 3);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_Loop,
    "Ck.PathNetwork.Vectorize.Loop",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_Loop::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    // Hollow square ring, 3 cells thick, outer 15x15.
    auto Rows = TArray<FString>{};
    Rows.Add(TEXT("................."));
    Rows.Add(TEXT(".###############."));
    Rows.Add(TEXT(".###############."));
    Rows.Add(TEXT(".###############."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###.........###."));
    Rows.Add(TEXT(".###############."));
    Rows.Add(TEXT(".###############."));
    Rows.Add(TEXT(".###############."));
    Rows.Add(TEXT("................."));

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(MakeMask(Rows), DefaultParams());

    TestEqual(TEXT("one ring ribbon"), Ribbons.Num(), 1);
    if (Ribbons.Num() != 1)
    { return false; }

    const auto& Points = Ribbons[0].Get_Points();
    TestTrue(TEXT("ring is closed (first == last)"),
        FVector::Dist(Points[0].Get_Location(), Points.Last().Get_Location()) < 1.0);

    // Centerline ring perimeter ~ 4 * 12 cells = 2400cm; allow slack for corner cuts.
    const auto Length = Get_RibbonLength(Ribbons[0]);
    TestTrue(FString::Printf(TEXT("perimeter in band (got %.0f)"), Length), Length > 1800.0f && Length < 2700.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_NoiseFiltered,
    "Ck.PathNetwork.Vectorize.NoiseFiltered",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_NoiseFiltered::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    // A lone paint speck far from anything: shorter than MinRibbonLength -> dropped.
    auto Rows = TArray<FString>{};
    Rows.Add(TEXT("............"));
    Rows.Add(TEXT("....##......"));
    Rows.Add(TEXT("....##......"));
    Rows.Add(TEXT("............"));

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(MakeMask(Rows), DefaultParams());
    TestEqual(TEXT("speck produces no ribbons"), Ribbons.Num(), 0);

    // Fully-empty (but structurally valid) mask -> no ribbons, no ensure.
    auto EmptyRows = TArray<FString>{};
    EmptyRows.Add(TEXT("...."));
    EmptyRows.Add(TEXT("...."));

    const auto EmptyResult = ck::pathnetwork::Vectorize_MaskToRibbons(MakeMask(EmptyRows), DefaultParams());
    TestEqual(TEXT("empty mask produces no ribbons"), EmptyResult.Num(), 0);

    return true;
}
