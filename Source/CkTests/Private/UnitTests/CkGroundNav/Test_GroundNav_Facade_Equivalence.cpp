// The provider dispatch, checked where it can actually be wrong: the ANSWER.
//
// A facade that resolves the right provider and then maps its query or its result badly is worse than
// one that resolves the wrong provider — it produces plausible numbers. So this asks the same question
// twice over one baked field, once through UCk_Utils_NavSurface_UE with the world set to GroundNav and
// once by calling the GroundNav query directly with the parameters the adapter is specified to build,
// and requires the two to agree exactly over a thousand seeded points.
//
// The provider assertion is up front and fatal on purpose: a world that could not take the provider
// would fall back to the project default, and every comparison below would be measuring the wrong
// provider.

#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_QueryTypes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Boundary.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_SearchTypes.h"

#include "CkNavigation/CkNavigation_Log.h"
#include "CkNavigation/NavSurface/CkNavFilterDefinition_Registry.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"
#include "CkNavigation/Settings/CkNav_ProjectSettings.h"

#include <Engine/World.h>
#include <NativeGameplayTags.h>

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// The area this test paints and the filter that refuses it. Registered by the test rather than by a
// module registrar, because what is under test is the ADAPTER's compilation of a definition and not
// which module happens to author one.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Facade_Area, "CkTests.GroundNav.Facade.Area");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Facade_Filter, "CkTests.GroundNav.Facade.Filter");

namespace ck_test_groundnav_facade
{
    using ck::groundnav::FCk_GroundNav_BoundaryQuery;
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_ClosestBoundaryQuery;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::FCk_GroundNav_ReachabilityQuery;
    using ck::groundnav::FCk_GroundNav_ReachabilityResult;
    using ck::groundnav::ECk_GroundNav_Reachability;
    using ck::groundnav::Get_BoundarySegments;
    using ck::groundnav::Get_ClosestBoundary;
    using ck::groundnav::Get_IsReachable;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_SurfaceRaycast;

    constexpr auto InformEngineOfWorld = false;

    constexpr auto kPointCount = 1000;
    constexpr auto kSeed = 20260902;

    constexpr auto kBoundaryRadiusUu = 300.0f;

    // The path pair runs over a PREFIX of the same seeded points rather than all of them: every other
    // comparison here is a single field read, while a path is a whole graph search, and a thousand of
    // those turns a unit test into a benchmark. A hundred of the same deterministic points still
    // covers ground, hole, wall, deck and open floor, and the pairs it takes are the first hundred
    // the seed produced - so a failure names an index that can be found again.
    constexpr auto kPathPairCount = 100;

    // ------------------------------------------------------------------------------------------------
    // The U2 cost-cap case's own scene: one flat floor, two ends well inside its single tile.
    // ------------------------------------------------------------------------------------------------

    constexpr auto kCostCapPlateMultiplier = 3.0f;

    // Half of what the priced ray costs and more than the unpriced one does, so the two answer
    // differently and the difference is arithmetic rather than a threshold that happens to sit right.
    constexpr auto kCostCapLengthUu = 500.0f;
    constexpr auto kCostCapMaxCost = 750.0f;

    inline auto Get_CostCapStart() -> FVector
    {
        return FVector{200.0, 200.0, 0.0};
    }

    inline auto Get_CostCapEnd() -> FVector
    {
        return FVector{200.0 + static_cast<double>(kCostCapLengthUu), 200.0, 0.0};
    }

    // The search box the projection and boundary queries carry, so their expectation does not move
    // with the project's own projection extents.
    inline auto Get_SearchHalfExtents() -> FVector
    {
        return FVector{100.0, 100.0, 300.0};
    }

    // The tolerance the adapter is specified to resolve a walk's, a raycast's and a reachability
    // query's ends with — the project's vertical reach, which the neutral shapes cannot carry.
    inline auto Get_VerticalToleranceUu() -> float
    {
        return static_cast<float>(UCk_Utils_Nav_Settings_UE::Get_NavQueryProjectionExtentVec().Z);
    }

