// The publish-swap concurrency design, exercised the only way it can be falsified: republish under
// load and check that no reader ever saw a world that never existed.
//
// A published field is immutable and a rebuild swaps a pointer, so a reader holding a snapshot is
// promised a self-consistent world for as long as it holds it — no lock, no lazily built index, no
// shared scratch anywhere beneath a query. That promise cannot be pinned by reading the code; it is
// pinned by publishing two DIFFERENT worlds back and forth a thousand times while eight real threads
// query the snapshot they were handed, and asserting every worker's answers belong wholly to its own
// world. The two worlds differ by one wall, and each of the three queries has an unambiguous, opposite
// answer either side of it — so a torn read is not a subtle drift, it is a worker reporting the wall
// its snapshot does not have.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Boundary.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"

#include <Async/Async.h>

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_threadstress
{
    using ck::groundnav::FCk_GroundNav_BoundaryQuery;
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPublisher;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::Get_BoundarySegments;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_SurfaceRaycast;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;
    using ck_test_groundnav_queryfixtures::kDeckTopZ;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kHoleMax;
    using ck_test_groundnav_queryfixtures::kHoleMin;
    using ck_test_groundnav_queryfixtures::kWallMaxX;
    using ck_test_groundnav_queryfixtures::kWallMinX;

    constexpr auto kIterationCount = 1000;
    constexpr auto kWorkerCount = 8;
    constexpr auto kQueriesPerWorker = 3;

    // The two worlds carry different epochs so the publisher's reported epoch says which one is out.
    constexpr auto kEpochWithWall = int64{1};
    constexpr auto kEpochWithoutWall = int64{2};

    // Every probe below is placed on an exact cell line of the 25 uu lattice, so the answers are exact
    // and the only slack is the float-to-double widening of a stored height.
    constexpr auto kTolerance = 1.0e-3;

    // Inside the wall's footprint: nowhere to stand in the world that has the wall, open floor in the
    // world that does not.
    constexpr auto kInsideWallX = 750.0;
    constexpr auto kProbeY = 800.0;
    constexpr auto kProbeZ = 10.0;

    constexpr auto kProjectionExtentUu = 150.0f;
    constexpr auto kProjectionReachUu = 100.0f;

    // West of the wall, through it, and out the far side.
    constexpr auto kRayStartX = 600.0;
    constexpr auto kRayEndX = 900.0;
    constexpr auto kRayStartToleranceUu = 20.0f;

    // The wall's west face is 100 uu from the boundary probe, well inside the radius.
    constexpr auto kBoundaryProbeX = 600.0;
    constexpr auto kBoundaryRadiusUu = 150.0f;
    constexpr auto kBoundaryWindowUu = 50.0f;
    constexpr auto kBoundaryFaceToleranceUu = 25.0;

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The query scene without its dividing wall.
     *
     * Deliberately a copy of the fixture's box list minus one box rather than a parameter on the
     * fixture: the whole point is that the two worlds are the SAME world apart from the one thing every
     * probe here asks about, and a shared builder with a flag would let that drift.
     */
    auto Make_SceneWithoutWall() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, kHoleMin, kGroundZ}});
        Boxes.Emplace(FBox{FVector{-400.0, kHoleMax, -10.0}, FVector{2000.0, 2000.0, kGroundZ}});
        Boxes.Emplace(FBox{FVector{-400.0, kHoleMin, -10.0}, FVector{kHoleMin, kHoleMax, kGroundZ}});
        Boxes.Emplace(FBox{FVector{kHoleMax, kHoleMin, -10.0}, FVector{2000.0, kHoleMax, kGroundZ}});

        Boxes.Emplace(FBox{FVector{1000.0, 200.0, 240.0}, FVector{1500.0, 700.0, kDeckTopZ}});

        Boxes.Emplace(FBox{FVector{300.0, 1300.0, 0.0}, FVector{400.0, 1400.0, 300.0}});

        return Boxes;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_ProjectionMismatches(
        const FCk_GroundNav_Field& InField,
        bool                       InHasWall) -> int32
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = FVector{kInsideWallX, kProbeY, kProbeZ};
        Query._HorizontalExtentUu = kProjectionExtentUu;
        Query._UpExtentUu = kProjectionReachUu;
        Query._DownExtentUu = kProjectionReachUu;
        Query._Mode = ECk_NavSurface_ProjectionMode::Closest;

        const auto Result = Get_ProjectPoint(InField, Query);

        if (NOT Result.Get_IsSuccess())
        { return 1; }

        if (InHasWall)
        {
            // Either side of the wall is a correct answer and the two are equidistant, so only ground
            // INSIDE the wall's footprint — ground that world does not have — is a torn read.
            const auto IsInsideTheWall =
                Result._Location.X > kWallMinX + kTolerance && Result._Location.X < kWallMaxX - kTolerance;

            return IsInsideTheWall ? 1 : 0;
        }

        return FMath::Abs(Result._Location.X - kInsideWallX) > kTolerance ? 1 : 0;
    }

    auto Get_RaycastMismatches(
        const FCk_GroundNav_Field& InField,
        bool                       InHasWall) -> int32
    {
        auto Query = FCk_GroundNav_RaycastQuery{};

        Query._Start = FVector{kRayStartX, kProbeY, kGroundZ};
        Query._End = FVector{kRayEndX, kProbeY, kGroundZ};
        Query._StartVerticalToleranceUu = kRayStartToleranceUu;

        const auto Result = Get_SurfaceRaycast(InField, Query);

        if (NOT InHasWall)
        { return Result.Get_IsClear() ? 0 : 1; }

        if (Result._Status != ECk_NavSurface_QueryStatus::Blocked)
        { return 1; }

        return Result._HitLocation.X > kWallMinX + kTolerance ? 1 : 0;
    }

    auto Get_BoundaryMismatches(
        const FCk_GroundNav_Field& InField,
        bool                       InHasWall) -> int32
    {
        auto Query = FCk_GroundNav_BoundaryQuery{};

        Query._Location = FVector{kBoundaryProbeX, kProbeY, kGroundZ};
        Query._RadiusUu = kBoundaryRadiusUu;
        Query._VerticalWindowUu = kBoundaryWindowUu;

        auto Segments = TArray<FCk_GroundNav_BoundarySegment>{};

        if (Get_BoundarySegments(InField, Query, Segments) != ECk_NavSurface_QueryStatus::Success)
        { return 1; }

        auto WallFacingRuns = 0;

        for (const auto& Segment : Segments)
        {
            const auto FacesWest = Segment._InwardNormalXY.Equals(FVector2D{-1.0, 0.0}, kTolerance);

            if (FacesWest && FMath::Abs(Segment._Start.X - kWallMinX) <= kBoundaryFaceToleranceUu)
            { ++WallFacingRuns; }
        }

        return InHasWall
            ? (WallFacingRuns > 0 ? 0 : 1)
            : WallFacingRuns;
    }

    /** Everything one worker asks of the ONE snapshot it was handed, and how much of it disagreed. */
    auto Get_WorkerMismatches(
        const FCk_GroundNav_Field& InField,
        bool                       InHasWall) -> int32
    {
        return Get_ProjectionMismatches(InField, InHasWall) +
               Get_RaycastMismatches(InField, InHasWall) +
               Get_BoundaryMismatches(InField, InHasWall);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_QueryThreadStress_EightWorkersOverAThousandPublishes,
    "CkTests.UnitTests.CkGroundNav.Query.ThreadStress_EightWorkersOverAThousandPublishesSeeNoTornRead",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_QueryThreadStress_EightWorkersOverAThousandPublishes::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_threadstress;

    auto FieldWithWall = FCk_GroundNav_Field{};
    auto FieldWithoutWall = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the world with the dividing wall bakes"),
        Bake(Make_QueryScene(), Make_QueryParams(), FieldWithWall)))
    { return false; }

    if (NOT TestTrue(TEXT("the world without it bakes"),
        Bake(Make_SceneWithoutWall(), Make_QueryParams(), FieldWithoutWall)))
    { return false; }

    FieldWithWall._Epoch = FCk_GroundNav_Epoch{kEpochWithWall};
    FieldWithoutWall._Epoch = FCk_GroundNav_Epoch{kEpochWithoutWall};

    // Both worlds are asked every question ONCE on the game thread first: an assertion that eight
    // workers agree with each other means nothing until the answers they are agreeing on are right.
    constexpr auto HasWall = true;
    constexpr auto HasNoWall = false;

    const auto WithWallBaseline = Get_WorkerMismatches(FieldWithWall, HasWall);
    const auto WithoutWallBaseline = Get_WorkerMismatches(FieldWithoutWall, HasNoWall);

    if (NOT TestEqual(TEXT("the walled world answers all three probes as its own on the game thread"),
        WithWallBaseline, 0))
    { return false; }

    if (NOT TestEqual(TEXT("and so does the wall-free one"), WithoutWallBaseline, 0))
    { return false; }

    const TSharedRef<const FCk_GroundNav_Field> SceneWithWall =
        MakeShared<FCk_GroundNav_Field>(MoveTemp(FieldWithWall));
    const TSharedRef<const FCk_GroundNav_Field> SceneWithoutWall =
        MakeShared<FCk_GroundNav_Field>(MoveTemp(FieldWithoutWall));

    auto Publisher = FCk_GroundNav_FieldPublisher{};

    auto Mismatches = 0;
    auto EpochAgreements = 0;
    auto EpochChanges = 0;

    auto PreviousEpoch = Publisher.Get_Epoch();

    for (auto Iteration = 0; Iteration < kIterationCount; ++Iteration)
    {
        const auto PublishTheWalledWorld = (Iteration % 2) == 0;

        Publisher.Request_Publish(PublishTheWalledWorld ? SceneWithWall : SceneWithoutWall);

        // Taken on the game thread and handed to the workers, exactly as a consumer takes one: the
        // snapshot IS the guarantee, and re-reading the publisher from a worker would be the bug.
        const auto Snapshot = Publisher.Get_Published();
        const auto Epoch = Publisher.Get_Epoch();

        if (Snapshot.IsValid() && Epoch == Snapshot->_Epoch)
        { ++EpochAgreements; }

        if (Iteration > 0 && NOT (Epoch == PreviousEpoch))
        { ++EpochChanges; }

        PreviousEpoch = Epoch;

        auto Answers = TArray<TFuture<int32>>{};
        Answers.Reserve(kWorkerCount);

        for (auto Worker = 0; Worker < kWorkerCount; ++Worker)
        {
            // A dedicated thread rather than the task graph: the task graph may service work on the
            // game thread, which would make the off-thread half of this test silently vacuous.
            Answers.Emplace(Async(EAsyncExecution::Thread, [Snapshot, PublishTheWalledWorld]() -> int32
            {
                return Get_WorkerMismatches(*Snapshot, PublishTheWalledWorld);
            }));
        }

        for (auto& Answer : Answers)
        { Mismatches += Answer.Get(); }
    }

    const auto TotalQueries = kIterationCount * kWorkerCount * kQueriesPerWorker;

    const auto Report = FString::Printf(
        TEXT("publishes %d, workers per publish %d, queries %d, mismatches %d, epoch agreements %d, epoch changes %d"),
        kIterationCount, kWorkerCount, TotalQueries, Mismatches, EpochAgreements, EpochChanges);

    ck::groundnav::Display(TEXT("{}"), Report);

    // Every worker's three answers belong wholly to the snapshot it was handed. One mismatch is a
    // reader that saw a world nobody ever published.
    TestEqual(FString::Printf(TEXT("no worker ever saw a torn read [%s]"), *Report), Mismatches, 0);

    // The publisher reports the epoch of what is published, and swapping between two worlds moves it
    // every single time — which is how a reader that took a snapshot finds out it is behind.
    TestEqual(FString::Printf(TEXT("the published epoch is the published field's, every time [%s]"), *Report),
        EpochAgreements, kIterationCount);
    TestEqual(FString::Printf(TEXT("and it moved on every republish [%s]"), *Report),
        EpochChanges, kIterationCount - 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
