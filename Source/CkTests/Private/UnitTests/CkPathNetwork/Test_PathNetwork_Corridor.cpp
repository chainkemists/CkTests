#include "Misc/AutomationTest.h"

#include "CkPathNetwork/Network/CkPathNetwork_Build.h"
#include "CkPathNetwork/Network/CkPathNetwork_CorridorCompile.h"
#include "CkPathNetwork/Network/CkPathNetwork_RouteGraph.h"
#include "CkPathNetwork/Network/CkPathNetwork_Types.h"
#include "CkPathNetwork/Network/CkPathNetwork_Utils.h"

// --------------------------------------------------------------------------------------------------------------------
// Pure corridor-compiler tests. These deliberately use only hand-authored ribbons and route spans:
// no world, navmesh, ECS, or route-search fixture is needed to prove the generated path geometry.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pathnetwork_corridor
{
    using namespace ck::pathnetwork;

    auto MakeRibbon(const TArray<FVector>& InLocations, const TArray<float>& InHalfWidths) -> FCk_PathNetwork_Ribbon
    {
        check(InLocations.Num() == InHalfWidths.Num());

        auto Points = TArray<FCk_PathNetwork_RibbonPoint>{};
        for (auto Index = 0; Index < InLocations.Num(); ++Index)
        { Points.Add(FCk_PathNetwork_RibbonPoint{InLocations[Index], InHalfWidths[Index]}); }

        auto Ribbon = FCk_PathNetwork_Ribbon{Points};
        Ribbon.Set_RibbonId(FGuid::NewGuid());
        return Ribbon;
    }

    auto MakeNetwork(const TArray<FVector>& InLocations, const TArray<float>& InHalfWidths) -> FBuiltNetwork
    {
        auto BuildParams = FCk_PathNetwork_BuildParams{};
        BuildParams.Set_NodeSnapRadius(1.0f);
        BuildParams.Set_ChunkSize(3200.0f);
        return Build_NetworkFromRibbons({MakeRibbon(InLocations, InHalfWidths)}, BuildParams);
    }

    auto MakeFullEdgeRun(const FBuiltNetwork& InNetwork, bool InReverse = false) -> TArray<FRouteLegSpan>
    {
        check(InNetwork._Edges.Num() == 1);
        const auto& Edge = InNetwork._Edges[0];

        auto Span = FRouteLegSpan{};
        Span._IsOffPath = false;
        Span._EdgeId = 0;
        Span._FromDist = InReverse ? Edge._Length : 0.0f;
        Span._ToDist = InReverse ? 0.0f : Edge._Length;
        Span._FromLocation = InNetwork.Sample_Edge(0, Span._FromDist)._Location;
        Span._ToLocation = InNetwork.Sample_Edge(0, Span._ToDist)._Location;
        return {Span};
    }

    auto MakeParams(float InSpacing, float InSmoothing, float InSideKeeping = 0.0f) -> FCorridorCompileParams
    {
        auto Params = FCorridorCompileParams{};
        Params._SideKeepingFraction = InSideKeeping;
        Params._WaypointSpacing = InSpacing;
        Params._CornerSmoothingDistance = InSmoothing;
        Params._RampSideOffsetAtStart = false;
        Params._RampSideOffsetAtEnd = false;
        return Params;
    }

    auto TestExactEndpoints(FAutomationTestBase& InTest, const TArray<FVector>& InPath, const FVector& InStart, const FVector& InEnd) -> bool
    {
        if (!InTest.TestTrue(TEXT("path has endpoints"), InPath.Num() >= 2))
        { return false; }

        InTest.TestTrue(TEXT("start endpoint is exact"), InPath[0].Equals(InStart, KINDA_SMALL_NUMBER));
        InTest.TestTrue(TEXT("end endpoint is exact"), InPath.Last().Equals(InEnd, KINDA_SMALL_NUMBER));
        return true;
    }

    auto TestContainedSegments(
        FAutomationTestBase& InTest,
        const FBuiltNetwork& InNetwork,
        const TArray<FRouteLegSpan>& InRun,
        const TArray<FVector>& InPath) -> bool
    {
        auto IsContained = true;
        for (auto Index = 1; Index < InPath.Num(); ++Index)
        {
            if (!Is_SegmentInsideRibbonRun(InNetwork, InRun, InPath[Index - 1], InPath[Index], 10.0f))
            {
                InTest.AddError(FString::Printf(TEXT("segment %d leaves its ribbon run"), Index - 1));
                IsContained = false;
            }
        }
        return IsContained;
    }

    auto HasPointNear(const TArray<FVector>& InPath, const FVector& InExpected, float InTolerance) -> bool
    {
        return InPath.ContainsByPredicate([&](const FVector& InPoint)
        {
            return InPoint.Equals(InExpected, InTolerance);
        });
    }

    auto CountStrictSelfIntersections2D(const TArray<FVector>& InPath) -> int32
    {
        const auto Orientation =
            [](const FVector& InA, const FVector& InB, const FVector& InC)
            {
                const auto AB = FVector2D{InB - InA};
                const auto AC = FVector2D{InC - InA};
                return AB.X * AC.Y - AB.Y * AC.X;
            };
        const auto HasOppositeOrientation =
            [](const double InA, const double InB)
            { return (InA > 0.01 && InB < -0.01) || (InA < -0.01 && InB > 0.01); };

        auto Count = 0;
        for (auto SegmentA = 0; SegmentA + 1 < InPath.Num(); ++SegmentA)
        {
            for (auto SegmentB = SegmentA + 2; SegmentB + 1 < InPath.Num(); ++SegmentB)
            {
                if (HasOppositeOrientation(
                        Orientation(InPath[SegmentA], InPath[SegmentA + 1], InPath[SegmentB]),
                        Orientation(InPath[SegmentA], InPath[SegmentA + 1], InPath[SegmentB + 1])) &&
                    HasOppositeOrientation(
                        Orientation(InPath[SegmentB], InPath[SegmentB + 1], InPath[SegmentA]),
                        Orientation(InPath[SegmentB], InPath[SegmentB + 1], InPath[SegmentA + 1])))
                { ++Count; }
            }
        }
        return Count;
    }

    auto Get_MaximumPlanarDistanceFromChord(const TArray<FVector>& InPath) -> float
    {
        if (InPath.Num() < 2)
        { return TNumericLimits<float>::Max(); }

        auto MaximumDistance = 0.0f;
        for (const auto& Point : InPath)
        {
            const auto Closest = FMath::ClosestPointOnSegment(
                Point,
                InPath[0],
                InPath.Last());
            MaximumDistance = FMath::Max(
                MaximumDistance,
                static_cast<float>(FVector::Dist2D(Point, Closest)));
        }
        return MaximumDistance;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_ValidatesPostNavRibbonTolerance,
    "Ck.PathNetwork.Corridor.ValidatesPostNavRibbonTolerance",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_ValidatesPostNavRibbonTolerance::RunTest(
    const FString& Parameters)
{
    auto Tuning = FCk_PathNetworkFollower_Tuning{};
    TestTrue(
        TEXT("packaged default post-nav ribbon tolerance is valid"),
        UCk_Utils_PathNetworkFollower_UE::Get_IsTuningValid(Tuning));
    TestEqual(
        TEXT("packaged default post-nav ribbon tolerance is ten centimeters"),
        Tuning.Get_NavmeshResolvedRibbonTolerance(),
        10.0f);

    Tuning.Set_NavmeshResolvedRibbonTolerance(100.01f);
    TestFalse(
        TEXT("out-of-range post-nav ribbon tolerance is rejected"),
        UCk_Utils_PathNetworkFollower_UE::Get_IsTuningValid(Tuning));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_AvoidsSideOffsetLoopsOnRasterCurve,
    "Ck.PathNetwork.Corridor.AvoidsSideOffsetLoopsOnRasterCurve",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_AvoidsSideOffsetLoopsOnRasterCurve::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {
            FVector{0, 0, 0},
            FVector{0, 100, 0},
            FVector{100, 100, 0},
            FVector{100, 200, 0},
            FVector{200, 200, 0},
            FVector{200, 300, 0},
            FVector{300, 300, 0},
            FVector{300, 400, 0},
            FVector{400, 400, 0},
            FVector{400, 500, 0}
        },
        {
            250.0f, 250.0f, 250.0f, 250.0f, 250.0f,
            250.0f, 250.0f, 250.0f, 250.0f, 250.0f
        });
    const auto Run = MakeFullEdgeRun(Network);
    const auto CenteredPath = Compile_OnRibbonRun(
        Network,
        Run,
        MakeParams(250.0f, 150.0f, 0.0f));
    const auto Path = Compile_OnRibbonRun(
        Network,
        Run,
        MakeParams(250.0f, 150.0f, 0.5f));

    TestTrue(TEXT("raster-scale curve still compiles"), Path.Num() >= 2);
    TestTrue(
        TEXT("alternating raster controls collapse to their contained chord"),
        Get_MaximumPlanarDistanceFromChord(CenteredPath) <= 1.0f);
    auto RetainedSideKeeping = false;
    if (Path.Num() == CenteredPath.Num())
    {
        for (auto Index = 0; Index < Path.Num(); ++Index)
        {
            if (NOT Path[Index].Equals(CenteredPath[Index], KINDA_SMALL_NUMBER))
            {
                RetainedSideKeeping = true;
                break;
            }
        }
    }
    TestTrue(
        TEXT("safe simplified curve retains requested side keeping"),
        RetainedSideKeeping);
    TestEqual(
        TEXT("side keeping cannot fold a raster-scale curve across itself"),
        CountStrictSelfIntersections2D(Path),
        0);
    TestContainedSegments(*this, Network, Run, Path);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_PreservesVerticalProfileOnRasterTurn,
    "Ck.PathNetwork.Corridor.PreservesVerticalProfileOnRasterTurn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_PreservesVerticalProfileOnRasterTurn::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {
            FVector{0, 0, 0},
            FVector{0, 100, 0},
            FVector{100, 100, 100},
            FVector{100, 200, 100},
            FVector{200, 200, 0}
        },
        {250.0f, 250.0f, 250.0f, 250.0f, 250.0f});
    const auto Run = MakeFullEdgeRun(Network);
    const auto Path = Compile_OnRibbonRun(
        Network,
        Run,
        MakeParams(100.0f, 150.0f, 0.0f));

    auto MaximumHeight = -TNumericLimits<float>::Max();
    for (const auto& Waypoint : Path)
    { MaximumHeight = FMath::Max(MaximumHeight, static_cast<float>(Waypoint.Z)); }

    TestTrue(TEXT("graded raster route still compiles"), Path.Num() >= 2);
    TestTrue(
        TEXT("raster simplification preserves the authored vertical profile"),
        MaximumHeight >= 75.0f);
    TestContainedSegments(*this, Network, Run, Path);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_PreservesSideKeepingAcrossOverpass,
    "Ck.PathNetwork.Corridor.PreservesSideKeepingAcrossOverpass",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_PreservesSideKeepingAcrossOverpass::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {
            FVector{-300, -300, 0},
            FVector{300, 300, 0},
            FVector{300, -300, 300},
            FVector{-300, 300, 300}
        },
        {250.0f, 250.0f, 250.0f, 250.0f});
    const auto Run = MakeFullEdgeRun(Network);
    const auto CenteredPath = Compile_OnRibbonRun(
        Network,
        Run,
        MakeParams(100.0f, 0.0f, 0.0f));
    const auto SideKeptPath = Compile_OnRibbonRun(
        Network,
        Run,
        MakeParams(100.0f, 0.0f, 0.5f));

    TestTrue(TEXT("overpass route still compiles"), SideKeptPath.Num() >= 2);
    TestEqual(
        TEXT("overpass side-kept and centered paths have comparable sampling"),
        SideKeptPath.Num(),
        CenteredPath.Num());
    auto RetainedSideKeeping = false;
    if (SideKeptPath.Num() == CenteredPath.Num())
    {
        for (auto Index = 0; Index < SideKeptPath.Num(); ++Index)
        {
            if (NOT SideKeptPath[Index].Equals(CenteredPath[Index], KINDA_SMALL_NUMBER))
            {
                RetainedSideKeeping = true;
                break;
            }
        }
    }
    TestTrue(
        TEXT("vertical separation preserves requested side keeping"),
        RetainedSideKeeping);
    TestContainedSegments(*this, Network, Run, SideKeptPath);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_AcceptsProjectionSlackButRejectsEscape,
    "Ck.PathNetwork.Corridor.AcceptsProjectionSlackButRejectsEscape",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_AcceptsProjectionSlackButRejectsEscape::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {FVector{0, 0, 0}, FVector{500, 0, 0}},
        {100.0f, 100.0f});
    const auto Run = MakeFullEdgeRun(Network);

    TestTrue(
        TEXT("nav-projection noise within the shared tolerance remains in the ribbon"),
        Is_SegmentInsideRibbonRun(
            Network,
            Run,
            FVector{0, 101.36, 0},
            FVector{500, 101.36, 0}));
    TestFalse(
        TEXT("a segment beyond the shared tolerance still leaves the ribbon"),
        Is_SegmentInsideRibbonRun(
            Network,
            Run,
            FVector{0, 102.25, 0},
            FVector{500, 102.25, 0}));
    TestFalse(
        TEXT("the live resolved-nav miss remains outside strict compiled containment"),
        Is_SegmentInsideRibbonRun(
            Network,
            Run,
            FVector{0, 105.66, 0},
            FVector{500, 105.66, 0},
            RibbonContainmentSampleSpacingCm,
            RibbonContainmentToleranceCm));
    TestTrue(
        TEXT("the packaged post-nav allowance accepts the live resolved-nav miss"),
        Is_SegmentInsideRibbonRun(
            Network,
            Run,
            FVector{0, 105.66, 0},
            FVector{500, 105.66, 0},
            RibbonContainmentSampleSpacingCm,
            RibbonContainmentToleranceCm +
                FCk_PathNetworkFollower_Tuning{}
                    .Get_NavmeshResolvedRibbonTolerance()));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_RoundsNinetyDegreeInsideRibbon,
    "Ck.PathNetwork.Corridor.RoundsNinetyDegreeInsideRibbon",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_RoundsNinetyDegreeInsideRibbon::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {FVector{0, 0, 0}, FVector{200, 0, 0}, FVector{200, 200, 0}},
        {100.0f, 100.0f, 100.0f});
    if (!TestEqual(TEXT("one L-shaped edge"), Network._Edges.Num(), 1))
    { return false; }

    const auto Run = MakeFullEdgeRun(Network);
    const auto Path = Compile_OnRibbonRun(Network, Run, MakeParams(1000.0f, 100.0f));
    if (!TestExactEndpoints(*this, Path, FVector{0, 0, 0}, FVector{200, 200, 0}))
    { return false; }

    // The old uniform resampling emitted start/end only at this spacing, cutting diagonally through
    // the L. The rounded result must have a contained arc rather than a single sharp shortcut.
    TestTrue(TEXT("rounded corner emits intermediate waypoints"), Path.Num() > 2);
    TestContainedSegments(*this, Network, Run, Path);

    auto LargestHeadingChangeDegrees = 0.0f;
    for (auto Index = 1; Index + 1 < Path.Num(); ++Index)
    {
        const auto Before = (Path[Index] - Path[Index - 1]).GetSafeNormal2D();
        const auto After = (Path[Index + 1] - Path[Index]).GetSafeNormal2D();
        if (!Before.IsNearlyZero() && !After.IsNearlyZero())
        {
            LargestHeadingChangeDegrees = FMath::Max(
                LargestHeadingChangeDegrees,
                FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(Before, After), -1.0f, 1.0f))));
        }
    }
    TestTrue(FString::Printf(TEXT("no internal corner is jagged (max %.1f deg)"), LargestHeadingChangeDegrees),
        LargestHeadingChangeDegrees <= 55.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_PreservesCornerAtSparseSpacing,
    "Ck.PathNetwork.Corridor.PreservesCornerAtSparseSpacing",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_PreservesCornerAtSparseSpacing::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {FVector{0, 0, 0}, FVector{200, 0, 0}, FVector{200, 200, 0}},
        {100.0f, 100.0f, 100.0f});
    const auto Run = MakeFullEdgeRun(Network);
    const auto Path = Compile_OnRibbonRun(Network, Run, MakeParams(1000.0f, 0.0f));

    if (!TestExactEndpoints(*this, Path, FVector{0, 0, 0}, FVector{200, 200, 0}))
    { return false; }

    TestTrue(TEXT("unsmoothed sparse route preserves the authored corner"),
        HasPointNear(Path, FVector{200, 0, 0}, 1.0f));
    TestContainedSegments(*this, Network, Run, Path);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_KeepsOpposingDirectionsOnOppositeSides,
    "Ck.PathNetwork.Corridor.KeepsOpposingDirectionsOnOppositeSides",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_KeepsOpposingDirectionsOnOppositeSides::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork({FVector{0, 0, 0}, FVector{1000, 0, 0}}, {100.0f, 100.0f});
    const auto ForwardRun = MakeFullEdgeRun(Network);
    const auto ReverseRun = MakeFullEdgeRun(Network, true);
    const auto Params = MakeParams(100.0f, 0.0f, 0.5f);

    const auto Forward = Compile_OnRibbonRun(Network, ForwardRun, Params);
    const auto Reverse = Compile_OnRibbonRun(Network, ReverseRun, Params);
    if (!TestTrue(TEXT("forward route has an interior point"), Forward.Num() > 2) ||
        !TestTrue(TEXT("reverse route has an interior point"), Reverse.Num() > 2))
    { return false; }

    const auto ForwardY = Forward[Forward.Num() / 2].Y;
    const auto ReverseY = Reverse[Reverse.Num() / 2].Y;
    TestTrue(FString::Printf(TEXT("opposing travel uses opposite sides (%.1f, %.1f)"), ForwardY, ReverseY),
        ForwardY * ReverseY < 0.0f);
    TestContainedSegments(*this, Network, ForwardRun, Forward);
    TestContainedSegments(*this, Network, ReverseRun, Reverse);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_TJunctionStraightRouteDoesNotBacktrack,
    "Ck.PathNetwork.Corridor.TJunctionStraightRouteDoesNotBacktrack",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_TJunctionStraightRouteDoesNotBacktrack::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;
    using namespace ck::pathnetwork;

    auto Bottom = MakeRibbon(
        {
            FVector{-1450, -650, 0},
            FVector{0, -650, 0},
            FVector{1450, -650, 0}
        },
        {140.0f, 140.0f, 140.0f});
    const auto BottomId = Bottom.Get_RibbonId();

    auto Ribbons = TArray<FCk_PathNetwork_Ribbon>{};
    Ribbons.Add(MoveTemp(Bottom));
    Ribbons.Add(MakeRibbon(
        {
            FVector{0, -750, 0},
            FVector{0, 750, 0}
        },
        {140.0f, 140.0f}));

    auto BuildParams = FCk_PathNetwork_BuildParams{};
    BuildParams.Set_NodeSnapRadius(150.0f);
    BuildParams.Set_ChunkSize(3200.0f);
    const auto Network = Build_NetworkFromRibbons(Ribbons, BuildParams);

    auto BottomEdgeIds = TArray<int32>{};
    for (auto EdgeId = 0; EdgeId < Network._Edges.Num(); ++EdgeId)
    {
        if (Network._Edges[EdgeId]._SourceRibbonId == BottomId)
        { BottomEdgeIds.Add(EdgeId); }
    }
    BottomEdgeIds.Sort([&](int32 InA, int32 InB)
    { return Network._Edges[InA]._Points[0].X < Network._Edges[InB]._Points[0].X; });

    if (NOT TestEqual(TEXT("T-junction splits the straight branch into two edges"), BottomEdgeIds.Num(), 2))
    { return false; }

    auto Run = TArray<FRouteLegSpan>{};
    for (const auto EdgeId : BottomEdgeIds)
    {
        const auto& Edge = Network._Edges[EdgeId];
        auto Span = FRouteLegSpan{};
        Span._EdgeId = EdgeId;
        Span._FromDist = 0.0f;
        Span._ToDist = Edge._Length;
        Span._FromLocation = Network.Sample_Edge(EdgeId, 0.0f)._Location;
        Span._ToLocation = Network.Sample_Edge(EdgeId, Edge._Length)._Location;
        Run.Add(Span);
    }

    const auto Path = Compile_OnRibbonRun(Network, Run, MakeParams(250.0f, 150.0f, 0.5f));
    if (NOT TestTrue(TEXT("straight T-junction branch compiles a path"), Path.Num() >= 2))
    { return false; }

    auto WorstForwardDeltaX = TNumericLimits<double>::Max();
    auto WorstSegmentIndex = int32{INDEX_NONE};
    for (auto Index = 1; Index < Path.Num(); ++Index)
    {
        const auto DeltaX = Path[Index].X - Path[Index - 1].X;
        if (DeltaX < WorstForwardDeltaX)
        {
            WorstForwardDeltaX = DeltaX;
            WorstSegmentIndex = Index - 1;
        }
    }

    TestTrue(
        FString::Printf(
            TEXT("eastbound straight branch never backtracks (worst segment %d delta-x %.3f)"),
            WorstSegmentIndex,
            WorstForwardDeltaX),
        WorstForwardDeltaX >= -1.0);
    TestContainedSegments(*this, Network, Run, Path);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_ClampsJoinForVariableWidth,
    "Ck.PathNetwork.Corridor.ClampsJoinForVariableWidth",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_ClampsJoinForVariableWidth::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    const auto Network = MakeNetwork(
        {FVector{0, 0, 0}, FVector{200, 0, 0}, FVector{200, 200, 0}},
        {100.0f, 40.0f, 100.0f});
    const auto Run = MakeFullEdgeRun(Network);
    const auto Path = Compile_OnRibbonRun(Network, Run, MakeParams(1000.0f, 200.0f));

    TestTrue(TEXT("variable-width join emits a route"), Path.Num() > 2);
    TestFalse(TEXT("variable-width join still uses a bounded fillet"),
        HasPointNear(Path, FVector{200, 0, 0}, 1.0f));
    TestContainedSegments(*this, Network, Run, Path);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_DoesNotRoundUTurn,
    "Ck.PathNetwork.Corridor.DoesNotRoundUTurn",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_DoesNotRoundUTurn::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;

    // The final point is deliberately 10cm short of the start so the builder keeps two distinct
    // endpoint nodes while the polyline still contains an unambiguous near-180-degree reversal.
    // Construct the plain built-edge value directly. Build_NetworkFromRibbons intentionally
    // splits the overlapping return segment; this test targets only corridor compilation.
    auto Network = FBuiltNetwork{};
    auto Edge = FBuiltEdge{};
    Edge._Points = {FVector{0, 0, 0}, FVector{200, 0, 0}, FVector{10, 0, 0}};
    Edge._HalfWidths = {100.0f, 100.0f, 100.0f};
    Edge._CumulativeLengths = {0.0f, 200.0f, 390.0f};
    Edge._Length = 390.0f;
    Network._Edges.Add(MoveTemp(Edge));

    const auto Run = MakeFullEdgeRun(Network);
    const auto Path = Compile_OnRibbonRun(Network, Run, MakeParams(1000.0f, 200.0f));

    TestTrue(TEXT("hairpin keeps a reversal anchor instead of collapsing to a shortcut"),
        Path.ContainsByPredicate([](const FVector& InPoint) { return InPoint.X >= 195.0f; }));
    TestContainedSegments(*this, Network, Run, Path);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_Corridor_RejectsDisconnectedRun,
    "Ck.PathNetwork.Corridor.RejectsDisconnectedRun",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_Corridor_RejectsDisconnectedRun::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_corridor;
    using namespace ck::pathnetwork;

    auto Network = FBuiltNetwork{};
    auto FirstEdge = FBuiltEdge{};
    FirstEdge._Points = {FVector{0, 0, 0}, FVector{100, 0, 0}};
    FirstEdge._HalfWidths = {20.0f, 20.0f};
    FirstEdge._CumulativeLengths = {0.0f, 100.0f};
    FirstEdge._Length = 100.0f;
    Network._Edges.Add(MoveTemp(FirstEdge));

    auto SecondEdge = FBuiltEdge{};
    SecondEdge._Points = {FVector{500, 0, 0}, FVector{600, 0, 0}};
    SecondEdge._HalfWidths = {20.0f, 20.0f};
    SecondEdge._CumulativeLengths = {0.0f, 100.0f};
    SecondEdge._Length = 100.0f;
    Network._Edges.Add(MoveTemp(SecondEdge));

    auto Spans = TArray<FRouteLegSpan>{};
    for (auto EdgeId = 0; EdgeId < 2; ++EdgeId)
    {
        auto Span = FRouteLegSpan{};
        Span._EdgeId = EdgeId;
        Span._FromDist = 0.0f;
        Span._ToDist = Network._Edges[EdgeId]._Length;
        Spans.Add(Span);
    }

    const auto Path = Compile_OnRibbonRun(Network, Spans, MakeParams(1000.0f, 100.0f));
    TestTrue(TEXT("disconnected spans fail closed"), Path.IsEmpty());
    return true;
}
