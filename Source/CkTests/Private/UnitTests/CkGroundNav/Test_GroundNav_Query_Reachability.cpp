// What the labels are allowed to claim, and what the flood fill's distances are worth.
//
// Two questions with very different costs and one shared trap. The label comparison expands NOTHING —
// the test asserts the counter, not a timing, because a near-O(1) claim measured with a clock is a
// claim about the machine — and it may only ever prove two points APART: an equal label with a doorway
// too narrow for the body asking is the wrong half of the guarantee, and the last test here pins it by
// exhibiting exactly that case.
//
// The flood fill's distances are checked against an independent construction rather than against
// themselves: an exact Euclidean shortest path over a visibility graph built from the field's own
// boundary runs, solved with Dijkstra. The two share no code and no idea — one walks portals and
// string-pulls, the other draws every corner-to-corner line the geometry admits — so a propagation bug
// in either shows up as a disagreement instead of as two matching wrong numbers. The remaining tests
// pin the exits: the early-out bounds are honoured, one-to-many agrees element-for-element with
// one-by-one, and an island the flood cannot reach is never settled.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"
#include "Test_GroundNav_ReferencePaths.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_reachability
{
    using ck::groundnav::ECk_GroundNav_Reachability;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FloodCrossing;
    using ck::groundnav::FCk_GroundNav_FloodQuery;
    using ck::groundnav::FCk_GroundNav_FloodResult;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_ReachabilityQuery;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::Get_FloodDistancesTo;
    using ck::groundnav::Get_FloodDistanceTo;
    using ck::groundnav::Get_FloodFill;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_IsReachable;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_TileAndPlate;
    using ck::groundnav::Get_TileIndex;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_QueryScene;
    using ck_test_groundnav_queryfixtures::Do_MakeTileUnbuiltAt;
    using ck_test_groundnav_queryfixtures::Get_TileCentre;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;
    using ck_test_groundnav_queryfixtures::Make_RandomPointsOverField;

    using ck_test_groundnav_referencepaths::Get_ReferenceDistance;
    using ck_test_groundnav_referencepaths::Get_XY;
    using ck_test_groundnav_referencepaths::kEpsilon;
    using ck_test_groundnav_referencepaths::kGroundStoreyMaxZ;
    using ck_test_groundnav_referencepaths::Make_VisibilityGraph;

    // The two-island scene: one field, two floors, and a 400 uu gap that no crossing spans.
    constexpr auto kIslandGapMinX = 600.0;
    constexpr auto kIslandGapMaxX = 1000.0;

    const auto kIslandAProbe = FVector{200.0, 800.0, kGroundZ};
    const auto kIslandASecondProbe = FVector{400.0, 1500.0, kGroundZ};
    const auto kIslandBProbe = FVector{1500.0, 800.0, kGroundZ};

    // One point per column of tiles, in row 0, so the unbuilt tile taken away is neither of them.
    const auto kIslandANearProbe = FVector{200.0, 400.0, kGroundZ};
    const auto kIslandBNearProbe = FVector{1500.0, 400.0, kGroundZ};

    const auto kGapProbe = FVector{800.0, 800.0, kGroundZ};
    const auto kHighProbe = FVector{200.0, 400.0, 500.0};
    constexpr auto kHighProbeToleranceUu = 40.0f;

    // The west room of the query scene, well clear of the dividing wall and of the field rim.
    const auto kFloodSource = FVector{200.0, 800.0, kGroundZ};

    constexpr auto kSamplePointCount = 2000;
    constexpr auto kSampleSeed = 20260903;
    constexpr auto kReferenceTargetCount = 100;
    constexpr auto kOneToManyTargetCount = 50;

    constexpr auto kProjectionExtentUu = 100.0f;
    constexpr auto kProjectionReachUu = 300.0f;

    constexpr auto kMaxDistanceUu = 600.0f;
    constexpr auto kPredicateStopUu = 300.0;
    constexpr auto kMaxExpansions = 3;

    // The doorway scene: a second wall across the west room with a 60 uu authored gap in it, which the
    // lattice resolves to two free cells. Wide enough for a body of no size, and for nothing else.
    const auto kDoorwaySource = FVector{200.0, 500.0, kGroundZ};
    const auto kDoorwayTarget = FVector{200.0, 1400.0, kGroundZ};
    constexpr auto kDoorwayRadiusUu = 40.0f;

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Get_StatusName(
        ECk_NavSurface_QueryStatus InStatus) -> const TCHAR*
    {
        switch (InStatus)
        {
            case ECk_NavSurface_QueryStatus::Success: return TEXT("Success");
            case ECk_NavSurface_QueryStatus::NoSurface: return TEXT("NoSurface");
            case ECk_NavSurface_QueryStatus::Unbuilt: return TEXT("Unbuilt");
            case ECk_NavSurface_QueryStatus::Blocked: return TEXT("Blocked");
            case ECk_NavSurface_QueryStatus::NoProvider: return TEXT("NoProvider");
        }

        return TEXT("Unknown");
    }

    auto Get_ReachabilityName(
        ECk_GroundNav_Reachability InReachability) -> const TCHAR*
    {
        switch (InReachability)
        {
            case ECk_GroundNav_Reachability::PossiblyReachable: return TEXT("PossiblyReachable");
            case ECk_GroundNav_Reachability::Unreachable: return TEXT("Unreachable");
            case ECk_GroundNav_Reachability::Unknown_OpenComponent: return TEXT("Unknown_OpenComponent");
        }

        return TEXT("Unknown");
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * Two floors in one field with nothing between them.
     *
     * The gap is wider than any halo, so neither floor's bake can see the other and no crossing of any
     * kind joins them: this is the only shape that lets a label comparison say Unreachable and mean it.
     */
    auto Make_TwoIslandScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{kIslandGapMinX, 2000.0, kGroundZ}},
            FBox{FVector{kIslandGapMaxX, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    }

    /**
     * The query scene with a second wall across its west room, pierced by a 60 uu doorway.
     *
     * 60 uu of authored gap on a 25 uu lattice leaves exactly two free cells, so the crossing carries a
     * cell of clearance: passable by a body of no size and by nothing wider than one.
     */
    auto Make_DoorwayScene() -> TArray<FBox>
    {
        auto Boxes = Make_QueryScene();

        Boxes.Emplace(FBox{FVector{0.0, 1000.0, 0.0}, FVector{300.0, 1100.0, 300.0}});
        Boxes.Emplace(FBox{FVector{360.0, 1000.0, 0.0}, FVector{700.0, 1100.0, 300.0}});

        return Boxes;
    }

    auto Make_ReachabilityQuery(
        const FVector& InStart,
        const FVector& InEnd,
        float          InVerticalToleranceUu) -> FCk_GroundNav_ReachabilityQuery
    {
        auto Query = FCk_GroundNav_ReachabilityQuery{};

        Query._Start = InStart;
        Query._End = InEnd;
        Query._VerticalToleranceUu = InVerticalToleranceUu;

        return Query;
    }

    auto Make_FloodQuery(
        const FVector& InSource,
        float          InRadiusUu) -> FCk_GroundNav_FloodQuery
    {
        auto Query = FCk_GroundNav_FloodQuery{};

        Query._Source = InSource;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(InRadiusUu);

        return Query;
    }

    auto Make_ProjectionQuery(
        const FVector& InLocation) -> FCk_GroundNav_ProjectionQuery
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = InLocation;
        Query._HorizontalExtentUu = kProjectionExtentUu;
        Query._UpExtentUu = kProjectionReachUu;
        Query._DownExtentUu = kProjectionReachUu;
        Query._Mode = ECk_NavSurface_ProjectionMode::Closest;

        return Query;
    }

    auto Get_LabelAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> int32
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStepHeight;

        const auto Result = Get_IsNavigable(InField, Query);

        if (NOT Result.Get_IsSuccess())
        { return INDEX_NONE; }

        return InField.Get_ReachabilityLabel(Result._Surface._TileIndex, Result._Surface._PlateIndex);
    }

    auto Get_FlatPlateLabel(
        const FCk_GroundNav_Field& InField,
        int32                      InFlatPlate) -> int32
    {
        int32 TileIndex = INDEX_NONE;
        int32 PlateIndex = INDEX_NONE;

        if (NOT Get_TileAndPlate(InField, InFlatPlate, TileIndex, PlateIndex))
        { return INDEX_NONE; }

        return InField.Get_ReachabilityLabel(TileIndex, PlateIndex);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** Random points in the field's slab, dropped onto whatever surface is under or over them. */
    auto Make_ProjectedPoints(
        const FCk_GroundNav_Field& InField,
        int32                      InWanted,
        TArray<FVector>&           OutPoints) -> void
    {
        const auto Points = Make_RandomPointsOverField(InField, kSamplePointCount, kSampleSeed);

        for (const auto& Point : Points)
        {
            if (OutPoints.Num() >= InWanted)
            { return; }

            const auto Projected = Get_ProjectPoint(InField, Make_ProjectionQuery(Point));

            if (NOT Projected.Get_IsSuccess())
            { continue; }

            OutPoints.Emplace(Projected._Location);
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_CrossIslandRejectsWithZeroExpansions,
    "CkTests.UnitTests.CkGroundNav.Query.Reachability_CrossIslandRejectsWithZeroExpansions",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_CrossIslandRejectsWithZeroExpansions::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-island scene bakes"), Bake(Make_TwoIslandScene(), Make_QueryParams(), Field)))
    { return false; }

    if (NOT TestTrue(TEXT("the two islands are two components"), Field.Get_ReachabilityComponentCount() >= 2))
    { return false; }

    const auto Across = Get_IsReachable(Field, Make_ReachabilityQuery(kIslandAProbe, kIslandBProbe, kStepHeight));
    const auto Within = Get_IsReachable(Field, Make_ReachabilityQuery(kIslandAProbe, kIslandASecondProbe, kStepHeight));

    const auto Report = FString::Printf(
        TEXT("components %d, across: %s/%s expansions %d, within: %s/%s expansions %d"),
        Field.Get_ReachabilityComponentCount(),
        Get_StatusName(Across._Status), Get_ReachabilityName(Across._Reachability), Across._ExpansionCount,
        Get_StatusName(Within._Status), Get_ReachabilityName(Within._Reachability), Within._ExpansionCount);

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("both ends of the cross-island query resolved [%s]"), *Report),
        Across.Get_IsSuccess()))
    { return false; }

    // Every tile is built, so neither component borders anything unbaked and the refusal is a PROOF
    // rather than a not-yet.
    TestTrue(FString::Printf(TEXT("the islands are provably out of each other's reach [%s]"), *Report),
        Across._Reachability == ECk_GroundNav_Reachability::Unreachable);

    // The counter, not a clock: a label comparison that expanded anything would still answer correctly
    // and would have stopped being the constant-time refusal the whole design rests on.
    TestEqual(FString::Printf(TEXT("the refusal expanded nothing [%s]"), *Report), Across._ExpansionCount, 0);

    if (NOT TestTrue(FString::Printf(TEXT("both ends of the same-island query resolved [%s]"), *Report),
        Within.Get_IsSuccess()))
    { return false; }

    TestTrue(FString::Printf(TEXT("one island is possibly reachable from itself [%s]"), *Report),
        Within._Reachability == ECk_GroundNav_Reachability::PossiblyReachable);

    TestEqual(FString::Printf(TEXT("the same-island answer expanded nothing [%s]"), *Report),
        Within._ExpansionCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_AnOpenComponentIsUnknownNotUnreachable,
    "CkTests.UnitTests.CkGroundNav.Query.Reachability_AnOpenComponentIsUnknownNotUnreachable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_AnOpenComponentIsUnknownNotUnreachable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-island scene bakes"), Bake(Make_TwoIslandScene(), Make_QueryParams(), Field)))
    { return false; }

    auto FarCoord = FCk_GroundNav_TileCoord{};
    FarCoord._X = 1;
    FarCoord._Y = 1;

    const auto FarTileIndex = Get_TileIndex(Field._Params._Divisions, FarCoord);

    if (NOT TestTrue(TEXT("the far tile was taken away"),
        Do_MakeTileUnbuiltAt(Field, Get_TileCentre(Field, FarTileIndex)) == FarTileIndex))
    { return false; }

    const auto Result = Get_IsReachable(Field, Make_ReachabilityQuery(kIslandANearProbe, kIslandBNearProbe, kStepHeight));

    const auto LabelA = Get_LabelAt(Field, kIslandANearProbe);
    const auto LabelB = Get_LabelAt(Field, kIslandBNearProbe);

    const auto EitherIsOpen = Field.Get_IsComponentOpen(LabelA) || Field.Get_IsComponentOpen(LabelB);

    const auto Report = FString::Printf(
        TEXT("status %s, verdict %s, expansions %d, labels %d/%d, open %d/%d"),
        Get_StatusName(Result._Status), Get_ReachabilityName(Result._Reachability), Result._ExpansionCount,
        LabelA, LabelB,
        Field.Get_IsComponentOpen(LabelA) ? 1 : 0, Field.Get_IsComponentOpen(LabelB) ? 1 : 0);

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("both ends still resolved to a surface [%s]"), *Report),
        Result.Get_IsSuccess()))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("the two ends are still different components [%s]"), *Report),
        LabelA != INDEX_NONE && LabelB != INDEX_NONE && LabelA != LabelB))
    { return false; }

    // The verdict tracks the component flags exactly. A component bordering ground nobody has baked can
    // never be proven closed, so the crossing that would join these two may simply not have been looked
    // at yet — and a consumer told Unreachable there would give up on a route that exists.
    const auto Expected = EitherIsOpen
        ? ECk_GroundNav_Reachability::Unknown_OpenComponent
        : ECk_GroundNav_Reachability::Unreachable;

    TestTrue(FString::Printf(TEXT("the verdict follows the components' own openness [%s]"), *Report),
        Result._Reachability == Expected);

    TestEqual(FString::Printf(TEXT("the verdict still expanded nothing [%s]"), *Report),
        Result._ExpansionCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_NoSurfaceReportsTheFailingEnd,
    "CkTests.UnitTests.CkGroundNav.Query.Reachability_NoSurfaceReportsTheFailingEnd",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_NoSurfaceReportsTheFailingEnd::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-island scene bakes"), Bake(Make_TwoIslandScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto StartInGap = Get_IsReachable(Field, Make_ReachabilityQuery(kGapProbe, kIslandAProbe, kStepHeight));
    const auto EndInGap = Get_IsReachable(Field, Make_ReachabilityQuery(kIslandAProbe, kGapProbe, kStepHeight));
    const auto EndAloft = Get_IsReachable(Field, Make_ReachabilityQuery(kIslandANearProbe, kHighProbe, kHighProbeToleranceUu));

    const auto Report = FString::Printf(
        TEXT("start in the gap %s, end in the gap %s, end aloft %s"),
        Get_StatusName(StartInGap._Status), Get_StatusName(EndInGap._Status), Get_StatusName(EndAloft._Status));

    ck::groundnav::Display(TEXT("{}"), Report);

    // A query whose end never landed on ground has no verdict to give. Reporting Success with any
    // reachability value would hand a consumer a comparison between a real plate and nothing.
    TestFalse(FString::Printf(TEXT("a start over nothing is not a success [%s]"), *Report),
        StartInGap.Get_IsSuccess());

    TestFalse(FString::Printf(TEXT("an end over nothing is not a success [%s]"), *Report),
        EndInGap.Get_IsSuccess());

    TestFalse(FString::Printf(TEXT("an end out of vertical reach is not a success [%s]"), *Report),
        EndAloft.Get_IsSuccess());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Flood_DistancesAgreeWithAVisibilityGraphReference,
    "CkTests.UnitTests.CkGroundNav.Query.Flood_DistancesAgreeWithAVisibilityGraphReference",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Flood_DistancesAgreeWithAVisibilityGraphReference::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Flood = Get_FloodFill(Field, Make_FloodQuery(kFloodSource, 0.0f));

    if (NOT TestTrue(TEXT("the flood fill resolved its source"), Flood.Get_IsSuccess()))
    { return false; }

    if (NOT TestTrue(TEXT("the flood fill expanded something"), Flood._ExpansionCount > 0))
    { return false; }

    const auto SourceLabel = Get_FlatPlateLabel(Field, Flood._SourceFlatPlate);

    if (NOT TestTrue(TEXT("the source plate carries a label"), SourceLabel != INDEX_NONE))
    { return false; }

    const auto Graph = Make_VisibilityGraph(Field, SourceLabel, Get_XY(Flood._SourcePoint));

    const auto Agent = Make_Agent(0.0f);
    const auto Points = Make_RandomPointsOverField(Field, kSamplePointCount, kSampleSeed);

    auto Compared = 0;
    auto Mismatched = 0;
    auto Shortcut = 0;
    auto NoReference = 0;

    auto WorstDeltaUu = 0.0;
    auto TotalDeltaUu = 0.0;

    for (const auto& Point : Points)
    {
        if (Compared >= kReferenceTargetCount)
        { break; }

        const auto Projected = Get_ProjectPoint(Field, Make_ProjectionQuery(Point));

        if (NOT Projected.Get_IsSuccess() || Projected._Location.Z > kGroundStoreyMaxZ)
        { continue; }

        if (Field.Get_ReachabilityLabel(Projected._Surface._TileIndex, Projected._Surface._PlateIndex) != SourceLabel)
        { continue; }

        const auto FloodDistance = Get_FloodDistanceTo(Field, Flood, Projected._Location, kStepHeight, Agent);

        if (NOT FloodDistance.IsSet())
        { continue; }

        const auto Reference = Get_ReferenceDistance(Field, Graph, Get_XY(Projected._Location));

        if (NOT Reference.IsSet())
        {
            ++NoReference;
            continue;
        }

        ++Compared;

        const auto Delta = FloodDistance.GetValue() - Reference.GetValue();

        WorstDeltaUu = FMath::Max(WorstDeltaUu, FMath::Abs(Delta));
        TotalDeltaUu += FMath::Abs(Delta);

        if (FMath::Abs(Delta) > kCellSize)
        { ++Mismatched; }

        // The reference is the shortest path there is, so the flood may only ever be longer. A flood
        // that came in UNDER it has taken a route the geometry does not offer, which no tolerance on the
        // absolute difference would ever catch.
        if (Delta < -kEpsilon)
        { ++Shortcut; }
    }

    const auto MeanDeltaUu = Compared > 0 ? TotalDeltaUu / static_cast<double>(Compared) : 0.0;

    const auto Report = FString::Printf(
        TEXT("compared %d, mismatched %d, shortcuts %d, unreachable in the reference %d, worst delta %.6f, mean delta %.6f, expansions %d, settled %d, graph nodes %d runs %d"),
        Compared, Mismatched, Shortcut, NoReference, WorstDeltaUu, MeanDeltaUu,
        Flood._ExpansionCount, Flood._Crossings.Num(), Graph._Nodes.Num(), Graph._Runs.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestEqual(FString::Printf(TEXT("the sample reached its full size [%s]"), *Report),
        Compared, kReferenceTargetCount))
    { return false; }

    TestEqual(FString::Printf(TEXT("every flood distance is within a cell of the exact shortest path [%s]"), *Report),
        Mismatched, 0);

    TestEqual(FString::Printf(TEXT("no flood distance undercuts the exact shortest path [%s]"), *Report),
        Shortcut, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Flood_EarlyExitBoundsExpansion,
    "CkTests.UnitTests.CkGroundNav.Query.Flood_EarlyExitBoundsExpansion",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Flood_EarlyExitBoundsExpansion::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Unbounded = Get_FloodFill(Field, Make_FloodQuery(kFloodSource, 0.0f));

    auto BoundedQuery = Make_FloodQuery(kFloodSource, 0.0f);
    BoundedQuery._MaxDistanceUu = kMaxDistanceUu;

    const auto Bounded = Get_FloodFill(Field, BoundedQuery);

    auto Do_StopBeyondPredicateLimit = [](const FCk_GroundNav_FloodCrossing& InCrossing) -> bool
    {
        return InCrossing._DistanceUu > kPredicateStopUu;
    };

    const auto Predicated = Get_FloodFill(Field, Make_FloodQuery(kFloodSource, 0.0f), Do_StopBeyondPredicateLimit);

    auto CappedQuery = Make_FloodQuery(kFloodSource, 0.0f);
    CappedQuery._MaxExpansions = kMaxExpansions;

    const auto Capped = Get_FloodFill(Field, CappedQuery);

    auto OverDistance = 0;

    auto FurthestUu = 0.0;

    for (const auto& Crossing : Bounded._Crossings)
    {
        FurthestUu = FMath::Max(FurthestUu, Crossing._DistanceUu);

        if (Crossing._DistanceUu > static_cast<double>(kMaxDistanceUu) + kEpsilon)
        { ++OverDistance; }
    }

    const auto Report = FString::Printf(
        TEXT("unbounded expansions %d settled %d, bounded expansions %d settled %d furthest %.6f over %d, predicated settled %d, capped expansions %d settled %d"),
        Unbounded._ExpansionCount, Unbounded._Crossings.Num(),
        Bounded._ExpansionCount, Bounded._Crossings.Num(), FurthestUu, OverDistance,
        Predicated._Crossings.Num(), Capped._ExpansionCount, Capped._Crossings.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("every run resolved its source [%s]"), *Report),
        Unbounded.Get_IsSuccess() && Bounded.Get_IsSuccess() &&
        Predicated.Get_IsSuccess() && Capped.Get_IsSuccess()))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("the unbounded run has room to be cut down [%s]"), *Report),
        Unbounded._Crossings.Num() > kMaxExpansions))
    { return false; }

    TestEqual(FString::Printf(TEXT("no settled crossing lies beyond the distance limit [%s]"), *Report),
        OverDistance, 0);

    // A limit that bounded the RESULT without bounding the WORK would leave the near-O(1) budget claim
    // resting on nothing, so the expansion counter is what the assertion reads.
    TestTrue(FString::Printf(TEXT("the distance limit costs no more than the unbounded run [%s]"), *Report),
        Bounded._ExpansionCount <= Unbounded._ExpansionCount);

    TestTrue(FString::Printf(TEXT("a tighter stop predicate settles no more than the distance limit [%s]"), *Report),
        Predicated._Crossings.Num() <= Bounded._Crossings.Num());

    TestTrue(FString::Printf(TEXT("the expansion cap is honoured [%s]"), *Report),
        Capped._ExpansionCount <= kMaxExpansions);

    TestTrue(FString::Printf(TEXT("the expansion cap bounds what is settled [%s]"), *Report),
        Capped._Crossings.Num() <= kMaxExpansions);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Flood_OneToManyMatchesOneByOne,
    "CkTests.UnitTests.CkGroundNav.Query.Flood_OneToManyMatchesOneByOne",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Flood_OneToManyMatchesOneByOne::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Flood = Get_FloodFill(Field, Make_FloodQuery(kFloodSource, 0.0f));

    if (NOT TestTrue(TEXT("the flood fill resolved its source"), Flood.Get_IsSuccess()))
    { return false; }

    auto Targets = TArray<FVector>{};
    Make_ProjectedPoints(Field, kOneToManyTargetCount, Targets);

    if (NOT TestEqual(TEXT("the sample reached its full size"), Targets.Num(), kOneToManyTargetCount))
    { return false; }

    const auto Agent = Make_Agent(0.0f);

    auto Batched = TArray<TOptional<double>>{};
    Get_FloodDistancesTo(Field, Flood, Targets, kStepHeight, Agent, Batched);

    if (NOT TestEqual(TEXT("the batch answers every target"), Batched.Num(), Targets.Num()))
    { return false; }

    auto SetnessDisagreed = 0;
    auto ValueDisagreed = 0;
    auto SetCount = 0;

    for (auto Index = 0; Index < Targets.Num(); ++Index)
    {
        const auto Single = Get_FloodDistanceTo(Field, Flood, Targets[Index], kStepHeight, Agent);

        if (Single.IsSet() != Batched[Index].IsSet())
        {
            ++SetnessDisagreed;
            continue;
        }

        if (NOT Single.IsSet())
        { continue; }

        ++SetCount;

        // Compared EXACTLY. The batch amortizes nothing, so anything but bit-identical answers means the
        // two forms took different routes through the same data and one of them is a defect.
        if (Single.GetValue() != Batched[Index].GetValue())
        { ++ValueDisagreed; }
    }

    const auto Report = FString::Printf(
        TEXT("targets %d, set %d, setness disagreements %d, value disagreements %d"),
        Targets.Num(), SetCount, SetnessDisagreed, ValueDisagreed);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("the batch and the singles agree on which targets are reached [%s]"), *Report),
        SetnessDisagreed, 0);

    TestEqual(FString::Printf(TEXT("the batch and the singles agree on every distance [%s]"), *Report),
        ValueDisagreed, 0);

    TestTrue(FString::Printf(TEXT("the sample contains reached targets at all [%s]"), *Report), SetCount > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Flood_UnreachableIslandIsNeverSettled,
    "CkTests.UnitTests.CkGroundNav.Query.Flood_UnreachableIslandIsNeverSettled",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Flood_UnreachableIslandIsNeverSettled::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-island scene bakes"), Bake(Make_TwoIslandScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto Flood = Get_FloodFill(Field, Make_FloodQuery(kIslandAProbe, 0.0f));

    if (NOT TestTrue(TEXT("the flood fill resolved its source"), Flood.Get_IsSuccess()))
    { return false; }

    const auto SourceLabel = Get_FlatPlateLabel(Field, Flood._SourceFlatPlate);

    if (NOT TestTrue(TEXT("the source plate carries a label"), SourceLabel != INDEX_NONE))
    { return false; }

    auto ForeignSettled = 0;

    for (const auto& Crossing : Flood._Crossings)
    {
        if (Get_FlatPlateLabel(Field, Crossing._Crossing._ToFlatPlate) != SourceLabel)
        { ++ForeignSettled; }
    }

    const auto Agent = Make_Agent(0.0f);

    const auto SameIsland = Get_FloodDistanceTo(Field, Flood, kIslandASecondProbe, kStepHeight, Agent);
    const auto FarIsland = Get_FloodDistanceTo(Field, Flood, kIslandBProbe, kStepHeight, Agent);

    const auto Report = FString::Printf(
        TEXT("settled %d, foreign %d, same island set %d, far island set %d"),
        Flood._Crossings.Num(), ForeignSettled, SameIsland.IsSet() ? 1 : 0, FarIsland.IsSet() ? 1 : 0);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("no settled crossing enters another component [%s]"), *Report),
        ForeignSettled, 0);

    // The positive half has to hold too, or "nothing was reached" would satisfy the negative one
    // vacuously and this test would pass against a flood fill that does nothing at all.
    TestTrue(FString::Printf(TEXT("a point on the source's own island is reached [%s]"), *Report),
        SameIsland.IsSet());

    TestFalse(FString::Printf(TEXT("a point on the far island is not reached [%s]"), *Report),
        FarIsland.IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Flood_RadiusRefusesNarrowCrossings,
    "CkTests.UnitTests.CkGroundNav.Query.Flood_RadiusRefusesNarrowCrossings",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Flood_RadiusRefusesNarrowCrossings::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the doorway scene bakes"), Bake(Make_DoorwayScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto SourceLabel = Get_LabelAt(Field, kDoorwaySource);
    const auto TargetLabel = Get_LabelAt(Field, kDoorwayTarget);

    const auto ThinFlood = Get_FloodFill(Field, Make_FloodQuery(kDoorwaySource, 0.0f));
    const auto WideFlood = Get_FloodFill(Field, Make_FloodQuery(kDoorwaySource, kDoorwayRadiusUu));

    if (NOT TestTrue(TEXT("both floods resolved their source"),
        ThinFlood.Get_IsSuccess() && WideFlood.Get_IsSuccess()))
    { return false; }

    const auto ThinDistance = Get_FloodDistanceTo(Field, ThinFlood, kDoorwayTarget, kStepHeight, Make_Agent(0.0f));
    const auto WideDistance =
        Get_FloodDistanceTo(Field, WideFlood, kDoorwayTarget, kStepHeight, Make_Agent(kDoorwayRadiusUu));

    const auto Report = FString::Printf(
        TEXT("labels %d/%d, thin set %d, wide set %d, thin settled %d, wide settled %d"),
        SourceLabel, TargetLabel, ThinDistance.IsSet() ? 1 : 0, WideDistance.IsSet() ? 1 : 0,
        ThinFlood._Crossings.Num(), WideFlood._Crossings.Num());

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("both ends stand on labelled ground [%s]"), *Report),
        SourceLabel != INDEX_NONE && TargetLabel != INDEX_NONE))
    { return false; }

    // This is the wrong half of the label guarantee, exhibited. The two rooms ARE one component — a body
    // of no size walks between them — and a consumer that read the equal label as permission would send
    // a body of forty units at a doorway it cannot fit through.
    TestEqual(FString::Printf(TEXT("the doorway makes the two rooms one component [%s]"), *Report),
        SourceLabel, TargetLabel);

    TestTrue(FString::Printf(TEXT("a body of no size walks through the doorway [%s]"), *Report),
        ThinDistance.IsSet());

    TestFalse(FString::Printf(TEXT("a body wider than the doorway does not [%s]"), *Report),
        WideDistance.IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
