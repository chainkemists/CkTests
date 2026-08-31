// Get_BoundarySegments is the navigation surface's C++-only entry, called off the game thread by
// CkCrowd's parallel avoidance sampler. This pins the half of that contract a headless world can
// answer: the no-provider path returns the same clean status from a worker thread as from the game
// thread, and leaves the caller's storage empty rather than appending to whatever was already in
// it. Exercising it against a BUILT navmesh needs a PIE world and belongs to the Crowd AutoTests.

#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include <Async/Async.h>
#include <Engine/World.h>

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_nav_surface_boundary
{
    constexpr auto InformEngineOfWorld = false;

    struct FBoundaryProbe
    {
        ECk_NavSurface_QueryStatus _Status = ECk_NavSurface_QueryStatus::Success;
        int32 _SegmentCount = 0;
        bool _RanOnGameThread = true;
    };

    auto Run_Probe(UWorld* InWorld) -> FBoundaryProbe
    {
        const auto Query = FCk_NavSurface_BoundaryQuery{FVector::ZeroVector, 500.0f};

        auto Segments = TArray<FCk_NavSurface_BoundarySegment>{};
        Segments.Emplace();

        auto Probe = FBoundaryProbe{};
        Probe._Status = UCk_Utils_NavSurface_UE::Get_BoundarySegments(InWorld, Query, Segments);
        Probe._SegmentCount = Segments.Num();
        Probe._RanOnGameThread = IsInGameThread();
        return Probe;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_BoundarySegments_ThreadContract,
    "CkTests.UnitTests.CkNavigation.NavSurface.BoundarySegmentsThreadContract",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_BoundarySegments_ThreadContract::RunTest(const FString& Parameters)
{
    auto* World = UWorld::CreateWorld(
        EWorldType::Game,
        ck_test_nav_surface_boundary::InformEngineOfWorld,
        FName{TEXT("CkNavSurfaceBoundaryThreadContract")});

    TestNotNull(TEXT("the probe world was created"), World);
    if (World == nullptr)
    { return false; }

    const auto GameThreadProbe = ck_test_nav_surface_boundary::Run_Probe(World);

    // A dedicated thread rather than the task graph: the task graph may service work on the game
    // thread, which would make the off-thread half of this test silently vacuous.
    const auto WorkerProbe =
        Async(EAsyncExecution::Thread, [World]() -> ck_test_nav_surface_boundary::FBoundaryProbe
        {
            return ck_test_nav_surface_boundary::Run_Probe(World);
        }).Get();

    World->DestroyWorld(ck_test_nav_surface_boundary::InformEngineOfWorld);

    TestTrue(TEXT("the game-thread probe ran on the game thread"), GameThreadProbe._RanOnGameThread);
    TestFalse(TEXT("the worker probe ran off the game thread"), WorkerProbe._RanOnGameThread);

    TestEqual(TEXT("a world with no navigation provider answers NoProvider on the game thread"),
        GameThreadProbe._Status, ECk_NavSurface_QueryStatus::NoProvider);
    TestEqual(TEXT("the worker thread gets the identical status"),
        WorkerProbe._Status, GameThreadProbe._Status);

    TestEqual(TEXT("a non-Success game-thread answer leaves no segments behind"),
        GameThreadProbe._SegmentCount, 0);
    TestEqual(TEXT("a non-Success worker answer leaves no segments behind"),
        WorkerProbe._SegmentCount, 0);

    return true;
}
