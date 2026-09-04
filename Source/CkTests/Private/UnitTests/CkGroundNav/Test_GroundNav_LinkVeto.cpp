// The per-agent veto: what ONE query is allowed to refuse about the links the field it reads holds.
//
// The veto is a property of the QUERY and of nothing else, so every case here is measured against the
// same field answering a query that does not carry it. That is what separates a veto from a link
// toggle: a toggle is authored state, it re-derives the field and it moves the reachability labels;
// a veto moves neither, and the case that says so asks the field for a label across the very link the
// query beside it refused to walk.
//
// The cost rewrite is measured the way LinkSearch measures an authored multiplier - at the crossover,
// the multiplier where taking the link and going round cost the same. The crossover is derived from
// two runs rather than from the geometry: the corridor over the link is its two on-plate legs plus
// span times multiplier, only the last term moves with the multiplier, so the price is affine in it
// and one run priced at one fixes the line. The closed form and the two runs it rests on are the same
// arithmetic LinkSearch states; they are repeated here because that copy is a file-local helper of
// that file's own namespace, exactly as Test_GroundNav_Links repeats the two-island scene.
//
// The rewrite REPLACES the authored multiplier rather than merging upward with it, and both halves of
// that claim are asserted: a rewrite dearer than the authored price sends the route round a link the
// author made cheap, and a rewrite cheaper than the authored price sends it over a link the author
// made dear. Never below one, which is refused where the request is made and not clamped in the
// search - a refusal a caller can see, at the same bound an authored multiplier is refused at.

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Path/CkGroundNavPath_Fragment.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// A tag and a tag UNDER it: the LINK'S tag is matched against the deny container, which answers up
// that tag's own parent chain, so naming the ladder must also deny the rope ladder without naming it.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Veto_Ladder, "CkTests.GroundNav.Veto.Ladder");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Veto_RopeLadder, "CkTests.GroundNav.Veto.Ladder.Rope");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Veto_Drop, "CkTests.GroundNav.Veto.Drop");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_linkveto
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_ReachabilityQuery;
    using ck::groundnav::Get_Funnelled;
    using ck::groundnav::Get_IsReachable;
    using ck::groundnav::Get_Path;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    // ----------------------------------------------------------------------------------------------------------------

    // Every closed form below is stated for a body of no size: an inset body cannot touch the corners
    // the taut string bends on.
    constexpr auto kNoRadius = 0.0f;

    // The tolerance a measured length is held to against a stated one, which is one cell: a portal
    // stands on a cell line and a closed form of the geometry does not.
    constexpr auto kOracleToleranceUu = static_cast<double>(kCellSize);

    // Two prices of the SAME corridor, so nothing but float rounding stands between them.
    constexpr auto kCostToleranceUu = 1.0;

    // A tenth either side of the multiplier at which the link and the way round cost the same.
    constexpr auto kUnderTheCrossover = 0.9f;
    constexpr auto kOverTheCrossover = 1.1f;

    constexpr auto kOneCrossing = 1;
    constexpr auto kNoCrossings = 0;

    // The id the barrier scene's link is authored under. Ids are the volume's, not the field's, and a
    // baked field carries whatever the record said - so a fixture names its own.
    constexpr auto kLinkId = 1;
    constexpr auto kUnusedLinkId = 77;

    // ----------------------------------------------------------------------------------------------------------------

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

    const auto kBarrierStart = FVector{200.0, 200.0, kGroundZ};
    const auto kBarrierGoal = FVector{600.0, 200.0, kGroundZ};

    // Straight across the barrier at the height of both ends, so the route that takes it is ONE line and
    // its taut length is the distance between those ends.
    const auto kLinkEntry = FVector{300.0, 200.0, kGroundZ};
    const auto kLinkExit = FVector{500.0, 200.0, kGroundZ};

    constexpr auto kLinkSpanUu = 200.0;

    // Two floors with a gap wider than any halo between them, so no portal and no seam joins them and a
    // link is the only thing that can. The same shape Test_GroundNav_Links uses to make a label
    // comparison mean something, repeated for the same reason it repeated it.
    constexpr auto kIslandGapMinX = 600.0;
    constexpr auto kIslandGapMaxX = 1000.0;

    const auto kIslandAPoint = FVector{200.0, 400.0, kGroundZ};
    const auto kIslandBPoint = FVector{1500.0, 400.0, kGroundZ};

    // ----------------------------------------------------------------------------------------------------------------

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

    auto Make_TwoIslandScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{kIslandGapMinX, 2000.0, kGroundZ}},
            FBox{FVector{kIslandGapMaxX, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
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

    // ----------------------------------------------------------------------------------------------------------------

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

    auto Make_TaggedLinkRecord(
        int32              InId,
        const FVector&     InStart,
        const FVector&     InEnd,
        float              InMultiplier,
        const FGameplayTag& InUserTypeTag) -> FCk_GroundNav_LinkRecord
    {
        auto Record = Make_LinkRecord(InId, InStart, InEnd, InMultiplier);

        Record.Set_UserTypeTag(InUserTypeTag);

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

    auto Bake_TwoIslands(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_FieldPtr&                 OutField) -> bool
    {
        return Bake_Shared(Make_TwoIslandScene(), Make_QueryParams(), InLinks, OutField);
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
        const FVector& InGoal) -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = InStart;
        Query._Goal = InGoal;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(kNoRadius);

        return Query;
    }

    auto Make_BarrierQuery() -> FCk_GroundNav_PathQuery
    {
        return Make_PathQuery(kBarrierStart, kBarrierGoal);
    }

    /** The same query with one link denied by its stable id, which is the only thing that differs. */
    auto Make_QueryDenyingId(
        const FCk_GroundNav_PathQuery& InQuery,
        int32                          InLinkId) -> FCk_GroundNav_PathQuery
    {
        auto Query = InQuery;

        Query._Cost._DeniedLinkIds.Add(InLinkId);

        return Query;
    }

    /** The same query with one class of link denied, which is the only thing that differs. */
    auto Make_QueryDenyingTag(
        const FCk_GroundNav_PathQuery& InQuery,
        const FGameplayTag&            InUserTypeTag) -> FCk_GroundNav_PathQuery
    {
        auto Query = InQuery;

        Query._Cost._DeniedLinkUserTypeTags.AddTag(InUserTypeTag);

        return Query;
    }

    /** The same query pricing one link at a number of its own, which is the only thing that differs. */
    auto Make_QueryRewriting(
        const FCk_GroundNav_PathQuery& InQuery,
        int32                          InLinkId,
        float                          InMultiplier) -> FCk_GroundNav_PathQuery
    {
        auto Query = InQuery;

        Query._Cost._LinkCostMultipliers.Add(InLinkId, InMultiplier);

        return Query;
    }

    auto Make_ReachabilityQuery(
        const FVector& InStart,
        const FVector& InEnd) -> FCk_GroundNav_ReachabilityQuery
    {
        auto Query = FCk_GroundNav_ReachabilityQuery{};

        Query._Start = InStart;
        Query._End = InEnd;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(kNoRadius);

        return Query;
    }

    // ----------------------------------------------------------------------------------------------------------------

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

    auto Get_FunnelledLengthUu(
        const FCk_GroundNav_PathResult& InResult) -> double
    {
        auto Waypoints = TArray<FVector>{};

        return Get_Funnelled(InResult, kNoRadius, Waypoints);
    }

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

        if (NOT Bake_Barrier({Make_LinkRecord(kLinkId, kLinkEntry, kLinkExit, 1.0f)}, Linked))
        { return false; }

        OutCrossover._Detour = Get_Path(Plain, Make_BarrierQuery());
        OutCrossover._AtMultiplierOne = Get_Path(Linked, Make_BarrierQuery());

        if (OutCrossover._Detour._Status != ECk_GroundNav_PathStatus::Ready ||
            OutCrossover._AtMultiplierOne._Status != ECk_GroundNav_PathStatus::Ready)
        { return false; }

        OutCrossover._Multiplier = Get_CrossoverMultiplier(
            OutCrossover._Detour._SearchCost,
            OutCrossover._AtMultiplierOne._SearchCost,
            kLinkSpanUu);

        return true;
    }

    /** A multiplier a tenth of the way below the crossover, which is where the link wins. */
    auto Get_CheapMultiplier(
        const FCrossover& InCrossover) -> float
    {
        return 1.0f + (kUnderTheCrossover * (InCrossover._Multiplier - 1.0f));
    }

    /** A multiplier a tenth of the way above the crossover, which is where the way round wins. */
    auto Get_DearMultiplier(
        const FCrossover& InCrossover) -> float
    {
        return 1.0f + (kOverTheCrossover * (InCrossover._Multiplier - 1.0f));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_DeniedLinkIsRoutedAround,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.DeniedLinkIsRoutedAround",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_DeniedLinkIsRoutedAround::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the scene bakes with the link priced under the crossover"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kLinkEntry, kLinkExit, Get_CheapMultiplier(Crossover))},
            Field)))
    { return false; }

    const auto Taken = Get_Path(Field, Make_BarrierQuery());

    if (NOT TestTrue(TEXT("a query carrying no veto takes it"),
        Taken._Status == ECk_GroundNav_PathStatus::Ready &&
        Get_LinkCrossingCount(Taken) == kOneCrossing))
    { return false; }

    const auto Denied = Get_Path(Field, Make_QueryDenyingId(Make_BarrierQuery(), kLinkId));

    if (NOT TestTrue(TEXT("and the query that denies it still answers a route"),
        Denied._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    // No node was minted for the denied crossing, so it cannot be in the corridor at any price.
    TestEqual(TEXT("that crosses no link at all"),
        Get_LinkCrossingCount(Denied), kNoCrossings);

    TestTrue(TEXT("and is the corridor the field with no link at all answered with"),
        Denied._PlateCorridor == Crossover._Detour._PlateCorridor);

    TestTrue(FString::Printf(TEXT("walking the closed form of the way round: %.3f against %.3f"),
        Get_FunnelledLengthUu(Denied), Get_BarrierDetourLengthUu()),
        FMath::Abs(Get_FunnelledLengthUu(Denied) - Get_BarrierDetourLengthUu()) <= kOracleToleranceUu);

    // A deny set naming a link this field does not hold changes nothing: the veto is keyed on the
    // stable id, and an id nothing matches is not a silent refusal of whatever happened to be there.
    const auto Unrelated = Get_Path(Field, Make_QueryDenyingId(Make_BarrierQuery(), kUnusedLinkId));

    TestEqual(TEXT("denying an id the field does not hold still takes the link"),
        Get_LinkCrossingCount(Unrelated), kOneCrossing);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_DenyByUserTypeTagRoutesAround,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.DenyByUserTypeTagRoutesAround",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_DenyByUserTypeTagRoutesAround::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    // The link is a ROPE ladder, and the query denies ladders. Nothing names the rope ladder itself,
    // so a container matched by equality rather than up the parent chain would let this route through.
    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the scene bakes with a tagged link priced under the crossover"),
        Bake_Barrier({Make_TaggedLinkRecord(kLinkId, kLinkEntry, kLinkExit,
            Get_CheapMultiplier(Crossover), TAG_CkTests_GroundNav_Veto_RopeLadder.GetTag())}, Field)))
    { return false; }

    const auto Taken = Get_Path(Field, Make_BarrierQuery());

    if (NOT TestTrue(TEXT("a query carrying no veto takes it"),
        Taken._Status == ECk_GroundNav_PathStatus::Ready &&
        Get_LinkCrossingCount(Taken) == kOneCrossing))
    { return false; }

    const auto Denied = Get_Path(Field,
        Make_QueryDenyingTag(Make_BarrierQuery(), TAG_CkTests_GroundNav_Veto_Ladder.GetTag()));

    if (NOT TestTrue(TEXT("and the query that denies ladders still answers a route"),
        Denied._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("that crosses no link"), Get_LinkCrossingCount(Denied), kNoCrossings);

    TestTrue(TEXT("and is the corridor the field with no link at all answered with"),
        Denied._PlateCorridor == Crossover._Detour._PlateCorridor);

    // A different class of link is a different answer, which is what makes the case above a match on
    // the tag rather than on the presence of one.
    const auto Unrelated = Get_Path(Field,
        Make_QueryDenyingTag(Make_BarrierQuery(), TAG_CkTests_GroundNav_Veto_Drop.GetTag()));

    TestEqual(TEXT("denying a class this link is not still takes it"),
        Get_LinkCrossingCount(Unrelated), kOneCrossing);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The veto belongs to the query and to nothing that outlives it. Two searches over ONE published field,
// so there is no rebuild, no republish and no second epoch between them for a difference to hide in.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_VetoIsPerQuery,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.VetoIsPerQuery",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_VetoIsPerQuery::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the scene bakes with the link priced under the crossover"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kLinkEntry, kLinkExit, Get_CheapMultiplier(Crossover))},
            Field)))
    { return false; }

    const auto Denying = Get_Path(Field, Make_QueryDenyingId(Make_BarrierQuery(), kLinkId));
    const auto Permitting = Get_Path(Field, Make_BarrierQuery());

    if (NOT TestTrue(TEXT("both queries answer a route"),
        Denying._Status == ECk_GroundNav_PathStatus::Ready &&
        Permitting._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestTrue(TEXT("planned against one and the same epoch"),
        Denying._PlannedAgainstEpoch == Permitting._PlannedAgainstEpoch);

    TestEqual(TEXT("the vetoing query goes round"),
        Get_LinkCrossingCount(Denying), kNoCrossings);
    TestEqual(TEXT("and the one beside it, over the same field, still crosses"),
        Get_LinkCrossingCount(Permitting), kOneCrossing);

    // Asked again AFTER the vetoing run, so a veto that had leaked onto the field rather than onto the
    // query would answer the detour here.
    const auto PermittingAgain = Get_Path(Field, Make_BarrierQuery());

    TestEqual(TEXT("and still crosses when it is asked last"),
        Get_LinkCrossingCount(PermittingAgain), kOneCrossing);

    TestTrue(TEXT("the field's own resolved link is untouched by either query"),
        Field->_ResolvedLinks.Num() == 1 && Field->_ResolvedLinks[0].Get_IsTraversable());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The rewrite REPLACES the authored multiplier. Both directions are asked, because a merge would pass
// one of them: an upward merge would honour a dearer rewrite and ignore a cheaper one.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_CostRewriteReplacesTheAuthoredMultiplier,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.CostRewriteReplacesTheAuthoredMultiplier",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_CostRewriteReplacesTheAuthoredMultiplier::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    // Authored at one: as cheap as a link may honestly be, so anything that sends the route round came
    // from the rewrite and from nothing the record says.
    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the scene bakes with the link authored at one"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kLinkEntry, kLinkExit, 1.0f)}, Field)))
    { return false; }

    const auto DearMultiplier = Get_DearMultiplier(Crossover);

    const auto Dear = Get_Path(Field, Make_QueryRewriting(Make_BarrierQuery(), kLinkId, DearMultiplier));

    if (NOT TestTrue(TEXT("a rewrite over the crossover still answers a route"),
        Dear._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("that goes round the link the author priced at one"),
        Get_LinkCrossingCount(Dear), kNoCrossings);

    TestTrue(FString::Printf(TEXT("at the way round's own price: %.3f against %.3f"),
        Dear._SearchCost, Crossover._Detour._SearchCost),
        FMath::Abs(static_cast<double>(Dear._SearchCost) -
            static_cast<double>(Crossover._Detour._SearchCost)) <= kCostToleranceUu);

    const auto CheapMultiplier = Get_CheapMultiplier(Crossover);

    const auto Cheap = Get_Path(Field, Make_QueryRewriting(Make_BarrierQuery(), kLinkId, CheapMultiplier));

    if (NOT TestTrue(TEXT("a rewrite under the crossover answers a route"),
        Cheap._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestEqual(TEXT("that takes the link"), Get_LinkCrossingCount(Cheap), kOneCrossing);

    // The whole of what the rewrite moved: the same corridor, priced at the rewritten multiplier and
    // not at the authored one.
    const auto PricedUu = Get_PricedAt(
        Crossover._AtMultiplierOne._SearchCost, kLinkSpanUu, CheapMultiplier);

    TestTrue(FString::Printf(
        TEXT("priced at its own span times the REWRITTEN multiplier: %.3f against %.3f"),
        Cheap._SearchCost, PricedUu),
        FMath::Abs(static_cast<double>(Cheap._SearchCost) - PricedUu) <= kCostToleranceUu);

    // The other direction of "replaces": the author priced the link out of reach and the query talks it
    // back down. An upward merge would leave this route on the detour.
    auto DearlyAuthored = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the scene bakes with the link authored over the crossover"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kLinkEntry, kLinkExit, DearMultiplier)}, DearlyAuthored)))
    { return false; }

    if (NOT TestTrue(TEXT("which the field answers by going round"),
        Get_LinkCrossingCount(Get_Path(DearlyAuthored, Make_BarrierQuery())) == kNoCrossings))
    { return false; }

    const auto TalkedDown = Get_Path(DearlyAuthored,
        Make_QueryRewriting(Make_BarrierQuery(), kLinkId, CheapMultiplier));

    TestEqual(TEXT("and a query that prices it cheaper takes it"),
        Get_LinkCrossingCount(TalkedDown), kOneCrossing);

    TestTrue(FString::Printf(
        TEXT("for the rewritten price and not the authored one: %.3f against %.3f"),
        TalkedDown._SearchCost, PricedUu),
        FMath::Abs(static_cast<double>(TalkedDown._SearchCost) - PricedUu) <= kCostToleranceUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A per-query multiplier below one breaks the same property an authored one below one breaks: an edge
// cheaper than the distance it covers, under a heuristic that is admissible only because no edge is.
// So it is refused at the same bound, where the request is made - not clamped inside the search, where
// the caller would have no way of learning its number was ignored.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_MultiplierBelowOneIsRefusedAtTheRequestBoundary,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.MultiplierBelowOneIsRefusedAtTheRequestBoundary",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_MultiplierBelowOneIsRefusedAtTheRequestBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto EcsWorld = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto Path = UCk_Utils_GroundNavPath_UE::Add(Owner, FCk_Fragment_GroundNavPath_ParamsData{kNoRadius});

    if (NOT TestTrue(TEXT("the agent takes the path feature"), ck::IsValid(Path)))
    { return false; }

    const auto Listener = TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
        NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};

    auto Delegate = FCk_Delegate_Request_OnCompleted{};
    Delegate.BindDynamic(Listener.Get(), &UCk_Test_CompletionListener_UE::OnRequestCompleted);

    auto Request = FCk_Request_GroundNavPath_FindPath{kBarrierStart, kBarrierGoal};
    Request.Get_LinkCostMultipliers().Add(kLinkId, 0.5f);

    AddExpectedError(
        TEXT("link cost multiplier below 1.0"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    UCk_Utils_GroundNavPath_UE::Request_FindPath(Path, Request, Delegate);

    TestFalse(TEXT("the refused request is never enqueued"),
        Path.Has<ck::FFragment_GroundNavPath_Requests>());

    TestEqual(TEXT("and completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed_NotEnqueued"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed_NotEnqueued);

    // One at the bound is admissible and passes, which is what makes the refusal above a test of the
    // bound rather than of the field's presence.
    auto Admissible = FCk_Request_GroundNavPath_FindPath{kBarrierStart, kBarrierGoal};
    Admissible.Get_LinkCostMultipliers().Add(kLinkId, 1.0f);

    UCk_Utils_GroundNavPath_UE::Request_FindPath(Path, Admissible, {});

    TestTrue(TEXT("a multiplier of exactly one is enqueued"),
        Path.Has<ck::FFragment_GroundNavPath_Requests>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A label is the FIELD's answer and a veto is one query's, so the two must not move together. The
// two-island scene is where that is visible: the link is the only thing joining the islands, so a veto
// that had reached the labels would turn PossiblyReachable into Unreachable for everybody.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_DeniedLinkStillJoinsReachabilityLabels,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.DeniedLinkStillJoinsReachabilityLabels",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_DeniedLinkStillJoinsReachabilityLabels::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the two-island scene bakes with a link across the gap"),
        Bake_TwoIslands({Make_LinkRecord(kLinkId, kIslandAPoint, kIslandBPoint, 1.0f)}, Field)))
    { return false; }

    if (NOT TestTrue(TEXT("and the link resolves on both islands"),
        Field->_ResolvedLinks.Num() == 1 && Field->_ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    const auto Reachability = Get_IsReachable(*Field, Make_ReachabilityQuery(kIslandAPoint, kIslandBPoint));

    if (NOT TestTrue(TEXT("the two islands resolve to surfaces"), Reachability.Get_IsSuccess()))
    { return false; }

    TestTrue(TEXT("and the field says they are possibly reachable"),
        Reachability._Reachability == ck::groundnav::ECk_GroundNav_Reachability::PossiblyReachable);

    const auto Crossing = Get_Path(Field, Make_PathQuery(kIslandAPoint, kIslandBPoint));

    if (NOT TestTrue(TEXT("a query carrying no veto walks across"),
        Crossing._Status == ECk_GroundNav_PathStatus::Ready &&
        Get_LinkCrossingCount(Crossing) == kOneCrossing))
    { return false; }

    const auto Denied = Get_Path(Field,
        Make_QueryDenyingId(Make_PathQuery(kIslandAPoint, kIslandBPoint), kLinkId));

    // The only edge between the two components is denied, and there is no way round: the query, and
    // only the query, cannot get there.
    TestTrue(FString::Printf(TEXT("the query that denies it answers Unreachable, not %s"),
        *ck::Format_UE(TEXT("{}"), Denied._Status)),
        Denied._Status == ECk_GroundNav_PathStatus::Unreachable);

    const auto AfterTheVeto =
        Get_IsReachable(*Field, Make_ReachabilityQuery(kIslandAPoint, kIslandBPoint));

    TestTrue(TEXT("while the field still says possibly reachable"),
        AfterTheVeto._Reachability == ck::groundnav::ECk_GroundNav_Reachability::PossiblyReachable);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A rewrite at or above one leaves the heuristic admissible, and an admissible heuristic at w = 1
// answers the OPTIMAL route. Stated as the answered length against the closed form of whichever of the
// two routes is cheaper at that multiplier, on both sides of the crossover - so a rewrite that had been
// applied somewhere the heuristic could not see it would answer a route that is merely legal.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkVeto_HeuristicStaysAdmissibleUnderARewrite,
    "CkTests.UnitTests.CkGroundNav.LinkVeto.HeuristicStaysAdmissibleUnderARewrite",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkVeto_HeuristicStaysAdmissibleUnderARewrite::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkveto;

    auto Crossover = FCrossover{};

    if (NOT TestTrue(TEXT("the barrier scene answers both with and without the link"),
        Do_MeasureCrossover(Crossover)))
    { return false; }

    // Authored over the crossover, so the field's own answer is the detour and every route below comes
    // from the rewrite.
    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the scene bakes with the link authored over the crossover"),
        Bake_Barrier({Make_LinkRecord(kLinkId, kLinkEntry, kLinkExit, Get_DearMultiplier(Crossover))},
            Field)))
    { return false; }

    // Exactly the bound the request boundary admits: the cheapest a link may honestly be.
    const auto AtOne = Get_Path(Field, Make_QueryRewriting(Make_BarrierQuery(), kLinkId, 1.0f));

    if (NOT TestTrue(TEXT("a rewrite of exactly one answers a route"),
        AtOne._Status == ECk_GroundNav_PathStatus::Ready))
    { return false; }

    TestTrue(FString::Printf(TEXT("of the optimum length, which is the straight line: %.3f against %.3f"),
        Get_FunnelledLengthUu(AtOne), Get_BarrierStraightLengthUu()),
        FMath::Abs(Get_FunnelledLengthUu(AtOne) - Get_BarrierStraightLengthUu()) <= kOracleToleranceUu);

    TestTrue(FString::Printf(TEXT("priced exactly as the same field priced a link authored at one: %.3f against %.3f"),
        AtOne._SearchCost, Crossover._AtMultiplierOne._SearchCost),
        FMath::Abs(static_cast<double>(AtOne._SearchCost) -
            static_cast<double>(Crossover._AtMultiplierOne._SearchCost)) <= kCostToleranceUu);

    const auto UnderTheCrossover = Get_Path(Field,
        Make_QueryRewriting(Make_BarrierQuery(), kLinkId, Get_CheapMultiplier(Crossover)));

    TestTrue(FString::Printf(TEXT("and just under the crossover it is still the straight line: %.3f against %.3f"),
        Get_FunnelledLengthUu(UnderTheCrossover), Get_BarrierStraightLengthUu()),
        FMath::Abs(Get_FunnelledLengthUu(UnderTheCrossover) - Get_BarrierStraightLengthUu()) <=
            kOracleToleranceUu);

    const auto OverTheCrossover = Get_Path(Field,
        Make_QueryRewriting(Make_BarrierQuery(), kLinkId, Get_DearMultiplier(Crossover)));

    TestTrue(FString::Printf(TEXT("and just over it the optimum is the way round: %.3f against %.3f"),
        Get_FunnelledLengthUu(OverTheCrossover), Get_BarrierDetourLengthUu()),
        FMath::Abs(Get_FunnelledLengthUu(OverTheCrossover) - Get_BarrierDetourLengthUu()) <=
            kOracleToleranceUu);

    return true;
}
