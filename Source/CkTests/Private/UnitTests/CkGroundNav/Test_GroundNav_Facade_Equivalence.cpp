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

#include "CkNavigation/CkNavigation_Log.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"
#include "CkNavigation/Settings/CkNav_ProjectSettings.h"

#include <Engine/World.h>

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_facade
{
    using ck::groundnav::FCk_GroundNav_BoundaryQuery;
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::FCk_GroundNav_ReachabilityQuery;
    using ck::groundnav::FCk_GroundNav_ReachabilityResult;
    using ck::groundnav::ECk_GroundNav_Reachability;
    using ck::groundnav::Get_BoundarySegments;
    using ck::groundnav::Get_IsReachable;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_SurfaceRaycast;

    constexpr auto InformEngineOfWorld = false;

    constexpr auto kPointCount = 1000;
    constexpr auto kSeed = 20260902;

    constexpr auto kBoundaryRadiusUu = 300.0f;

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

    ck::groundnav::world_fields::Publish(World, FCk_Handle{}, Baked, {});

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
    }

    World->DestroyWorld(InformEngineOfWorld);

    ck::nav::Display
    (
        TEXT("NavSurface facade equivalence over [{}] points: projection [{}], raycast [{}], "
             "boundary [{}], reachability [{}] mismatches"),
        Points.Num(), ProjectionMismatches, RaycastMismatches, BoundaryMismatches, ReachabilityMismatches
    );

    TestEqual(TEXT("every facade projection equals the direct GroundNav projection"),
        ProjectionMismatches, 0);
    TestEqual(TEXT("every facade raycast equals the direct GroundNav raycast"),
        RaycastMismatches, 0);
    TestEqual(TEXT("every facade boundary answer equals the direct GroundNav one, segment for segment"),
        BoundaryMismatches, 0);
    TestEqual(TEXT("every facade reachability answer equals the mapped direct GroundNav one"),
        ReachabilityMismatches, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
