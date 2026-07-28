// Pure coverage for the feet-anchor correction applied after a navmesh surface walk. World
// integration remains covered by the Crowd AutoTests.

#include <limits>

#include "CkCrowd/Agent/CkCrowdAgent_ConstrainToNavmesh_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;
using ck::ck_crowd_agent_constrain_to_navmesh_algorithm::ResolveSurfaceOffset;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_ConstrainToNavmesh_SurfaceOffset,
    "CkTests.UnitTests.CkCrowd.ConstrainToNavmesh.SurfaceOffset",
    kCkUnitTestFlags)

bool FCkTest_Crowd_ConstrainToNavmesh_SurfaceOffset::RunTest(const FString& Parameters)
{
    const auto FlatSurfaceOffset = ResolveSurfaceOffset(
        FVector{100.0f, -50.0f, 100.0f},
        FVector{110.0f, -30.0f, 25.0f});
    TestTrue(TEXT("A flat-surface result discards free-space Z and lands the feet on the surface"),
        FlatSurfaceOffset.Equals(FVector{10.0f, 20.0f, -75.0f}, 0.001f));

    const auto UphillSurfaceOffset = ResolveSurfaceOffset(
        FVector{10.0f, 20.0f, 25.0f},
        FVector{40.0f, 60.0f, 45.0f});
    TestTrue(TEXT("An uphill surface walk applies the reached surface elevation"),
        UphillSurfaceOffset.Equals(FVector{30.0f, 40.0f, 20.0f}, 0.001f));

    const auto RecoveryOffset = ResolveSurfaceOffset(
        FVector{-25.0f, 5.0f, -400.0f},
        FVector{-20.0f, 15.0f, 30.0f});
    TestTrue(TEXT("A recoverable off-mesh agent snaps all axes back to the projected feet location"),
        RecoveryOffset.Equals(FVector{5.0f, 10.0f, 430.0f}, 0.001f));

    AddExpectedError(
        TEXT("Invalid crowd navmesh constraint inputs"),
        EAutomationExpectedErrorFlags::Contains,
        4);
    const auto NotANumber = std::numeric_limits<float>::quiet_NaN();
    const auto InvalidFeet = ResolveSurfaceOffset(
        FVector{NotANumber, 0.0f, 0.0f},
        FVector::ZeroVector);
    const auto InvalidSurface = ResolveSurfaceOffset(
        FVector::ZeroVector,
        FVector{0.0f, 0.0f, NotANumber});
    TestTrue(TEXT("A non-finite feet location fails closed"),
        InvalidFeet.IsNearlyZero());
    TestTrue(TEXT("A non-finite surface location fails closed"),
        InvalidSurface.IsNearlyZero());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