    inline auto Get_ExpectedReachability(
        const FCk_GroundNav_ReachabilityResult& InResult) -> ECk_NavSurface_Reachability
    {
        switch (InResult._Status)
        {
            case ECk_NavSurface_QueryStatus::NoSurface:
            {
                return ECk_NavSurface_Reachability::Unreachable;
            }
            case ECk_NavSurface_QueryStatus::Success:
            {
                switch (InResult._Reachability)
                {
                    case ECk_GroundNav_Reachability::PossiblyReachable:
                    {
                        return ECk_NavSurface_Reachability::Reachable;
                    }
                    case ECk_GroundNav_Reachability::Unreachable:
                    {
                        return ECk_NavSurface_Reachability::Unreachable;
                    }
                    default:
                    {
                        return ECk_NavSurface_Reachability::Unknown_ProviderNotReady;
                    }
                }
            }
            default:
            {
                return ECk_NavSurface_Reachability::Unknown_ProviderNotReady;
            }
        }
    }

    // ------------------------------------------------------------------------------------------------
    // The filtered case's own scene: the gym's four-pillar slab, with one plate PAINTED by hand.
    // ------------------------------------------------------------------------------------------------

    // The ray's lane, off the field's 25 uu lattice from origin (-2000, -1600) so no coordinate sits on
    // a cell line, and south of every pillar - the southernmost reaches Y -175 - so it is clear floor.
    // Plates are TILE-LOCAL and the tile columns are 800 uu from X -2000, so these three points are on
    // three different plates by construction.
    constexpr auto kFilterLaneY = -612.0;
    constexpr auto kFilterLaneStartX = -1638.0;
    constexpr auto kFilterLaneEndX = 1638.0;
    constexpr auto kFilterLaneMiddleX = 12.0;

    inline auto Get_FilterLaneStart() -> FVector
    {
        return FVector{kFilterLaneStartX, kFilterLaneY, ck_test_groundnav_queryfixtures::kGroundZ};
    }

    inline auto Get_FilterLaneEnd() -> FVector
    {
        return FVector{kFilterLaneEndX, kFilterLaneY, ck_test_groundnav_queryfixtures::kGroundZ};
    }

    inline auto Get_FilterLaneMiddle() -> FVector
    {
        return FVector{kFilterLaneMiddleX, kFilterLaneY, ck_test_groundnav_queryfixtures::kGroundZ};
    }

    /**
     * The flat plate under a point, and INDEX_NONE where the point stands on none.
     *
     * A point of no size, so the answer is about the ground rather than about what fits on it.
     */
    inline auto TryGet_FlatPlateAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> int32
    {
        auto Query = ck::groundnav::FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = ck_test_groundnav_queryfixtures::kStepHeight;

        const auto Result = ck::groundnav::Get_IsNavigable(InField, Query);

        if (NOT Result.Get_IsSuccess())
        { return INDEX_NONE; }

        return ck::groundnav::Get_FlatPlateIndex(
            InField, Result._Surface._TileIndex, Result._Surface._PlateIndex);
    }

