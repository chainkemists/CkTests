// Strict-cell heuristic checks use public PathSearch only. W0 is the same graph with its heuristic
// disabled, so it is a Dijkstra reference for each field and query row.

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"

#include "../CkUnitTest_Common.h"
#include "Test_GroundNav_QueryFixtures.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_strictsearchheuristic
{
    using ck::groundnav::ECk_GroundNav_CellRouteEdgeKind;
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::ECk_GroundNav_PathRouteKind;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleObb;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_TwoRouteScene;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    constexpr auto kMaxSearchIterations = 20'000;
    constexpr auto kCostTolerance = 0.01f;
    constexpr auto kLegacyFreeExpansionCount = 3'685;
    constexpr auto kRequiredFreeExpansionCeiling = kLegacyFreeExpansionCount / 4;

    struct FRun
    {
        ECk_GroundNav_PathStatus _Status = ECk_GroundNav_PathStatus::InProgress;
        FCk_GroundNav_PathResult _Result;
    };

    auto MakeHighDiscSnapshot() -> TOptional<FCk_GroundNav_DynamicObstacleSnapshot>
    {
        auto Discs = TArray<FCk_GroundNav_DynamicObstacleDisc>{};
        Discs.Reserve(9);
        for (auto Index = 0; Index < 9; ++Index)
        {
            auto Disc = FCk_GroundNav_DynamicObstacleDisc{};
            const auto Along = 450.0f + static_cast<float>(Index) * 75.0f;
            Disc._Centre = FVector{Along, Along, 10'000.0};
            Disc._RadiusUu = 55.0f;
            Disc._VerticalHalfExtentUu = 30.0f;
            Discs.Add(Disc);
        }

        return Try_MakeDynamicObstacleSnapshot(Discs, TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{});
    }

    auto RunToTerminal(const FCk_GroundNav_FieldPtr& InField, const FCk_GroundNav_PathQuery& InQuery) -> FRun
    {
        auto Search = FCk_GroundNav_PathSearch{};
        auto Run = FRun{};
        Run._Status = Search.Request_Begin(InField, InQuery);

        auto Slice = FCk_GroundNav_PathSliceParams{};
        Slice._MaxIterations = 0;
        for (auto Iteration = 0; Iteration < kMaxSearchIterations && NOT Search.Get_IsTerminal(); ++Iteration)
        { Run._Status = Search.ContinueSearch(Slice); }

        if (NOT Search.Get_IsTerminal()) { return Run; }
        Run._Status = Search.Get_Status();
        Run._Result = Search.Get_Result();
        return Run;
    }

    auto Get_HasFiniteClearStrictRoute(const FRun& InRun) -> bool
    {
        if (InRun._Result._RouteKind != ECk_GroundNav_PathRouteKind::StrictCell ||
            InRun._Result._CellRoute.IsEmpty() || NOT FMath::IsFinite(InRun._Result._SearchCost))
        { return false; }

        for (const auto& Edge : InRun._Result._CellRoute)
        {
            if (Edge._FromPoint.ContainsNaN() || Edge._ToPoint.ContainsNaN()) { return false; }
            if (Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link) { continue; }
            const auto Union = Get_DynamicUnionEdge(
                InRun._Result._DynamicObstacles, Edge._FromPoint, Edge._ToPoint);
            if (NOT Union.IsSet() || *Union != ECk_GroundNav_DynamicUnionEdge::Clear) { return false; }
        }

        return true;
    }

    auto VerifyDijkstraParity(
        FAutomationTestBase& InTest,
        const TCHAR* InName,
        const FCk_GroundNav_FieldPtr& InField,
        FCk_GroundNav_PathQuery InQuery,
        FRun& OutW1,
        bool InExpectWorkReduction = false) -> bool
    {
        auto W0Query = InQuery;
        W0Query._GreedyWeightW = 0.0f;
        InQuery._GreedyWeightW = 1.0f;

        const auto W0 = RunToTerminal(InField, W0Query);
        OutW1 = RunToTerminal(InField, InQuery);
        InTest.AddInfo(FString::Printf(TEXT("[STRICT-HEURISTIC] %s w0Expansions=%d w1Expansions=%d w0Cost=%.6f w1Cost=%.6f"),
            InName, W0._Result._ExpansionCount, OutW1._Result._ExpansionCount,
            W0._Result._SearchCost, OutW1._Result._SearchCost));

        const auto W0Ready = InTest.TestEqual(*FString::Printf(TEXT("%s W0 Dijkstra resolves"), InName),
            W0._Status, ECk_GroundNav_PathStatus::Ready);
        const auto W1Ready = InTest.TestEqual(*FString::Printf(TEXT("%s W1 resolves"), InName),
            OutW1._Status, ECk_GroundNav_PathStatus::Ready);
        if (NOT W0Ready || NOT W1Ready) { return false; }

        const auto Strict = InTest.TestEqual(*FString::Printf(TEXT("%s remains strict-cell"), InName),
            OutW1._Result._RouteKind, ECk_GroundNav_PathRouteKind::StrictCell);
        const auto W0Strict = InTest.TestEqual(*FString::Printf(TEXT("%s W0 remains strict-cell"), InName),
            W0._Result._RouteKind, ECk_GroundNav_PathRouteKind::StrictCell);
        const auto SameCost = InTest.TestTrue(*FString::Printf(TEXT("%s W1 preserves the W0 optimum"), InName),
            FMath::Abs(W0._Result._SearchCost - OutW1._Result._SearchCost) <= kCostTolerance);
        const auto W0ValidRoute = InTest.TestTrue(*FString::Printf(TEXT("%s W0 route is finite and clear"), InName),
            Get_HasFiniteClearStrictRoute(W0));
        const auto ValidRoute = InTest.TestTrue(*FString::Printf(TEXT("%s W1 route is finite and clear"), InName),
            Get_HasFiniteClearStrictRoute(OutW1));
        const auto ReducedWork = NOT InExpectWorkReduction || InTest.TestTrue(
            *FString::Printf(TEXT("%s W1 expands fewer nodes than the W0 reference"), InName),
            OutW1._Result._ExpansionCount < W0._Result._ExpansionCount);
        return Strict && W0Strict && SameCost && W0ValidRoute && ValidRoute && ReducedWork;
    }

    auto BakeLinkedBarrier(FCk_GroundNav_Field& OutField) -> bool
    {
        auto Boxes = TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}},
            FBox{FVector{350.0, -400.0, 0.0}, FVector{450.0, 500.0, 300.0}}};
        auto Params = Make_FlatParams();
        Params._Links = {FCk_GroundNav_LinkRecord{17, FVector{300.0, 200.0, kGroundZ}, FVector{500.0, 200.0, kGroundZ}}};
        return Bake(Boxes, Params, OutField);
    }

    auto BakeCostPlateDetour(FCk_GroundNav_Field& OutField) -> bool
    {
        auto Params = Make_FlatParams();
        auto CostPlate = FCk_GroundNav_MarkupRecord{
            71,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{250.0, 100.0, 50.0}}},
            FTransform{FVector{400.0, 400.0, kGroundZ}},
            ECk_GroundNav_MarkupKind::Cost};
        CostPlate.Set_CostMultiplier(64.0f);
        Params._MarkupRecords.Add(CostPlate);

        const auto Floor = TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}}};
        return Bake(Floor, Params, OutField);
    }

    auto Get_HasPlateTransition(const FCk_GroundNav_Field& InField, const FRun& InRun) -> bool
    {
        return InRun._Result._CellRoute.ContainsByPredicate([&InField](const auto& Edge)
        {
            if (Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link ||
                NOT InField._Tiles.IsValidIndex(Edge._FromSurface._TileIndex) ||
                NOT InField._Tiles.IsValidIndex(Edge._ToSurface._TileIndex))
            { return false; }
            return Edge._FromSurface._PlateIndex != Edge._ToSurface._PlateIndex ||
                Edge._FromSurface._TileIndex != Edge._ToSurface._TileIndex;
        });
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictSearchHeuristic_PreservesOptimalCostAndBreaksFreePlateau,
    "CkTests.UnitTests.CkGroundNav.Path.StrictSearchHeuristic.PreservesOptimalCostAndBreaksFreePlateau",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictSearchHeuristic_PreservesOptimalCostAndBreaksFreePlateau::RunTest(const FString& InParameters)
{
    using namespace ck_test_groundnav_strictsearchheuristic;

    const auto Snapshot = MakeHighDiscSnapshot();
    if (NOT TestTrue(TEXT("the strict snapshot is valid"), Snapshot.IsSet())) { return false; }

    auto FlatField = MakeShared<FCk_GroundNav_Field>();
    const auto FlatFloor = TArray<FBox>{
        FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    if (NOT TestTrue(TEXT("the uniform field bakes"), Bake(FlatFloor, Make_QueryParams(), *FlatField)))
    { return false; }

    auto MakeStrictQuery = [&Snapshot](const FVector& InStart, const FVector& InGoal)
    {
        auto Query = FCk_GroundNav_PathQuery{};
        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._DynamicObstacles = Snapshot.GetValue();
        return Query;
    };

    auto FreeDiagonal = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("uniform diagonal"), FlatField,
        MakeStrictQuery(FVector{100.0, 100.0, kGroundZ}, FVector{1500.0, 1500.0, kGroundZ}), FreeDiagonal))
    { return false; }
    TestTrue(TEXT("the free diagonal avoids the former equal-F plateau"),
        FreeDiagonal._Result._ExpansionCount < kRequiredFreeExpansionCeiling);

    auto OffCentre = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("uniform off-centre"), FlatField,
        MakeStrictQuery(FVector{117.0, 138.0, kGroundZ}, FVector{1485.0, 1458.0, kGroundZ}), OffCentre))
    { return false; }

    auto AdjacentEnd = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("uniform adjacent endpoint"), FlatField,
        MakeStrictQuery(FVector{100.0, 100.0, kGroundZ}, FVector{130.0, 105.0, kGroundZ}), AdjacentEnd))
    { return false; }

    auto WeightedField = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the weighted detour field bakes"), Bake_TwoRouteScene(*WeightedField)))
    { return false; }
    auto WeightedQuery = MakeStrictQuery(kTwoRouteStart, kTwoRouteGoal);
    WeightedQuery._Cost._ClearanceBiasK = 0.5f;
    auto Weighted = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("clearance-weighted detour"), WeightedField, WeightedQuery, Weighted))
    { return false; }

    auto CostPlateField = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the 64x cost-plate detour field bakes"), BakeCostPlateDetour(*CostPlateField)))
    { return false; }
    const auto& CostTile = CostPlateField->_Tiles[0];
    const auto StartPlate = CostTile._Plates.Get_PlateIndexAt(10, 16, 0);
    const auto GoalPlate = CostTile._Plates.Get_PlateIndexAt(22, 16, 0);
    if (NOT TestTrue(TEXT("both endpoints are interior to the expensive plate"),
        CostTile._Plates._Plates.IsValidIndex(StartPlate) && StartPlate == GoalPlate &&
        CostTile._Plates._Plates[StartPlate]._CostMultiplier == 64.0f))
    { return false; }
    auto CostPlate = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("64x coarse cost plate cheap outside detour"), CostPlateField,
        MakeStrictQuery(FVector{262.5, 412.5, kGroundZ}, FVector{562.5, 412.5, kGroundZ}), CostPlate, true))
    { return false; }
    TestTrue(TEXT("the optimal cost route crosses from the expensive plate to cheap ground"),
        Get_HasPlateTransition(*CostPlateField, CostPlate));

    auto GoalEntry = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("64x goal-plate boundary outside terminal origin"), CostPlateField,
        MakeStrictQuery(FVector{62.5, 412.5, kGroundZ}, FVector{140.0, 412.5, kGroundZ}), GoalEntry, true))
    { return false; }
    const auto GoalEntryTileIndex = GoalEntry._Result._GoalSurface._TileIndex;
    const auto& GoalEntryTile = CostPlateField->_Tiles[GoalEntryTileIndex];
    const auto GoalEntryPlateIndex = GoalEntry._Result._GoalSurface._PlateIndex;
    if (NOT TestTrue(TEXT("the offset goal resolves onto the 64x plate boundary"),
        GoalEntryTile._Plates._Plates.IsValidIndex(GoalEntryPlateIndex) &&
        GoalEntryTile._Plates._Plates[GoalEntryPlateIndex]._CostMultiplier == 64.0f &&
        GoalEntry._Result._GoalSurface._CellX == GoalEntryTile._Plates._Plates[GoalEntryPlateIndex]._MinX))
    { return false; }
    TestTrue(TEXT("the goal-entry route crosses from a cheap outside terminal origin"),
        Get_HasPlateTransition(*CostPlateField, GoalEntry));

    auto MultiLayerField = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the deck scene bakes"),
        Bake(ck_test_groundnav_queryfixtures::Make_QueryScene(), Make_QueryParams(), *MultiLayerField)))
    { return false; }
    const auto HasMultiLayerTile = MultiLayerField->_Tiles.ContainsByPredicate([](const auto& Tile)
    { return Tile._LayerCount > 1; });
    if (NOT TestTrue(TEXT("the deck fixture carries an interior alternate layer"), HasMultiLayerTile)) { return false; }
    auto MultiLayer = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("multi-layer interior exit fallback"), MultiLayerField,
        MakeStrictQuery(FVector{1100.0, 400.0, kGroundZ}, FVector{1450.0, 400.0, kGroundZ}), MultiLayer))
    { return false; }

    auto LinkedField = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the shortcut-link field bakes"), BakeLinkedBarrier(*LinkedField)))
    { return false; }
    auto Linked = FRun{};
    if (NOT VerifyDijkstraParity(*this, TEXT("link shortcut fallback"), LinkedField,
        MakeStrictQuery(FVector{100.0, 200.0, kGroundZ}, FVector{700.0, 200.0, kGroundZ}), Linked))
    { return false; }
    TestTrue(TEXT("the link shortcut is retained in the strict result"),
        Linked._Result._CellRoute.ContainsByPredicate([](const auto& Edge)
        { return Edge._Kind == ECk_GroundNav_CellRouteEdgeKind::Link; }));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
