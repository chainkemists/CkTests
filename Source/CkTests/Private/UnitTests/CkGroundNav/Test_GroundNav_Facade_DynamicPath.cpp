// The native facade seam owns no Crowd state. This exercise publishes a real baked field into a
// real UWorld registry, then proves that immutable query-local obstacle values select strict routing.

#include "CkGroundNav/Facade/CkGroundNav_NavSurfaceAdapter.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include <Engine/World.h>

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_facade_dynamicpath
{
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    constexpr auto InformEngineOfWorld = false;

    auto MakeDisc(const FVector& InCentre, float InRadiusUu, float InVerticalHalfExtentUu)
        -> FCk_GroundNav_DynamicObstacleDisc
    {
        auto Disc = FCk_GroundNav_DynamicObstacleDisc{};
        Disc._Centre = InCentre;
        Disc._RadiusUu = InRadiusUu;
        Disc._VerticalHalfExtentUu = InVerticalHalfExtentUu;
        return Disc;
    }

    auto Try_MakeSnapshot(const FCk_GroundNav_DynamicObstacleDisc& InDisc)
        -> TOptional<FCk_GroundNav_DynamicObstacleSnapshot>
    {
        return Try_MakeDynamicObstacleSnapshot(
            TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{&InDisc, 1},
            TConstArrayView<ck::groundnav::FCk_GroundNav_DynamicObstacleObb>{});
    }

    auto Get_IsSamePathResult(
        const FCk_NavSurface_PathResult& InLeft,
        const FCk_NavSurface_PathResult& InRight) -> bool
    {
        if (InLeft.Get_Status() != InRight.Get_Status() ||
            InLeft.Get_StartProjected() != InRight.Get_StartProjected() ||
            InLeft.Get_EndProjected() != InRight.Get_EndProjected() ||
            InLeft.Get_IsPartial() != InRight.Get_IsPartial() ||
            InLeft.Get_LengthUu() != InRight.Get_LengthUu() ||
            InLeft.Get_Waypoints().Num() != InRight.Get_Waypoints().Num())
        { return false; }

        for (auto Index = 0; Index < InLeft.Get_Waypoints().Num(); ++Index)
        {
            if (InLeft.Get_Waypoints()[Index] != InRight.Get_Waypoints()[Index])
            { return false; }
        }

        return true;
    }

    auto Get_PathSegments(const FCk_NavSurface_PathResult& InResult) -> TArray<TPair<FVector, FVector>>
    {
        auto Points = TArray<FVector>{};
        Points.Reserve(InResult.Get_Waypoints().Num() + 2);
        Points.Add(InResult.Get_StartProjected());
        Points.Append(InResult.Get_Waypoints());
        Points.Add(InResult.Get_EndProjected());

        auto Segments = TArray<TPair<FVector, FVector>>{};
        for (auto Index = 1; Index < Points.Num(); ++Index)
        {
            if (Points[Index - 1] != Points[Index])
            { Segments.Emplace(Points[Index - 1], Points[Index]); }
        }
        return Segments;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Facade_DynamicPath,
    "CkTests.UnitTests.CkGroundNav.Facade.DynamicPath_UsesStrictObstacleSnapshotAndRejectsMalformedEndpoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Facade_DynamicPath::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_facade_dynamicpath;
    using namespace ck_test_groundnav_queryfixtures;

    auto Field = MakeShared<FCk_GroundNav_Field>();
    if (NOT TestTrue(TEXT("the facade fixture's flat field bakes"), Bake_FlatScene(*Field))) { return false; }

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkGroundNavFacadeDynamicPath")});
    if (NOT TestNotNull(TEXT("the facade fixture world was created"), World)) { return false; }

    ck::groundnav::world_fields::Publish(
        World, FCk_Handle{}, Field, {}, ck::groundnav::world_fields::FCk_GroundNav_PublishClaim::Geometry());
    const auto DestroyFixtureWorld = [World]() -> void
    {
        ck::groundnav::world_fields::Unpublish(World, FCk_Handle{});
        World->DestroyWorld(InformEngineOfWorld);
    };
    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    if (NOT TestEqual(TEXT("the real facade world selected GroundNav"),
        UCk_Utils_NavSurface_UE::Get_Provider(World), ECk_NavSurface_Provider::GroundNav))
    {
        DestroyFixtureWorld();
        return false;
    }

    const auto Start = FVector{200.0, 200.0, kGroundZ};
    const auto Goal = FVector{700.0, 200.0, kGroundZ};
    auto Query = FCk_NavSurface_PathQuery{Start, Goal};
    Query.Set_SearchHalfExtents(FVector{100.0, 100.0, kStepHeight});
    Query.Set_CornerOffset(ECk_NavSurface_CornerOffset::None);

    const auto Legacy = UCk_Utils_NavSurface_UE::Try_FindPathSync(World, Query);
    const auto EmptySnapshot = ck::groundnav::nav_surface_adapter::Try_FindPathSyncWithDynamicObstacles(
        World, Query, FCk_GroundNav_DynamicObstacleSnapshot{});

    const auto BlockingSnapshot = Try_MakeSnapshot(MakeDisc(
        FVector{400.0, 200.0, kGroundZ}, 100.0f, 50.0f));
    if (NOT TestTrue(TEXT("the finite-height blocker snapshot validates"), BlockingSnapshot.IsSet()))
    {
        DestroyFixtureWorld();
        return false;
    }

    const auto StrictBlocked = ck::groundnav::nav_surface_adapter::Try_FindPathSyncWithDynamicObstacles(
        World, Query, BlockingSnapshot.GetValue());

    const auto HighSnapshot = Try_MakeSnapshot(MakeDisc(
        FVector{400.0, 200.0, 200.0}, 100.0f, 10.0f));
    if (NOT TestTrue(TEXT("the high finite-height control snapshot validates"), HighSnapshot.IsSet()))
    {
        DestroyFixtureWorld();
        return false;
    }

    const auto HighStrict = ck::groundnav::nav_surface_adapter::Try_FindPathSyncWithDynamicObstacles(
        World, Query, HighSnapshot.GetValue());

    // The start is exactly inside its initial obstacle union. Strict search must allow that one
    // monotonic escape, but it must not silently turn the snapshot off to achieve it.
    const auto EscapeSnapshot = Try_MakeSnapshot(MakeDisc(Start, 75.0f, 50.0f));
    if (NOT TestTrue(TEXT("the exact initial-union snapshot validates"), EscapeSnapshot.IsSet()))
    {
        DestroyFixtureWorld();
        return false;
    }

    const auto StrictEscape = ck::groundnav::nav_surface_adapter::Try_FindPathSyncWithDynamicObstacles(
        World, Query, EscapeSnapshot.GetValue());

    auto NonFiniteEnd = Goal;
    constexpr auto QuietNaNBits = uint64{0x7FF8000000000000};
    FMemory::Memcpy(&NonFiniteEnd.X, &QuietNaNBits, sizeof(NonFiniteEnd.X));
    AddExpectedError(TEXT("A GroundNav facade path query received non-finite endpoints"),
        EAutomationExpectedErrorFlags::Contains, 2);
    const auto Invalid = ck::groundnav::nav_surface_adapter::Try_FindPathSyncWithDynamicObstacles(
        World, FCk_NavSurface_PathQuery{Start, NonFiniteEnd}, FCk_GroundNav_DynamicObstacleSnapshot{});

    // The invalid call is read-only failure: the already-published field and the valid empty query
    // still answer exactly as before it, which catches a partial registry/search mutation.
    const auto AfterInvalid = ck::groundnav::nav_surface_adapter::Try_FindPathSyncWithDynamicObstacles(
        World, Query, FCk_GroundNav_DynamicObstacleSnapshot{});

    DestroyFixtureWorld();

    TestEqual(TEXT("the ordinary facade route is available"), Legacy.Get_Status(), ECk_NavSurface_QueryStatus::Success);
    TestTrue(TEXT("an empty native snapshot preserves the ordinary facade answer"),
        Get_IsSamePathResult(Legacy, EmptySnapshot));
    TestEqual(TEXT("the finite-height blocker selects strict routing and still finds its detour"),
        StrictBlocked.Get_Status(), ECk_NavSurface_QueryStatus::Success);
    const auto BlockingChord = Get_DynamicUnionEdge(BlockingSnapshot.GetValue(), Start, Goal);
    TestTrue(TEXT("the ground-height blocker intersects the ordinary straight chord"),
        BlockingChord.IsSet() && BlockingChord.GetValue() != ECk_GroundNav_DynamicUnionEdge::Clear);
    const auto HighChord = Get_DynamicUnionEdge(HighSnapshot.GetValue(), Start, Goal);
    if (TestTrue(TEXT("the finite-height control evaluates the ground chord"), HighChord.IsSet()))
    {
        TestEqual(TEXT("the finite-height control leaves the ground chord clear"),
            HighChord.GetValue(), ECk_GroundNav_DynamicUnionEdge::Clear);
    }
    TestEqual(TEXT("the high obstacle does not block the ground route"),
        HighStrict.Get_Status(), ECk_NavSurface_QueryStatus::Success);
    for (const auto& Segment : Get_PathSegments(HighStrict))
    {
        const auto Union = Get_DynamicUnionEdge(HighSnapshot.GetValue(), Segment.Key, Segment.Value);
        TestTrue(TEXT("every high-obstacle strict-route segment remains clear at ground height"),
            Union.IsSet() && Union.GetValue() == ECk_GroundNav_DynamicUnionEdge::Clear);
    }
    for (const auto& Segment : Get_PathSegments(StrictBlocked))
    {
        const auto Union = Get_DynamicUnionEdge(BlockingSnapshot.GetValue(), Segment.Key, Segment.Value);
        TestTrue(TEXT("every strict detour segment is clear of the ground-height blocker"),
            Union.IsSet() && Union.GetValue() == ECk_GroundNav_DynamicUnionEdge::Clear);
    }
    TestEqual(TEXT("a start inside the exact initial obstacle union gets its one strict escape"),
        StrictEscape.Get_Status(), ECk_NavSurface_QueryStatus::Success);
    auto EscapeSawFirstExit = false;
    auto EscapeStayedClear = true;
    for (const auto& Segment : Get_PathSegments(StrictEscape))
    {
        const auto Union = Get_DynamicUnionEdge(EscapeSnapshot.GetValue(), Segment.Key, Segment.Value);
        EscapeStayedClear &= Union.IsSet();
        if (NOT Union.IsSet()) { continue; }
        if (NOT EscapeSawFirstExit)
        {
            EscapeStayedClear &= Union.GetValue() == ECk_GroundNav_DynamicUnionEdge::InsideAll ||
                                 Union.GetValue() == ECk_GroundNav_DynamicUnionEdge::ExitsOnce;
            EscapeSawFirstExit = Union.GetValue() == ECk_GroundNav_DynamicUnionEdge::ExitsOnce;
        }
        else
        { EscapeStayedClear &= Union.GetValue() == ECk_GroundNav_DynamicUnionEdge::Clear; }
    }
    TestTrue(TEXT("the exact initial union is exited once before every later route segment stays clear"),
        EscapeSawFirstExit && EscapeStayedClear);
    TestEqual(TEXT("non-finite endpoints fail before the facade can publish route data"),
        Invalid.Get_Status(), ECk_NavSurface_QueryStatus::Blocked);
    TestEqual(TEXT("non-finite endpoints publish no waypoints"), Invalid.Get_Waypoints().Num(), 0);
    TestTrue(TEXT("the invalid query leaves the valid empty-snapshot answer unchanged"),
        Get_IsSamePathResult(EmptySnapshot, AfterInvalid));

    return true;
}
