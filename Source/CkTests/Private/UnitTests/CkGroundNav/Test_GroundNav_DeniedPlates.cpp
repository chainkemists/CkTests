// The per-query GROUND veto: what ONE query is allowed to refuse about the plates the field it reads
// holds, stated the way the link veto beside it is.
//
// A refusal is not a price, and the whole of this file is about that difference. A very large
// multiplier still lets the search cross the ground when nothing cheaper exists, so a caller asking
// "is there a route that avoids this ground AT ALL" would be answered with a route through it and no
// way to tell. A denied plate is therefore entered by no crossing, walked onto by no ray, and stood on
// by no start - three refusals in three places, one per case below.
//
// The scene is the gym's four-pillar slab, taken by shared pointer the way a search takes one. Every
// case measures against the SAME field answering a query that carries no veto: the veto is a property
// of the query and of nothing else, so a field that moved between the two runs would make the
// comparison mean nothing.
//
// The plate ids are read out of the unfiltered ANSWER rather than written down here. A flat plate id
// is a product of the decomposition and of the tile lattice under it, so a literal would be a claim
// about how the baker happens to cut this slab today - and the claim these cases exist to make is
// about the veto, not about the cut.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_QueryTypes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_deniedplates
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_Path;
    using ck::groundnav::Get_SurfaceRaycast;

    using ck_test_groundnav_queryfixtures::Bake_SharedFourPillarSlabScene;
    using ck_test_groundnav_queryfixtures::kFourPillarAgentRadiusUu;
    using ck_test_groundnav_queryfixtures::kFourPillarEastPost;
    using ck_test_groundnav_queryfixtures::kFourPillarWestPost;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;

    // ----------------------------------------------------------------------------------------------------------------

    // The ray's lane, and every coordinate on it is INTERIOR to its cell rather than on a cell line:
    // a point on a line belongs to the cells on both sides, and two ways of asking which plate is
    // under it are then entitled to two answers. The field's lattice is 25 uu from origin
    // (-2000, -1600), which is what these numbers are off-line against.
    //
    // The lane runs south of every pillar - the southernmost reaches Y -175 - so it is clear floor end
    // to end. Plates are TILE-LOCAL and the tile columns are 800 uu wide from X -2000, so the lane's
    // start, middle and end sit in three different tiles and therefore on three different plates by
    // construction rather than by luck.
    constexpr auto kRayLaneY = -612.0;
    constexpr auto kRayStartX = -1638.0;
    constexpr auto kRayEndX = 1638.0;
    constexpr auto kRayMiddleX = 12.0;

    // Short enough to stay inside the start's own plate, and off the lattice for the same reason.
    constexpr auto kShortRayLengthUu = 50.0;

    const auto kRayStart = FVector{kRayStartX, kRayLaneY, kGroundZ};
    const auto kRayEnd = FVector{kRayEndX, kRayLaneY, kGroundZ};
    const auto kRayMiddle = FVector{kRayMiddleX, kRayLaneY, kGroundZ};

    // The corridor must hold a plate that is neither end for an INTERIOR one to be denied. The lane
    // above crosses five tile columns and the west-east route crosses the same five, so this is the
    // shape of the scene rather than a hope about it.
    constexpr auto kMinInteriorCorridorLength = 3;

    // Every closed form here is stated for a body of no size where the ray is concerned; the route
    // cases run at the gym's own radius, because a route that bends around a pillar is what they are
    // about.
    constexpr auto kNoRadius = 0.0f;

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
        Query._Agent = Make_Agent(kFourPillarAgentRadiusUu);

        return Query;
    }

    /** The same query refusing one plate, which is the only thing that differs. */
    auto Make_QueryDenying(
        const FCk_GroundNav_PathQuery& InQuery,
        int32                          InFlatPlate) -> FCk_GroundNav_PathQuery
    {
        auto Query = InQuery;

        Query._Cost._DeniedPlates.Add(InFlatPlate);

        return Query;
    }

    auto Make_RaycastQuery(
        const FVector& InStart,
        const FVector& InEnd) -> FCk_GroundNav_RaycastQuery
    {
        auto Query = FCk_GroundNav_RaycastQuery{};

        Query._Start = InStart;
        Query._End = InEnd;
        Query._StartVerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(kNoRadius);

        return Query;
    }

    /** The flat plate the ground under a point belongs to, or INDEX_NONE where the point stands on none. */
    auto TryGet_FlatPlateAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> int32
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Agent = Make_Agent(kNoRadius);

        const auto Result = Get_IsNavigable(InField, Query);

        if (NOT Result.Get_IsSuccess())
        { return INDEX_NONE; }

        return Get_FlatPlateIndex(InField, Result._Surface._TileIndex, Result._Surface._PlateIndex);
    }

    auto Get_FlatPlateOfSurface(
        const FCk_GroundNav_Field&               InField,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InSurface) -> int32
    {
        return Get_FlatPlateIndex(InField, InSurface._TileIndex, InSurface._PlateIndex);
    }
}

// --------------------------------------------------------------------------------------------------------------------

