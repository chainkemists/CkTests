// What a path search answers, and what it is allowed to answer it with.
//
// Four claims are made here and each is checked against something that is not the search. The route it
// answers is measured against the visibility-graph oracle — an exact Euclidean shortest path built from
// the field's own boundary runs and solved with Dijkstra, which shares no code and no idea with the
// funnel — so a propagation bug shows up as a disagreement rather than as two matching wrong numbers.
// The sliced run is measured against the one-shot run, element for element, because slicing is only
// allowed to change where the work stops. The budgets are measured against the statuses they must
// produce, never against a truncated corridor. And the checks that answer without searching are
// measured against their own order, because a consumer waits on unbuilt ground and gives up on ground
// with nowhere to stand, and would do the wrong one if the two were ever swapped.
//
// The doorway and two-island scenes are rebuilt here rather than shared: their builders live inside
// other tests' file-private namespaces and never reached the fixtures header. The boxes are copied
// verbatim and must be kept so.

#include "CkCore/Time/CkTime.h"

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"
#include "CkGroundNav/Query/CkGroundNav_QueryCore.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_PlatePortalGraph.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"
#include "Test_GroundNav_ReferencePaths.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathsearch
{
    using ck::groundnav::FCk_GroundNav_Crossing;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_PathNodeId;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::FCk_GroundNav_PlatePortalGraph;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_QueryCost;
    using ck::groundnav::Get_CrossingsFrom;
    using ck::groundnav::Get_CrossingTransitionPoint;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_Path;
    using ck::groundnav::Get_StringPull;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_QueryScene;
    using ck_test_groundnav_queryfixtures::Do_MakeEveryTileUnbuilt;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kMaxClearance;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_FlatScene;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;

    using ck_test_groundnav_referencepaths::Get_ReferenceDistance;
    using ck_test_groundnav_referencepaths::Get_XY;
    using ck_test_groundnav_referencepaths::kEpsilon;
    using ck_test_groundnav_referencepaths::kGroundStoreyMaxZ;
    using ck_test_groundnav_referencepaths::Make_VisibilityGraph;

    // A body of no size, which is the only radius the visibility-graph oracle is stated for: it draws
    // corner-to-corner lines, and an inset body cannot touch the corners those lines bend on.
    constexpr auto kNoRadius = 0.0f;

    // The tolerance the flood fill's own reference test holds its distances to.
    constexpr auto kOracleToleranceUu = static_cast<double>(kCellSize);

    // Enough oracle-covered pairs per scene that an aggregate means something and a scene which
    // silently stopped connecting cannot pass by comparing nothing.
    constexpr auto kMinOraclePairsPerScene = 3;

    // Above the field's clearance ceiling, so no clearance can admit it and the field must refuse.
    constexpr auto kUnanswerableRadiusUu = kMaxClearance + 100.0f;

    // One expansion per slice: the finest grain there is, so a verdict that depended on where a
    // boundary fell would differ from the one-shot run at every boundary rather than at some of them.
    constexpr auto kOneExpansionPerSlice = 1;

    // A microsecond, which no slice can respect: CkAStar samples the clock every sixteenth expansion,
    // so this stops a slice at the first sample it takes and never before one.
    constexpr auto kTinySliceBudget = FCk_Time{0.000001};

    // A sliced run that has not terminated by here is not slow, it is stuck.
    constexpr auto kMaxSlices = 100000;

    // A route costing one expansion could not tell the two sides of the cap rule apart: the cap that
    // admits it and the cap that refuses it would be the same number.
    constexpr auto kMinCappedExpansions = 2;

    constexpr auto kTwoCrossings = 2;

    constexpr auto kTransitionPlateSampleCount = 6;

    // The centre of the square of missing floor: over built ground with nowhere to stand on it.
    const auto kHoleCentre = FVector{1100.0, 1100.0, kGroundZ};

    // Somewhere in the west room of the query scene, well clear of the wall and of the field rim.
    const auto kStandingPoint = FVector{150.0, 150.0, kGroundZ};

    // A second standing point on the far side of the dividing wall, so a query between the two is a
    // real one whatever else the test is asking.
    const auto kFarStandingPoint = FVector{900.0, 150.0, kGroundZ};

    // Two points inside one cell of the flat scene, so the plate they share is not a matter of how the
    // merge happened to run.
    const auto kSameCellStart = FVector{410.0, 410.0, kGroundZ};
    const auto kSameCellGoal = FVector{412.0, 412.0, kGroundZ};

    // ----------------------------------------------------------------------------------------------------------------

    struct FProbePair
    {
        FVector _Start = FVector::ZeroVector;
        FVector _Goal = FVector::ZeroVector;
    };

    struct FSceneTally
    {
        int32 _Compared = 0;
        int32 _NotReady = 0;
        int32 _NoOracle = 0;

        int32 _CorridorEndsWrong = 0;
        int32 _CorridorUnchained = 0;
        int32 _OracleMismatched = 0;
        int32 _OracleShortcut = 0;

        double _WorstOracleDeltaUu = 0.0;
    };

    // ----------------------------------------------------------------------------------------------------------------

    /** Two floors in one field with a gap no crossing spans. Copied from the reachability suite. */
    auto Make_TwoIslandScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{600.0, 2000.0, kGroundZ}},
            FBox{FVector{1000.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    }

    /** The query scene with a second wall across its west room, pierced by a 60 uu doorway. Likewise copied. */
    auto Make_DoorwayScene() -> TArray<FBox>
    {
        auto Boxes = Make_QueryScene();

        Boxes.Emplace(FBox{FVector{0.0, 1000.0, 0.0}, FVector{300.0, 1100.0, 300.0}});
        Boxes.Emplace(FBox{FVector{360.0, 1000.0, 0.0}, FVector{700.0, 1100.0, 300.0}});

        return Boxes;
    }

    /**
     * A baked scene held the way a search takes one.
     *
     * The search holds the field by shared pointer so a rebuild underneath a sliced run cannot take it
     * away, which means every scene here has to be published into one rather than kept on the stack.
     */
    auto Bake_Shared(
        const TArray<FBox>&              InBoxes,
        const FCk_GroundNav_FieldParams& InParams,
        FCk_GroundNav_FieldPtr&          OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(InBoxes, InParams, *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Make_PathQuery(
        const FVector& InStart,
        const FVector& InGoal,
        float          InRadiusUu) -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(InRadiusUu);

        return Query;
    }

    auto Get_StatusName(
        ECk_GroundNav_PathStatus InStatus) -> const TCHAR*
    {
        switch (InStatus)
        {
            case ECk_GroundNav_PathStatus::InProgress: return TEXT("InProgress");
            case ECk_GroundNav_PathStatus::Ready: return TEXT("Ready");
            case ECk_GroundNav_PathStatus::Partial: return TEXT("Partial");
            case ECk_GroundNav_PathStatus::Unbuilt: return TEXT("Unbuilt");
            case ECk_GroundNav_PathStatus::NoStartSurface: return TEXT("NoStartSurface");
            case ECk_GroundNav_PathStatus::NoGoalSurface: return TEXT("NoGoalSurface");
            case ECk_GroundNav_PathStatus::Unreachable: return TEXT("Unreachable");
            case ECk_GroundNav_PathStatus::BudgetExceeded: return TEXT("BudgetExceeded");
            case ECk_GroundNav_PathStatus::Blocked: return TEXT("Blocked");
        }

        return TEXT("Unknown");
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_PulledLengthUu(
        const FCk_GroundNav_PathResult& InResult) -> double
    {
        auto Waypoints = TArray<FVector>{};

        return Get_StringPull(
            InResult._StartPoint, InResult._GoalPoint, InResult._FunnelPortals, kNoRadius, Waypoints);
    }

    /** Whether every leg leaves the plate the leg before it arrived on. Vacuous for a corridor of one plate. */
    auto Get_CorridorIsChained(
        const FCk_GroundNav_PathResult& InResult) -> bool
    {
        for (auto Index = 0; Index + 1 < InResult._Crossings.Num(); ++Index)
        {
            if (InResult._Crossings[Index]._ToFlatPlate != InResult._Crossings[Index + 1]._FromFlatPlate)
            { return false; }
        }

        return true;
    }

    /**
     * The exact shortest path, where the construction can state one.
     *
     * It is stated on the ground storey of one component for a body of no size; a route leaving any of
     * those conditions has no oracle rather than a wrong one.
     */
    auto Get_OracleLength(
        const FCk_GroundNav_Field&      InField,
        const FCk_GroundNav_PathResult& InResult) -> TOptional<double>
    {
        const auto StartLabel = InField.Get_ReachabilityLabel(
            InResult._StartSurface._TileIndex, InResult._StartSurface._PlateIndex);

        const auto GoalLabel = InField.Get_ReachabilityLabel(
            InResult._GoalSurface._TileIndex, InResult._GoalSurface._PlateIndex);

        if (StartLabel == INDEX_NONE || StartLabel != GoalLabel)
        { return {}; }

        if (InResult._StartPoint.Z > kGroundStoreyMaxZ || InResult._GoalPoint.Z > kGroundStoreyMaxZ)
        { return {}; }

        const auto Graph = Make_VisibilityGraph(InField, StartLabel, Get_XY(InResult._StartPoint));

        return Get_ReferenceDistance(InField, Graph, Get_XY(InResult._GoalPoint));
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The first thing two results disagree about, or nothing.
     *
     * A named disagreement rather than a boolean, because "the sliced run differed" is not a report
     * anybody can act on and the point of comparing the two is to say WHERE they parted. Times are not
     * compared: they measure this machine, and a run cut into a hundred calls samples the clock a
     * hundred times more often than one call does.
     */
    auto Get_Disagreement(
        const FCk_GroundNav_PathResult& InLeft,
        const FCk_GroundNav_PathResult& InRight) -> FString
    {
        if (InLeft._Status != InRight._Status)
        {
            return FString::Printf(TEXT("status %s vs %s"),
                Get_StatusName(InLeft._Status), Get_StatusName(InRight._Status));
        }

        if (InLeft._PlateCorridor != InRight._PlateCorridor)
        {
            return FString::Printf(TEXT("plate corridor of %d vs %d plates"),
                InLeft._PlateCorridor.Num(), InRight._PlateCorridor.Num());
        }

        if (InLeft._Crossings.Num() != InRight._Crossings.Num())
        {
            return FString::Printf(TEXT("%d vs %d crossings"),
                InLeft._Crossings.Num(), InRight._Crossings.Num());
        }

        for (auto Index = 0; Index < InLeft._Crossings.Num(); ++Index)
        {
            const auto& Left = InLeft._Crossings[Index];
            const auto& Right = InRight._Crossings[Index];

            const auto CrossingsAgree =
                Left._FromFlatPlate == Right._FromFlatPlate &&
                Left._ToFlatPlate == Right._ToFlatPlate &&
                Left._Left == Right._Left &&
                Left._Right == Right._Right;

            if (NOT CrossingsAgree)
            {
                return FString::Printf(TEXT("crossing %d: %d->%d vs %d->%d"), Index,
                    Left._FromFlatPlate, Left._ToFlatPlate, Right._FromFlatPlate, Right._ToFlatPlate);
            }
        }

        if (InLeft._ExpansionCount != InRight._ExpansionCount)
        {
            return FString::Printf(TEXT("%d vs %d expansions"),
                InLeft._ExpansionCount, InRight._ExpansionCount);
        }

        if (InLeft._SearchCost != InRight._SearchCost)
        {
            return FString::Printf(TEXT("search cost %.6f vs %.6f"),
                InLeft._SearchCost, InRight._SearchCost);
        }

        return FString{};
    }

    auto Do_RunSliced(
        const FCk_GroundNav_FieldPtr&        InField,
        const FCk_GroundNav_PathQuery&       InQuery,
        const FCk_GroundNav_PathSliceParams& InSlice,
        int32&                               OutSliceCount) -> FCk_GroundNav_PathResult
    {
        auto Search = FCk_GroundNav_PathSearch{};

        Search.Request_Begin(InField, InQuery);

        OutSliceCount = 0;

        while (NOT Search.Get_IsTerminal() && OutSliceCount < kMaxSlices)
        {
            Search.ContinueSearch(InSlice);
            ++OutSliceCount;
        }

        return Search.Get_Result();
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Do_MeasurePair(
        const FCk_GroundNav_FieldPtr& InField,
        const TCHAR*                  InSceneName,
        const FProbePair&             InPair,
        FSceneTally&                  OutTally) -> void
    {
        const auto Result = Get_Path(InField, Make_PathQuery(InPair._Start, InPair._Goal, kNoRadius));

        if (Result._Status != ECk_GroundNav_PathStatus::Ready)
        {
            ++OutTally._NotReady;
            return;
        }

        const auto& Field = *InField;

        const auto StartPlate = Get_FlatPlateIndex(
            Field, Result._StartSurface._TileIndex, Result._StartSurface._PlateIndex);

        const auto GoalPlate = Get_FlatPlateIndex(
            Field, Result._GoalSurface._TileIndex, Result._GoalSurface._PlateIndex);

        const auto CorridorEndsHoldTheQuery =
            NOT Result._PlateCorridor.IsEmpty() &&
            Result._PlateCorridor[0] == StartPlate &&
            Result._PlateCorridor.Last() == GoalPlate;

        if (NOT CorridorEndsHoldTheQuery)
        { ++OutTally._CorridorEndsWrong; }

        if (NOT Get_CorridorIsChained(Result))
        { ++OutTally._CorridorUnchained; }

        const auto PulledUu = Get_PulledLengthUu(Result);
        const auto Oracle = Get_OracleLength(Field, Result);

        const auto OracleText =
            Oracle.IsSet() ? FString::Printf(TEXT("%.3f"), Oracle.GetValue()) : FString{TEXT("n/a")};

        const auto Report = FString::Printf(
            TEXT("[SEARCH-BUDGET] %s (%.0f, %.0f)->(%.0f, %.0f): expansions=%d cellsRead=%d crossings=%d cost=%.3f pulled=%.3f oracle=%s"),
            InSceneName,
            InPair._Start.X, InPair._Start.Y, InPair._Goal.X, InPair._Goal.Y,
            Result._ExpansionCount, Result._Cost._CellsRead, Result._Crossings.Num(),
            Result._SearchCost, PulledUu, *OracleText);

        ck::groundnav::Display(TEXT("{}"), Report);

        if (NOT Oracle.IsSet())
        {
            ++OutTally._NoOracle;
            return;
        }

        const auto DeltaUu = PulledUu - Oracle.GetValue();

        ++OutTally._Compared;
        OutTally._WorstOracleDeltaUu = FMath::Max(OutTally._WorstOracleDeltaUu, FMath::Abs(DeltaUu));

        if (FMath::Abs(DeltaUu) > kOracleToleranceUu)
        { ++OutTally._OracleMismatched; }

        // The oracle is the shortest path there is, so the answered route may only ever be longer. One
        // that came in UNDER it took a route the geometry does not offer, which no tolerance on the
        // absolute difference would catch.
        if (DeltaUu < -kEpsilon)
        { ++OutTally._OracleShortcut; }
    }

    auto Get_SceneReport(
        const TCHAR*       InSceneName,
        const FSceneTally& InTally) -> FString
    {
        return FString::Printf(
            TEXT("%s: compared %d, not ready %d, no oracle %d, corridor ends wrong %d, unchained %d, mismatched %d, shortcut %d, worst delta %.3f"),
            InSceneName, InTally._Compared, InTally._NotReady, InTally._NoOracle,
            InTally._CorridorEndsWrong, InTally._CorridorUnchained,
            InTally._OracleMismatched, InTally._OracleShortcut, InTally._WorstOracleDeltaUu);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** Every crossing leaving the first few plates that offer any, which is the sample the point is read over. */
    auto Do_CollectCrossings(
        const FCk_GroundNav_Field&      InField,
        int32                           InWantedPlates,
        TArray<FCk_GroundNav_Crossing>& OutCrossings) -> int32
    {
        auto Cost = FCk_GroundNav_QueryCost{};
        auto PlatesSampled = 0;

        for (auto TileIndex = 0; TileIndex < InField._Tiles.Num(); ++TileIndex)
        {
            if (NOT InField._Tiles[TileIndex].Get_IsBuilt())
            { continue; }

            const auto PlateCount = InField._Tiles[TileIndex]._Plates._Plates.Num();

            for (auto PlateIndex = 0; PlateIndex < PlateCount; ++PlateIndex)
            {
                if (PlatesSampled >= InWantedPlates)
                { return PlatesSampled; }

                auto Crossings = TArray<FCk_GroundNav_Crossing>{};

                Get_CrossingsFrom(
                    InField, Get_FlatPlateIndex(InField, TileIndex, PlateIndex), Crossings, Cost);

                if (Crossings.IsEmpty())
                { continue; }

                OutCrossings.Append(Crossings);
                ++PlatesSampled;
            }
        }

        return PlatesSampled;
    }

    /** The first pair of a list whose one-shot answer cost at least the wanted number of expansions. */
    auto Get_SearchedPair(
        const FCk_GroundNav_FieldPtr& InField,
        TConstArrayView<FProbePair>   InPairs,
        int32                         InWantedExpansions,
        FProbePair&                   OutPair,
        FCk_GroundNav_PathResult&     OutResult) -> bool
    {
        for (const auto& Pair : InPairs)
        {
            const auto Result = Get_Path(InField, Make_PathQuery(Pair._Start, Pair._Goal, kNoRadius));

            if (Result._Status != ECk_GroundNav_PathStatus::Ready ||
                Result._ExpansionCount < InWantedExpansions)
            { continue; }

            OutPair = Pair;
            OutResult = Result;

            return true;
        }

        return false;
    }

    /** The first pair of a list whose one-shot answer holds at least the wanted number of crossings. */
    auto Get_MultiCrossingPair(
        const FCk_GroundNav_FieldPtr& InField,
        TConstArrayView<FProbePair>   InPairs,
        int32                         InWantedCrossings,
        FProbePair&                   OutPair,
        FCk_GroundNav_PathResult&     OutResult) -> bool
    {
        for (const auto& Pair : InPairs)
        {
            const auto Result = Get_Path(InField, Make_PathQuery(Pair._Start, Pair._Goal, kNoRadius));

            if (Result._Status != ECk_GroundNav_PathStatus::Ready ||
                Result._Crossings.Num() < InWantedCrossings)
            { continue; }

            OutPair = Pair;
            OutResult = Result;

            return true;
        }

        return false;
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** The west room, the east room and the ground around the hole, on the ground storey throughout. */
    auto Make_QueryPairs() -> TArray<FProbePair>
    {
        return TArray<FProbePair>{
            FProbePair{kStandingPoint, FVector{150.0, 1450.0, kGroundZ}},
            FProbePair{kStandingPoint, FVector{650.0, 1450.0, kGroundZ}},
            FProbePair{kFarStandingPoint, FVector{900.0, 1450.0, kGroundZ}},
            FProbePair{FVector{900.0, 1100.0, kGroundZ}, FVector{1500.0, 1100.0, kGroundZ}},
            FProbePair{FVector{1400.0, 150.0, kGroundZ}, FVector{900.0, 1450.0, kGroundZ}}};
    }

    /** Every route between the halves of the west room threads the one 60 uu gap. */
    auto Make_DoorwayPairs() -> TArray<FProbePair>
    {
        return TArray<FProbePair>{
            FProbePair{FVector{200.0, 500.0, kGroundZ}, FVector{200.0, 1400.0, kGroundZ}},
            FProbePair{FVector{100.0, 300.0, kGroundZ}, FVector{600.0, 1500.0, kGroundZ}},
            FProbePair{FVector{650.0, 200.0, kGroundZ}, FVector{100.0, 1500.0, kGroundZ}},
            FProbePair{FVector{200.0, 800.0, kGroundZ}, FVector{500.0, 1300.0, kGroundZ}}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_ConceptGraphSatisfiesAStar,
    "CkTests.UnitTests.CkGroundNav.Search.Concept_GraphSatisfiesAStar",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_ConceptGraphSatisfiesAStar::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    // Restated here rather than trusted from the header: this file is a second translation unit that
    // has to be able to hand the graph to CkAStar, and a concept that only holds where it is declared
    // holds nowhere useful.
    static_assert(
        ck::astar::AStarGraph<FCk_GroundNav_PlatePortalGraph, FCk_GroundNav_PathNodeId>,
        "FCk_GroundNav_PlatePortalGraph must satisfy the AStarGraph concept from a consumer too");

    static_assert(
        ck::astar::AStarNodeId<FCk_GroundNav_PathNodeId>,
        "A ground path node id must be copyable and comparable");

    // Compiling is the whole of the proof; the run exists so the claim has a row in the report.
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_TransitionPointOnIntervalAndDeterministic,
    "CkTests.UnitTests.CkGroundNav.Search.TransitionPoint_OnIntervalAndDeterministic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_TransitionPointOnIntervalAndDeterministic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    auto Crossings = TArray<FCk_GroundNav_Crossing>{};

    const auto PlatesSampled = Do_CollectCrossings(Field, kTransitionPlateSampleCount, Crossings);

    if (NOT TestTrue(
        FString::Printf(TEXT("the scene offers crossings to read the point over [plates %d, crossings %d]"),
            PlatesSampled, Crossings.Num()),
        Crossings.Num() > 0))
    { return false; }

    auto OffInterval = 0;
    auto NotBetween = 0;
    auto DegenerateWrong = 0;
    auto Undeterministic = 0;

    for (const auto& Crossing : Crossings)
    {
        const auto Point = Get_CrossingTransitionPoint(Crossing);

        // Two calls, compared EXACTLY: the point is pure arithmetic over two vectors, so anything short
        // of bit equality would be a different function than the one the search prices legs with.
        if (Point != Get_CrossingTransitionPoint(Crossing))
        { ++Undeterministic; }

        const auto IntervalUu = FVector::Dist(Crossing._Left, Crossing._Right);
        const auto ToLeftUu = FVector::Dist(Crossing._Left, Point);
        const auto ToRightUu = FVector::Dist(Point, Crossing._Right);

        // Colinear: the two legs sum to the interval only where the point lies on the line between them.
        if (FMath::Abs((ToLeftUu + ToRightUu) - IntervalUu) > kEpsilon)
        { ++OffInterval; }

        if (IntervalUu > kEpsilon)
        {
            if (ToLeftUu <= kEpsilon || ToRightUu <= kEpsilon)
            { ++NotBetween; }
        }
        else if (Point != Crossing._Left || Point != Crossing._Right)
        {
            ++DegenerateWrong;
        }
    }

    const auto Report = FString::Printf(
        TEXT("plates %d, crossings %d, off interval %d, not between %d, degenerate wrong %d, undeterministic %d"),
        PlatesSampled, Crossings.Num(), OffInterval, NotBetween, DegenerateWrong, Undeterministic);

    TestEqual(FString::Printf(TEXT("every transition point is colinear with its interval [%s]"), *Report),
        OffInterval, 0);

    TestEqual(FString::Printf(TEXT("and strictly between its ends where the interval has length [%s]"), *Report),
        NotBetween, 0);

    TestEqual(FString::Printf(TEXT("and equal to both ends where it has none [%s]"), *Report),
        DegenerateWrong, 0);

    TestEqual(FString::Printf(TEXT("and two reads of one crossing agree exactly [%s]"), *Report),
        Undeterministic, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_OneShotMatchesAnalyticOptimum,
    "CkTests.UnitTests.CkGroundNav.Search.OneShot_MatchesAnalyticOptimum",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_OneShotMatchesAnalyticOptimum::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto QueryField = FCk_GroundNav_FieldPtr{};
    auto DoorwayField = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the query scene bakes"),
        Bake_Shared(Make_QueryScene(), Make_QueryParams(), QueryField)))
    { return false; }

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), DoorwayField)))
    { return false; }

    auto QueryTally = FSceneTally{};
    auto DoorwayTally = FSceneTally{};

    for (const auto& Pair : Make_QueryPairs())
    { Do_MeasurePair(QueryField, TEXT("query"), Pair, QueryTally); }

    for (const auto& Pair : Make_DoorwayPairs())
    { Do_MeasurePair(DoorwayField, TEXT("doorway"), Pair, DoorwayTally); }

    const auto Tallies = TArray<FSceneTally>{QueryTally, DoorwayTally};
    const auto Names = TArray<const TCHAR*>{TEXT("query"), TEXT("doorway")};

    for (auto Index = 0; Index < Tallies.Num(); ++Index)
    {
        const auto& Tally = Tallies[Index];
        const auto Report = Get_SceneReport(Names[Index], Tally);

        // Without a floor on the sample every bound below holds vacuously, and a scene that quietly
        // stopped connecting would compare nothing and pass.
        if (NOT TestTrue(FString::Printf(TEXT("the scene contributed pairs the oracle covers [%s]"), *Report),
            Tally._Compared >= kMinOraclePairsPerScene))
        { continue; }

        TestEqual(FString::Printf(TEXT("every corridor begins on the start's plate and ends on the goal's [%s]"), *Report),
            Tally._CorridorEndsWrong, 0);

        TestEqual(FString::Printf(TEXT("every leg leaves the plate the leg before it arrived on [%s]"), *Report),
            Tally._CorridorUnchained, 0);

        TestEqual(FString::Printf(TEXT("every answered route is within a cell of the exact shortest path [%s]"), *Report),
            Tally._OracleMismatched, 0);

        TestEqual(FString::Printf(TEXT("no answered route undercuts the exact shortest path [%s]"), *Report),
            Tally._OracleShortcut, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_CrossComponentRejectsWithZeroExpansions,
    "CkTests.UnitTests.CkGroundNav.Search.CrossComponent_RejectsWithZeroExpansions",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_CrossComponentRejectsWithZeroExpansions::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the two-island scene bakes"),
        Bake_Shared(Make_TwoIslandScene(), Make_QueryParams(), Field)))
    { return false; }

    if (NOT TestTrue(TEXT("the two islands are two components"),
        Field->Get_ReachabilityComponentCount() >= 2))
    { return false; }

    const auto IslandProbe = FVector{200.0, 800.0, kGroundZ};

    const auto Across = Get_Path(Field,
        Make_PathQuery(IslandProbe, FVector{1500.0, 800.0, kGroundZ}, kNoRadius));

    const auto Within = Get_Path(Field,
        Make_PathQuery(IslandProbe, FVector{400.0, 1500.0, kGroundZ}, kNoRadius));

    const auto Report = FString::Printf(
        TEXT("components %d, across: %s expansions %d crossings %d, within: %s expansions %d crossings %d"),
        Field->Get_ReachabilityComponentCount(),
        Get_StatusName(Across._Status), Across._ExpansionCount, Across._Crossings.Num(),
        Get_StatusName(Within._Status), Within._ExpansionCount, Within._Crossings.Num());

    TestEqual(FString::Printf(TEXT("a route between the islands is refused [%s]"), *Report),
        Across._Status, ECk_GroundNav_PathStatus::Unreachable);

    // The counter, not a clock: a near-constant-time claim measured with a timer is a claim about the
    // machine. The labels prove these two ends apart, so nothing may be expanded to find that out.
    TestEqual(FString::Printf(TEXT("and expands nothing to say so [%s]"), *Report),
        Across._ExpansionCount, 0);

    TestEqual(FString::Printf(TEXT("and answers with no crossings at all [%s]"), *Report),
        Across._Crossings.Num(), 0);

    TestEqual(FString::Printf(TEXT("and no corridor rather than a route to nowhere [%s]"), *Report),
        Across._PlateCorridor.Num(), 0);

    // The other half of the guarantee: the refusal is a proof about these two ends, not about the field.
    TestEqual(FString::Printf(TEXT("a route within one island is still answered [%s]"), *Report),
        Within._Status, ECk_GroundNav_PathStatus::Ready);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_SlicedEqualsOneShot,
    "CkTests.UnitTests.CkGroundNav.Search.Sliced_EqualsOneShot",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_SlicedEqualsOneShot::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto QueryField = FCk_GroundNav_FieldPtr{};
    auto DoorwayField = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the query scene bakes"),
        Bake_Shared(Make_QueryScene(), Make_QueryParams(), QueryField)))
    { return false; }

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), DoorwayField)))
    { return false; }

    auto IterationSlice = FCk_GroundNav_PathSliceParams{};
    IterationSlice._MaxIterations = kOneExpansionPerSlice;

    auto BudgetSlice = FCk_GroundNav_PathSliceParams{};
    BudgetSlice._Budget = kTinySliceBudget;

    auto Compared = 0;

    const auto Do_Compare = [&](
        const FCk_GroundNav_FieldPtr& InField,
        const TCHAR*                  InSceneName,
        const FProbePair&             InPair) -> void
    {
        const auto Query = Make_PathQuery(InPair._Start, InPair._Goal, kNoRadius);

        const auto OneShot = Get_Path(InField, Query);

        if (OneShot._Status != ECk_GroundNav_PathStatus::Ready)
        { return; }

        int32 IterationSlices = INDEX_NONE;
        int32 BudgetSlices = INDEX_NONE;

        const auto Iterated = Do_RunSliced(InField, Query, IterationSlice, IterationSlices);
        const auto Budgeted = Do_RunSliced(InField, Query, BudgetSlice, BudgetSlices);

        ++Compared;

        const auto Report = FString::Printf(
            TEXT("%s (%.0f, %.0f)->(%.0f, %.0f): one shot %d expansions, %d iteration slices, %d budget slices"),
            InSceneName, InPair._Start.X, InPair._Start.Y, InPair._Goal.X, InPair._Goal.Y,
            OneShot._ExpansionCount, IterationSlices, BudgetSlices);

        TestTrue(FString::Printf(TEXT("the one-expansion slices terminated [%s]"), *Report),
            IterationSlices < kMaxSlices);

        TestTrue(FString::Printf(TEXT("the time-budget slices terminated [%s]"), *Report),
            BudgetSlices < kMaxSlices);

        TestEqual(FString::Printf(TEXT("one expansion per slice answers what one call answers [%s]"), *Report),
            Get_Disagreement(OneShot, Iterated), FString{});

        TestEqual(FString::Printf(TEXT("and so does a slice too short to finish anything [%s]"), *Report),
            Get_Disagreement(OneShot, Budgeted), FString{});
    };

    for (const auto& Pair : Make_QueryPairs())
    { Do_Compare(QueryField, TEXT("query"), Pair); }

    for (const auto& Pair : Make_DoorwayPairs())
    { Do_Compare(DoorwayField, TEXT("doorway"), Pair); }

    TestTrue(FString::Printf(TEXT("some route was driven both ways [compared %d]"), Compared),
        Compared >= kMinOraclePairsPerScene);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_ExpansionCapReportsBudgetExceeded,
    "CkTests.UnitTests.CkGroundNav.Search.ExpansionCap_ReportsBudgetExceeded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_ExpansionCapReportsBudgetExceeded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto Pairs = Make_DoorwayPairs();

    auto Pair = FProbePair{};
    auto Uncapped = FCk_GroundNav_PathResult{};

    if (NOT TestTrue(TEXT("the scene offers a route costing more than one expansion"),
        Get_SearchedPair(Field, Pairs, kMinCappedExpansions, Pair, Uncapped)))
    { return false; }

    const auto SpentExpansions = Uncapped._ExpansionCount;

    auto Refused = Make_PathQuery(Pair._Start, Pair._Goal, kNoRadius);
    Refused._MaxExpansions = SpentExpansions - 1;

    auto Admitted = Make_PathQuery(Pair._Start, Pair._Goal, kNoRadius);
    Admitted._MaxExpansions = SpentExpansions;

    const auto UnderCap = Get_Path(Field, Refused);
    const auto AtCap = Get_Path(Field, Admitted);

    const auto Report = FString::Printf(
        TEXT("uncapped %s in %d expansions with %d crossings; at %d: %s with %d crossings; at %d: %s in %d expansions"),
        Get_StatusName(Uncapped._Status), SpentExpansions, Uncapped._Crossings.Num(),
        SpentExpansions - 1, Get_StatusName(UnderCap._Status), UnderCap._Crossings.Num(),
        SpentExpansions, Get_StatusName(AtCap._Status), AtCap._ExpansionCount);

    TestEqual(FString::Printf(TEXT("a cap one expansion under the route's cost refuses it [%s]"), *Report),
        UnderCap._Status, ECk_GroundNav_PathStatus::BudgetExceeded);

    TestNotEqual(FString::Printf(TEXT("and never answers it as Ready [%s]"), *Report),
        UnderCap._Status, ECk_GroundNav_PathStatus::Ready);

    // Never a truncated Ready: a corridor that ran out of budget is not a shorter corridor, and a
    // caller that walked it would walk into a wall. So there is no corridor at all.
    TestEqual(FString::Printf(TEXT("and answers with no doors to walk through [%s]"), *Report),
        UnderCap._Crossings.Num(), 0);

    TestEqual(FString::Printf(TEXT("and no plates to walk over [%s]"), *Report),
        UnderCap._PlateCorridor.Num(), 0);

    // The cap is what the search MAY spend, not one more than it may spend: a route that finishes on
    // its last permitted expansion has exceeded nothing, and is answered exactly as an uncapped one is.
    TestEqual(FString::Printf(TEXT("a cap at the route's own cost admits it [%s]"), *Report),
        AtCap._Status, ECk_GroundNav_PathStatus::Ready);

    TestEqual(FString::Printf(TEXT("with the corridor the uncapped run answered [%s]"), *Report),
        Get_Disagreement(Uncapped, AtCap), FString{});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_CorridorCapReportsBudgetExceeded,
    "CkTests.UnitTests.CkGroundNav.Search.CorridorCap_ReportsBudgetExceeded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_CorridorCapReportsBudgetExceeded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto Pairs = Make_DoorwayPairs();

    auto Pair = FProbePair{};
    auto Uncapped = FCk_GroundNav_PathResult{};

    if (NOT TestTrue(TEXT("the scene offers a route through more than one door"),
        Get_MultiCrossingPair(Field, Pairs, kTwoCrossings, Pair, Uncapped)))
    { return false; }

    const auto SpentCrossings = Uncapped._Crossings.Num();

    auto Refused = Make_PathQuery(Pair._Start, Pair._Goal, kNoRadius);
    Refused._MaxCorridorLength = SpentCrossings - 1;

    auto Admitted = Make_PathQuery(Pair._Start, Pair._Goal, kNoRadius);
    Admitted._MaxCorridorLength = SpentCrossings;

    const auto UnderCap = Get_Path(Field, Refused);
    const auto AtCap = Get_Path(Field, Admitted);

    const auto Report = FString::Printf(
        TEXT("uncapped %s with %d crossings; at %d: %s; at %d: %s with %d crossings"),
        Get_StatusName(Uncapped._Status), SpentCrossings,
        SpentCrossings - 1, Get_StatusName(UnderCap._Status),
        SpentCrossings, Get_StatusName(AtCap._Status), AtCap._Crossings.Num());

    TestEqual(FString::Printf(TEXT("a cap one door under the route's length refuses it [%s]"), *Report),
        UnderCap._Status, ECk_GroundNav_PathStatus::BudgetExceeded);

    TestNotEqual(FString::Printf(TEXT("and never answers it as Ready [%s]"), *Report),
        UnderCap._Status, ECk_GroundNav_PathStatus::Ready);

    // The ceiling is on the answer's length and not on the query, so a route the cap admits is still
    // answered — which is what says the refusal above was the cap and not the scene.
    TestEqual(FString::Printf(TEXT("a cap at the route's own length admits it [%s]"), *Report),
        AtCap._Status, ECk_GroundNav_PathStatus::Ready);

    TestEqual(FString::Printf(TEXT("with the corridor the uncapped run answered [%s]"), *Report),
        Get_Disagreement(Uncapped, AtCap), FString{});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Search_PreSearchStatusOrder,
    "CkTests.UnitTests.CkGroundNav.Search.PreSearch_StatusOrder",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Search_PreSearchStatusOrder::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathsearch;

    auto QueryField = FCk_GroundNav_FieldPtr{};
    auto FlatField = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the query scene bakes"),
        Bake_Shared(Make_QueryScene(), Make_QueryParams(), QueryField)))
    { return false; }

    if (NOT TestTrue(TEXT("the flat scene bakes"),
        Bake_Shared(Make_FlatScene(), Make_FlatParams(), FlatField)))
    { return false; }

    TestEqual(TEXT("no field at all is Unbuilt, never a missing surface"),
        Get_Path(FCk_GroundNav_FieldPtr{}, Make_PathQuery(kHoleCentre, kStandingPoint, kNoRadius))._Status,
        ECk_GroundNav_PathStatus::Unbuilt);

    auto TakenAway = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the query scene bakes again to be taken away"), Bake_QueryScene(*TakenAway)))
    { return false; }

    Do_MakeEveryTileUnbuilt(*TakenAway);

    TestEqual(TEXT("a field whose every tile was taken away is Unbuilt too"),
        Get_Path(TakenAway, Make_PathQuery(kStandingPoint, kFarStandingPoint, kNoRadius))._Status,
        ECk_GroundNav_PathStatus::Unbuilt);

    // The body is wider than the field's clearance ceiling, so no clearance can admit it and the field
    // refuses rather than answering wrongly — before either end is resolved at all.
    TestEqual(TEXT("a body above the clearance ceiling is Blocked"),
        Get_Path(QueryField,
            Make_PathQuery(kStandingPoint, kFarStandingPoint, kUnanswerableRadiusUu))._Status,
        ECk_GroundNav_PathStatus::Blocked);

    TestEqual(TEXT("and Blocked outranks a start with nowhere to stand"),
        Get_Path(QueryField, Make_PathQuery(kHoleCentre, kStandingPoint, kUnanswerableRadiusUu))._Status,
        ECk_GroundNav_PathStatus::Blocked);

    TestEqual(TEXT("a start over the hole is NoStartSurface"),
        Get_Path(QueryField, Make_PathQuery(kHoleCentre, kStandingPoint, kNoRadius))._Status,
        ECk_GroundNav_PathStatus::NoStartSurface);

    // The two ends are told apart, because a consumer that cannot say which end it failed on cannot
    // move either of them.
    TestEqual(TEXT("a goal over the hole is NoGoalSurface"),
        Get_Path(QueryField, Make_PathQuery(kStandingPoint, kHoleCentre, kNoRadius))._Status,
        ECk_GroundNav_PathStatus::NoGoalSurface);

    TestEqual(TEXT("and the start is answered first when both ends are over it"),
        Get_Path(QueryField, Make_PathQuery(kHoleCentre, kHoleCentre, kNoRadius))._Status,
        ECk_GroundNav_PathStatus::NoStartSurface);

    // A plate is a convex rectangle, so two ends on one see each other across it and there is no door
    // to find: the corridor is the plate they share, and the search never runs.
    const auto SamePlate = Get_Path(FlatField, Make_PathQuery(kSameCellStart, kSameCellGoal, kNoRadius));

    const auto SamePlateReport = FString::Printf(
        TEXT("%s with %d plates, %d crossings, %d expansions"),
        Get_StatusName(SamePlate._Status), SamePlate._PlateCorridor.Num(),
        SamePlate._Crossings.Num(), SamePlate._ExpansionCount);

    TestEqual(FString::Printf(TEXT("two ends on one plate are Ready [%s]"), *SamePlateReport),
        SamePlate._Status, ECk_GroundNav_PathStatus::Ready);

    TestEqual(FString::Printf(TEXT("with the one plate they share [%s]"), *SamePlateReport),
        SamePlate._PlateCorridor.Num(), 1);

    TestEqual(FString::Printf(TEXT("no door between them [%s]"), *SamePlateReport),
        SamePlate._Crossings.Num(), 0);

    TestEqual(FString::Printf(TEXT("and nothing expanded to find that out [%s]"), *SamePlateReport),
        SamePlate._ExpansionCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
