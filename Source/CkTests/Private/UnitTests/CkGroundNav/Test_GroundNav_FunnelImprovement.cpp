// How much the string pull is worth, measured rather than asserted.
//
// The flood fill settles a chain of crossings and the funnel pulls a string through it. The chain
// alone already describes a walkable route — start, the midpoint of every crossing in order, goal —
// and that polyline is what a consumer would follow if the funnel did not exist. The difference
// between the two lengths is the whole value of the string pull, and nobody had a number for it.
//
// So this file measures rather than pins. The assertions are the bounds a WRONG answer would break:
// the pulled string can never be longer than the polyline through the same intervals in the same
// order, because that polyline is itself a feasible string; the ratio between them is a real fraction
// of a real length; and where the visibility-graph oracle can state the exact shortest path, the
// pulled answer agrees with it to the same cell-sized tolerance the flood fill's own reference test
// uses. Nothing here asserts a percentage — a tight bound on the improvement would be asserting the
// very number the file exists to discover, and would fail the first time a scene got a better route.
//
// The scenes are the suite's existing ones. Two of them are rebuilt here rather than shared because
// their builders live inside another test's file-private namespace and never reached the fixtures
// header; the boxes are copied verbatim and must be kept so.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"
#include "Test_GroundNav_ReferencePaths.h"

