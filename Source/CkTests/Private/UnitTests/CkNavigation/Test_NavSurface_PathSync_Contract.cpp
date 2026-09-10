// The two capabilities a route needs from the navigation surface - a synchronous path and the
// distance to the nearest wall - checked where a headless world can check them.
//
// The first pin is structural, and it is the one that matters most: both are REQUIRED entries. A
// provider table that fills every other capability and leaves either of these empty must not
// register, because Register_Provider refuses an incomplete table outright - so a provider adapter
// that gained the entries in the header and not in its own table would take the WHOLE of navigation
// down at module startup rather than failing to compile. That is what this asks about first.
//
// The second pins the answer with nothing to answer from: both capabilities say NoProvider on a world
// that has no navigation data, and say it with an empty route rather than with a plausible one.
//
// The third is the thread contract, which is the OPPOSITE of Get_BoundarySegments' (see
// Test_NavSurface_BoundarySegments_ThreadContract.cpp): these two are GAME THREAD ONLY, because both
// providers answer them by reading live state - a live ARecastNavMesh on one side, and on the other a
// search stood up per call. There is deliberately no worker probe here: a test that called them from
// a worker would be asserting the contract does not hold. What is pinned instead is that the answers
// below were measured on the thread the contract names.
//
// What is NOT covered here: either capability over BUILT ground. That needs a navmesh, and therefore
// a PIE world - the GroundNav half of it is pinned over a baked field in
// UnitTests/CkGroundNav/Test_GroundNav_Facade_Equivalence.cpp instead.

#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/Nav/CkNav_Algorithm.h"
#include "CkNavigation/Nav/CkNav_Fragment.h"
#include "CkNavigation/Nav/CkNav_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_ProviderTable.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"
#include "CkNavigation/NavSurface/Recast/CkNavSurface_RecastAdapter.h"

