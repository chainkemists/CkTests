// The settled capability is what a caller waits on instead of counting ticks. Three things are asked
// of it here, and all three are askable without a navmesh - which is the point, because a headless
// world has none.
//
// The first is structural: settled is a REQUIRED entry, so a table that fills the other thirteen and
// leaves this one empty is not a provider. That is what stops a provider from being registered while
// silently null-calling the capability every waiter depends on.
//
// The second pins the answer a caller gets when nothing can say yes: a real world with no nav data
// must read "not settled" rather than defaulting to true - a settled-by-default answer would let a
// fixture proceed against a surface that was never published.
//
// The third is the neutral half of the same question. Settled is not only the provider's answer: a
// paint still sitting in the markup request queue, and a markup entity torn down but not yet released
// through its EndPlay processor, both leave the provider genuinely idle while the ground it answers for
// is not what the caller asked for. That half is driven here by hand, because a headless registry has
// no scheduler to walk either state forward.
//
// What is NOT covered here: settled going true after a real build, which needs a built navmesh and
// therefore a PIE world.

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_ProviderTable.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"
#include "CkNavigation/NavSurface/Recast/CkNavSurface_RecastAdapter.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_NavSurface_Settled_Markup, "Ck.Test.NavSurface.Settled.Markup");

namespace ck_test_nav_surface_settled
{
    constexpr auto InformEngineOfWorld = false;

    // Every capability except the settled one, each answering its own default. The bodies are
    // irrelevant - completeness asks only whether a callable is bound - so they are the shortest thing
    // that satisfies the signature.
    auto Make_TableMissingSettled() -> FCk_NavSurface_ProviderTable
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

        Table._SurfaceBounds = [](UWorld*)
        { return FBox{ForceInit}; };

        Table._ProviderHealth = [](UWorld*)
        { return ECk_NavSurface_ProviderHealth::NoData; };

        Table._IsBuildInProgress = [](UWorld*)
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurfaceSettled_TableIsIncompleteWithoutTheSettledEntry,
    "CkTests.UnitTests.CkNavigation.NavSurfaceSettled.TableIsIncompleteWithoutTheSettledEntry",
    kCkUnitTestFlags)

bool FCkTest_NavSurfaceSettled_TableIsIncompleteWithoutTheSettledEntry::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_settled;

    auto Table = Make_TableMissingSettled();

    // Asked of the table directly rather than through Register_Provider: registration REFUSES an
    // incomplete table with an ensure, and an ensure is a failure to this harness even when it is the
    // behaviour under test.
    TestFalse(TEXT("thirteen of fourteen capabilities is not a provider"), Table.Get_IsComplete());

    Table._IsSurfaceSettled = [](UWorld*)
    { return false; };

    TestTrue(TEXT("and the settled entry is the only thing that was missing"), Table.Get_IsComplete());

    return true;
}


// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurfaceSettled_RecastIsNotSettledWithoutNavData,
    "CkTests.UnitTests.CkNavigation.NavSurfaceSettled.RecastIsNotSettledWithoutNavData",
    kCkUnitTestFlags)

bool FCkTest_NavSurfaceSettled_RecastIsNotSettledWithoutNavData::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_settled;

    auto* World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, TEXT("CkNavSurfaceSettledNoNavData"));

    if (NOT TestTrue(TEXT("the probe world was created"), World != nullptr))
    { return false; }

    // Stated alongside the answer so a later failure says WHICH half moved: settled is health Ready
    // plus a drained dirty-areas queue, and a world with no navmesh fails the first half.
    TestTrue(TEXT("a world with no navmesh reports no nav data"),
        ck::nav_surface_recast::Get_ProviderHealth(World) != ECk_NavSurface_ProviderHealth::Ready);

    TestFalse(TEXT("so Recast is not settled there"),
        ck::nav_surface_recast::Get_IsSurfaceSettled(World));

    World->DestroyWorld(InformEngineOfWorld);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurfaceSettled_PendingMarkupWorkIsNotSettled,
    "CkTests.UnitTests.CkNavigation.NavSurfaceSettled.PendingMarkupWorkIsNotSettled",
    kCkUnitTestFlags)

bool FCkTest_NavSurfaceSettled_PendingMarkupWorkIsNotSettled::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_settled;

    auto* World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, TEXT("CkNavSurfaceSettledPendingMarkup"));

    if (NOT TestTrue(TEXT("the probe world was created"), World != nullptr))
    { return false; }

    TestFalse(TEXT("a world nobody has painted holds no neutral markup work"),
        ck::nav_surface::Get_HasPendingMarkupWork(World));

    auto Markup = UCk_Utils_NavSurface_UE::Request_AreaMarkup(World,
        FCk_Request_NavSurface_AreaMarkup{
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{100.0}}},
            TAG_Test_NavSurface_Settled_Markup.GetTag()},
        {});

    if (NOT TestTrue(TEXT("the paint produced a markup entity"), ck::IsValid(Markup)))
    {
        World->DestroyWorld(InformEngineOfWorld);
        return false;
    }

    TestTrue(TEXT("a paint the drain has not reached yet is neutral work in flight"),
        ck::nav_surface::Get_HasPendingMarkupWork(World));

    // A consistency pin, not a discriminating one: Recast answers unsettled in a headless world anyway,
    // and the only way to make it say yes here would be to register a fake table over the real provider
    // for the rest of the process. What discriminates is Get_HasPendingMarkupWork above.
    TestFalse(TEXT("so the surface is not settled while the paint is still queued"),
        UCk_Utils_NavSurface_UE::Get_IsSurfaceSettled(World));

    // What the drain leaves behind, without the drain: FProcessor_NavSurfaceMarkup_HandleRequests takes
    // the whole fragment off the entity (CopyAndRemove), so this is the state of a paint that landed.
    Markup.Try_Remove<ck::FFragment_NavSurfaceMarkup_Requests>();

    TestFalse(TEXT("and a drained queue leaves nothing neutral in flight"),
        ck::nav_surface::Get_HasPendingMarkupWork(World));

    // Teardown stopped at its first stamp, which is all Request_DestroyEntity adds synchronously. The
    // release the provider is waiting for happens several phases later, in FGroup_EndPlay.
    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Markup);

    TestTrue(TEXT("a markup entity whose teardown has not reached its release is neutral work in flight"),
        ck::nav_surface::Get_HasPendingMarkupWork(World));

    TestFalse(TEXT("so the surface is not settled while that release is still coming"),
        UCk_Utils_NavSurface_UE::Get_IsSurfaceSettled(World));

    World->DestroyWorld(InformEngineOfWorld);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