    /**
     * Paints one plate with an area tag, by hand.
     *
     * By hand rather than through a markup record for the reason the cost-cap case above prices by
     * hand: what is under test is whether the ADAPTER translates an area tag into plates at all, and a
     * paint would put a bake and a re-derive between the tag and the query.
     */
    inline auto Do_PaintPlate(
        FCk_GroundNav_Field& InOutField,
        int32                InFlatPlate,
        const FGameplayTag&  InAreaTag) -> bool
    {
        auto TileIndex = int32{INDEX_NONE};
        auto PlateIndex = int32{INDEX_NONE};

        if (NOT ck::groundnav::Get_TileAndPlate(InOutField, InFlatPlate, TileIndex, PlateIndex))
        { return false; }

        if (NOT InOutField._Tiles.IsValidIndex(TileIndex))
        { return false; }

        auto& PlateField = InOutField._Tiles[TileIndex]._Plates;

        if (NOT PlateField._Plates.IsValidIndex(PlateIndex))
        { return false; }

        PlateField._Plates[PlateIndex]._AreaPolicyIndex =
            PlateField._AreaPolicies.Emplace(FGameplayTagContainer{InAreaTag});

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Facade_Equivalence,
    "CkTests.UnitTests.CkGroundNav.Facade.Equivalence_FacadeAnswersEqualDirectCalls",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Facade_Equivalence::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_facade;

    auto Baked = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(*Baked)))
    { return false; }

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkGroundNavFacadeEquivalence")});

    if (NOT TestNotNull(TEXT("the probe world was created"), World))
    { return false; }

    ck::groundnav::world_fields::Publish(World, FCk_Handle{}, Baked, {}, ck::groundnav::world_fields::FCk_GroundNav_PublishClaim::Geometry());

    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    const auto ProviderTookEffect =
        UCk_Utils_NavSurface_UE::Get_Provider(World) == ECk_NavSurface_Provider::GroundNav;

    if (NOT TestTrue(
        TEXT("the world accepted GroundNav as its navigation-surface provider (without this every "
             "comparison below would silently be Recast)"), ProviderTookEffect))
    {
        World->DestroyWorld(InformEngineOfWorld);
        return false;
    }

    const auto Points = Make_RandomPointsOverField(*Baked, kPointCount, kSeed);

    const auto SearchHalfExtents = Get_SearchHalfExtents();
    const auto VerticalToleranceUu = Get_VerticalToleranceUu();

    auto ProjectionMismatches = 0;
    auto RaycastMismatches = 0;
    auto BoundaryMismatches = 0;
    auto ReachabilityMismatches = 0;
    auto PathMismatches = 0;
    auto WallDistanceMismatches = 0;

    for (auto Index = 0; Index < Points.Num(); ++Index)
    {
        const auto& Point = Points[Index];

        // ------------------------------------------------------------------------------------------
        // Projection
        // ------------------------------------------------------------------------------------------
        {
            auto NeutralQuery = FCk_NavSurface_ProjectionQuery{Point};
            NeutralQuery.Set_SearchHalfExtents(SearchHalfExtents);
            NeutralQuery.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

            const auto FacadeResult = UCk_Utils_NavSurface_UE::Try_ProjectPoint(World, NeutralQuery);

            auto DirectQuery = FCk_GroundNav_ProjectionQuery{};
            DirectQuery._Location = Point;
            DirectQuery._HorizontalExtentUu = static_cast<float>(SearchHalfExtents.X);
            DirectQuery._UpExtentUu = static_cast<float>(SearchHalfExtents.Z);
            DirectQuery._DownExtentUu = static_cast<float>(SearchHalfExtents.Z);
            DirectQuery._Mode = ECk_NavSurface_ProjectionMode::Closest;

            const auto DirectResult = Get_ProjectPoint(*Baked, DirectQuery);

            if (FacadeResult.Get_Status() != DirectResult._Status ||
                FacadeResult.Get_Location() != DirectResult._Location ||
                FacadeResult.Get_SurfaceNormal() != DirectResult._SurfaceNormal)
            { ++ProjectionMismatches; }
        }

        // ------------------------------------------------------------------------------------------
        // Boundary
        // ------------------------------------------------------------------------------------------
        {
            auto NeutralQuery = FCk_NavSurface_BoundaryQuery{Point, kBoundaryRadiusUu};
            NeutralQuery.Set_SearchHalfExtents(SearchHalfExtents);

            auto FacadeSegments = TArray<FCk_NavSurface_BoundarySegment>{};
            const auto FacadeStatus =
                UCk_Utils_NavSurface_UE::Get_BoundarySegments(World, NeutralQuery, FacadeSegments);

            auto DirectQuery = FCk_GroundNav_BoundaryQuery{};
            DirectQuery._Location = Point;
            DirectQuery._RadiusUu = kBoundaryRadiusUu;
            DirectQuery._VerticalWindowUu = static_cast<float>(SearchHalfExtents.Z);
            DirectQuery._MaxSegments = 0;

            auto DirectSegments = TArray<FCk_GroundNav_BoundarySegment>{};
            const auto DirectStatus = Get_BoundarySegments(*Baked, DirectQuery, DirectSegments);

            auto BoundaryAgrees = FacadeStatus == DirectStatus &&
                                  FacadeSegments.Num() == DirectSegments.Num();

            for (auto SegmentIndex = 0; BoundaryAgrees && SegmentIndex < DirectSegments.Num(); ++SegmentIndex)
            {
                const auto& FacadeSegment = FacadeSegments[SegmentIndex];
                const auto& DirectSegment = DirectSegments[SegmentIndex];

                const auto ExpectedInwardNormal = FVector{
                    DirectSegment._InwardNormalXY.X, DirectSegment._InwardNormalXY.Y, 0.0};

                BoundaryAgrees = FacadeSegment.Get_Start() == DirectSegment._Start &&
                                 FacadeSegment.Get_End() == DirectSegment._End &&
                                 FacadeSegment.Get_InwardNormal() == ExpectedInwardNormal;
            }

            if (NOT BoundaryAgrees)
            { ++BoundaryMismatches; }
        }

        // ------------------------------------------------------------------------------------------
        // Distance to the nearest wall
        // ------------------------------------------------------------------------------------------
        {
            const auto FacadeWall = UCk_Utils_NavSurface_UE::Try_FindDistanceToWall(
                World, FCk_NavSurface_WallDistanceQuery{Point, kBoundaryRadiusUu});

            auto DirectQuery = FCk_GroundNav_ClosestBoundaryQuery{};
            DirectQuery._Location = Point;
            DirectQuery._MaxRadiusUu = kBoundaryRadiusUu;
            DirectQuery._VerticalWindowUu = VerticalToleranceUu;

            const auto DirectWall = Get_ClosestBoundary(*Baked, DirectQuery);

            const auto ExpectedFoundWall = DirectWall.Get_IsSuccess();

            // NoSurface is the adapter's one fold: the ring search answers it both for a point on no
            // ground and for a point with no wall inside the radius, so it surfaces as a Success that
            // found nothing - which is what Recast answers to the same pair.
            const auto ExpectedStatus = DirectWall._Status == ECk_NavSurface_QueryStatus::NoSurface
                ? ECk_NavSurface_QueryStatus::Success
                : DirectWall._Status;

            const auto ExpectedDistanceUu = ExpectedFoundWall ? DirectWall._DistanceUu : 0.0f;
            const auto ExpectedClosestPoint = ExpectedFoundWall ? DirectWall._ClosestPoint : FVector::ZeroVector;

            if (FacadeWall.Get_Status() != ExpectedStatus ||
                FacadeWall.Get_FoundWall() != ExpectedFoundWall ||
                FacadeWall.Get_DistanceUu() != ExpectedDistanceUu ||
                FacadeWall.Get_ClosestWallPoint() != ExpectedClosestPoint)
            { ++WallDistanceMismatches; }
        }

        // ------------------------------------------------------------------------------------------
        // Raycast and reachability, between this point and the next
        // ------------------------------------------------------------------------------------------
        if (Index + 1 < Points.Num())
        {
            const auto& NextPoint = Points[Index + 1];

            const auto FacadeRaycast = UCk_Utils_NavSurface_UE::Try_SurfaceRaycast(
                World, FCk_NavSurface_RaycastQuery{Point, NextPoint});

            auto DirectRaycastQuery = FCk_GroundNav_RaycastQuery{};
            DirectRaycastQuery._Start = Point;
            DirectRaycastQuery._End = NextPoint;
            DirectRaycastQuery._StartVerticalToleranceUu = VerticalToleranceUu;

            // What the adapter is specified to build: the cap is a COST cap, so the ground under the
            // ray has to be priced at what it was authored with rather than at a flat 1.0.
            DirectRaycastQuery._UseBakedPlateCost = true;

            const auto DirectRaycast = Get_SurfaceRaycast(*Baked, DirectRaycastQuery);

            if (FacadeRaycast.Get_Status() != DirectRaycast._Status ||
                FacadeRaycast.Get_HitLocation() != DirectRaycast._HitLocation)
            { ++RaycastMismatches; }

            const auto FacadeReachability = UCk_Utils_NavSurface_UE::Get_IsReachable(
                World, FCk_NavSurface_ReachabilityQuery{Point, NextPoint});

            auto DirectReachabilityQuery = FCk_GroundNav_ReachabilityQuery{};
            DirectReachabilityQuery._Start = Point;
            DirectReachabilityQuery._End = NextPoint;
            DirectReachabilityQuery._VerticalToleranceUu = VerticalToleranceUu;

            const auto ExpectedReachability =
                Get_ExpectedReachability(Get_IsReachable(*Baked, DirectReachabilityQuery));

            if (FacadeReachability != ExpectedReachability)
            { ++ReachabilityMismatches; }
        }

        // ------------------------------------------------------------------------------------------
        // A whole route, between this point and the next
        // ------------------------------------------------------------------------------------------
        if (Index + 1 < Points.Num() && Index < kPathPairCount)
        {
            const auto& NextPoint = Points[Index + 1];

            auto NeutralQuery = FCk_NavSurface_PathQuery{Point, NextPoint};
            NeutralQuery.Set_SearchHalfExtents(SearchHalfExtents);

            // The direct call below names no radius, so it runs at FCk_GroundNav_QueryAgent's own
            // zero default - pinned here rather than left implicit, so the pair stays byte-equal on
            // purpose and not because two unrelated defaults happen to agree.
            NeutralQuery.Set_AgentRadiusUu(0.0f);

            // The direct Get_PathPlan below runs at FCk_GroundNav_PathPostParams' own default
            // _CornerOffsetK, and ProviderDefault is exactly the policy that leaves K at that default
            // - pinned here so the pair stays byte-equal on purpose rather than by coincidence.
            NeutralQuery.Set_CornerOffset(ECk_NavSurface_CornerOffset::ProviderDefault);

            const auto FacadePath = UCk_Utils_NavSurface_UE::Try_FindPathSync(World, NeutralQuery);

            // The one-shot the adapter is specified to stand up: a begin, then ONE slice with both
            // ceilings off, over the same field, with the ends resolved through the same vertical
            // reach. The two steps are driven here as well so the pair compares like with like.
            auto DirectPathQuery = FCk_GroundNav_PathQuery{};
            DirectPathQuery._Start = Point;
            DirectPathQuery._Goal = NextPoint;
            DirectPathQuery._VerticalToleranceUu = static_cast<float>(SearchHalfExtents.Z);

            auto DirectSearch = FCk_GroundNav_PathSearch{};

            const auto DirectBeginStatus = DirectSearch.Request_Begin(Baked, DirectPathQuery);

            if (DirectBeginStatus == ECk_GroundNav_PathStatus::InProgress)
            { DirectSearch.ContinueSearch(FCk_GroundNav_PathSliceParams{}); }

            const auto DirectStatus = DirectSearch.Get_Status();

            const auto DirectIsSuccess = DirectStatus == ECk_GroundNav_PathStatus::Ready;

            const auto ExpectedStatus = DirectIsSuccess
                ? ECk_NavSurface_QueryStatus::Success
                : DirectStatus == ECk_GroundNav_PathStatus::Unbuilt
                    ? ECk_NavSurface_QueryStatus::Unbuilt
                    : (DirectStatus == ECk_GroundNav_PathStatus::NoStartSurface ||
                       DirectStatus == ECk_GroundNav_PathStatus::NoGoalSurface)
                        ? ECk_NavSurface_QueryStatus::NoSurface
                        : ECk_NavSurface_QueryStatus::Blocked;

            auto PathAgrees = FacadePath.Get_Status() == ExpectedStatus &&
                              NOT FacadePath.Get_IsPartial();

            if (PathAgrees && DirectIsSuccess)
            {
                auto PostParams = FCk_GroundNav_PathPostParams{};
                PostParams._VerticalToleranceUu = DirectPathQuery._VerticalToleranceUu;
                PostParams._AgentLocation = Point;

                const auto DirectPlan = Get_PathPlan(DirectSearch.Get_Result(), *Baked, PostParams);

                PathAgrees = FacadePath.Get_Waypoints().Num() == DirectPlan._Waypoints.Num();

                for (auto WaypointIndex = 0;
                     PathAgrees && WaypointIndex < DirectPlan._Waypoints.Num();
                     ++WaypointIndex)
                {
                    PathAgrees = FacadePath.Get_Waypoints()[WaypointIndex] ==
                                 DirectPlan._Waypoints[WaypointIndex]._Location;
                }
            }
            else if (PathAgrees)
            {
                // Every non-Success status answers with no route at all - a route that is not a route
                // is never a shorter route.
                PathAgrees = FacadePath.Get_Waypoints().IsEmpty();
            }

            if (NOT PathAgrees)
            { ++PathMismatches; }
        }
    }

    World->DestroyWorld(InformEngineOfWorld);

    ck::nav::Display
    (
        TEXT("NavSurface facade equivalence over [{}] points ([{}] path pairs): projection [{}], "
             "raycast [{}], boundary [{}], reachability [{}], path [{}], wall distance [{}] mismatches"),
        Points.Num(), kPathPairCount, ProjectionMismatches, RaycastMismatches, BoundaryMismatches,
        ReachabilityMismatches, PathMismatches, WallDistanceMismatches
    );

    TestEqual(TEXT("every facade projection equals the direct GroundNav projection"),
        ProjectionMismatches, 0);
    TestEqual(TEXT("every facade raycast equals the direct GroundNav raycast"),
        RaycastMismatches, 0);
    TestEqual(TEXT("every facade boundary answer equals the direct GroundNav one, segment for segment"),
        BoundaryMismatches, 0);
    TestEqual(TEXT("every facade reachability answer equals the mapped direct GroundNav one"),
        ReachabilityMismatches, 0);
    TestEqual(TEXT("every facade path equals the direct GroundNav one-shot search, waypoint for waypoint"),
        PathMismatches, 0);
    TestEqual(TEXT("every facade wall distance equals the direct GroundNav closest-boundary answer"),
        WallDistanceMismatches, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The cost cap the facade's raycast query gained, checked where it can actually be wrong: the ground
// under the ray is PRICED, so the cap is a cost cap and not a distance cap.
//
// Both halves of the plumbing are falsified here at once. Drop _MaxCost from the adapter and the
// capped ray answers exactly what the uncapped one does; keep it but leave _UseBakedPlateCost off and
// every plate weighs 1.0, the accumulation is the segment's bare length, and the cap admits ground the
// cost model was authored to refuse. Only both together make the two answers differ.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Facade_CostCappedRaycast,
    "CkTests.UnitTests.CkGroundNav.Facade.Equivalence_CappedRaycastRefusesPricedGroundTheUncappedOneAdmits",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Facade_CostCappedRaycast::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_facade;

    auto Baked = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(*Baked)))
    { return false; }

    // Priced by hand rather than through markup: what is under test is whether the ADAPTER reads the
    // field's price at all, and a paint would put a bake and a re-derive between the price and the ray.
    auto PricedPlateCount = 0;

    for (auto& Tile : Baked->_Tiles)
    {
        for (auto& Plate : Tile._Plates._Plates)
        {
            Plate._CostMultiplier = kCostCapPlateMultiplier;
            ++PricedPlateCount;
        }
    }

    if (NOT TestTrue(TEXT("the flat scene baked ground for the price to be put on"), PricedPlateCount > 0))
    { return false; }

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkGroundNavFacadeCostCap")});

    if (NOT TestNotNull(TEXT("the probe world was created"), World))
    { return false; }

    ck::groundnav::world_fields::Publish(World, FCk_Handle{}, Baked, {}, ck::groundnav::world_fields::FCk_GroundNav_PublishClaim::Geometry());

    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    if (NOT TestTrue(TEXT("the world accepted GroundNav as its navigation-surface provider"),
        UCk_Utils_NavSurface_UE::Get_Provider(World) == ECk_NavSurface_Provider::GroundNav))
    {
        World->DestroyWorld(InformEngineOfWorld);
        return false;
    }

    const auto Start = Get_CostCapStart();
    const auto End = Get_CostCapEnd();

    const auto Uncapped = UCk_Utils_NavSurface_UE::Try_SurfaceRaycast(
        World, FCk_NavSurface_RaycastQuery{Start, End});

    const auto Capped = UCk_Utils_NavSurface_UE::Try_SurfaceRaycast(
        World, FCk_NavSurface_RaycastQuery{Start, End}.Set_MaxCost(kCostCapMaxCost));

    World->DestroyWorld(InformEngineOfWorld);

    // Stated before the discriminating assertion so a later failure says WHICH half moved: the segment
    // is over open floor, so nothing but the cap can refuse it.
    TestEqual(TEXT("the uncapped ray walks the priced floor end to end"),
        Uncapped.Get_Status(), ECk_NavSurface_QueryStatus::Success);

    // The cap is 750 and the priced ray costs 3 x 500 = 1500, so it stops halfway; an unpriced ray
    // would cost 500 and clear the same cap outright.
    TestEqual(TEXT("and the capped ray refuses the very same segment, because the ground is priced"),
        Capped.Get_Status(), ECk_NavSurface_QueryStatus::Blocked);

    TestTrue(TEXT("stopping short of the end it was asked to reach"),
        Capped.Get_HitLocation() != End);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The QUERY FILTER, checked where it can actually be wrong: the answer.
