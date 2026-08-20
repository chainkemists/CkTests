// Pure C++ coverage for the facing dead-band in Commit_TrackedYaw. These assertions do not
// instantiate an ECS world or processor; the facing contract's behavioural effect is covered by
// the Crowd Facing AutoTest.

#include "CkCrowd/Agent/CkCrowdAgent_FaceAngle_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_face_angle_dead_band
{
    using ck::ck_crowd_agent_face_angle_algorithm::Commit_TrackedYaw;
    using ck::ck_crowd_agent_face_angle_algorithm::TargetPersistFrames;

    const auto kDeadBandRad = FMath::DegreesToRadians(6.0f);
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_FaceAngleDeadBand_ChatterWithinBandHoldsTarget,
    "CkTests.UnitTests.CkCrowd.FaceAngleDeadBand.ChatterWithinBandHoldsTarget",
    kCkUnitTestFlags)
auto FCkTest_Crowd_FaceAngleDeadBand_ChatterWithinBandHoldsTarget::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_face_angle_dead_band;

    auto PendingYaw = 0.0f;
    auto PendingFrames = 0;

    // Oscillate +-4 degrees around a 0-radian committed target: every candidate is inside the
    // 6-degree band, so the target must never move at all.
    for (auto Frame = 0; Frame < 10; ++Frame)
    {
        const auto Sign = (Frame % 2 == 0) ? 1.0f : -1.0f;
        const auto Candidate = Sign * FMath::DegreesToRadians(4.0f);
        const auto Committed = Commit_TrackedYaw(0.0f, Candidate, kDeadBandRad, PendingYaw, PendingFrames);

        TestEqual(TEXT("chatter inside the band leaves the target untouched"), Committed, 0.0f);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_FaceAngleDeadBand_DriftBeyondBandTracksImmediately,
    "CkTests.UnitTests.CkCrowd.FaceAngleDeadBand.DriftBeyondBandTracksImmediately",
    kCkUnitTestFlags)
auto FCkTest_Crowd_FaceAngleDeadBand_DriftBeyondBandTracksImmediately::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_face_angle_dead_band;

    auto PendingYaw = 0.0f;
    auto PendingFrames = 0;

    // 10 degrees is past the band but inside the 15-degree track tolerance: a genuine gradual turn
    // still commits the frame it appears.
    const auto Candidate = FMath::DegreesToRadians(10.0f);
    const auto Committed = Commit_TrackedYaw(0.0f, Candidate, kDeadBandRad, PendingYaw, PendingFrames);

    TestEqual(TEXT("drift past the band tracks immediately"), Committed, Candidate);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_FaceAngleDeadBand_ZeroBandRestoresImmediateTracking,
    "CkTests.UnitTests.CkCrowd.FaceAngleDeadBand.ZeroBandRestoresImmediateTracking",
    kCkUnitTestFlags)
auto FCkTest_Crowd_FaceAngleDeadBand_ZeroBandRestoresImmediateTracking::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_face_angle_dead_band;

    auto PendingYaw = 0.0f;
    auto PendingFrames = 0;

    const auto Candidate = FMath::DegreesToRadians(4.0f);
    const auto Committed = Commit_TrackedYaw(0.0f, Candidate, 0.0f, PendingYaw, PendingFrames);

    TestEqual(TEXT("a zero band disables the hold and tracks sub-tolerance changes immediately"),
        Committed, Candidate);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_FaceAngleDeadBand_LargeFlipStillNeedsPersistence,
    "CkTests.UnitTests.CkCrowd.FaceAngleDeadBand.LargeFlipStillNeedsPersistence",
    kCkUnitTestFlags)
auto FCkTest_Crowd_FaceAngleDeadBand_LargeFlipStillNeedsPersistence::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_face_angle_dead_band;

    auto PendingYaw = 0.0f;
    auto PendingFrames = 0;

    const auto Flip = FMath::DegreesToRadians(90.0f);

    for (auto Frame = 0; Frame < TargetPersistFrames - 1; ++Frame)
    {
        const auto Committed = Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);
        TestEqual(TEXT("a large flip is held while the candidate bucket fills"), Committed, 0.0f);
    }

    const auto Committed = Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);
    TestEqual(TEXT("a persistent large flip commits on the final frame"), Committed, Flip);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_FaceAngleDeadBand_ChatterResetsPendingCandidate,
    "CkTests.UnitTests.CkCrowd.FaceAngleDeadBand.ChatterResetsPendingCandidate",
    kCkUnitTestFlags)
auto FCkTest_Crowd_FaceAngleDeadBand_ChatterResetsPendingCandidate::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_face_angle_dead_band;

    auto PendingYaw = 0.0f;
    auto PendingFrames = 0;

    const auto Flip = FMath::DegreesToRadians(90.0f);
    const auto Chatter = FMath::DegreesToRadians(2.0f);

    // Two flip frames, an in-band chatter frame, then two more flips: without the chatter reset the
    // fourth flip frame would commit; with it, "consecutive" starts over and the target holds.
    Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);
    Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);
    Commit_TrackedYaw(0.0f, Chatter, kDeadBandRad, PendingYaw, PendingFrames);

    const auto AfterThirdFlip = Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);
    const auto AfterFourthFlip = Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);

    TestEqual(TEXT("chatter broke the candidate chain"), AfterThirdFlip, 0.0f);
    TestEqual(TEXT("the chain re-fills from scratch"), AfterFourthFlip, 0.0f);

    const auto AfterFifthFlip = Commit_TrackedYaw(0.0f, Flip, kDeadBandRad, PendingYaw, PendingFrames);
    TestEqual(TEXT("a re-filled chain still commits"), AfterFifthFlip, Flip);
    return true;
}
