// What a search does with an authored link in the graph it walks.
//
// A link is the one edge of this graph that is not a door in a wall: it joins two points the lattice
// never joined, it is priced by its own span rather than by the ground under it, and it puts two
// waypoints on the route where a door puts one. Every claim here is measured against something that is
// not the link. Whether the route takes it is measured against the SAME field with the link priced out
// of reach, so the two runs differ in one number and in nothing else. What the way round costs is
// measured against a closed form of the geometry - a barrier the free space's full width with the only
// way past it at the far end, so the detour is two straight legs bending on the barrier's top corners
// plus a step across its thickness. And the sliced run is measured against the one-shot run element for
// element, because the link block of the enumeration is the newest thing the push order rests on.
//
// The crossover is taken where the two COSTS meet rather than where the two LENGTHS meet. What the
// search compares is the graph's own price of a corridor and not its funnelled length, and a multiplier
// derived from the taut detour would land on the right side of that decision only by luck. A link edge
// is its span times its multiplier and nothing else on the route moves with that multiplier, so the
// price is affine in it: one run priced at one fixes the whole line, the meeting point is a closed form
// of two measured runs, and the two cases sit a tenth either side of it.

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_PlatePortalGraph.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_linksearch
{
    using ck::groundnav::FCk_GroundNav_Crossing;
    using ck::groundnav::FCk_GroundNav_CrossingKey;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSharedData;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::FCk_GroundNav_PlatePortalGraph;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::Get_CornerOffset;
    using ck::groundnav::Get_Funnelled;
    using ck::groundnav::Get_Path;
    using ck::groundnav::kPathSourceNode;
    using ck::groundnav::Make_CrossingKey;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    // --------------------------------------------------------------------------------------------------

    // Every closed form below is stated for a body of no size: an inset body cannot touch the corners
    // the taut string bends on.
    constexpr auto kNoRadius = 0.0f;

    // The tolerance the search tests hold a measured length to against a stated one, which is one cell:
    // a portal stands on a cell line and a closed form of the geometry does not.
    constexpr auto kOracleToleranceUu = static_cast<double>(kCellSize);

    // Two prices of the SAME corridor, so nothing but float rounding stands between them.
    constexpr auto kCostToleranceUu = 1.0;

    // One expansion per slice: the finest grain there is, so a verdict that depended on where a slice
    // boundary fell would differ at every boundary rather than at some of them.
    constexpr auto kOneExpansionPerSlice = 1;

    // A sliced run that has not terminated by here is not slow, it is stuck.
    constexpr auto kMaxSlices = 100000;

    // A tenth either side of the multiplier at which the link and the way round cost the same.
    constexpr auto kUnderTheCrossover = 0.9f;
    constexpr auto kOverTheCrossover = 1.1f;

    constexpr auto kFirstLinkIndex = 0;
    constexpr auto kSecondLinkIndex = 1;

    constexpr auto kOneCrossing = 1;
    constexpr auto kNoCrossings = 0;
    constexpr auto kTwoPortalsPerLink = 2;
    constexpr auto kOnce = 1;

    // --------------------------------------------------------------------------------------------------

    // A barrier across the free space with the only way past it at the far end, so the way round is two
    // straight legs bending on its two top corners plus a step across its thickness. The outer blocks
    // reach well past the field in every direction, so no route escapes around the fixture itself.
    constexpr auto kBarrierFreeMinX = 100.0;
    constexpr auto kBarrierFreeMaxX = 700.0;
    constexpr auto kBarrierFreeMinY = 100.0;
    constexpr auto kBarrierFreeMaxY = 700.0;

    constexpr auto kBarrierMinX = 350.0;
    constexpr auto kBarrierMaxX = 450.0;
    constexpr auto kBarrierTopY = 500.0;

    // Placed the same distance from the barrier on either side, which is what makes the way round a
    // closed form rather than four separate legs.
    const auto kBarrierStart = FVector{200.0, 200.0, kGroundZ};
    const auto kBarrierGoal = FVector{600.0, 200.0, kGroundZ};

    // Straight across the barrier at the height of both ends, so the route that takes it is ONE line and
    // its taut length is the distance between those ends.
    const auto kLinkEntry = FVector{300.0, 200.0, kGroundZ};
    const auto kLinkExit = FVector{500.0, 200.0, kGroundZ};

    // Off that line, so the string has to BEND at both endpoints rather than run through them.
    const auto kBentLinkEntry = FVector{300.0, 350.0, kGroundZ};
    const auto kBentLinkExit = FVector{500.0, 350.0, kGroundZ};

    // A second link on the same field, so the enumeration has more than one of them to order.
    const auto kSecondLinkEntry = FVector{300.0, 450.0, kGroundZ};
    const auto kSecondLinkExit = FVector{500.0, 450.0, kGroundZ};

    constexpr auto kLinkSpanUu = 200.0;

    // Narrower than the ground at either end, so admission can only be answering with the number the
    // record authored and not with whatever the plates at its ends already allow.
    constexpr auto kAuthoredClearanceUu = 20.0f;

    constexpr auto kAdmittedRadiusUu = 10.0f;
    constexpr auto kRefusedRadiusUu = 30.0f;

    // Two points a link joins across a TILE seam, so the plates at its ends are two plates by
    // construction and a lattice route between them exists without depending on how a merge ran.
    const auto kSeamLinkEntry = FVector{400.0, 400.0, kGroundZ};
    const auto kSeamLinkExit = FVector{1200.0, 400.0, kGroundZ};

    // A second exit on that same far plate, so two links leave ONE point for ONE plate and differ in
    // nothing a crossing carries except which link they are.
    const auto kSeamLinkSecondExit = FVector{1200.0, 600.0, kGroundZ};

    constexpr auto kCornerOffsetUu = 20.0f;
    constexpr auto kOffsetAgentRadiusUu = 10.0f;

    constexpr auto kStraightThroughALinkIsFourWaypoints = 4;

    // The route a case asks this of crosses no link, so no waypoint of one is exempt from the offset.
    const auto kNothingPinned = TArray<FVector>{};

    // --------------------------------------------------------------------------------------------------

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

    /** One floor under the whole 2 x 2 field and its halo, so its tiles are joined by seams and by nothing else. */
    auto Make_OpenFloorScene() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    }

    /** Up to the barrier's top corner, across its thickness, and back down the far side. */
    auto Get_BarrierDetourLengthUu() -> double
    {
        const auto ReachX = kBarrierMinX - kBarrierStart.X;
        const auto ClimbY = kBarrierTopY - kBarrierStart.Y;

        return (2.0 * FMath::Sqrt((ReachX * ReachX) + (ClimbY * ClimbY))) +
            (kBarrierMaxX - kBarrierMinX);
    }

    /** The route that takes the straight link: one line from the start through both of its ends to the goal. */
    auto Get_BarrierStraightLengthUu() -> double
    {
        return kBarrierGoal.X - kBarrierStart.X;
    }

    // --------------------------------------------------------------------------------------------------

    auto Make_LinkRecord(
        int32          InId,
        const FVector& InStart,
        const FVector& InEnd,
        float          InMultiplier) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};

        Record.Set_CostMultiplierForward(InMultiplier);
        Record.Set_CostMultiplierBackward(InMultiplier);

        return Record;
    }

    /**
     * A scene published the way a search takes one.
     *
     * The search holds the field by shared pointer so a rebuild underneath a sliced run cannot take it
     * away, which means every scene here has to be published into one rather than kept on the stack.
     */
    auto Bake_Shared(
        const TArray<FBox>&                     InBoxes,
        const FCk_GroundNav_FieldParams&        InBaseParams,
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_FieldPtr&                 OutField) -> bool
    {
        auto Params = InBaseParams;
        Params._Links = InLinks;

        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(InBoxes, Params, *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    auto Bake_Barrier(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_FieldPtr&                 OutField) -> bool
    {
        return Bake_Shared(Make_BarrierScene(), Make_FlatParams(), InLinks, OutField);
    }

    auto Bake_OpenFloor(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_FieldPtr&                 OutField) -> bool
    {
        return Bake_Shared(Make_OpenFloorScene(), Make_QueryParams(), InLinks, OutField);
    }

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

    auto Make_BarrierQuery(
        float InRadiusUu) -> FCk_GroundNav_PathQuery
    {
        return Make_PathQuery(kBarrierStart, kBarrierGoal, InRadiusUu);
    }

    auto Make_SharedData(
        const FCk_GroundNav_FieldPtr& InField,
        int32                         InGoalFlatPlate,
        const FVector&                InSourcePoint,
        const FVector&                InGoalPoint) -> TSharedPtr<const FCk_GroundNav_PathSharedData>
    {
        auto Shared = MakeShared<FCk_GroundNav_PathSharedData>();

        Shared->_Field = InField;
        Shared->_Epoch = InField->_Epoch;
        Shared->_GoalFlatPlate = InGoalFlatPlate;
        Shared->_GoalPoint = InGoalPoint;
        Shared->_SourcePoint = InSourcePoint;
        Shared->_CellSizeUu = kCellSize;

        return Shared;
    }

    // --------------------------------------------------------------------------------------------------

    auto Get_LinkCrossingCount(
        const FCk_GroundNav_PathResult& InResult) -> int32
    {
        auto Count = 0;

        for (const auto& Crossing : InResult._Crossings)
        {
            if (Crossing._LinkIndex != INDEX_NONE)
            { ++Count; }
        }

        return Count;
    }

    auto Get_FirstLinkIndex(
        const FCk_GroundNav_PathResult& InResult) -> int32
    {
        for (const auto& Crossing : InResult._Crossings)
        {
            if (Crossing._LinkIndex != INDEX_NONE)
            { return Crossing._LinkIndex; }
        }

        return INDEX_NONE;
    }

    auto Get_LinkPortalCount(
        const FCk_GroundNav_PathResult& InResult) -> int32
    {
        auto Count = 0;

        for (const auto& Portal : InResult._FunnelPortals)
        {
            if (Portal._LinkIndex != INDEX_NONE)
            { ++Count; }
        }

        return Count;
    }

    auto Get_FirstLinkPortal(
        const FCk_GroundNav_PathResult& InResult) -> int32
    {
        for (auto Index = 0; Index < InResult._FunnelPortals.Num(); ++Index)
        {
            if (InResult._FunnelPortals[Index]._LinkIndex != INDEX_NONE)
            { return Index; }
        }

        return INDEX_NONE;
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

    auto Get_WaypointIndex(
        TConstArrayView<FVector> InWaypoints,
        const FVector&           InPoint) -> int32
    {
        for (auto Index = 0; Index < InWaypoints.Num(); ++Index)
        {
            if (InWaypoints[Index] == InPoint)
            { return Index; }
        }

        return INDEX_NONE;
    }

    auto Get_WaypointOccurrences(
        TConstArrayView<FVector> InWaypoints,
        const FVector&           InPoint) -> int32
    {
        auto Count = 0;

        for (const auto& Waypoint : InWaypoints)
        {
            if (Waypoint == InPoint)
            { ++Count; }
        }

        return Count;
    }

    auto Get_FunnelledLengthUu(
        const FCk_GroundNav_PathResult& InResult,
        TArray<FVector>&                OutWaypoints) -> double
    {
        return Get_Funnelled(InResult, kNoRadius, OutWaypoints);
    }

    // --------------------------------------------------------------------------------------------------

    /**
     * Where the link and the way round cost the same, in the quantity the search actually compares.
     *
     * The corridor that takes the link is its two on-plate legs plus span times multiplier, and only
     * the last term moves with that multiplier - so the price is affine in it and one run priced at one
     * fixes the whole line. Below this number the link wins and above it the way round does.
     */
    auto Get_CrossoverMultiplier(
        float  InDetourCostUu,
        float  InCostAtMultiplierOneUu,
        double InSpanUu) -> float
    {
        const auto ExcessUu =
            static_cast<double>(InDetourCostUu) - static_cast<double>(InCostAtMultiplierOneUu);

        return 1.0f + static_cast<float>(ExcessUu / InSpanUu);
    }

    auto Get_PricedAt(
        float  InCostAtMultiplierOneUu,
        double InSpanUu,
        float  InMultiplier) -> double
    {
        return static_cast<double>(InCostAtMultiplierOneUu) +
            (InSpanUu * (static_cast<double>(InMultiplier) - 1.0));
    }

    /**
     * The two runs every crossover case is stated against - the field with no link at all and the same
     * field with the link priced at one - and the multiplier at which the two answers cost the same.
     */
    struct FCrossover
    {
        FCk_GroundNav_PathResult _Detour;
        FCk_GroundNav_PathResult _AtMultiplierOne;

        float _Multiplier = 1.0f;
    };

    auto Do_MeasureCrossover(
        FCrossover& OutCrossover) -> bool
    {
        auto Plain = FCk_GroundNav_FieldPtr{};

        if (NOT Bake_Barrier({}, Plain))
        { return false; }

        auto Linked = FCk_GroundNav_FieldPtr{};

        if (NOT Bake_Barrier({Make_LinkRecord(1, kLinkEntry, kLinkExit, 1.0f)}, Linked))
        { return false; }

        OutCrossover._Detour = Get_Path(Plain, Make_BarrierQuery(kNoRadius));
        OutCrossover._AtMultiplierOne = Get_Path(Linked, Make_BarrierQuery(kNoRadius));

        if (OutCrossover._Detour._Status != ECk_GroundNav_PathStatus::Ready ||
            OutCrossover._AtMultiplierOne._Status != ECk_GroundNav_PathStatus::Ready)
        { return false; }

        OutCrossover._Multiplier = Get_CrossoverMultiplier(
            OutCrossover._Detour._SearchCost,
            OutCrossover._AtMultiplierOne._SearchCost,
            kLinkSpanUu);

        return true;
    }

    // --------------------------------------------------------------------------------------------------

    /**
     * The first thing two results disagree about, or nothing.
     *
     * A named disagreement rather than a boolean, because "the sliced run differed" is not a report
     * anybody can act on. The link index is compared beside the endpoints: two crossings can leave and
     * enter the same plates at the same point and still be different routes, so a comparison without it
     * would call a link and the door beside it one corridor. Times are not compared - a run cut into a
     * hundred calls samples the clock a hundred times more often than one call does.
     */
    auto Get_Disagreement(
        const FCk_GroundNav_PathResult& InLeft,
        const FCk_GroundNav_PathResult& InRight) -> FString
    {
        if (InLeft._Status != InRight._Status)
        {
            return FString::Printf(TEXT("status %d vs %d"),
                static_cast<int32>(InLeft._Status), static_cast<int32>(InRight._Status));
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
                Left._Direction == Right._Direction &&
                Left._LinkIndex == Right._LinkIndex &&
                Left._Left == Right._Left &&
                Left._Right == Right._Right;

            if (NOT CrossingsAgree)
            {
                return FString::Printf(TEXT("crossing %d: %d->%d link %d vs %d->%d link %d"), Index,
                    Left._FromFlatPlate, Left._ToFlatPlate, Left._LinkIndex,
                    Right._FromFlatPlate, Right._ToFlatPlate, Right._LinkIndex);
            }
        }

        if (InLeft._FunnelPortals.Num() != InRight._FunnelPortals.Num())
        {
            return FString::Printf(TEXT("%d vs %d funnel portals"),
                InLeft._FunnelPortals.Num(), InRight._FunnelPortals.Num());
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_PathUsesTheLinkWhenItBeatsTheDetour,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.PathUsesTheLinkWhenItBeatsTheDetour",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_PathUsesTheLinkWhenItBeatsTheDetour::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    TestEqual(TEXT("the route with no link crosses none"),
        Get_LinkCrossingCount(Crossover._Detour), kNoCrossings);

    auto DetourWaypoints = TArray<FVector>{};
    const auto DetourLengthUu = Get_FunnelledLengthUu(Crossover._Detour, DetourWaypoints);

    TestTrue(FString::Printf(TEXT("and is the closed form of the way round: %.3f against %.3f"),
        DetourLengthUu, Get_BarrierDetourLengthUu()),
        FMath::Abs(DetourLengthUu - Get_BarrierDetourLengthUu()) <= kOracleToleranceUu);

    const auto CheapMultiplier = 1.0f + (kUnderTheCrossover * (Crossover._Multiplier - 1.0f));

    if (NOT TestTrue(FString::Printf(
        TEXT("the crossover multiplier %.4f leaves an admissible price under it"), Crossover._Multiplier),
        CheapMultiplier >= 1.0f))
    { return false; }

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the same scene bakes with the link priced under the crossover"),
        Bake_Barrier({Make_LinkRecord(1, kLinkEntry, kLinkExit, CheapMultiplier)}, Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_BarrierQuery(kNoRadius));

    if (NOT TestTrue(TEXT("and the search answers a route over it"),
        Result._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("that takes a link exactly once"), Get_LinkCrossingCount(Result), kOneCrossing);
    TestEqual(TEXT("and takes the only link there is"), Get_FirstLinkIndex(Result), kFirstLinkIndex);

    TestTrue(FString::Printf(TEXT("for less than the way round: %.3f against %.3f"),
        Result._SearchCost, Crossover._Detour._SearchCost),
        Result._SearchCost < Crossover._Detour._SearchCost);

    const auto PricedUu = Get_PricedAt(
        Crossover._AtMultiplierOne._SearchCost, kLinkSpanUu, CheapMultiplier);

    TestTrue(FString::Printf(
        TEXT("priced at its own span times its multiplier and nothing else: %.3f against %.3f"),
        Result._SearchCost, PricedUu),
        FMath::Abs(static_cast<double>(Result._SearchCost) - PricedUu) <= kCostToleranceUu);

    auto Waypoints = TArray<FVector>{};
    const auto LengthUu = Get_FunnelledLengthUu(Result, Waypoints);

    TestTrue(FString::Printf(TEXT("and walks the straight line the link makes: %.3f against %.3f"),
        LengthUu, Get_BarrierStraightLengthUu()),
        FMath::Abs(LengthUu - Get_BarrierStraightLengthUu()) <= kOracleToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_PathTakesTheDetourWhenTheLinkDoesNot,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.PathTakesTheDetourWhenTheLinkDoesNot",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_PathTakesTheDetourWhenTheLinkDoesNot::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    const auto DearMultiplier = 1.0f + (kOverTheCrossover * (Crossover._Multiplier - 1.0f));

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the same scene bakes with the link priced over the crossover"),
        Bake_Barrier({Make_LinkRecord(1, kLinkEntry, kLinkExit, DearMultiplier)}, Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_BarrierQuery(kNoRadius));

    if (NOT TestTrue(TEXT("and the search still answers a route"),
        Result._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("that crosses no link"), Get_LinkCrossingCount(Result), kNoCrossings);

    TestTrue(TEXT("and is the corridor the field without a link answered with"),
        Result._PlateCorridor == Crossover._Detour._PlateCorridor);

    TestTrue(FString::Printf(TEXT("at the same price: %.3f against %.3f"),
        Result._SearchCost, Crossover._Detour._SearchCost),
        FMath::Abs(static_cast<double>(Result._SearchCost) -
            static_cast<double>(Crossover._Detour._SearchCost)) <= kCostToleranceUu);

    auto Waypoints = TArray<FVector>{};
    const auto LengthUu = Get_FunnelledLengthUu(Result, Waypoints);

    TestTrue(FString::Printf(TEXT("walking the closed form of the way round: %.3f against %.3f"),
        LengthUu, Get_BarrierDetourLengthUu()),
        FMath::Abs(LengthUu - Get_BarrierDetourLengthUu()) <= kOracleToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_OneDirectionalLinkTraversesInExactlyOneDirection,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.OneDirectionalLinkTraversesInExactlyOneDirection",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_OneDirectionalLinkTraversesInExactlyOneDirection::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Forward = Make_LinkRecord(1, kLinkEntry, kLinkExit, 1.0f);
    Forward.Set_Direction(ECk_GroundNav_LinkDirection::Forward);

    auto ForwardField = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with a forward-only link"),
        Bake_Barrier({Forward}, ForwardField)))
    { return false; }

    const auto WithTheGrain = Get_Path(
        ForwardField, Make_PathQuery(kBarrierStart, kBarrierGoal, kNoRadius));

    const auto AgainstTheGrain = Get_Path(
        ForwardField, Make_PathQuery(kBarrierGoal, kBarrierStart, kNoRadius));

    if (NOT TestTrue(TEXT("a forward link answers both ways round the barrier"),
        WithTheGrain._Status == ECk_GroundNav_PathStatus::Ready &&
        AgainstTheGrain._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("start to end crosses the forward link"),
        Get_LinkCrossingCount(WithTheGrain), kOneCrossing);

    TestEqual(TEXT("and end to start takes the way round instead"),
        Get_LinkCrossingCount(AgainstTheGrain), kNoCrossings);

    auto Backward = Make_LinkRecord(2, kLinkEntry, kLinkExit, 1.0f);
    Backward.Set_Direction(ECk_GroundNav_LinkDirection::Backward);

    auto BackwardField = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with a backward-only link"),
        Bake_Barrier({Backward}, BackwardField)))
    { return false; }

    const auto Mirrored = Get_Path(
        BackwardField, Make_PathQuery(kBarrierGoal, kBarrierStart, kNoRadius));

    const auto MirroredAgainst = Get_Path(
        BackwardField, Make_PathQuery(kBarrierStart, kBarrierGoal, kNoRadius));

    if (NOT TestTrue(TEXT("a backward link answers both ways round the barrier"),
        Mirrored._Status == ECk_GroundNav_PathStatus::Ready &&
        MirroredAgainst._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("end to start crosses the backward link"),
        Get_LinkCrossingCount(Mirrored), kOneCrossing);

    TestEqual(TEXT("and start to end takes the way round instead"),
        Get_LinkCrossingCount(MirroredAgainst), kNoCrossings);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_DisabledLinkIsInvisibleToSearch,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.DisabledLinkIsInvisibleToSearch",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_DisabledLinkIsInvisibleToSearch::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Plain = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with no link at all"), Bake_Barrier({}, Plain)))
    { return false; }

    auto Disabled = Make_LinkRecord(1, kLinkEntry, kLinkExit, 1.0f);
    Disabled.Set_Enable(ECk_EnableDisable::Disable);

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("and again with a switched-off link across it"),
        Bake_Barrier({Disabled}, Field)))
    { return false; }

    if (NOT TestEqual(TEXT("the switched-off record still resolves to an entry"),
        Field->Get_ResolvedLinkCount(), 1))
    { return false; }

    TestTrue(TEXT("with both ends found"), Field->_ResolvedLinks[0].Get_IsResolved());
    TestFalse(TEXT("and nothing to traverse"), Field->_ResolvedLinks[0].Get_IsTraversable());

    const auto Reference = Get_Path(Plain, Make_BarrierQuery(kNoRadius));
    const auto Result = Get_Path(Field, Make_BarrierQuery(kNoRadius));

    if (NOT TestTrue(TEXT("both fields answer a route"),
        Reference._Status == ECk_GroundNav_PathStatus::Ready &&
        Result._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("the route crosses no link"), Get_LinkCrossingCount(Result), kNoCrossings);

    TestTrue(TEXT("and is the corridor the field without the record answered with"),
        Result._PlateCorridor == Reference._PlateCorridor);

    TestTrue(FString::Printf(TEXT("at the same price: %.3f against %.3f"),
        Result._SearchCost, Reference._SearchCost),
        FMath::Abs(static_cast<double>(Result._SearchCost) -
            static_cast<double>(Reference._SearchCost)) <= kCostToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_LinkAdmissionUsesTheAuthoredClearance,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.LinkAdmissionUsesTheAuthoredClearance",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_LinkAdmissionUsesTheAuthoredClearance::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Narrow = Make_LinkRecord(1, kLinkEntry, kLinkExit, 1.0f);
    Narrow.Set_ClearanceUu(kAuthoredClearanceUu);

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with a link narrower than the ground at its ends"),
        Bake_Barrier({Narrow}, Field)))
    { return false; }

    TestTrue(TEXT("and the entry carries the authored clearance"),
        Field->_ResolvedLinks[0]._ClearanceUu == kAuthoredClearanceUu);

    const auto Slim = Get_Path(Field, Make_BarrierQuery(kAdmittedRadiusUu));
    const auto Wide = Get_Path(Field, Make_BarrierQuery(kRefusedRadiusUu));

    if (NOT TestTrue(TEXT("both bodies are answered a route"),
        Slim._Status == ECk_GroundNav_PathStatus::Ready &&
        Wide._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("a body the clearance admits crosses the link"),
        Get_LinkCrossingCount(Slim), kOneCrossing);

    TestEqual(TEXT("and one it refuses takes the way round"),
        Get_LinkCrossingCount(Wide), kNoCrossings);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_LinkBesideARampIsNotEatenByTheBackPlateSkip,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.LinkBesideARampIsNotEatenByTheBackPlateSkip",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_LinkBesideARampIsNotEatenByTheBackPlateSkip::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the open floor bakes with a link across the seam between its tiles"),
        Bake_OpenFloor({Make_LinkRecord(1, kSeamLinkEntry, kSeamLinkExit, 1.0f)}, Field)))
    { return false; }

    if (NOT TestEqual(TEXT("and carries the one entry it was given"),
        Field->Get_ResolvedLinkCount(), 1))
    { return false; }

    const auto Link = Field->_ResolvedLinks[0];

    if (NOT TestTrue(TEXT("the link is traversable between two different plates"),
        Link.Get_IsTraversable() && Link._StartFlatPlate != Link._EndFlatPlate))
    { return false; }

    const auto Graph = FCk_GroundNav_PlatePortalGraph{
        Make_SharedData(Field, Link._StartFlatPlate, Link._End, Link._Start),
        Link._EndFlatPlate};

    // The walk arrives on the link's start plate through the LATTICE, so the plate it came from is the
    // plate the link goes back to - which is the one case the skip exists to refuse.
    auto Arrived = int32{INDEX_NONE};

    for (const auto Node : Graph.Neighbors(kPathSourceNode))
    {
        const auto& Crossing = Graph.Get_Crossing(Node);

        if (Crossing._LinkIndex == INDEX_NONE && Crossing._ToFlatPlate == Link._StartFlatPlate)
        {
            Arrived = Node;
            break;
        }
    }

    if (NOT TestTrue(TEXT("a lattice route joins the two plates the link joins"),
        Arrived != INDEX_NONE))
    { return false; }

    auto OffersTheLinkBack = false;
    auto OffersTheDoorBack = false;

    for (const auto Node : Graph.Neighbors(Arrived))
    {
        const auto& Crossing = Graph.Get_Crossing(Node);

        if (Crossing._ToFlatPlate != Link._EndFlatPlate)
        { continue; }

        if (Crossing._LinkIndex != INDEX_NONE)
        { OffersTheLinkBack = true; }
        else
        { OffersTheDoorBack = true; }
    }

    TestTrue(TEXT("the link back is still offered from the plate the walk arrived on"), OffersTheLinkBack);
    TestFalse(TEXT("while the door it just came through is not"), OffersTheDoorBack);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_FunnelEmitsBothLinkEndpointsAsConsecutiveWaypoints,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.FunnelEmitsBothLinkEndpointsAsConsecutiveWaypoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_FunnelEmitsBothLinkEndpointsAsConsecutiveWaypoints::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with a link off the line between the two ends"),
        Bake_Barrier({Make_LinkRecord(1, kBentLinkEntry, kBentLinkExit, 1.0f)}, Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_BarrierQuery(kNoRadius));

    if (NOT TestTrue(TEXT("and the search takes it, and takes nothing else"),
        Result._Status == ECk_GroundNav_PathStatus::Ready &&
        Result._Crossings.Num() == kOneCrossing &&
        Get_LinkCrossingCount(Result) == kOneCrossing))
    { return false; }

    if (NOT TestEqual(TEXT("the corridor carries two portals for the one crossing"),
        Get_LinkPortalCount(Result), kTwoPortalsPerLink))
    { return false; }

    const auto FirstPortal = Get_FirstLinkPortal(Result);

    if (NOT TestTrue(TEXT("and they are consecutive"),
        Result._FunnelPortals.IsValidIndex(FirstPortal + 1) &&
        Result._FunnelPortals[FirstPortal + 1]._LinkIndex ==
            Result._FunnelPortals[FirstPortal]._LinkIndex))
    { return false; }

    TestTrue(TEXT("the first standing on the entry the record authored"),
        Result._FunnelPortals[FirstPortal]._Left == kBentLinkEntry &&
        Result._FunnelPortals[FirstPortal]._Right == kBentLinkEntry);

    TestTrue(TEXT("and the second on its exit"),
        Result._FunnelPortals[FirstPortal + 1]._Left == kBentLinkExit &&
        Result._FunnelPortals[FirstPortal + 1]._Right == kBentLinkExit);

    auto Waypoints = TArray<FVector>{};
    Get_FunnelledLengthUu(Result, Waypoints);

    TestEqual(TEXT("the string bends at both ends and nowhere else"),
        Waypoints.Num(), kStraightThroughALinkIsFourWaypoints);

    const auto EntryIndex = Get_WaypointIndex(Waypoints, kBentLinkEntry);

    if (NOT TestTrue(TEXT("the entry is one of the waypoints"), EntryIndex != INDEX_NONE))
    { return false; }

    if (NOT TestTrue(TEXT("and the exit is the very next one"),
        Waypoints.IsValidIndex(EntryIndex + 1) && Waypoints[EntryIndex + 1] == kBentLinkExit))
    { return false; }

    TestEqual(TEXT("the entry is walked through once"),
        Get_WaypointOccurrences(Waypoints, kBentLinkEntry), kOnce);

    TestEqual(TEXT("and so is the exit"),
        Get_WaypointOccurrences(Waypoints, kBentLinkExit), kOnce);

    const auto Pinned = Get_PinnedWaypoints(Result);

    const auto Offset = Get_CornerOffset(
        Waypoints, Pinned, *Field, kCornerOffsetUu, Make_Agent(kOffsetAgentRadiusUu), kStepHeight);

    const auto Unpinned = Get_CornerOffset(
        Waypoints, kNothingPinned, *Field, kCornerOffsetUu, Make_Agent(kOffsetAgentRadiusUu), kStepHeight);

    TestTrue(TEXT("the corner offset leaves the entry where the record put it"),
        Offset[EntryIndex] == Waypoints[EntryIndex]);

    TestTrue(TEXT("and leaves the exit there too"),
        Offset[EntryIndex + 1] == Waypoints[EntryIndex + 1]);

    // Without the pin the same two points are inside corners like any other and the pass walks them off
    // the link, which is what makes the two assertions above about the exemption and not about the
    // geometry happening to sit still.
    TestTrue(TEXT("which is the exemption doing it and not the geometry"),
        NOT (Unpinned[EntryIndex] == Waypoints[EntryIndex]) &&
        NOT (Unpinned[EntryIndex + 1] == Waypoints[EntryIndex + 1]));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_SlicedSearchMatchesOneShotWithLinks,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.SlicedSearchMatchesOneShotWithLinks",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_SlicedSearchMatchesOneShotWithLinks::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with two links across it"),
        Bake_Barrier({
            Make_LinkRecord(1, kLinkEntry, kLinkExit, 1.0f),
            Make_LinkRecord(2, kSecondLinkEntry, kSecondLinkExit, 1.0f)}, Field)))
    { return false; }

    if (NOT TestEqual(TEXT("and carries both entries"), Field->Get_ResolvedLinkCount(), 2))
    { return false; }

    const auto Query = Make_BarrierQuery(kNoRadius);

    const auto OneShot = Get_Path(Field, Query);

    if (NOT TestTrue(TEXT("the one-shot run answers a route over a link"),
        OneShot._Status == ECk_GroundNav_PathStatus::Ready &&
        Get_LinkCrossingCount(OneShot) == kOneCrossing))
    { return false; }

    TestEqual(TEXT("and takes the nearer of the two"),
        Get_FirstLinkIndex(OneShot), kFirstLinkIndex);

    auto Slice = FCk_GroundNav_PathSliceParams{};
    Slice._MaxIterations = kOneExpansionPerSlice;

    auto SliceCount = 0;
    const auto Sliced = Do_RunSliced(Field, Query, Slice, SliceCount);

    TestTrue(TEXT("the sliced run terminates"), SliceCount < kMaxSlices);

    const auto Disagreement = Get_Disagreement(OneShot, Sliced);

    TestTrue(FString::Printf(TEXT("and answers what the one-shot run did: %s"),
        Disagreement.IsEmpty() ? TEXT("no disagreement") : *Disagreement),
        Disagreement.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_HeuristicStaysAdmissibleWithLinks,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.HeuristicStaysAdmissibleWithLinks",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_HeuristicStaysAdmissibleWithLinks::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with a link priced at exactly its own span"),
        Bake_Barrier({Make_LinkRecord(1, kLinkEntry, kLinkExit, 1.0f)}, Field)))
    { return false; }

    const auto Result = Get_Path(Field, Make_BarrierQuery(kNoRadius));

    if (NOT TestTrue(TEXT("and the search answers a route"),
        Result._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("over the link"), Get_LinkCrossingCount(Result), kOneCrossing);

    // A link priced at one costs exactly the distance it covers, so the whole route costs the straight
    // line between the two ends - and no route can cost less than that, because every edge of this
    // graph costs at least the Euclidean distance it spans. The answer is therefore the OPTIMUM and not
    // merely a path, which is what a Euclidean heuristic at w = 1 is supposed to buy.
    const auto OptimumUu = Get_BarrierStraightLengthUu();

    TestTrue(FString::Printf(TEXT("answered at the optimum: %.3f against %.3f"),
        Result._SearchCost, OptimumUu),
        FMath::Abs(static_cast<double>(Result._SearchCost) - OptimumUu) <= kOracleToleranceUu);

    auto Waypoints = TArray<FVector>{};
    const auto LengthUu = Get_FunnelledLengthUu(Result, Waypoints);

    TestTrue(FString::Printf(TEXT("and walked at the optimum: %.3f against %.3f"),
        LengthUu, OptimumUu),
        FMath::Abs(LengthUu - OptimumUu) <= kOracleToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkSearch_CrossingKeyDistinguishesALinkFromAPortalWithTheSameEndpoints,
    "CkTests.UnitTests.CkGroundNav.LinkSearch.CrossingKeyDistinguishesALinkFromAPortalWithTheSameEndpoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkSearch_CrossingKeyDistinguishesALinkFromAPortalWithTheSameEndpoints::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linksearch;

    auto Lattice = FCk_GroundNav_Crossing{};
    Lattice._FromFlatPlate = 3;
    Lattice._ToFlatPlate = 7;
    Lattice._Direction = INDEX_NONE;
    Lattice._Left = kLinkEntry;
    Lattice._Right = kLinkEntry;
    Lattice._ClearanceUu = 40.0f;

    auto Linked = Lattice;
    Linked._LinkIndex = kFirstLinkIndex;

    const auto LatticeKey = Make_CrossingKey(Lattice);
    const auto LinkedKey = Make_CrossingKey(Linked);

    TestTrue(TEXT("two crossings alike in everything but which link they are key apart"),
        NOT (LatticeKey == LinkedKey));

    TestTrue(TEXT("and hash apart, so the pool cannot fold one onto the other"),
        GetTypeHash(LatticeKey) != GetTypeHash(LinkedKey));

    // The constructible form of the same collision: two links leaving ONE authored point for ONE plate.
    // Their crossings agree in every field a key is made of except the link index, so if that were not
    // in the key the cheaper of the two would never be minted a node of its own.
    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the open floor bakes with two links leaving one point for one plate"),
        Bake_OpenFloor({
            Make_LinkRecord(1, kSeamLinkEntry, kSeamLinkExit, 1.0f),
            Make_LinkRecord(2, kSeamLinkEntry, kSeamLinkSecondExit, 1.0f)}, Field)))
    { return false; }

    if (NOT TestEqual(TEXT("and carries both entries"), Field->Get_ResolvedLinkCount(), 2))
    { return false; }

    const auto First = Field->_ResolvedLinks[0];
    const auto Second = Field->_ResolvedLinks[1];

    if (NOT TestTrue(TEXT("both resolved onto the same pair of plates"),
        First.Get_IsTraversable() && Second.Get_IsTraversable() &&
        First._StartFlatPlate == Second._StartFlatPlate &&
        First._EndFlatPlate == Second._EndFlatPlate &&
        First._StartFlatPlate != First._EndFlatPlate))
    { return false; }

    const auto Graph = FCk_GroundNav_PlatePortalGraph{
        Make_SharedData(Field, First._EndFlatPlate, First._Start, First._End),
        First._StartFlatPlate};

    auto Nodes = TArray<int32>{};
    auto LinkIndices = TArray<int32>{};

    for (const auto Node : Graph.Neighbors(kPathSourceNode))
    {
        const auto& Crossing = Graph.Get_Crossing(Node);

        if (Crossing._LinkIndex == INDEX_NONE)
        { continue; }

        Nodes.AddUnique(Node);
        LinkIndices.AddUnique(Crossing._LinkIndex);
    }

    TestEqual(TEXT("the two links are two nodes of the search"), Nodes.Num(), 2);

    TestTrue(TEXT("one per authored record"),
        LinkIndices.Contains(kFirstLinkIndex) && LinkIndices.Contains(kSecondLinkIndex));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
