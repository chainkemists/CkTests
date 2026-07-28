#include "Misc/AutomationTest.h"

#include "CkPathNetwork/Network/CkPathNetwork_Build.h"
#include "CkPathNetwork/Network/CkPathNetwork_Types.h"

// --------------------------------------------------------------------------------------------------------------------
// Pure-math builder tests: hand-authored ribbons in, graph topology out. No world, no ECS.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pathnetwork_build
{
    auto MakeRibbon(const TArray<FVector>& InPoints, float InHalfWidth = 100.0f) -> FCk_PathNetwork_Ribbon
    {
        auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
        for (const auto& Location : InPoints)
        { Points.Add(FCk_PathNetwork_RibbonPoint{Location, InHalfWidth}); }

        auto Ribbon = FCk_PathNetwork_Ribbon{Points};
        Ribbon.Set_RibbonId(FGuid::NewGuid());
        return Ribbon;
    }

    auto DefaultParams() -> FCk_PathNetwork_BuildParams
    {
        auto Params = FCk_PathNetwork_BuildParams{};
        Params.Set_NodeSnapRadius(150.0f);
        Params.Set_ChunkSize(3200.0f);
        return Params;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Build_EndpointFusion,
    "Ck.PathNetwork.Build.EndpointFusion",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Build_EndpointFusion::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_build;

    // Two ribbons meeting end-to-end (40cm gap, inside the 150cm snap radius): A--B--C.
    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    Ribbons.Add(MakeRibbon({FVector{0, 0, 0}, FVector{2000, 0, 0}}));
    Ribbons.Add(MakeRibbon({FVector{2040, 0, 0}, FVector{2040, 2000, 0}}));

    const auto Network = ck::pathnetwork::Build_NetworkFromRibbons(Ribbons, DefaultParams());

    TestEqual(TEXT("three nodes"), Network._Nodes.Num(), 3);
    TestEqual(TEXT("two edges"), Network._Edges.Num(), 2);
    if (Network._Nodes.Num() != 3 || Network._Edges.Num() != 2)
    { return false; }

    // Exactly one node carries both edges (the fused middle).
    auto MiddleNodeCount = 0;
    auto MiddleLocation = FVector::ZeroVector;
    for (const auto& Node : Network._Nodes)
    {
        if (Node._EdgeIds.Num() == 2)
        {
            ++MiddleNodeCount;
            MiddleLocation = Node._Location;
        }
    }
    TestEqual(TEXT("one shared node"), MiddleNodeCount, 1);

    // Fused node sits at the endpoint centroid ~(2020, 0).
    TestTrue(FString::Printf(TEXT("middle node at centroid (got %.0f, %.0f)"), MiddleLocation.X, MiddleLocation.Y),
        FVector::Dist(MiddleLocation, FVector{2020, 0, 0}) < 25.0);

    // Both edges' geometry was snapped onto the shared node exactly.
    for (const auto& Edge : Network._Edges)
    {
        const auto TouchesMiddle =
            FVector::Dist(Edge._Points[0], MiddleLocation) < 1.0 ||
            FVector::Dist(Edge._Points.Last(), MiddleLocation) < 1.0;
        TestTrue(TEXT("edge geometry snapped to node"), TouchesMiddle);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Build_TJunctionSplit,
    "Ck.PathNetwork.Build.TJunctionSplit",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Build_TJunctionSplit::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_build;

    // The vertical endpoint snaps to an authored horizontal midpoint, matching the sidewalk
    // fixture where the split point must not be duplicated as an interior control point.
    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    Ribbons.Add(MakeRibbon({FVector{0, 0, 0}, FVector{2000, 0, 0}, FVector{4000, 0, 0}}));
    Ribbons.Add(MakeRibbon({FVector{2000, 60, 0}, FVector{2000, 3000, 0}}));

    const auto Network = ck::pathnetwork::Build_NetworkFromRibbons(Ribbons, DefaultParams());

    TestEqual(TEXT("four nodes (two bar ends, junction, stem end)"), Network._Nodes.Num(), 4);
    TestEqual(TEXT("three edges (split bar + stem)"), Network._Edges.Num(), 3);
    if (Network._Nodes.Num() != 4 || Network._Edges.Num() != 3)
    { return false; }

    auto JunctionCount = 0;
    auto JunctionLocation = FVector::ZeroVector;
    for (const auto& Node : Network._Nodes)
    {
        if (Node._EdgeIds.Num() == 3)
        {
            ++JunctionCount;
            JunctionLocation = Node._Location;
        }
    }

    TestEqual(TEXT("one 3-way junction"), JunctionCount, 1);
    TestTrue(FString::Printf(TEXT("junction near (2000, 0) (got %.0f, %.0f)"), JunctionLocation.X, JunctionLocation.Y),
        FVector::Dist2D(JunctionLocation, FVector{2000, 0, 0}) < 100.0);

    for (const auto& Edge : Network._Edges)
    {
        TestEqual(
            TEXT("split fixture edge has no duplicate cut control"),
            Edge._Points.Num(),
            2);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Build_ProjectAndSample,
    "Ck.PathNetwork.Build.ProjectAndSample",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Build_ProjectAndSample::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_build;

    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    Ribbons.Add(MakeRibbon({FVector{0, 0, 0}, FVector{1000, 0, 0}}, 80.0f));

    const auto Network = ck::pathnetwork::Build_NetworkFromRibbons(Ribbons, DefaultParams());

    TestEqual(TEXT("one edge"), Network._Edges.Num(), 1);
    if (Network._Edges.Num() != 1)
    { return false; }

    const auto Projection = Network.Project_OntoEdge(0, FVector{500, 300, 0});
    TestEqual(TEXT("projection edge id"), Projection._EdgeId, 0);
    TestTrue(FString::Printf(TEXT("dist-along ~500 (got %.1f)"), Projection._DistAlong),
        FMath::Abs(Projection._DistAlong - 500.0f) < 1.0f);
    TestTrue(FString::Printf(TEXT("distance ~300 (got %.1f)"), Projection._Distance),
        FMath::Abs(Projection._Distance - 300.0f) < 1.0f);
    TestTrue(TEXT("projected location on centerline"),
        FVector::Dist(Projection._Location, FVector{500, 0, 0}) < 1.0);

    const auto Sample = Network.Sample_Edge(0, 250.0f);
    TestTrue(TEXT("sample location"), FVector::Dist(Sample._Location, FVector{250, 0, 0}) < 1.0);
    TestTrue(TEXT("sample tangent +X"), FVector::DotProduct(Sample._Tangent, FVector::ForwardVector) > 0.99);
    TestTrue(FString::Printf(TEXT("sample half-width (got %.1f)"), Sample._HalfWidth),
        FMath::Abs(Sample._HalfWidth - 80.0f) < 1.0f);

    // Clamping: sampling past the end returns the end.
    const auto PastEnd = Network.Sample_Edge(0, 99999.0f);
    TestTrue(TEXT("past-end sample clamps"), FVector::Dist(PastEnd._Location, Network._Edges[0]._Points.Last()) < 1.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Build_ChunkQuery,
    "Ck.PathNetwork.Build.ChunkQuery",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Build_ChunkQuery::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_build;

    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    Ribbons.Add(MakeRibbon({FVector{0, 0, 0}, FVector{10000, 0, 0}}));
    Ribbons.Add(MakeRibbon({FVector{0, 20000, 0}, FVector{10000, 20000, 0}}));

    const auto Network = ck::pathnetwork::Build_NetworkFromRibbons(Ribbons, DefaultParams());

    TestEqual(TEXT("two edges"), Network._Edges.Num(), 2);
    TestTrue(TEXT("chunk grid populated"), Network._ChunkVersions.Num() > 0);

    // Near the first edge: finds it, not the far one.
    const auto NearFirst = Network.Query_EdgesNear(FVector{5000, 200, 0}, 500.0f);
    TestTrue(TEXT("query near first edge finds it"), NearFirst.Contains(0));
    TestFalse(TEXT("query near first edge excludes the far edge"), NearFirst.Contains(1));

    // Versions all start at 1.
    for (const auto Version : Network._ChunkVersions)
    { TestEqual(TEXT("initial chunk version"), static_cast<int32>(Version), 1); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Build_DegenerateInputs,
    "Ck.PathNetwork.Build.DegenerateInputs",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Build_DegenerateInputs::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_build;

    // Empty input.
    const auto EmptyNetwork = ck::pathnetwork::Build_NetworkFromRibbons({}, DefaultParams());
    TestEqual(TEXT("empty input -> no nodes"), EmptyNetwork._Nodes.Num(), 0);
    TestEqual(TEXT("empty input -> no edges"), EmptyNetwork._Edges.Num(), 0);

    // Single-point and zero-length ribbons are dropped without ensures.
    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    Ribbons.Add(MakeRibbon({FVector{0, 0, 0}}));
    Ribbons.Add(MakeRibbon({FVector{100, 0, 0}, FVector{100, 0, 0}}));

    const auto Network = ck::pathnetwork::Build_NetworkFromRibbons(Ribbons, DefaultParams());
    TestEqual(TEXT("degenerate ribbons -> no edges"), Network._Edges.Num(), 0);

    return true;
}
