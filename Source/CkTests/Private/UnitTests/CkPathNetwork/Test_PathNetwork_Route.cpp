#include "Misc/AutomationTest.h"

#include "CkAStar/Algorithm/CkAStar_Search.h"

#include "CkPathNetwork/Network/CkPathNetwork_Build.h"
#include "CkPathNetwork/Network/CkPathNetwork_RoutePlan.h"
#include "CkPathNetwork/Network/CkPathNetwork_RouteGraph.h"
#include "CkPathNetwork/Network/CkPathNetwork_Types.h"

#include <limits>

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

    // Two collinear sidewalk islands separated by a 1000cm off-network gap.
    auto MakeDisconnectedNetwork() -> FBuiltNetwork
    {
        auto MakeRibbon =
            [](const FVector& InStart, const FVector& InEnd)
            {
                auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
                Points.Add(
                    FCk_PathNetwork_RibbonPoint{
                        InStart,
                        100.0f});
                Points.Add(
                    FCk_PathNetwork_RibbonPoint{
                        InEnd,
                        100.0f});

                auto Ribbon = FCk_PathNetwork_Ribbon{Points};
                Ribbon.Set_RibbonId(FGuid::NewGuid());
                return Ribbon;
            };

        return Build_NetworkFromRibbons(
            {
                MakeRibbon(
                    FVector{0, 0, 0},
                    FVector{4000, 0, 0}),
                MakeRibbon(
                    FVector{5000, 0, 0},
                    FVector{9000, 0, 0})
            },
            FCk_PathNetwork_BuildParams{});
    }

    auto
    MakeRepeatedDisconnectedGapNetwork(
        const int32 InGapCount,
        const double InSpacing,
        const double InGapDistance)
        -> FBuiltNetwork
    {
        const auto MakeSegment =
            [](const FVector& InStart, const FVector& InEnd)
            {
                auto Points = TArray<FCk_PathNetwork_RibbonPoint>{
                    FCk_PathNetwork_RibbonPoint{InStart, 100.0f},
                    FCk_PathNetwork_RibbonPoint{InEnd, 100.0f}};
                auto Ribbon = FCk_PathNetwork_Ribbon{Points};
                Ribbon.Set_RibbonId(FGuid::NewGuid());
                return Ribbon;
            };

        auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
        for (auto GapIndex = 0; GapIndex < InGapCount - 1; ++GapIndex)
        {
            const auto StartAlong =
                static_cast<double>(GapIndex) * InSpacing;
            const auto EndAlong =
                static_cast<double>(GapIndex + 1) * InSpacing;
            Ribbons.Add(MakeSegment(
                FVector{StartAlong, 0.0, 0.0},
                FVector{EndAlong, 0.0, 0.0}));
            Ribbons.Add(MakeSegment(
                FVector{StartAlong, InGapDistance, 0.0},
                FVector{EndAlong, InGapDistance, 0.0}));
        }

        auto BuildParams = FCk_PathNetwork_BuildParams{};
        BuildParams.Set_NodeSnapRadius(1.0f);
        return Build_NetworkFromRibbons(Ribbons, BuildParams);
    }

    // A single connected U: the left endpoints are 1000cm apart, but its authored
    // sidewalk route must travel 21000cm around the far-right turn.
    auto MakeConnectedUNetwork() -> FBuiltNetwork
    {
        auto MakeRibbon =
            [](const FVector& InStart, const FVector& InEnd)
            {
                auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
                Points.Add(FCk_PathNetwork_RibbonPoint{InStart, 100.0f});
                Points.Add(FCk_PathNetwork_RibbonPoint{InEnd, 100.0f});

                auto Ribbon = FCk_PathNetwork_Ribbon{Points};
                Ribbon.Set_RibbonId(FGuid::NewGuid());
                return Ribbon;
            };

        return Build_NetworkFromRibbons(
            {
                MakeRibbon(FVector{0, 0, 0}, FVector{10000, 0, 0}),
                MakeRibbon(FVector{10000, 0, 0}, FVector{10000, 1000, 0}),
                MakeRibbon(FVector{10000, 1000, 0}, FVector{0, 1000, 0})
            },
            FCk_PathNetwork_BuildParams{});
    }

    // A and two closer nodes sit on short authored branches. A third, slightly
    // farther node is reached only through a long detour. Geometric-only capped
    // admission starves the actually valuable crossing.
    auto MakeShortcutBenefitRankingNetwork() -> FBuiltNetwork
    {
        auto MakeRibbon =
            [](const FVector& InStart, const FVector& InEnd)
            {
                auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
                Points.Add(FCk_PathNetwork_RibbonPoint{InStart, 100.0f});
                Points.Add(FCk_PathNetwork_RibbonPoint{InEnd, 100.0f});

                auto Ribbon = FCk_PathNetwork_Ribbon{Points};
                Ribbon.Set_RibbonId(FGuid::NewGuid());
                return Ribbon;
            };

        const auto Source = FVector{0, 0, 0};
        const auto Hub = FVector{0, -300, 0};
        const auto NearA = FVector{-500, 0, 0};
        const auto NearB = FVector{-400, 300, 0};
        const auto Detour = FVector{6000, -300, 0};
        const auto ValuableTarget = FVector{700, 0, 0};
        return Build_NetworkFromRibbons(
            {
                MakeRibbon(Source, Hub),
                MakeRibbon(Hub, NearA),
                MakeRibbon(Hub, NearB),
                MakeRibbon(Hub, Detour),
                MakeRibbon(Detour, ValuableTarget)
            },
            FCk_PathNetwork_BuildParams{});
    }

    auto MakeDenseLocalNetwork(const int32 InNodeCount) -> FBuiltNetwork
    {
        auto Network = FBuiltNetwork{};
        Network._Nodes.SetNum(InNodeCount);
        for (auto NodeId = 0; NodeId < InNodeCount; ++NodeId)
        {
            const auto Angle =
                2.0 * UE_PI
                * static_cast<double>(NodeId)
                / static_cast<double>(InNodeCount);
            Network._Nodes[NodeId]._Location =
                FVector{
                    100.0 * FMath::Cos(Angle),
                    100.0 * FMath::Sin(Angle),
                    0.0};
        }

        for (auto NodeId = 0; NodeId < InNodeCount - 1; ++NodeId)
        {
            const auto EdgeId = Network._Edges.AddDefaulted();
            auto& Edge = Network._Edges[EdgeId];
            Edge._NodeA = NodeId;
            Edge._NodeB = NodeId + 1;
            Edge._Points = {
                Network._Nodes[NodeId]._Location,
                Network._Nodes[NodeId + 1]._Location};
            Edge._Length = static_cast<float>(
                FVector::Dist(
                    Edge._Points[0],
                    Edge._Points[1]));
            Edge._CumulativeLengths = {0.0f, Edge._Length};
            Network._Nodes[NodeId]._EdgeIds.Add(EdgeId);
            Network._Nodes[NodeId + 1]._EdgeIds.Add(EdgeId);
        }
        return Network;
    }

    auto AddOverlayProjection(FRouteGraphSharedData& InOutShared, const FBuiltNetwork& InNetwork, const FVector& InLocation) -> int32
    {
        const auto Projection = InNetwork.Project_OntoEdge(0, InLocation);
        const auto NewIndex = InOutShared._OverlayPoints.Add(
            FRouteOverlayPoint{0, Projection._DistAlong, Projection._Location});
        InOutShared._OverlayPointsByEdge.FindOrAdd(0).Add(NewIndex);
        return NewIndex;
    }

    auto MakeLegacyPolicy(float InMultiplier = 3.0f) -> FRouteCostPolicy
    {
        auto Policy = FRouteCostPolicy{};
        Policy._FarOrDirectCostMultiplier = InMultiplier;
        Policy._NearEndpointCostMultiplier = InMultiplier;
        Policy._NetworkGapCostMultiplier = InMultiplier;
        Policy._EndpointJoinMaxDistance = 0.0f;
        Policy._DirectTripGraceDistance = 0.0f;
        return Policy;
    }

    auto MakeEndpointAwarePolicy(
        float InNearEndpointMultiplier,
        float InFarOrDirectMultiplier,
        float InEndpointJoinMaxDistance,
        float InDirectTripGraceDistance,
        float InComponentTransferMaxDistance = 0.0f,
        float InDirectRouteMinimumSavingsFraction = 0.0f,
        float InLocalNetworkShortcutMaxDistance = 0.0f) -> FRouteCostPolicy
    {
        auto Policy = FRouteCostPolicy{};
        Policy._FarOrDirectCostMultiplier = InFarOrDirectMultiplier;
        Policy._NearEndpointCostMultiplier = InNearEndpointMultiplier;
        Policy._NetworkGapCostMultiplier = InFarOrDirectMultiplier;
        Policy._EndpointJoinMaxDistance = InEndpointJoinMaxDistance;
        Policy._ComponentTransferMaxDistance =
            InComponentTransferMaxDistance;
        Policy._DirectTripGraceDistance = InDirectTripGraceDistance;
        Policy._DirectRouteMinimumSavingsFraction =
            InDirectRouteMinimumSavingsFraction;
        Policy._LocalNetworkShortcutMaxDistance =
            InLocalNetworkShortcutMaxDistance;
        return Policy;
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
    const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, MakeLegacyPolicy(Multiplier), Shared};

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
    const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, MakeLegacyPolicy(Multiplier), Shared};

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

        const auto Graph = FRouteGraph{
            &Network,
            StartLocation,
            GoalLocation,
            MakeLegacyPolicy(InMultiplier),
            Shared};
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
        const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, MakeLegacyPolicy(Multiplier), Shared};
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
        const auto Graph = FRouteGraph{&Network, StartLocation, GoalLocation, MakeLegacyPolicy(Multiplier), Shared};
        const auto Result = RunSearch(Graph);

        TestTrue(TEXT("search still completes after reprice"), Result.Status == ck::astar::ESearchStatus::Complete);
        TestFalse(TEXT("blocked exit is demoted"),
            Result.Path.Contains(FRouteNodeId{ERouteNodeKind::OverlayPoint, NearExit}));
        TestTrue(TEXT("alternative exit is promoted"),
            Result.Path.Contains(FRouteNodeId{ERouteNodeKind::OverlayPoint, FarExit}));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_EndpointPolicy_LegacyDefaults,
    "Ck.PathNetwork.Route.EndpointPolicy.LegacyDefaults",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_EndpointPolicy_LegacyDefaults::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{1000, 300, 0};
    const auto GoalLocation = FVector{1200, -300, 0};
    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);
    AddOverlayProjection(*Shared, Network, GoalLocation);

    constexpr auto LegacyMultiplier = 3.0f;
    const auto Graph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        MakeLegacyPolicy(LegacyMultiplier),
        Shared};
    const auto Result = RunSearch(Graph);

    TestTrue(TEXT("legacy search completes"), Result.Status == ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("legacy policy keeps direct fallback"), Result.Path.Num(), 2);
    TestTrue(TEXT("legacy direct cost remains distance times multiplier"),
        FMath::IsNearlyEqual(
            Result.TotalCost,
            static_cast<float>(FVector::Dist(StartLocation, GoalLocation)) * LegacyMultiplier,
            1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_EndpointPolicy_DirectGrace,
    "Ck.PathNetwork.Route.EndpointPolicy.DirectGrace",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_EndpointPolicy_DirectGrace::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{1000, 300, 0};
    const auto GoalLocation = FVector{1200, -300, 0};
    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);
    AddOverlayProjection(*Shared, Network, GoalLocation);

    constexpr auto NearMultiplier = 1.25f;
    const auto Graph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(NearMultiplier, 8.0f, 1000.0f, 700.0f),
        Shared};
    const auto Result = RunSearch(Graph);

    TestTrue(TEXT("short direct-grace search completes"), Result.Status == ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("short trip remains direct"), Result.Path.Num(), 2);
    TestTrue(TEXT("short direct trip uses near multiplier"),
        FMath::IsNearlyEqual(
            Result.TotalCost,
            static_cast<float>(FVector::Dist(StartLocation, GoalLocation)) * NearMultiplier,
            1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_EndpointPolicy_LongTripUsesRibbon,
    "Ck.PathNetwork.Route.EndpointPolicy.LongTripUsesRibbon",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_EndpointPolicy_LongTripUsesRibbon::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4600, 800, 0};
    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);
    AddOverlayProjection(*Shared, Network, GoalLocation);

    constexpr auto NearMultiplier = 1.5f;
    const auto Graph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(NearMultiplier, 8.0f, 1200.0f, 700.0f),
        Shared};
    const auto Result = RunSearch(Graph);

    TestTrue(TEXT("long-trip search completes"), Result.Status == ck::astar::ESearchStatus::Complete);
    TestTrue(TEXT("long trip uses the ribbon instead of far direct shortcut"),
        Count_OnNetworkSteps(Result.Path) >= 2);
    const auto ExpectedRibbonCost = 100.0f * NearMultiplier + 4000.0f + 1000.0f * NearMultiplier;
    TestTrue(TEXT("endpoint connectors use the near multiplier"),
        FMath::IsNearlyEqual(Result.TotalCost, ExpectedRibbonCost, 50.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_EndpointPolicy_JoinLimitFallsBackDirect,
    "Ck.PathNetwork.Route.EndpointPolicy.JoinLimitFallsBackDirect",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_EndpointPolicy_JoinLimitFallsBackDirect::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 3000, 0};
    const auto GoalLocation = FVector{4000, 3000, 0};
    auto Shared = MakeShared<FRouteGraphSharedData>();
    AddOverlayProjection(*Shared, Network, StartLocation);
    AddOverlayProjection(*Shared, Network, GoalLocation);

    constexpr auto FarMultiplier = 8.0f;
    const auto Graph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(1.5f, FarMultiplier, 1000.0f, 500.0f),
        Shared};
    const auto Result = RunSearch(Graph);

    TestTrue(TEXT("join-limited search completes"), Result.Status == ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("distant overlay hops are filtered"), Count_OnNetworkSteps(Result.Path), 0);
    TestEqual(TEXT("direct fallback remains available"), Result.Path.Num(), 2);
    TestTrue(TEXT("fallback uses far/direct multiplier"),
        FMath::IsNearlyEqual(Result.TotalCost, 4000.0f * FarMultiplier, 1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_EndpointPolicy_RepriceUsesHopMultiplier,
    "Ck.PathNetwork.Route.EndpointPolicy.RepriceUsesHopMultiplier",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_EndpointPolicy_RepriceUsesHopMultiplier::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4000, 100, 0};
    auto Shared = MakeShared<FRouteGraphSharedData>();
    const auto StartOverlay = AddOverlayProjection(*Shared, Network, StartLocation);

    constexpr auto NearMultiplier = 1.5f;
    constexpr auto FarMultiplier = 8.0f;
    const auto Graph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(NearMultiplier, FarMultiplier, 1000.0f, 500.0f),
        Shared};
    constexpr auto ResolvedLength = 1000.0f;

    TestTrue(TEXT("repriced start connector uses near multiplier"),
        FMath::IsNearlyEqual(
            Graph.Get_OffPathCostForResolvedLength(
                FRouteNodeId{ERouteNodeKind::Start, 0},
                FRouteNodeId{ERouteNodeKind::OverlayPoint, StartOverlay},
                ResolvedLength),
            ResolvedLength * NearMultiplier));
    TestTrue(TEXT("repriced long direct hop uses far multiplier"),
        FMath::IsNearlyEqual(
            Graph.Get_OffPathCostForResolvedLength(
                FRouteNodeId{ERouteNodeKind::Start, 0},
                FRouteNodeId{ERouteNodeKind::Goal, 0},
                ResolvedLength),
            ResolvedLength * FarMultiplier));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerGathersEndpointOverlays,
    "Ck.PathNetwork.Route.Planner.GathersEndpointOverlays",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerGathersEndpointOverlays::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4600, 800, 0};

    auto Tuning = FCk_PathNetworkFollower_Tuning{};
    Tuning.Set_OffPathCostMultiplier(8.0f);
    Tuning.Set_NearEndpointCostMultiplier(1.5f);
    Tuning.Set_EndpointJoinMaxDistance(1200.0f);
    Tuning.Set_DirectTripGraceDistance(700.0f);
    Tuning.Set_DirectRouteMinimumSavingsFraction(0.05f);

    const auto CostPolicy = Resolve_RouteCostPolicy(Tuning);
    TestEqual(TEXT("planner resolves the minimum direct-route saving"),
        CostPolicy._DirectRouteMinimumSavingsFraction, 0.05f);
    const auto Plan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        CostPolicy);

    TestTrue(TEXT("planner succeeds"), Plan._Succeeded);
    TestTrue(TEXT("planner returns shared endpoint-overlay data"), Plan._Shared.IsValid());
    TestTrue(TEXT("planner gathers both endpoint overlays"), Plan._Shared->_OverlayPoints.Num() >= 2);
    TestTrue(TEXT("high far/direct cost selects an on-network span"),
        Plan._Spans.ContainsByPredicate([](const FRouteLegSpan& Span)
        { return NOT Span._IsOffPath; }));
    TestTrue(TEXT("selected route is not the direct fallback"), Plan._Path.Num() > 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerDirectEdgeOptOut,
    "Ck.PathNetwork.Route.Planner.DirectEdgeOptOut",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerDirectEdgeOptOut::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4000, 100, 0};
    const auto Policy = MakeEndpointAwarePolicy(1.5f, 8.0f, 1200.0f, 500.0f);
    auto Shared = Build_RouteGraphSharedData(
        Network,
        StartLocation,
        GoalLocation,
        Policy);
    Shared->_AllowDirectStartToGoal = false;

    const auto Plan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Policy,
        Shared);

    TestTrue(TEXT("direct-edge opt-out finds the sidewalk route"), Plan._Succeeded);
    TestTrue(TEXT("direct-edge opt-out completes"),
        Plan._SearchOutcome == ERouteSearchOutcome::Complete);
    TestTrue(TEXT("direct-edge opt-out includes on-network spans"),
        Plan._Spans.ContainsByPredicate([](const FRouteLegSpan& InSpan)
        { return NOT InSpan._IsOffPath; }));
    TestTrue(TEXT("direct-edge opt-out cannot return Start->Goal"), Plan._Path.Num() > 2);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerDirectRouteMinimumSavings,
    "Ck.PathNetwork.Route.Planner.DirectRouteMinimumSavings",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerDirectRouteMinimumSavings::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 10, 0};
    const auto GoalLocation = FVector{4000, 10, 0};

    const auto LegacyPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(
            1.0f,
            1.0f,
            100.0f,
            0.0f));
    TestTrue(TEXT("legacy zero-savings policy succeeds"), LegacyPlan._Succeeded);
    TestEqual(TEXT("legacy zero-savings policy keeps the cheaper direct route"),
        LegacyPlan._Path.Num(), 2);

    const auto SidewalkPreferredPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(
            1.0f,
            1.0f,
            100.0f,
            0.0f,
            0.0f,
            0.01f));
    TestTrue(TEXT("minimum-savings policy succeeds"), SidewalkPreferredPlan._Succeeded);
    TestTrue(TEXT("sub-threshold direct saving selects the sidewalk"),
        SidewalkPreferredPlan._Spans.ContainsByPredicate(
            [](const FRouteLegSpan& InSpan)
            { return NOT InSpan._IsOffPath; }));
    TestTrue(TEXT("sidewalk preference may accept a slightly higher route cost"),
        SidewalkPreferredPlan._EstimatedCost > LegacyPlan._EstimatedCost);

    const auto DirectQualifiedPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(
            1.0f,
            1.0f,
            100.0f,
            0.0f,
            0.0f,
            0.001f));
    TestTrue(TEXT("qualified direct-savings policy succeeds"),
        DirectQualifiedPlan._Succeeded);
    TestEqual(TEXT("direct route remains eligible when its saving clears the minimum"),
        DirectQualifiedPlan._Path.Num(), 2);

    const auto GracePlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        MakeEndpointAwarePolicy(
            1.0f,
            1.0f,
            100.0f,
            5000.0f,
            0.0f,
            0.01f));
    TestTrue(TEXT("short-trip grace policy succeeds"), GracePlan._Succeeded);
    TestEqual(TEXT("short-trip grace bypasses the minimum-savings preference"),
        GracePlan._Path.Num(), 2);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerSearchOutcome,
    "Ck.PathNetwork.Route.Planner.SearchOutcome",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerSearchOutcome::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{4000, 100, 0};
    const auto Policy = MakeEndpointAwarePolicy(1.5f, 8.0f, 1200.0f, 500.0f);

    const auto CompletePlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Policy);
    TestTrue(TEXT("complete search keeps success semantics"), CompletePlan._Succeeded);
    TestTrue(TEXT("complete search reports complete outcome"),
        CompletePlan._SearchOutcome == ERouteSearchOutcome::Complete);

    const auto InProgressPlan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Policy,
        Build_RouteGraphSharedData(
            Network,
            StartLocation,
            GoalLocation,
            Policy),
        1);
    TestFalse(TEXT("iteration-limited search remains unsuccessful"), InProgressPlan._Succeeded);
    TestTrue(TEXT("iteration-limited search reports in-progress outcome"),
        InProgressPlan._SearchOutcome == ERouteSearchOutcome::InProgress);

    auto DisconnectedShared = MakeShared<FRouteGraphSharedData>();
    DisconnectedShared->_AllowDirectStartToGoal = false;
    const auto FailedPlan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Policy,
        DisconnectedShared);
    TestFalse(TEXT("unreachable search remains unsuccessful"), FailedPlan._Succeeded);
    TestTrue(TEXT("unreachable search reports failed outcome"),
        FailedPlan._SearchOutcome == ERouteSearchOutcome::Failed);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerGatherEndpointCandidates,
    "Ck.PathNetwork.Route.Planner.GatherEndpointCandidates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerGatherEndpointCandidates::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto Policy = MakeEndpointAwarePolicy(1.5f, 8.0f, 1000.0f, 500.0f);
    const auto NearCandidates = Gather_RouteEndpointCandidates(
        Network,
        FVector{1000, 500, 0},
        Policy);
    const auto FarCandidates = Gather_RouteEndpointCandidates(
        Network,
        FVector{1000, 1500, 0},
        Policy);

    TestEqual(TEXT("near endpoint returns one eligible candidate"), NearCandidates.Num(), 1);
    TestEqual(TEXT("far endpoint returns no candidate beyond join limit"), FarCandidates.Num(), 0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerGatherEndpointCandidatesInvalidInput,
    "Ck.PathNetwork.Route.Planner.GatherEndpointCandidatesInvalidInput",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerGatherEndpointCandidatesInvalidInput::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto ValidPolicy = MakeEndpointAwarePolicy(1.5f, 8.0f, 1000.0f, 500.0f);
    const auto Network = MakeStraightNetwork();
    auto InvalidPolicy = ValidPolicy;
    InvalidPolicy._FarOrDirectCostMultiplier = 0.5f;
    auto InvalidNetworkGapPolicy = ValidPolicy;
    InvalidNetworkGapPolicy._NetworkGapCostMultiplier = 0.5f;
    auto InvalidSavingsPolicy = ValidPolicy;
    InvalidSavingsPolicy._DirectRouteMinimumSavingsFraction = 1.01f;

    TestEqual(TEXT("empty network is rejected without candidates"),
        Gather_RouteEndpointCandidates(
            FBuiltNetwork{},
            FVector{1000, 500, 0},
            ValidPolicy).Num(),
        0);
    TestEqual(TEXT("non-finite endpoint is rejected without candidates"),
        Gather_RouteEndpointCandidates(
            Network,
            FVector{std::numeric_limits<float>::quiet_NaN(), 500, 0},
            ValidPolicy).Num(),
        0);
    TestEqual(TEXT("invalid policy is rejected without candidates"),
        Gather_RouteEndpointCandidates(
            Network,
            FVector{1000, 500, 0},
            InvalidPolicy).Num(),
        0);
    TestEqual(TEXT("invalid network-gap policy is rejected without candidates"),
        Gather_RouteEndpointCandidates(
            Network,
            FVector{1000, 500, 0},
            InvalidNetworkGapPolicy).Num(),
        0);
    TestEqual(TEXT("invalid direct-savings policy is rejected without candidates"),
        Gather_RouteEndpointCandidates(
            Network,
            FVector{1000, 500, 0},
            InvalidSavingsPolicy).Num(),
        0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_PlannerJoinLimitFallsBackDirect,
    "Ck.PathNetwork.Route.Planner.JoinLimitFallsBackDirect",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_PlannerJoinLimitFallsBackDirect::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeStraightNetwork();
    const auto StartLocation = FVector{0, 3000, 0};
    const auto GoalLocation = FVector{4000, 3000, 0};

    auto Tuning = FCk_PathNetworkFollower_Tuning{};
    Tuning.Set_OffPathCostMultiplier(8.0f);
    Tuning.Set_NearEndpointCostMultiplier(1.5f);
    Tuning.Set_EndpointJoinMaxDistance(1000.0f);
    Tuning.Set_DirectTripGraceDistance(500.0f);

    const auto Plan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Resolve_RouteCostPolicy(Tuning));

    TestTrue(TEXT("planner succeeds with direct fallback"), Plan._Succeeded);
    TestEqual(TEXT("tight join limit prevents endpoint overlays"), Plan._Shared->_OverlayPoints.Num(), 0);
    TestEqual(TEXT("direct fallback has one span"), Plan._Spans.Num(), 1);
    TestTrue(TEXT("direct fallback span is off-path"), Plan._Spans[0]._IsOffPath);
    TestEqual(TEXT("direct fallback path contains only endpoints"), Plan._Path.Num(), 2);
    TestTrue(TEXT("direct fallback uses far/direct multiplier"),
        FMath::IsNearlyEqual(Plan._EstimatedCost, 4000.0f * 8.0f, 1.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_ComponentTransferOptIn,
    "Ck.PathNetwork.Route.ComponentTransfer.OptIn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_ComponentTransferOptIn::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeDisconnectedNetwork();
    const auto StartLocation = FVector{0, 100, 0};
    const auto GoalLocation = FVector{9000, 100, 0};
    constexpr auto NearMultiplier = 1.5f;
    constexpr auto FarMultiplier = 8.0f;
    constexpr auto JoinMaxDistance = 1200.0f;
    constexpr auto DirectGraceDistance = 500.0f;

    const auto DisabledPolicy = MakeEndpointAwarePolicy(
        NearMultiplier,
        FarMultiplier,
        JoinMaxDistance,
        DirectGraceDistance);
    const auto DisabledPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        DisabledPolicy);
    TestTrue(TEXT("legacy-disabled planner still succeeds"),
        DisabledPlan._Succeeded);
    TestEqual(TEXT("zero transfer distance keeps the direct fallback"),
        DisabledPlan._Path.Num(), 2);
    TestTrue(TEXT("zero transfer distance creates no transfer adjacency"),
        DisabledPlan._Shared->_ComponentTransfersByNode.IsEmpty());

    const auto EnabledPolicy = MakeEndpointAwarePolicy(
        NearMultiplier,
        FarMultiplier,
        JoinMaxDistance,
        DirectGraceDistance,
        1200.0f);
    const auto EnabledPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        EnabledPolicy);
    TestTrue(TEXT("transfer-enabled planner succeeds"),
        EnabledPlan._Succeeded);
    TestTrue(TEXT("transfer-enabled route uses network islands"),
        Count_OnNetworkSteps(EnabledPlan._Path) >= 4);
    TestFalse(TEXT("enabled route is not the direct fallback"),
        EnabledPlan._Path.Num() == 2);
    TestFalse(TEXT("enabled policy creates transfer adjacency"),
        EnabledPlan._Shared->_ComponentTransfersByNode.IsEmpty());

    const auto* TransferSpan = EnabledPlan._Spans.FindByPredicate(
        [](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId._Kind == ERouteNodeKind::NetNode
                && InSpan._ToId._Kind == ERouteNodeKind::NetNode;
        });
    TestNotNull(TEXT("route contains an inter-component transfer span"),
        TransferSpan);
    if (TransferSpan != nullptr)
    {
        const auto TransferLength = static_cast<float>(
            FVector::Dist(
                TransferSpan->_FromLocation,
                TransferSpan->_ToLocation));
        const auto Graph = FRouteGraph{
            &Network,
            StartLocation,
            GoalLocation,
            EnabledPolicy,
            EnabledPlan._Shared};
        TestTrue(TEXT("component transfer pays the far off-network cost"),
            FMath::IsNearlyEqual(
                Graph.Get_OffPathCostForResolvedLength(
                    TransferSpan->_FromId,
                    TransferSpan->_ToId,
                    TransferLength),
                TransferLength * FarMultiplier,
                1.0f));
    }

    TestTrue(TEXT("sidewalk route beats the long direct shortcut"),
        EnabledPlan._EstimatedCost
            < static_cast<float>(
                FVector::Dist(StartLocation, GoalLocation))
                * FarMultiplier);

    const auto LegacyOnlyShared =
        MakeShared<FRouteGraphSharedData>(
            *EnabledPlan._Shared);
    LegacyOnlyShared->_ComponentTransfersByRouteNode.Reset();
    LegacyOnlyShared->_AllowDirectStartToGoal = false;
    const auto LegacyOnlyPlan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        EnabledPolicy,
        LegacyOnlyShared);
    const auto LegacyOnlyGraph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        EnabledPolicy,
        LegacyOnlyShared};
    TestTrue(TEXT("legacy node-only transfer data remains routable"),
        LegacyOnlyPlan._Succeeded);
    TestTrue(TEXT("legacy node-only transfer is classified as an off-path hop"),
        LegacyOnlyPlan._Spans.ContainsByPredicate(
            [&LegacyOnlyGraph](const FRouteLegSpan& InSpan)
            {
                return InSpan._IsOffPath
                    && LegacyOnlyGraph.Get_IsComponentTransferHop(
                        InSpan._FromId,
                        InSpan._ToId);
            }));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_ComponentTransferGeographicCoverage,
    "Ck.PathNetwork.Route.ComponentTransfer.GeographicCoverage",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_ComponentTransferGeographicCoverage::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    constexpr auto GapCount = 9;
    constexpr auto GapSpacing = 2000.0;
    constexpr auto GapDistance = 100.0;
    constexpr auto FarMultiplier = 8.0f;
    const auto Network = MakeRepeatedDisconnectedGapNetwork(
        GapCount,
        GapSpacing,
        GapDistance);
    const auto Topology = Analyze_NetworkTopology(Network);
    const auto StartLocation = FVector{
        static_cast<double>(GapCount - 1) * GapSpacing,
        0.0,
        0.0};
    const auto GoalLocation = StartLocation + FVector{0.0, GapDistance, 0.0};
    const auto FindNodeAt =
        [&Network](const FVector& InLocation) -> int32
        {
            for (auto NodeId = 0; NodeId < Network._Nodes.Num(); ++NodeId)
            {
                if (Network._Nodes[NodeId]._Location.Equals(InLocation))
                { return NodeId; }
            }
            return INDEX_NONE;
        };
    const auto FarLowerNode = FindNodeAt(StartLocation);
    const auto FarUpperNode = FindNodeAt(GoalLocation);
    const auto Policy = MakeEndpointAwarePolicy(
        1.5f,
        FarMultiplier,
        1.0f,
        0.0f,
        150.0f,
        1.0f);

    TestEqual(TEXT("parallel sidewalks remain separate components"),
        Topology._ComponentCount,
        2);
    if (NOT TestTrue(
            TEXT("distant crossing nodes are present"),
            FarLowerNode != INDEX_NONE && FarUpperNode != INDEX_NONE))
    { return false; }

    const auto Shared = Build_RouteGraphSharedData(
        Network,
        StartLocation,
        GoalLocation,
        Policy);
    Shared->_AllowDirectStartToGoal = false;
    const auto Plan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Policy,
        Shared);
    TestTrue(TEXT("geographic coverage route succeeds"), Plan._Succeeded);
    TestTrue(TEXT("route shared data is available"), Plan._Shared.IsValid());

    const auto* FarTransfers = Plan._Shared.IsValid()
        ? Plan._Shared->_ComponentTransfersByNode.Find(FarLowerNode)
        : nullptr;
    TestTrue(TEXT("distant legal gap receives a component transfer"),
        FarTransfers != nullptr && FarTransfers->Contains(FarUpperNode));

    const auto* ExactTransferSpan = Plan._Spans.FindByPredicate(
        [FarLowerNode, FarUpperNode](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId._Kind == ERouteNodeKind::NetNode
                && InSpan._FromId._Index == FarLowerNode
                && InSpan._ToId._Kind == ERouteNodeKind::NetNode
                && InSpan._ToId._Index == FarUpperNode;
        });
    TestNotNull(TEXT("route uses the local distant transfer"),
        ExactTransferSpan);
    TestTrue(TEXT("route avoids a geographically unrelated transfer detour"),
        FMath::IsNearlyEqual(
            Plan._EstimatedCost,
            static_cast<float>(GapDistance) * FarMultiplier,
            1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_ComponentTransferEdgeInterior,
    "Ck.PathNetwork.Route.ComponentTransfer.EdgeInterior",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_ComponentTransferEdgeInterior::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    // The ribbons overlap laterally at an 800cm gap, but their authored
    // endpoints are offset enough that every endpoint pair is over 1000cm
    // apart. Only an edge-interior transfer can cross the gap.
    const auto LeftA = FVector{-2000.0, 0.0, 0.0};
    const auto RightA = FVector{2000.0, 0.0, 0.0};
    const auto LeftB = FVector{-1000.0, 800.0, 0.0};
    const auto RightB = FVector{3000.0, 800.0, 0.0};
    const auto StartLocation = FVector{0.0, 0.0, 0.0};
    const auto GoalLocation = FVector{0.0, 800.0, 0.0};
    const auto MakeRibbon =
        [](const FVector& InStart, const FVector& InEnd)
        {
            auto Points = TArray<FCk_PathNetwork_RibbonPoint>{
                FCk_PathNetwork_RibbonPoint{InStart, 100.0f},
                FCk_PathNetwork_RibbonPoint{InEnd, 100.0f}};
            auto Ribbon = FCk_PathNetwork_Ribbon{Points};
            Ribbon.Set_RibbonId(FGuid::NewGuid());
            return Ribbon;
        };
    auto BuildParams = FCk_PathNetwork_BuildParams{};
    BuildParams.Set_NodeSnapRadius(1.0f);
    const auto Network = Build_NetworkFromRibbons(
        {MakeRibbon(LeftA, RightA), MakeRibbon(LeftB, RightB)},
        BuildParams);
    constexpr auto TransferMaxDistance = 1000.0f;
    constexpr auto NetworkGapMultiplier = 1.5f;
    auto Policy = MakeEndpointAwarePolicy(
        1.5f,
        8.0f,
        1.0f,
        0.0f,
        TransferMaxDistance);
    Policy._NetworkGapCostMultiplier = NetworkGapMultiplier;

    const auto MinimumEndpointDistance = static_cast<float>(FMath::Min(
        FMath::Min(FVector::Dist(LeftA, LeftB), FVector::Dist(LeftA, RightB)),
        FMath::Min(FVector::Dist(RightA, LeftB), FVector::Dist(RightA, RightB))));
    TestEqual(TEXT("sparse parallel ribbons remain separate components"),
        Analyze_NetworkTopology(Network)._ComponentCount,
        2);
    TestTrue(TEXT("no authored endpoint pair is eligible for the transfer"),
        MinimumEndpointDistance > TransferMaxDistance);

    const auto Shared = Build_RouteGraphSharedData(
        Network,
        StartLocation,
        GoalLocation,
        Policy);
    TestTrue(TEXT("edge-interior transfer candidate is discovered"),
        Shared->_ComponentTransferEdgeInteriorCandidateCount > 0);
    TestTrue(TEXT("canonical route-node transfer map contains a transfer"),
        NOT Shared->_ComponentTransfersByRouteNode.IsEmpty());
    TestTrue(TEXT("legacy node-only transfer map cannot represent the interior gap"),
        Shared->_ComponentTransfersByNode.IsEmpty());

    auto HasCanonicalInteriorTransfer = false;
    for (const auto& Pair : Shared->_ComponentTransfersByRouteNode)
    {
        for (const auto& OtherNode : Pair.Value)
        {
            if (Pair.Key._Kind == ERouteNodeKind::OverlayPoint
                || OtherNode._Kind == ERouteNodeKind::OverlayPoint)
            {
                HasCanonicalInteriorTransfer = true;
                break;
            }
        }
        if (HasCanonicalInteriorTransfer)
        { break; }
    }
    TestTrue(TEXT("canonical transfer retains at least one edge-interior route node"),
        HasCanonicalInteriorTransfer);

    Shared->_AllowDirectStartToGoal = false;
    const auto Plan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        Policy,
        Shared);
    TestTrue(TEXT("network-only edge-interior transfer route succeeds"),
        Plan._Succeeded);
    TestTrue(TEXT("network-only edge-interior transfer route uses the network"),
        Uses_Network(Plan));

    const auto Graph = FRouteGraph{
        &Network,
        StartLocation,
        GoalLocation,
        Policy,
        Shared};
    const auto* TransferSpan = Plan._Spans.FindByPredicate(
        [&Graph](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && (InSpan._FromId._Kind == ERouteNodeKind::OverlayPoint
                    || InSpan._ToId._Kind == ERouteNodeKind::OverlayPoint)
                && Graph.Get_IsComponentTransferHop(
                    InSpan._FromId,
                    InSpan._ToId);
        });
    TestNotNull(TEXT("route selects an edge-interior component-transfer span"),
        TransferSpan);
    if (TransferSpan != nullptr)
    {
        const auto TransferLength = static_cast<float>(
            FVector::Dist(
                TransferSpan->_FromLocation,
                TransferSpan->_ToLocation));
        TestTrue(TEXT("edge-interior transfer retains the 800cm physical gap"),
            FMath::IsNearlyEqual(TransferLength, 800.0f, 1.0f));
        TestTrue(TEXT("edge-interior transfer pays the network-gap multiplier"),
            FMath::IsNearlyEqual(
                Graph.Get_OffPathCostForResolvedLength(
                    TransferSpan->_FromId,
                    TransferSpan->_ToId,
                    TransferLength),
                TransferLength * NetworkGapMultiplier,
                1.0f));
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_ComponentTransferCanonicalDedupe,
    "Ck.PathNetwork.Route.ComponentTransfer.CanonicalDedupe",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_ComponentTransferCanonicalDedupe::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    // Nine distinct edge pairs dip just inside the transfer threshold, but
    // every closest point is within 1cm of the same authored node on each
    // component. They must charge the geographic cap as one canonical jump.
    const auto NodeA = FVector{0.0, 0.0, 0.0};
    const auto NodeB = FVector{0.0, 1000.5, 0.0};
    const auto MakeRibbon =
        [](const FVector& InStart,
           const FVector& InBend,
           const FVector& InEnd)
        {
            auto Points = TArray<FCk_PathNetwork_RibbonPoint>{
                FCk_PathNetwork_RibbonPoint{InStart, 100.0f},
                FCk_PathNetwork_RibbonPoint{InBend, 100.0f},
                FCk_PathNetwork_RibbonPoint{InEnd, 100.0f}};
            auto Ribbon = FCk_PathNetwork_Ribbon{Points};
            Ribbon.Set_RibbonId(FGuid::NewGuid());
            return Ribbon;
        };
    const auto Offsets = TArray<double>{
        -0.25,
        0.0,
        0.25};
    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    for (const auto Offset : Offsets)
    {
        const auto FarX = Offset * 24000.0;
        Ribbons.Add(
            MakeRibbon(
                NodeA,
                FVector{Offset, 0.4, 0.0},
                FVector{FarX, -6000.0, 0.0}));
        Ribbons.Add(
            MakeRibbon(
                NodeB,
                FVector{Offset, 1000.1, 0.0},
                FVector{FarX, 7000.0, 0.0}));
    }

    auto BuildParams = FCk_PathNetwork_BuildParams{};
    BuildParams.Set_NodeSnapRadius(0.1f);
    const auto Network =
        Build_NetworkFromRibbons(
            Ribbons,
            BuildParams);
    const auto Topology = Analyze_NetworkTopology(Network);
    const auto Policy = MakeEndpointAwarePolicy(
        1.5f,
        8.0f,
        1.0f,
        0.0f,
        1000.0f);
    const auto Shared = Build_RouteGraphSharedData(
        Network,
        NodeA,
        NodeB,
        Policy);
    const auto FindNodeAt =
        [&Network](const FVector& InLocation) -> int32
        {
            for (auto NodeId = 0;
                 NodeId < Network._Nodes.Num();
                 ++NodeId)
            {
                if (Network._Nodes[NodeId]
                        ._Location.Equals(
                            InLocation,
                            0.1))
                { return NodeId; }
            }
            return INDEX_NONE;
        };
    const auto NodeAId = FindNodeAt(NodeA);
    const auto NodeBId = FindNodeAt(NodeB);

    TestEqual(TEXT("fixture produces two connected components"),
        Topology._ComponentCount,
        2);
    TestTrue(TEXT("fixture authored nodes are present"),
        NodeAId != INDEX_NONE
            && NodeBId != INDEX_NONE);
    TestEqual(TEXT("duplicate raw edge pairs become one canonical candidate"),
        Shared->_ComponentTransferCandidateCount,
        1);
    TestEqual(TEXT("canonical candidate remains classified edge-interior"),
        Shared->_ComponentTransferEdgeInteriorCandidateCount,
        1);
    TestEqual(TEXT("duplicates do not consume the geographic cap"),
        Shared->_ComponentTransferRejectedByCellCapCount,
        0);

    const auto* TransfersFromA =
        Shared->_ComponentTransfersByNode.Find(NodeAId);
    TestTrue(TEXT("the canonical node transfer is admitted once"),
        TransfersFromA != nullptr
            && TransfersFromA->Num() == 1
            && TransfersFromA->Contains(NodeBId));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_ComponentTransferFarMultiplierCharacterization,
    "Ck.PathNetwork.Route.ComponentTransfer.FarMultiplierCharacterization",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_ComponentTransferFarMultiplierCharacterization::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    constexpr auto AuthoredLegLength = 2000.0;
    constexpr auto LocalGapLength = 800.0;
    constexpr auto RemoteGapLength = 100.0;
    constexpr auto GapOffset = (LocalGapLength - RemoteGapLength) / 2.0;
    const auto Along = FMath::Sqrt(
        AuthoredLegLength * AuthoredLegLength - GapOffset * GapOffset);
    const auto NearA = FVector{0.0, 0.0, 0.0};
    const auto FarA = FVector{Along, GapOffset, 0.0};
    const auto NearB = FVector{0.0, LocalGapLength, 0.0};
    const auto FarB = FVector{Along, LocalGapLength - GapOffset, 0.0};
    const auto MakeRibbon =
        [](const FVector& InStart, const FVector& InEnd)
        {
            auto Points = TArray<FCk_PathNetwork_RibbonPoint>{
                FCk_PathNetwork_RibbonPoint{InStart, 100.0f},
                FCk_PathNetwork_RibbonPoint{InEnd, 100.0f}};
            auto Ribbon = FCk_PathNetwork_Ribbon{Points};
            Ribbon.Set_RibbonId(FGuid::NewGuid());
            return Ribbon;
        };
    auto BuildParams = FCk_PathNetwork_BuildParams{};
    BuildParams.Set_NodeSnapRadius(1.0f);
    const auto Network = Build_NetworkFromRibbons(
        {MakeRibbon(NearA, FarA), MakeRibbon(NearB, FarB)},
        BuildParams);
    const auto Topology = Analyze_NetworkTopology(Network);
    const auto FindNodeAt =
        [&Network](const FVector& InLocation) -> int32
        {
            for (auto NodeId = 0; NodeId < Network._Nodes.Num(); ++NodeId)
            {
                if (Network._Nodes[NodeId]._Location.Equals(InLocation))
                { return NodeId; }
            }
            return INDEX_NONE;
        };
    const auto NearANode = FindNodeAt(NearA);
    const auto FarANode = FindNodeAt(FarA);
    const auto NearBNode = FindNodeAt(NearB);
    const auto FarBNode = FindNodeAt(FarB);
    constexpr auto FarMultiplier = 8.0f;
    const auto Policy = MakeEndpointAwarePolicy(
        1.5f,
        FarMultiplier,
        1.0f,
        0.0f,
        1000.0f);
    auto LegacyAuthoredTuning = FCk_PathNetworkFollower_Tuning{};
    LegacyAuthoredTuning.Set_OffPathCostMultiplier(FarMultiplier);
    LegacyAuthoredTuning.Set_NearEndpointCostMultiplier(1.5f);
    LegacyAuthoredTuning.Set_NetworkGapCostMultiplier(0.0f);
    const auto LegacyResolvedPolicy =
        Resolve_RouteCostPolicy(LegacyAuthoredTuning);
    TestTrue(TEXT("public network-gap tuning keeps the zero inheritance sentinel"),
        FMath::IsNearlyZero(
            LegacyAuthoredTuning.Get_NetworkGapCostMultiplier()));
    TestTrue(TEXT("zero network-gap tuning resolves to the far/direct price"),
        FMath::IsNearlyEqual(
            LegacyResolvedPolicy._NetworkGapCostMultiplier,
            FarMultiplier));
    TestTrue(TEXT("legacy characterization policy uses the far/direct gap price"),
        FMath::IsNearlyEqual(
            Policy._NetworkGapCostMultiplier,
            FarMultiplier));

    if (NOT TestEqual(TEXT("two ribbons remain distinct components"),
            Topology._ComponentCount,
            2)
        || NOT TestTrue(TEXT("four transfer fixture nodes are present"),
            NearANode != INDEX_NONE
                && FarANode != INDEX_NONE
                && NearBNode != INDEX_NONE
                && FarBNode != INDEX_NONE))
    { return false; }

    const auto Shared = Build_RouteGraphSharedData(
        Network,
        NearA,
        NearB,
        Policy);
    const auto* NearTransfers =
        Shared->_ComponentTransfersByNode.Find(NearANode);
    const auto* FarTransfers =
        Shared->_ComponentTransfersByNode.Find(FarANode);
    TestEqual(TEXT("both qualifying transfer pairs reach admission"),
        Shared->_ComponentTransferCandidateCount,
        2);
    TestEqual(TEXT("fixture transfers are not rejected by the geographic cap"),
        Shared->_ComponentTransferRejectedByCellCapCount,
        0);
    TestTrue(TEXT("admission includes the 800cm local component transfer"),
        NearTransfers != nullptr && NearTransfers->Contains(NearBNode));
    TestTrue(TEXT("admission includes the 100cm remote component transfer"),
        FarTransfers != nullptr && FarTransfers->Contains(FarBNode));

    Shared->_AllowDirectStartToGoal = false;
    const auto Plan = Search_RouteGraph(
        Network,
        NearA,
        NearB,
        Policy,
        Shared);
    TestTrue(TEXT("far-multiplier characterization route succeeds"),
        Plan._Succeeded);

    const auto HasNearTransfer = Plan._Spans.ContainsByPredicate(
        [NearANode, NearBNode](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId == FRouteNodeId{ERouteNodeKind::NetNode, NearANode}
                && InSpan._ToId == FRouteNodeId{ERouteNodeKind::NetNode, NearBNode};
        });
    const auto HasFarTransfer = Plan._Spans.ContainsByPredicate(
        [FarANode, FarBNode](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId == FRouteNodeId{ERouteNodeKind::NetNode, FarANode}
                && InSpan._ToId == FRouteNodeId{ERouteNodeKind::NetNode, FarBNode};
        });
    TestFalse(TEXT("far multiplier rejects the admitted 800cm local transfer"),
        HasNearTransfer);
    TestTrue(TEXT("far multiplier selects the remote 100cm transfer"),
        HasFarTransfer);
    TestTrue(TEXT("remote transfer route pays 2000 + 100*8 + 2000"),
        FMath::IsNearlyEqual(Plan._EstimatedCost, 4800.0f, 1.0f));

    auto LowGapPolicy = Policy;
    LowGapPolicy._NetworkGapCostMultiplier = 1.5f;
    const auto LowGapShared = Build_RouteGraphSharedData(
        Network,
        NearA,
        NearB,
        LowGapPolicy);
    LowGapShared->_AllowDirectStartToGoal = false;
    const auto LowGapPlan = Search_RouteGraph(
        Network,
        NearA,
        NearB,
        LowGapPolicy,
        LowGapShared);
    TestTrue(TEXT("low network-gap multiplier route succeeds"),
        LowGapPlan._Succeeded);
    const auto LowGapUsesNearTransfer = LowGapPlan._Spans.ContainsByPredicate(
        [NearANode, NearBNode](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId == FRouteNodeId{ERouteNodeKind::NetNode, NearANode}
                && InSpan._ToId == FRouteNodeId{ERouteNodeKind::NetNode, NearBNode};
        });
    const auto LowGapUsesFarTransfer = LowGapPlan._Spans.ContainsByPredicate(
        [FarANode, FarBNode](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId == FRouteNodeId{ERouteNodeKind::NetNode, FarANode}
                && InSpan._ToId == FRouteNodeId{ERouteNodeKind::NetNode, FarBNode};
        });
    TestTrue(TEXT("low network-gap multiplier selects the admitted 800cm local transfer"),
        LowGapUsesNearTransfer);
    TestFalse(TEXT("low network-gap multiplier rejects the remote transfer detour"),
        LowGapUsesFarTransfer);
    TestTrue(TEXT("local transfer pays 800*1.5"),
        FMath::IsNearlyEqual(LowGapPlan._EstimatedCost, 1200.0f, 1.0f));

    const auto DirectStart = FVector{-1000.0, -1000.0, 0.0};
    const auto DirectGoal = FVector{-900.0, -1000.0, 0.0};
    const auto DirectGraph = FRouteGraph{
        &Network,
        DirectStart,
        DirectGoal,
        LowGapPolicy,
        MakeShared<FRouteGraphSharedData>()};
    const auto DirectResult = RunSearch(DirectGraph);
    TestTrue(TEXT("direct-only graph search completes"),
        DirectResult.Status == ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("gap multiplier cannot turn arbitrary direct travel into a network crossing"),
        DirectResult.Path.Num(),
        2);
    TestTrue(TEXT("arbitrary direct travel still pays 100*8"),
        FMath::IsNearlyEqual(DirectResult.TotalCost, 800.0f, 1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_LocalNetworkShortcutOptIn,
    "Ck.PathNetwork.Route.LocalNetworkShortcut.OptIn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_LocalNetworkShortcutOptIn::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeConnectedUNetwork();
    const auto Topology = Analyze_NetworkTopology(Network);
    const auto StartLocation = FVector{0, 0, 0};
    const auto GoalLocation = FVector{0, 1000, 0};
    constexpr auto NearMultiplier = 1.5f;
    constexpr auto FarMultiplier = 8.0f;
    constexpr auto JoinMaxDistance = 100.0f;
    constexpr auto LocalShortcutDistance = 1200.0f;
    constexpr auto LocalShortcutLength = 1000.0f;

    TestEqual(TEXT("U network is one connected component"),
        Topology._ComponentCount,
        1);

    const auto FindNodeAt =
        [&Network](const FVector& InLocation) -> int32
        {
            for (auto NodeId = 0; NodeId < Network._Nodes.Num(); ++NodeId)
            {
                if (Network._Nodes[NodeId]._Location.Equals(InLocation))
                { return NodeId; }
            }
            return INDEX_NONE;
        };
    const auto LeftLowerNode = FindNodeAt(StartLocation);
    const auto LeftUpperNode = FindNodeAt(GoalLocation);
    const auto RightLowerNode = FindNodeAt(FVector{10000, 0, 0});
    const auto RightUpperNode = FindNodeAt(FVector{10000, 1000, 0});
    TestTrue(TEXT("U endpoint nodes found"),
        LeftLowerNode != INDEX_NONE && LeftUpperNode != INDEX_NONE);
    TestTrue(TEXT("authored right-turn nodes found"),
        RightLowerNode != INDEX_NONE && RightUpperNode != INDEX_NONE);

    const auto DisabledPolicy = MakeEndpointAwarePolicy(
        NearMultiplier,
        FarMultiplier,
        JoinMaxDistance,
        0.0f);
    auto DisabledShared = Build_RouteGraphSharedData(
        Network,
        StartLocation,
        GoalLocation,
        DisabledPolicy);
    DisabledShared->_AllowDirectStartToGoal = false;
    const auto DisabledPlan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        DisabledPolicy,
        DisabledShared);
    TestTrue(TEXT("disabled local-shortcut search succeeds"), DisabledPlan._Succeeded);
    TestTrue(TEXT("disabled setting creates no local shortcut adjacency"),
        DisabledShared->_LocalNetworkShortcutsByNode.IsEmpty());
    TestTrue(TEXT("disabled setting follows the authored U"),
        FMath::IsNearlyEqual(DisabledPlan._EstimatedCost, 21000.0f, 1.0f));
    const auto DirectPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        DisabledPolicy);
    TestTrue(TEXT("direct comparison plan succeeds"), DirectPlan._Succeeded);
    TestFalse(TEXT("plain direct fallback does not claim network use"),
        Uses_Network(DirectPlan));

    const auto EnabledPolicy = MakeEndpointAwarePolicy(
        NearMultiplier,
        FarMultiplier,
        JoinMaxDistance,
        0.0f,
        0.0f,
        0.0f,
        LocalShortcutDistance);
    auto EnabledShared = Build_RouteGraphSharedData(
        Network,
        StartLocation,
        GoalLocation,
        EnabledPolicy);
    EnabledShared->_AllowDirectStartToGoal = false;
    const auto EnabledPlan = Search_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        EnabledPolicy,
        EnabledShared);
    TestTrue(TEXT("enabled local-shortcut search succeeds"), EnabledPlan._Succeeded);
    TestTrue(TEXT("exact-node local shortcut counts as network use"),
        Uses_Network(EnabledPlan));
    TestFalse(TEXT("exact-node shortcut route drops zero-length on-ribbon spans"),
        EnabledPlan._Spans.ContainsByPredicate(
            [](const FRouteLegSpan& InSpan)
            {
                return NOT InSpan._IsOffPath
                    && FMath::IsNearlyEqual(
                        InSpan._FromDist,
                        InSpan._ToDist,
                        KINDA_SMALL_NUMBER);
            }));

    const auto* LeftShortcutNodes =
        EnabledShared->_LocalNetworkShortcutsByNode.Find(LeftLowerNode);
    TestTrue(TEXT("enabled setting links the nearby U endpoints"),
        LeftShortcutNodes != nullptr && LeftShortcutNodes->Contains(LeftUpperNode));
    const auto* RightShortcutNodes =
        EnabledShared->_LocalNetworkShortcutsByNode.Find(RightLowerNode);
    TestTrue(TEXT("existing authored neighbors receive no redundant local shortcut"),
        RightShortcutNodes == nullptr || NOT RightShortcutNodes->Contains(RightUpperNode));

    const auto* ShortcutSpan = EnabledPlan._Spans.FindByPredicate(
        [](const FRouteLegSpan& InSpan)
        {
            return InSpan._IsOffPath
                && InSpan._FromId._Kind == ERouteNodeKind::NetNode
                && InSpan._ToId._Kind == ERouteNodeKind::NetNode;
        });
    TestNotNull(TEXT("enabled route uses a local network shortcut span"), ShortcutSpan);
    if (ShortcutSpan != nullptr)
    {
        const auto Graph = FRouteGraph{
            &Network,
            StartLocation,
            GoalLocation,
            EnabledPolicy,
            EnabledShared};
        const auto ShortcutLength = static_cast<float>(
            FVector::Dist(
                ShortcutSpan->_FromLocation,
                ShortcutSpan->_ToLocation));
        TestTrue(TEXT("span is classified as a local network shortcut"),
            Graph.Get_IsLocalNetworkShortcutHop(
                ShortcutSpan->_FromId,
                ShortcutSpan->_ToId));
        TestTrue(TEXT("local network shortcut pays the far off-network cost"),
            FMath::IsNearlyEqual(
                Graph.Get_OffPathCostForResolvedLength(
                    ShortcutSpan->_FromId,
                    ShortcutSpan->_ToId,
                    ShortcutLength),
                ShortcutLength * FarMultiplier,
                1.0f));
    }
    TestTrue(TEXT("local shortcut beats the 21000cm authored U"),
        FMath::IsNearlyEqual(
            EnabledPlan._EstimatedCost,
            LocalShortcutLength * FarMultiplier,
            1.0f));

    auto MinimumSavingsPolicy = EnabledPolicy;
    MinimumSavingsPolicy._DirectRouteMinimumSavingsFraction = 1.0f;
    const auto MinimumSavingsPlan = Plan_RouteGraph(
        Network,
        StartLocation,
        GoalLocation,
        MinimumSavingsPolicy);
    TestTrue(TEXT("minimum-savings planner succeeds"),
        MinimumSavingsPlan._Succeeded);
    TestTrue(TEXT("minimum-savings planner preserves network classification"),
        Uses_Network(MinimumSavingsPlan));
    TestNotNull(
        TEXT("minimum-savings planner selects the local crossing over direct fallback"),
        MinimumSavingsPlan._Spans.FindByPredicate(
            [](const FRouteLegSpan& InSpan)
            {
                return InSpan._IsOffPath
                    && InSpan._FromId._Kind == ERouteNodeKind::NetNode
                    && InSpan._ToId._Kind == ERouteNodeKind::NetNode;
            }));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_LocalNetworkShortcutBenefitRanking,
    "Ck.PathNetwork.Route.LocalNetworkShortcut.BenefitRanking",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_LocalNetworkShortcutBenefitRanking::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    const auto Network = MakeShortcutBenefitRankingNetwork();
    const auto FindNodeAt =
        [&Network](const FVector& InLocation) -> int32
        {
            for (auto NodeId = 0; NodeId < Network._Nodes.Num(); ++NodeId)
            {
                if (Network._Nodes[NodeId]._Location.Equals(InLocation))
                { return NodeId; }
            }
            return INDEX_NONE;
        };

    const auto SourceNode = FindNodeAt(FVector{0, 0, 0});
    const auto NearNodeA = FindNodeAt(FVector{-500, 0, 0});
    const auto NearNodeB = FindNodeAt(FVector{-400, 300, 0});
    const auto ValuableTargetNode = FindNodeAt(FVector{700, 0, 0});
    if (NOT TestTrue(
            TEXT("benefit-ranking fixture nodes found"),
            SourceNode != INDEX_NONE
                && NearNodeA != INDEX_NONE
                && NearNodeB != INDEX_NONE
                && ValuableTargetNode != INDEX_NONE))
    { return false; }

    const auto Policy = MakeEndpointAwarePolicy(
        1.5f,
        8.0f,
        100.0f,
        0.0f,
        0.0f,
        0.0f,
        800.0f);
    const auto Shared = Build_RouteGraphSharedData(
        Network,
        FVector{0, 0, 0},
        FVector{700, 0, 0},
        Policy);
    const auto* SourceShortcuts =
        Shared->_LocalNetworkShortcutsByNode.Find(SourceNode);

    TestTrue(
        TEXT("valuable farther crossing survives nearer low-value candidates"),
        SourceShortcuts != nullptr
            && SourceShortcuts->Contains(ValuableTargetNode));
    TestTrue(
        TEXT("closer authored detours that cost less than crossing are rejected"),
        SourceShortcuts == nullptr
            || (NOT SourceShortcuts->Contains(NearNodeA)
                && NOT SourceShortcuts->Contains(NearNodeB)));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Route_LocalNetworkShortcutDensityBudget,
    "Ck.PathNetwork.Route.LocalNetworkShortcut.DensityBudgetFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Route_LocalNetworkShortcutDensityBudget::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_route;
    using namespace ck::pathnetwork;

    // 130 mutually-near nodes create 8,256 non-neighbor pairs, just beyond
    // the fixed 8,192-pair safety budget.
    const auto Network = MakeDenseLocalNetwork(130);
    const auto Policy = MakeEndpointAwarePolicy(
        1.5f,
        8.0f,
        100.0f,
        0.0f,
        0.0f,
        0.0f,
        800.0f);
    const auto Shared = Build_RouteGraphSharedData(
        Network,
        FVector{-100, 0, 0},
        FVector{100, 0, 0},
        Policy);

    TestTrue(
        TEXT("dense local-shortcut candidate set reports its safety budget"),
        Shared->_LocalNetworkShortcutBudgetExceeded);
    TestTrue(
        TEXT("budget rejection publishes no partial shortcut graph"),
        Shared->_LocalNetworkShortcutsByNode.IsEmpty());
    TestTrue(
        TEXT("budget diagnostic preserves the observed candidate count"),
        Shared->_LocalNetworkShortcutCandidateCount > 8192);
    return true;
}
