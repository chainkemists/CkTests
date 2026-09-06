// The line-of-sight shortcut: what it is allowed to remove from a plan, and what it may never touch.
//
// The stage exists because a plate corridor is CHOSEN on the midpoint polyline and only afterwards
// string-pulled, so on an open floor cut into rectangles the funnel is regularly handed a channel that
// does not contain the straight line. What comes out is a bend standing in open floor with no wall
// anywhere near it, which the corner offset then pushes a further radius away from where the body
// wanted to go. A chord across the union of the corridor's own plates recovers the straight line
// wherever the wrongly-chosen chain still contains it; the claims below are what that chord may cost.
//
// Four things are asserted, and they are deliberately not one thing. The route over the gym's four
// pillars must come back with no interior waypoint standing in open floor - that is the defect. Every
// endpoint an authored link put on the route must survive, exactly where the record put it - a link is
// a place a body passes THROUGH, and a chord that spanned one would walk it off the link. The plan's
// own price must never rise - a chord that cut the corner of cheap ground into dear ground would be a
// shortcut the search never priced. And running the pass over its own output must change nothing, or
// the answer depends on how many times it was asked.
//
// The endpoint claim is made TWICE, from opposite sides, because the barrier route alone cannot fail
// it: there every chord that would span an endpoint crosses the barrier wall, so the raycast refuses
// it on geometry and the pinned list is never consulted. That test therefore states the plan-level
// claim - the stamp survives every stage - and Shortcut_PinnedWaypointSurvivesAClearChord states the
// rule itself over a chord the geometry ACCEPTS: dropped with nothing pinned, kept with the middle
// point pinned, the same route and the same field either way.
//
// The price and idempotence claims are likewise made twice, and for the same kind of reason: on flat
// ground at a uniform table both of them reduce to the triangle inequality, so a pass that got the
// pricing wrong would satisfy them anyway. Shortcut_CostNeverRisesWhenAnEndpointStandsOnDearGround
// restates them where one END of a chord stands on marked-up ground - the case a scene that prices
// ground the route AVOIDS structurally cannot reach - and Shortcut_CostNeverRisesUnderTheSlopePenalty
// restates the price claim where the route climbs, which is the one term the chord's own raycast
// cannot see.
//
// PINS THIS STAGE MUST LEAVE GREEN. FCkTest_GroundNav_Path_LCorridorThreeWaypointsAllClearOfBoundary
// (Test_GroundNav_PathPostProcess.cpp) is the over-shortcutting regression pin: the L corridor's one
// bend is a REAL corner, the shortest string through that corridor genuinely bends there, and a
// shortcut that collapsed it to two waypoints has cut through a wall. A red there is a bug in the
// stage, never a pin to re-measure. FCkTest_GroundNav_PathLinkMetadata_MetadataSurvivesSkipFirstAndCornerOffset
// asserts the barrier route keeps at least three points, which a shortcut across that route could
// break; the link pin below covers the same geometry from this side.

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"
#include "CkGroundNav/Query/CkGroundNav_QueryTypes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Boundary.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"
#include "Test_GroundNav_ReferencePaths.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathshortcut
{
    using ck::groundnav::ECk_GroundNav_LinkWaypointRole;
    using ck::groundnav::FCk_GroundNav_ClosestBoundaryQuery;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_PathCostParams;
    using ck::groundnav::FCk_GroundNav_PathPlan;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::Get_ClosestBoundary;
    using ck::groundnav::Get_CornerOffset;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_Funnelled;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_Path;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Get_Shortcut;
    using ck::groundnav::Get_SkipFirstWaypoint;
    using ck::groundnav::Get_SurfaceRaycast;
    using ck::groundnav::Get_WithLinkEndpointsEmitted;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_SharedFourPillarSlabScene;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kFourPillarAgentRadiusUu;
    using ck_test_groundnav_queryfixtures::kFourPillarEastPost;
    using ck_test_groundnav_queryfixtures::kFourPillarWestPost;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    using ck_test_groundnav_referencepaths::kEpsilon;

    // ----------------------------------------------------------------------------------------------------------------

    // The pass off, mirroring _CornerOffsetK = 0: zero is not a span of zero, it is no pass at all.
    constexpr auto kShortcutOff = 0;

    // The pass with no span cap, which is what the recommendation ships as the default: at the handful
    // of waypoints a plan carries, the quadratic worst case is small enough to always take the best
    // answer available rather than the first one within a cap.
    constexpr auto kShortcutUnbounded = MAX_int32;

    // The corner offset the cost model ships with. Stated here because the allowance the false-corner
    // pin measures against is that offset plus the radius it multiplies.
    constexpr auto kCornerOffsetK = 1.0f;

    // Far enough that no skip-first threshold reaches it, so every waypoint the passes made is kept and
    // a count is a statement about the shortcut rather than about where a body happens to stand.
    const auto kDistantAgentLocation = FVector{-9000.0, -9000.0, kGroundZ};

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Make_Cost(
        int32 InShortcutSpanCap) -> FCk_GroundNav_PathCostParams
    {
        auto Cost = FCk_GroundNav_PathCostParams{};

        Cost._CornerOffsetK = kCornerOffsetK;
        Cost._ShortcutSpanCap = InShortcutSpanCap;

        return Cost;
    }

    auto Make_PathQuery(
        const FVector&                      InStart,
        const FVector&                      InGoal,
        float                               InRadiusUu,
        const FCk_GroundNav_PathCostParams& InCost) -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(InRadiusUu);
        Query._Cost = InCost;

        return Query;
    }

    auto Make_PostParams(
        float                               InRadiusUu,
        const FCk_GroundNav_PathCostParams& InCost,
        const FVector&                      InAgentLocation) -> FCk_GroundNav_PathPostParams
    {
        auto Params = FCk_GroundNav_PathPostParams{};

        Params._Agent = Make_Agent(InRadiusUu);
        Params._VerticalToleranceUu = kStepHeight;
        Params._AgentLocation = InAgentLocation;
        Params._Cost = InCost;

        return Params;
    }

    /** The points an authored link put on the route, collected the way the post-process collects them. */
    auto Get_PinnedWaypoints(
        const FCk_GroundNav_PathResult& InResult) -> TArray<FVector>
    {
        auto Pinned = TArray<FVector>{};

        for (const auto& Portal : InResult._FunnelPortals)
        {
            if (Portal._LinkIndex == INDEX_NONE)
            { continue; }

            Pinned.Emplace(Portal._Left);
        }

        return Pinned;
    }

    /**
     * The polyline the plan actually hands the shortcut: funnel, link endpoints, corner offset, and
     * nothing after (CkGroundNav_PathPostProcess.cpp:726-752 runs the pass here, ahead of skip-first).
     *
     * The offset comes FIRST there for a measured reason, and that is why this is the input worth
     * feeding the pass by hand: the funnel's apexes hug their walls at one radius, a chord between two
     * of them is refused by the radius-aware ray, and the pass run bare over the funnel's own output
     * removes nothing at all on the four-pillar route. Offset first and the false corner drops.
     */
    auto Get_PreShortcutLocations(
        const FCk_GroundNav_PathResult& InResult,
        const FCk_GroundNav_Field&      InField,
        float                           InRadiusUu) -> TArray<FVector>
    {
        auto Funnelled = TArray<FVector>{};
        Get_Funnelled(InResult, InRadiusUu, Funnelled);

        const auto WithLinks = Get_WithLinkEndpointsEmitted(Funnelled, InResult);

        return Get_CornerOffset(
            WithLinks,
            Get_PinnedWaypoints(InResult),
            InField,
            kCornerOffsetK * InRadiusUu,
            Make_Agent(InRadiusUu),
            kStepHeight);
    }

    /**
     * The plan's stages run by hand with the shortcut absent, which is the plan as it stood before this
     * stage existed.
     *
     * Deliberately usable only where the pass is OFF. Where it is on, the stage's position in the chain
     * is the production's business, and a test that re-stated it would pin the wiring rather than the
     * behaviour.
     */
    auto Get_StagedLocations(
        const FCk_GroundNav_PathResult& InResult,
        const FCk_GroundNav_Field&      InField,
        float                           InRadiusUu,
        const FVector&                  InAgentLocation) -> TArray<FVector>
    {
        return Get_SkipFirstWaypoint(
            Get_PreShortcutLocations(InResult, InField, InRadiusUu), InAgentLocation, InRadiusUu);
    }

    auto Get_WaypointReport(
        TConstArrayView<FVector> InWaypoints) -> FString
    {
        auto Report = FString::Printf(TEXT("%d waypoints"), InWaypoints.Num());

        for (const auto& Waypoint : InWaypoints)
        { Report += FString::Printf(TEXT(" (%.1f, %.1f)"), Waypoint.X, Waypoint.Y); }

        return Report;
    }

    auto Get_PlanReport(
        const FCk_GroundNav_PathPlan& InPlan) -> FString
    {
        auto Locations = TArray<FVector>{};
        Locations.Reserve(InPlan._Waypoints.Num());

        for (const auto& Waypoint : InPlan._Waypoints)
        { Locations.Emplace(Waypoint._Location); }

        return FString::Printf(
            TEXT("%s, length %.2f, cost %.2f"),
            *Get_WaypointReport(Locations), InPlan._LengthUu,
            InPlan._Waypoints.IsEmpty() ? 0.0 : InPlan._Waypoints.Last()._CostFromStart);
    }

    /** A pin asserts once it holds a number; until then it says so on the log and asserts nothing. */
    auto Do_CheckPin(
        FAutomationTestBase& InTest,
        const TCHAR*         InWhat,
        int32                InPinned,
        int32                InMeasured) -> void
    {
        if (InPinned == INDEX_NONE)
        {
            ck::groundnav::Display(TEXT("{}"),
                FString::Printf(TEXT("[SHORTCUT-BUDGET] %s is unpinned; measured %d"), InWhat, InMeasured));

            return;
        }

        InTest.TestEqual(FString{InWhat}, InMeasured, InPinned);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_FourPillarRouteHasNoFalseCorners,
    "CkTests.UnitTests.CkGroundNav.Path.FourPillar_RouteHasNoFalseCorners",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_FourPillarRouteHasNoFalseCorners::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;

    // Wide enough to reach the pillar a real corner bends around, and far short of the slab's own rim,
    // so a probe that answers is answering about an obstacle and not about the edge of the world.
    constexpr auto kProbeRadiusUu = 600.0f;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(
        kFourPillarWestPost, kFourPillarEastPost, kFourPillarAgentRadiusUu,
        Make_Cost(kShortcutUnbounded)));

    if (NOT TestEqual(TEXT("the slab answers a west-east crossing"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto Plan = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutUnbounded), kDistantAgentLocation));

    if (NOT TestTrue(TEXT("and the plan carries the two ends at least"), Plan._Waypoints.Num() >= 2))
    { return false; }

    // What a REAL corner may stand at. The funnel already inset by a radius, and the corner offset then
    // pushed the point a further _CornerOffsetK radii into the free space, so a waypoint that bent
    // around an actual obstacle silhouette is at most that far from it - plus one cell for the lattice
    // the boundary runs are quantised onto. Anything further away bent around nothing.
    const auto AllowanceUu = static_cast<double>(kFourPillarAgentRadiusUu) +
        (static_cast<double>(kCornerOffsetK) * static_cast<double>(kFourPillarAgentRadiusUu)) +
        static_cast<double>(kCellSize);

    auto StandingInOpenFloor = 0;
    auto NoWallInRange = 0;
    auto FurthestUu = 0.0;

    for (auto Index = 1; Index < Plan._Waypoints.Num() - 1; ++Index)
    {
        auto Query = FCk_GroundNav_ClosestBoundaryQuery{};

        Query._Location = Plan._Waypoints[Index]._Location;
        Query._MaxRadiusUu = kProbeRadiusUu;
        Query._VerticalWindowUu = kStepHeight;

        const auto Boundary = Get_ClosestBoundary(*Field, Query);

        if (NOT Boundary.Get_IsSuccess())
        {
            ++NoWallInRange;

            continue;
        }

        const auto DistanceUu = static_cast<double>(Boundary._DistanceUu);

        FurthestUu = FMath::Max(FurthestUu, DistanceUu);

        if (DistanceUu > AllowanceUu)
        { ++StandingInOpenFloor; }
    }

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT] %s, interior %d, furthest wall %.2f, allowance %.2f"),
        *Get_PlanReport(Plan), FMath::Max(0, Plan._Waypoints.Num() - 2), FurthestUu, AllowanceUu);

    ck::groundnav::Display(TEXT("{}"), Report);

    // No wall inside a 600 uu probe is the strongest statement a false corner can make about itself:
    // the waypoint is not merely far from what it bent around, there is nothing there to have bent
    // around at all.
    TestEqual(FString::Printf(TEXT("no interior waypoint stands with no wall in reach [%s]"), *Report),
        NoWallInRange, 0);

    TestEqual(FString::Printf(TEXT("and every one of them is a corner of something real [%s]"), *Report),
        StandingInOpenFloor, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_pathshortcut_barrier
{
    using namespace ck_test_groundnav_pathshortcut;

    // The barrier the link suite states its own claims over, restated here rather than shared: the two
    // files make different claims about the same geometry, and Test_GroundNav_PathLinkMetadata.cpp
    // restated it from the link search for exactly that reason.
    constexpr auto kBarrierFreeMinX = 100.0;
    constexpr auto kBarrierFreeMaxX = 700.0;
    constexpr auto kBarrierFreeMinY = 100.0;
    constexpr auto kBarrierFreeMaxY = 700.0;

    constexpr auto kBarrierMinX = 350.0;
    constexpr auto kBarrierMaxX = 450.0;
    constexpr auto kBarrierTopY = 500.0;

    const auto kBarrierStart = FVector{200.0, 200.0, kGroundZ};
    const auto kBarrierGoal = FVector{600.0, 200.0, kGroundZ};

    // Off the line between the two ends, so the string BENDS at both of them - which is what makes them
    // waypoints a shortcut has something to gain by removing.
    const auto kBentLinkEntry = FVector{300.0, 350.0, kGroundZ};
    const auto kBentLinkExit = FVector{500.0, 350.0, kGroundZ};

    constexpr auto kLinkId = 7;

    constexpr auto kAgentRadiusUu = 10.0f;

    constexpr auto kOneEntryAndOneExit = 2;

    auto Make_BarrierScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}});

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{2000.0, kBarrierFreeMinY, 300.0}});
        Boxes.Emplace(FBox{FVector{-400.0, kBarrierFreeMaxY, 0.0}, FVector{2000.0, 2000.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{-400.0, kBarrierFreeMinY, 0.0},
            FVector{kBarrierFreeMinX, kBarrierFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kBarrierFreeMaxX, kBarrierFreeMinY, 0.0},
            FVector{2000.0, kBarrierFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kBarrierMinX, kBarrierFreeMinY, 0.0},
            FVector{kBarrierMaxX, kBarrierTopY, 300.0}});

        return Boxes;
    }

    auto Make_LinkRecord(
        int32          InId,
        const FVector& InStart,
        const FVector& InEnd) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};

        Record.Set_CostMultiplierForward(1.0f);
        Record.Set_CostMultiplierBackward(1.0f);

        return Record;
    }

    auto Bake_Barrier(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_FieldPtr&                 OutField) -> bool
    {
        auto Params = Make_FlatParams();
        Params._Links = InLinks;

        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_BarrierScene(), Params, *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    auto Get_StampedIndices(
        const FCk_GroundNav_PathPlan& InPlan) -> TArray<int32>
    {
        auto Stamped = TArray<int32>{};

        for (auto Index = 0; Index < InPlan._Waypoints.Num(); ++Index)
        {
            if (InPlan._Waypoints[Index]._LinkRole != ECk_GroundNav_LinkWaypointRole::None)
            { Stamped.Emplace(Index); }
        }

        return Stamped;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutKeepsEveryLinkEndpoint,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_KeepsEveryLinkEndpoint",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutKeepsEveryLinkEndpoint::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;
    using namespace ck_test_groundnav_pathshortcut_barrier;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with one link across it"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kBentLinkEntry, kBentLinkExit)}, Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(
        kBarrierStart, kBarrierGoal, kAgentRadiusUu, Make_Cost(kShortcutUnbounded)));

    if (NOT TestEqual(TEXT("and the search takes the link"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto Plan = Get_PathPlan(Result, *Field, Make_PostParams(
        kAgentRadiusUu, Make_Cost(kShortcutUnbounded), kDistantAgentLocation));

    const auto Report = FString::Printf(TEXT("[SHORTCUT] %s"), *Get_PlanReport(Plan));

    ck::groundnav::Display(TEXT("{}"), Report);

    const auto Stamped = Get_StampedIndices(Plan);

    // WHAT THIS PROVES, STATED HONESTLY: the link stamp survives the WHOLE plan - funnel, link
    // endpoints, corner offset, shortcut, skip-first and fill - and comes out one entry followed by one
    // exit, each still exactly where the record put it. It is a plan-level claim, not a test of the
    // pinning rule: on THIS geometry every chord that would span an endpoint crosses the barrier wall,
    // so the radius-aware raycast refuses it on geometry alone and the pass could ignore its pinned
    // list entirely without going red here. Shortcut_PinnedWaypointSurvivesAClearChord below is the
    // falsifiable half - a chord the geometry ACCEPTS, dropped when nothing is pinned and kept when the
    // middle point is.
    if (NOT TestEqual(FString::Printf(TEXT("the route still carries one entry and one exit [%s]"), *Report),
        Stamped.Num(), kOneEntryAndOneExit))
    { return false; }

    const auto& Entry = Plan._Waypoints[Stamped[0]];
    const auto& Exit = Plan._Waypoints[Stamped[1]];

    // Exactly, not within a tolerance: both points are copies of the one resolved endpoint the record
    // produced, and the stamp downstream recognises an endpoint by that same exact equality.
    TestTrue(FString::Printf(TEXT("the entry stands exactly where the record put it [%s]"), *Report),
        Entry._Location == kBentLinkEntry);

    TestTrue(FString::Printf(TEXT("and so does the exit [%s]"), *Report),
        Exit._Location == kBentLinkExit);

    TestTrue(FString::Printf(TEXT("with the entry first and the exit next [%s]"), *Report),
        Entry._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry &&
        Exit._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit &&
        Stamped[1] == Stamped[0] + 1);

    // The same route with the pass off, which is the control: the pair the pass had to preserve is the
    // pair that was there to preserve, rather than one the shortcut happened to reintroduce.
    const auto Unshortcut = Get_PathPlan(Result, *Field, Make_PostParams(
        kAgentRadiusUu, Make_Cost(kShortcutOff), kDistantAgentLocation));

    const auto UnshortcutStamped = Get_StampedIndices(Unshortcut);

    if (NOT TestEqual(TEXT("the same pair is there with the pass off"),
        UnshortcutStamped.Num(), kOneEntryAndOneExit))
    { return true; }

    TestTrue(TEXT("and stands in the same two places"),
        Unshortcut._Waypoints[UnshortcutStamped[0]]._Location == Entry._Location &&
        Unshortcut._Waypoints[UnshortcutStamped[1]]._Location == Exit._Location);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_pathshortcut_clearlane
{
    using namespace ck_test_groundnav_pathshortcut;

    // Three points of a lane across the slab's northern half. Chosen so the geometry refuses NOTHING:
    // the northernmost pillar reaches Y 195 and the slab's rim stands at Y 1200, so all three points
    // and the chord between the outer two sit on several hundred uu of open floor in every direction.
    // That is the whole point - where a chord is accepted, whether the middle point survives is a
    // decision the pinned list makes, and the pass has nowhere to hide behind a wall.
    const auto kLaneWest = FVector{-1000.0, 800.0, kGroundZ};
    const auto kLaneBend = FVector{0.0, 900.0, kGroundZ};
    const auto kLaneEast = FVector{1000.0, 800.0, kGroundZ};

    // A and C, the middle point gone.
    constexpr auto kTheTwoEnds = 2;

    // A, B and C, the span split at the pinned point into A-B and B-C.
    constexpr auto kBothSpansKept = 3;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutPinnedWaypointSurvivesAClearChord,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_PinnedWaypointSurvivesAClearChord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutPinnedWaypointSurvivesAClearChord::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;
    using namespace ck_test_groundnav_pathshortcut_clearlane;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Cost = Make_Cost(kShortcutUnbounded);
    const auto Agent = Make_Agent(kFourPillarAgentRadiusUu);

    // The chord proved CLEAR before anything is asked of the pass. Without this the drop below could
    // pass because the geometry refused nothing, and the survival below it would be a statement about a
    // wall rather than about the pinned list.
    auto ChordQuery = FCk_GroundNav_RaycastQuery{};

    ChordQuery._Start = kLaneWest;
    ChordQuery._End = kLaneEast;
    ChordQuery._StartVerticalToleranceUu = kStepHeight;
    ChordQuery._Agent = Agent;

    if (NOT TestTrue(TEXT("the straight line from A to C is walkable ground throughout"),
        Get_SurfaceRaycast(*Field, ChordQuery).Get_IsClear()))
    { return false; }

    const auto Route = TArray<FVector>{kLaneWest, kLaneBend, kLaneEast};

    const auto NothingPinned = TArray<FVector>{};
    const auto MiddlePinned = TArray<FVector>{kLaneBend};

    // Nothing pinned. B stands in open floor with an accepted chord across it, so the pass has both the
    // opportunity and the permission to remove it - and a pass that kept it here is not shortcutting.
    const auto Unpinned = Get_Shortcut(Route, NothingPinned, *Field, Cost, Agent, kStepHeight);

    const auto UnpinnedReport = FString::Printf(
        TEXT("[SHORTCUT] clear lane A-B-C, nothing pinned: %s"), *Get_WaypointReport(Unpinned));

    ck::groundnav::Display(TEXT("{}"), UnpinnedReport);

    if (NOT TestEqual(FString::Printf(TEXT("with nothing pinned the pass drops the middle point [%s]"),
        *UnpinnedReport), Unpinned.Num(), kTheTwoEnds))
    { return false; }

    TestTrue(FString::Printf(TEXT("and answers with the two ends it was given [%s]"), *UnpinnedReport),
        Unpinned[0] == kLaneWest && Unpinned.Last() == kLaneEast);

    // The SAME route over the SAME geometry, differing in the pinned list and nothing else. That is
    // what makes this a test of the pinning rule rather than of the accept rule: the one thing that
    // changed is the instruction, so the one thing that can explain B surviving is the pass obeying it.
    const auto Pinned = Get_Shortcut(Route, MiddlePinned, *Field, Cost, Agent, kStepHeight);

    const auto PinnedReport = FString::Printf(
        TEXT("[SHORTCUT] clear lane A-B-C, middle pinned: %s"), *Get_WaypointReport(Pinned));

    ck::groundnav::Display(TEXT("{}"), PinnedReport);

    if (NOT TestEqual(FString::Printf(TEXT("pinning the middle point keeps it on the route [%s]"),
        *PinnedReport), Pinned.Num(), kBothSpansKept))
    { return false; }

    // Exactly, not within a tolerance: a pinned point is a place the body passes THROUGH, and a pass
    // that moved one has walked the body off whatever put it there.
    TestTrue(FString::Printf(
        TEXT("exactly where it was pinned, with the span split into A-B and B-C [%s]"), *PinnedReport),
        Pinned[0] == kLaneWest && Pinned[1] == kLaneBend && Pinned[2] == kLaneEast);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_pathshortcut_pricedband
{
    using namespace ck_test_groundnav_pathshortcut;

    // Three bands of floor joined by a connector at each end, and the middle band is what gets priced.
    //
    // The shape is chosen so the two things the claim needs are independent: the middle band is its own
    // PLATE because two walls bound it - a Cost markup would not do it, since Stamp_PlateCostPolicies
    // prices a whole plate and explicitly never splits one - and the straight line between the two ends
    // crosses that band over ground that is perfectly walkable. So the way round is a decision about
    // PRICE alone, and a chord across it would be recovering a line the search refused on cost.
    constexpr auto kBandFreeMinX = 100.0;
    constexpr auto kBandFreeMaxX = 1000.0;
    constexpr auto kBandFreeMinY = 100.0;
    constexpr auto kBandFreeMaxY = 1100.0;

    constexpr auto kBandDividerMinX = 300.0;
    constexpr auto kBandDividerMaxX = 800.0;

    constexpr auto kBandSouthDividerMinY = 400.0;
    constexpr auto kBandSouthDividerMaxY = 450.0;
    constexpr auto kBandNorthDividerMinY = 750.0;
    constexpr auto kBandNorthDividerMaxY = 800.0;

    // On the middle band's own centre line, in the connectors at either end, so the straight line
    // between them runs the length of the priced ground and bends nowhere.
    constexpr auto kBandRouteY = 600.0;

    const auto kBandStart = FVector{200.0, kBandRouteY, kGroundZ};
    const auto kBandGoal = FVector{900.0, kBandRouteY, kGroundZ};

    // The middle of the priced ground, which is where the plate it belongs to is read off.
    const auto kBandPricedProbe = FVector{550.0, kBandRouteY, kGroundZ};

    constexpr auto kBandAgentRadiusUu = 20.0f;

    // Far past the crossover: the way round the middle band is about twice the direct line, so anything
    // over a handful makes the detour the cheaper answer with room to spare.
    constexpr auto kPricedOutMultiplier = 100.0f;

    auto Make_PricedBandScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}});

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{2000.0, kBandFreeMinY, 300.0}});
        Boxes.Emplace(FBox{FVector{-400.0, kBandFreeMaxY, 0.0}, FVector{2000.0, 2000.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{-400.0, kBandFreeMinY, 0.0}, FVector{kBandFreeMinX, kBandFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kBandFreeMaxX, kBandFreeMinY, 0.0}, FVector{2000.0, kBandFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kBandDividerMinX, kBandSouthDividerMinY, 0.0},
            FVector{kBandDividerMaxX, kBandSouthDividerMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kBandDividerMinX, kBandNorthDividerMinY, 0.0},
            FVector{kBandDividerMaxX, kBandNorthDividerMaxY, 300.0}});

        return Boxes;
    }

    auto Bake_PricedBand(
        FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_PricedBandScene(), Make_QueryParams(), *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    /** Which flat plate the priced ground belongs to, or INDEX_NONE where nothing stands there. */
    auto Get_PricedPlate(
        const FCk_GroundNav_Field& InField) -> int32
    {
        auto Probe = FCk_GroundNav_IsNavigableQuery{};

        Probe._Location = kBandPricedProbe;
        Probe._VerticalToleranceUu = kStepHeight;

        const auto Standing = Get_IsNavigable(InField, Probe);

        if (NOT Standing.Get_IsSuccess())
        { return INDEX_NONE; }

        return Get_FlatPlateIndex(
            InField, Standing._Surface._TileIndex, Standing._Surface._PlateIndex);
    }

    auto Make_PricedCost(
        int32 InShortcutSpanCap,
        int32 InPricedPlate) -> FCk_GroundNav_PathCostParams
    {
        auto Cost = Make_Cost(InShortcutSpanCap);
        Cost._PlateCostMultipliers.Add(InPricedPlate, kPricedOutMultiplier);

        return Cost;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutNeverLowersThePlateCostPaid,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_NeverLowersThePlateCostPaid",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutNeverLowersThePlateCostPaid::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;
    using namespace ck_test_groundnav_pathshortcut_pricedband;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the priced-band scene bakes"), Bake_PricedBand(Field)))
    { return false; }

    const auto PricedPlate = Get_PricedPlate(*Field);

    if (NOT TestTrue(TEXT("the middle band is ground a body can stand on"), PricedPlate != INDEX_NONE))
    { return false; }

    // The chord the shortcut would take, proved CLEAR before anything is priced. Without this the pin
    // could pass because the geometry refused the chord rather than because the pass respected its
    // budget, and the claim would be about a wall instead of about a cost.
    auto ChordQuery = FCk_GroundNav_RaycastQuery{};

    ChordQuery._Start = kBandStart;
    ChordQuery._End = kBandGoal;
    ChordQuery._StartVerticalToleranceUu = kStepHeight;
    ChordQuery._Agent = Make_Agent(kBandAgentRadiusUu);

    if (NOT TestTrue(TEXT("the straight line between the two ends is walkable ground throughout"),
        Get_SurfaceRaycast(*Field, ChordQuery).Get_IsClear()))
    { return false; }

    // Unpriced, the route IS that straight line through the middle band - which is what makes the
    // priced answer below a decision the price caused rather than one the geometry forced.
    const auto Unpriced = Get_Path(Field, Make_PathQuery(
        kBandStart, kBandGoal, kBandAgentRadiusUu, Make_Cost(kShortcutOff)));

    if (NOT TestEqual(TEXT("the unpriced route is answered"),
        Unpriced._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(TEXT("and goes through the middle band"),
        Unpriced._PlateCorridor.Contains(PricedPlate)))
    { return false; }

    const auto Priced = Get_Path(Field, Make_PathQuery(
        kBandStart, kBandGoal, kBandAgentRadiusUu, Make_PricedCost(kShortcutOff, PricedPlate)));

    if (NOT TestEqual(TEXT("the priced route is answered too"),
        Priced._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(TEXT("and the search now routes AROUND the middle band"),
        NOT Priced._PlateCorridor.Contains(PricedPlate)))
    { return false; }

    const auto Off = Get_PathPlan(Priced, *Field, Make_PostParams(
        kBandAgentRadiusUu, Make_PricedCost(kShortcutOff, PricedPlate), kDistantAgentLocation));

    const auto On = Get_PathPlan(Priced, *Field, Make_PostParams(
        kBandAgentRadiusUu, Make_PricedCost(kShortcutUnbounded, PricedPlate), kDistantAgentLocation));

    if (NOT TestTrue(TEXT("both plans carry waypoints to price"),
        NOT Off._Waypoints.IsEmpty() && NOT On._Waypoints.IsEmpty()))
    { return false; }

    const auto OffCost = Off._Waypoints.Last()._CostFromStart;
    const auto OnCost = On._Waypoints.Last()._CostFromStart;

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT] priced plate %d at %.1f: off %s | on %s"),
        PricedPlate, static_cast<double>(kPricedOutMultiplier),
        *Get_PlanReport(Off), *Get_PlanReport(On));

    ck::groundnav::Display(TEXT("{}"), Report);

    // The fill prices whatever polyline it is handed with the SAME Get_AreaMultiplier the search used,
    // so a chord that cut across the priced band comes back charged for it and the total rises. A total
    // that never rises is therefore the budget rule made observable on the shipped plan: the pass may
    // shorten the walk, and may not buy that shortness with ground the search refused to pay for.
    TestTrue(FString::Printf(TEXT("the shortcut never raises what the plan pays [%s]"), *Report),
        OnCost <= OffCost + kEpsilon);

    // A plan whose price fell without its walk shortening has been re-priced rather than re-routed,
    // which the pass has no business doing. Asserted ONLY on the runs where the walk did not shorten:
    // a chord is never longer than the polyline it replaces and _LengthUu is the fill's own Dist2D sum,
    // so "cost held OR length fell" is true of every run this pass can produce and claims nothing.
    if (On._LengthUu >= Off._LengthUu - kEpsilon)
    {
        TestTrue(FString::Printf(TEXT("a plan re-priced without being re-routed keeps its price [%s]"), *Report),
            OnCost >= OffCost - kEpsilon);
    }
    else
    {
        ck::groundnav::Display(TEXT("{}"), FString::Printf(
            TEXT("[SHORTCUT] the pass shortened the walk (%.2f -> %.2f), so the never-raises claim above ")
            TEXT("is the one carrying the budget rule on this run"),
            Off._LengthUu, On._LengthUu));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutIsIdempotent,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_IsIdempotent",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutIsIdempotent::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(
        kFourPillarWestPost, kFourPillarEastPost, kFourPillarAgentRadiusUu,
        Make_Cost(kShortcutUnbounded)));

    if (NOT TestEqual(TEXT("the slab answers a west-east crossing"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    // The polyline the PLAN hands the pass, not the funnel's bare output. Fed the latter the pass is an
    // identity on this scene (the count pin records funnelled 5 -> pass 5), so Twice == Once would hold
    // of a pass that had done nothing at all - which is the one reading idempotence must not have.
    const auto Input = Get_PreShortcutLocations(Result, *Field, kFourPillarAgentRadiusUu);

    if (NOT TestTrue(TEXT("the offset stages gave a polyline to shorten"), Input.Num() >= 2))
    { return false; }

    const auto Cost = Make_Cost(kShortcutUnbounded);
    const auto Agent = Make_Agent(kFourPillarAgentRadiusUu);
    const auto Pinned = Get_PinnedWaypoints(Result);

    const auto Once = Get_Shortcut(Input, Pinned, *Field, Cost, Agent, kStepHeight);
    const auto Twice = Get_Shortcut(Once, Pinned, *Field, Cost, Agent, kStepHeight);

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT] pre-shortcut %d, once %d, twice %d"),
        Input.Num(), Once.Num(), Twice.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

    // The PRECONDITION that makes everything below a statement about idempotence rather than about a
    // pass with nothing to do: the first run must actually remove something. On this route it removes
    // the false corner the offset pushed into open floor, so a first run that removed nothing means the
    // input stopped being one the pass changes and the claim below has gone vacuous.
    if (NOT TestTrue(FString::Printf(TEXT("the first pass removes something to be idempotent about [%s]"), *Report),
        Once.Num() < Input.Num()))
    { return false; }

    if (NOT TestEqual(FString::Printf(TEXT("a second pass removes nothing further [%s]"), *Report),
        Twice.Num(), Once.Num()))
    { return false; }

    // Exactly, not within a tolerance: the pass either kept a point or it did not, and moving one is
    // never something this pass is allowed to do.
    auto Moved = 0;

    for (auto Index = 0; Index < Once.Num(); ++Index)
    {
        if (Twice[Index] != Once[Index])
        { ++Moved; }
    }

    TestEqual(FString::Printf(TEXT("and moves none of the points it kept [%s]"), *Report), Moved, 0);

    // Two points have no interior to remove, so the pass has nothing to do and must say so by handing
    // back what it was given rather than by re-deriving a line between them.
    const auto Ends = TArray<FVector>{Input[0], Input.Last()};
    const auto EndsOnly = Get_Shortcut(Ends, Pinned, *Field, Cost, Agent, kStepHeight);

    TestTrue(TEXT("a route with no interior comes back element for element"),
        EndsOnly.Num() == Ends.Num() && EndsOnly[0] == Ends[0] && EndsOnly.Last() == Ends.Last());

    // Zero is off, not a span of zero - the same reading _CornerOffsetK = 0 already has. Stated over the
    // input the pass DOES change, so "changed nothing" is a decision the cap made rather than one the
    // geometry would have made anyway.
    const auto Disabled = Get_Shortcut(
        Input, Pinned, *Field, Make_Cost(kShortcutOff), Agent, kStepHeight);

    auto ChangedWhileOff = FMath::Abs(Disabled.Num() - Input.Num());

    if (Disabled.Num() == Input.Num())
    {
        for (auto Index = 0; Index < Input.Num(); ++Index)
        {
            if (Disabled[Index] != Input[Index])
            { ++ChangedWhileOff; }
        }
    }

    TestEqual(FString::Printf(TEXT("a span cap of zero changes nothing at all [%s]"), *Report),
        ChangedWhileOff, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_pathshortcut_dearendpoint
{
    using namespace ck_test_groundnav_pathshortcut;

    // What ONE plate of the route's own ground is marked up to. The two claims above - the price
    // never rises, and the pass is idempotent - are both stated on this route at a UNIFORM table,
    // where every multiplier is 1.0 and each of them degenerates to the triangle inequality. A single
    // dear plate on the ground the chord the pass takes runs over is the smallest departure from that,
    // and it is the markup shape the demo gyms ship: enough that a chord billed at that plate's price
    // is billed at four times ground the detour it replaces mostly did not stand on, and not so much
    // that the search abandons the route.
    //
    // The test states it TWICE, at the two ENDS of the chord, because the two halves of the trade
    // answer different ones. SCENARIO A prices the plate the chord's FAR END stands on - the fill's
    // business, since it is the fill that bills a whole chord at its endpoints' price, and the chord is
    // rightly REFUSED there. SCENARIO B prices the plate under the chord's NEAR END, which on this slab
    // is also the plate the dropped corner stands on (measured: near 6, dropped 6, far 15): the detour
    // pays that ground on BOTH of its segments while the chord pays it once, so the chord is TAKEN and
    // the published price falls.
    //
    // A third shape was tried and abandoned - a dear plate the chord CROSSES with no waypoint on it,
    // the design's O2 discriminator for the ray budget. On this slab both sides cross the same tile-wide
    // plate end to end and the DIAGONAL chord crosses ~0.1 uu MORE of it than the straight segment it
    // replaces, so at 4x it costs 3820.68 against a 3820.21 budget and O5 rightly refuses it by 0.47 -
    // it never pays more for the ground than the corridor paid. O2 needs a fixture where the DETOUR
    // crosses more dear ground than the chord (filed as its own follow-up).
    constexpr auto kDearEndpointMultiplier = 4.0f;

    /** Which flat plate a body standing at a location stands on, read the way the priced-band pin reads its own. */
    auto Get_PlateAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> int32
    {
        auto Probe = FCk_GroundNav_IsNavigableQuery{};

        Probe._Location = InLocation;
        Probe._VerticalToleranceUu = kStepHeight;
        Probe._Agent = Make_Agent(kFourPillarAgentRadiusUu);

        const auto Standing = Get_IsNavigable(InField, Probe);

        if (NOT Standing.Get_IsSuccess())
        { return INDEX_NONE; }

        return Get_FlatPlateIndex(
            InField, Standing._Surface._TileIndex, Standing._Surface._PlateIndex);
    }

    auto Make_DearEndpointCost(
        int32 InShortcutSpanCap,
        int32 InDearPlate) -> FCk_GroundNav_PathCostParams
    {
        auto Cost = Make_Cost(InShortcutSpanCap);
        Cost._PlateCostMultipliers.Add(InDearPlate, kDearEndpointMultiplier);

        return Cost;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutCostNeverRisesWhenAnEndpointStandsOnDearGround,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_CostNeverRisesWhenAnEndpointStandsOnDearGround",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutCostNeverRisesWhenAnEndpointStandsOnDearGround::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;
    using namespace ck_test_groundnav_pathshortcut_dearendpoint;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    // ONE search, at a UNIFORM table, planned several ways below. A plate marked up in the POST params
    // changes what the plan pays for a polyline without changing which corridor the search chose, so
    // every comparison here is one corridor priced differently - which is what makes each of them a
    // statement about the pass rather than about two routes.
    const auto Result = Get_Path(Field, Make_PathQuery(
        kFourPillarWestPost, kFourPillarEastPost, kFourPillarAgentRadiusUu,
        Make_Cost(kShortcutUnbounded)));

    if (NOT TestEqual(TEXT("the slab answers a west-east crossing"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto UniformOff = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutOff), kDistantAgentLocation));

    const auto UniformOn = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutUnbounded), kDistantAgentLocation));

    if (NOT TestTrue(TEXT("both uniform plans carry waypoints to price"),
        NOT UniformOff._Waypoints.IsEmpty() && NOT UniformOn._Waypoints.IsEmpty()))
    { return false; }

    const auto UniformReport = FString::Printf(
        TEXT("[SHORTCUT] dear endpoint, uniform table: off %s | on %s"),
        *Get_PlanReport(UniformOff), *Get_PlanReport(UniformOn));

    ck::groundnav::Display(TEXT("{}"), UniformReport);

    // The CONTROL, and what makes the two scenarios below reachable at all: at a uniform table this
    // route has a false corner and the pass takes it. Everything after this reads the chord's two ends
    // off that drop, so a route the pass leaves alone leaves nothing to mark the ground under.
    if (NOT TestTrue(FString::Printf(
        TEXT("the pass drops the false corner at a uniform table [%s]"), *UniformReport),
        UniformOn._Waypoints.Num() < UniformOff._Waypoints.Num()))
    { return false; }

    // WHICH point it dropped, and therefore which chord replaced it: the first off-plan waypoint whose
    // location appears nowhere in the on-plan. Exact equality, the comparison the idempotence pin
    // makes, because the pass either kept a point or it did not and moving one is not something it is
    // allowed to do.
    auto DroppedIndex = int32{INDEX_NONE};

    for (auto Index = 0; Index < UniformOff._Waypoints.Num(); ++Index)
    {
        const auto& Location = UniformOff._Waypoints[Index]._Location;

        auto Kept = false;

        for (const auto& Waypoint : UniformOn._Waypoints)
        {
            if (Waypoint._Location == Location)
            {
                Kept = true;

                break;
            }
        }

        if (NOT Kept)
        {
            DroppedIndex = Index;

            break;
        }
    }

    if (NOT TestTrue(FString::Printf(
        TEXT("the point the pass dropped is an INTERIOR one with a neighbour either side [%s]"), *UniformReport),
        DroppedIndex > 0 && DroppedIndex < UniformOff._Waypoints.Num() - 1))
    { return false; }

    // The chord's two ends are the dropped point's off-plan neighbours, and the FAR one is the one at
    // the larger off-plan index - the end the chord arrives at, and the end the rise is about.
    const auto Dropped = UniformOff._Waypoints[DroppedIndex]._Location;
    const auto NearEnd = UniformOff._Waypoints[DroppedIndex - 1]._Location;
    const auto FarEnd = UniformOff._Waypoints[DroppedIndex + 1]._Location;

    const auto NearPlate = Get_PlateAt(*Field, NearEnd);
    const auto DroppedPlate = Get_PlateAt(*Field, Dropped);
    const auto FarPlate = Get_PlateAt(*Field, FarEnd);

    const auto ChordReport = FString::Printf(
        TEXT("[SHORTCUT] the pass drops (%.1f, %.1f) for the chord (%.1f, %.1f) -> (%.1f, %.1f); ")
        TEXT("plates near %d dropped %d far %d"),
        Dropped.X, Dropped.Y, NearEnd.X, NearEnd.Y, FarEnd.X, FarEnd.Y,
        NearPlate, DroppedPlate, FarPlate);

    ck::groundnav::Display(TEXT("{}"), ChordReport);

    if (NOT TestTrue(FString::Printf(
        TEXT("the chord's ends and the point it replaces all stand on ground that has a plate [%s]"), *ChordReport),
        NearPlate != INDEX_NONE && DroppedPlate != INDEX_NONE && FarPlate != INDEX_NONE))
    { return false; }

    // SCENARIO A - the fill conjunct, and the case that was red before it existed. Price the plate the
    // chord's FAR end stands on, and nothing else. The chord is then ADMITTED against the ground it
    // actually crosses and BILLED against the greater of its two ends' plates, and those were different
    // numbers: the ray budget was a sum of endpoint-max x Dist2D over the replaced segments (a
    // ~1900-shape on this route's magnitudes) while the chord's own ray, pricing per cell, answered a
    // ~1130-shape - so the chord cleared the budget, the fill then billed the WHOLE chord at 4x, and
    // the published cost rose. Conjunct (ii) refuses exactly that: the fill's price of the chord may
    // not exceed the fill's price of what it replaces.
    //
    // Whether the chord SURVIVES the markup is deliberately not asserted either way. Under O5 the
    // expected answer is that it does not - billing 4x a chord running mostly over 1.0 plates is
    // precisely what (ii) refuses - and that refusal is the conjunct working rather than a fixture that
    // stopped hosting the case. What is asserted is the one thing that must hold whichever way it goes.
    if (NOT TestTrue(FString::Printf(
        TEXT("the chord's two ends stand on DIFFERENT plates; if not there is no dear-endpoint case ")
        TEXT("here and the fixture needs re-measuring [%s]"), *ChordReport),
        NearPlate != FarPlate))
    { return false; }

    const auto FarOff = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_DearEndpointCost(kShortcutOff, FarPlate), kDistantAgentLocation));

    const auto FarOn = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_DearEndpointCost(kShortcutUnbounded, FarPlate), kDistantAgentLocation));

    if (NOT TestTrue(TEXT("both far-end plans carry waypoints to price"),
        NOT FarOff._Waypoints.IsEmpty() && NOT FarOn._Waypoints.IsEmpty()))
    { return false; }

    const auto FarReport = FString::Printf(
        TEXT("[SHORTCUT] far chord end on plate %d at %.1f: off %s | on %s"),
        FarPlate, static_cast<double>(kDearEndpointMultiplier),
        *Get_PlanReport(FarOff), *Get_PlanReport(FarOn));

    ck::groundnav::Display(TEXT("{}"), FarReport);

    TestTrue(FString::Printf(TEXT("the shortcut never raises what the plan pays [%s]"), *FarReport),
        FarOn._Waypoints.Last()._CostFromStart <= FarOff._Waypoints.Last()._CostFromStart + kEpsilon);

    ck::groundnav::Display(TEXT("{}"), FString::Printf(
        TEXT("[SHORTCUT] with the far end marked up the chord was %s"),
        FarOn._Waypoints.Num() < FarOff._Waypoints.Num() ? TEXT("ACCEPTED") : TEXT("REFUSED")));

    // SCENARIO B - the budget conjunct's own case, and the shape that discriminates on THIS slab: price
    // the plate under the chord's NEAR END, which here is also the plate the dropped corner stands on.
    // The detour crosses that dear ground on BOTH of its segments while the chord crosses it once, so
    // both budgets clear by a few units and the chord is taken. Before the per-segment ray the budget
    // priced the replaced stretch at endpoint-max x Dist2D; now the replaced segments are cast by the
    // SAME ray as the chord, so both sides charge the same ground. It is also a table whose multipliers
    // are NOT all equal that the pass shortens under, which is what the idempotence claim below needs
    // to be about a pass that did something.
    //
    // The plate the chord CROSSES with no waypoint on it - the design's O2 discriminator - is NOT
    // stated here; the multiplier's note above records why this slab cannot host it.
    if (NOT TestTrue(FString::Printf(
        TEXT("the chord's near end and the corner it drops share a plate the far end does not, or ")
        TEXT("this scenario has no dear ground to price [near %d dropped %d far %d]"),
        NearPlate, DroppedPlate, FarPlate),
        NearPlate == DroppedPlate && NearPlate != FarPlate && NearPlate != INDEX_NONE))
    { return false; }

    const auto DearNearCostOff = Make_DearEndpointCost(kShortcutOff, NearPlate);
    const auto DearNearCostOn = Make_DearEndpointCost(kShortcutUnbounded, NearPlate);

    const auto NearOff = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, DearNearCostOff, kDistantAgentLocation));

    const auto NearOn = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, DearNearCostOn, kDistantAgentLocation));

    if (NOT TestTrue(TEXT("both near-end plans carry waypoints to price"),
        NOT NearOff._Waypoints.IsEmpty() && NOT NearOn._Waypoints.IsEmpty()))
    { return false; }

    const auto NearReport = FString::Printf(
        TEXT("[SHORTCUT] dear plate %d under the near end and the corner at %.1f: off %s | on %s"),
        NearPlate, static_cast<double>(kDearEndpointMultiplier),
        *Get_PlanReport(NearOff), *Get_PlanReport(NearOn));

    ck::groundnav::Display(TEXT("{}"), NearReport);

    // The three rays the pass weighs for this chord, cast with the same table and uncapped, reported so
    // the MARGINS are visible: both budgets clear the chord by only a few units on this shallow corner
    // (the false corner sits 26 uu off the straight line, so the triangle-inequality gap is 1.6 uu
    // before multipliers). The line also names which side would refuse - a replaced segment's own ray
    // (the fallback) or the chord's. A red at the count assertion below should be read with these
    // numbers, not re-measured blind.
    {
        const auto RayAgent = Make_Agent(kFourPillarAgentRadiusUu);

        const auto CastPriced = [&](const FVector& InFrom, const FVector& InTo) -> FString
        {
            auto Query = FCk_GroundNav_RaycastQuery{};
            Query._Start = InFrom;
            Query._End = InTo;
            Query._StartVerticalToleranceUu = kStepHeight;
            Query._Agent = RayAgent;
            Query._PlateCostMultipliers = DearNearCostOn._PlateCostMultipliers;
            Query._UseBakedPlateCost = true;
            Query._MaxCost = 0.0f;

            const auto Answer = Get_SurfaceRaycast(*Field, Query);

            return FString::Printf(TEXT("status %d cost %.2f len2d %.2f"),
                static_cast<int32>(Answer._Status), static_cast<double>(Answer._AccumulatedCost),
                FVector::Dist2D(InFrom, InTo));
        };

        auto RayFallbacks = int32{0};
        const auto RayInput = Get_PreShortcutLocations(Result, *Field, kFourPillarAgentRadiusUu);
        const auto RayPass = Get_Shortcut(RayInput, Get_PinnedWaypoints(Result), *Field, DearNearCostOn, RayAgent, kStepHeight, &RayFallbacks);

        ck::groundnav::Display(
            TEXT("[SHORTCUT] rays under the near-end table: near->dropped {} | dropped->far {} | near->far {} | offset polyline {} -> pass {} fallbacks {}"),
            CastPriced(NearEnd, Dropped), CastPriced(Dropped, FarEnd), CastPriced(NearEnd, FarEnd),
            RayInput.Num(), RayPass.Num(), RayFallbacks);
    }

    if (NOT TestTrue(FString::Printf(
        TEXT("with the near end's plate marked up the pass still takes the chord: the detour paid ")
        TEXT("that ground on two segments, the chord pays it once [%s]"), *NearReport),
        NearOn._Waypoints.Num() < NearOff._Waypoints.Num()))
    { return false; }

    TestTrue(FString::Printf(TEXT("and never raises what the plan pays [%s]"), *NearReport),
        NearOn._Waypoints.Last()._CostFromStart <= NearOff._Waypoints.Last()._CostFromStart + kEpsilon);

    // The same idempotence the uniform-table pin states, restated where the multipliers are NOT all
    // equal - which is the only case in which the two runs' budgets could differ, and so the only case
    // in which the claim says anything.
    const auto Input = Get_PreShortcutLocations(Result, *Field, kFourPillarAgentRadiusUu);

    if (NOT TestTrue(TEXT("the offset stages gave a polyline to shorten"), Input.Num() >= 2))
    { return false; }

    const auto Agent = Make_Agent(kFourPillarAgentRadiusUu);
    const auto Pinned = Get_PinnedWaypoints(Result);

    const auto Once = Get_Shortcut(Input, Pinned, *Field, DearNearCostOn, Agent, kStepHeight);
    const auto Twice = Get_Shortcut(Once, Pinned, *Field, DearNearCostOn, Agent, kStepHeight);

    const auto IdempotenceReport = FString::Printf(
        TEXT("[SHORTCUT] dear plate %d under the near end: pre-shortcut %d, once %d, twice %d"),
        NearPlate, Input.Num(), Once.Num(), Twice.Num());

    ck::groundnav::Display(TEXT("{}"), IdempotenceReport);

    if (NOT TestTrue(FString::Printf(
        TEXT("the first pass removes something to be idempotent about [%s]"), *IdempotenceReport),
        Once.Num() < Input.Num()))
    { return false; }

    if (NOT TestEqual(FString::Printf(
        TEXT("a second pass over a non-uniform table removes nothing further [%s]"), *IdempotenceReport),
        Twice.Num(), Once.Num()))
    { return false; }

    auto Moved = 0;

    for (auto Index = 0; Index < Once.Num(); ++Index)
    {
        if (Twice[Index] != Once[Index])
        { ++Moved; }
    }

    TestEqual(FString::Printf(TEXT("and moves none of the points it kept [%s]"), *IdempotenceReport),
        Moved, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_pathshortcut_rampgap
{
    using namespace ck_test_groundnav_pathshortcut;

    using ck_test_groundnav_queryfixtures::Bake_RampGapPillarScene;
    using ck_test_groundnav_queryfixtures::Get_RampVsLevelSurfaceZ;
    using ck_test_groundnav_queryfixtures::kRampVsLevelRampStartX;

    // The penalty the search itself gives the slope up at, mirrored from the search pin that measured
    // it (Test_GroundNav_PathSearch.cpp:643). Restated rather than shared because the two files pin
    // different stages of the same trade and neither should be able to move the other's number.
    constexpr auto kSteepSlopePenaltyK = 8.0f;

    // Small enough for the slots the pillar leaves either side of itself in the east gap, which is the
    // only thing the radius has to fit here.
    constexpr auto kRampGapAgentRadiusUu = 20.0f;

    // West of the panel's foot and south of the divider, so the start itself owes the slope nothing.
    const auto kRampGapStart = FVector{850.0, 400.0, kGroundZ};

    // On the panel, north of the divider and east of the pillar, so the route must cross the east gap
    // and weave past the pillar to get there - and cannot avoid the climb by going the level way,
    // because the goal is up the slope whichever way round the wall it is reached.
    const auto kRampGapGoalX = 1250.0;
    const auto kRampGapGoal = FVector{kRampGapGoalX, 1000.0, Get_RampVsLevelSurfaceZ(kRampGapGoalX)};

    // A cell of height and then some: a waypoint the lattice nudged off the level floor must not read
    // as one standing on the panel.
    constexpr auto kOnThePanelZUu = 25.0;

    // How much of a climb the route's two ends must be apart for the slope term to be exercised on both
    // sides of the fill's comparison rather than multiplied by a rise of zero. The goal sits ~127 uu up
    // the panel from the start, so this is a floor under a measured number and not a target.
    constexpr auto kClimbedUu = 100.0;

    auto Bake_RampGapPillar(
        FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake_RampGapPillarScene(*Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    auto Make_SlopedCost(
        int32 InShortcutSpanCap,
        float InSlopePenaltyK) -> FCk_GroundNav_PathCostParams
    {
        auto Cost = Make_Cost(InShortcutSpanCap);
        Cost._SlopePenaltyK = InSlopePenaltyK;

        return Cost;
    }

    /** How many INTERIOR waypoints of a plan stand on the ramp panel rather than on the level floor. */
    auto Get_InteriorWaypointsOnThePanel(
        const FCk_GroundNav_PathPlan& InPlan) -> int32
    {
        auto OnThePanel = 0;

        for (auto Index = 1; Index < InPlan._Waypoints.Num() - 1; ++Index)
        {
            const auto& Location = InPlan._Waypoints[Index]._Location;

            if (Location.X > kRampVsLevelRampStartX && Location.Z > kGroundZ + kOnThePanelZUu)
            { ++OnThePanel; }
        }

        return OnThePanel;
    }
}

// --------------------------------------------------------------------------------------------------------------------

// WHAT THIS CLAIMS, AND WHAT IT DELIBERATELY DOES NOT. The claim this pin was first written for - a
// chord the slope penalty REFUSES that the geometry admits - is unrealizable under this cost model.
// Get_LegCost prices a segment from its two ENDPOINTS' 3D delta, so on a panel where Z is a function of
// X a straight chord between two points climbs exactly what any detour between those same two points
// climbs, and the slope term can never make the chord dearer than the stretch it replaces. The design's
// Finding-B worked example set two FLAT legs against a CLIMBING chord between the same endpoints, which
// is geometrically impossible: if the chord climbs, the legs climbed the same rise.
//
// What the fill conjunct DOES guarantee is the thing worth pinning here: the 3D-plus-slope price the
// plan PUBLISHES never rises across the pass, on a climb exactly as on the flat. Every other price pin
// in this file runs at _SlopePenaltyK = 0, where Get_LegCost degenerates to 2D arc length and the
// triangle inequality carries the claim whether or not the pass prices anything correctly.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutCostNeverRisesUnderTheSlopePenalty,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_CostNeverRisesUnderTheSlopePenalty",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutCostNeverRisesUnderTheSlopePenalty::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;
    using namespace ck_test_groundnav_pathshortcut_rampgap;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the ramp-gap-pillar scene bakes"), Bake_RampGapPillar(Field)))
    { return false; }

    const auto SteepCostOff = Make_SlopedCost(kShortcutOff, kSteepSlopePenaltyK);
    const auto SteepCostOn = Make_SlopedCost(kShortcutUnbounded, kSteepSlopePenaltyK);

    const auto Steep = Get_Path(Field, Make_PathQuery(
        kRampGapStart, kRampGapGoal, kRampGapAgentRadiusUu, SteepCostOn));

    if (NOT TestEqual(TEXT("the scene answers a west-east crossing of the east gap under a steep penalty"),
        Steep._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto Off = Get_PathPlan(Steep, *Field, Make_PostParams(
        kRampGapAgentRadiusUu, SteepCostOff, kDistantAgentLocation));

    const auto On = Get_PathPlan(Steep, *Field, Make_PostParams(
        kRampGapAgentRadiusUu, SteepCostOn, kDistantAgentLocation));

    if (NOT TestTrue(TEXT("both plans carry waypoints to price"),
        NOT Off._Waypoints.IsEmpty() && NOT On._Waypoints.IsEmpty()))
    { return false; }

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT] ramp gap at k=%.1f: off %s | on %s, interior on the panel %d"),
        static_cast<double>(kSteepSlopePenaltyK),
        *Get_PlanReport(Off), *Get_PlanReport(On),
        Get_InteriorWaypointsOnThePanel(Off));

    ck::groundnav::Display(TEXT("{}"), Report);

    // The PRECONDITION, asserted before the claim it makes non-vacuous and never softened into a skip.
    // A pass that dropped nothing leaves every price identical and would satisfy the comparison below
    // while proving none of it. A red here means the fixture stopped hosting the case - move the pillar
    // until the east-gap crossing weaves - and never that the pass is fine.
    if (NOT TestTrue(FString::Printf(
        TEXT("the pass drops a bend on this route under a steep penalty; if not, the pillar needs ")
        TEXT("moving until the east-gap crossing weaves [%s]"), *Report),
        On._Waypoints.Num() < Off._Waypoints.Num()))
    { return false; }

    // And the route it drops it on CLIMBS, which is what puts the slope term on both sides of the
    // fill's comparison instead of multiplying it by a rise of zero. Read off the two ends the search
    // was given, so it is a statement about the fixture rather than about whatever the pass produced.
    TestTrue(FString::Printf(TEXT("the two ends of this route are a real climb apart [%s]"), *Report),
        kRampGapGoal.Z - kRampGapStart.Z >= kClimbedUu);

    const auto OffCost = Off._Waypoints.Last()._CostFromStart;
    const auto OnCost = On._Waypoints.Last()._CostFromStart;

    // THE CLAIM. Both plans are priced by Get_LegCost, which carries the 3D length and the
    // 1 + k * rise/run term, and the fill conjunct is what holds the second number under the first: the
    // pass may take a chord only where the fill's own price of that chord is no more than the fill's
    // price of the stretch it replaces.
    TestTrue(FString::Printf(TEXT("the shortcut never raises what the plan pays on a climb [%s]"), *Report),
        OnCost <= OffCost + kEpsilon);

    // The CONTROL, on the SAME search result rather than a second query: re-planned with nothing
    // charged for the climb, the pass is handed the same corridor and the same polyline and only the
    // fill's slope term moves. Both claims must hold there too, which is what makes the pair above a
    // statement about what the penalty does to the pass rather than one about this route in particular.
    const auto LevelOff = Get_PathPlan(Steep, *Field, Make_PostParams(
        kRampGapAgentRadiusUu, Make_SlopedCost(kShortcutOff, 0.0f), kDistantAgentLocation));

    const auto LevelOn = Get_PathPlan(Steep, *Field, Make_PostParams(
        kRampGapAgentRadiusUu, Make_SlopedCost(kShortcutUnbounded, 0.0f), kDistantAgentLocation));

    if (NOT TestTrue(TEXT("both unpenalised plans carry waypoints to price"),
        NOT LevelOff._Waypoints.IsEmpty() && NOT LevelOn._Waypoints.IsEmpty()))
    { return false; }

    const auto LevelReport = FString::Printf(
        TEXT("[SHORTCUT] ramp gap at k=0: off %s | on %s"),
        *Get_PlanReport(LevelOff), *Get_PlanReport(LevelOn));

    ck::groundnav::Display(TEXT("{}"), LevelReport);

    TestTrue(FString::Printf(
        TEXT("with nothing charged for the climb the pass drops a bend too [%s]"), *LevelReport),
        LevelOn._Waypoints.Num() < LevelOff._Waypoints.Num());

    TestTrue(FString::Printf(
        TEXT("and does not raise what the plan pays there either [%s]"), *LevelReport),
        LevelOn._Waypoints.Last()._CostFromStart <= LevelOff._Waypoints.Last()._CostFromStart + kEpsilon);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutWaypointCountsAreStableAndRecorded,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_WaypointCountsAreStableAndRecorded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutWaypointCountsAreStableAndRecorded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;

    // WHAT IS PINNED: WAYPOINT COUNTS, AND WHY NOT A RAYCAST COUNT. Get_Shortcut answers with a
    // polyline and nothing else, and FCk_GroundNav_QueryCost carries cells read and tiles touched but
    // no count of segments cast - so there is no raycast number to read here without inventing an API
    // for one, and the wall-clock cost of the pass is the B4 metric's business rather than this pin's.
    // What IS deterministic and machine-independent is how many waypoints the pass consumed and
    // produced on a fixed scene, and that moves for every reason a raycast count would: a changed
    // accept rule, a changed budget, a changed corridor. Pinned as counts, in the manner
    // Test_GroundNav_ReferenceNumbers.cpp pins its search budgets.
    //
    // A constant set to INDEX_NONE reports itself on the log and asserts nothing; that is what a
    // deliberate change to the pass is re-measured against before it is re-pinned. The four below are
    // pinned to measured numbers.
    // Pinned 2026-09-06 (S10-6): the pass run bare over the funnel's output drops nothing, because
    // before the corner offset the apexes hug their walls at one radius and the chord between two
    // of them is refused; the plan, which offsets first, drops the false corner.
    constexpr int32 kFunnelledWaypoints = 5;
    constexpr int32 kShortcutWaypoints = 5;
    constexpr int32 kPlanWaypointsWithThePassOff = 5;
    constexpr int32 kPlanWaypointsWithThePassOn = 4;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(
        kFourPillarWestPost, kFourPillarEastPost, kFourPillarAgentRadiusUu,
        Make_Cost(kShortcutUnbounded)));

    if (NOT TestEqual(TEXT("the slab answers a west-east crossing"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    auto Funnelled = TArray<FVector>{};
    Get_Funnelled(Result, kFourPillarAgentRadiusUu, Funnelled);

    // How many of the pass's own segments could not be priced by their own raycast and fell back to the
    // endpoint-max price. REPORTED and never asserted: it is the one number that says how much of the
    // ray budget is really the ray's, and no run has yet measured what it is on this route.
    auto SegmentRayFallbacks = 0;

    const auto Shortcut = Get_Shortcut(
        Funnelled, Get_PinnedWaypoints(Result), *Field, Make_Cost(kShortcutUnbounded),
        Make_Agent(kFourPillarAgentRadiusUu), kStepHeight, &SegmentRayFallbacks);

    const auto Off = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutOff), kDistantAgentLocation));

    const auto On = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutUnbounded), kDistantAgentLocation));

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT-BUDGET] four-pillar route: funnelled %d, shortcut %d, plan off %d, plan on %d, ")
        TEXT("length off %.2f, length on %.2f, expansions %d, cells read %d, segmentRayFallbacks %d"),
        Funnelled.Num(), Shortcut.Num(), Off._Waypoints.Num(), On._Waypoints.Num(),
        Off._LengthUu, On._LengthUu, Result._ExpansionCount, Result._Cost._CellsRead,
        SegmentRayFallbacks);

    ck::groundnav::Display(TEXT("{}"), Report);

    // Determinism is what makes a count assertable at all: the same scene and the same query must
    // produce the same polyline every run, or no budget expressed in it could be held to.
    const auto Repeat = Get_Shortcut(
        Funnelled, Get_PinnedWaypoints(Result), *Field, Make_Cost(kShortcutUnbounded),
        Make_Agent(kFourPillarAgentRadiusUu), kStepHeight);

    TestEqual(TEXT("the pass answers the same count twice"), Repeat.Num(), Shortcut.Num());

    // The pass REMOVES points and inserts none, so a count that grew is a different pass than the one
    // described - whatever else it did.
    TestTrue(FString::Printf(TEXT("the pass never adds a waypoint [%s]"), *Report),
        Shortcut.Num() <= Funnelled.Num() && On._Waypoints.Num() <= Off._Waypoints.Num());

    // The two ends are where the body is and where it was told to go, and no pass may answer a
    // different query than the one that was asked.
    if (Funnelled.Num() >= 2 && Shortcut.Num() >= 2)
    {
        TestTrue(FString::Printf(TEXT("and keeps both ends exactly [%s]"), *Report),
            Shortcut[0] == Funnelled[0] && Shortcut.Last() == Funnelled.Last());
    }

    // The same three checks over the polyline the PLAN hands the pass. On the bare funnel output above
    // the pass is an IDENTITY on this scene - it consumed 5 and answered 5 - so determinism, "never
    // adds", and "keeps both ends" are all satisfied there by a pass that did nothing. Restated over
    // the offset polyline, where the pass genuinely drops the false corner, they are claims about work.
    const auto PreShortcut = Get_PreShortcutLocations(Result, *Field, kFourPillarAgentRadiusUu);

    const auto FromPreShortcut = Get_Shortcut(
        PreShortcut, Get_PinnedWaypoints(Result), *Field, Make_Cost(kShortcutUnbounded),
        Make_Agent(kFourPillarAgentRadiusUu), kStepHeight);

    const auto PreShortcutRepeat = Get_Shortcut(
        PreShortcut, Get_PinnedWaypoints(Result), *Field, Make_Cost(kShortcutUnbounded),
        Make_Agent(kFourPillarAgentRadiusUu), kStepHeight);

    const auto PreShortcutReport = FString::Printf(
        TEXT("[SHORTCUT-BUDGET] four-pillar route, offset polyline: pre-shortcut %d, pass %d"),
        PreShortcut.Num(), FromPreShortcut.Num());

    ck::groundnav::Display(TEXT("{}"), PreShortcutReport);

    TestEqual(FString::Printf(TEXT("the pass answers the same count twice on the offset polyline [%s]"),
        *PreShortcutReport), PreShortcutRepeat.Num(), FromPreShortcut.Num());

    TestTrue(FString::Printf(TEXT("and never adds a waypoint to it [%s]"), *PreShortcutReport),
        FromPreShortcut.Num() <= PreShortcut.Num());

    if (PreShortcut.Num() >= 2 && FromPreShortcut.Num() >= 2)
    {
        TestTrue(FString::Printf(TEXT("and keeps both of its ends exactly [%s]"), *PreShortcutReport),
            FromPreShortcut[0] == PreShortcut[0] && FromPreShortcut.Last() == PreShortcut.Last());
    }

    // The pass off must reproduce the plan as it stood before the stage existed: funnel, link
    // endpoints, corner offset, skip-first, fill - run by hand here, element for element. That is what
    // makes the span cap a switch rather than a tuning knob, and it is stated with the pass OFF for a
    // second reason: where it is on, the stage's position in the chain is the production's business.
    const auto Staged = Get_StagedLocations(
        Result, *Field, kFourPillarAgentRadiusUu, kDistantAgentLocation);

    if (TestEqual(TEXT("with the pass off the plan has one waypoint per point the other stages made"),
        Off._Waypoints.Num(), Staged.Num()))
    {
        auto MatchesTheStages = true;

        for (auto Index = 0; Index < Staged.Num(); ++Index)
        {
            MatchesTheStages = MatchesTheStages && Off._Waypoints[Index]._Location == Staged[Index];
        }

        TestTrue(TEXT("and every one of them is EXACTLY the point that pass emitted"), MatchesTheStages);
    }

    Do_CheckPin(*this, TEXT("waypoints the funnel gave the pass on the four-pillar route"),
        kFunnelledWaypoints, Funnelled.Num());

    Do_CheckPin(*this, TEXT("waypoints the pass answered with"),
        kShortcutWaypoints, Shortcut.Num());

    Do_CheckPin(*this, TEXT("waypoints the plan carries with the pass off"),
        kPlanWaypointsWithThePassOff, Off._Waypoints.Num());

    Do_CheckPin(*this, TEXT("waypoints the plan carries with the pass on"),
        kPlanWaypointsWithThePassOn, On._Waypoints.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