//
// A filter tag names a provider-neutral definition, and this provider has to compile that definition
// into the only two things a grounded query understands - what a plate costs, and which plates the
// query may not enter. So the question is whether the facade's filtered answer is the SAME answer the
// direct call gives when handed the denied set that definition compiles to.
//
// Both halves are falsifiable on their own. Drop the filter from Do_SurfaceRaycast and the filtered
// ray answers exactly what the unfiltered one does, which the first pair catches. Compile the wrong
// plates - miss the required/excluded matching, or key the tables by tile-local plate instead of flat
// plate - and the filtered answer stops equalling the direct call with the RIGHT set, which the
// second half of each pair catches.
//
// The painted plate is chosen by asking the field which plate is under a point, never written down: a
// flat plate id is a product of the decomposition and the tile lattice, so a literal would be a claim
// about how the baker cuts this slab today rather than about the filter.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Facade_FilteredEquivalence,
    "CkTests.UnitTests.CkGroundNav.Facade.Equivalence_FilteredAnswersEqualTheDirectCallWithTheSameDeniedSet",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Facade_FilteredEquivalence::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_facade;

    auto Baked = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the four-pillar slab bakes"), Bake_FourPillarSlabScene(*Baked)))
    { return false; }

    const auto LaneStart = Get_FilterLaneStart();
    const auto LaneEnd = Get_FilterLaneEnd();

    const auto LaneStartPlate = TryGet_FlatPlateAt(*Baked, LaneStart);
    const auto PaintedPlate = TryGet_FlatPlateAt(*Baked, Get_FilterLaneMiddle());

    if (NOT TestTrue(TEXT("the lane's start and middle stand on different plates"),
        LaneStartPlate != INDEX_NONE && PaintedPlate != INDEX_NONE && LaneStartPlate != PaintedPlate))
    { return false; }

    if (NOT TestTrue(TEXT("the middle plate takes the area paint"),
        Do_PaintPlate(*Baked, PaintedPlate, TAG_CkTests_GroundNav_Facade_Area.GetTag())))
    { return false; }

    auto Definition = FCk_NavFilter_Definition{};
    Definition.Set_ExcludedAreaTags(
        FGameplayTagContainer{TAG_CkTests_GroundNav_Facade_Area.GetTag()});

    ck::nav_surface::Register_FilterDefinition(
        TAG_CkTests_GroundNav_Facade_Filter.GetTag(), Definition);

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkGroundNavFacadeFilter")});

    if (NOT TestNotNull(TEXT("the probe world was created"), World))
    { return false; }

    ck::groundnav::world_fields::Publish(World, FCk_Handle{}, Baked, {}, ck::groundnav::world_fields::FCk_GroundNav_PublishClaim::Geometry());

    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    if (NOT TestTrue(TEXT("the world accepted GroundNav as its navigation-surface provider"),
        UCk_Utils_NavSurface_UE::Get_Provider(World) == ECk_NavSurface_Provider::GroundNav))
    {
        World->DestroyWorld(InformEngineOfWorld);
        return false;
    }

    // ----------------------------------------------------------------------------------------------
    // A ray down the lane: unfiltered it is clear, filtered it must stop, and where it stops must be
    // where the direct call carrying the same denied set stops.
    // ----------------------------------------------------------------------------------------------

    const auto UnfilteredRay = UCk_Utils_NavSurface_UE::Try_SurfaceRaycast(
        World, FCk_NavSurface_RaycastQuery{LaneStart, LaneEnd});

    const auto FilteredRay = UCk_Utils_NavSurface_UE::Try_SurfaceRaycast(
        World, FCk_NavSurface_RaycastQuery{LaneStart, LaneEnd}
            .Set_QueryFilter(TAG_CkTests_GroundNav_Facade_Filter.GetTag()));

    auto DirectRayQuery = FCk_GroundNav_RaycastQuery{};
    DirectRayQuery._Start = LaneStart;
    DirectRayQuery._End = LaneEnd;
    DirectRayQuery._StartVerticalToleranceUu = Get_VerticalToleranceUu();
    DirectRayQuery._UseBakedPlateCost = true;
    DirectRayQuery._DeniedPlates.Add(PaintedPlate);

    const auto DirectRay = Get_SurfaceRaycast(*Baked, DirectRayQuery);

    // ----------------------------------------------------------------------------------------------
    // A route down the same lane, which the paint puts a hole in the middle of.
    // ----------------------------------------------------------------------------------------------

    auto NeutralPathQuery = FCk_NavSurface_PathQuery{LaneStart, LaneEnd};
    NeutralPathQuery.Set_SearchHalfExtents(Get_SearchHalfExtents());
    NeutralPathQuery.Set_AgentRadiusUu(0.0f);
    NeutralPathQuery.Set_CornerOffset(ECk_NavSurface_CornerOffset::ProviderDefault);

    const auto UnfilteredPath = UCk_Utils_NavSurface_UE::Try_FindPathSync(World, NeutralPathQuery);

    auto FilteredPathQuery = NeutralPathQuery;
    FilteredPathQuery.Set_QueryFilter(TAG_CkTests_GroundNav_Facade_Filter.GetTag());

    const auto FilteredPath = UCk_Utils_NavSurface_UE::Try_FindPathSync(World, FilteredPathQuery);

    // The one-shot the adapter is specified to stand up, carrying the denied set the definition
    // compiles to and nothing else.
    auto DirectPathQuery = FCk_GroundNav_PathQuery{};
    DirectPathQuery._Start = LaneStart;
    DirectPathQuery._Goal = LaneEnd;
    DirectPathQuery._VerticalToleranceUu = static_cast<float>(Get_SearchHalfExtents().Z);
    DirectPathQuery._Cost._DeniedPlates.Add(PaintedPlate);

    auto DirectSearch = FCk_GroundNav_PathSearch{};

    if (DirectSearch.Request_Begin(Baked, DirectPathQuery) == ECk_GroundNav_PathStatus::InProgress)
    { DirectSearch.ContinueSearch(FCk_GroundNav_PathSliceParams{}); }

    const auto DirectPathStatus = DirectSearch.Get_Status();

    auto DirectWaypoints = TArray<FVector>{};

    if (DirectPathStatus == ECk_GroundNav_PathStatus::Ready)
    {
        auto PostParams = FCk_GroundNav_PathPostParams{};
        PostParams._VerticalToleranceUu = DirectPathQuery._VerticalToleranceUu;
        PostParams._AgentLocation = LaneStart;
        PostParams._Cost._DeniedPlates = DirectPathQuery._Cost._DeniedPlates;

        const auto DirectPlan = Get_PathPlan(DirectSearch.Get_Result(), *Baked, PostParams);

        for (const auto& Waypoint : DirectPlan._Waypoints)
        { DirectWaypoints.Emplace(Waypoint._Location); }
    }

    World->DestroyWorld(InformEngineOfWorld);

    ck::nav::Display
    (
        TEXT("NavSurface filtered equivalence: painted plate [{}], ray unfiltered [{}] filtered [{}] "
             "direct [{}], path unfiltered [{}] filtered [{}] direct [{}]"),
        PaintedPlate, UnfilteredRay.Get_Status(), FilteredRay.Get_Status(), DirectRay._Status,
        UnfilteredPath.Get_Status(), FilteredPath.Get_Status(), DirectPathStatus
    );

    // Stated before the discriminating assertions so a later failure says WHICH half moved: with no
    // filter the lane is open floor end to end, so nothing but the filter can refuse it.
    TestEqual(TEXT("the unfiltered ray walks the lane end to end"),
        UnfilteredRay.Get_Status(), ECk_NavSurface_QueryStatus::Success);

    TestEqual(TEXT("and the unfiltered route crosses it"),
        UnfilteredPath.Get_Status(), ECk_NavSurface_QueryStatus::Success);

    TestEqual(TEXT("the filtered ray refuses the very same segment, because the filter denies the "
                   "ground in the middle of it"),
        FilteredRay.Get_Status(), ECk_NavSurface_QueryStatus::Blocked);

    TestEqual(TEXT("and it stops exactly where the direct call with the same denied set stops"),
        FilteredRay.Get_HitLocation(), DirectRay._HitLocation);

    TestEqual(TEXT("the direct call agrees it is blocked"),
        DirectRay._Status, ECk_NavSurface_QueryStatus::Blocked);

    // The route may go round the painted plate or refuse - either is a correct answer about this
    // slab - but whichever it is, it must be the answer the direct call gives.
    const auto ExpectedPathStatus = DirectPathStatus == ECk_GroundNav_PathStatus::Ready
        ? ECk_NavSurface_QueryStatus::Success
        : ECk_NavSurface_QueryStatus::Blocked;

    TestEqual(TEXT("the filtered route answers what the direct call with the same denied set answers"),
        FilteredPath.Get_Status(), ExpectedPathStatus);

    TestEqual(TEXT("waypoint for waypoint"),
        FilteredPath.Get_Waypoints().Num(), DirectWaypoints.Num());

    for (auto Index = 0; Index < DirectWaypoints.Num() && Index < FilteredPath.Get_Waypoints().Num(); ++Index)
    {
        TestEqual(TEXT("the filtered route's waypoint equals the direct one"),
            FilteredPath.Get_Waypoints()[Index], DirectWaypoints[Index]);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