#include "../CkUnitTest_Common.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include <UObject/UnrealType.h>

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_nav_surface_pathsync
{
    constexpr auto InformEngineOfWorld = false;

    constexpr auto kWallSearchRadiusUu = 200.0f;

    // Every capability, each answering its own default. The bodies are irrelevant - completeness asks
    // only whether a callable is bound - so they are the shortest thing that satisfies the signature.
    auto Make_CompleteTable() -> FCk_NavSurface_ProviderTable
    {
        auto Table = FCk_NavSurface_ProviderTable{};

        Table._ProjectPoint = [](UWorld*, const FCk_NavSurface_ProjectionQuery&)
        { return FCk_NavSurface_ProjectionResult{}; };

        Table._MoveAlongSurface = [](UWorld*, const FCk_NavSurface_MoveAlongSurfaceQuery&)
        { return FCk_NavSurface_MoveAlongSurfaceResult{}; };

        Table._SurfaceRaycast = [](UWorld*, const FCk_NavSurface_RaycastQuery&)
        { return FCk_NavSurface_RaycastResult{}; };

        Table._BoundarySegments = [](UWorld*, const FCk_NavSurface_BoundaryQuery&)
        { return FCk_NavSurface_BoundaryResult{}; };

        Table._IsReachable = [](UWorld*, const FCk_NavSurface_ReachabilityQuery&)
        { return FCk_NavSurface_ReachabilityResult{}; };

        Table._FindPathSync = [](UWorld*, const FCk_NavSurface_PathQuery&)
        { return FCk_NavSurface_PathResult{}; };

        Table._FindDistanceToWall = [](UWorld*, const FCk_NavSurface_WallDistanceQuery&)
        { return FCk_NavSurface_WallDistanceResult{}; };

        Table._SurfaceBounds = [](UWorld*)
        { return FBox{ForceInit}; };

        Table._ProviderHealth = [](UWorld*)
        { return ECk_NavSurface_ProviderHealth::NoData; };

        Table._IsBuildInProgress = [](UWorld*)
        { return false; };

        Table._IsSurfaceSettled = [](UWorld*)
        { return false; };

        Table._SurfaceRevision = [](UWorld*)
        { return int64{0}; };

        Table._RequestSurfaceRebuild = [](UWorld*)
        { return false; };

        Table._ApplyAreaMarkup = [](UWorld*, FCk_Handle&, const FCk_Request_NavSurface_AreaMarkup&)
        { return false; };

        Table._IsMarkupLive = [](UWorld*, const FCk_Handle&)
        { return false; };

        Table._ReleaseAreaMarkup = [](UWorld*, FCk_Handle&)
        { };

        return Table;
    }

    auto Set_QueryDurationForLifecycleTest(
        FCk_Nav_PathResult& InOutResult,
        float               InDurationMs) -> bool
    {
        auto* DiagnosticsProperty = FindFProperty<FStructProperty>(
            FCk_Nav_PathResult::StaticStruct(), TEXT("_Diagnostics"));
        if (DiagnosticsProperty == nullptr)
        { return false; }

        auto* Diagnostics = DiagnosticsProperty->ContainerPtrToValuePtr<FCk_Nav_PathDiagnostics>(&InOutResult);
        auto* DurationProperty = FindFProperty<FFloatProperty>(
            FCk_Nav_PathDiagnostics::StaticStruct(), TEXT("_LastQueryDurationMs"));
        auto* AvailableProperty = FindFProperty<FBoolProperty>(
            FCk_Nav_PathDiagnostics::StaticStruct(), TEXT("_HasQueryDuration"));
        if (DurationProperty == nullptr || AvailableProperty == nullptr)
        { return false; }

        DurationProperty->SetPropertyValue_InContainer(Diagnostics, InDurationMs);
        AvailableProperty->SetPropertyValue_InContainer(Diagnostics, true);
        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurfacePathSync_BothCapabilitiesAreRequiredTableEntries,
    "CkTests.UnitTests.CkNavigation.NavSurfacePathSync.BothCapabilitiesAreRequiredTableEntries",
    kCkUnitTestFlags)

bool FCkTest_NavSurfacePathSync_BothCapabilitiesAreRequiredTableEntries::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_pathsync;

    // Asked of the table directly rather than through Register_Provider: registration REFUSES an
    // incomplete table with an ensure, and an ensure is a failure to this harness even when it is the
    // behaviour under test.
    TestTrue(TEXT("a table filling every capability is a provider"),
        Make_CompleteTable().Get_IsComplete());

    {
        auto Table = Make_CompleteTable();
        Table._FindPathSync.Reset();

        TestFalse(TEXT("a table that cannot answer a synchronous path is NOT a provider"),
            Table.Get_IsComplete());
    }

    {
        auto Table = Make_CompleteTable();
        Table._FindDistanceToWall.Reset();

        TestFalse(TEXT("a table that cannot answer the distance to a wall is NOT a provider"),
            Table.Get_IsComplete());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurfacePathSync_NoWorldDataAnswersNoProvider,
    "CkTests.UnitTests.CkNavigation.NavSurfacePathSync.NoWorldDataAnswersNoProvider",
    kCkUnitTestFlags)

bool FCkTest_NavSurfacePathSync_NoWorldDataAnswersNoProvider::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_pathsync;

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkNavSurfacePathSyncNoData")});

    if (NOT TestTrue(TEXT("the probe world was created"), World != nullptr))
    { return false; }

    // The thread contract these two are declared under, recorded at the point it is relied on rather
    // than left as a comment: everything below is measured from the game thread.
    TestTrue(TEXT("the probe ran on the thread the capabilities' contract names"), IsInGameThread());

    // Asked of the Recast adapter directly rather than through the facade, so the answer cannot move
    // with whichever provider the project currently defaults to.
    const auto PathResult = ck::nav_surface_recast::Try_FindPathSync(
        World, FCk_NavSurface_PathQuery{FVector::ZeroVector, FVector{1000.0, 0.0, 0.0}});

    TestEqual(TEXT("a world with no navmesh answers a path query NoProvider"),
        PathResult.Get_Status(), ECk_NavSurface_QueryStatus::NoProvider);

    TestEqual(TEXT("and answers it with no waypoints rather than a plausible route"),
        PathResult.Get_Waypoints().Num(), 0);

    TestFalse(TEXT("and does not claim the nothing it returned was a partial route"),
        PathResult.Get_IsPartial());

    const auto WallResult = ck::nav_surface_recast::Try_FindDistanceToWall(
        World, FCk_NavSurface_WallDistanceQuery{FVector::ZeroVector, kWallSearchRadiusUu});

    TestEqual(TEXT("a world with no navmesh answers a wall-distance query NoProvider"),
        WallResult.Get_Status(), ECk_NavSurface_QueryStatus::NoProvider);

    TestFalse(TEXT("and reports no wall rather than one at distance zero"),
        WallResult.Get_FoundWall());

    // The same two questions through the neutral surface, which is what a consumer actually calls.
    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::Recast);

    const auto FacadePath = UCk_Utils_NavSurface_UE::Try_FindPathSync(
        World, FCk_NavSurface_PathQuery{FVector::ZeroVector, FVector{1000.0, 0.0, 0.0}});

    TestEqual(TEXT("the facade relays the same path status"),
        FacadePath.Get_Status(), ECk_NavSurface_QueryStatus::NoProvider);

    const auto FacadeWall = UCk_Utils_NavSurface_UE::Try_FindDistanceToWall(
        World, FCk_NavSurface_WallDistanceQuery{FVector::ZeroVector, kWallSearchRadiusUu});

    TestEqual(TEXT("the facade relays the same wall-distance status"),
        FacadeWall.Get_Status(), ECk_NavSurface_QueryStatus::NoProvider);

    World->DestroyWorld(InformEngineOfWorld);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavPathDiagnostics_DefaultQueryDurationIsUnavailable,
    "CkTests.UnitTests.CkNavigation.Nav.PathDiagnostics.DefaultQueryDurationIsUnavailable",
    kCkUnitTestFlags)

