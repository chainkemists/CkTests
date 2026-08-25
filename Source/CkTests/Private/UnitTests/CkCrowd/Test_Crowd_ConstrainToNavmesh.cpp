// Pure coverage for the feet-anchor correction applied after a navmesh surface walk. World
// integration remains covered by the Crowd AutoTests.

#include <limits>

#include "CkCrowd/Agent/CkCrowdAgent_ConstrainToNavmesh_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;
using ck::ck_crowd_agent_constrain_to_navmesh_algorithm::Get_GroundingVerifyPhaseSeconds;
using ck::ck_crowd_agent_constrain_to_navmesh_algorithm::Get_ShouldVerifyGrounding;
using ck::ck_crowd_agent_constrain_to_navmesh_algorithm::ResolveSurfaceOffset;
using ck::ck_crowd_agent_constrain_to_navmesh_algorithm::ResolveVerticalDriftOffset;

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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_ConstrainToNavmesh_GroundingLease,
    "CkTests.UnitTests.CkCrowd.ConstrainToNavmesh.GroundingLease",
    kCkUnitTestFlags)

bool FCkTest_Crowd_ConstrainToNavmesh_GroundingLease::RunTest(const FString& Parameters)
{
    constexpr auto Interval = 1.0f;

    TestFalse(TEXT("A lease that has not run its interval is not due"),
        Get_ShouldVerifyGrounding(0.0f, Interval));
    TestFalse(TEXT("A lease just short of its interval is not due"),
        Get_ShouldVerifyGrounding(0.999f, Interval));
    TestTrue(TEXT("A lease exactly at its interval is due"),
        Get_ShouldVerifyGrounding(Interval, Interval));
    TestTrue(TEXT("A lease past its interval is due"),
        Get_ShouldVerifyGrounding(4.0f, Interval));

    // A non-positive interval is the A/B configuration that restores the pre-lease behaviour: no
    // amount of elapsed time may make a verify due, or the switch does not switch anything off.
    TestFalse(TEXT("A zero interval never becomes due, however long the agent has rested"),
        Get_ShouldVerifyGrounding(1000.0f, 0.0f));
    TestFalse(TEXT("A negative interval never becomes due either"),
        Get_ShouldVerifyGrounding(1000.0f, -1.0f));

    TestTrue(TEXT("A disabled interval seeds no phase at all"),
        Get_GroundingVerifyPhaseSeconds(1234567u, 0.0f) == 0.0f);
    TestTrue(TEXT("A negative interval seeds no phase either"),
        Get_GroundingVerifyPhaseSeconds(1234567u, -1.0f) == 0.0f);

    // The seed exists so a crowd composed on ONE frame does not verify in lockstep forever, so the
    // property under test is the RANGE it spreads agents across: [0, Interval), never the interval
    // itself (which would make the very first frame due for a whole bucket).
    const auto Hashes = TArray<uint32>{0u, 1u, 7u, 255u, 256u, 511u, 512u, 1023u, 4096u, 987654321u};
    for (const auto Hash : Hashes)
    {
        const auto Phase = Get_GroundingVerifyPhaseSeconds(Hash, Interval);
        TestTrue(*FString::Printf(TEXT("Hash %u seeds a phase inside [0, Interval)"), Hash),
            Phase >= 0.0f && Phase < Interval);
    }

    TestTrue(TEXT("The lowest bucket seeds a zero phase"),
        Get_GroundingVerifyPhaseSeconds(0u, Interval) == 0.0f);
    TestTrue(TEXT("The half bucket seeds half the interval"),
        FMath::IsNearlyEqual(Get_GroundingVerifyPhaseSeconds(512u, Interval), 0.5f, 0.001f));

    // Two hashes landing in DIFFERENT mod-1024 buckets must not collide, or the crowd is spread in
    // name only.
    TestTrue(TEXT("Hashes in different buckets seed different phases"),
        Get_GroundingVerifyPhaseSeconds(256u, Interval) != Get_GroundingVerifyPhaseSeconds(768u, Interval));

    // ...and the bucketing is deliberately modular, so the wrap is the same agent as far as the
    // spread is concerned. Pinned so a future "improvement" to the hash mix cannot silently change
    // which agents share a slot.
    TestTrue(TEXT("Hashes one bucket-period apart seed the same phase"),
        Get_GroundingVerifyPhaseSeconds(1024u, Interval) == Get_GroundingVerifyPhaseSeconds(0u, Interval));

    TestTrue(TEXT("The phase scales with the interval it spreads across"),
        FMath::IsNearlyEqual(Get_GroundingVerifyPhaseSeconds(512u, 4.0f), 2.0f, 0.001f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_ConstrainToNavmesh_VerticalDriftOffset,
    "CkTests.UnitTests.CkCrowd.ConstrainToNavmesh.VerticalDriftOffset",
    kCkUnitTestFlags)

bool FCkTest_Crowd_ConstrainToNavmesh_VerticalDriftOffset::RunTest(const FString& Parameters)
{
    constexpr auto DeadBand = 0.5f;

    const auto PureDrop = ResolveVerticalDriftOffset(
        FVector{250.0f, -125.0f, 130.0f},
        FVector{250.0f, -125.0f, 30.0f},
        DeadBand);
    TestTrue(TEXT("An agent floating a metre above the surface is dropped exactly onto it"),
        PureDrop.Equals(FVector{0.0f, 0.0f, -100.0f}, 0.001f));

    // THE anti-creep pin. ProjectPointToNavigation answers with the nearest poly point, which near a
    // navmesh edge carries a LATERAL nudge; folding that into a resting agent's offset would shove a
    // settled formation a little every lease, re-creating the formation creep the push-apart slop
    // exists to end. X and Y are therefore asserted to be EXACTLY zero, not merely small.
    const auto Feet = FVector{-40.0f, 610.0f, 130.0f};
    const auto LateralNudge = ResolveVerticalDriftOffset(
        Feet,
        Feet + FVector{30.0f, -20.0f, -100.0f},
        DeadBand);
    TestTrue(TEXT("A surface point carrying lateral delta contributes no X to the idle correction"),
        LateralNudge.X == 0.0);
    TestTrue(TEXT("A surface point carrying lateral delta contributes no Y to the idle correction"),
        LateralNudge.Y == 0.0);
    TestTrue(TEXT("The vertical component survives that lateral delta unchanged"),
        FMath::IsNearlyEqual(LateralNudge.Z, -100.0, 0.001));

    // The dead-band is inclusive: at exactly the band there is nothing worth correcting, so an
    // at-rest agent is left alone rather than nudged every single lease.
    const auto AtBand = ResolveVerticalDriftOffset(
        FVector{0.0f, 0.0f, DeadBand},
        FVector::ZeroVector,
        DeadBand);
    TestTrue(TEXT("A drift of exactly the dead-band is left uncorrected"),
        AtBand == FVector::ZeroVector);

    const auto UnderBand = ResolveVerticalDriftOffset(
        FVector{0.0f, 0.0f, 0.4f},
        FVector::ZeroVector,
        DeadBand);
    TestTrue(TEXT("A drift under the dead-band is left uncorrected"),
        UnderBand == FVector::ZeroVector);

    // Past the band the correction is the WHOLE drift, not the drift minus the band — the band gates
    // whether to act, it is not a deduction, and subtracting it would leave a permanent residue.
    const auto OverBand = ResolveVerticalDriftOffset(
        FVector{0.0f, 0.0f, 0.6f},
        FVector::ZeroVector,
        DeadBand);
    TestTrue(TEXT("A drift just past the dead-band is corrected in full, with nothing deducted"),
        OverBand.Equals(FVector{0.0f, 0.0f, -0.6f}, 0.0001f));

    // Upward corrections take the same path: an agent that sank below the surface is lifted onto it.
    const auto Sunk = ResolveVerticalDriftOffset(
        FVector{12.0f, 34.0f, -25.0f},
        FVector{12.0f, 34.0f, 0.0f},
        DeadBand);
    TestTrue(TEXT("An agent below the surface is lifted onto it, still Z-only"),
        Sunk.Equals(FVector{0.0f, 0.0f, 25.0f}, 0.001f));

    // NaN inherits ResolveSurfaceOffset's ensure and its zero-vector recovery: the drift resolver
    // adds no validation of its own, so this pins that it does not accidentally swallow the report.
    // Occurrence count left open deliberately — the assertion is that the ensure FIRES, and pinning
    // an exact count here would couple this test to the ensure pipeline's log fan-out.
    AddExpectedError(
        TEXT("Invalid crowd navmesh constraint inputs"),
        EAutomationExpectedErrorFlags::Contains,
        0);
    const auto NotANumber = std::numeric_limits<float>::quiet_NaN();
    const auto InvalidFeet = ResolveVerticalDriftOffset(
        FVector{NotANumber, 0.0f, 0.0f},
        FVector::ZeroVector,
        DeadBand);
    TestTrue(TEXT("A non-finite feet location fails closed"),
        InvalidFeet.IsNearlyZero());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
