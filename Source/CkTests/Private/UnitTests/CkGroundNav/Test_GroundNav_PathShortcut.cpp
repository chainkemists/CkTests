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
        auto Funnelled = TArray<FVector>{};
        Get_Funnelled(InResult, InRadiusUu, Funnelled);

        const auto WithLinks = Get_WithLinkEndpointsEmitted(Funnelled, InResult);

        const auto Offset = Get_CornerOffset(
            WithLinks,
            Get_PinnedWaypoints(InResult),
            InField,
            kCornerOffsetK * InRadiusUu,
            Make_Agent(InRadiusUu),
            kStepHeight);

        return Get_SkipFirstWaypoint(Offset, InAgentLocation, InRadiusUu);
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

    // Both endpoints of the link are exactly the two points a chord has most to gain by spanning: the
    // string bends at each of them and the ground between them is clear. Exactly one pair, and not one
    // endpoint, is what says the pass split its span at every pinned point rather than dropping an end.
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
    // which the pass has no business doing.
    TestTrue(FString::Printf(TEXT("and never lowers it without also shortening the walk [%s]"), *Report),
        OnCost >= OffCost - kEpsilon || On._LengthUu <= Off._LengthUu + kEpsilon);

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

    auto Funnelled = TArray<FVector>{};
    Get_Funnelled(Result, kFourPillarAgentRadiusUu, Funnelled);

    if (NOT TestTrue(TEXT("the funnel gave a polyline to shorten"), Funnelled.Num() >= 2))
    { return false; }

    const auto Cost = Make_Cost(kShortcutUnbounded);
    const auto Agent = Make_Agent(kFourPillarAgentRadiusUu);
    const auto Pinned = Get_PinnedWaypoints(Result);

    const auto Once = Get_Shortcut(Funnelled, Pinned, *Field, Cost, Agent, kStepHeight);
    const auto Twice = Get_Shortcut(Once, Pinned, *Field, Cost, Agent, kStepHeight);

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT] funnelled %d, once %d, twice %d"),
        Funnelled.Num(), Once.Num(), Twice.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

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
    const auto Ends = TArray<FVector>{Funnelled[0], Funnelled.Last()};
    const auto EndsOnly = Get_Shortcut(Ends, Pinned, *Field, Cost, Agent, kStepHeight);

    TestTrue(TEXT("a route with no interior comes back element for element"),
        EndsOnly.Num() == Ends.Num() && EndsOnly[0] == Ends[0] && EndsOnly.Last() == Ends.Last());

    // Zero is off, not a span of zero - the same reading _CornerOffsetK = 0 already has.
    const auto Disabled = Get_Shortcut(
        Funnelled, Pinned, *Field, Make_Cost(kShortcutOff), Agent, kStepHeight);

    auto ChangedWhileOff = FMath::Abs(Disabled.Num() - Funnelled.Num());

    if (Disabled.Num() == Funnelled.Num())
    {
        for (auto Index = 0; Index < Funnelled.Num(); ++Index)
        {
            if (Disabled[Index] != Funnelled[Index])
            { ++ChangedWhileOff; }
        }
    }

    TestEqual(FString::Printf(TEXT("a span cap of zero changes nothing at all [%s]"), *Report),
        ChangedWhileOff, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_ShortcutRaycastCountIsStableAndRecorded,
    "CkTests.UnitTests.CkGroundNav.Path.Shortcut_RaycastCountIsStableAndRecorded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_ShortcutRaycastCountIsStableAndRecorded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathshortcut;

    // WHAT IS PINNED, AND WHY IT IS NOT THE RAYCAST COUNT. Get_Shortcut answers with a polyline and
    // nothing else, and FCk_GroundNav_QueryCost carries cells read and tiles touched but no count of
    // segments cast - so there is no raycast number to read here without inventing an API for one. What
    // IS deterministic and machine-independent is how many waypoints the pass consumed and produced on
    // a fixed scene, and that moves for every reason a raycast count would: a changed accept rule, a
    // changed budget, a changed corridor. Pinned as counts, in the manner
    // Test_GroundNav_ReferenceNumbers.cpp pins its search budgets.
    //
    // Every constant below is INDEX_NONE, which reports itself on the log and asserts nothing. They are
    // pinned from the first green run, and set back to INDEX_NONE whenever a deliberate change to the
    // pass is being re-measured before it is re-pinned.
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

    const auto Shortcut = Get_Shortcut(
        Funnelled, Get_PinnedWaypoints(Result), *Field, Make_Cost(kShortcutUnbounded),
        Make_Agent(kFourPillarAgentRadiusUu), kStepHeight);

    const auto Off = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutOff), kDistantAgentLocation));

    const auto On = Get_PathPlan(Result, *Field, Make_PostParams(
        kFourPillarAgentRadiusUu, Make_Cost(kShortcutUnbounded), kDistantAgentLocation));

    const auto Report = FString::Printf(
        TEXT("[SHORTCUT-BUDGET] four-pillar route: funnelled %d, shortcut %d, plan off %d, plan on %d, ")
        TEXT("length off %.2f, length on %.2f, expansions %d, cells read %d"),
        Funnelled.Num(), Shortcut.Num(), Off._Waypoints.Num(), On._Waypoints.Num(),
        Off._LengthUu, On._LengthUu, Result._ExpansionCount, Result._Cost._CellsRead);

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
