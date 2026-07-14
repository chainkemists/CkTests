#include "Misc/AutomationTest.h"

#include "CkAStar/Algorithm/CkAStar_Search.h"

#include "CkPathNetwork/Network/CkPathNetwork_Build.h"
#include "CkPathNetwork/Network/CkPathNetwork_RouteGraph.h"
#include "CkPathNetwork/Network/CkPathNetwork_Types.h"

// --------------------------------------------------------------------------------------------------------------------
// Routing-heuristic tests over FRouteGraph + CkAStar directly — no world, no navmesh, no ECS.
// These pin the core behaviors: emergent exit selection, direct-when-short, multiplier
// monotonicity, and reprice-driven exit demotion.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pathnetwork_route
{
    using namespace ck::pathnetwork;

    // One straight sidewalk from (0,0,0) to (4000,0,0).
    auto MakeStraightNetwork() -> FBuiltNetwork
    {
        auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
        Points.Add(FCk_PathNetwork_RibbonPoint{FVector{0, 0, 0}, 100.0f});
        Points.Add(FCk_PathNetwork_RibbonPoint{FVector{4000, 0, 0}, 100.0f});

        auto Ribbon = FCk_PathNetwork_Ribbon{Points};
        Ribbon.Set_RibbonId(FGuid::NewGuid());

        return Build_NetworkFromRibbons({Ribbon}, FCk_PathNetwork_BuildParams{});
    }

    auto AddOverlayProjection(FRouteGraphSharedData& InOutShared, const FBuiltNetwork& InNetwork, const FVector& InLocation) -> int32
    {
        const auto Projection = InNetwork.Project_OntoEdge(0, InLocation);
        const auto NewIndex = InOutShared._OverlayPoints.Add(
            FRouteOverlayPoint{0, Projection._DistAlong, Projection._Location});
        InOutShared._OverlayPointsByEdge.FindOrAdd(0).Add(NewIndex);
        return NewIndex;
    }

    auto RunSearch(const FRouteGraph& InGraph) -> ck::astar::TSearchResult<FRouteNodeId>
    {
        auto Search = ck::astar::TSearchState<FRouteNodeId, FRouteGraph>{
            InGraph,
            FRouteNodeId{ERouteNodeKind::Start, 0},
            FRouteNodeId{ERouteNodeKind::Goal, 0}};

        auto Params = ck::astar::FSearchParams{};
        Params.MaxIterationsPerTick = 100000;
        Search.ContinueSearch(Params);

        return Search.GetResult();
    }

    auto Count_OnNetworkSteps(const TArray<FRouteNodeId>& InPath) -> int32
    {
        auto Count = 0;
        for (const auto& Node : InPath)
        {
            if (Node._Kind == ERouteNodeKind::NetNode || Node._Kind == ERouteNodeKind::OverlayPoint)
            { ++Count; }
        }
        return Count;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_ExitSelection,
    "Ck.PathNetwork.Route.ExitSelection",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_ExitSelection::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    if (!TestEqual(TEXT("fixture built"), Network._Edges.Num(), 1))
    { return false; }

    // Agent near the ribbon's west end; goal PAST the east end, off to the side — the sidewalk
    // "ends but is not the destination". The route must ride the ribbon to its east end and only
    // then go off-path, and the exit choice must be emergent (both ends are offered).
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4600, 800, 0};

    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);   // projects to dist-along ~0
    const auto EastExit = AddOverlayProjection(*Shared, Network, GoalLocation); // projects to ~4000

    constexpr auto Multiplier = 3.0f;
    const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, Multiplier, Shared};

    const auto Result = RunSearch(Graph);
    TestTrue(TEXT("search completed"), Result.Status == ck::astar::ESearchStatus::Complete);

    // Expected winning route: Start -> west overlay -> east overlay -> Goal.
    // Cost ~ 100*3 (walk on) + 4000 (ribbon) + dist((4000,0),(4600,800))*3 (walk off = 1000*3).
    TestTrue(TEXT("route uses the network"), Count_OnNetworkSteps(Result.Path) >= 2);
    TestTrue(TEXT("route exits at the east end"),
        Result.Path.Contains(FRouteNodeId{ERouteNodeKind::OverlayPoint, EastExit}));

    const auto ExpectedCost = 100.0f * Multiplier + 4000.0f + 1000.0f * Multiplier;
    TestTrue(FString::Printf(TEXT("cost ~%.0f (got %.0f)"), ExpectedCost, Result.TotalCost),
        FMath::Abs(Result.TotalCost - ExpectedCost) < 50.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_DirectWhenShort,
    "Ck.PathNetwork.Route.DirectWhenShort",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_DirectWhenShort::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();

    // Crossing the street diagonally: direct euclidean*3 beats on/off/on via the ribbon.
    const auto StartLocation = FVector{1000, 300, 0};
    const auto GoalLocation = FVector{1200, -300, 0};

    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);
    AddOverlayProjection(*Shared, Network, GoalLocation);

    constexpr auto Multiplier = 3.0f;
    const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, Multiplier, Shared};

    const auto Result = RunSearch(Graph);
    TestTrue(TEXT("search completed"), Result.Status == ck::astar::ESearchStatus::Complete);

    // Direct: dist((1000,300),(1200,-300)) * 3 = ~632.5 * 3 = ~1897
    // Via ribbon: 300*3 + 200 + 300*3 = 2000 -> direct wins.
    TestEqual(TEXT("route is Start->Goal direct"), Result.Path.Num(), 2);
    TestEqual(TEXT("no on-network steps"), Count_OnNetworkSteps(Result.Path), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_MultiplierMonotonicity,
    "Ck.PathNetwork.Route.MultiplierMonotonicity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_MultiplierMonotonicity::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();

    // Same crossing as DirectWhenShort: at multiplier 3 the shortcut wins; raising the multiplier
    // to 10 must flip the SAME trip onto the sidewalk. That flip IS the tunable heuristic.
    const auto StartLocation = FVector{1000, 300, 0};
    const auto GoalLocation = FVector{1200, -300, 0};

    const auto RunWithMultiplier = [&](float InMultiplier)
    {
        auto Shared = MakeShared<FRouteGraphSharedData>();
        AddOverlayProjection(*Shared, Network, StartLocation);
        AddOverlayProjection(*Shared, Network, GoalLocation);

        const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, InMultiplier, Shared};
        return RunSearch(Graph);
    };

    const auto LowMultiplier = RunWithMultiplier(3.0f);
    const auto HighMultiplier = RunWithMultiplier(10.0f);

    TestEqual(TEXT("low multiplier cuts across"), Count_OnNetworkSteps(LowMultiplier.Path), 0);
    TestTrue(TEXT("high multiplier stays on the sidewalk"), Count_OnNetworkSteps(HighMultiplier.Path) >= 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_RepriceDemotesBlockedExit,
    "Ck.PathNetwork.Route.RepriceDemotesBlockedExit",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_RepriceDemotesBlockedExit::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();

    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4300, 200, 0};

    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);
    const auto NearExit = AddOverlayProjection(*Shared, Network, GoalLocation);          // ~4000 (nearest the goal)
    const auto FarExit = AddOverlayProjection(*Shared, Network, FVector{3000, 0, 0});    // mid-ribbon alternative

    constexpr auto Multiplier = 3.0f;

    // Un-repriced: the exit nearest the goal wins.
    {
        const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, Multiplier, Shared};
        const auto Result = RunSearch(Graph);
        TestTrue(TEXT("nearest exit wins before reprice"),
            Result.Path.Contains(FRouteNodeId{ERouteNodeKind::OverlayPoint, NearExit}));
    }

    // Simulate the validation pass discovering a wall on nearest-exit -> goal: reprice that hop
    // to unwalkable and re-run — the search must promote the alternative exit.
    Shared->_RepricedOffPathCosts.Add(
        FRouteGraph::PackOffPathKey(
            FRouteNodeId{ERouteNodeKind::OverlayPoint, NearExit},
            FRouteNodeId{ERouteNodeKind::Goal, 0}),
        TNumericLimits<float>::Max() / 8.0f);

    {
        const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, Multiplier, Shared};
        const auto Result = RunSearch(Graph);

        TestTrue(TEXT("search still completes after reprice"), Result.Status == ck::astar::ESearchStatus::Complete);
        TestFalse(TEXT("blocked exit is demoted"),
            Result.Path.Contains(FRouteNodeId{ERouteNodeKind::OverlayPoint, NearExit}));
        TestTrue(TEXT("alternative exit is promoted"),
            Result.Path.Contains(FRouteNodeId{ERouteNodeKind::OverlayPoint, FarExit}));
    }

    return true;
}
