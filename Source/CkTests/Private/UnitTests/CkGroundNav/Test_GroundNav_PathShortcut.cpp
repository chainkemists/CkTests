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
// Two further pins state what the pass's two DIALS buy. Shortcut_SpanCapBoundary states the cap's own
// boundary - a cap of one is still the pass OFF and answers the polyline element for element, a cap of
// two takes a chord over at most one dropped point, and a wider reach never keeps more points than a
// narrower one. Shortcut_BudgetSeesGroundNoWaypointStandsOn states what the RAY budget buys that the
// retired endpoint-max arithmetic could not: a chord across dear ground NO waypoint of it stands on is
// admitted when the detour it replaces crosses at least as much of that ground.
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
    using ck_test_groundnav_queryfixtures::kFourPillarPostXUu;
    using ck_test_groundnav_queryfixtures::kFourPillarSlabBottomZ;
    using ck_test_groundnav_queryfixtures::kFourPillarSlabHalfXUu;
    using ck_test_groundnav_queryfixtures::kFourPillarSlabHalfYUu;
    using ck_test_groundnav_queryfixtures::kFourPillarWestPost;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_FourPillarParams;
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

// WHERE THE CAP TURNS ON, AND WHAT IT BUYS ONE STEP AT A TIME. The idempotence pin above states the
// OFF end of the dial at zero; this one states the boundary the documentation makes and a number
// alone cannot: one is still off, because a chord needs TWO segments to replace and a cap of one
// leaves the candidate loop empty (CkGroundNav_PathPostProcess.cpp:598-600), so the pass answers what
// it was given. Two is the narrowest cap that is ON, and it may skip exactly one point per chord -
// which is assertable on the answer itself, since every point the pass keeps is a point it was given
// and the gaps between them are what a reach of two allows.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutSpanCapBoundary,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_SpanCapBoundary",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutSpanCapBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;

    // The last cap that is still the pass OFF, and the one a reader cannot guess from the number.
    constexpr auto kCapThatIsStillOff = 1;

    // The narrowest cap that is ON: it reaches two points ahead, so the widest chord it can take
    // replaces two segments and drops the ONE point between them.
    constexpr auto kCapThatMaySkipOnePoint = 2;

    // Measured and reported only, so the line carries the shape of the dial rather than one point on it.
    constexpr auto kCapThatMaySkipTwoPoints = 3;

    // What a cap of two may leave between two consecutive points it kept: the next point of the input,
    // or the one after it. Anything wider is a chord that skipped two points on a reach of two.
    constexpr auto kWidestGapACapOfTwoMayLeave = 2;

    constexpr auto kFewestPointsWithAnInterior = 3;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_PathQuery(
        kFourPillarWestPost, kFourPillarEastPost, kFourPillarAgentRadiusUu,
        Make_Cost(kShortcutUnbounded)));

    if (NOT TestEqual(TEXT("the slab answers a west-east crossing"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    // The polyline the PLAN hands the pass, for the reason the idempotence pin states: fed the funnel's
    // bare output the pass is an identity on this scene, and a boundary stated over an input nothing
    // happens to would hold of a pass that never read the cap at all.
    const auto Input = Get_PreShortcutLocations(Result, *Field, kFourPillarAgentRadiusUu);
    const auto Pinned = Get_PinnedWaypoints(Result);
    const auto Agent = Make_Agent(kFourPillarAgentRadiusUu);

    if (NOT TestTrue(TEXT("the offset stages gave a polyline with an interior to shorten"),
        Input.Num() >= kFewestPointsWithAnInterior))
    { return false; }

    const auto AtCapOne = Get_Shortcut(
        Input, Pinned, *Field, Make_Cost(kCapThatIsStillOff), Agent, kStepHeight);

    const auto AtCapTwo = Get_Shortcut(
        Input, Pinned, *Field, Make_Cost(kCapThatMaySkipOnePoint), Agent, kStepHeight);

    const auto AtCapThree = Get_Shortcut(
        Input, Pinned, *Field, Make_Cost(kCapThatMaySkipTwoPoints), Agent, kStepHeight);

    const auto AtNoCap = Get_Shortcut(
        Input, Pinned, *Field, Make_Cost(kShortcutUnbounded), Agent, kStepHeight);

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT-CAP] input %d: cap1 %d, cap2 %d, cap3 %d, unbounded %d"),
        Input.Num(), AtCapOne.Num(), AtCapTwo.Num(), AtCapThree.Num(), AtNoCap.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

    // Element for element, exactly, the same statement the zero pin makes: a cap below two is not a
    // span of one, it is no pass at all, and a pass that shortened anything here read the dial wrong.
    auto ChangedAtCapOne = FMath::Abs(AtCapOne.Num() - Input.Num());

    if (AtCapOne.Num() == Input.Num())
    {
        for (auto Index = 0; Index < Input.Num(); ++Index)
        {
            if (AtCapOne[Index] != Input[Index])
            { ++ChangedAtCapOne; }
        }
    }

    TestEqual(FString::Printf(
        TEXT("a span cap of one is still the pass OFF and answers element for element [%s]"), *Report),
        ChangedAtCapOne, 0);

    // The PRECONDITION for everything below: this route has a false corner, so a cap that admits a
    // one-point skip has one to take. A cap of two that removed nothing leaves the gap claim vacuous.
    if (NOT TestTrue(FString::Printf(
        TEXT("a span cap of two removes at least one point of the polyline [%s]"), *Report),
        AtCapTwo.Num() < Input.Num()))
    { return false; }

    // Every point the pass kept, matched to the input point it IS - exact equality, in order, indices
    // strictly increasing - which is the comparison the idempotence pin makes and for the same reason:
    // the pass either kept a point or it did not, and moving one is not something it may do.
    auto KeptIndices = TArray<int32>{};
    auto Cursor = 0;
    auto EveryKeptPointIsAnInputPoint = true;

    for (const auto& Kept : AtCapTwo)
    {
        auto Found = int32{INDEX_NONE};

        for (auto Index = Cursor; Index < Input.Num(); ++Index)
        {
            if (Input[Index] == Kept)
            {
                Found = Index;

                break;
            }
        }

        if (Found == INDEX_NONE)
        {
            EveryKeptPointIsAnInputPoint = false;

            break;
        }

        KeptIndices.Emplace(Found);
        Cursor = Found + 1;
    }

    if (NOT TestTrue(FString::Printf(
        TEXT("every point the cap-two answer kept is a point it was given, in order [%s]"), *Report),
        EveryKeptPointIsAnInputPoint && KeptIndices.Num() == AtCapTwo.Num()))
    { return false; }

    auto WidestGap = 0;

    for (auto Index = 1; Index < KeptIndices.Num(); ++Index)
    { WidestGap = FMath::Max(WidestGap, KeptIndices[Index] - KeptIndices[Index - 1]); }

    TestTrue(FString::Printf(
        TEXT("and no chord it took skipped more than one point: kept %d points, widest gap %d ")
        TEXT("(must be 1..2) [%s]"),
        KeptIndices.Num(), WidestGap, *Report),
        KeptIndices.Num() >= 2 && WidestGap >= 1 && WidestGap <= kWidestGapACapOfTwoMayLeave);

    // A wider reach offers the candidate loop every chord a narrower one offered and more, and it takes
    // the farthest that clears, so it can never come back holding more points.
    TestTrue(FString::Printf(
        TEXT("a wider reach never keeps more points than a narrower one [%s]"), *Report),
        AtNoCap.Num() <= AtCapTwo.Num());

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
    // The third shape - a dear plate the chord CROSSES with no waypoint on it, the design's O2
    // discriminator for the ray budget - is stated by Shortcut_BudgetSeesGroundNoWaypointStandsOn
    // below rather than here, and it is still SELECTED by measurement rather than authored - but no
    // longer from THIS slab. The sweep was run over the four-pillar route once (S11-8) and the slab
    // measured EMPTY: two rows cast, both at corner 2 on plate 10, the chord costing 3820.68 against
    // a 3820.21 ray budget - refused by 0.47, so O5 rightly never pays more for the ground than the
    // corridor paid - and the other corners are real corners around pillars whose chords the geometry
    // refuses outright. What is left is one clear chord across a 1.6 uu false corner, and on a
    // tile-wide plate the sign of "how much of a plate the chord crosses minus how much the detour
    // crosses" is a sub-uu matter there. That pin therefore keeps the sweep as its SELECTOR and runs
    // it on the purpose-built dear-band bend scene below, where a real bend has a clear chord; it
    // still fails loudly where no row discriminates.
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

    /**
     * One UNCAPPED priced ray, answering what the ground between two points cost - and nothing where
     * the ray did not come back clear.
     *
     * A _MaxCost of zero is the raycast's own "no cap", which is what makes two of these comparable:
     * each is what the ground actually costs rather than what fitted inside a budget. A refused ray
     * has no price to report, and a refusal is not a zero.
     */
    auto Cast_PricedRay(
        const FCk_GroundNav_Field&          InField,
        const FVector&                      InFrom,
        const FVector&                      InTo,
        const FCk_GroundNav_PathCostParams& InCost,
        const FCk_GroundNav_QueryAgent&     InAgent) -> TOptional<double>
    {
        auto Query = FCk_GroundNav_RaycastQuery{};

        Query._Start = InFrom;
        Query._End = InTo;
        Query._StartVerticalToleranceUu = kStepHeight;
        Query._Agent = InAgent;
        Query._PlateCostMultipliers = InCost._PlateCostMultipliers;
        Query._UseBakedPlateCost = true;
        Query._MaxCost = 0.0f;

        const auto Answer = Get_SurfaceRaycast(InField, Query);

        if (NOT Answer.Get_IsClear())
        { return {}; }

        return static_cast<double>(Answer._AccumulatedCost);
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
    // stated here; Shortcut_BudgetSeesGroundNoWaypointStandsOn below states it on its own scene (the
    // dear-band bend - this slab measured empty), over a (corner, plate) pair it selects by measuring
    // the three rays.
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

namespace ck_test_groundnav_pathshortcut_dearband
{
    using namespace ck_test_groundnav_pathshortcut;

    // THE SCENE THE O2 PIN SWEEPS, and the one thing it is for: a route with a REAL bend whose chord is
    // clear ground. The four-pillar slab offers one or the other and never both - its corners are real
    // corners around pillars, so the chords that would span them cross a pillar and the raycast refuses
    // them before any budget is consulted, and its one clear chord cuts a 1.6 uu false corner where the
    // whole trade lives under a unit.
    //
    // So the bend is bought in the SEARCH instead of authored into the geometry. The floor is the
    // four-pillar slab's own floor box and NOTHING else - no pillars - and the search query prices the
    // one tile sitting on the direct line at 100. A* buys the way round it, the funnel bends at that
    // tile's corners, and the ground under the bend is unbroken slab: a price artefact, not a wall.

    // The four-pillar posts' own X, and a Y in row R2: 380 uu north of that row's south edge and 420 uu
    // south of its north edge, so the cheaper way round the priced tile is SOUTH through R1 and what
    // comes back is a bend rather than a straight run.
    const auto kDearBandWestPost = FVector{-kFourPillarPostXUu, 380.0, kGroundZ};
    const auto kDearBandEastPost = FVector{kFourPillarPostXUu, 380.0, kGroundZ};

    // The middle of C2xR2 - the tile on the direct line whose plate the SEARCH prices, and the one the
    // POST table deliberately leaves at 1.0.
    const auto kDearBandBentTileProbe = FVector{0.0, 400.0, kGroundZ};

    // Far past the crossover, the same reading the priced-band pin's own multiplier has: enough that
    // A* buys the whole way round the tile rather than clipping a corner of it.
    constexpr auto kDearBandBendMultiplier = 100.0f;

    // How far off the straight line between the posts an interior point has to stand before the answer
    // counts as a bend. Well under the ~404 uu the funnel apexes are expected to measure, and well over
    // the 1.6 uu false corner the four-pillar slab offered.
    constexpr auto kDearBandBentOffTheLineUu = 200.0;

    /**
     * The four-pillar slab's FLOOR and nothing else.
     *
     * Copied box for box from Test_GroundNav_QueryFixtures.h rather than shared, because what this
     * scene needs is the slab WITHOUT the pillars and a fixture helper that took a flag would make one
     * scene answer for two claims.
     */
    auto Make_DearBandBendScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{
            FVector{-kFourPillarSlabHalfXUu, -kFourPillarSlabHalfYUu, kFourPillarSlabBottomZ},
            FVector{kFourPillarSlabHalfXUu, kFourPillarSlabHalfYUu, kGroundZ}});

        return Boxes;
    }

    /**
     * Baked with the FOUR-PILLAR params, which is what puts the tile grid where the posts assume it is.
     *
     * Tiles are laid from the params' own _OriginXY (CkGroundNav_Field.cpp:86-88), and those params put
     * the origin at (-2000, -1600) with 5x4 tiles of 800. Make_QueryParams is a 2x2 field at the world
     * origin and would put every number below on different ground.
     */
    auto Bake_DearBandBend(
        FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_DearBandBendScene(), Make_FourPillarParams(), *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    /** How far a point stands off the straight line between the two posts, in XY. */
    auto Get_OffTheStraightLineUu(
        const FVector& InPoint) -> double
    {
        const auto Along = FVector2D{
            kDearBandEastPost.X - kDearBandWestPost.X, kDearBandEastPost.Y - kDearBandWestPost.Y};

        const auto ToPoint = FVector2D{
            InPoint.X - kDearBandWestPost.X, InPoint.Y - kDearBandWestPost.Y};

        const auto LengthUu = Along.Size();

        if (LengthUu <= 0.0)
        { return ToPoint.Size(); }

        return FMath::Abs(FVector2D::CrossProduct(Along, ToPoint)) / LengthUu;
    }
}

// --------------------------------------------------------------------------------------------------------------------

// WHAT THIS CLAIMS. The ray budget prices the ground the replaced stretch actually CROSSES, so a chord
// running over dear ground NO waypoint of it stands on is admitted whenever the detour it replaces
// crosses at least as much of that ground - which the retired arithmetic, the replaced stretch's XY
// length times the greater of its two ENDPOINTS' multipliers, cannot see and therefore refuses.
//
// THE TWO INEQUALITIES, IN WORDS. The chord's own priced ray costs MORE than the two replaced segments
// measured end to end at the endpoint multiplier - which is 1.0 here - and that is the retired budget
// refusing. And the chord's priced ray costs no more than those two segments' OWN priced rays added
// together, which is the shipped budget admitting. A row where both hold is a case the rewrite decides
// differently from what it replaced, and that difference is the whole of the claim.
//
// WHY THE PLATE MUST BE ONE NO WAYPOINT STANDS ON. It is what holds the endpoint-max at 1.0, so the two
// inequalities are about the ground BETWEEN the points rather than about the prices of the points
// themselves; a dear plate under an ENDPOINT is the case the pin above already states, from both sides.
//
// WHY THIS SCENE AND NOT THE FOUR-PILLAR SLAB. The sweep below was run over that slab once (S11-8) and
// it measured EMPTY: rows cast 2, endpoint-max REFUSES 2, ray budget ADMITS 0, both 0. Both rows were
// corner 2 on plate 10 - near->dropped 615.76, dropped->far 3204.45, near->far 3820.68, plain detour
// 1420.21 - so the chord came out 0.47 uu the wrong side of a 3820.21 ray budget. The slab's other
// corners are real corners around pillars and the geometry refuses their chords outright, which leaves
// exactly one clear chord, across a 1.6 uu false corner; on a tile-wide plate the sign of "chord
// crossing minus detour crossing" is a sub-uu matter there. The pin keeps its sweep as the SELECTOR and
// moves it to a scene where a real bend has a clear chord.
//
// HOW THE BEND IS BOUGHT. The search honours _Cost._PlateCostMultipliers - CkGroundNav_PathSearch.cpp:304
// copies the table into the shared search data and CkGroundNav_PlatePortalGraph.cpp:234 applies it per
// plate - so pricing the ONE tile on the direct line at 100 in the SEARCH query makes A* route around it
// and the funnel bend at that tile's corners, which the corner offset then pushes a further radius off.
//
// AND WHY THE POST TABLE DOES NOT PRICE THAT TILE. The table the pass and the fill price with is a POST
// param, and it is a different table. It prices ONLY the swept BAND tile, at 4x, and leaves the bent
// tile at 1.0 - which is the whole trade: the chord runs cheap across the ground the corridor was
// expensive on, while the detour crosses the band the long way and the chord only clips its corner.
//
// THE GRID, BECAUSE THE POSTS ARE PLACED ON IT. Columns C0 [-2000,-1200) C1 [-1200,-400) C2 [-400,400)
// C3 [400,1200) C4 [1200,2000); rows R0 [-1600,-800) R1 [-800,0) R2 [0,800) R3 [800,1600). The posts
// stand at Y 380 in R2, nearer its south edge, so the way round C2xR2 goes south through R1.
//
// WHAT IS EXPECTED, SO A RED CAN BE READ RATHER THAN RE-MEASURED BLIND. Corridor C0R2 -> C1R2 -> C1R1 ->
// C2R1 -> C3R1 -> C3R2 -> C4R2; funnel apexes at C2xR2's south corners (-400, 0) and (400, 0), pushed by
// the corner offset (K 1.0 x radius 34) to about A1 (-424, -24) and A2 (424, -24); pre-shortcut polyline
// [W, A1, A2, E]. The BAND is C2xR1: the detour's second segment runs its whole 800 uu at Y about -24,
// the chord W->A2 enters R1 only at X about 301 and crosses about 101 uu of it, and no waypoint stands
// on it (A1 is in C1xR1, A2 in C3xR1, W in C0xR2). Under a post table pricing C2xR1 at 4x, the chord
// prices at about 2416 against a plain detour of about 2139 - the endpoint-max REFUSING by about 276 -
// and against about 4539 of summed segment rays, which the ray budget ADMITS by about 2120.
//
// WHY NOT A WALL-BENT CORNER, AND WHY NOT THE SLOPE. A corner that bends around geometry has that
// geometry between its two neighbours, so the chord is refused by the raycast before any budget is
// consulted - which is what every other corner of the four-pillar route measured. And the surface ray
// charges nothing for slope, so a pin built on the ramp would be about the ray and the fill disagreeing
// rather than about the budget.
//
// AND WHY THE PLATE IS STILL MEASURED RATHER THAN AUTHORED. The numbers above are what the scene is
// built to produce, not what the pin asserts: it sweeps the route's own interior corners, probes the
// chord and the two replaced segments for candidate plates, casts the three rays, and takes the first
// pair that discriminates. A sweep that finds none FAILS rather than skipping: a fixture that stopped
// hosting the case has to say so.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutBudgetSeesGroundNoWaypointStandsOn,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_BudgetSeesGroundNoWaypointStandsOn",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutBudgetSeesGroundNoWaypointStandsOn::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;
    using namespace ck_test_groundnav_pathshortcut_dearband;
    using namespace ck_test_groundnav_pathshortcut_dearendpoint;

    // The near and far ends with the corner between them gone: the answer that says the chord was taken.
    constexpr auto kTheChordAlone = 2;

    // Enough that a row is decided by the ground rather than by the last bits of a float - the numbers
    // these rays answer with run into the thousands.
    constexpr auto kMarginUu = 1.0;

    constexpr auto kFewestPointsWithAnInterior = 3;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the dear-band bend scene bakes"), Bake_DearBandBend(Field)))
    { return false; }

    const auto BentPlate = Get_PlateAt(*Field, kDearBandBentTileProbe);

    if (NOT TestTrue(TEXT("the tile on the direct line is ground a body can stand on"),
        BentPlate != INDEX_NONE))
    { return false; }

    // ONE search, and the ONLY table the SEARCH sees: the tile on the direct line priced at 100, which
    // is what buys the bend. Every table after this is a POST param, so each row below prices one
    // corridor differently rather than comparing two routes.
    auto SearchCost = Make_Cost(kShortcutUnbounded);
    SearchCost._PlateCostMultipliers.Add(BentPlate, kDearBandBendMultiplier);

    const auto Result = Get_Path(Field, Make_PathQuery(
        kDearBandWestPost, kDearBandEastPost, kFourPillarAgentRadiusUu, SearchCost));

    if (NOT TestEqual(TEXT("the scene answers a west-east crossing"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto Input = Get_PreShortcutLocations(Result, *Field, kFourPillarAgentRadiusUu);
    const auto PinnedList = Get_PinnedWaypoints(Result);
    const auto Agent = Make_Agent(kFourPillarAgentRadiusUu);

    const auto InputReport = FString::Printf(
        TEXT("[SHORTCUT-O2] bent tile plate %d at %.1f: pre-shortcut %s"),
        BentPlate, static_cast<double>(kDearBandBendMultiplier), *Get_WaypointReport(Input));

    ck::groundnav::Display(TEXT("{}"), InputReport);

    if (NOT TestTrue(FString::Printf(
        TEXT("the offset stages gave a polyline with an interior corner to sweep [%s]"), *InputReport),
        Input.Num() >= kFewestPointsWithAnInterior))
    { return false; }

    // THE PRECONDITION THE WHOLE SWEEP RESTS ON: the search BENT. A straight answer means the priced
    // tile never reached the corridor - the bend was not bought - and the pin has nothing to say rather
    // than something to be quiet about.
    auto FurthestOffTheLineUu = 0.0;

    for (auto Index = 1; Index < Input.Num() - 1; ++Index)
    { FurthestOffTheLineUu = FMath::Max(FurthestOffTheLineUu, Get_OffTheStraightLineUu(Input[Index])); }

    if (NOT TestTrue(FString::Printf(
        TEXT("the priced tile bent the route: an interior point stands %.2f uu off the straight line, ")
        TEXT("and %.2f is the least that counts [%s]"),
        FurthestOffTheLineUu, kDearBandBentOffTheLineUu, *InputReport),
        FurthestOffTheLineUu > kDearBandBentOffTheLineUu))
    { return false; }

    // Where along the chord the dear plate is looked for. Three points rather than one because a chord
    // crosses several plates and only some of them are ones no waypoint of that chord stands on.
    const auto ProbeFractions = TArray<double>{0.25, 0.5, 0.75};

    auto Rows = TArray<FString>{};

    auto RowsCast = 0;
    auto RowsTheEndpointMaxRefuses = 0;
    auto RowsTheRayBudgetAdmits = 0;
    auto RowsWhereBothHold = 0;

    auto TakenCorner = int32{INDEX_NONE};
    auto TakenPlate = int32{INDEX_NONE};
    auto TakenUniformCount = 0;
    auto TakenNumbers = FString{};

    for (auto Corner = 1; Corner < Input.Num() - 1 && TakenCorner == INDEX_NONE; ++Corner)
    {
        // A pinned point is a place the body passes THROUGH, so no chord may span it and there is
        // nothing at this corner to measure.
        if (PinnedList.Contains(Input[Corner]))
        { continue; }

        const auto Near = Input[Corner - 1];
        const auto Dropped = Input[Corner];
        const auto Far = Input[Corner + 1];

        const auto NearPlate = Get_PlateAt(*Field, Near);
        const auto DroppedPlate = Get_PlateAt(*Field, Dropped);
        const auto FarPlate = Get_PlateAt(*Field, Far);

        if (NearPlate == INDEX_NONE || DroppedPlate == INDEX_NONE || FarPlate == INDEX_NONE)
        { continue; }

        // WHERE THE CANDIDATE PLATES COME FROM, and why the chord's own probes are not enough. The
        // three fractions sample the CHORD, which finds a band the chord crosses; but the case the ray
        // budget is for is a band the DETOUR crosses far more of than the chord does, and a chord that
        // merely clips the corner of such a band may sample none of it at any fraction. The two
        // replaced segments' midpoints name that ground directly: it is the ground the ray budget sums.
        auto Probes = TArray<TPair<FString, FVector>>{};

        for (const auto Fraction : ProbeFractions)
        {
            Probes.Emplace(
                FString::Printf(TEXT("f %.2f"), Fraction), Near + ((Far - Near) * Fraction));
        }

        Probes.Emplace(FString{TEXT("seg1 mid")}, (Near + Dropped) * 0.5);
        Probes.Emplace(FString{TEXT("seg2 mid")}, (Dropped + Far) * 0.5);

        // Two probes landing on one plate are one row, not two: the row is about the PLATE, and casting
        // it twice would double every count the loud failure below reports.
        auto PlatesAlreadyCast = TSet<int32>{};

        for (const auto& Probe : Probes)
        {
            const auto ProbePlate = Get_PlateAt(*Field, Probe.Value);

            // The plate must be one NO waypoint of the chord stands on, which is also what keeps the
            // endpoint-max at 1.0 and the two inequalities about the ground between the points.
            if (ProbePlate == INDEX_NONE || ProbePlate == NearPlate ||
                ProbePlate == DroppedPlate || ProbePlate == FarPlate)
            { continue; }

            if (PlatesAlreadyCast.Contains(ProbePlate))
            { continue; }

            PlatesAlreadyCast.Add(ProbePlate);

            // The POST table, and it prices ONLY this band plate. The tile the SEARCH priced at 100 is
            // deliberately absent from it and stands at 1.0 here - that is what makes the chord across
            // the corridor's inside cheap, and the pass and the fill both price with THIS table.
            const auto Table = Make_DearEndpointCost(kShortcutUnbounded, ProbePlate);

            const auto NearToDropped = Cast_PricedRay(*Field, Near, Dropped, Table, Agent);
            const auto DroppedToFar = Cast_PricedRay(*Field, Dropped, Far, Table, Agent);
            const auto NearToFar = Cast_PricedRay(*Field, Near, Far, Table, Agent);

            if (NOT NearToDropped.IsSet() || NOT DroppedToFar.IsSet() || NOT NearToFar.IsSet())
            {
                Rows.Emplace(FString::Printf(
                    TEXT("[SHORTCUT-O2] corner %d %s plate %d: a ray was refused, row not cast"),
                    Corner, *Probe.Key, ProbePlate));

                continue;
            }

            ++RowsCast;

            const auto NearToDroppedUu = NearToDropped.GetValue();
            const auto DroppedToFarUu = DroppedToFar.GetValue();
            const auto NearToFarUu = NearToFar.GetValue();

            // What the RETIRED budget would have measured: the replaced stretch's XY length times the
            // greater of the two endpoints' multipliers, which is 1.0 because the dear plate is one
            // neither of them stands on.
            const auto PlainDetourUu = FVector::Dist2D(Near, Dropped) + FVector::Dist2D(Dropped, Far);

            const auto EndpointMaxRefuses = NearToFarUu > PlainDetourUu + kMarginUu;
            const auto RayBudgetAdmits = NearToFarUu + kMarginUu <= NearToDroppedUu + DroppedToFarUu;

            RowsTheEndpointMaxRefuses += EndpointMaxRefuses ? 1 : 0;
            RowsTheRayBudgetAdmits += RayBudgetAdmits ? 1 : 0;

            Rows.Emplace(FString::Printf(
                TEXT("[SHORTCUT-O2] corner %d %s plate %d: near->dropped %.2f | dropped->far %.2f | ")
                TEXT("near->far %.2f | plain detour %.2f | endpoint-max %s | ray budget %s"),
                Corner, *Probe.Key, ProbePlate,
                NearToDroppedUu, DroppedToFarUu, NearToFarUu, PlainDetourUu,
                EndpointMaxRefuses ? TEXT("REFUSES") : TEXT("ADMITS"),
                RayBudgetAdmits ? TEXT("ADMITS") : TEXT("REFUSES")));

            if (NOT (EndpointMaxRefuses && RayBudgetAdmits))
            { continue; }

            ++RowsWhereBothHold;

            // A three-point input, with nothing pinned: its two ends are pinned by construction, so the
            // one decision the pass has left is whether to take the chord across the corner between them.
            const auto ChordInput = TArray<FVector>{Near, Dropped, Far};
            const auto NothingPinned = TArray<FVector>{};

            const auto Chord = Get_Shortcut(
                ChordInput, NothingPinned, *Field, Table, Agent, kStepHeight);

            // The fill conjunct is entitled to refuse a row the ray budget admits, and that refusal is
            // an answer rather than a defect - so the row records it and the sweep keeps looking.
            if (Chord.Num() != kTheChordAlone)
            {
                Rows.Last() += TEXT(" | chord REFUSED past the rays (the fill conjunct, or the capped ray)");

                continue;
            }

            TakenCorner = Corner;
            TakenPlate = ProbePlate;

            // The CONTROL: the same three points at a uniform table. The chord is clear ground either
            // way, so the dear plate is the only thing that varies between the two runs.
            TakenUniformCount = Get_Shortcut(
                ChordInput, NothingPinned, *Field, Make_Cost(kShortcutUnbounded),
                Agent, kStepHeight).Num();

            TakenNumbers = FString::Printf(
                TEXT("near->dropped %.2f, dropped->far %.2f, near->far %.2f, plain detour %.2f"),
                NearToDroppedUu, DroppedToFarUu, NearToFarUu, PlainDetourUu);

            break;
        }
    }

    for (const auto& Row : Rows)
    { ck::groundnav::Display(TEXT("{}"), Row); }

    // NEVER VACUOUS AND NEVER SKIPPED. A sweep that measured every corner of the route and found no
    // pair that discriminates has not shown the budget is wrong - it has shown this fixture no longer
    // hosts the case, and the counts say which half of the pair went missing.
    if (TakenCorner == INDEX_NONE)
    {
        TestTrue(FString::Printf(
            TEXT("the sweep found a corner and a plate that discriminate: rows cast %d, endpoint-max ")
            TEXT("REFUSES %d, ray budget ADMITS %d, both %d - the dear-band bend hosts no O2 case at ")
            TEXT("%.1fx; re-measure the posts and the band from the rows above"),
            RowsCast, RowsTheEndpointMaxRefuses, RowsTheRayBudgetAdmits, RowsWhereBothHold,
            static_cast<double>(kDearEndpointMultiplier)),
            false);

        return false;
    }

    ck::groundnav::Display(TEXT("{}"), FString::Printf(
        TEXT("[SHORTCUT-O2] TAKEN at corner %d plate %d: %s"), TakenCorner, TakenPlate, *TakenNumbers));

    // THE CLAIM, on the row the sweep selected: the chord crosses dear ground no waypoint of it stands
    // on, the detour it replaces crosses at least as much of that ground, and the pass takes it. That
    // claim is established by the selection itself - the sweep above stops and records TAKEN only on a
    // row where Chord.Num() == kTheChordAlone - so the assertions with teeth are the loud fail above
    // when the sweep finds no TAKEN row, and the uniform-table control below.
    TestEqual(FString::Printf(
        TEXT("and the same three points come back as two at a uniform table, so the dear ground is the ")
        TEXT("only variable [corner %d plate %d: %s]"),
        TakenCorner, TakenPlate, *TakenNumbers),
        TakenUniformCount, kTheChordAlone);

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
