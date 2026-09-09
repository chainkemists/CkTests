// Strict-cell postprocess preserves the path collector's exact edges. These rows are already
// collision-safe under the search snapshot, so they must not be reshaped by the portal passes.

#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_strictcellpostprocess
{
    using ck::groundnav::ECk_GroundNav_CellRouteEdgeKind;
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::ECk_GroundNav_LinkWaypointRole;
    using ck::groundnav::ECk_GroundNav_PathRouteKind;
    using ck::groundnav::FCk_GroundNav_CellRouteEdge;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Get_Path;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    using ck_test_groundnav_queryfixtures::Bake_FlatScene;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;

    constexpr auto kLinkStableId = 91;
    constexpr auto kAgentRadiusUu = 50.0f;

    const auto kStart = FVector{100.0, 100.0, kGroundZ};
    const auto kLinkEntry = FVector{300.0, 100.0, kGroundZ};
    const auto kLinkExit = FVector{600.0, 100.0, kGroundZ};
    const auto kGoal = FVector{900.0, 100.0, kGroundZ};
    // Bake_FlatScene publishes one 800 uu tile. Keep the real public-search end inside that field;
    // kGoal above remains the deliberately synthetic end used by the post-process-only rows below.
    const auto kPublicSearchGoal = FVector{700.0, 100.0, kGroundZ};

    auto MakeEdge(
        const FVector&                   InFrom,
        const FVector&                   InTo,
        ECk_GroundNav_CellRouteEdgeKind InKind = ECk_GroundNav_CellRouteEdgeKind::Ordinary)
        -> FCk_GroundNav_CellRouteEdge
    {
        auto Edge = FCk_GroundNav_CellRouteEdge{};
        Edge._FromPoint = InFrom;
        Edge._ToPoint = InTo;
        Edge._Kind = InKind;
        Edge._Cost = static_cast<float>(FVector::Dist(InFrom, InTo));
        return Edge;
    }

    auto MakeLinkEdge(
        const FVector& InFrom,
        const FVector& InTo,
        int32          InStableId = kLinkStableId) -> FCk_GroundNav_CellRouteEdge
    {
        auto Edge = MakeEdge(InFrom, InTo, ECk_GroundNav_CellRouteEdgeKind::Link);
        Edge._LinkStableId = InStableId;
        Edge._LinkDirection = ECk_GroundNav_LinkDirection::Forward;
        return Edge;
    }

    auto MakeStrictResult(
        const FVector&                         InStart,
        const FVector&                         InGoal,
        const TArray<FCk_GroundNav_CellRouteEdge>& InEdges) -> FCk_GroundNav_PathResult
    {
        auto Result = FCk_GroundNav_PathResult{};
        Result._Status = ECk_GroundNav_PathStatus::Ready;
        Result._RouteKind = ECk_GroundNav_PathRouteKind::StrictCell;
        Result._StartPoint = InStart;
        Result._GoalPoint = InGoal;
        Result._CellRoute = InEdges;
        return Result;
    }

    auto MakePostParams(const FVector& InAgentLocation) -> FCk_GroundNav_PathPostParams
    {
        auto Params = FCk_GroundNav_PathPostParams{};
        Params._Agent._RadiusUu = kAgentRadiusUu;
        Params._AgentLocation = InAgentLocation;
        Params._VerticalToleranceUu = kStepHeight;
        return Params;
    }

    auto MakeDiscSnapshot(const FVector& InCentre, float InRadiusUu) -> FCk_GroundNav_DynamicObstacleSnapshot
    {
        auto Disc = FCk_GroundNav_DynamicObstacleDisc{};
        Disc._Centre = InCentre;
        Disc._RadiusUu = InRadiusUu;
        Disc._VerticalHalfExtentUu = 50.0f;
        const auto Discs = TArray<FCk_GroundNav_DynamicObstacleDisc>{Disc};
        const auto Snapshot = Try_MakeDynamicObstacleSnapshot(
            Discs,
            TConstArrayView<ck::groundnav::FCk_GroundNav_DynamicObstacleObb>{});
        return Snapshot.IsSet() ? Snapshot.GetValue() : FCk_GroundNav_DynamicObstacleSnapshot{};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_RealStrictSearchRetainsResolvedEnds,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.RealStrictSearchRetainsResolvedEnds",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_RealStrictSearchRetainsResolvedEnds::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    const auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(*Field))) { return false; }

    auto Query = FCk_GroundNav_PathQuery{};
    Query._Start = kStart;
    Query._Goal = kPublicSearchGoal;
    Query._VerticalToleranceUu = kStepHeight;
    Query._Agent._RadiusUu = kAgentRadiusUu;
    // A valid, out-of-route snapshot selects the strict graph without blocking its direct answer.
    Query._DynamicObstacles = MakeDiscSnapshot(FVector{100.0, 700.0, kGroundZ}, 25.0f);

    const auto Result = Get_Path(Field, Query);
    if (NOT TestEqual(TEXT("the in-field public query resolves before graph selection is inspected"),
        Result._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }
    if (NOT TestEqual(TEXT("the public search selected its strict graph"),
        Result._RouteKind, ECk_GroundNav_PathRouteKind::StrictCell)) { return false; }
    if (NOT TestTrue(TEXT("the real predecessor rows are present"), Result._CellRoute.Num() > 0))
    { return false; }

    const auto Plan = Get_PathPlan(Result, *Field, MakePostParams(kStart));
    if (NOT TestEqual(TEXT("the real strict answer remains Ready through formatting"),
        Plan._Status, ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("the formatter retains the graph's resolved source and goal"),
        Plan._Waypoints[0]._Location == Result._StartPoint &&
        Plan._Waypoints.Last()._Location == Result._GoalPoint);
    TestTrue(TEXT("the rich plan preserves the strict graph's total price"),
        FMath::IsNearlyEqual(Plan._Waypoints.Last()._CostFromStart, static_cast<double>(Result._SearchCost), 0.01));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_ExactLinkRowsSurviveAndSourceIsNotSkipped,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.ExactLinkRowsSurviveAndSourceIsNotSkipped",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_ExactLinkRowsSurviveAndSourceIsNotSkipped::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    auto Link = MakeEdge(kLinkEntry, kLinkExit, ECk_GroundNav_CellRouteEdgeKind::Link);
    Link._LinkStableId = kLinkStableId;
    Link._LinkDirection = ECk_GroundNav_LinkDirection::Forward;
    Link._Cost = 777.0f;
    const auto Result = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, kLinkEntry), Link, MakeEdge(kLinkExit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});

    const auto Plan = Get_PathPlan(Result, Field, MakePostParams(kStart));
    if (NOT TestEqual(TEXT("the strict route remains Ready"), Plan._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }
    if (NOT TestEqual(TEXT("the source, link ends, and goal all remain"), Plan._Waypoints.Num(), 4))
    { return false; }

    TestTrue(TEXT("the source and goal are exact"), Plan._Waypoints[0]._Location == kStart &&
        Plan._Waypoints.Last()._Location == kGoal);
    TestTrue(TEXT("the entry preserves authored stable identity and direction"),
        Plan._Waypoints[1]._Location == kLinkEntry && Plan._Waypoints[1]._LinkId == kLinkStableId &&
        Plan._Waypoints[1]._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry &&
        Plan._Waypoints[1]._LinkEntryDirection == ECk_GroundNav_LinkDirection::Forward);
    TestTrue(TEXT("the exit preserves the same authored traversal"),
        Plan._Waypoints[2]._Location == kLinkExit && Plan._Waypoints[2]._LinkId == kLinkStableId &&
        Plan._Waypoints[2]._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit &&
        Plan._Waypoints[2]._LinkEntryDirection == ECk_GroundNav_LinkDirection::Forward);
    TestTrue(TEXT("the exact predecessor prices, including the link price, survive"),
        Plan._LengthUu > 0.0 && FMath::IsNearlyEqual(
            Plan._Waypoints.Last()._CostFromStart,
            static_cast<double>(Result._CellRoute[0]._Cost + Link._Cost + Result._CellRoute[2]._Cost)));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_DynamicSnapshotRefusesShortcutChord,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.DynamicSnapshotRefusesShortcutChord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_DynamicSnapshotRefusesShortcutChord::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    const auto Detour = FVector{500.0, 400.0, kGroundZ};
    auto Result = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, Detour), MakeEdge(Detour, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    Result._DynamicObstacles = MakeDiscSnapshot(FVector{500.0, 100.0, kGroundZ}, 110.0f);
    TestEqual(TEXT("the tempting source-goal chord enters the captured union"),
        Get_DynamicUnionEdge(Result._DynamicObstacles, kStart, kGoal).GetValue(),
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);

    const auto Plan = Get_PathPlan(Result, Field, MakePostParams(kStart));
    if (NOT TestEqual(TEXT("the snapshot-safe strict route remains Ready"), Plan._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }
    TestEqual(TEXT("no shortcut deletes the collector's detour row"), Plan._Waypoints.Num(), 3);
    TestTrue(TEXT("the middle point remains the collector's exact detour"), Plan._Waypoints[1]._Location == Detour);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_InsideStartEscapesOnceWithoutReentry,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.InsideStartEscapesOnceWithoutReentry",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_InsideStartEscapesOnceWithoutReentry::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    const auto Exit = FVector{400.0, 100.0, kGroundZ};
    auto Result = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, Exit), MakeEdge(Exit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    Result._DynamicObstacles = MakeDiscSnapshot(kStart, 150.0f);
    TestEqual(TEXT("the first strict edge is one monotonic escape"),
        Get_DynamicUnionEdge(Result._DynamicObstacles, kStart, Exit).GetValue(),
        ECk_GroundNav_DynamicUnionEdge::ExitsOnce);

    const auto Plan = Get_PathPlan(Result, Field, MakePostParams(kStart));
    if (NOT TestEqual(TEXT("the one-time escape remains walkable"), Plan._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }
    TestEqual(TEXT("the source remains available to express the escape"), Plan._Waypoints[0]._Location, kStart);
    TestEqual(TEXT("the final row remains the exact goal"), Plan._Waypoints.Last()._Location, kGoal);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_InsideStartCannotReenterAfterEscape,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.InsideStartCannotReenterAfterEscape",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_InsideStartCannotReenterAfterEscape::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    const auto Outside = FVector{400.0, 300.0, kGroundZ};
    auto Result = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, Outside), MakeEdge(Outside, kStart),
        MakeEdge(kStart, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    Result._DynamicObstacles = MakeDiscSnapshot(kStart, 150.0f);

    const auto Plan = Get_PathPlan(Result, Field, MakePostParams(kStart));
    TestEqual(TEXT("a strict route that re-enters after its one allowed escape is refused"),
        Plan._Status, ECk_GroundNav_PathStatus::Blocked);
    TestTrue(TEXT("the refused route publishes no partial waypoints"), Plan._Waypoints.IsEmpty());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_AuthoredLinkMayCrossDynamicInterior,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.AuthoredLinkMayCrossDynamicInterior",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_AuthoredLinkMayCrossDynamicInterior::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    auto Result = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, kLinkEntry), MakeLinkEdge(kLinkEntry, kLinkExit),
        MakeEdge(kLinkExit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    Result._DynamicObstacles = MakeDiscSnapshot(FVector{450.0, 100.0, kGroundZ}, 60.0f);

    TestEqual(TEXT("the authored traversal crosses the disc interior"),
        Get_DynamicUnionEdge(Result._DynamicObstacles, kLinkEntry, kLinkExit).GetValue(),
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);
    const auto Plan = Get_PathPlan(Result, Field, MakePostParams(kStart));
    if (NOT TestEqual(TEXT("the complete authored traversal remains walkable"),
        Plan._Status, ECk_GroundNav_PathStatus::Ready)) { return false; }
    TestTrue(TEXT("the entry preserves its stable id and traversal direction"),
        Plan._Waypoints[1]._LinkId == kLinkStableId &&
        Plan._Waypoints[1]._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry &&
        Plan._Waypoints[1]._LinkEntryDirection == ECk_GroundNav_LinkDirection::Forward);
    TestTrue(TEXT("the exit preserves the same stable id and traversal direction"),
        Plan._Waypoints[2]._LinkId == kLinkStableId &&
        Plan._Waypoints[2]._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit &&
        Plan._Waypoints[2]._LinkEntryDirection == ECk_GroundNav_LinkDirection::Forward);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_AuthoredLinkCannotHideGroundLeg,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.AuthoredLinkCannotHideGroundLeg",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_AuthoredLinkCannotHideGroundLeg::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    const auto MakeResult = []()
    {
        return MakeStrictResult(kStart, kGoal, {
            MakeEdge(kStart, kLinkEntry), MakeLinkEdge(kLinkEntry, kLinkExit),
            MakeEdge(kLinkExit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    };

    auto BlockedApproach = MakeResult();
    BlockedApproach._DynamicObstacles = MakeDiscSnapshot(FVector{200.0, 100.0, kGroundZ}, 60.0f);
    const auto ApproachPlan = Get_PathPlan(BlockedApproach, Field, MakePostParams(kStart));
    TestEqual(TEXT("a blocked ground approach is refused"), ApproachPlan._Status, ECk_GroundNav_PathStatus::Blocked);
    TestTrue(TEXT("the blocked approach publishes no partial route"), ApproachPlan._Waypoints.IsEmpty());

    auto BlockedLanding = MakeResult();
    BlockedLanding._DynamicObstacles = MakeDiscSnapshot(FVector{750.0, 100.0, kGroundZ}, 60.0f);
    const auto LandingPlan = Get_PathPlan(BlockedLanding, Field, MakePostParams(kStart));
    TestEqual(TEXT("a blocked ground landing is refused"), LandingPlan._Status, ECk_GroundNav_PathStatus::Blocked);
    TestTrue(TEXT("the blocked landing publishes no partial route"), LandingPlan._Waypoints.IsEmpty());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_LinkCannotEscapeInitialUnionOrPublishMalformedMetadata,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.LinkCannotEscapeInitialUnionOrPublishMalformedMetadata",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_LinkCannotEscapeInitialUnionOrPublishMalformedMetadata::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    auto LinkEscape = MakeStrictResult(kStart, kGoal, {
        MakeLinkEdge(kStart, kLinkExit), MakeEdge(kLinkExit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    LinkEscape._DynamicObstacles = MakeDiscSnapshot(kStart, 60.0f);
    const auto EscapePlan = Get_PathPlan(LinkEscape, Field, MakePostParams(kStart));
    TestEqual(TEXT("an authored link cannot escape the initial covered union"),
        EscapePlan._Status, ECk_GroundNav_PathStatus::Blocked);
    TestTrue(TEXT("the refused link escape publishes no partial route"), EscapePlan._Waypoints.IsEmpty());

    auto MissingStableId = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, kLinkEntry), MakeLinkEdge(kLinkEntry, kLinkExit),
        MakeEdge(kLinkExit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    MissingStableId._CellRoute[1]._LinkStableId = INDEX_NONE;
    const auto MalformedPlan = Get_PathPlan(MissingStableId, Field, MakePostParams(kStart));
    TestEqual(TEXT("a link without stable identity is refused"),
        MalformedPlan._Status, ECk_GroundNav_PathStatus::Blocked);
    TestTrue(TEXT("malformed link metadata publishes zero waypoints"), MalformedPlan._Waypoints.IsEmpty());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictCellPostProcess_ChainedLinksRetainBothEndpointRoles,
    "CkTests.UnitTests.CkGroundNav.Path.StrictCellPostProcess.ChainedLinksRetainBothEndpointRoles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictCellPostProcess_ChainedLinksRetainBothEndpointRoles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_strictcellpostprocess;
    auto Field = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the flat field bakes"), Bake_FlatScene(Field))) { return false; }

    const auto Middle = FVector{500.0, 100.0, kGroundZ};
    auto Result = MakeStrictResult(kStart, kGoal, {
        MakeEdge(kStart, kLinkEntry), MakeLinkEdge(kLinkEntry, Middle, 91), MakeLinkEdge(Middle, kLinkExit, 92),
        MakeEdge(kLinkExit, kGoal, ECk_GroundNav_CellRouteEdgeKind::Terminal)});
    const auto Plan = Get_PathPlan(Result, Field, MakePostParams(kStart));
    if (NOT TestEqual(TEXT("the chained authored traversals remain walkable"),
        Plan._Status, ECk_GroundNav_PathStatus::Ready)) { return false; }
    if (NOT TestEqual(TEXT("the shared endpoint has distinct exit and entry rows"), Plan._Waypoints.Num(), 6))
    { return false; }
    TestTrue(TEXT("the first link retains its exit at the shared endpoint"),
        Plan._Waypoints[2]._Location == Middle && Plan._Waypoints[2]._LinkId == 91 &&
        Plan._Waypoints[2]._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit);
    TestTrue(TEXT("the second link retains its entry at the duplicated shared endpoint"),
        Plan._Waypoints[3]._Location == Middle && Plan._Waypoints[3]._LinkId == 92 &&
        Plan._Waypoints[3]._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry);
    return true;
}
