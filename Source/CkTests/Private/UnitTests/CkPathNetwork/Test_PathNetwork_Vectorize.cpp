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

    auto MakeCircularCorridorMask() -> FCk_PathNetwork_DetectionMask
    {
        constexpr auto Size = 49;
        constexpr auto Center = 24.0f;
        constexpr auto Radius = 16.0f;
        constexpr auto CorridorHalfWidth = 2.5f;

        auto Mask = FCk_PathNetwork_DetectionMask{
            FVector::ZeroVector,
            CellSize,
            Size,
            Size};

        auto Occupancy = TArray<uint8>{};
        Occupancy.SetNumZeroed(Size * Size);

        for (auto Y = 0; Y < Size; ++Y)
        {
            for (auto X = 0; X < Size; ++X)
            {
                const auto DX = static_cast<float>(X) - Center;
                const auto DY = static_cast<float>(Y) - Center;
                const auto DistanceFromCenter = FMath::Sqrt(DX * DX + DY * DY);
                Occupancy[Y * Size + X] =
                    FMath::Abs(DistanceFromCenter - Radius) <= CorridorHalfWidth
                    ? 1
                    : 0;
            }
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

    auto Count_GridScaleTurns(const FCk_PathNetwork_Ribbon& InRibbon) -> int32
    {
        const auto& Points = InRibbon.Get_Points();
        const auto IsClosed =
            Points.Num() >= 2
            && Points[0].Get_Location().Equals(
                Points.Last().Get_Location(),
                UE_KINDA_SMALL_NUMBER);
        const auto UniquePointCount = IsClosed ? Points.Num() - 1 : Points.Num();
        if (UniquePointCount < 3)
        { return 0; }

        auto Count = 0;
        for (auto Index = 0; Index < UniquePointCount; ++Index)
        {
            const auto PreviousIndex =
                (Index - 1 + UniquePointCount) % UniquePointCount;
            const auto NextIndex = (Index + 1) % UniquePointCount;
            const auto& Previous = Points[PreviousIndex].Get_Location();
            const auto& Current = Points[Index].Get_Location();
            const auto& Next = Points[NextIndex].Get_Location();
            const auto IncomingLength = FVector::Dist2D(Previous, Current);
            const auto OutgoingLength = FVector::Dist2D(Current, Next);
            if (IncomingLength > 1.5f * CellSize
                || OutgoingLength > 1.5f * CellSize)
            { continue; }

            const auto Incoming = FVector2D{Current - Previous}.GetSafeNormal();
            const auto Outgoing = FVector2D{Next - Current}.GetSafeNormal();
            const auto TurnDegrees = FMath::RadiansToDegrees(FMath::Acos(
                FMath::Clamp(
                    FVector2D::DotProduct(Incoming, Outgoing),
                    -1.0,
                    1.0)));
            if (TurnDegrees >= 35.0)
            { ++Count; }
        }
        return Count;
    }

    auto Get_DoesSegmentStayWithinMask(
        const FCk_PathNetwork_DetectionMask& InMask,
        const FVector& InStart,
        const FVector& InEnd) -> bool
    {
        const auto MaskCellSize = InMask.Get_CellSize();
        const auto& Origin = InMask.Get_Origin();
        const auto StartX = FMath::FloorToInt32(
            (InStart.X - Origin.X) / MaskCellSize);
        const auto StartY = FMath::FloorToInt32(
            (InStart.Y - Origin.Y) / MaskCellSize);
        const auto EndX = FMath::FloorToInt32(
            (InEnd.X - Origin.X) / MaskCellSize);
        const auto EndY = FMath::FloorToInt32(
            (InEnd.Y - Origin.Y) / MaskCellSize);
        const auto Delta = FVector2D{InEnd - InStart};

        for (auto Y = FMath::Min(StartY, EndY);
             Y <= FMath::Max(StartY, EndY);
             ++Y)
        {
            for (auto X = FMath::Min(StartX, EndX);
                 X <= FMath::Max(StartX, EndX);
                 ++X)
            {
                auto EnterT = 0.0;
                auto ExitT = 1.0;
                const auto IntersectsAxis =
                    [&](const double InStartCoordinate,
                        const double InDelta,
                        const double InMinimum,
                        const double InMaximum)
                    {
                        if (FMath::IsNearlyZero(InDelta))
                        {
                            return InStartCoordinate >= InMinimum &&
                                InStartCoordinate <= InMaximum;
                        }

                        auto FirstT =
                            (InMinimum - InStartCoordinate) / InDelta;
                        auto LastT =
                            (InMaximum - InStartCoordinate) / InDelta;
                        if (FirstT > LastT)
                        { Swap(FirstT, LastT); }
                        EnterT = FMath::Max(EnterT, FirstT);
                        ExitT = FMath::Min(ExitT, LastT);
                        return EnterT <= ExitT + UE_KINDA_SMALL_NUMBER;
                    };
                const auto CellMinimumX =
                    Origin.X + static_cast<double>(X) * MaskCellSize;
                const auto CellMinimumY =
                    Origin.Y + static_cast<double>(Y) * MaskCellSize;
                const auto DoesIntersect =
                    IntersectsAxis(
                        InStart.X,
                        Delta.X,
                        CellMinimumX,
                        CellMinimumX + MaskCellSize) &&
                    IntersectsAxis(
                        InStart.Y,
                        Delta.Y,
                        CellMinimumY,
                        CellMinimumY + MaskCellSize);
                if (DoesIntersect &&
                    NOT InMask.Get_IsOccupied(X, Y))
                { return false; }
            }
        }

        return true;
    }

    auto
    Get_DoesRibbonStayWithinMask(
        const FCk_PathNetwork_DetectionMask& InMask,
        const FCk_PathNetwork_Ribbon& InRibbon)
        -> bool
    {
        const auto& Points = InRibbon.Get_Points();
        for (auto PointIndex = 0;
             PointIndex < Points.Num() - 1;
             ++PointIndex)
        {
            if (NOT Get_DoesSegmentStayWithinMask(
                InMask,
                Points[PointIndex].Get_Location(),
                Points[PointIndex + 1].Get_Location()))
            { return false; }
        }

        return true;
    }

    class FMaximumLengthSegmentEvaluator final
        : public ICk_PathNetwork_VectorizationSegmentEvaluator
    {
    public:
        explicit
        FMaximumLengthSegmentEvaluator(
            const double InMaximumLength)
            : _MaximumLength{InMaximumLength}
        {
        }

        auto
        Evaluate_Segment(
            const FVector& InStart,
            const FVector& InEnd)
            -> FCk_PathNetwork_VectorizationSegmentResult override
        {
            ++_CallCount;
            auto Result =
                FCk_PathNetwork_VectorizationSegmentResult{};
            if (FVector::Distance(InStart, InEnd) >
                _MaximumLength)
            {
                Result._Decision =
                    ECk_PathNetwork_VectorizationSegmentDecision::
                        Unsupported;
            }
            return Result;
        }

        auto Get_CallCount() const -> int32
        { return _CallCount; }

    private:
        double _MaximumLength = 0.0;
        int32 _CallCount = 0;
    };

    class FMiddleGapSegmentEvaluator final
        : public ICk_PathNetwork_VectorizationSegmentEvaluator
    {
    public:
        explicit
        FMiddleGapSegmentEvaluator(
            const double InGapX)
            : _GapX{InGapX}
        {
        }

        auto
        Evaluate_Segment(
            const FVector& InStart,
            const FVector& InEnd)
            -> FCk_PathNetwork_VectorizationSegmentResult override
        {
            auto Result =
                FCk_PathNetwork_VectorizationSegmentResult{};
            const auto CrossesGap =
                FMath::Min(InStart.X, InEnd.X) < _GapX &&
                FMath::Max(InStart.X, InEnd.X) > _GapX;
            if (CrossesGap)
            {
                Result._Decision =
                    ECk_PathNetwork_VectorizationSegmentDecision::
                        Unsupported;
            }
            return Result;
        }

    private:
        double _GapX = 0.0;
    };

    class FFailingSegmentEvaluator final
        : public ICk_PathNetwork_VectorizationSegmentEvaluator
    {
    public:
        auto
        Evaluate_Segment(
            const FVector& InStart,
            const FVector& InEnd)
            -> FCk_PathNetwork_VectorizationSegmentResult override
        {
            auto Result =
                FCk_PathNetwork_VectorizationSegmentResult{};
            Result._Decision =
                ECk_PathNetwork_VectorizationSegmentDecision::
                    EvaluationFailed;
            Result._FailureReason =
                TEXT("Intentional segment evaluation failure");
            return Result;
        }
    };
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
    FCk_PathNetwork_Vectorize_DetectorVetoSubdividesSimplifiedChord,
    "Ck.PathNetwork.Vectorize.DetectorVetoSubdividesSimplifiedChord",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_PathNetwork_Vectorize_DetectorVetoSubdividesSimplifiedChord::
    RunTest(
        const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    const auto Mask = MakeMask({
        TEXT("................................"),
        TEXT("................................"),
        TEXT(".##############################."),
        TEXT(".##############################."),
        TEXT(".##############################."),
        TEXT("................................"),
        TEXT("................................")});
    auto Params = DefaultParams();
    Params.Set_SimplifyTolerance(10000.0f);
    auto Evaluator =
        FMaximumLengthSegmentEvaluator{4.0 * CellSize};

    const auto Result =
        ck::pathnetwork::Try_VectorizeMaskToRibbons(
            Mask,
            Params,
            &Evaluator);
    TestTrue(TEXT("detector-constrained vectorization succeeds"),
        Result._Succeeded);
    TestEqual(TEXT("detector veto preserves one connected ribbon"),
        Result._Ribbons.Num(), 1);
    TestTrue(TEXT("detector evaluator is consulted"),
        Evaluator.Get_CallCount() > 0);
    if (Result._Ribbons.Num() == 1)
    {
        const auto& Points = Result._Ribbons[0].Get_Points();
        TestTrue(TEXT("unsupported long chord retains subdivision points"),
            Points.Num() > 4);
        for (auto PointIndex = 0;
             PointIndex < Points.Num() - 1;
             ++PointIndex)
        {
            TestTrue(
                TEXT("every emitted chord satisfies detector length policy"),
                FVector::Distance(
                    Points[PointIndex].Get_Location(),
                    Points[PointIndex + 1].Get_Location()) <=
                    4.0 * CellSize + UE_KINDA_SMALL_NUMBER);
        }
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_DetectorVetoSplitsRawEdge,
    "Ck.PathNetwork.Vectorize.DetectorVetoSplitsRawEdge",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_PathNetwork_Vectorize_DetectorVetoSplitsRawEdge::
    RunTest(
        const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    const auto Mask = MakeMask({
        TEXT("................................"),
        TEXT("................................"),
        TEXT(".##############################."),
        TEXT(".##############################."),
        TEXT(".##############################."),
        TEXT("................................"),
        TEXT("................................")});
    auto Params = DefaultParams();
    Params.Set_SimplifyTolerance(0.0f);
    auto Evaluator = FMiddleGapSegmentEvaluator{16.0 * CellSize};

    const auto Result =
        ck::pathnetwork::Try_VectorizeMaskToRibbons(
            Mask,
            Params,
            &Evaluator);
    TestTrue(TEXT("raw-edge detector veto is a supported topology result"),
        Result._Succeeded);
    TestEqual(TEXT("unsupported raw edge partitions the generated chain"),
        Result._Ribbons.Num(), 2);
    for (const auto& Ribbon : Result._Ribbons)
    {
        TestTrue(TEXT("each partition remains usable"),
            Ribbon.Get_Points().Num() >= 2);
        for (auto PointIndex = 0;
             PointIndex < Ribbon.Get_Points().Num() - 1;
             ++PointIndex)
        {
            const auto& Start =
                Ribbon.Get_Points()[PointIndex].Get_Location();
            const auto& End =
                Ribbon.Get_Points()[PointIndex + 1].Get_Location();
            TestFalse(
                TEXT("no emitted segment crosses the unsupported raw edge"),
                FMath::Min(Start.X, End.X) < 16.0 * CellSize &&
                    FMath::Max(Start.X, End.X) > 16.0 * CellSize);
        }
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_DetectorEvaluationFailureIsAtomic,
    "Ck.PathNetwork.Vectorize.DetectorEvaluationFailureIsAtomic",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_PathNetwork_Vectorize_DetectorEvaluationFailureIsAtomic::
    RunTest(
        const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    const auto Mask = MakeMask({
        TEXT(".........."),
        TEXT(".########."),
        TEXT(".########."),
        TEXT(".########."),
        TEXT("..........")});
    auto Evaluator = FFailingSegmentEvaluator{};
    const auto Result =
        ck::pathnetwork::Try_VectorizeMaskToRibbons(
            Mask,
            DefaultParams(),
            &Evaluator);

    TestFalse(TEXT("detector evaluation failure rejects vectorization"),
        Result._Succeeded);
    TestTrue(TEXT("failure reason is preserved"),
        Result._FailureReason.Contains(
            TEXT("Intentional segment evaluation failure")));
    TestTrue(TEXT("failed vectorization publishes no partial ribbons"),
        Result._Ribbons.IsEmpty());
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
    FCk_PathNetwork_Vectorize_SimplificationDoesNotLeaveMask,
    "Ck.PathNetwork.Vectorize.SimplificationDoesNotLeaveMask",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_SimplificationDoesNotLeaveMask::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    const auto Mask = MakeMask({
        TEXT(".............."),
        TEXT(".###.........."),
        TEXT(".###.........."),
        TEXT(".###.........."),
        TEXT(".###.........."),
        TEXT(".###.........."),
        TEXT(".###.........."),
        TEXT(".###.........."),
        TEXT(".############."),
        TEXT(".############."),
        TEXT(".############."),
        TEXT("..............")});
    auto Params = DefaultParams();
    Params.Set_MinRibbonLength(0.0f);
    Params.Set_SimplifyTolerance(10000.0f);

    const auto Ribbons =
        ck::pathnetwork::Vectorize_MaskToRibbons(Mask, Params);
    TestEqual(TEXT("L corridor remains one ribbon"), Ribbons.Num(), 1);
    if (Ribbons.Num() != 1)
    { return false; }

    TestTrue(
        TEXT("unsupported diagonal shortcut retains an interior point"),
        Ribbons[0].Get_Points().Num() >= 3);
    TestTrue(
        TEXT("every simplified segment stays within occupied mask support"),
        Get_DoesRibbonStayWithinMask(Mask, Ribbons[0]));

    auto NearCornerMask = FCk_PathNetwork_DetectionMask{
        FVector::ZeroVector,
        CellSize,
        103,
        102};
    auto NearCornerOccupancy = TArray<uint8>{};
    NearCornerOccupancy.Init(
        1,
        NearCornerMask.Get_SizeX() * NearCornerMask.Get_SizeY());
    NearCornerOccupancy[1] = 0;
    NearCornerMask.Set_Occupancy(NearCornerOccupancy);
    TestFalse(
        TEXT("exact mask oracle catches a sub-tenth-cell near-corner crossing"),
        Get_DoesSegmentStayWithinMask(
            NearCornerMask,
            NearCornerMask.Get_CellWorldLocation(0, 0),
            NearCornerMask.Get_CellWorldLocation(101, 100)));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_CornerTouchingCellsDoNotConnect,
    "Ck.PathNetwork.Vectorize.CornerTouchingCellsDoNotConnect",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_CornerTouchingCellsDoNotConnect::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    auto Params = DefaultParams();
    Params.Set_MinRibbonLength(0.0f);
    Params.Set_SimplifyTolerance(0.0f);

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(
        MakeMask({
            TEXT("#..."),
            TEXT(".#.."),
            TEXT("..#."),
            TEXT("...#")}),
        Params);

    TestEqual(
        TEXT("corner-only occupied cells do not form a traversable ribbon"),
        Ribbons.Num(),
        0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_SupportedDiagonalCorridorStaysConnected,
    "Ck.PathNetwork.Vectorize.SupportedDiagonalCorridorStaysConnected",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_SupportedDiagonalCorridorStaysConnected::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    auto Params = DefaultParams();
    Params.Set_MinRibbonLength(0.0f);
    Params.Set_SimplifyTolerance(0.0f);

    const auto Ribbons = ck::pathnetwork::Vectorize_MaskToRibbons(
        MakeMask({
            TEXT("........."),
            TEXT(".##......"),
            TEXT(".###....."),
            TEXT("..###...."),
            TEXT("...###..."),
            TEXT("....###.."),
            TEXT(".....###."),
            TEXT("......##."),
            TEXT(".........")}),
        Params);

    TestEqual(
        TEXT("area-supported diagonal corridor remains connected"),
        Ribbons.Num(),
        1);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_SimplificationPreservesTerrainHeight,
    "Ck.PathNetwork.Vectorize.SimplificationPreservesTerrainHeight",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_SimplificationPreservesTerrainHeight::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    auto Mask = MakeMask({
        TEXT("........."),
        TEXT(".#######."),
        TEXT(".#######."),
        TEXT(".#######."),
        TEXT(".........")});
    auto Heights = TArray<float>{};
    Heights.SetNumZeroed(Mask.Get_SizeX() * Mask.Get_SizeY());
    for (auto Y = 0; Y < Mask.Get_SizeY(); ++Y)
    {
        Heights[Y * Mask.Get_SizeX() + 4] = 200.0f;
    }
    Mask.Set_Heights(Heights);

    constexpr float SimplifyTolerances[] = {0.0f, 10.0f};
    for (const auto SimplifyTolerance : SimplifyTolerances)
    {
        auto Params = DefaultParams();
        Params.Set_MinRibbonLength(0.0f);
        Params.Set_SimplifyTolerance(SimplifyTolerance);

        const auto Ribbons =
            ck::pathnetwork::Vectorize_MaskToRibbons(Mask, Params);
        TestEqual(
            FString::Printf(
                TEXT("height-varying corridor remains one ribbon at tolerance %.1f"),
                SimplifyTolerance),
            Ribbons.Num(),
            1);
        if (Ribbons.Num() != 1)
        { continue; }

        auto HighestPoint = TNumericLimits<double>::Lowest();
        for (const auto& Point : Ribbons[0].Get_Points())
        {
            HighestPoint = FMath::Max(
                HighestPoint,
                Point.Get_Location().Z);
        }
        TestTrue(
            FString::Printf(
                TEXT("tolerance %.1f retains the terrain-height sample (got %.1f cm)"),
                SimplifyTolerance,
                HighestPoint),
            HighestPoint >= 199.0);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_CircularCorridorSuppressesRasterStairSteps,
    "Ck.PathNetwork.Vectorize.CircularCorridorSuppressesRasterStairSteps",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_CircularCorridorSuppressesRasterStairSteps::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_vectorize;

    auto Params = DefaultParams();
    Params.Set_SimplifyTolerance(CellSize * 0.25f);
    const auto Ribbons =
        ck::pathnetwork::Vectorize_MaskToRibbons(
            MakeCircularCorridorMask(),
            Params);

    TestEqual(TEXT("circular corridor remains one ring ribbon"), Ribbons.Num(), 1);
    if (Ribbons.Num() != 1)
    { return false; }

    const auto& Points = Ribbons[0].Get_Points();
    TestTrue(TEXT("circular corridor remains closed"),
        Points.Num() >= 2
        && Points[0].Get_Location().Equals(
            Points.Last().Get_Location(),
            UE_KINDA_SMALL_NUMBER));

    const auto GridScaleTurns = Count_GridScaleTurns(Ribbons[0]);
    AddInfo(FString::Printf(
        TEXT("Simplified circular corridor: %d points, %d cell-scale turns"),
        Points.Num(),
        GridScaleTurns));
    TestEqual(
        TEXT("circular corridor has no cell-scale staircase turns"),
        GridScaleTurns,
        0);

    auto RawParams = Params;
    RawParams.Set_SimplifyTolerance(0.0f);
    const auto RawRibbons =
        ck::pathnetwork::Vectorize_MaskToRibbons(
            MakeCircularCorridorMask(),
            RawParams);
    TestEqual(TEXT("zero tolerance still preserves one raw ring"), RawRibbons.Num(), 1);
    if (RawRibbons.Num() == 1)
    {
        const auto RawGridScaleTurns = Count_GridScaleTurns(RawRibbons[0]);
        AddInfo(FString::Printf(
            TEXT("Raw circular corridor: %d points, %d cell-scale turns"),
            RawRibbons[0].Get_Points().Num(),
            RawGridScaleTurns));
        TestTrue(
            TEXT("zero tolerance preserves raw grid detail"),
            RawGridScaleTurns > 0);
    }

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

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_RibbonSimplificationHonorsTolerance,
    "Ck.PathNetwork.Vectorize.RibbonSimplificationHonorsTolerance",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_RibbonSimplificationHonorsTolerance::RunTest(
    const FString& Parameters)
{
    const auto Source = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 100.0f},
        FCk_PathNetwork_RibbonPoint{FVector{25.0, 5.0, 0.0}, 100.0f},
        FCk_PathNetwork_RibbonPoint{FVector{50.0, 10.0, 0.0}, 100.0f},
        FCk_PathNetwork_RibbonPoint{FVector{75.0, 5.0, 0.0}, 100.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 0.0}, 100.0f}};

    const auto Unsimplified = ck::pathnetwork::Simplify_RibbonPoints(
        Source,
        0.0f);
    TestEqual(TEXT("zero tolerance preserves every source point"),
        Unsimplified.Num(),
        Source.Num());

    const auto Simplified = ck::pathnetwork::Simplify_RibbonPoints(
        Source,
        6.0f);
    TestTrue(TEXT("positive tolerance removes redundant curve samples"),
        Simplified.Num() < Source.Num());
    TestTrue(TEXT("simplification preserves the exact first point"),
        Simplified[0].Get_Location().Equals(Source[0].Get_Location()) &&
        FMath::IsNearlyEqual(
            Simplified[0].Get_HalfWidth(),
            Source[0].Get_HalfWidth()));
    TestTrue(TEXT("simplification preserves the exact last point"),
        Simplified.Last().Get_Location().Equals(Source.Last().Get_Location()) &&
        FMath::IsNearlyEqual(
            Simplified.Last().Get_HalfWidth(),
            Source.Last().Get_HalfWidth()));
    TestTrue(TEXT("curve deviation above tolerance retains its apex"),
        Simplified.ContainsByPredicate(
            [&Source](const FCk_PathNetwork_RibbonPoint& InPoint)
            {
                return InPoint.Get_Location().Equals(
                    Source[2].Get_Location());
            }));

    const auto SourceConstrained = ck::pathnetwork::Simplify_RibbonPoints(
        Source,
        10000.0f,
        [](const int32 InFirstIndex, const int32 InLastIndex)
        { return InLastIndex - InFirstIndex <= 1; });
    TestEqual(TEXT("unsupported shortcut chords retain the original supported route"),
        SourceConstrained.Num(),
        Source.Num());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Vectorize_RibbonSimplificationPreservesHeightAndWidth,
    "Ck.PathNetwork.Vectorize.RibbonSimplificationPreservesHeightAndWidth",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Vectorize_RibbonSimplificationPreservesHeightAndWidth::RunTest(
    const FString& Parameters)
{
    const auto HeightProfile = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{50.0, 0.0, 30.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 0.0}, 50.0f}};
    const auto HeightResult = ck::pathnetwork::Simplify_RibbonPoints(
        HeightProfile,
        25.0f);
    TestEqual(TEXT("height deviation above tolerance retains the source point"),
        HeightResult.Num(),
        3);

    const auto WidthProfile = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{50.0, 0.0, 0.0}, 100.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 0.0}, 50.0f}};
    const auto WidthResult = ck::pathnetwork::Simplify_RibbonPoints(
        WidthProfile,
        25.0f);
    TestEqual(TEXT("half-width deviation above tolerance retains the source point"),
        WidthResult.Num(),
        3);

    const auto EdgeProfile = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{50.0, 15.0, 0.0}, 65.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 0.0}, 50.0f}};
    const auto EdgeResult = ck::pathnetwork::Simplify_RibbonPoints(
        EdgeProfile,
        25.0f);
    TestEqual(TEXT("combined centerline and width error bounds corridor-edge drift"),
        EdgeResult.Num(),
        3);

    // Asymmetric endpoints with an off-center interior sample (chord T = 0.25) pin the
    // interpolated reference itself: a reference read at the wrong T or from swapped
    // endpoints turns each on-profile deviation from ~3 cm into an above-tolerance one.
    const auto HeightRampProfile = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{25.0, 0.0, 28.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 100.0}, 50.0f}};
    const auto HeightRampResult = ck::pathnetwork::Simplify_RibbonPoints(
        HeightRampProfile,
        10.0f);
    TestEqual(TEXT("a sample near the interpolated height ramp collapses onto the chord"),
        HeightRampResult.Num(),
        2);

    const auto WidthRampProfile = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{25.0, 0.0, 0.0}, 65.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 0.0}, 100.0f}};
    const auto WidthRampResult = ck::pathnetwork::Simplify_RibbonPoints(
        WidthRampProfile,
        10.0f);
    TestEqual(TEXT("a sample near the interpolated width ramp collapses onto the chord"),
        WidthRampResult.Num(),
        2);

    const auto HeightRampSpikeProfile = TArray<FCk_PathNetwork_RibbonPoint>{
        FCk_PathNetwork_RibbonPoint{FVector{0.0, 0.0, 0.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{25.0, 0.0, 60.0}, 50.0f},
        FCk_PathNetwork_RibbonPoint{FVector{100.0, 0.0, 100.0}, 50.0f}};
    const auto HeightRampSpikeResult = ck::pathnetwork::Simplify_RibbonPoints(
        HeightRampSpikeProfile,
        10.0f);
    TestEqual(TEXT("a spike above the interpolated height ramp is retained"),
        HeightRampSpikeResult.Num(),
        3);
    return true;
}