bool FCkTest_NavPathDiagnostics_DefaultQueryDurationIsUnavailable::RunTest(const FString& Parameters)
{
    const auto Diagnostics = FCk_Nav_PathDiagnostics{};

    TestFalse(TEXT("a fresh diagnostics value does not pretend that provider work was measured"),
        Diagnostics.Get_HasQueryDuration());
    TestEqual(TEXT("and its unavailable duration has the neutral value"),
        Diagnostics.Get_LastQueryDurationMs(), 0.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavPathDiagnostics_LifecycleClearsStaleQueryDuration,
    "CkTests.UnitTests.CkNavigation.Nav.PathDiagnostics.LifecycleClearsStaleQueryDuration",
    kCkUnitTestFlags)

bool FCkTest_NavPathDiagnostics_LifecycleClearsStaleQueryDuration::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_pathsync;

    auto EcsWorld = ck::FEcsWorld{};
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("the lifecycle fixture creates an entity"), ck::IsValid(Entity)))
    { return false; }

    auto& Result = Entity.AddOrGet<FCk_Nav_PathResult>();
    if (NOT TestTrue(TEXT("the reflected test seam can seed a prior measured result"),
        Set_QueryDurationForLifecycleTest(Result, 3.25f)))
    { return false; }

    FCk_Nav_Algorithm::MarkPathPending(Entity, 11);
    TestFalse(TEXT("a pending request cannot inherit a prior query duration"),
        Result.Get_Diagnostics().Get_HasQueryDuration());
    TestEqual(TEXT("and resets the stale duration to neutral"),
        Result.Get_Diagnostics().Get_LastQueryDurationMs(), 0.0f);

    if (NOT TestTrue(TEXT("the test can seed another prior measured result before failure"),
        Set_QueryDurationForLifecycleTest(Result, 6.5f)))
    { return false; }

    FCk_Nav_Algorithm::FailPath(Entity, ECk_Nav_PathFailReason::NoNavData, 12);
    TestFalse(TEXT("a no-work failure cannot inherit a prior query duration"),
        Result.Get_Diagnostics().Get_HasQueryDuration());
    TestEqual(TEXT("and clears its stale duration"),
        Result.Get_Diagnostics().Get_LastQueryDurationMs(), 0.0f);

    if (NOT TestTrue(TEXT("the test can seed another prior measured result before abandon"),
        Set_QueryDurationForLifecycleTest(Result, 9.75f)))
    { return false; }

    FCk_Nav_Algorithm::AbandonPath(Entity, 13);
    TestFalse(TEXT("an abandoned request cannot inherit a prior query duration"),
        Result.Get_Diagnostics().Get_HasQueryDuration());
    TestEqual(TEXT("and clears its stale duration"),
        Result.Get_Diagnostics().Get_LastQueryDurationMs(), 0.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
