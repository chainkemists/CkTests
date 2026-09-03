// The one funnel, pinned as pure geometry against hand-authored portal sequences and nothing else.
//
// The funnel is the single piece of the query stack that owes an EXACT answer: the flood fill measures
// distances with it and the path search string-pulls with it, so a bend placed a cell out of position
// is wrong twice over, in two subsystems, and neither of them can tell. Every corridor here is small
// enough that its shortest string can be written down by hand, which is what lets the assertions be
// equalities rather than tolerances.
//
// What the file pins: a straight corridor is a straight line, an L bends exactly once and at the inner
// corner, the radius inset pulls the string off that corner, a zero-length interval is an ordinary
// point the path passes through rather than a duplicate waypoint, an interval narrower than twice the
// radius collapses to its midpoint, the to-segment form lands on the nearest point of the target its
// wedge can see, and — over 200 seeded zig-zags nobody can check by hand — the answer always lies
// between the chain through the portal centres and the straight line from start to end.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>
#include <Math/RandomStream.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_funnel
{
    using ck::groundnav::FCk_GroundNav_FunnelPortal;
    using ck::groundnav::Get_StringPull;
    using ck::groundnav::Get_StringPull_ToSegment;

    // Every corridor here is authored on exact integer lines, so the only slack any comparison needs is
    // the float-to-double widening of a stored height.
    constexpr auto kEpsilon = 1.0e-6;

    constexpr auto kNoRadius = 0.0f;

    // The straight corridor: 100 wide, running +X along y = 50, portals every 200 uu.
    const auto kStraightStart = FVector{0.0, 50.0, 0.0};
    const auto kStraightEnd = FVector{1000.0, 50.0, 0.0};
    constexpr auto kStraightLength = 1000.0;

    // The L: the same 100-wide corridor as far as x = 500, then a +Y leg in x [400, 500]. Its inner
    // corner — the one reflex corner of the free space — is where the string has to bend.
    const auto kLStart = FVector{0.0, 50.0, 0.0};
    const auto kLEnd = FVector{450.0, 600.0, 0.0};
    const auto kLCorner = FVector2D{400.0, 100.0};

    constexpr auto kInsetRadius = 20.0f;

    // The narrow interval: 30 uu of room for a body that wants 40, so the interval is a point.
    const auto kNarrowMidpoint = FVector2D{500.0, 35.0};

    // The slit the to-segment case looks through, and the crossing it still owes afterwards.
    const auto kSlitLow = FVector2D{200.0, 80.0};
    const auto kUnobstructedLanding = FVector2D{500.0, 50.0};
    constexpr auto kUnobstructedLength = 500.0;
    constexpr auto kSlitToTargetUu = 300.0;
    constexpr auto kTargetLineX = 500.0;
    constexpr auto kTargetHighY = 100.0;

    constexpr auto kZigZagCorridorCount = 200;
    constexpr auto kZigZagPortalCount = 8;
    constexpr auto kZigZagSeed = 20260902;
    constexpr auto kZigZagSpacingUu = 100.0;
    constexpr auto kZigZagHalfWidthUu = 50.0;
    constexpr auto kZigZagStepUu = 40.0f;

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_XY(
        const FVector& InLocation) -> FVector2D
    {
        return FVector2D{InLocation.X, InLocation.Y};
    }

    auto Get_IsFinite(
        const FVector& InLocation) -> bool
    {
        return FMath::IsFinite(InLocation.X) && FMath::IsFinite(InLocation.Y) && FMath::IsFinite(InLocation.Z);
    }

    auto Get_EveryWaypointIsFinite(
        TConstArrayView<FVector> InWaypoints) -> bool
    {
        for (const auto& Waypoint : InWaypoints)
        {
            if (NOT Get_IsFinite(Waypoint))
            { return false; }
        }

        return true;
    }

    auto Get_HasDuplicateWaypoint(
        TConstArrayView<FVector> InWaypoints) -> bool
    {
        for (auto Index = 1; Index < InWaypoints.Num(); ++Index)
        {
            if (FVector2D::Distance(Get_XY(InWaypoints[Index - 1]), Get_XY(InWaypoints[Index])) <= kEpsilon)
            { return true; }
        }

        return false;
    }

    auto Get_PolylineLengthXY(
        TConstArrayView<FVector2D> InPoints) -> double
    {
        auto Length = 0.0;

        for (auto Index = 1; Index < InPoints.Num(); ++Index)
        { Length += FVector2D::Distance(InPoints[Index - 1], InPoints[Index]); }

        return Length;
    }

    auto Get_WaypointLengthXY(
        TConstArrayView<FVector> InWaypoints) -> double
    {
        auto Length = 0.0;

        for (auto Index = 1; Index < InWaypoints.Num(); ++Index)
        { Length += FVector2D::Distance(Get_XY(InWaypoints[Index - 1]), Get_XY(InWaypoints[Index])); }

        return Length;
    }

    /**
     * The walked length of a to-segment answer, recomputed from the waypoints the call reported.
     *
     * The last leg is added only when the final waypoint is not already the landing point, so this
     * agrees with the reported length whether or not the call lists that point among its waypoints.
     */
    auto Get_WaypointLengthToPointXY(
        TConstArrayView<FVector> InWaypoints,
        const FVector&           InPoint) -> double
    {
        auto Length = Get_WaypointLengthXY(InWaypoints);

        if (InWaypoints.Num() == 0)
        { return Length; }

        const auto FinalLeg = FVector2D::Distance(Get_XY(InWaypoints.Last()), Get_XY(InPoint));

        if (FinalLeg > kEpsilon)
        { Length += FinalLeg; }

        return Length;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Portal(
        const FVector2D& InLeft,
        const FVector2D& InRight) -> FCk_GroundNav_FunnelPortal
    {
        auto Portal = FCk_GroundNav_FunnelPortal{};

        Portal._Left = FVector{InLeft.X, InLeft.Y, 0.0};
        Portal._Right = FVector{InRight.X, InRight.Y, 0.0};

        return Portal;
    }

    /**
     * An interval across a corridor running +X.
     *
     * Unreal's frame is left-handed with Z up, so a body facing +X has +Y on its RIGHT: the LOW-Y end
     * of the interval is the left one. Every portal in this file is built through these two helpers so
     * that convention lives in exactly one place.
     */
    auto Make_EastwardPortal(
        double InLineX,
        double InLowY,
        double InHighY) -> FCk_GroundNav_FunnelPortal
    {
        return Make_Portal(FVector2D{InLineX, InLowY}, FVector2D{InLineX, InHighY});
    }

    /** An interval across a corridor running +Y: facing +Y, the body's left is the HIGH-X end. */
    auto Make_NorthwardPortal(
        double InLineY,
        double InLowX,
        double InHighX) -> FCk_GroundNav_FunnelPortal
    {
        return Make_Portal(FVector2D{InHighX, InLineY}, FVector2D{InLowX, InLineY});
    }

    auto Make_StraightPortals() -> TArray<FCk_GroundNav_FunnelPortal>
    {
        const auto Lines = TArray<double>{200.0, 400.0, 600.0, 800.0};

        auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};

        for (const auto Line : Lines)
        { Portals.Emplace(Make_EastwardPortal(Line, 0.0, 100.0)); }

        return Portals;
    }

    /**
     * The L's portal sequence: two across the +X leg, then two across the +Y leg.
     *
     * The corner square x [400, 500] y [0, 100] belongs to both legs, which is why the last eastward
     * interval and the first northward one need nothing between them.
     */
    auto Make_LCorridorPortals() -> TArray<FCk_GroundNav_FunnelPortal>
    {
        auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};

        Portals.Emplace(Make_EastwardPortal(200.0, 0.0, 100.0));
        Portals.Emplace(Make_EastwardPortal(400.0, 0.0, 100.0));
        Portals.Emplace(Make_NorthwardPortal(200.0, 400.0, 500.0));
        Portals.Emplace(Make_NorthwardPortal(400.0, 400.0, 500.0));

        return Portals;
    }

    auto Get_LCorridorLength() -> double
    {
        return FVector2D::Distance(Get_XY(kLStart), kLCorner) + FVector2D::Distance(kLCorner, Get_XY(kLEnd));
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FZigZagCorridor
    {
        FVector _Start = FVector::ZeroVector;
        FVector _End = FVector::ZeroVector;

        TArray<FCk_GroundNav_FunnelPortal> _Portals;

        // Start, every interval's centre, end: a feasible string through the same intervals in the same
        // order, and therefore an upper bound the shortest one can never exceed.
        TArray<FVector2D> _CentreChain;
    };

    auto Make_ZigZagCorridor(
        int32 InSeed) -> FZigZagCorridor
    {
        auto Stream = FRandomStream{InSeed};

        auto Corridor = FZigZagCorridor{};

        auto CentreY = 0.0;

        Corridor._Start = FVector{0.0, CentreY, 0.0};
        Corridor._CentreChain.Emplace(Get_XY(Corridor._Start));

        for (auto Step = 1; Step <= kZigZagPortalCount; ++Step)
        {
            CentreY += static_cast<double>(Stream.FRandRange(-kZigZagStepUu, kZigZagStepUu));

            const auto LineX = static_cast<double>(Step) * kZigZagSpacingUu;

            Corridor._Portals.Emplace(
                Make_EastwardPortal(LineX, CentreY - kZigZagHalfWidthUu, CentreY + kZigZagHalfWidthUu));

            Corridor._CentreChain.Emplace(FVector2D{LineX, CentreY});
        }

        Corridor._End = FVector{(static_cast<double>(kZigZagPortalCount) + 1.0) * kZigZagSpacingUu, CentreY, 0.0};
        Corridor._CentreChain.Emplace(Get_XY(Corridor._End));

        return Corridor;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_StraightCorridorIsTwoWaypoints,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_StraightCorridorIsTwoWaypoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_StraightCorridorIsTwoWaypoints::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    const auto Portals = Make_StraightPortals();

    auto Waypoints = TArray<FVector>{};

    const auto Length = Get_StringPull(kStraightStart, kStraightEnd, Portals, kNoRadius, Waypoints);

    const auto Report = FString::Printf(
        TEXT("portals %d, waypoints %d, length %.9f"), Portals.Num(), Waypoints.Num(), Length);

    ck::groundnav::Display(TEXT("{}"), Report);

    // Four intervals the straight line passes cleanly through, and not one of them is a corner. The
    // waypoint count is the assertion that matters: a funnel emitting portal crossings instead of bends
    // reports this same LENGTH and hands its consumer a path with four redundant turns in it.
    if (NOT TestEqual(FString::Printf(TEXT("a straight corridor is start and end only [%s]"), *Report),
        Waypoints.Num(), 2))
    { return false; }

    TestTrue(FString::Printf(TEXT("the first waypoint is the start [%s]"), *Report),
        Waypoints[0].Equals(kStraightStart, kEpsilon));

    TestTrue(FString::Printf(TEXT("the last waypoint is the end [%s]"), *Report),
        Waypoints.Last().Equals(kStraightEnd, kEpsilon));

    TestTrue(FString::Printf(TEXT("the length is the straight line [%s]"), *Report),
        FMath::Abs(Length - kStraightLength) <= kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_LShapedCorridorIsThreeWaypoints,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_LShapedCorridorIsThreeWaypoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_LShapedCorridorIsThreeWaypoints::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    const auto Portals = Make_LCorridorPortals();

    auto Waypoints = TArray<FVector>{};

    const auto Length = Get_StringPull(kLStart, kLEnd, Portals, kNoRadius, Waypoints);

    const auto ExpectedLength = Get_LCorridorLength();

    const auto Report = FString::Printf(
        TEXT("waypoints %d, length %.9f, expected %.9f"), Waypoints.Num(), Length, ExpectedLength);

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestEqual(FString::Printf(TEXT("the L bends exactly once [%s]"), *Report), Waypoints.Num(), 3))
    { return false; }

    TestTrue(FString::Printf(TEXT("the first waypoint is the start [%s]"), *Report),
        Waypoints[0].Equals(kLStart, kEpsilon));

    // The inner corner is the only reflex corner of this free space, so it is the only place a shortest
    // string can bend. Asserted as a POSITION and not merely as a count: a bend placed a little way into
    // either leg costs almost nothing in length and is a wall clip for everything that follows it.
    TestTrue(FString::Printf(TEXT("the middle waypoint is the inner corner [%s]"), *Report),
        FVector2D::Distance(Get_XY(Waypoints[1]), kLCorner) <= kEpsilon);

    TestTrue(FString::Printf(TEXT("the last waypoint is the end [%s]"), *Report),
        Waypoints.Last().Equals(kLEnd, kEpsilon));

    TestTrue(FString::Printf(TEXT("the length is the two legs [%s]"), *Report),
        FMath::Abs(Length - ExpectedLength) <= kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_RadiusInsetPullsOffTheCorner,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_RadiusInsetPullsOffTheCorner",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_RadiusInsetPullsOffTheCorner::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    const auto Portals = Make_LCorridorPortals();

    auto BareWaypoints = TArray<FVector>{};
    auto InsetWaypoints = TArray<FVector>{};

    const auto BareLength = Get_StringPull(kLStart, kLEnd, Portals, kNoRadius, BareWaypoints);
    const auto InsetLength = Get_StringPull(kLStart, kLEnd, Portals, kInsetRadius, InsetWaypoints);

    auto ClosestApproachUu = TNumericLimits<double>::Max();

    for (auto Index = 1; Index < InsetWaypoints.Num() - 1; ++Index)
    {
        ClosestApproachUu = FMath::Min(
            ClosestApproachUu, FVector2D::Distance(Get_XY(InsetWaypoints[Index]), kLCorner));
    }

    const auto Report = FString::Printf(
        TEXT("bare waypoints %d length %.9f, inset waypoints %d length %.9f, closest approach %.9f"),
        BareWaypoints.Num(), BareLength, InsetWaypoints.Num(), InsetLength, ClosestApproachUu);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("the inset path is finite [%s]"), *Report),
        Get_EveryWaypointIsFinite(InsetWaypoints));

    if (NOT TestTrue(FString::Printf(TEXT("the inset path still bends [%s]"), *Report),
        InsetWaypoints.Num() >= 3))
    { return false; }

    // Shrinking every interval shrinks the set of feasible strings, so the inset answer can never be
    // shorter — and here it is strictly longer, which is the whole content of the name: the string was
    // pulled off a corner it was previously allowed to touch.
    TestTrue(FString::Printf(TEXT("the inset path is longer than the bare one [%s]"), *Report),
        InsetLength > BareLength + kEpsilon);

    TestTrue(FString::Printf(TEXT("no inset waypoint sits on the bare corner [%s]"), *Report),
        ClosestApproachUu > kEpsilon);

    // The corner is the tightest point on the route; a body of this radius bending anywhere nearer than
    // its own radius is inside the wall the inset exists to hold it off.
    TestTrue(FString::Printf(TEXT("every bend keeps the radius clear of the corner [%s]"), *Report),
        ClosestApproachUu >= static_cast<double>(kInsetRadius) - kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_DegeneratePortalsDoNotDuplicate,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_DegeneratePortalsDoNotDuplicate",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_DegeneratePortalsDoNotDuplicate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    // A zero-length interval sitting on the straight line the path already takes. It constrains nothing,
    // so the answer must be identical to the corridor without it: no extra waypoint, no repeated one,
    // and no NaN out of normalizing a zero-length interval.
    const auto Degenerate = FVector2D{500.0, 50.0};

    auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};

    Portals.Emplace(Make_EastwardPortal(200.0, 0.0, 100.0));
    Portals.Emplace(Make_EastwardPortal(400.0, 0.0, 100.0));
    Portals.Emplace(Make_Portal(Degenerate, Degenerate));
    Portals.Emplace(Make_EastwardPortal(600.0, 0.0, 100.0));
    Portals.Emplace(Make_EastwardPortal(800.0, 0.0, 100.0));

    auto Waypoints = TArray<FVector>{};

    const auto Length = Get_StringPull(kStraightStart, kStraightEnd, Portals, kNoRadius, Waypoints);

    const auto Report = FString::Printf(
        TEXT("portals %d, waypoints %d, length %.9f"), Portals.Num(), Waypoints.Num(), Length);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("every waypoint is finite [%s]"), *Report),
        Get_EveryWaypointIsFinite(Waypoints));

    TestFalse(FString::Printf(TEXT("no waypoint repeats its predecessor [%s]"), *Report),
        Get_HasDuplicateWaypoint(Waypoints));

    TestEqual(FString::Printf(TEXT("the degenerate interval adds no waypoint [%s]"), *Report),
        Waypoints.Num(), 2);

    TestTrue(FString::Printf(TEXT("the length is the straight line [%s]"), *Report),
        FMath::Abs(Length - kStraightLength) <= kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_NarrowPortalCollapsesToItsMidpoint,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_NarrowPortalCollapsesToItsMidpoint",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_NarrowPortalCollapsesToItsMidpoint::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    // 30 uu of interval for a body that wants 40: insetting from both ends would invert it, so the
    // contract collapses it to its midpoint and the string is pinned through that point.
    auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};

    Portals.Emplace(Make_EastwardPortal(500.0, 20.0, 50.0));

    auto Waypoints = TArray<FVector>{};

    const auto Length = Get_StringPull(kStraightStart, kStraightEnd, Portals, kInsetRadius, Waypoints);

    const auto ExpectedLength =
        FVector2D::Distance(Get_XY(kStraightStart), kNarrowMidpoint) +
        FVector2D::Distance(kNarrowMidpoint, Get_XY(kStraightEnd));

    const auto Report = FString::Printf(
        TEXT("waypoints %d, length %.9f, expected %.9f"), Waypoints.Num(), Length, ExpectedLength);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("every waypoint is finite [%s]"), *Report),
        Get_EveryWaypointIsFinite(Waypoints));

    TestTrue(FString::Printf(TEXT("the path is pinned through the midpoint [%s]"), *Report),
        FMath::Abs(Length - ExpectedLength) <= kEpsilon);

    if (NOT TestEqual(FString::Printf(TEXT("the collapsed interval is one bend [%s]"), *Report),
        Waypoints.Num(), 3))
    { return false; }

    TestTrue(FString::Printf(TEXT("the bend is the interval's midpoint [%s]"), *Report),
        FVector2D::Distance(Get_XY(Waypoints[1]), kNarrowMidpoint) <= kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_ToSegmentReachesTheNearestVisiblePoint,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_ToSegmentReachesTheNearestVisiblePoint",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_ToSegmentReachesTheNearestVisiblePoint::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    const auto Target = Make_EastwardPortal(kTargetLineX, 0.0, kTargetHighY);

    // Nothing between the apex and the target: the wedge is everything, so the answer is the plain
    // nearest point of the interval and the string is a straight line to it.
    {
        const auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};

        auto Point = FVector::ZeroVector;
        auto Waypoints = TArray<FVector>{};

        const auto Length = Get_StringPull_ToSegment(kStraightStart, Portals, Target, kNoRadius, Point, Waypoints);

        const auto Report = FString::Printf(
            TEXT("unobstructed: waypoints %d, point (%.6f, %.6f), length %.9f"),
            Waypoints.Num(), Point.X, Point.Y, Length);

        ck::groundnav::Display(TEXT("{}"), Report);

        TestTrue(FString::Printf(TEXT("the answer is finite [%s]"), *Report),
            Get_EveryWaypointIsFinite(Waypoints) && Get_IsFinite(Point));

        TestTrue(FString::Printf(TEXT("the landing point is the foot of the perpendicular [%s]"), *Report),
            FVector2D::Distance(Get_XY(Point), kUnobstructedLanding) <= kEpsilon);

        TestTrue(FString::Printf(TEXT("the length is the perpendicular distance [%s]"), *Report),
            FMath::Abs(Length - kUnobstructedLength) <= kEpsilon);
    }

    // One slit above the start line. The wedge it admits, carried out to the target, clears the target's
    // far end entirely, so the nearest point the apex can SEE is not the nearest point there is — which
    // is the whole difference between this call and a closest-point-on-segment.
    {
        auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};

        Portals.Emplace(Make_EastwardPortal(200.0, 80.0, 100.0));

        auto Point = FVector::ZeroVector;
        auto Waypoints = TArray<FVector>{};

        const auto Length = Get_StringPull_ToSegment(kStraightStart, Portals, Target, kNoRadius, Point, Waypoints);

        const auto Recomputed = Get_WaypointLengthToPointXY(Waypoints, Point);
        const auto SlitLegUu = FVector2D::Distance(Get_XY(kStraightStart), kSlitLow);

        const auto Report = FString::Printf(
            TEXT("through the slit: waypoints %d, point (%.6f, %.6f), length %.9f, recomputed %.9f"),
            Waypoints.Num(), Point.X, Point.Y, Length, Recomputed);

        ck::groundnav::Display(TEXT("{}"), Report);

        TestTrue(FString::Printf(TEXT("the answer is finite [%s]"), *Report),
            Get_EveryWaypointIsFinite(Waypoints) && Get_IsFinite(Point));

        // The reported length is the length of the reported path, and not a number arrived at some other
        // way: a flood fill that settles on one and walks the other is measuring a route nobody takes.
        TestTrue(FString::Printf(TEXT("the length is the polyline it reported [%s]"), *Report),
            FMath::Abs(Length - Recomputed) <= kEpsilon);

        TestTrue(FString::Printf(TEXT("the landing point is on the target interval [%s]"), *Report),
            FMath::Abs(Point.X - kTargetLineX) <= kEpsilon &&
            Point.Y >= -kEpsilon && Point.Y <= kTargetHighY + kEpsilon);

        // The wedge cannot reach below the slit's own lower end, so neither can the answer.
        TestTrue(FString::Printf(TEXT("the landing point is above the slit line [%s]"), *Report),
            Point.Y >= kSlitLow.Y - kEpsilon);

        if (TestTrue(FString::Printf(TEXT("the path bends at the slit [%s]"), *Report), Waypoints.Num() >= 2))
        {
            TestTrue(FString::Printf(TEXT("the bend is the slit's lower end [%s]"), *Report),
                FVector2D::Distance(Get_XY(Waypoints[1]), kSlitLow) <= kEpsilon);
        }

        // Through the slit and then across to the target line: no route to the interval is shorter.
        TestTrue(FString::Printf(TEXT("the length is at least the slit leg plus the crossing [%s]"), *Report),
            Length >= SlitLegUu + kSlitToTargetUu - kEpsilon);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_LengthNeverExceedsPortalCentreChain,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_LengthNeverExceedsPortalCentreChain",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_LengthNeverExceedsPortalCentreChain::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnel;

    auto TooLong = 0;
    auto TooShort = 0;
    auto NotFinite = 0;
    auto Duplicated = 0;

    auto WorstSlackUu = 0.0;

    for (auto CorridorIndex = 0; CorridorIndex < kZigZagCorridorCount; ++CorridorIndex)
    {
        const auto Corridor = Make_ZigZagCorridor(kZigZagSeed + CorridorIndex);

        auto Waypoints = TArray<FVector>{};

        const auto Length =
            Get_StringPull(Corridor._Start, Corridor._End, Corridor._Portals, kNoRadius, Waypoints);

        const auto CentreChainUu = Get_PolylineLengthXY(Corridor._CentreChain);
        const auto StraightUu = FVector2D::Distance(Get_XY(Corridor._Start), Get_XY(Corridor._End));

        // The chain through the interval centres visits one point of every interval in order, so it is a
        // feasible string and the shortest one cannot be longer than it. The straight line ignores the
        // intervals entirely, so nothing constrained by them can be shorter than it. Between those two
        // numbers is the only place a correct answer can be, for every corridor there is.
        if (Length > CentreChainUu + kEpsilon)
        { ++TooLong; }

        if (Length < StraightUu - kEpsilon)
        { ++TooShort; }

        if (NOT Get_EveryWaypointIsFinite(Waypoints))
        { ++NotFinite; }

        if (Get_HasDuplicateWaypoint(Waypoints))
        { ++Duplicated; }

        WorstSlackUu = FMath::Max(WorstSlackUu, Length - CentreChainUu);
    }

    const auto Report = FString::Printf(
        TEXT("corridors %d, over the centre chain %d, under the straight line %d, non-finite %d, duplicated %d, worst slack %.9f"),
        kZigZagCorridorCount, TooLong, TooShort, NotFinite, Duplicated, WorstSlackUu);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("no corridor's string is longer than its portal centre chain [%s]"), *Report),
        TooLong, 0);

    TestEqual(FString::Printf(TEXT("no corridor's string is shorter than the straight line [%s]"), *Report),
        TooShort, 0);

    TestEqual(FString::Printf(TEXT("no corridor produced a non-finite waypoint [%s]"), *Report),
        NotFinite, 0);

    TestEqual(FString::Printf(TEXT("no corridor repeated a waypoint [%s]"), *Report),
        Duplicated, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
