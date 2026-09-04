// What a finished plan says about the authored links it walks, and what the two queries make of it.
//
// The metadata is ADDITIVE and nothing else: the locations a consumer has always read are the same
// locations, element for element, and the stamp only fills in fields that did not exist before. That is
// the first claim here, and it is measured by running the three passes the plan is made of by hand and
// comparing what they produced against what the plan carries.
//
// The stamp itself is checked against the geometry the link search already pins: a route across one
// link carries exactly one entry and one exit, they stand where the record put them, and they survive
// both passes that run between the funnel and the fill - the corner offset, which must leave a link
// endpoint alone, and the skip-first, which renumbers everything after it.
//
// The two queries are checked against a brute-force walk of the metadata array over a thousand
// generated results. The brute force scans FORWARD from each entry for an exit nothing has claimed;
// the production keeps its open spans and closes the newest. Two different formulations of the same
// pairing, so a bug in either shows up as a disagreement rather than as two matching wrong answers.

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Path/CkGroundNavPath_Fragment_Data.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkGroundNav/Query/CkGroundNav_Funnel.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathlinkmetadata
{
    using ck::groundnav::ECk_GroundNav_LinkWaypointRole;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_PathPlan;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::Get_CornerOffset;
    using ck::groundnav::Get_Funnelled;
    using ck::groundnav::Get_Path;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Get_SkipFirstWaypoint;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;

    // --------------------------------------------------------------------------------------------------

    // The barrier scene the link search states its own claims over, restated here rather than shared:
    // the two suites make different claims about the same geometry, and a fixture header would put a
    // third file between a case and the numbers it reads.
    constexpr auto kBarrierFreeMinX = 100.0;
    constexpr auto kBarrierFreeMaxX = 700.0;
    constexpr auto kBarrierFreeMinY = 100.0;
    constexpr auto kBarrierFreeMaxY = 700.0;

    constexpr auto kBarrierMinX = 350.0;
    constexpr auto kBarrierMaxX = 450.0;
    constexpr auto kBarrierTopY = 500.0;

    const auto kBarrierStart = FVector{200.0, 200.0, kGroundZ};
    const auto kBarrierGoal = FVector{600.0, 200.0, kGroundZ};

    // Off the line between the two ends, so the string BENDS at both of them and each is a waypoint of
    // its own rather than a point the line happens to run through.
    const auto kBentLinkEntry = FVector{300.0, 350.0, kGroundZ};
    const auto kBentLinkExit = FVector{500.0, 350.0, kGroundZ};

    // A body of no size, for the cases that want the funnel's own points and nothing inset.
    constexpr auto kNoRadius = 0.0f;

    // A body that the skip-first and the corner offset both have something to do for.
    constexpr auto kAgentRadiusUu = 10.0f;

    // Twice the radius, so the corner pass is asked for a real offset rather than switched off.
    constexpr auto kCornerOffsetK = 2.0f;
    constexpr auto kNoCornerOffsetK = 0.0f;

    // Far enough that no skip-first threshold reaches it, so every waypoint the passes made is kept.
    const auto kDistantAgentLocation = FVector{-5000.0, -5000.0, kGroundZ};

    constexpr auto kLinkId = 7;
    constexpr auto kReversedLinkId = 9;

    constexpr auto kOneEntryAndOneExit = 2;
    constexpr auto kNone = 0;
    constexpr auto kOneWaypointDropped = 1;

    constexpr auto kFewestPointsWithAnInterior = 3;

    // Enough draws that a pairing bug that needs two links on one route, a repeated id, or a route that
    // stops on a link is met many times over rather than depended on to appear.
    constexpr auto kGeneratedResults = 1000;

    constexpr auto kLinksOnPathSeed = 20260904;
    constexpr auto kNextLinkBeyondSeed = 40260904;

    // Small enough that ids repeat across the links of one generated route, which is what makes the
    // pairing answer something rather than fall out of the ids being distinct.
    constexpr auto kGeneratedIdPoolSize = 3;

    constexpr auto kMostLinksOnAGeneratedRoute = 4;

    // A route that stops ON a link is a quarter of the draws: rare enough to be a case and common
    // enough that a thousand results carry hundreds of them.
    constexpr auto kOpenEndedDrawChance = 0.25f;

    // --------------------------------------------------------------------------------------------------

    /** A barrier across the free space with the only way past it at the far end. */
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

    auto Make_LinkRecord(
        int32          InId,
        const FVector& InStart,
        const FVector& InEnd) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};

        Record.Set_CostMultiplierForward(1.0f);
        Record.Set_CostMultiplierBackward(1.0f);

        return Record;
    }

    /** The scene held the way a search takes one: by shared pointer, so nothing can take it away. */
    auto Bake_Barrier(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_FieldPtr&                 OutField) -> bool
    {
        auto Params = Make_FlatParams();
        Params._Links = InLinks;

        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_BarrierScene(), Params, *Baked))
        { return false; }

        OutField = Baked;

        return true;
    }

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Make_BarrierQuery(
        float InRadiusUu) -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = kBarrierStart;
        Query._Goal = kBarrierGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(InRadiusUu);

        return Query;
    }

    auto Make_PostParams(
        float          InRadiusUu,
        float          InCornerOffsetK,
        const FVector& InAgentLocation) -> FCk_GroundNav_PathPostParams
    {
        auto Params = FCk_GroundNav_PathPostParams{};

        Params._Agent = Make_Agent(InRadiusUu);
        Params._VerticalToleranceUu = kStepHeight;
        Params._AgentLocation = InAgentLocation;
        Params._Cost._CornerOffsetK = InCornerOffsetK;

        return Params;
    }

    // --------------------------------------------------------------------------------------------------

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

    /**
     * The three passes that stand between a corridor and a filled waypoint, run by hand.
     *
     * This is the production as it was BEFORE the stamp existed: funnel, corner offset, skip-first.
     * What the plan carries as locations has to be this, element for element, or the stamp moved a
     * waypoint.
     */
    auto Get_StagedLocations(
        const FCk_GroundNav_PathResult& InResult,
        const FCk_GroundNav_Field&      InField,
        float                           InRadiusUu,
        float                           InCornerOffsetK,
        const FVector&                  InAgentLocation) -> TArray<FVector>
    {
        auto Funnelled = TArray<FVector>{};
        Get_Funnelled(InResult, InRadiusUu, Funnelled);

        const auto Offset = Get_CornerOffset(
            Funnelled,
            Get_PinnedWaypoints(InResult),
            InField,
            InCornerOffsetK * InRadiusUu,
            Make_Agent(InRadiusUu),
            kStepHeight);

        return Get_SkipFirstWaypoint(Offset, InAgentLocation, InRadiusUu);
    }

    auto Get_StampedIndices(
        const FCk_GroundNav_PathPlan& InPlan) -> TArray<int32>
    {
        auto Stamped = TArray<int32>{};

        for (auto Index = 0; Index < InPlan._Waypoints.Num(); ++Index)
        {
            if (InPlan._Waypoints[Index]._LinkRole != ECk_GroundNav_LinkWaypointRole::None)
            { Stamped.Emplace(Index); }
        }

        return Stamped;
    }

    /** A plan over the barrier, with whatever links the field was baked with. */
    auto Get_PlanAcrossTheLink(
        const FCk_GroundNav_FieldPtr& InField,
        float                         InRadiusUu,
        float                         InCornerOffsetK,
        const FVector&                InAgentLocation,
        FCk_GroundNav_PathResult&     OutResult) -> FCk_GroundNav_PathPlan
    {
        OutResult = Get_Path(InField, Make_BarrierQuery(InRadiusUu));

        return Get_PathPlan(
            OutResult, *InField, Make_PostParams(InRadiusUu, InCornerOffsetK, InAgentLocation));
    }

    // --------------------------------------------------------------------------------------------------

    auto Make_LinkWaypoint(
        int32                              InWaypointIndex,
        int32                              InLinkId,
        ECk_GroundNavPath_LinkWaypointRole InRole,
        ECk_GroundNav_LinkDirection        InDirection,
        float                              InDistanceUu) -> FCk_GroundNavPath_LinkWaypoint
    {
        return FCk_GroundNavPath_LinkWaypoint{
            InWaypointIndex, InLinkId, InRole, InDirection, InDistanceUu};
    }

    /**
     * A published result carrying nothing but link metadata.
     *
     * The queries read the metadata array and never the locations, so a generated case states the
     * array directly rather than baking a field to produce one.
     *
     * The links are laid out as NON-OVERLAPPING segments in walk order, which is the only shape the
     * stamp can produce: it marks the first waypoint of a link entry and the next one exit, so a second
     * entry of the same link before its exit is unreachable. The last one is left open a quarter of the
     * time, which is the partial route that stopped on a link.
     */
    auto Make_GeneratedResult(
        FRandomStream& InStream) -> FCk_GroundNavPath_Result
    {
        const auto LinkCount = InStream.RandRange(0, kMostLinksOnAGeneratedRoute);
        const auto IsOpenEnded = InStream.GetFraction() < kOpenEndedDrawChance;

        auto Metadata = TArray<FCk_GroundNavPath_LinkWaypoint>{};

        auto WaypointIndex = InStream.RandRange(0, 3);
        auto DistanceUu = InStream.GetFraction() * 100.0f;

        for (auto Link = 0; Link < LinkCount; ++Link)
        {
            const auto LinkId = InStream.RandRange(1, kGeneratedIdPoolSize);

            const auto Direction = InStream.GetFraction() < 0.5f
                ? ECk_GroundNav_LinkDirection::Forward
                : ECk_GroundNav_LinkDirection::Backward;

            Metadata.Emplace(Make_LinkWaypoint(
                WaypointIndex, LinkId, ECk_GroundNavPath_LinkWaypointRole::Entry, Direction, DistanceUu));

            WaypointIndex += 1 + InStream.RandRange(0, 2);
            DistanceUu += 1.0f + (InStream.GetFraction() * 500.0f);

            const auto IsLastAndOpen = IsOpenEnded && Link == LinkCount - 1;

            if (NOT IsLastAndOpen)
            {
                Metadata.Emplace(Make_LinkWaypoint(
                    WaypointIndex, LinkId, ECk_GroundNavPath_LinkWaypointRole::Exit, Direction, DistanceUu));
            }

            WaypointIndex += 1 + InStream.RandRange(0, 3);
            DistanceUu += 1.0f + (InStream.GetFraction() * 500.0f);
        }

        auto Result = FCk_GroundNavPath_Result{};
        Result.Set_LinkWaypoints(Metadata);

        return Result;
    }

    /**
     * The pairing done the other way round: from each entry, scan FORWARD for the first exit of the
     * same link that no earlier entry has already claimed.
     *
     * Deliberately not the production's shape, which keeps its open spans and closes the newest one.
     */
    auto Get_BruteForceSpans(
        const FCk_GroundNavPath_Result& InResult) -> TArray<FCk_GroundNavPath_LinkSpan>
    {
        const auto& Metadata = InResult.Get_LinkWaypoints();

        auto Spans = TArray<FCk_GroundNavPath_LinkSpan>{};
        auto ClaimedExits = TArray<int32>{};

        for (auto EntryAt = 0; EntryAt < Metadata.Num(); ++EntryAt)
        {
            const auto& Entry = Metadata[EntryAt];

            if (Entry.Get_Role() != ECk_GroundNavPath_LinkWaypointRole::Entry)
            { continue; }

            auto Span = FCk_GroundNavPath_LinkSpan{
                Entry.Get_LinkId(),
                Entry.Get_WaypointIndex(),
                Entry.Get_DistanceFromStartUu(),
                Entry.Get_EntryDirection()};

            for (auto ExitAt = EntryAt + 1; ExitAt < Metadata.Num(); ++ExitAt)
            {
                const auto& Exit = Metadata[ExitAt];

                if (Exit.Get_Role() != ECk_GroundNavPath_LinkWaypointRole::Exit ||
                    Exit.Get_LinkId() != Entry.Get_LinkId() ||
                    ClaimedExits.Contains(ExitAt))
                { continue; }

                Span.Set_ExitWaypointIndex(Exit.Get_WaypointIndex());
                Span.Set_ExitDistanceUu(Exit.Get_DistanceFromStartUu());

                ClaimedExits.Emplace(ExitAt);

                break;
            }

            Spans.Emplace(Span);
        }

        return Spans;
    }

    auto Get_IsSameSpan(
        const FCk_GroundNavPath_LinkSpan& InLeft,
        const FCk_GroundNavPath_LinkSpan& InRight) -> bool
    {
        return InLeft.Get_LinkId() == InRight.Get_LinkId() &&
               InLeft.Get_EntryWaypointIndex() == InRight.Get_EntryWaypointIndex() &&
               InLeft.Get_ExitWaypointIndex() == InRight.Get_ExitWaypointIndex() &&
               InLeft.Get_EntryDistanceUu() == InRight.Get_EntryDistanceUu() &&
               InLeft.Get_ExitDistanceUu() == InRight.Get_ExitDistanceUu() &&
               InLeft.Get_EntryDirection() == InRight.Get_EntryDirection();
    }

    /** The first entry past a distance, read off the metadata array rather than off the spans. */
    auto Get_BruteForceNextEntryIndex(
        const FCk_GroundNavPath_Result& InResult,
        float                           InDistanceUu) -> int32
    {
        const auto& Metadata = InResult.Get_LinkWaypoints();

        for (auto Index = 0; Index < Metadata.Num(); ++Index)
        {
            if (Metadata[Index].Get_Role() != ECk_GroundNavPath_LinkWaypointRole::Entry)
            { continue; }

            if (Metadata[Index].Get_DistanceFromStartUu() > InDistanceUu)
            { return Metadata[Index].Get_WaypointIndex(); }
        }

        return INDEX_NONE;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_PlanCarriesExactlyOneEntryExitPairAcrossALink,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.PlanCarriesExactlyOneEntryExitPairAcrossALink",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_PlanCarriesExactlyOneEntryExitPairAcrossALink::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with one link across it"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kBentLinkEntry, kBentLinkExit)}, Field)))
    { return false; }

    auto Result = FCk_GroundNav_PathResult{};

    const auto Plan = Get_PlanAcrossTheLink(
        Field, kNoRadius, kNoCornerOffsetK, kDistantAgentLocation, Result);

    if (NOT TestTrue(TEXT("and the search takes it"),
        Plan._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto Stamped = Get_StampedIndices(Plan);

    if (NOT TestEqual(TEXT("the plan carries exactly one pair of link waypoints"),
        Stamped.Num(), kOneEntryAndOneExit))
    { return false; }

    TestTrue(TEXT("and they are consecutive, as the two ends of one traversal are"),
        Stamped[1] == Stamped[0] + 1);

    const auto& Entry = Plan._Waypoints[Stamped[0]];
    const auto& Exit = Plan._Waypoints[Stamped[1]];

    TestTrue(TEXT("the first is the entry and the second the exit"),
        Entry._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry &&
        Exit._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit);

    TestTrue(TEXT("both name the AUTHORED id and not the field's index"),
        Entry._LinkId == kLinkId && Exit._LinkId == kLinkId);

    TestTrue(TEXT("and both stand exactly where the record put them"),
        Entry._Location == kBentLinkEntry && Exit._Location == kBentLinkExit);

    TestTrue(TEXT("the direction is Forward, entered at the record's start, and the exit says so too"),
        Entry._LinkEntryDirection == ECk_GroundNav_LinkDirection::Forward &&
        Exit._LinkEntryDirection == ECk_GroundNav_LinkDirection::Forward);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_PlanWithNoLinkCarriesNoMetadata,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.PlanWithNoLinkCarriesNoMetadata",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_PlanWithNoLinkCarriesNoMetadata::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the same scene bakes with no link at all"), Bake_Barrier({}, Field)))
    { return false; }

    auto Result = FCk_GroundNav_PathResult{};

    const auto Plan = Get_PlanAcrossTheLink(
        Field, kNoRadius, kNoCornerOffsetK, kDistantAgentLocation, Result);

    if (NOT TestTrue(TEXT("and the route round the barrier is found"),
        Plan._Status == ECk_GroundNav_PathStatus::Ready && NOT Plan._Waypoints.IsEmpty()))
    { return false; }

    TestEqual(TEXT("no waypoint of it is stamped"), Get_StampedIndices(Plan).Num(), kNone);

    auto NamesNoLink = true;

    for (const auto& Waypoint : Plan._Waypoints)
    {
        NamesNoLink = NamesNoLink && Waypoint._LinkId == INDEX_NONE;
    }

    TestTrue(TEXT("and none of them names a link"), NamesNoLink);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_WaypointsAreByteIdenticalWithAndWithoutMetadata,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.WaypointsAreByteIdenticalWithAndWithoutMetadata",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_WaypointsAreByteIdenticalWithAndWithoutMetadata::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with one link across it"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kBentLinkEntry, kBentLinkExit)}, Field)))
    { return false; }

    auto Result = FCk_GroundNav_PathResult{};

    const auto Plan = Get_PlanAcrossTheLink(
        Field, kAgentRadiusUu, kCornerOffsetK, kDistantAgentLocation, Result);

    if (NOT TestTrue(TEXT("and the search takes it"),
        Plan._Status == ECk_GroundNav_PathStatus::Ready && NOT Plan._Waypoints.IsEmpty()))
    { return false; }

    // The passes the plan is made of, run by hand: this is the array the production produced before
    // any of the stamping existed.
    const auto Staged = Get_StagedLocations(
        Result, *Field, kAgentRadiusUu, kCornerOffsetK, kDistantAgentLocation);

    if (NOT TestEqual(TEXT("the plan has one waypoint per point the three passes produced"),
        Plan._Waypoints.Num(), Staged.Num()))
    { return false; }

    auto Locations = TArray<FVector>{};
    Locations.Reserve(Plan._Waypoints.Num());

    for (const auto& Waypoint : Plan._Waypoints)
    { Locations.Emplace(Waypoint._Location); }

    auto MatchesTheStages = true;

    for (auto Index = 0; Index < Locations.Num(); ++Index)
    {
        MatchesTheStages = MatchesTheStages && Locations[Index] == Staged[Index];
    }

    TestTrue(TEXT("and every one of them is EXACTLY the point that pass emitted"), MatchesTheStages);

    // The same array read off waypoints the stamp never touched, which is what a consumer that only
    // ever reads locations gets.
    auto Stripped = Plan._Waypoints;

    for (auto& Waypoint : Stripped)
    {
        Waypoint._LinkId = INDEX_NONE;
        Waypoint._LinkRole = ECk_GroundNav_LinkWaypointRole::None;
        Waypoint._LinkEntryDirection = ECk_GroundNav_LinkDirection::Bidirectional;
    }

    auto StrippedLocations = TArray<FVector>{};
    StrippedLocations.Reserve(Stripped.Num());

    for (const auto& Waypoint : Stripped)
    { StrippedLocations.Emplace(Waypoint._Location); }

    TestTrue(TEXT("so stripping the stamps changes no location"), StrippedLocations == Locations);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_MetadataSurvivesSkipFirstAndCornerOffset,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.MetadataSurvivesSkipFirstAndCornerOffset",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_MetadataSurvivesSkipFirstAndCornerOffset::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the barrier scene bakes with one link across it"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kBentLinkEntry, kBentLinkExit)}, Field)))
    { return false; }

    auto Result = FCk_GroundNav_PathResult{};

    const auto Kept = Get_PlanAcrossTheLink(
        Field, kAgentRadiusUu, kCornerOffsetK, kDistantAgentLocation, Result);

    // Three points is what the corner pass needs before it has an interior to work on at all, so this
    // is what makes the case a statement about that pass and not about a line it skipped.
    if (NOT TestTrue(TEXT("the search takes the link, and the corner pass has an interior to run over"),
        Kept._Status == ECk_GroundNav_PathStatus::Ready &&
        Kept._Waypoints.Num() >= kFewestPointsWithAnInterior))
    { return false; }

    // Standing exactly on the first point the funnel emitted, which is what makes the skip-first fire.
    auto Funnelled = TArray<FVector>{};
    Get_Funnelled(Result, kAgentRadiusUu, Funnelled);

    if (NOT TestTrue(TEXT("the funnel gave a first point to stand on"), NOT Funnelled.IsEmpty()))
    { return false; }

    const auto Plan = Get_PathPlan(
        Result, *Field, Make_PostParams(kAgentRadiusUu, kCornerOffsetK, Funnelled[0]));

    if (NOT TestEqual(TEXT("the skip-first drops exactly one waypoint"),
        Plan._Waypoints.Num(), Kept._Waypoints.Num() - kOneWaypointDropped))
    { return false; }

    const auto Stamped = Get_StampedIndices(Plan);

    if (NOT TestEqual(TEXT("the pair is still there after both passes"),
        Stamped.Num(), kOneEntryAndOneExit))
    { return false; }

    const auto& Entry = Plan._Waypoints[Stamped[0]];
    const auto& Exit = Plan._Waypoints[Stamped[1]];

    TestTrue(TEXT("the indices still point at the two ends the record authored"),
        Entry._Location == kBentLinkEntry && Exit._Location == kBentLinkExit);

    TestTrue(TEXT("with the entry first and the exit next"),
        Entry._LinkRole == ECk_GroundNav_LinkWaypointRole::Entry &&
        Exit._LinkRole == ECk_GroundNav_LinkWaypointRole::Exit &&
        Stamped[1] == Stamped[0] + 1);

    const auto KeptStamped = Get_StampedIndices(Kept);

    if (NOT TestEqual(TEXT("the same pair was there before the skip"),
        KeptStamped.Num(), kOneEntryAndOneExit))
    { return true; }

    TestTrue(TEXT("and every index moved down by the one waypoint that was dropped"),
        Stamped[0] == KeptStamped[0] - kOneWaypointDropped &&
        Stamped[1] == KeptStamped[1] - kOneWaypointDropped);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_EntryDirectionIsBackwardWhenEnteredAtTheEnd,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.EntryDirectionIsBackwardWhenEnteredAtTheEnd",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_EntryDirectionIsBackwardWhenEnteredAtTheEnd::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Field = FCk_GroundNav_FieldPtr{};

    // The SAME two points, authored the other way round: the route still meets the x = 300 end first,
    // and that end is now the record's _End.
    if (NOT TestTrue(TEXT("the scene bakes with the link authored from its far end back"),
        Bake_Barrier({Make_LinkRecord(kReversedLinkId, kBentLinkExit, kBentLinkEntry)}, Field)))
    { return false; }

    auto Result = FCk_GroundNav_PathResult{};

    const auto Plan = Get_PlanAcrossTheLink(
        Field, kNoRadius, kNoCornerOffsetK, kDistantAgentLocation, Result);

    if (NOT TestTrue(TEXT("and the search takes it"),
        Plan._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto Stamped = Get_StampedIndices(Plan);

    if (NOT TestEqual(TEXT("the plan carries the one pair"), Stamped.Num(), kOneEntryAndOneExit))
    { return false; }

    const auto& Entry = Plan._Waypoints[Stamped[0]];
    const auto& Exit = Plan._Waypoints[Stamped[1]];

    TestTrue(TEXT("the route meets the record's _End first"), Entry._Location == kBentLinkEntry);

    TestTrue(TEXT("so the direction is Backward"),
        Entry._LinkEntryDirection == ECk_GroundNav_LinkDirection::Backward);

    TestTrue(TEXT("and the exit answers what its entry did"),
        Exit._LinkEntryDirection == ECk_GroundNav_LinkDirection::Backward);

    TestTrue(TEXT("both still naming the authored id"),
        Entry._LinkId == kReversedLinkId && Exit._LinkId == kReversedLinkId);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_LinksOnPathAgreesWithABruteForceWalk,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.LinksOnPathAgreesWithABruteForceWalk",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_LinksOnPathAgreesWithABruteForceWalk::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Stream = FRandomStream{kLinksOnPathSeed};

    auto Disagreements = 0;
    auto FirstDisagreement = FString{};
    auto SpansSeen = 0;
    auto OpenSpansSeen = 0;

    for (auto Draw = 0; Draw < kGeneratedResults; ++Draw)
    {
        const auto Result = Make_GeneratedResult(Stream);

        const auto Spans = ck::groundnav::Get_LinksOnPath(Result);
        const auto Expected = Get_BruteForceSpans(Result);

        SpansSeen += Spans.Num();

        for (const auto& Span : Spans)
        {
            if (Span.Get_ExitWaypointIndex() == INDEX_NONE)
            { ++OpenSpansSeen; }
        }

        auto Agrees = Spans.Num() == Expected.Num();

        for (auto Index = 0; Agrees && Index < Spans.Num(); ++Index)
        {
            Agrees = Get_IsSameSpan(Spans[Index], Expected[Index]);
        }

        if (Agrees)
        { continue; }

        ++Disagreements;

        if (FirstDisagreement.IsEmpty())
        {
            FirstDisagreement = FString::Printf(
                TEXT("draw %d: %d spans against %d"), Draw, Spans.Num(), Expected.Num());
        }
    }

    TestEqual(FString::Printf(TEXT("every generated route pairs the same way [%s]"), *FirstDisagreement),
        Disagreements, kNone);

    TestTrue(TEXT("and the thousand draws carried spans to disagree about"), SpansSeen > 0);

    TestTrue(TEXT("including routes that stop on a link"), OpenSpansSeen > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_NextLinkBeyondAgreesWithABruteForceWalk,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.NextLinkBeyondAgreesWithABruteForceWalk",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_NextLinkBeyondAgreesWithABruteForceWalk::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    auto Stream = FRandomStream{kNextLinkBeyondSeed};

    auto Disagreements = 0;
    auto FirstDisagreement = FString{};
    auto AnswersSeen = 0;
    auto EmptyAnswersSeen = 0;

    for (auto Draw = 0; Draw < kGeneratedResults; ++Draw)
    {
        const auto Result = Make_GeneratedResult(Stream);
        const auto Expected = Get_BruteForceSpans(Result);

        // Asked from before the route, from a point on it, and from past its end, so both the answer
        // and the absence of one are drawn many times.
        const auto QueryDistancesUu = TArray<float>{
            -1.0f,
            0.0f,
            Stream.GetFraction() * 500.0f,
            Stream.GetFraction() * 2000.0f,
            10000.0f};

        for (const auto DistanceUu : QueryDistancesUu)
        {
            const auto Answer = ck::groundnav::TryGet_NextLinkBeyond(Result, DistanceUu);

            const auto ExpectedEntryIndex = Get_BruteForceNextEntryIndex(Result, DistanceUu);

            if (Answer.Get_LinkId() == INDEX_NONE)
            { ++EmptyAnswersSeen; }
            else
            { ++AnswersSeen; }

            auto Agrees = ExpectedEntryIndex == INDEX_NONE
                ? Answer.Get_LinkId() == INDEX_NONE
                : Answer.Get_EntryWaypointIndex() == ExpectedEntryIndex;

            if (Agrees && ExpectedEntryIndex != INDEX_NONE)
            {
                const auto* ExpectedSpan = Expected.FindByPredicate(
                    [ExpectedEntryIndex](const FCk_GroundNavPath_LinkSpan& InSpan)
                    { return InSpan.Get_EntryWaypointIndex() == ExpectedEntryIndex; });

                Agrees = ExpectedSpan != nullptr && Get_IsSameSpan(Answer, *ExpectedSpan);
            }

            if (Agrees)
            { continue; }

            ++Disagreements;

            if (FirstDisagreement.IsEmpty())
            {
                FirstDisagreement = FString::Printf(
                    TEXT("draw %d at %.3fuu: entry %d against %d"),
                    Draw, DistanceUu, Answer.Get_EntryWaypointIndex(), ExpectedEntryIndex);
            }
        }
    }

    TestEqual(FString::Printf(TEXT("every ask answers the same way [%s]"), *FirstDisagreement),
        Disagreements, kNone);

    TestTrue(TEXT("and the draws found links to answer with"), AnswersSeen > 0);

    TestTrue(TEXT("as well as routes with none left"), EmptyAnswersSeen > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathLinkMetadata_PartialPathEndingOnALinkYieldsAnOpenSpan,
    "CkTests.UnitTests.CkGroundNav.PathLinkMetadata.PartialPathEndingOnALinkYieldsAnOpenSpan",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathLinkMetadata_PartialPathEndingOnALinkYieldsAnOpenSpan::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathlinkmetadata;

    constexpr auto ClosedLinkId = 4;
    constexpr auto OpenLinkId = 5;

    constexpr auto ClosedEntryIndex = 2;
    constexpr auto ClosedExitIndex = 3;
    constexpr auto OpenEntryIndex = 6;

    constexpr auto ClosedEntryUu = 40.0f;
    constexpr auto ClosedExitUu = 90.0f;
    constexpr auto OpenEntryUu = 260.0f;

    constexpr auto TwoSpans = 2;

    auto Metadata = TArray<FCk_GroundNavPath_LinkWaypoint>{};

    Metadata.Emplace(Make_LinkWaypoint(
        ClosedEntryIndex, ClosedLinkId, ECk_GroundNavPath_LinkWaypointRole::Entry,
        ECk_GroundNav_LinkDirection::Forward, ClosedEntryUu));

    Metadata.Emplace(Make_LinkWaypoint(
        ClosedExitIndex, ClosedLinkId, ECk_GroundNavPath_LinkWaypointRole::Exit,
        ECk_GroundNav_LinkDirection::Forward, ClosedExitUu));

    // The route stops here: an entry with nothing after it, which is what a partial plan that reached
    // the far node and no further produces.
    Metadata.Emplace(Make_LinkWaypoint(
        OpenEntryIndex, OpenLinkId, ECk_GroundNavPath_LinkWaypointRole::Entry,
        ECk_GroundNav_LinkDirection::Backward, OpenEntryUu));

    auto Result = FCk_GroundNavPath_Result{};
    Result.Set_LinkWaypoints(Metadata);

    const auto Spans = ck::groundnav::Get_LinksOnPath(Result);

    if (NOT TestEqual(TEXT("the open entry is a span of its own and not a dropped one"),
        Spans.Num(), TwoSpans))
    { return false; }

    TestTrue(TEXT("the first is closed"),
        Spans[0].Get_LinkId() == ClosedLinkId &&
        Spans[0].Get_EntryWaypointIndex() == ClosedEntryIndex &&
        Spans[0].Get_ExitWaypointIndex() == ClosedExitIndex &&
        Spans[0].Get_ExitDistanceUu() == ClosedExitUu);

    TestTrue(TEXT("and the second is open, with no exit waypoint to point at"),
        Spans[1].Get_LinkId() == OpenLinkId &&
        Spans[1].Get_EntryWaypointIndex() == OpenEntryIndex &&
        Spans[1].Get_ExitWaypointIndex() == INDEX_NONE);

    TestTrue(TEXT("carrying the direction it was entered in"),
        Spans[1].Get_EntryDirection() == ECk_GroundNav_LinkDirection::Backward);

    const auto Next = ck::groundnav::TryGet_NextLinkBeyond(Result, ClosedExitUu);

    TestTrue(TEXT("and the next-link query answers with it"),
        Next.Get_LinkId() == OpenLinkId && Next.Get_ExitWaypointIndex() == INDEX_NONE);

    const auto None = ck::groundnav::TryGet_NextLinkBeyond(Result, OpenEntryUu);

    TestTrue(TEXT("while an ask past it names no link"), None.Get_LinkId() == INDEX_NONE);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
