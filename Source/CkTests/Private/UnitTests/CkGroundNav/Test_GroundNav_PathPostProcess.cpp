// What turns a corridor into a line a body can walk, stage by stage.
//
// Every stage is a pure function over a field the caller holds, so each one is exercised ALONE here and
// the composed answer is checked to be those stages in order and nothing else. That split is the point:
// a plan that came out wrong has one stage that produced it, and a test that only ever ran the whole
// pipeline could not say which.
//
// The claims: an L corridor is three waypoints and every one of them stands a radius clear of the wall;
// the corner pass moves interior waypoints by the offset it was asked for, away from what they were
// hugging, and never onto ground the field refuses; the skip-first pass drops exactly the waypoint the
// Recast path drops, on the same threshold, so a body switching providers does not change which point it
// steers at first; the fill's integrated distance is the funnel's own return rather than a second
// arithmetic; and merging plate tables takes the greater, which is the rule the search prices with.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"
#include "CkGroundNav/Query/CkGroundNav_QueryTypes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Boundary.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"
#include "Test_GroundNav_ReferencePaths.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathpostprocess
{
    using ck::groundnav::FCk_GroundNav_ClosestBoundaryQuery;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_PathCostParams;
    using ck::groundnav::FCk_GroundNav_PathPlan;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_PathWaypoint;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::Get_ClosestBoundary;
    using ck::groundnav::Get_CornerOffset;
    using ck::groundnav::Get_FilledWaypoints;
    using ck::groundnav::Get_Funnelled;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_MaxMerged;
    using ck::groundnav::Get_Path;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Get_SkipFirstWaypoint;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_LCorridorScene;
    using ck_test_groundnav_queryfixtures::Get_LCorridorCentreChainLengthUu;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kLCorridorGoal;
    using ck_test_groundnav_queryfixtures::kLCorridorStart;
    using ck_test_groundnav_queryfixtures::kLCorridorStraightGoal;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_LCorridorScene;
    using ck_test_groundnav_queryfixtures::Make_Params;

    using ck_test_groundnav_referencepaths::kEpsilon;

    // Wide enough that a body of this radius crosses the corridor with room to spare on both sides, so a
    // waypoint that ends up nearer than this to a wall was put there by a pass and not by the geometry.
    constexpr auto kCorridorRadiusUu = 20.0f;

    // The offset the corner pass is asked for, as the cost model states it: a multiple of the radius.
    constexpr auto kCornerOffsetK = 1.0f;

    // Boundary runs are stored as floats and the funnel insets in doubles, so two answers about the same
    // wall differ in the last places. A uu is far under anything a pass could move a waypoint by.
    constexpr auto kBoundarySlackUu = 1.0;

    // Far enough that no threshold the skip-first pass could compute reaches it, so a test that wants
    // every waypoint kept gets every waypoint kept.
    const auto kDistantAgentLocation = FVector{-5000.0, -5000.0, kGroundZ};

    // The probe only has to find the corridor's own walls, which are never further than half its width.
    constexpr auto kBoundaryProbeRadiusMultiplier = 4.0f;

    constexpr auto kStraightIsTwoWaypoints = 2;
    constexpr auto kBentOnceIsThreeWaypoints = 3;

    // No route here crosses an authored link, so no waypoint of one is exempt from the offset.
    const auto kNothingPinned = TArray<FVector>{};

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Make_PathQuery(
        const FVector& InStart,
        const FVector& InGoal,
        float          InRadiusUu) -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(InRadiusUu);

        return Query;
    }

    auto Make_PostParams(
        float InRadiusUu,
        float InCornerOffsetK,
        const FVector& InAgentLocation) -> FCk_GroundNav_PathPostParams
    {
        auto Params = FCk_GroundNav_PathPostParams{};

        Params._Agent = Make_Agent(InRadiusUu);
        Params._VerticalToleranceUu = kStepHeight;
        Params._AgentLocation = InAgentLocation;
        Params._Cost._CornerOffsetK = InCornerOffsetK;

        return Params;
    }

    /**
     * The scene held the way the search takes one.
     *
     * A search holds its field by shared pointer so a rebuild underneath it cannot take it away, which
     * means a scene a path is asked of has to be published into one rather than kept on the stack.
     */
    auto Bake_Shared(
        const TArray<FBox>&              InBoxes,
        const FCk_GroundNav_FieldParams& InParams,
        FCk_GroundNav_FieldPtr&          OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(InBoxes, InParams, *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    auto Bake_SharedLCorridor(
        FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        return Bake_Shared(Make_LCorridorScene(), Make_Params(FIntPoint{1, 1}), OutField);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * How far a point stands from the nearest wall, or nothing where no wall is in range.
     *
     * Asked for a body of NO size deliberately: the probe is a question about the geometry, and a point
     * sitting exactly a radius from a wall stands on a cell whose own clearance may refuse that radius,
     * which would answer about admission rather than about distance.
     */
    auto Get_BoundaryDistanceUu(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation,
        float                      InRadiusUu) -> TOptional<double>
    {
        auto Query = FCk_GroundNav_ClosestBoundaryQuery{};

        Query._Location = InLocation;
        Query._MaxRadiusUu = InRadiusUu * kBoundaryProbeRadiusMultiplier;
        Query._VerticalWindowUu = kStepHeight;

        const auto Result = Get_ClosestBoundary(InField, Query);

        if (NOT Result.Get_IsSuccess())
        { return {}; }

        return static_cast<double>(Result._DistanceUu);
    }

    auto Get_IsOnWalkableGround(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> bool
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStepHeight;

        return Get_IsNavigable(InField, Query).Get_IsSuccess();
    }

    auto Get_WaypointReport(
        TConstArrayView<FVector> InWaypoints) -> FString
    {
        auto Report = FString::Printf(TEXT("%d waypoints"), InWaypoints.Num());

        for (const auto& Waypoint : InWaypoints)
        { Report += FString::Printf(TEXT(" (%.2f, %.2f)"), Waypoint.X, Waypoint.Y); }

        return Report;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Line(
        int32   InCount,
        double  InSpacingUu) -> TArray<FVector>
    {
        auto Points = TArray<FVector>{};
        Points.Reserve(InCount);

        for (auto Index = 0; Index < InCount; ++Index)
        { Points.Emplace(FVector{static_cast<double>(Index) * InSpacingUu, 0.0, kGroundZ}); }

        return Points;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_LCorridorThreeWaypointsAllClearOfBoundary,
    "CkTests.UnitTests.CkGroundNav.Path.LCorridor_ThreeWaypointsAllClearOfBoundary",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_LCorridorThreeWaypointsAllClearOfBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathpostprocess;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the L corridor scene bakes"), Bake_SharedLCorridor(Field)))
    { return false; }

    const auto Bent = Get_Path(Field, Make_PathQuery(kLCorridorStart, kLCorridorGoal, kCorridorRadiusUu));

    if (NOT TestEqual(TEXT("the L corridor answers a route around its corner"),
        Bent._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    auto Waypoints = TArray<FVector>{};

    const auto PulledUu = Get_Funnelled(Bent, kCorridorRadiusUu, Waypoints);
    const auto ChainUu = Get_LCorridorCentreChainLengthUu(kLCorridorStart, kLCorridorGoal);

    const auto Report = FString::Printf(
        TEXT("%s, pulled %.3f, centre chain %.3f, plates %d, crossings %d"),
        *Get_WaypointReport(Waypoints), PulledUu, ChainUu,
        Bent._PlateCorridor.Num(), Bent._Crossings.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

    // The inside corner is the one reflex corner of this free space, so it is the one place a shortest
    // string may bend — before the skip-first pass has a chance to drop anything off either end.
    if (NOT TestEqual(FString::Printf(TEXT("the L bends exactly once [%s]"), *Report),
        Waypoints.Num(), kBentOnceIsThreeWaypoints))
    { return false; }

    // The chain through the two legs' centre lines is a route the corridor admits, so the shortest one
    // through the same corridor cannot be longer than it.
    TestTrue(FString::Printf(TEXT("the pulled string is no longer than the centre chain [%s]"), *Report),
        PulledUu <= ChainUu + kEpsilon);

    auto TooNearAWall = 0;
    auto OffWalkableGround = 0;
    auto WorstDistanceUu = TNumericLimits<double>::Max();

    for (const auto& Waypoint : Waypoints)
    {
        if (NOT Get_IsOnWalkableGround(*Field, Waypoint))
        { ++OffWalkableGround; }

        const auto DistanceUu = Get_BoundaryDistanceUu(*Field, Waypoint, kCorridorRadiusUu);

        if (NOT DistanceUu.IsSet())
        { continue; }

        WorstDistanceUu = FMath::Min(WorstDistanceUu, DistanceUu.GetValue());

        if (DistanceUu.GetValue() < static_cast<double>(kCorridorRadiusUu) - kBoundarySlackUu)
        { ++TooNearAWall; }
    }

    const auto ClearanceReport = FString::Printf(
        TEXT("%s, nearest wall %.3f, radius %.3f"),
        *Report, WorstDistanceUu, static_cast<double>(kCorridorRadiusUu));

    ck::groundnav::Display(TEXT("{}"), ClearanceReport);

    // The inset lives inside the funnel, so a waypoint nearer than a radius to a wall is a body clipping
    // that wall on the way through — the one thing the inset exists to prevent.
    TestEqual(FString::Printf(TEXT("every waypoint stands a radius clear of the nearest wall [%s]"), *ClearanceReport),
        TooNearAWall, 0);

    TestEqual(FString::Printf(TEXT("and on ground the field still calls walkable [%s]"), *ClearanceReport),
        OffWalkableGround, 0);

    // The same corridor with both ends on ONE leg has no reflex corner between them, so the string is
    // the straight line and the count says so.
    const auto Straight = Get_Path(
        Field, Make_PathQuery(kLCorridorStart, kLCorridorStraightGoal, kCorridorRadiusUu));

    if (NOT TestEqual(TEXT("a pair along one leg is answered too"),
        Straight._Status, ECk_GroundNav_PathStatus::Ready))
    { return true; }

    auto StraightWaypoints = TArray<FVector>{};
    Get_Funnelled(Straight, kCorridorRadiusUu, StraightWaypoints);

    TestEqual(FString::Printf(TEXT("a straight run bends nowhere [%s]"), *Get_WaypointReport(StraightWaypoints)),
        StraightWaypoints.Num(), kStraightIsTwoWaypoints);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_CornerOffsetMovesOnlyInsideCorners,
    "CkTests.UnitTests.CkGroundNav.Path.CornerOffset_MovesOnlyInsideCornersByAnalyticAmount",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_CornerOffsetMovesOnlyInsideCorners::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathpostprocess;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the L corridor scene bakes"), Bake_SharedLCorridor(Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(kLCorridorStart, kLCorridorGoal, kCorridorRadiusUu));

    if (NOT TestEqual(TEXT("the L corridor answers a route around its corner"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    auto Funnelled = TArray<FVector>{};
    Get_Funnelled(Result, kCorridorRadiusUu, Funnelled);

    if (NOT TestEqual(TEXT("the route has an interior waypoint to offset"),
        Funnelled.Num(), kBentOnceIsThreeWaypoints))
    { return false; }

    const auto OffsetUu = static_cast<double>(kCornerOffsetK * kCorridorRadiusUu);

    const auto Offset = Get_CornerOffset(
        Funnelled, kNothingPinned, *Field, static_cast<float>(OffsetUu),
        Make_Agent(kCorridorRadiusUu), kStepHeight);

    const auto Unmoved = Get_CornerOffset(
        Funnelled, kNothingPinned, *Field, 0.0f, Make_Agent(kCorridorRadiusUu), kStepHeight);

    if (NOT TestEqual(TEXT("the pass answers with as many waypoints as it was given"),
        Offset.Num(), Funnelled.Num()))
    { return false; }

    const auto CornerIndex = 1;

    const auto BeforeUu = Get_BoundaryDistanceUu(*Field, Funnelled[CornerIndex], kCorridorRadiusUu);
    const auto AfterUu = Get_BoundaryDistanceUu(*Field, Offset[CornerIndex], kCorridorRadiusUu);

    const auto MovedUu = FVector::Dist(Funnelled[CornerIndex], Offset[CornerIndex]);

    const auto Report = FString::Printf(
        TEXT("corner (%.3f, %.3f) -> (%.3f, %.3f), moved %.4f, asked %.4f, wall %.4f -> %.4f, radius %.1f"),
        Funnelled[CornerIndex].X, Funnelled[CornerIndex].Y,
        Offset[CornerIndex].X, Offset[CornerIndex].Y,
        MovedUu, OffsetUu,
        BeforeUu.IsSet() ? BeforeUu.GetValue() : -1.0,
        AfterUu.IsSet() ? AfterUu.GetValue() : -1.0,
        static_cast<double>(kCorridorRadiusUu));

    ck::groundnav::Display(TEXT("{}"), Report);

    // The ends of a route are where the body is and where it was told to go; a pass that moved either
    // would be answering a different query than the one that was asked.
    TestTrue(FString::Printf(TEXT("the first waypoint is untouched [%s]"), *Report),
        Offset[0].Equals(Funnelled[0], kEpsilon));

    TestTrue(FString::Printf(TEXT("and so is the last [%s]"), *Report),
        Offset.Last().Equals(Funnelled.Last(), kEpsilon));

    TestTrue(FString::Printf(TEXT("the inside corner moves by exactly the offset it was asked for [%s]"), *Report),
        FMath::Abs(MovedUu - OffsetUu) <= kEpsilon);

    // Which way it moved is the whole point: an inside corner is a waypoint hugging a wall, and an offset
    // that did not put more wall between the body and that wall bought nothing.
    if (BeforeUu.IsSet() && AfterUu.IsSet())
    {
        TestTrue(FString::Printf(TEXT("and moves AWAY from the wall it was hugging [%s]"), *Report),
            AfterUu.GetValue() > BeforeUu.GetValue() + kEpsilon);

        TestTrue(FString::Printf(TEXT("and lands no nearer than a radius to any wall [%s]"), *Report),
            AfterUu.GetValue() >= static_cast<double>(kCorridorRadiusUu) - kBoundarySlackUu);
    }

    TestTrue(FString::Printf(TEXT("and lands on ground the field still calls walkable [%s]"), *Report),
        Get_IsOnWalkableGround(*Field, Offset[CornerIndex]));

    // Zero is off, not a small offset: the funnel already inset by a radius, so a pass asked for nothing
    // has nothing to improve and must hand back exactly what it was given.
    auto MovedAtZero = 0;

    for (auto Index = 0; Index < Funnelled.Num(); ++Index)
    {
        if (NOT Unmoved[Index].Equals(Funnelled[Index], kEpsilon))
        { ++MovedAtZero; }
    }

    TestEqual(FString::Printf(TEXT("an offset of zero moves nothing at all [%s]"), *Report), MovedAtZero, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_SkipFirstMirrorsTheCkPass,
    "CkTests.UnitTests.CkGroundNav.Path.SkipFirst_MirrorsTheCkPass",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_SkipFirstMirrorsTheCkPass::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathpostprocess;

    constexpr auto RadiusUu = 20.0f;
    constexpr auto SpacingUu = 100.0;
    constexpr auto PointCount = 3;

    // Twice the radius, which is the threshold the Recast path uses. Copied rather than re-derived: the
    // whole point of the pass is that a body switching providers drops the same first waypoint.
    const auto ThresholdUu = 2.0 * static_cast<double>(RadiusUu);

    const auto Points = Make_Line(PointCount, SpacingUu);

    const auto OnTop = Get_SkipFirstWaypoint(Points, Points[0], RadiusUu);
    const auto AtThreshold = Get_SkipFirstWaypoint(Points, FVector{ThresholdUu, 0.0, kGroundZ}, RadiusUu);
    const auto PastThreshold = Get_SkipFirstWaypoint(Points, FVector{ThresholdUu + 1.0, 0.0, kGroundZ}, RadiusUu);
    const auto NoRadius = Get_SkipFirstWaypoint(Points, Points[0], 0.0f);
    const auto NegativeRadius = Get_SkipFirstWaypoint(Points, Points[0], -RadiusUu);

    const auto Report = FString::Printf(
        TEXT("of %d: on top %d, at %.1f %d, past it %d, no radius %d, negative radius %d"),
        Points.Num(), OnTop.Num(), ThresholdUu, AtThreshold.Num(), PastThreshold.Num(),
        NoRadius.Num(), NegativeRadius.Num());

    TestEqual(FString::Printf(TEXT("a body standing on the first waypoint drops it [%s]"), *Report),
        OnTop.Num(), Points.Num() - 1);

    TestTrue(FString::Printf(TEXT("and keeps the rest in order [%s]"), *Report),
        OnTop.Num() == Points.Num() - 1 && OnTop[0].Equals(Points[1], kEpsilon));

    // The comparison is not strict, so a body exactly at the threshold is close enough to drop it.
    TestEqual(FString::Printf(TEXT("a body exactly at the threshold drops it too [%s]"), *Report),
        AtThreshold.Num(), Points.Num() - 1);

    TestEqual(FString::Printf(TEXT("a body one unit past the threshold keeps it [%s]"), *Report),
        PastThreshold.Num(), Points.Num());

    // A radius of zero is what a query asks for when the body has no size, and there is no first waypoint
    // to drop for a body that occupies no room.
    TestEqual(FString::Printf(TEXT("a radius of zero disables the pass [%s]"), *Report),
        NoRadius.Num(), Points.Num());

    TestEqual(FString::Printf(TEXT("and so does a negative one [%s]"), *Report),
        NegativeRadius.Num(), Points.Num());

    // Only index zero is ever considered, so a later waypoint the body happens to be standing on stays.
    const auto StandingOnTheSecond = Get_SkipFirstWaypoint(Points, Points[1], RadiusUu);

    TestEqual(TEXT("a body standing on a LATER waypoint drops nothing"),
        StandingOnTheSecond.Num(), Points.Num());

    TestEqual(TEXT("and an empty route answers with an empty one"),
        Get_SkipFirstWaypoint(TArray<FVector>{}, Points[0], RadiusUu).Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_FillAgreesWithItself,
    "CkTests.UnitTests.CkGroundNav.Path.Fill_AgreesWithItself",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_FillAgreesWithItself::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathpostprocess;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the L corridor scene bakes"), Bake_SharedLCorridor(Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(kLCorridorStart, kLCorridorGoal, kCorridorRadiusUu));

    if (NOT TestEqual(TEXT("the L corridor answers a route around its corner"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    auto Funnelled = TArray<FVector>{};

    const auto PulledUu = Get_Funnelled(Result, kCorridorRadiusUu, Funnelled);

    // Nothing is skipped and nothing is offset, so the fill is measuring EXACTLY what the funnel returned
    // and the two numbers are one arithmetic rather than two that could drift.
    const auto Cost = FCk_GroundNav_PathCostParams{};

    const auto Filled = Get_FilledWaypoints(
        Funnelled, *Field, Cost, Make_Agent(kCorridorRadiusUu), kStepHeight);

    if (NOT TestEqual(TEXT("the fill answers with as many waypoints as it was given"),
        Filled.Num(), Funnelled.Num()))
    { return false; }

    const auto LastDistanceUu = Filled.Last()._DistanceFromStart;
    const auto LastCostUu = Filled.Last()._CostFromStart;

    const auto Report = FString::Printf(
        TEXT("%d waypoints, pulled %.6f, integrated %.6f, cost %.6f"),
        Filled.Num(), PulledUu, LastDistanceUu, LastCostUu);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("the integrated distance is the funnel's own return [%s]"), *Report),
        FMath::Abs(LastDistanceUu - PulledUu) <= kEpsilon);

    auto DirectionWrong = 0;
    auto CostWentBackwards = 0;
    auto DistanceWentBackwards = 0;

    for (auto Index = 0; Index < Filled.Num(); ++Index)
    {
        const auto IsLast = Index + 1 == Filled.Num();

        const auto Expected = IsLast
            ? FVector::ZeroVector
            : (Funnelled[Index + 1] - Funnelled[Index]).GetSafeNormal();

        if (NOT Filled[Index]._DirectionToNext.Equals(Expected, kEpsilon))
        { ++DirectionWrong; }

        if (Index == 0)
        { continue; }

        if (Filled[Index]._CostFromStart < Filled[Index - 1]._CostFromStart)
        { ++CostWentBackwards; }

        if (Filled[Index]._DistanceFromStart < Filled[Index - 1]._DistanceFromStart)
        { ++DistanceWentBackwards; }
    }

    TestEqual(FString::Printf(TEXT("every direction points at the next waypoint, and the last at none [%s]"), *Report),
        DirectionWrong, 0);

    TestEqual(FString::Printf(TEXT("the running cost never decreases [%s]"), *Report),
        CostWentBackwards, 0);

    TestEqual(FString::Printf(TEXT("and neither does the running distance [%s]"), *Report),
        DistanceWentBackwards, 0);

    // Every multiplier one and every penalty zero on flat ground: a leg's 3D length is its XY length, so
    // the price of the polyline is the polyline.
    TestTrue(FString::Printf(TEXT("an unpriced route costs exactly its own length [%s]"), *Report),
        FMath::Abs(LastCostUu - LastDistanceUu) <= kEpsilon);

    // The composed pass is the stages in order and nothing else, which is only checkable where no stage
    // in between had anything to do.
    const auto Plan = Get_PathPlan(
        Result, *Field, Make_PostParams(kCorridorRadiusUu, 0.0f, kDistantAgentLocation));

    if (NOT TestEqual(TEXT("the plan carries the stages' own waypoints"), Plan._Waypoints.Num(), Filled.Num()))
    { return true; }

    TestEqual(TEXT("and the status it was built from"), Plan._Status, Result._Status);

    TestEqual(TEXT("and the corridor it was built from"), Plan._PlateCorridor.Num(), Result._PlateCorridor.Num());

    TestTrue(TEXT("and its length is its last waypoint's distance"),
        FMath::Abs(Plan._LengthUu - Plan._Waypoints.Last()._DistanceFromStart) <= kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_MaxMergedTakesTheMaximum,
    "CkTests.UnitTests.CkGroundNav.Path.MaxMerged_TakesTheMaximum",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_MaxMergedTakesTheMaximum::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathpostprocess;

    constexpr auto SharedPlate = 7;
    constexpr auto LeftOnlyPlate = 9;
    constexpr auto RightOnlyPlate = 11;

    constexpr auto LowerMultiplier = 2.0f;
    constexpr auto HigherMultiplier = 3.0f;
    constexpr auto LeftOnlyMultiplier = 5.0f;
    constexpr auto RightOnlyMultiplier = 4.0f;

    auto Left = TMap<int32, float>{};
    Left.Add(SharedPlate, LowerMultiplier);
    Left.Add(LeftOnlyPlate, LeftOnlyMultiplier);

    auto Right = TMap<int32, float>{};
    Right.Add(SharedPlate, HigherMultiplier);
    Right.Add(RightOnlyPlate, RightOnlyMultiplier);

    const auto Tables = TArray<TMap<int32, float>>{Left, Right};

    const auto Merged = Get_MaxMerged(Tables);

    const auto Report = FString::Printf(TEXT("%d entries from %d tables"), Merged.Num(), Tables.Num());

    if (NOT TestEqual(FString::Printf(TEXT("the merge names every plate either table named [%s]"), *Report),
        Merged.Num(), 3))
    { return false; }

    // Greater wins, so overlapping policy has ONE answer whichever order the tables arrived in.
    TestEqual(FString::Printf(TEXT("a plate both tables name takes the greater [%s]"), *Report),
        Merged.FindRef(SharedPlate), HigherMultiplier);

    TestEqual(FString::Printf(TEXT("a plate only the first names keeps its value [%s]"), *Report),
        Merged.FindRef(LeftOnlyPlate), LeftOnlyMultiplier);

    TestEqual(FString::Printf(TEXT("and so does one only the second names [%s]"), *Report),
        Merged.FindRef(RightOnlyPlate), RightOnlyMultiplier);

    const auto Reversed = Get_MaxMerged(TArray<TMap<int32, float>>{Right, Left});

    TestEqual(TEXT("and the order the tables arrived in changes nothing"),
        Reversed.FindRef(SharedPlate), HigherMultiplier);

    TestEqual(TEXT("no tables at all merge to no entries"),
        Get_MaxMerged(TArray<TMap<int32, float>>{}).Num(), 0);

    TestEqual(TEXT("and one table merges to itself"),
        Get_MaxMerged(TArray<TMap<int32, float>>{Left}).Num(), Left.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