// A plate the ROUTE went through, refused: the search must answer with a route that does not hold it.
//
// Falsified by dropping the _DeniedPlates skip beside the link veto in FCk_GroundNav_PlatePortalGraph
// ::Neighbors - with it gone the crossing into the denied plate is minted as a node again, the search
// has no reason to prefer any other, and the corridor comes back holding the plate it was told not to.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DeniedPlates_RouteAvoidsADeniedPlate,
    "CkTests.UnitTests.CkGroundNav.DeniedPlates.RouteAvoidsADeniedPlate",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DeniedPlates_RouteAvoidsADeniedPlate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_deniedplates;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Query = Make_PathQuery(kFourPillarWestPost, kFourPillarEastPost);
    const auto Unfiltered = Get_Path(Field, Query);

    if (NOT TestEqual(TEXT("a query carrying no veto crosses the slab"),
        Unfiltered._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    if (NOT TestTrue(TEXT("and its corridor holds a plate that is neither end"),
        Unfiltered._PlateCorridor.Num() >= kMinInteriorCorridorLength))
    { return false; }

    const auto DeniedPlate = Unfiltered._PlateCorridor[1];

    const auto Denied = Get_Path(Field, Make_QueryDenying(Query, DeniedPlate));

    ck::groundnav::Display(
        TEXT("[DENIED-PLATES] unfiltered corridor [{}] plates, denied plate [{}], filtered status [{}] "
             "over [{}] plates"),
        Unfiltered._PlateCorridor.Num(), DeniedPlate, Denied._Status, Denied._PlateCorridor.Num());

    // The claim, and it holds whichever way the search answered: a refusal answers with no corridor at
    // all, and a route that found a way round answers with one the plate is not in.
    TestFalse(TEXT("no corridor the search answers with holds the denied plate"),
        Denied._PlateCorridor.Contains(DeniedPlate));

    // The slab is open floor with four small posts on it, so taking one plate away leaves the rest
    // joined - stated as its own assertion so a red here says "the scene stopped being open", which is
    // a different failure from "the veto stopped working".
    TestEqual(TEXT("and the slab still answers a west-east crossing around it"),
        Denied._Status, ECk_GroundNav_PathStatus::Ready);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The GOAL's own ground refused: there is no door into it, so there is no route to it.
//
// Falsified by the same missing skip as above - a search that mints the crossing into the goal plate
// walks into it and answers Ready.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DeniedPlates_DeniedGoalPlateIsUnreachable,
    "CkTests.UnitTests.CkGroundNav.DeniedPlates.DeniedGoalPlateIsUnreachable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DeniedPlates_DeniedGoalPlateIsUnreachable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_deniedplates;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Query = Make_PathQuery(kFourPillarWestPost, kFourPillarEastPost);
    const auto Unfiltered = Get_Path(Field, Query);

    if (NOT TestEqual(TEXT("a query carrying no veto crosses the slab"),
        Unfiltered._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto StartPlate = Get_FlatPlateOfSurface(*Field, Unfiltered._StartSurface);
    const auto GoalPlate = Get_FlatPlateOfSurface(*Field, Unfiltered._GoalSurface);

    // The two ends must stand on different plates, or the search answers from its same-plate early-out
    // and never consults a crossing at all.
    if (NOT TestTrue(TEXT("the two posts stand on different plates"),
        StartPlate != INDEX_NONE && GoalPlate != INDEX_NONE && StartPlate != GoalPlate))
    { return false; }

    const auto Denied = Get_Path(Field, Make_QueryDenying(Query, GoalPlate));

    TestEqual(TEXT("a goal standing on refused ground is unreachable"),
        Denied._Status, ECk_GroundNav_PathStatus::Unreachable);

    TestTrue(TEXT("and the search answers with no corridor"), Denied._PlateCorridor.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The START's own ground refused: Blocked, and deliberately NOT NoStartSurface.
//
// The distinction is the whole case. There IS ground under the body and the field found it - this
// query is simply not allowed to use it, which is the verdict a body too wide for the field's
// clearance ceiling already gets. Answering NoStartSurface would tell a caller the field has nothing
// there, and a caller that reacts by rebuilding or re-projecting would be chasing ground that is
// already present.
//
// Falsified by dropping the pre-check in FCk_GroundNav_PathSearch: Neighbors refuses plates it is
// asked to ENTER, and the start plate is entered through no crossing, so without the pre-check the
// search leaves the denied ground it is standing on and answers Ready.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DeniedPlates_DeniedStartPlateIsBlocked,
    "CkTests.UnitTests.CkGroundNav.DeniedPlates.DeniedStartPlateIsBlocked",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DeniedPlates_DeniedStartPlateIsBlocked::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_deniedplates;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Query = Make_PathQuery(kFourPillarWestPost, kFourPillarEastPost);
    const auto Unfiltered = Get_Path(Field, Query);

    if (NOT TestEqual(TEXT("a query carrying no veto crosses the slab"),
        Unfiltered._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    const auto StartPlate = Get_FlatPlateOfSurface(*Field, Unfiltered._StartSurface);

    if (NOT TestTrue(TEXT("the start stands on a plate"), StartPlate != INDEX_NONE))
    { return false; }

    const auto Denied = Get_Path(Field, Make_QueryDenying(Query, StartPlate));

    TestEqual(TEXT("a body standing on refused ground is Blocked, not standing on no ground"),
        Denied._Status, ECk_GroundNav_PathStatus::Blocked);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A ray walking onto refused ground stops at its edge, exactly as it stops at a wall - and says so
// with the same Blocked it says about a wall, rather than with the cost flag, because nothing was
// spent.
//
// Falsified by dropping the denial from FTraversal::DoAdvance: the ray steps onto the plate and walks
// the whole lane, answering Success over ground it was told it may not use.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DeniedPlates_RaycastBlocksAtADeniedPlatesEdge,
    "CkTests.UnitTests.CkGroundNav.DeniedPlates.RaycastBlocksAtADeniedPlatesEdge",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DeniedPlates_RaycastBlocksAtADeniedPlatesEdge::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_deniedplates;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto Clear = Get_SurfaceRaycast(*Field, Make_RaycastQuery(kRayStart, kRayEnd));

    if (NOT TestEqual(TEXT("the lane south of every pillar is clear end to end"),
        Clear._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto StartPlate = TryGet_FlatPlateAt(*Field, kRayStart);
    const auto MiddlePlate = TryGet_FlatPlateAt(*Field, kRayMiddle);

    // Plates are tile-local and the lane crosses five tile columns, so these two cannot be the same
    // plate. Asserted rather than assumed: a lattice change that put both ends in one tile would make
    // every claim below a claim about a denied START instead.
    if (NOT TestTrue(TEXT("the lane's start and middle stand on different plates"),
        StartPlate != INDEX_NONE && MiddlePlate != INDEX_NONE && StartPlate != MiddlePlate))
    { return false; }

    auto DeniedQuery = Make_RaycastQuery(kRayStart, kRayEnd);
    DeniedQuery._DeniedPlates.Add(MiddlePlate);

    const auto Denied = Get_SurfaceRaycast(*Field, DeniedQuery);

    ck::groundnav::Display(
        TEXT("[DENIED-PLATES] lane start plate [{}], denied middle plate [{}], hit [{}] status [{}]"),
        StartPlate, MiddlePlate, Denied._HitLocation, Denied._Status);

    TestEqual(TEXT("a ray onto refused ground is Blocked"),
        Denied._Status, ECk_NavSurface_QueryStatus::Blocked);

    TestFalse(TEXT("and it is the ground that stopped it, not a cost cap"), Denied._StoppedOnCost);

    // At the EDGE, stated without geometry: the ray never entered the plate, so the surface it ended on
    // is not that plate - and the denied plate contains the lane's midpoint, so the edge it stopped on
    // is at or west of it.
    TestTrue(TEXT("the ray ended on the plate BEFORE the denied one"),
        Get_FlatPlateOfSurface(*Field, Denied._LastSurface) != MiddlePlate);

    TestTrue(TEXT("stopping at or before the denied plate's western edge"),
        Denied._HitLocation.X <= kRayMiddle.X);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A ray STANDING on refused ground is refused where it stands, ahead of the plate early-out.
//
// Falsified by moving the start check below that early-out: a segment that never leaves the start's
// own plate is answered without a single step, so the early-out would report Success for a ray whose
// whole length lies on ground the query refused.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DeniedPlates_RaycastFromADeniedPlateIsBlocked,
    "CkTests.UnitTests.CkGroundNav.DeniedPlates.RaycastFromADeniedPlateIsBlocked",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DeniedPlates_RaycastFromADeniedPlateIsBlocked::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_deniedplates;

    auto Field = FCk_GroundNav_FieldPtr{};

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_SharedFourPillarSlabScene(Field)))
    { return false; }

    const auto StartPlate = TryGet_FlatPlateAt(*Field, kRayStart);

    if (NOT TestTrue(TEXT("the lane's start stands on a plate"), StartPlate != INDEX_NONE))
    { return false; }

    // Short enough to stay on the start's own plate, which is what routes the query through the early
    // out this case exists to get in front of.
    const auto ShortEnd = kRayStart + FVector{kShortRayLengthUu, 0.0, 0.0};

    const auto Clear = Get_SurfaceRaycast(*Field, Make_RaycastQuery(kRayStart, ShortEnd));

    if (NOT TestEqual(TEXT("the short segment is clear with no veto"),
        Clear._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    auto DeniedQuery = Make_RaycastQuery(kRayStart, ShortEnd);
    DeniedQuery._DeniedPlates.Add(StartPlate);

    const auto Denied = Get_SurfaceRaycast(*Field, DeniedQuery);

    TestEqual(TEXT("a ray standing on refused ground is Blocked"),
        Denied._Status, ECk_NavSurface_QueryStatus::Blocked);

    TestTrue(TEXT("and it never reached the end it was asked about"),
        Denied._HitLocation != ShortEnd);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
