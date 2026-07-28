// Pure coverage for selecting the first live waypoint when a path is installed after the agent
// has moved. Full corridor-swap behavior remains covered by the PathNetwork gym and AutoTests.

#include "CkCrowd/Agent/CkCrowdAgent_PathFollow_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;
using ck::ck_crowd_agent_path_follow_algorithm::SkipAlreadyPassedLeadingWaypoints;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_PathFollow_RebuildSwapSkipsPassedPrefix,
    "CkTests.UnitTests.CkCrowd.PathFollow.RebuildSwapSkipsPassedPrefix",
    kCkUnitTestFlags)

bool FCkTest_Crowd_PathFollow_RebuildSwapSkipsPassedPrefix::RunTest(const FString& Parameters)
{
    // Exact leading geometry from the residual Sidewalk Path Gym capture. The epoch-2 corridor
    // arrived after the agent had moved just beyond its lateral start projection.
    const auto AgentLocation = FVector{1235.1f, -58.3f, 1.0f};
    const auto Waypoints = TArray<FVector>{
        FVector{1235.103f, 0.0f, 1.0f},
        FVector{1000.0f, -65.829f, 1.0f},
        FVector{825.0f, -70.0f, 1.0f}};

    auto WaypointIndex = 0;
    auto CurrentSegmentStart = AgentLocation;
    const auto ObsoleteTargetDirection = (Waypoints[0] - AgentLocation).GetSafeNormal();
    TestTrue(TEXT("The captured stale target reproduces the near-pure positive-Y hook"),
        FMath::Abs(ObsoleteTargetDirection.X) < 0.01f &&
        ObsoleteTargetDirection.Y > 0.99f);

    const auto SkippedWaypointCount = SkipAlreadyPassedLeadingWaypoints(
        AgentLocation,
        Waypoints,
        WaypointIndex,
        CurrentSegmentStart);

    TestEqual(TEXT("The obsolete lateral projection is retired"), SkippedWaypointCount, 1);
    TestEqual(TEXT("The cursor advances to the forward corridor segment"), WaypointIndex, 1);
    TestTrue(TEXT("The retired waypoint becomes the incoming segment start"),
        CurrentSegmentStart.Equals(Waypoints[0], 0.001f));
    TestTrue(TEXT("The selected target continues west instead of hooking back to the projection"),
        (Waypoints[WaypointIndex] - AgentLocation).GetSafeNormal().X < -0.9f);

    // A leading waypoint that is still ahead along its outgoing segment remains load-bearing.
    const auto BeforeFirstWaypoint = FVector{1300.0f, -55.8f, 1.0f};
    WaypointIndex = 0;
    CurrentSegmentStart = BeforeFirstWaypoint;
    const auto ForwardSkipCount = SkipAlreadyPassedLeadingWaypoints(
        BeforeFirstWaypoint,
        Waypoints,
        WaypointIndex,
        CurrentSegmentStart);

    TestEqual(TEXT("A still-forward first waypoint is preserved"), ForwardSkipCount, 0);
    TestEqual(TEXT("The preserved first waypoint remains selected"), WaypointIndex, 0);
    TestTrue(TEXT("A no-op leaves the install anchor unchanged"),
        CurrentSegmentStart.Equals(BeforeFirstWaypoint, 0.001f));

    // Even when every segment plane has been crossed, final arrival owns the last waypoint.
    const auto ShortPath = TArray<FVector>{
        FVector{0.0f, 0.0f, 0.0f},
        FVector{100.0f, 0.0f, 0.0f},
        FVector{200.0f, 0.0f, 0.0f}};
    const auto BeyondGoal = FVector{250.0f, 0.0f, 0.0f};
    WaypointIndex = 0;
    CurrentSegmentStart = BeyondGoal;
    const auto FinalPreservingSkipCount = SkipAlreadyPassedLeadingWaypoints(
        BeyondGoal,
        ShortPath,
        WaypointIndex,
        CurrentSegmentStart);

    TestEqual(TEXT("Every crossed intermediate waypoint is retired"), FinalPreservingSkipCount, 2);
    TestEqual(TEXT("The final waypoint remains selected for arrival"), WaypointIndex, 2);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
