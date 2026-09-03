// What a repair is allowed to keep of a corridor it was handed, and what it must pay to keep it.
//
// A repair makes exactly three claims and each is measured against something that is not the repair.
// A corridor re-offered against the epoch it was planned for must cost NOTHING — zero expansions and
// the same doors back — because an epoch names one immutable snapshot and re-finding a route that
// cannot have moved is work nobody should pay twice. A corridor whose door at step k is gone must
// keep the k steps before it, which is measured against a COLD search over the same rebuilt field
// rather than against a number written down here. And a corridor that does not survive its first step
// must be a cold search under another name, which is measured by asking for its expansion count and
// requiring the cold search's own.
//
// The doors are sealed by REBUILDING the scene with a wall across the interval the corridor crossed,
// because a door that is merely renamed is not the failure this exists for. Sealing a door near
// either end of the route can wall that end off instead, which would be a broken fixture rather than
// a broken repair, so a seal is only measured once the rebuilt field still answers the same query
// cold.
//
// The doorway scene is rebuilt here rather than shared: its builder lives inside another test's
// file-private namespace and never reached the fixtures header. The boxes are copied verbatim and
// must be kept so.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_QueryTypes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_PlatePortalGraph.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_repair
{
    using ck::groundnav::ECk_GroundNav_RepairVerdict;
    using ck::groundnav::FCk_GroundNav_Crossing;
    using ck::groundnav::FCk_GroundNav_CrossingKey;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_PathNodeId;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSharedData;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::FCk_GroundNav_PlatePortalGraph;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_Path;
    using ck::groundnav::kPathSourceNode;
    using ck::groundnav::Make_CrossingKey;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;
    using ck_test_groundnav_queryfixtures::Make_TwoRouteScene;

    // A body of no size, so every door the geometry offers is admitted and which doors a corridor
    // holds is the route's decision rather than the clearance filter's.
    constexpr auto kNoRadius = 0.0f;

    // Far past what any of these scenes needs, so a run that stops on it is a search that did not
    // terminate rather than a scene that is merely large.
    constexpr auto kMaxSlices = 20000;

    // The finest grain there is, so a sliced repair differs from an unsliced one at every boundary
    // rather than at some of them.
    constexpr auto kOneExpansionPerSlice = 1;

    // The two builds. They are stamped explicitly because the fixture bakes every field at epoch one,
    // and a repair whose two epochs compare equal takes the branch that answers without validating.
    constexpr auto kBuiltEpoch = int64{11};
    constexpr auto kRebuiltEpoch = int64{12};

    // Half a cell either side of the interval, so the cells on both sides of the crossing are covered
    // and the door is gone rather than narrowed.
    constexpr auto kSealMarginUu = 1.5 * static_cast<double>(kCellSize);

    // Tall enough to be a wall rather than a step, matching the scene's own dividers.
    constexpr auto kSealHeightUu = 300.0;

    // Both ends stand in open floor of the west room, well clear of the doorway the route threads, so
    // a seal placed on the route cannot wall an end of it off by accident.
    const auto kRepairStart = FVector{200.0, 500.0, kGroundZ};
    const auto kRepairGoal = FVector{200.0, 1400.0, kGroundZ};

    // Enough doors that a break at step k has steps before it to keep. Below this the corridor cannot
    // express the case at all and the scene, not the repair, is what failed.
    constexpr auto kMinCorridorCrossings = 2;

    // ----------------------------------------------------------------------------------------------------------------

    /** The query scene with a second wall across its west room, pierced by a 60 uu doorway. */
    auto Make_DoorwayScene() -> TArray<FBox>
    {
        auto Boxes = Make_QueryScene();

        Boxes.Emplace(FBox{FVector{0.0, 1000.0, 0.0}, FVector{300.0, 1100.0, 300.0}});
        Boxes.Emplace(FBox{FVector{360.0, 1000.0, 0.0}, FVector{700.0, 1100.0, 300.0}});

        return Boxes;
    }

    /**
     * A baked scene held the way a search takes one, stamped with the build it stands for.
     *
     * The fixture's own bake hardcodes epoch one, so two bakes of two different scenes are
     * indistinguishable to a repair. The stamp here is the rebuild the repair is being asked about.
     */
    auto Bake_Shared(
        const TArray<FBox>&              InBoxes,
        const FCk_GroundNav_FieldParams& InParams,
        int64                            InEpochValue,
        FCk_GroundNav_FieldPtr&          OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(InBoxes, InParams, *Baked))
        { return false; }

        Baked->_Epoch = FCk_GroundNav_Epoch{InEpochValue};

        OutField = Baked;

        return true;
    }

    auto Make_PathQuery(
        const FVector& InStart,
        const FVector& InGoal) -> FCk_GroundNav_PathQuery
    {
        auto Agent = FCk_GroundNav_QueryAgent{};
        Agent._RadiusUu = kNoRadius;

        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Agent;

        return Query;
    }

    /** The flat plate a probe stands on, or INDEX_NONE where the field has no ground under it. */
    auto Get_FlatPlateAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> int32
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStepHeight;

        const auto Result = Get_IsNavigable(InField, Query);

        if (NOT Result.Get_IsSuccess())
        { return INDEX_NONE; }

        return Get_FlatPlateIndex(InField, Result._Surface._TileIndex, Result._Surface._PlateIndex);
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_StatusText(
        ECk_GroundNav_PathStatus InStatus) -> FString
    {
        return ck::Format_UE(TEXT("{}"), InStatus);
    }

    auto Get_VerdictText(
        ECk_GroundNav_RepairVerdict InVerdict) -> FString
    {
        switch (InVerdict)
        {
            case ECk_GroundNav_RepairVerdict::StillValid:
            { return TEXT("StillValid"); }

            case ECk_GroundNav_RepairVerdict::Repaired:
            { return TEXT("Repaired"); }

            case ECk_GroundNav_RepairVerdict::FullReplan:
            { return TEXT("FullReplan"); }

            default:
            { return TEXT("None"); }
        }
    }

    /**
     * The first thing two results disagree about, or nothing.
     *
     * A named disagreement rather than a boolean, because "the sliced repair differed" is not a report
     * anybody can act on and the point of comparing the two is to say WHERE they parted.
     */
    auto Get_Disagreement(
        const FCk_GroundNav_PathResult& InLeft,
        const FCk_GroundNav_PathResult& InRight) -> FString
    {
        if (InLeft._Status != InRight._Status)
        {
            return FString::Printf(TEXT("status %s vs %s"),
                *Get_StatusText(InLeft._Status), *Get_StatusText(InRight._Status));
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
            if (NOT (Make_CrossingKey(InLeft._Crossings[Index]) ==
                     Make_CrossingKey(InRight._Crossings[Index])))
            {
                return FString::Printf(TEXT("crossing %d: %d->%d vs %d->%d"), Index,
                    InLeft._Crossings[Index]._FromFlatPlate, InLeft._Crossings[Index]._ToFlatPlate,
                    InRight._Crossings[Index]._FromFlatPlate, InRight._Crossings[Index]._ToFlatPlate);
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

    // ----------------------------------------------------------------------------------------------------------------

    auto Do_RunToTerminal(
        FCk_GroundNav_PathSearch&            InSearch,
        const FCk_GroundNav_PathSliceParams& InSlice,
        int32&                               OutSliceCount) -> ECk_GroundNav_PathStatus
    {
        OutSliceCount = 0;

        while (NOT InSearch.Get_IsTerminal() && OutSliceCount < kMaxSlices)
        {
            InSearch.ContinueSearch(InSlice);
            ++OutSliceCount;
        }

        return InSearch.Get_Status();
    }

    /** The whole route in one call, with the corridor in the one form that outlives the search. */
    auto Do_PlanRoute(
        const FCk_GroundNav_FieldPtr&      InField,
        const FCk_GroundNav_PathQuery&     InQuery,
        FCk_GroundNav_PathResult&          OutResult,
        TArray<FCk_GroundNav_CrossingKey>& OutKeys) -> ECk_GroundNav_PathStatus
    {
        auto Search = FCk_GroundNav_PathSearch{};

        Search.Request_Begin(InField, InQuery);

        auto SliceCount = 0;
        const auto Status = Do_RunToTerminal(Search, FCk_GroundNav_PathSliceParams{}, SliceCount);

        OutResult = Search.Get_Result();
        OutKeys = Search.Get_CorridorKeys();

        return Status;
    }

    /** A wall across the interval one crossing spans, so that door is gone rather than narrowed. */
    auto Make_SealBox(
        const FCk_GroundNav_Crossing& InCrossing) -> FBox
    {
        const auto MinX = FMath::Min(InCrossing._Left.X, InCrossing._Right.X) - kSealMarginUu;
        const auto MaxX = FMath::Max(InCrossing._Left.X, InCrossing._Right.X) + kSealMarginUu;
        const auto MinY = FMath::Min(InCrossing._Left.Y, InCrossing._Right.Y) - kSealMarginUu;
        const auto MaxY = FMath::Max(InCrossing._Left.Y, InCrossing._Right.Y) + kSealMarginUu;

        return FBox{
            FVector{MinX, MinY, kGroundZ},
            FVector{MaxX, MaxY, kGroundZ + kSealHeightUu}};
    }

    /**
     * A key no crossing can ever match: nothing leaves the plate that is not a plate.
     *
     * It stands for a door a rebuild took away, which is what the walk sees either way — a key that
     * resolves to nothing. The geometric half of that claim is pinned by RemovedDoorResolvesToNoNode.
     */
    auto Make_UnresolvableKey() -> FCk_GroundNav_CrossingKey
    {
        return FCk_GroundNav_CrossingKey{};
    }

    auto Get_MaxNodeId(
        TConstArrayView<FCk_GroundNav_PathNodeId> InNodes) -> FCk_GroundNav_PathNodeId
    {
        auto Highest = kPathSourceNode;

        for (const auto Node : InNodes)
        { Highest = FMath::Max(Highest, Node); }

        return Highest;
    }

    /** The seed a graph reads, built exactly the way the search's own pre-search builds it. */
    auto Make_SharedData(
        const FCk_GroundNav_FieldPtr&  InField,
        const FCk_GroundNav_PathQuery& InQuery,
        int32                          InGoalFlatPlate) -> TSharedPtr<const FCk_GroundNav_PathSharedData>
    {
        auto Shared = MakeShared<FCk_GroundNav_PathSharedData>();

        Shared->_Field = InField;
        Shared->_Epoch = InField->_Epoch;
        Shared->_Agent = InQuery._Agent;
        Shared->_GoalFlatPlate = InGoalFlatPlate;
        Shared->_GoalPoint = InQuery._Goal;
        Shared->_SourcePoint = InQuery._Start;
        Shared->_GreedyWeightW = InQuery._GreedyWeightW;
        Shared->_SlopePenaltyK = InQuery._Cost._SlopePenaltyK;
        Shared->_ClearanceBiasK = InQuery._Cost._ClearanceBiasK;
        Shared->_PlateCostMultipliers = InQuery._Cost._PlateCostMultipliers;
        Shared->_CellSizeUu = InField->_Params._Config.Get_CellSizeUu();

        return Shared;
    }

    /** How far a stored corridor walks back onto a live graph before a key resolves to nothing. */
    auto Do_WalkCorridor(
        const FCk_GroundNav_PlatePortalGraph&      InGraph,
        TConstArrayView<FCk_GroundNav_CrossingKey> InKeys,
        TArray<FCk_GroundNav_PathNodeId>&          OutPrefix) -> int32
    {
        OutPrefix.Reset();
        OutPrefix.Add(kPathSourceNode);

        for (auto Index = 0; Index < InKeys.Num(); ++Index)
        {
            const auto Node = InGraph.TryGet_NodeForKey(OutPrefix.Last(), InKeys[Index]);

            if (Node == INDEX_NONE)
            { return Index; }

            OutPrefix.Add(Node);
        }

        return InKeys.Num();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_SameEpochValidatesWithZeroExpansions,
    "CkTests.UnitTests.CkGroundNav.Repair.SameEpochValidatesWithZeroExpansions",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_SameEpochValidatesWithZeroExpansions::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_repair;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kBuiltEpoch, Field)))
    { return false; }

    const auto Query = Make_PathQuery(kRepairStart, kRepairGoal);

    auto Planned = FCk_GroundNav_PathResult{};
    auto Keys = TArray<FCk_GroundNav_CrossingKey>{};

    const auto PlannedStatus = Do_PlanRoute(Field, Query, Planned, Keys);

    if (NOT TestTrue(FString::Printf(TEXT("the scene answers the query [%s]"),
            *Get_StatusText(PlannedStatus)),
        PlannedStatus == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("and the route holds doors to re-offer [%d]"), Keys.Num()),
        Keys.Num() >= kMinCorridorCrossings))
    { return false; }

    auto Repair = FCk_GroundNav_PathSearch{};

    const auto RepairStatus = Repair.Request_BeginRepair(Field, Query, Keys, Field->_Epoch);

    // The field is the one immutable snapshot the corridor was planned against, so the corridor is
    // the corridor a search would answer with and there is nothing left to find.
    TestTrue(FString::Printf(TEXT("the repair answers before any slice runs [%s]"),
            *Get_StatusText(RepairStatus)),
        RepairStatus == ECk_GroundNav_PathStatus::Ready);

    TestTrue(TEXT("and stands terminal"), Repair.Get_IsTerminal());

    TestTrue(FString::Printf(TEXT("naming the corridor still valid [%s]"),
            *Get_VerdictText(Repair.Get_RepairVerdict())),
        Repair.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::StillValid);

    TestEqual(TEXT("having expanded nothing"), Repair.Get_Result()._ExpansionCount, 0);

    TestTrue(TEXT("and answering with the doors it was handed"), Repair.Get_CorridorKeys() == Keys);

    TestTrue(TEXT("over the same plates"),
        Repair.Get_Result()._PlateCorridor == Planned._PlateCorridor);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_InvalidAtStepKBoundsExpansions,
    "CkTests.UnitTests.CkGroundNav.Repair.InvalidAtStepKBoundsExpansions",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_InvalidAtStepKBoundsExpansions::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_repair;

    // The two-route scene rather than the doorway one. Every route across the doorway scene threads
    // its one 60 uu gap, so sealing any door on that route seals the only route and the query comes
    // back Unreachable, which measures the fixture rather than the repair. Here the two rooms are
    // joined twice, by a door low in the divider and by the way over the divider's top, so a sealed
    // door still leaves a route for the kept prefix to be repaired onto.
    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the two-route scene bakes"),
        Bake_Shared(Make_TwoRouteScene(), Make_QueryParams(), kBuiltEpoch, Field)))
    { return false; }

    const auto Query = Make_PathQuery(kTwoRouteStart, kTwoRouteGoal);

    auto Planned = FCk_GroundNav_PathResult{};
    auto Keys = TArray<FCk_GroundNav_CrossingKey>{};

    const auto PlannedStatus = Do_PlanRoute(Field, Query, Planned, Keys);

    if (NOT TestTrue(FString::Printf(TEXT("the scene answers the query [%s]"),
            *Get_StatusText(PlannedStatus)),
        PlannedStatus == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("and the route holds a door past its first [%d]"), Keys.Num()),
        Keys.Num() >= kMinCorridorCrossings))
    { return false; }

    int32 SealedAt = INDEX_NONE;
    auto ColdOnRebuilt = FCk_GroundNav_PathResult{};
    auto Warm = FCk_GroundNav_PathResult{};
    auto WarmVerdict = ECk_GroundNav_RepairVerdict::None;
    int32 RebuiltGoalPlate = INDEX_NONE;
    auto Rejected = FString{};

    // Later doors first: a seal near the start is likelier to reshape the plates the corridor's early
    // keys name, and a seal on the last door is likelier to wall the goal itself off.
    for (auto Candidate = Keys.Num() - 1; Candidate >= 1 && SealedAt == INDEX_NONE; --Candidate)
    {
        auto Boxes = Make_TwoRouteScene();
        Boxes.Emplace(Make_SealBox(Planned._Crossings[Candidate]));

        auto Rebuilt = FCk_GroundNav_FieldPtr{};

        if (NOT Bake_Shared(Boxes, Make_QueryParams(), kRebuiltEpoch, Rebuilt))
        {
            Rejected += FString::Printf(TEXT(" %d:bake"), Candidate);
            continue;
        }

        const auto Cold = Get_Path(Rebuilt, Query);

        // A seal that took an end of the route with it is a broken fixture, not a broken repair.
        if (Cold._Status != ECk_GroundNav_PathStatus::Ready)
        {
            Rejected += FString::Printf(TEXT(" %d:%s"), Candidate, *Get_StatusText(Cold._Status));
            continue;
        }

        auto Repair = FCk_GroundNav_PathSearch{};
        Repair.Request_BeginRepair(Rebuilt, Query, Keys, Field->_Epoch);

        if (Repair.Get_RepairVerdict() != ECk_GroundNav_RepairVerdict::Repaired)
        {
            Rejected += FString::Printf(TEXT(" %d:%s"),
                Candidate, *Get_VerdictText(Repair.Get_RepairVerdict()));
            continue;
        }

        auto SliceCount = 0;
        Do_RunToTerminal(Repair, FCk_GroundNav_PathSliceParams{}, SliceCount);

        SealedAt = Candidate;
        ColdOnRebuilt = Cold;
        Warm = Repair.Get_Result();
        WarmVerdict = Repair.Get_RepairVerdict();
        RebuiltGoalPlate = Get_FlatPlateAt(*Rebuilt, kTwoRouteGoal);
    }

    if (NOT TestTrue(FString::Printf(
            TEXT("a door past the first can be sealed and repaired around [%d doors, rejected%s]"),
            Keys.Num(), Rejected.IsEmpty() ? TEXT(" none") : *Rejected),
        SealedAt != INDEX_NONE))
    { return false; }

    const auto Report = FString::Printf(
        TEXT("[REPAIR-BUDGET] two-route seal at door %d of %d: warm %d expansions, cold %d, verdict %s, status %s"),
        SealedAt, Keys.Num(), Warm._ExpansionCount, ColdOnRebuilt._ExpansionCount,
        *Get_VerdictText(WarmVerdict), *Get_StatusText(Warm._Status));

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("the repair reaches a route [%s]"), *Report),
        Warm._Status == ECk_GroundNav_PathStatus::Ready);

    // The kept prefix is the whole point: a repair that expands what a cold search expands has
    // repaired nothing and merely paid for the walk that proved it.
    TestTrue(FString::Printf(TEXT("and expands less than the cold search over the same field [%s]"), *Report),
        Warm._ExpansionCount < ColdOnRebuilt._ExpansionCount);

    if (TestTrue(FString::Printf(TEXT("the rebuilt field still has ground under the goal [%s]"), *Report),
        RebuiltGoalPlate != INDEX_NONE))
    {
        TestTrue(FString::Printf(TEXT("and the repaired corridor arrives on the goal plate [%s]"), *Report),
            NOT Warm._PlateCorridor.IsEmpty() && Warm._PlateCorridor.Last() == RebuiltGoalPlate);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_InvalidAtStepZeroIsFullReplan,
    "CkTests.UnitTests.CkGroundNav.Repair.InvalidAtStepZeroIsFullReplan",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_InvalidAtStepZeroIsFullReplan::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_repair;

    auto Field = FCk_GroundNav_FieldPtr{};
    auto Rebuilt = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kBuiltEpoch, Field)))
    { return false; }

    // The same ground under a later build. A rebuild that changed nothing still earns a new epoch, so
    // the corridor is re-canonicalised rather than trusted, which is the branch under test.
    if (NOT TestTrue(TEXT("and bakes again as a later build"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kRebuiltEpoch, Rebuilt)))
    { return false; }

    const auto Query = Make_PathQuery(kRepairStart, kRepairGoal);

    auto Planned = FCk_GroundNav_PathResult{};
    auto Keys = TArray<FCk_GroundNav_CrossingKey>{};

    const auto PlannedStatus = Do_PlanRoute(Field, Query, Planned, Keys);

    if (NOT TestTrue(FString::Printf(TEXT("the scene answers the query [%s]"),
            *Get_StatusText(PlannedStatus)),
        PlannedStatus == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    auto Corridor = TArray<FCk_GroundNav_CrossingKey>{Make_UnresolvableKey()};
    Corridor.Append(Keys);

    auto Repair = FCk_GroundNav_PathSearch{};

    const auto BeginStatus = Repair.Request_BeginRepair(
        Rebuilt, Query, Corridor, FCk_GroundNav_Epoch{kBuiltEpoch});

    // A prefix of the source alone is a cold search under another name, and it is also the one index
    // the warm-start constructor cannot be handed.
    TestTrue(FString::Printf(TEXT("a corridor that loses its first door replans whole [%s]"),
            *Get_VerdictText(Repair.Get_RepairVerdict())),
        Repair.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::FullReplan);

    TestTrue(FString::Printf(TEXT("and stands up a search rather than answering [%s]"),
            *Get_StatusText(BeginStatus)),
        BeginStatus == ECk_GroundNav_PathStatus::InProgress);

    auto SliceCount = 0;
    const auto FinalStatus = Do_RunToTerminal(Repair, FCk_GroundNav_PathSliceParams{}, SliceCount);

    const auto Cold = Get_Path(Rebuilt, Query);

    TestTrue(FString::Printf(TEXT("the replan reaches a route [%s]"), *Get_StatusText(FinalStatus)),
        FinalStatus == ECk_GroundNav_PathStatus::Ready);

    // Cold means cold: the pool was rebuilt, so the replan must expand node for node what a plain
    // begin over the same field expands.
    TestEqual(TEXT("and expands exactly what a cold search over the same field expands"),
        Repair.Get_Result()._ExpansionCount, Cold._ExpansionCount);

    TestEqual(TEXT("answering with the cold search's own route"),
        Get_Disagreement(Repair.Get_Result(), Cold), FString{});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_RemovedDoorResolvesToNoNode,
    "CkTests.UnitTests.CkGroundNav.Repair.RemovedDoorResolvesToNoNode",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_RemovedDoorResolvesToNoNode::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_repair;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kBuiltEpoch, Field)))
    { return false; }

    const auto Query = Make_PathQuery(kRepairStart, kRepairGoal);

    auto Planned = FCk_GroundNav_PathResult{};
    auto Keys = TArray<FCk_GroundNav_CrossingKey>{};

    const auto PlannedStatus = Do_PlanRoute(Field, Query, Planned, Keys);

    if (NOT TestTrue(FString::Printf(TEXT("the scene answers the query [%s]"),
            *Get_StatusText(PlannedStatus)),
        PlannedStatus == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("and the route holds doors to take away [%d]"), Keys.Num()),
        Keys.Num() >= kMinCorridorCrossings))
    { return false; }

    const auto SealedAt = Keys.Num() - 1;

    auto Boxes = Make_DoorwayScene();
    Boxes.Emplace(Make_SealBox(Planned._Crossings[SealedAt]));

    auto Rebuilt = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the sealed scene bakes"),
        Bake_Shared(Boxes, Make_QueryParams(), kRebuiltEpoch, Rebuilt)))
    { return false; }

    // The walk over the field the corridor was planned on, so the mechanism and the keys are known
    // sound before absence is claimed to mean anything.
    const auto BuiltStartPlate = Get_FlatPlateAt(*Field, kRepairStart);
    const auto BuiltGoalPlate = Get_FlatPlateAt(*Field, kRepairGoal);

    if (NOT TestTrue(TEXT("the built field has ground under both ends"),
        BuiltStartPlate != INDEX_NONE && BuiltGoalPlate != INDEX_NONE))
    { return false; }

    const auto BuiltGraph = FCk_GroundNav_PlatePortalGraph{
        Make_SharedData(Field, Query, BuiltGoalPlate), BuiltStartPlate};

    auto BuiltPrefix = TArray<FCk_GroundNav_PathNodeId>{};

    TestEqual(TEXT("the stored corridor walks back whole onto the field it was planned on"),
        Do_WalkCorridor(BuiltGraph, Keys, BuiltPrefix), Keys.Num());

    const auto RebuiltStartPlate = Get_FlatPlateAt(*Rebuilt, kRepairStart);

    if (NOT TestTrue(TEXT("the rebuilt field still has ground under the start"),
        RebuiltStartPlate != INDEX_NONE))
    { return false; }

    const auto RebuiltGraph = FCk_GroundNav_PlatePortalGraph{
        Make_SharedData(Rebuilt, Query, Get_FlatPlateAt(*Rebuilt, kRepairGoal)), RebuiltStartPlate};

    auto RebuiltPrefix = TArray<FCk_GroundNav_PathNodeId>{};

    const auto BrokeAt = Do_WalkCorridor(RebuiltGraph, Keys, RebuiltPrefix);

    const auto Report = FString::Printf(TEXT("sealed door %d of %d, walk broke at %d"),
        SealedAt, Keys.Num(), BrokeAt);

    // Exactly at the sealed door, not merely at or before it: a door is matched on its geometry, so
    // every door the rebuild left alone re-resolves however the plates around it were renumbered,
    // and the one that does not is the one that is gone.
    if (NOT TestTrue(FString::Printf(TEXT("the walk stops at the sealed door and nowhere earlier [%s]"), *Report),
        BrokeAt == SealedAt))
    { return false; }

    const auto BreakNode = RebuiltPrefix.Last();
    const auto& BrokenKey = Keys[BrokeAt];

    // Kept whether or not it is empty. Sealing the only way on turns the plate the walk stopped on
    // into a pocket, and a pocket offering nothing is the seal working rather than a case to skip.
    const auto Before = RebuiltGraph.Neighbors(BreakNode);

    TestEqual(FString::Printf(TEXT("the missing door resolves to nothing [%s]"), *Report),
        RebuiltGraph.TryGet_NodeForKey(BreakNode, BrokenKey), static_cast<FCk_GroundNav_PathNodeId>(INDEX_NONE));

    TestTrue(FString::Printf(TEXT("and the plate still offers exactly the doors it did [%s]"), *Report),
        RebuiltGraph.Neighbors(BreakNode) == Before);

    // The mint claim is measured on a graph nothing has walked, because every plate the walk stood
    // on already had its doors enumerated and a pool that cannot grow proves nothing. Ids are handed
    // out densely in enumeration order, so the FIRST door minted after the failed lookup names
    // whether that lookup quietly took an id of its own.
    const auto MintGraph = FCk_GroundNav_PlatePortalGraph{
        Make_SharedData(Rebuilt, Query, Get_FlatPlateAt(*Rebuilt, kRepairGoal)), RebuiltStartPlate};

    const auto Opened = MintGraph.Neighbors(kPathSourceNode);

    if (NOT TestTrue(FString::Printf(TEXT("the start plate offers doors to mint [%s]"), *Report),
        NOT Opened.IsEmpty()))
    { return false; }

    const auto HighestOpened = Get_MaxNodeId(Opened);

    TestEqual(FString::Printf(TEXT("the missing door resolves to nothing there too [%s]"), *Report),
        MintGraph.TryGet_NodeForKey(kPathSourceNode, BrokenKey), static_cast<FCk_GroundNav_PathNodeId>(INDEX_NONE));

    auto LowestNew = TNumericLimits<FCk_GroundNav_PathNodeId>::Max();

    for (const auto Opener : Opened)
    {
        for (const auto Node : MintGraph.Neighbors(Opener))
        {
            if (Node > HighestOpened)
            { LowestNew = FMath::Min(LowestNew, Node); }
        }

        if (LowestNew != TNumericLimits<FCk_GroundNav_PathNodeId>::Max())
        { break; }
    }

    if (TestTrue(FString::Printf(TEXT("a plate past the start offers a door to mint [%s]"), *Report),
        LowestNew != TNumericLimits<FCk_GroundNav_PathNodeId>::Max()))
    {
        TestEqual(FString::Printf(TEXT("the failed lookup minted no node of its own [%s]"), *Report),
            LowestNew, HighestOpened + 1);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_MovedSourcePlateIsFullReplan,
    "CkTests.UnitTests.CkGroundNav.Repair.MovedSourcePlateIsFullReplan",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_MovedSourcePlateIsFullReplan::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_repair;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kBuiltEpoch, Field)))
    { return false; }

    const auto Query = Make_PathQuery(kRepairStart, kRepairGoal);

    auto Planned = FCk_GroundNav_PathResult{};
    auto Keys = TArray<FCk_GroundNav_CrossingKey>{};

    const auto PlannedStatus = Do_PlanRoute(Field, Query, Planned, Keys);

    if (NOT TestTrue(FString::Printf(TEXT("the scene answers the query [%s]"),
            *Get_StatusText(PlannedStatus)),
        PlannedStatus == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("and the route leaves a plate to move off [%d]"), Keys.Num()),
        Keys.Num() >= 1))
    { return false; }

    const auto LeftPlate = Keys[0]._FromFlatPlate;

    // Points in the same room as the start, sampled until one stands on a different plate and still
    // has a route of its own. A key names the plate it leaves, so from any other plate the corridor's
    // first door cannot be among the ones the graph enumerates.
    const auto Candidates = TArray<FVector>{
        FVector{100.0, 200.0, kGroundZ},
        FVector{600.0, 300.0, kGroundZ},
        FVector{400.0, 700.0, kGroundZ},
        FVector{100.0, 900.0, kGroundZ},
        FVector{650.0, 900.0, kGroundZ},
        FVector{200.0, 150.0, kGroundZ},
        FVector{550.0, 600.0, kGroundZ}};

    auto MovedQuery = FCk_GroundNav_PathQuery{};
    int32 MovedPlate = INDEX_NONE;
    auto Rejected = FString{};

    for (const auto& Candidate : Candidates)
    {
        const auto Plate = Get_FlatPlateAt(*Field, Candidate);

        if (Plate == INDEX_NONE || Plate == LeftPlate)
        {
            Rejected += FString::Printf(TEXT(" (%.0f,%.0f):plate %d"), Candidate.X, Candidate.Y, Plate);
            continue;
        }

        const auto Moved = Make_PathQuery(Candidate, kRepairGoal);
        const auto Cold = Get_Path(Field, Moved);

        if (Cold._Status != ECk_GroundNav_PathStatus::Ready)
        {
            Rejected += FString::Printf(TEXT(" (%.0f,%.0f):%s"),
                Candidate.X, Candidate.Y, *Get_StatusText(Cold._Status));
            continue;
        }

        MovedQuery = Moved;
        MovedPlate = Plate;
        break;
    }

    if (NOT TestTrue(FString::Printf(
            TEXT("the scene offers a second plate to start from [left %d, rejected%s]"),
            LeftPlate, Rejected.IsEmpty() ? TEXT(" none") : *Rejected),
        MovedPlate != INDEX_NONE))
    { return false; }

    auto Repair = FCk_GroundNav_PathSearch{};

    const auto BeginStatus = Repair.Request_BeginRepair(Field, MovedQuery, Keys, Field->_Epoch);

    const auto Report = FString::Printf(TEXT("corridor leaves plate %d, repair starts on plate %d"),
        LeftPlate, MovedPlate);

    TestTrue(FString::Printf(TEXT("a corridor that does not leave the plate the start stands on replans whole [%s]"),
            *Report),
        Repair.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::FullReplan);

    TestTrue(FString::Printf(TEXT("and stands up a search rather than answering [%s]"),
            *Get_StatusText(BeginStatus)),
        BeginStatus == ECk_GroundNav_PathStatus::InProgress);

    auto SliceCount = 0;
    const auto FinalStatus = Do_RunToTerminal(Repair, FCk_GroundNav_PathSliceParams{}, SliceCount);

    TestTrue(FString::Printf(TEXT("the replan reaches a route [%s]"), *Get_StatusText(FinalStatus)),
        FinalStatus == ECk_GroundNav_PathStatus::Ready);

    TestEqual(TEXT("and it is the route a cold search over the same field answers with"),
        Get_Disagreement(Repair.Get_Result(), Get_Path(Field, MovedQuery)), FString{});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_SlicedEqualsOneShot,
    "CkTests.UnitTests.CkGroundNav.Repair.SlicedEqualsOneShot",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_SlicedEqualsOneShot::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_repair;

    auto Field = FCk_GroundNav_FieldPtr{};
    auto Rebuilt = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kBuiltEpoch, Field)))
    { return false; }

    if (NOT TestTrue(TEXT("and bakes again as a later build"),
        Bake_Shared(Make_DoorwayScene(), Make_QueryParams(), kRebuiltEpoch, Rebuilt)))
    { return false; }

    const auto Query = Make_PathQuery(kRepairStart, kRepairGoal);

    auto Planned = FCk_GroundNav_PathResult{};
    auto Keys = TArray<FCk_GroundNav_CrossingKey>{};

    const auto PlannedStatus = Do_PlanRoute(Field, Query, Planned, Keys);

    if (NOT TestTrue(FString::Printf(TEXT("the scene answers the query [%s]"),
            *Get_StatusText(PlannedStatus)),
        PlannedStatus == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("and the route holds doors to keep [%d]"), Keys.Num()),
        Keys.Num() >= kMinCorridorCrossings))
    { return false; }

    // One door kept, the rest of the route left to find, so the warm search has real work in it and a
    // slice boundary has somewhere to fall.
    const auto Kept = TConstArrayView<FCk_GroundNav_CrossingKey>{Keys.GetData(), 1};

    auto OneShot = FCk_GroundNav_PathSearch{};
    OneShot.Request_BeginRepair(Rebuilt, Query, Kept, FCk_GroundNav_Epoch{kBuiltEpoch});

    auto OneShotSlices = 0;
    Do_RunToTerminal(OneShot, FCk_GroundNav_PathSliceParams{}, OneShotSlices);

    auto Iterated = FCk_GroundNav_PathSearch{};
    Iterated.Request_BeginRepair(Rebuilt, Query, Kept, FCk_GroundNav_Epoch{kBuiltEpoch});

    auto FinestSlice = FCk_GroundNav_PathSliceParams{};
    FinestSlice._MaxIterations = kOneExpansionPerSlice;

    auto IteratedSlices = 0;
    Do_RunToTerminal(Iterated, FinestSlice, IteratedSlices);

    const auto Report = FString::Printf(TEXT("one shot in %d slices, iterated in %d, verdicts %s and %s"),
        OneShotSlices, IteratedSlices,
        *Get_VerdictText(OneShot.Get_RepairVerdict()), *Get_VerdictText(Iterated.Get_RepairVerdict()));

    TestTrue(FString::Printf(TEXT("both repairs keep the door they were handed [%s]"), *Report),
        OneShot.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::Repaired &&
        Iterated.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::Repaired);

    TestTrue(FString::Printf(TEXT("and both reach a route [%s]"), *Report),
        OneShot.Get_Status() == ECk_GroundNav_PathStatus::Ready &&
        Iterated.Get_Status() == ECk_GroundNav_PathStatus::Ready);

    // Slicing is only allowed to change where the work stops, and a warm start is no exception.
    TestEqual(FString::Printf(TEXT("the sliced repair answers exactly as the unsliced one [%s]"), *Report),
        Get_Disagreement(OneShot.Get_Result(), Iterated.Get_Result()), FString{});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