#include <Algo/Reverse.h>
#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_funnelimprovement
{
    using ck::groundnav::FCk_GroundNav_Crossing;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FloodQuery;
    using ck::groundnav::FCk_GroundNav_FloodResult;
    using ck::groundnav::FCk_GroundNav_FunnelPortal;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_FloodDistanceTo;
    using ck::groundnav::Get_FloodFill;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_StringPull;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_QueryScene;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;

    using ck_test_groundnav_referencepaths::Get_ReferenceDistance;
    using ck_test_groundnav_referencepaths::Get_XY;
    using ck_test_groundnav_referencepaths::kEpsilon;
    using ck_test_groundnav_referencepaths::kGroundStoreyMaxZ;
    using ck_test_groundnav_referencepaths::Make_VisibilityGraph;

    // A body of no size, which is the radius every ground-storey flood in this suite asks with and the
    // only one the visibility-graph oracle is stated for: the oracle draws corner-to-corner lines, and
    // an inset body cannot touch the corners those lines bend on.
    constexpr auto kNoRadius = 0.0f;

    // The tolerance the flood fill's own reference test holds its distances to.
    constexpr auto kOracleToleranceUu = static_cast<double>(kCellSize);

    // Enough measured pairs per scene that an aggregate means something and a scene which silently
    // stopped connecting cannot pass by measuring nothing.
    constexpr auto kMinMeasuredPairsPerScene = 3;

    // ----------------------------------------------------------------------------------------------------------------

    /** Two floors in one field with a gap no crossing spans. */
    auto Make_TwoIslandScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{600.0, 2000.0, kGroundZ}},
            FBox{FVector{1000.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    }

    /** The query scene with a second wall across its west room, pierced by a 60 uu doorway. */
    auto Make_DoorwayScene() -> TArray<FBox>
    {
        auto Boxes = Make_QueryScene();

        Boxes.Emplace(FBox{FVector{0.0, 1000.0, 0.0}, FVector{300.0, 1100.0, 300.0}});
        Boxes.Emplace(FBox{FVector{360.0, 1000.0, 0.0}, FVector{700.0, 1100.0, 300.0}});

        return Boxes;
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FProbePair
    {
        FVector _Start = FVector::ZeroVector;
        FVector _Goal = FVector::ZeroVector;
    };

    /** A point put onto the ground it stands on, with the two identities every comparison below needs. */
    struct FResolvedPoint
    {
        FVector _Point = FVector::ZeroVector;

        int32 _FlatPlate = INDEX_NONE;
        int32 _Label = INDEX_NONE;

    public:
        auto Get_IsValid() const -> bool { return _FlatPlate != INDEX_NONE; }
    };

    struct FSceneTally
    {
        int32 _Measured = 0;
        int32 _Unreached = 0;
        int32 _SamePlate = 0;

        int32 _OracleCompared = 0;
        int32 _OracleMismatched = 0;
        int32 _OracleShortcut = 0;

        int32 _PulledOverRaw = 0;
        int32 _RatioOutOfRange = 0;
        int32 _ChainDisagreed = 0;

        double _MinImprovementPercent = TNumericLimits<double>::Max();
        double _MaxImprovementPercent = TNumericLimits<double>::Lowest();
        double _TotalImprovementPercent = 0.0;

        double _WorstOracleDeltaUu = 0.0;

    public:
        auto Get_MeanImprovementPercent() const -> double
        {
            return _Measured > 0 ? _TotalImprovementPercent / static_cast<double>(_Measured) : 0.0;
        }
    };

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Make_FloodQuery(
        const FVector& InSource) -> FCk_GroundNav_FloodQuery
    {
        auto Query = FCk_GroundNav_FloodQuery{};

        Query._Source = InSource;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(kNoRadius);

        return Query;
    }

    auto Get_Resolved(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> FResolvedPoint
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStepHeight;

        const auto Result = Get_IsNavigable(InField, Query);

        auto Resolved = FResolvedPoint{};

        if (NOT Result.Get_IsSuccess())
        { return Resolved; }

        Resolved._Point = FVector{InLocation.X, InLocation.Y, static_cast<double>(Result._SurfaceZUu)};
        Resolved._FlatPlate = Get_FlatPlateIndex(InField, Result._Surface._TileIndex, Result._Surface._PlateIndex);
        Resolved._Label = InField.Get_ReachabilityLabel(Result._Surface._TileIndex, Result._Surface._PlateIndex);

        return Resolved;
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The crossings from the source up to and including one settled crossing, in walk order.
     *
     * Walked off the predecessor index the flood fill publishes on every settled crossing, which is the
     * same chain the library funnels through — so the raw polyline and the pulled string below are
     * measured over one route and not two.
     */
    auto Do_BuildCrossingChain(
        const FCk_GroundNav_FloodResult& InFlood,
        int32                            InCrossingIndex,
        TArray<FCk_GroundNav_Crossing>&  OutChain) -> void
    {
        OutChain.Reset();

        int32 Index = InCrossingIndex;

        while (InFlood._Crossings.IsValidIndex(Index))
        {
            OutChain.Emplace(InFlood._Crossings[Index]._Crossing);

            Index = InFlood._Crossings[Index]._Predecessor;
        }

        Algo::Reverse(OutChain);
    }

    auto Make_Portals(
        TConstArrayView<FCk_GroundNav_Crossing> InChain) -> TArray<FCk_GroundNav_FunnelPortal>
    {
        auto Portals = TArray<FCk_GroundNav_FunnelPortal>{};
        Portals.Reserve(InChain.Num());

        for (const auto& Crossing : InChain)
        {
            auto Portal = FCk_GroundNav_FunnelPortal{};

            Portal._Left = Crossing._Left;
            Portal._Right = Crossing._Right;

            Portals.Emplace(Portal);
        }

        return Portals;
    }

    /** Start, every crossing's own midpoint, goal: the route the plate sequence describes before it is pulled. */
    auto Get_RawLengthXY(
        const FVector&                          InStart,
        const FVector&                          InGoal,
        TConstArrayView<FCk_GroundNav_Crossing> InChain) -> double
    {
        auto Previous = Get_XY(InStart);
        auto Length = 0.0;

        for (const auto& Crossing : InChain)
        {
            const auto Midpoint = (Get_XY(Crossing._Left) + Get_XY(Crossing._Right)) * 0.5;

            Length += FVector2D::Distance(Previous, Midpoint);
            Previous = Midpoint;
        }

        return Length + FVector2D::Distance(Previous, Get_XY(InGoal));
    }

    /**
     * The exact shortest path, where the construction can state one.
     *
     * It is stated on the ground storey of one component for a body of no size; a pair leaving any of
     * those conditions has no oracle rather than a wrong one.
     */
    auto Get_OracleLength(
        const FCk_GroundNav_Field& InField,
        const FResolvedPoint&      InSource,
        const FResolvedPoint&      InGoal) -> TOptional<double>
    {
        if (InSource._Label == INDEX_NONE || InSource._Label != InGoal._Label)
        { return {}; }

        if (InSource._Point.Z > kGroundStoreyMaxZ || InGoal._Point.Z > kGroundStoreyMaxZ)
        { return {}; }

        const auto Graph = Make_VisibilityGraph(InField, InSource._Label, Get_XY(InSource._Point));

        return Get_ReferenceDistance(InField, Graph, Get_XY(InGoal._Point));
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * One pair, measured and logged, folded into the scene's running tally.
     *
     * The chain measured is the one the flood fill would answer this goal with: the entry into the
     * goal's plate whose pulled string is shortest, which is exactly how Get_FloodDistanceTo picks. Any
     * other entry would describe a route the library does not report.
     */
    auto Do_MeasurePair(
        const FCk_GroundNav_Field& InField,
        const TCHAR*               InSceneName,
        const FProbePair&          InPair,
        FSceneTally&               OutTally) -> void
    {
        const auto Flood = Get_FloodFill(InField, Make_FloodQuery(InPair._Start));

        const auto Source = Get_Resolved(InField, InPair._Start);
        const auto Goal = Get_Resolved(InField, InPair._Goal);

        if (NOT Flood.Get_IsSuccess() || NOT Source.Get_IsValid() || NOT Goal.Get_IsValid() ||
            NOT Flood.Get_IsPlateReached(Goal._FlatPlate))
        {
            ++OutTally._Unreached;
            return;
        }

        if (Goal._FlatPlate == Flood._SourceFlatPlate)
        {
            ++OutTally._SamePlate;
            return;
        }

        auto Chain = TArray<FCk_GroundNav_Crossing>{};
        auto BestChain = TArray<FCk_GroundNav_Crossing>{};
        auto Waypoints = TArray<FVector>{};

        auto BestPulledUu = TNumericLimits<double>::Max();

        for (const auto EntryIndex : Flood._PlateEntries[Goal._FlatPlate])
        {
            if (NOT Flood._Crossings.IsValidIndex(EntryIndex))
            { continue; }

            Do_BuildCrossingChain(Flood, EntryIndex, Chain);

            const auto PulledUu =
                Get_StringPull(Flood._SourcePoint, Goal._Point, Make_Portals(Chain), kNoRadius, Waypoints);

            if (PulledUu >= BestPulledUu)
            { continue; }

            BestPulledUu = PulledUu;
            BestChain = Chain;
        }

        if (BestChain.IsEmpty())
        {
            ++OutTally._Unreached;
            return;
        }

        const auto RawUu = Get_RawLengthXY(Flood._SourcePoint, Goal._Point, BestChain);

        if (RawUu <= kEpsilon)
        {
            ++OutTally._SamePlate;
            return;
        }

        const auto Ratio = BestPulledUu / RawUu;
        const auto ImprovementPercent = (1.0 - Ratio) * 100.0;

        const auto Oracle = Get_OracleLength(InField, Source, Goal);

        // The library's own answer over the same flood, so a chain rebuilt wrong here shows up as a
        // disagreement rather than as a plausible-looking improvement measured off the wrong route.
        const auto Reported =
            Get_FloodDistanceTo(InField, Flood, InPair._Goal, kStepHeight, Make_Agent(kNoRadius));

        ++OutTally._Measured;

        OutTally._MinImprovementPercent = FMath::Min(OutTally._MinImprovementPercent, ImprovementPercent);
        OutTally._MaxImprovementPercent = FMath::Max(OutTally._MaxImprovementPercent, ImprovementPercent);
        OutTally._TotalImprovementPercent += ImprovementPercent;

        if (BestPulledUu > RawUu + kEpsilon)
        { ++OutTally._PulledOverRaw; }

        if (Ratio <= 0.0 || Ratio > 1.0 + kEpsilon)
        { ++OutTally._RatioOutOfRange; }

        if (NOT Reported.IsSet() || FMath::Abs(Reported.GetValue() - BestPulledUu) > kEpsilon)
        { ++OutTally._ChainDisagreed; }

        if (Oracle.IsSet())
        {
            const auto Delta = BestPulledUu - Oracle.GetValue();

            ++OutTally._OracleCompared;
            OutTally._WorstOracleDeltaUu = FMath::Max(OutTally._WorstOracleDeltaUu, FMath::Abs(Delta));

            if (FMath::Abs(Delta) > kOracleToleranceUu)
            { ++OutTally._OracleMismatched; }

            // The oracle is the shortest path there is, so the pulled string may only ever be longer.
            // One that came in UNDER it took a route the geometry does not offer, which no tolerance on
            // the absolute difference would catch.
            if (Delta < -kEpsilon)
            { ++OutTally._OracleShortcut; }
        }

        const auto OracleText =
            Oracle.IsSet() ? FString::Printf(TEXT("%.3f"), Oracle.GetValue()) : FString{TEXT("n/a")};

        const auto Report = FString::Printf(
            TEXT("[FUNNEL-BUDGET] %s (%.0f, %.0f)->(%.0f, %.0f): raw=%.3f pulled=%.3f oracle=%s improvement=%.3f%% crossings=%d"),
            InSceneName,
            InPair._Start.X, InPair._Start.Y, InPair._Goal.X, InPair._Goal.Y,
            RawUu, BestPulledUu, *OracleText, ImprovementPercent, BestChain.Num());

        ck::groundnav::Display(TEXT("{}"), Report);
    }

    auto Do_MeasureScene(
        const FCk_GroundNav_Field&  InField,
        const TCHAR*                InSceneName,
        TConstArrayView<FProbePair> InPairs,
        FSceneTally&                OutTally) -> void
    {
        for (const auto& Pair : InPairs)
        { Do_MeasurePair(InField, InSceneName, Pair, OutTally); }

        const auto Report = FString::Printf(
            TEXT("[FUNNEL-BUDGET] %s aggregate: pairs=%d min=%.3f%% max=%.3f%% mean=%.3f%% (unreached %d, same plate %d, oracle compared %d worst delta %.3f)"),
            InSceneName, OutTally._Measured,
            OutTally._Measured > 0 ? OutTally._MinImprovementPercent : 0.0,
            OutTally._Measured > 0 ? OutTally._MaxImprovementPercent : 0.0,
            OutTally.Get_MeanImprovementPercent(),
            OutTally._Unreached, OutTally._SamePlate, OutTally._OracleCompared, OutTally._WorstOracleDeltaUu);

        ck::groundnav::Display(TEXT("{}"), Report);
    }

    auto Get_SceneReport(
        const TCHAR*       InSceneName,
        const FSceneTally& InTally) -> FString
    {
        return FString::Printf(
            TEXT("%s: measured %d, pulled over raw %d, ratio out of range %d, chain disagreed %d, oracle compared %d mismatched %d shortcut %d"),
            InSceneName, InTally._Measured, InTally._PulledOverRaw, InTally._RatioOutOfRange,
            InTally._ChainDisagreed, InTally._OracleCompared, InTally._OracleMismatched, InTally._OracleShortcut);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Funnel_ImprovementOverRawCrossingChain,
    "CkTests.UnitTests.CkGroundNav.Query.Funnel_ImprovementOverRawCrossingChain",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Funnel_ImprovementOverRawCrossingChain::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_funnelimprovement;

    // The west room, the east room and the ground around the hole. The dividing wall reaches both field
    // edges, so no pair spans it and the two halves are measured separately.
    const auto QueryPairs = TArray<FProbePair>{
        FProbePair{FVector{150.0, 150.0, kGroundZ}, FVector{150.0, 1450.0, kGroundZ}},
        FProbePair{FVector{150.0, 150.0, kGroundZ}, FVector{650.0, 1450.0, kGroundZ}},
        FProbePair{FVector{250.0, 1350.0, kGroundZ}, FVector{600.0, 1350.0, kGroundZ}},
        FProbePair{FVector{900.0, 150.0, kGroundZ}, FVector{900.0, 1450.0, kGroundZ}},
        FProbePair{FVector{900.0, 1100.0, kGroundZ}, FVector{1500.0, 1100.0, kGroundZ}},
        FProbePair{FVector{1400.0, 150.0, kGroundZ}, FVector{900.0, 1450.0, kGroundZ}}};

    // Every route between the halves of the west room threads the one 60 uu gap.
    const auto DoorwayPairs = TArray<FProbePair>{
        FProbePair{FVector{200.0, 500.0, kGroundZ}, FVector{200.0, 1400.0, kGroundZ}},
        FProbePair{FVector{100.0, 300.0, kGroundZ}, FVector{600.0, 1500.0, kGroundZ}},
        FProbePair{FVector{650.0, 200.0, kGroundZ}, FVector{100.0, 1500.0, kGroundZ}},
        FProbePair{FVector{200.0, 800.0, kGroundZ}, FVector{500.0, 1300.0, kGroundZ}}};

    // Open floor either side of a gap nothing spans: the chain is a tile seam and nothing else, which
    // is where the raw polyline is already close to straight and the pull has least to buy.
    const auto IslandPairs = TArray<FProbePair>{
        FProbePair{FVector{100.0, 100.0, kGroundZ}, FVector{500.0, 1400.0, kGroundZ}},
        FProbePair{FVector{500.0, 150.0, kGroundZ}, FVector{150.0, 1450.0, kGroundZ}},
        FProbePair{FVector{1100.0, 150.0, kGroundZ}, FVector{1500.0, 1400.0, kGroundZ}},
        FProbePair{FVector{1500.0, 150.0, kGroundZ}, FVector{1100.0, 1450.0, kGroundZ}}};

    auto QueryField = FCk_GroundNav_Field{};
    auto DoorwayField = FCk_GroundNav_Field{};
    auto IslandField = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(QueryField)))
    { return false; }

    if (NOT TestTrue(TEXT("the doorway scene bakes"), Bake(Make_DoorwayScene(), Make_QueryParams(), DoorwayField)))
    { return false; }

    if (NOT TestTrue(TEXT("the two-island scene bakes"), Bake(Make_TwoIslandScene(), Make_QueryParams(), IslandField)))
    { return false; }

    auto QueryTally = FSceneTally{};
    auto DoorwayTally = FSceneTally{};
    auto IslandTally = FSceneTally{};

    Do_MeasureScene(QueryField, TEXT("query"), QueryPairs, QueryTally);
    Do_MeasureScene(DoorwayField, TEXT("doorway"), DoorwayPairs, DoorwayTally);
    Do_MeasureScene(IslandField, TEXT("islands"), IslandPairs, IslandTally);

    const auto Tallies = TArray<FSceneTally>{QueryTally, DoorwayTally, IslandTally};
    const auto Names = TArray<const TCHAR*>{TEXT("query"), TEXT("doorway"), TEXT("islands")};

    auto FloorPercent = TNumericLimits<double>::Max();
    auto TotalMeasured = 0;

    for (const auto& Tally : Tallies)
    {
        if (Tally._Measured == 0)
        { continue; }

        TotalMeasured += Tally._Measured;
        FloorPercent = FMath::Min(FloorPercent, Tally._MinImprovementPercent);
    }

    const auto FloorReport = FString::Printf(
        TEXT("[FUNNEL-BUDGET] floor candidate: min improvement over all pairs = %.3f%%"),
        TotalMeasured > 0 ? FloorPercent : 0.0);

    ck::groundnav::Display(TEXT("{}"), FloorReport);

    if (NOT TestTrue(TEXT("some pair on some scene was measured"), TotalMeasured > 0))
    { return false; }

    for (auto Index = 0; Index < Tallies.Num(); ++Index)
    {
        const auto& Tally = Tallies[Index];
        const auto Report = Get_SceneReport(Names[Index], Tally);

        // Without a floor on the sample every bound below holds vacuously, and a scene that quietly
        // stopped connecting would report an improvement of nothing and pass.
        if (NOT TestTrue(FString::Printf(TEXT("the scene contributed pairs to measure [%s]"), *Report),
            Tally._Measured >= kMinMeasuredPairsPerScene))
        { continue; }

        // The polyline through the same intervals in the same order is itself a feasible string, so the
        // shortest one cannot be longer than it. A pull that came out longer is not a weaker saving —
        // it is a route through the chain the funnel got wrong.
        TestEqual(FString::Printf(TEXT("no pulled string is longer than its raw crossing chain [%s]"), *Report),
            Tally._PulledOverRaw, 0);

        TestEqual(FString::Printf(TEXT("every ratio of pulled to raw is a real fraction of it [%s]"), *Report),
            Tally._RatioOutOfRange, 0);

        // The chain rebuilt from the published predecessors has to be the chain the library answers
        // with, or the improvement above is measured against a route nobody walks.
        TestEqual(FString::Printf(TEXT("the rebuilt chain gives the distance the flood fill reports [%s]"), *Report),
            Tally._ChainDisagreed, 0);

        TestEqual(FString::Printf(TEXT("every pulled string is within a cell of the exact shortest path [%s]"), *Report),
            Tally._OracleMismatched, 0);

        TestEqual(FString::Printf(TEXT("no pulled string undercuts the exact shortest path [%s]"), *Report),
            Tally._OracleShortcut, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
