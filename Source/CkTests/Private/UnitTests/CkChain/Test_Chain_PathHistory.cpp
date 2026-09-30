#include "Misc/AutomationTest.h"
#include "Math/RandomStream.h"

#include <limits>

#include "CkChain/CkChain_PathHistory.h"
#include "../CkUnitTest_Common.h"

// Editor automation records both the ensure log and its outside-PIE error message.

namespace ck_test_chain_pathhistory
{
    using namespace ck::chain;

    auto MakePose(const FVector& InLocation, const FQuat& InRotation = FQuat::Identity) -> FTransform
    {
        return FTransform{InRotation, InLocation};
    }

    auto MakeStraightHistory(float InLength = 1000.0f) -> FPathHistory
    {
        auto History = FPathHistory{};
        History.Reserve_ForDistance(InLength, 10.0f);
        History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
        for (auto X = 10.0f; X <= InLength; X += 10.0f)
        { History.Record(MakePose(FVector{X, 0, 0}), 10.0f); }
        return History;
    }

    auto MakeCornerHistory() -> FPathHistory
    {
        auto History = MakeStraightHistory(500.0f);
        History.Reserve_ForDistance(1100.0f, 10.0f);
        for (auto Y = 10.0f; Y <= 500.0f; Y += 10.0f)
        { History.Record(MakePose(FVector{500, Y, 0}), 10.0f); }
        return History;
    }

    auto MakeNewestPose(const FPathHistory& InHistory) -> FTransform
    {
        const auto& Newest = InHistory.Get_Sample(InHistory.Get_NumSamples() - 1);
        return MakePose(Newest.Get_Location(), Newest.Get_Rotation());
    }

    auto TestSampleLocation(FAutomationTestBase& InTest, const FPathHistory& InHistory,
        float InS, const FVector& InExpected) -> void
    {
        const auto Sample = InHistory.Sample_AtArcDistance(InS, ECk_Chain_HistorySeed::StraightBehindHead);
        if (InTest.TestTrue(TEXT("sample is present"), Sample.IsSet()))
        { InTest.TestTrue(TEXT("sample follows expected path location"), Sample.GetValue().Get_Location().Equals(InExpected, 1.0e-3)); }
    }
}

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Reseed_ProducesTwoSamplesBehindAndAtHead,
    "Ck.Chain.PathHistory.Reseed_ProducesTwoSamplesBehindAndAtHead", kCkUnitTestFlags)
bool FCk_Chain_Reseed_ProducesTwoSamplesBehindAndAtHead::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto Pose = MakePose(FVector{40, 80, 120}, FRotator{0, 90, 0}.Quaternion());
    auto History = MakeStraightHistory();
    History.Reseed(Pose, 25.0f);
    if (NOT TestEqual(TEXT("reseed replaces old samples"), History.Get_NumSamples(), 2))
    { return false; }
    TestEqual(TEXT("oldest arc"), History.Get_OldestArcDistance(), -25.0f);
    TestEqual(TEXT("head arc"), History.Get_HeadArcDistance(), 0.0f);
    TestSampleLocation(*this, History, -25.0f, Pose.GetLocation() - Pose.GetRotation().GetForwardVector() * 25.0f);
    TestSampleLocation(*this, History, 0.0f, Pose.GetLocation());
    TestTrue(TEXT("seed rotation retained"), History.Get_Sample(0).Get_Rotation().Equals(Pose.GetRotation(), 1.0e-3));
    AddExpectedError(TEXT("Chain history spacing must be finite and positive"), EAutomationExpectedErrorFlags::Contains, 2);
    History.Reseed(MakePose(FVector{999, 999, 999}), 0.0f);
    TestEqual(TEXT("invalid reseed preserves sample count"), History.Get_NumSamples(), 2);
    TestSampleLocation(*this, History, 0.0f, Pose.GetLocation());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Record_RejectsChordBelowSpacing,
    "Ck.Chain.PathHistory.Record_RejectsChordBelowSpacing", kCkUnitTestFlags)
bool FCk_Chain_Record_RejectsChordBelowSpacing::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    for (auto Index = 0; Index < 100; ++Index)
    { TestFalse(TEXT("sub-spacing chord rejected"), History.Record(MakePose(FVector{Index * 0.09, 0, 0}), 10.0f)); }
    TestEqual(TEXT("no sample appended"), History.Get_NumSamples(), 2);
    TestEqual(TEXT("no arc advance"), History.Get_HeadArcDistance(), 0.0f);
    TestTrue(TEXT("spacing equality appends"), History.Record(MakePose(FVector{10, 0, 0}), 10.0f));
    AddExpectedError(TEXT("Chain history spacing must be finite and positive"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("invalid spacing rejects record"), History.Record(MakePose(FVector{20, 0, 0}), 0.0f));
    TestEqual(TEXT("invalid record preserves arc"), History.Get_HeadArcDistance(), 10.0f);
    TestEqual(TEXT("invalid record preserves count"), History.Get_NumSamples(), 2);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Record_ArcDistanceIsCumulativeChord,
    "Ck.Chain.PathHistory.Record_ArcDistanceIsCumulativeChord", kCkUnitTestFlags)
bool FCk_Chain_Record_ArcDistanceIsCumulativeChord::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = MakeStraightHistory();
    TestTrue(TEXT("straight cumulative arc"), FMath::IsNearlyEqual(History.Get_HeadArcDistance(), 1000.0f, 1.0e-3f));
    History.Record(MakePose(FVector{1000, 30, 40}), 10.0f);
    TestTrue(TEXT("3D chord advances arc by fifty"), FMath::IsNearlyEqual(History.Get_HeadArcDistance(), 1050.0f, 1.0e-3f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Sample_StraightLineIsExact,
    "Ck.Chain.PathHistory.Sample_StraightLineIsExact", kCkUnitTestFlags)
bool FCk_Chain_Sample_StraightLineIsExact::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeStraightHistory();
    auto Random = FRandomStream{271828};
    for (auto Index = 0; Index < 50; ++Index)
    {
        const auto S = Random.FRandRange(-10.0f, 1000.0f);
        TestSampleLocation(*this, History, S, FVector{S, 0, 0});
    }
    auto Rotating = FPathHistory{};
    Rotating.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    Rotating.Record(MakePose(FVector{10, 0, 0}, FRotator{0, 90, 0}.Quaternion()), 10.0f);
    const auto Midpoint = Rotating.Sample_AtArcDistance(5.0f, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("rotation midpoint present"), Midpoint.IsSet()))
    { TestTrue(TEXT("rotation interpolates using slerp"), Midpoint.GetValue().Get_Rotation().Equals(FRotator{0, 45, 0}.Quaternion(), 1.0e-3)); }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Sample_RightAngleFollowsCorner,
    "Ck.Chain.PathHistory.Sample_RightAngleFollowsCorner", kCkUnitTestFlags)
bool FCk_Chain_Sample_RightAngleFollowsCorner::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeCornerHistory();
    TestSampleLocation(*this, History, 700.0f, FVector{500, 200, 0});
    TestSampleLocation(*this, History, 495.0f, FVector{495, 0, 0});
    TestSampleLocation(*this, History, 505.0f, FVector{500, 5, 0});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Sample_BeyondNewestClampsToHead,
    "Ck.Chain.PathHistory.Sample_BeyondNewestClampsToHead", kCkUnitTestFlags)
bool FCk_Chain_Sample_BeyondNewestClampsToHead::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeStraightHistory();
    TestSampleLocation(*this, History, History.Get_HeadArcDistance() + 50.0f, FVector{1000, 0, 0});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Sample_BehindOldest_ExtrapolatesOrHolds,
    "Ck.Chain.PathHistory.Sample_BehindOldest_ExtrapolatesOrHolds", kCkUnitTestFlags)
bool FCk_Chain_Sample_BehindOldest_ExtrapolatesOrHolds::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector{30, 40, 50}, FRotator{0, 90, 0}.Quaternion()), 10.0f);
    TestSampleLocation(*this, History, -60.0f, FVector{30, -20, 50});
    TestFalse(TEXT("hold leaves uncovered sample unset"), History.Sample_AtArcDistance(-60.0f, ECk_Chain_HistorySeed::HoldUntilCovered).IsSet());
    TestTrue(TEXT("oldest boundary covered"), History.Sample_AtArcDistance(-10.0f, ECk_Chain_HistorySeed::HoldUntilCovered).IsSet());
    TestFalse(TEXT("hold propagates through placement"), Solve_PathHistoryPose(History, MakeNewestPose(History), 60.0f,
        ECk_Chain_LinkOrientation::KeepOwn, FVector::UpVector, ECk_Chain_HistorySeed::HoldUntilCovered,
        FTransform::Identity).IsSet());
    AddExpectedError(TEXT("Chain link distance must be finite and nonnegative"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("negative link distance fails closed"), Solve_PathHistoryPose(History, MakeNewestPose(History), -1.0f,
        ECk_Chain_LinkOrientation::KeepOwn, FVector::UpVector, ECk_Chain_HistorySeed::StraightBehindHead,
        FTransform::Identity).IsSet());
    auto TinyHistory = FPathHistory{};
    TinyHistory.Reseed(FTransform::Identity, 1.0e-5f);
    const auto TinySample = TinyHistory.Sample_AtArcDistance(-2.0e-5f, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("tiny positive spacing has extrapolated sample"), TinySample.IsSet()))
    { TestTrue(TEXT("tiny spacing extrapolates by arc distance"), TinySample.GetValue().Get_Location().Equals(FVector{-2.0e-5, 0, 0}, 1.0e-9)); }
    TestTrue(TEXT("tiny spacing still has unit tangent"), TinyHistory.Tangent_AtArcDistance(-2.0e-5f).Equals(FVector::ForwardVector, 1.0e-9));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Tangent_AtCornerUsesBracketingSegment,
    "Ck.Chain.PathHistory.Tangent_AtCornerUsesBracketingSegment", kCkUnitTestFlags)
bool FCk_Chain_Tangent_AtCornerUsesBracketingSegment::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeCornerHistory();
    TestTrue(TEXT("before corner follows X"), History.Tangent_AtArcDistance(495.0f).Equals(FVector::ForwardVector, 1.0e-3));
    TestTrue(TEXT("after corner follows Y"), History.Tangent_AtArcDistance(505.0f).Equals(FVector::RightVector, 1.0e-3));
    TestTrue(TEXT("extrapolation uses oldest segment"), History.Tangent_AtArcDistance(-100.0f).Equals(FVector::ForwardVector, 1.0e-3));
    TestTrue(TEXT("beyond newest uses final segment"), History.Tangent_AtArcDistance(2000.0f).Equals(FVector::RightVector, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Trim_KeepsAtLeastTwoAndCoversDistance,
    "Ck.Chain.PathHistory.Trim_KeepsAtLeastTwoAndCoversDistance", kCkUnitTestFlags)
bool FCk_Chain_Trim_KeepsAtLeastTwoAndCoversDistance::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = MakeStraightHistory();
    History.Trim(305.0f);
    if (NOT TestTrue(TEXT("trim leaves a bracketing pair"), History.Get_NumSamples() >= 2))
    { return false; }
    TestEqual(TEXT("off-grid cutoff retains predecessor"), History.Get_OldestArcDistance(), 690.0f);
    TestEqual(TEXT("successor brackets cutoff"), History.Get_Sample(1).Get_ArcDistanceCm(), 700.0f);
    TestSampleLocation(*this, History, 695.0f, FVector{695, 0, 0});
    const auto BeforeInvalidTrim = History.Get_NumSamples();
    AddExpectedError(TEXT("Chain history trim distance must be finite and nonnegative"), EAutomationExpectedErrorFlags::Contains, 2);
    History.Trim(-1.0f);
    TestEqual(TEXT("negative trim preserves count"), History.Get_NumSamples(), BeforeInvalidTrim);
    TestEqual(TEXT("negative trim preserves oldest"), History.Get_OldestArcDistance(), 690.0f);
    History.Trim(0.0f);
    TestEqual(TEXT("zero retention keeps two"), History.Get_NumSamples(), 2);
    TestEqual(TEXT("newest retained"), History.Get_HeadArcDistance(), 1000.0f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Ring_WrapsWithoutReallocInSteadyState,
    "Ck.Chain.PathHistory.Ring_WrapsWithoutReallocInSteadyState", kCkUnitTestFlags)
bool FCk_Chain_Ring_WrapsWithoutReallocInSteadyState::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reserve_ForDistance(500.0f, 10.0f);
    const auto ReservedSize = History.Get_AllocatedSize();
    TestTrue(TEXT("reserve allocates storage"), ReservedSize > 0);
    AddExpectedError(TEXT("Chain history reserve distance and spacing are invalid"), EAutomationExpectedErrorFlags::Contains, 2);
    History.Reserve_ForDistance(-1.0f, 10.0f);
    TestEqual(TEXT("negative reserve preserves storage"), History.Get_AllocatedSize(), ReservedSize);
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    TestEqual(TEXT("reseed preserves reserve"), History.Get_AllocatedSize(), ReservedSize);
    for (auto Index = 1; Index <= 10000; ++Index)
    {
        const auto X = Index * 10.0f;
        if (NOT TestTrue(TEXT("steady-state record appends"), History.Record(MakePose(FVector{X, 0, 0}), 10.0f)))
        { return false; }
        if (NOT TestEqual(TEXT("append does not allocate"), History.Get_AllocatedSize(), ReservedSize))
        { return false; }
        History.Trim(500.0f);
        if (NOT TestEqual(TEXT("trim does not allocate"), History.Get_AllocatedSize(), ReservedSize))
        { return false; }
        if (Index % 100 == 0)
        { TestSampleLocation(*this, History, X - 495.0f, FVector{X - 495.0f, 0, 0}); }
    }
    TestTrue(TEXT("retained samples bounded by reserve horizon"), History.Get_NumSamples() <= 52);
    const auto WrappedSamples = History.Get_Samples();
    History.Reserve_ForDistance(2000.0f, 10.0f);
    const auto GrownSize = History.Get_AllocatedSize();
    TestTrue(TEXT("larger horizon grows allocation"), GrownSize > ReservedSize);
    if (NOT TestEqual(TEXT("reserve growth retains sample count"), History.Get_NumSamples(), WrappedSamples.Num()))
    { return false; }
    for (auto Index = 0; Index < WrappedSamples.Num(); ++Index)
    {
        const auto& Before = WrappedSamples[Index];
        const auto& After = History.Get_Sample(Index);
        TestEqual(TEXT("wrapped growth preserves logical arc order"), After.Get_ArcDistanceCm(), Before.Get_ArcDistanceCm());
        TestTrue(TEXT("wrapped growth preserves location"), After.Get_Location().Equals(Before.Get_Location(), 1.0e-3));
        TestTrue(TEXT("wrapped growth preserves rotation"), After.Get_Rotation().Equals(Before.Get_Rotation(), 1.0e-3));
    }
    TestSampleLocation(*this, History, 99995.0f, FVector{99995, 0, 0});
    History.Reseed(MakePose(FVector{200, 300, 400}), 10.0f);
    TestEqual(TEXT("second reseed preserves storage"), History.Get_AllocatedSize(), GrownSize);
    TestEqual(TEXT("second reseed clears logical ring"), History.Get_NumSamples(), 2);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Slice_Behind_RebasesNewestToZero,
    "Ck.Chain.PathHistory.Slice_Behind_RebasesNewestToZero", kCkUnitTestFlags)
bool FCk_Chain_Slice_Behind_RebasesNewestToZero::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeStraightHistory();
    const auto Slice = History.Slice_Behind(705.0f);
    if (NOT TestEqual(TEXT("exact subset includes seed and records through seven hundred"), Slice.Get_NumSamples(), 72))
    { return false; }
    TestEqual(TEXT("newest rebased to zero"), Slice.Get_HeadArcDistance(), 0.0f);
    TestEqual(TEXT("oldest rebased consistently"), Slice.Get_OldestArcDistance(), -710.0f);
    TestSampleLocation(*this, Slice, 0.0f, FVector{700, 0, 0});
    TestSampleLocation(*this, Slice, -5.0f, FVector{695, 0, 0});
    TestEqual(TEXT("source history unchanged"), History.Get_HeadArcDistance(), 1000.0f);
    const auto Empty = History.Slice_Behind(-11.0f);
    TestEqual(TEXT("slice before oldest empty"), Empty.Get_NumSamples(), 0);
    TestFalse(TEXT("empty sample unset"), Empty.Sample_AtArcDistance(0.0f, ECk_Chain_HistorySeed::StraightBehindHead).IsSet());
    TestTrue(TEXT("empty tangent zero"), Empty.Tangent_AtArcDistance(0.0f).IsNearlyZero());
    const auto Single = History.Slice_Behind(-10.0f);
    if (NOT TestEqual(TEXT("oldest-only slice has one sample"), Single.Get_NumSamples(), 1))
    { return false; }
    TestSampleLocation(*this, Single, -100.0f, FVector{-10, 0, 0});
    TestSampleLocation(*this, Single, 100.0f, FVector{-10, 0, 0});
    TestFalse(TEXT("single hold below oldest unset"), Single.Sample_AtArcDistance(-1.0f, ECk_Chain_HistorySeed::HoldUntilCovered).IsSet());
    TestTrue(TEXT("single hold at oldest covered"), Single.Sample_AtArcDistance(0.0f, ECk_Chain_HistorySeed::HoldUntilCovered).IsSet());
    TestTrue(TEXT("single tangent zero"), Single.Tangent_AtArcDistance(0.0f).IsNearlyZero());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Orientation_FollowPathFacesTangentWithUp,
    "Ck.Chain.PathHistory.Orientation_FollowPathFacesTangentWithUp", kCkUnitTestFlags)
bool FCk_Chain_Orientation_FollowPathFacesTangentWithUp::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeCornerHistory();
    const auto Current = FTransform{FRotator{20, -35, 10}.Quaternion(), FVector{3, 4, 5}, FVector{2, 3, 4}};
    for (const auto Orientation : {ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_LinkOrientation::KeepOwn})
    {
        const auto Pose = Solve_PathHistoryPose(History, MakeNewestPose(History), 305.0f, Orientation, FVector::UpVector,
            ECk_Chain_HistorySeed::StraightBehindHead, Current);
        if (NOT TestTrue(TEXT("placement present"), Pose.IsSet()))
        { continue; }
        TestTrue(TEXT("placement preserves nonuniform scale"), Pose.GetValue().GetScale3D().Equals(Current.GetScale3D(), 1.0e-3));
        TestTrue(TEXT("placement samples location"), Pose.GetValue().GetLocation().Equals(FVector{500, 195, 0}, 1.0e-3));
        if (Orientation == ECk_Chain_LinkOrientation::FollowPath)
        {
            TestTrue(TEXT("forward follows tangent"), Pose.GetValue().GetRotation().GetForwardVector().Equals(FVector::RightVector, 1.0e-3));
            TestTrue(TEXT("up follows configured reference"), Pose.GetValue().GetRotation().GetUpVector().Equals(FVector::UpVector, 1.0e-3));
        }
        else
        {
            const auto Expected = Orientation == ECk_Chain_LinkOrientation::KeepOwn ? Current.GetRotation() : FQuat::Identity;
            TestTrue(TEXT("orientation policy retained"), Pose.GetValue().GetRotation().Equals(Expected, 1.0e-3));
        }
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Orientation_DegenerateUpFallsBackToSampled,
    "Ck.Chain.PathHistory.Orientation_DegenerateUpFallsBackToSampled", kCkUnitTestFlags)
bool FCk_Chain_Orientation_DegenerateUpFallsBackToSampled::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto Rotation = FRotator{0, 37, 0}.Quaternion();
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector, Rotation), 10.0f);
    History.Record(MakePose(FVector{0, 0, 100}, Rotation), 10.0f);
    AddExpectedError(TEXT("Chain orientation tangent is parallel to the configured up vector"), EAutomationExpectedErrorFlags::Contains, 2);
    const auto Pose = Solve_PathHistoryPose(History, MakeNewestPose(History), 50.0f, ECk_Chain_LinkOrientation::FollowPath,
        FVector::UpVector, ECk_Chain_HistorySeed::StraightBehindHead, FTransform::Identity);
    if (TestTrue(TEXT("degenerate orientation still produces pose"), Pose.IsSet()))
    {
        TestTrue(TEXT("sampled rotation used as fallback"), Pose.GetValue().GetRotation().Equals(Rotation, 1.0e-3));
        TestTrue(TEXT("fallback preserves sampled location"), Pose.GetValue().GetLocation().Equals(FVector{0, 0, 50}, 1.0e-3));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Solve_FollowsUnrecordedHeadChord,
    "Ck.Chain.PathHistory.Solve_FollowsUnrecordedHeadChord", kCkUnitTestFlags)
bool FCk_Chain_Solve_FollowsUnrecordedHeadChord::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeStraightHistory();
    const auto MovedHead = MakePose(FVector{1004, 0, 0});
    const auto StillHead = MakePose(FVector{1000, 0, 0});
    TestTrue(TEXT("leading arc adds the unrecorded chord"),
        FMath::IsNearlyEqual(Get_LeadingArcDistance(History, MovedHead), 1004.0f, 1.0e-3f));
    TestTrue(TEXT("leading arc equals newest arc when the head sits on it"),
        FMath::IsNearlyEqual(Get_LeadingArcDistance(History, StillHead), 1000.0f, 1.0e-3f));

    const auto TestPlacement = [&](const TCHAR* InWhat, const FPathHistory& InHistory, const FTransform& InHead,
        float InDistance, ECk_Chain_LinkOrientation InOrientation, ECk_Chain_HistorySeed InSeed,
        const FVector& InExpected) -> TOptional<FTransform>
    {
        const auto Pose = Solve_PathHistoryPose(InHistory, InHead, InDistance, InOrientation, FVector::UpVector,
            InSeed, FTransform::Identity);
        if (TestTrue(InWhat, Pose.IsSet()))
        { TestTrue(InWhat, Pose.GetValue().GetLocation().Equals(InExpected, 1.0e-3)); }
        return Pose;
    };

    TestPlacement(TEXT("link behind the chord samples recorded path"), History, MovedHead, 100.0f,
        ECk_Chain_LinkOrientation::KeepOwn, ECk_Chain_HistorySeed::StraightBehindHead, FVector{904, 0, 0});
    TestPlacement(TEXT("link inside the chord interpolates toward the head"), History, MovedHead, 2.0f,
        ECk_Chain_LinkOrientation::KeepOwn, ECk_Chain_HistorySeed::StraightBehindHead, FVector{1002, 0, 0});
    TestPlacement(TEXT("zero distance places at the head"), History, MovedHead, 0.0f,
        ECk_Chain_LinkOrientation::KeepOwn, ECk_Chain_HistorySeed::StraightBehindHead, FVector{1004, 0, 0});
    TestPlacement(TEXT("head without motion leaves placement unchanged"), History, StillHead, 100.0f,
        ECk_Chain_LinkOrientation::KeepOwn, ECk_Chain_HistorySeed::StraightBehindHead, FVector{900, 0, 0});

    const auto Facing = TestPlacement(TEXT("follow path inside the chord"), History, MovedHead, 2.0f,
        ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_HistorySeed::StraightBehindHead, FVector{1002, 0, 0});
    if (Facing.IsSet())
    {
        TestTrue(TEXT("chord forward follows head travel"), Facing.GetValue().GetRotation().GetForwardVector().Equals(FVector::ForwardVector, 1.0e-3));
        TestTrue(TEXT("chord up follows configured reference"), Facing.GetValue().GetRotation().GetUpVector().Equals(FVector::UpVector, 1.0e-3));
    }

    const auto TurnedHead = MakePose(FVector{1004, 0, 0}, FRotator{0, 90, 0}.Quaternion());
    const auto Copied = TestPlacement(TEXT("copy head inside the chord"), History, TurnedHead, 2.0f,
        ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_HistorySeed::StraightBehindHead, FVector{1002, 0, 0});
    if (Copied.IsSet())
    { TestTrue(TEXT("chord rotation slerps toward the head"), Copied.GetValue().GetRotation().Equals(FRotator{0, 45, 0}.Quaternion(), 1.0e-3)); }

    auto Seeded = FPathHistory{};
    Seeded.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    const auto EarlyHead = MakePose(FVector{5, 0, 0});
    TestFalse(TEXT("hold stays unset behind the oldest sample"), Solve_PathHistoryPose(Seeded, EarlyHead, 20.0f,
        ECk_Chain_LinkOrientation::KeepOwn, FVector::UpVector, ECk_Chain_HistorySeed::HoldUntilCovered,
        FTransform::Identity).IsSet());
    TestPlacement(TEXT("hold covers the oldest sample"), Seeded, EarlyHead, 15.0f,
        ECk_Chain_LinkOrientation::KeepOwn, ECk_Chain_HistorySeed::HoldUntilCovered, FVector{-10, 0, 0});
    const auto EarlyFacing = TestPlacement(TEXT("seeded chord interpolates toward the head"), Seeded, EarlyHead, 3.0f,
        ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_HistorySeed::HoldUntilCovered, FVector{2, 0, 0});
    if (EarlyFacing.IsSet())
    { TestTrue(TEXT("seeded chord forward follows head travel"), EarlyFacing.GetValue().GetRotation().GetForwardVector().Equals(FVector::ForwardVector, 1.0e-3)); }

    auto Idle = FPathHistory{};
    Idle.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    const auto AtHead = TestPlacement(TEXT("idle head places at the head"), Idle, MakePose(FVector::ZeroVector), 0.0f,
        ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_HistorySeed::StraightBehindHead, FVector::ZeroVector);
    if (AtHead.IsSet())
    { TestTrue(TEXT("idle head keeps the seed rotation"), AtHead.GetValue().GetRotation().Equals(Idle.Get_Sample(1).Get_Rotation(), 1.0e-3)); }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_ShortHistory_EmptyAndSingleAreDefined,
    "Ck.Chain.PathHistory.ShortHistory_EmptyAndSingleAreDefined", kCkUnitTestFlags)
bool FCk_Chain_ShortHistory_EmptyAndSingleAreDefined::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto Empty = FPathHistory{};
    TestEqual(TEXT("default history has no storage"), Empty.Get_AllocatedSize(), static_cast<SIZE_T>(0));
    TestFalse(TEXT("empty sample is unset"), Empty.Sample_AtArcDistance(0.0f, ECk_Chain_HistorySeed::StraightBehindHead).IsSet());
    TestTrue(TEXT("empty tangent is zero"), Empty.Tangent_AtArcDistance(0.0f).IsZero());
    TestEqual(TEXT("empty slice stays empty"), Empty.Slice_Behind(0.0f).Get_NumSamples(), 0);
    TestEqual(TEXT("empty leading arc is zero"), Get_LeadingArcDistance(Empty, MakePose(FVector{4, 0, 0})), 0.0f);
    TestFalse(TEXT("empty solve stays unset"), Solve_PathHistoryPose(Empty, MakePose(FVector{4, 0, 0}), 0.0f,
        ECk_Chain_LinkOrientation::CopyHead, FVector::UpVector, ECk_Chain_HistorySeed::StraightBehindHead,
        FTransform::Identity).IsSet());

    auto Seeded = FPathHistory{};
    Seeded.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    const auto One = Seeded.Slice_Behind(-10.0f);
    if (NOT TestEqual(TEXT("slice contains only the old seed sample"), One.Get_NumSamples(), 1))
    { return false; }

    TestTrue(TEXT("one-sample tangent is zero"), One.Tangent_AtArcDistance(-100.0f).IsZero());
    const auto Held = One.Sample_AtArcDistance(-100.0f, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("one-sample straight policy holds its pose"), Held.IsSet()))
    { TestTrue(TEXT("held sample location is unchanged"), Held.GetValue().Get_Location().Equals(FVector{-10, 0, 0}, 1.0e-3)); }

    TestFalse(TEXT("one-sample hold policy is unset below its arc"),
        One.Sample_AtArcDistance(-100.0f, ECk_Chain_HistorySeed::HoldUntilCovered).IsSet());
    TestEqual(TEXT("slice before oldest is empty"), Seeded.Slice_Behind(-11.0f).Get_NumSamples(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Ring_UndersizedHistoryEvictsOldestWithoutAllocation,
    "Ck.Chain.PathHistory.Ring_UndersizedHistoryEvictsOldestWithoutAllocation", kCkUnitTestFlags)
bool FCk_Chain_Ring_UndersizedHistoryEvictsOldestWithoutAllocation::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    const auto AllocatedBefore = History.Get_AllocatedSize();
    for (auto Index = 1; Index <= 100; ++Index)
    { TestTrue(TEXT("full ring still records"), History.Record(MakePose(FVector{Index * 10.0f, 0, 0}), 10.0f)); }

    TestEqual(TEXT("undersized ring keeps its bounded sample count"), History.Get_NumSamples(), 2);
    TestEqual(TEXT("undersized ring did not reallocate"), History.Get_AllocatedSize(), AllocatedBefore);
    TestTrue(TEXT("newest pose is current"), History.Get_Sample(1).Get_Location().Equals(FVector{1000, 0, 0}, 1.0e-3));
    TestTrue(TEXT("oldest pose was evicted in order"), History.Get_Sample(0).Get_Location().Equals(FVector{990, 0, 0}, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_InvalidInput_RejectsWithoutPartialMutation,
    "Ck.Chain.PathHistory.InvalidInput_RejectsWithoutPartialMutation", kCkUnitTestFlags)
bool FCk_Chain_InvalidInput_RejectsWithoutPartialMutation::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reserve_ForDistance(120.0f, 10.0f);
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    for (auto X = 10.0f; X <= 100.0f; X += 10.0f)
    { History.Record(MakePose(FVector{X, 0, 0}), 10.0f); }

    const auto Before = History.Get_Samples();
    const auto AllocatedBefore = History.Get_AllocatedSize();
    const auto Infinity = std::numeric_limits<float>::infinity();
    const auto Unnormalized = FTransform{FQuat{0, 0, 0, 2}, FVector{100, 0, 0}};
    const auto InfiniteHead = MakePose(FVector{std::numeric_limits<double>::infinity(), 0, 0});

    AddExpectedError(TEXT("Chain history spacing must be finite and positive"), EAutomationExpectedErrorFlags::Contains, 8);
    History.Reseed(MakePose(FVector{100, 0, 0}), -1.0f);
    History.Reseed(MakePose(FVector{100, 0, 0}), Infinity);
    TestFalse(TEXT("negative spacing record rejected"), History.Record(MakePose(FVector{200, 0, 0}), -1.0f));
    TestFalse(TEXT("infinite spacing record rejected"), History.Record(MakePose(FVector{200, 0, 0}), Infinity));
    AddExpectedError(TEXT("Chain history head pose must be finite and normalized"), EAutomationExpectedErrorFlags::Contains, 6);
    History.Reseed(Unnormalized, 10.0f);
    TestFalse(TEXT("unnormalized rotation record rejected"), History.Record(Unnormalized, 10.0f));
    TestFalse(TEXT("infinite location record rejected"), History.Record(InfiniteHead, 10.0f));
    AddExpectedError(TEXT("Chain history seed spacing is not representable at this location"), EAutomationExpectedErrorFlags::Contains, 2);
    History.Reseed(MakePose(FVector{1.0e17, 0, 0}), 10.0f);
    AddExpectedError(TEXT("Chain history reserve distance and spacing are invalid"), EAutomationExpectedErrorFlags::Contains, 4);
    History.Reserve_ForDistance(-1.0f, 10.0f);
    History.Reserve_ForDistance(Infinity, 10.0f);
    AddExpectedError(TEXT("Chain history trim distance must be finite and nonnegative"), EAutomationExpectedErrorFlags::Contains, 4);
    History.Trim(-1.0f);
    History.Trim(Infinity);
    AddExpectedError(TEXT("Chain history sample seed policy is invalid"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("invalid seed policy sample unset"), History.Sample_AtArcDistance(50.0f, static_cast<ECk_Chain_HistorySeed>(7)).IsSet());

    TestEqual(TEXT("invalid input leaves sample count untouched"), History.Get_NumSamples(), Before.Num());
    TestEqual(TEXT("invalid input does not allocate"), History.Get_AllocatedSize(), AllocatedBefore);
    for (auto Index = 0; Index < Before.Num(); ++Index)
    {
        TestTrue(TEXT("invalid input leaves sample location untouched"),
            History.Get_Sample(Index).Get_Location().Equals(Before[Index].Get_Location(), 1.0e-3));
        TestEqual(TEXT("invalid input leaves sample arc untouched"),
            History.Get_Sample(Index).Get_ArcDistanceCm(), Before[Index].Get_ArcDistanceCm());
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Solve_InvalidInputRejectsBeforePlacement,
    "Ck.Chain.PathHistory.Solve_InvalidInputRejectsBeforePlacement", kCkUnitTestFlags)
bool FCk_Chain_Solve_InvalidInputRejectsBeforePlacement::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    const auto History = MakeStraightHistory(100.0f);
    const auto Head = MakeNewestPose(History);
    const auto Solve = [&](const FTransform& InHead, ECk_Chain_LinkOrientation InOrientation, ECk_Chain_HistorySeed InSeed,
        const FTransform& InLink) -> bool
    {
        return Solve_PathHistoryPose(History, InHead, 20.0f, InOrientation, FVector::UpVector, InSeed, InLink).IsSet();
    };
    AddExpectedError(TEXT("Chain solver orientation is invalid"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("invalid orientation rejected"), Solve(Head, static_cast<ECk_Chain_LinkOrientation>(9),
        ECk_Chain_HistorySeed::StraightBehindHead, FTransform::Identity));
    AddExpectedError(TEXT("Chain solver history seed is invalid"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("invalid seed rejected"), Solve(Head, ECk_Chain_LinkOrientation::KeepOwn,
        static_cast<ECk_Chain_HistorySeed>(9), FTransform::Identity));
    AddExpectedError(TEXT("Chain link current pose must be finite and normalized"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("unnormalized link rotation rejected"), Solve(Head, ECk_Chain_LinkOrientation::KeepOwn,
        ECk_Chain_HistorySeed::StraightBehindHead, FTransform{FQuat{0, 0, 0, 2}}));
    AddExpectedError(TEXT("Chain solver head pose must be finite and normalized"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("unnormalized head rotation rejected"), Solve(FTransform{FQuat{0, 0, 0, 2}, Head.GetLocation()},
        ECk_Chain_LinkOrientation::KeepOwn, ECk_Chain_HistorySeed::StraightBehindHead, FTransform::Identity));
    TestTrue(TEXT("valid input still solves"), Solve(Head, ECk_Chain_LinkOrientation::KeepOwn,
        ECk_Chain_HistorySeed::StraightBehindHead, FTransform::Identity));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Extrapolation_LargeArcUsesFiniteDifference,
    "Ck.Chain.PathHistory.Extrapolation_LargeArcUsesFiniteDifference", kCkUnitTestFlags)
bool FCk_Chain_Extrapolation_LargeArcUsesFiniteDifference::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 1.0f);
    TestTrue(TEXT("large first record accepted"), History.Record(MakePose(FVector{1.0e38, 0, 0}), 1.0f));
    TestTrue(TEXT("large second record accepted"), History.Record(MakePose(FVector{2.0e38, 0, 0}), 1.0f));
    const auto Sample = History.Sample_AtArcDistance(-3.0e38f, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("large arc extrapolation remains set"), Sample.IsSet()))
    {
        TestTrue(TEXT("large arc extrapolation remains finite"), FMath::IsFinite(Sample.GetValue().Get_Location().X));
        TestTrue(TEXT("large arc extrapolation stays on the path"),
            FMath::IsNearlyEqual(Sample.GetValue().Get_Location().X / 1.0e38, -3.0, 1.0e-3));
    }

    const auto Before = History.Get_Samples();
    AddExpectedError(TEXT("Chain history arc distance must remain finite and increasing"), EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("record past the float arc domain rejected"), History.Record(MakePose(FVector::ZeroVector), 1.0f));
    TestEqual(TEXT("rejected record keeps the newest arc"), History.Get_HeadArcDistance(), Before.Last().Get_ArcDistanceCm());
    TestEqual(TEXT("rejected record keeps the sample count"), History.Get_NumSamples(), Before.Num());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Reseed_NearUnitHeadRotationSeedsExactSpacing,
    "Ck.Chain.PathHistory.Reseed_NearUnitHeadRotationSeedsExactSpacing", kCkUnitTestFlags)
bool FCk_Chain_Reseed_NearUnitHeadRotationSeedsExactSpacing::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto NearUnit = FRotator{0, 90, 0}.Quaternion();
    NearUnit *= FMath::Sqrt(1.005);
    const auto Head = FTransform{NearUnit, FVector{30, 40, 50}};
    if (NOT TestTrue(TEXT("fixture rotation is inside the normalized tolerance"), Head.IsRotationNormalized()))
    { return false; }

    auto History = FPathHistory{};
    History.Reseed(Head, 10.0f);
    if (NOT TestEqual(TEXT("near-unit rotation reseeds"), History.Get_NumSamples(), 2))
    { return false; }

    TestTrue(TEXT("seed sits exactly one spacing behind the head"),
        FMath::IsNearlyEqual(FVector::Distance(History.Get_Sample(0).Get_Location(), Head.GetLocation()), 10.0, 1.0e-3));
    TestTrue(TEXT("seed lies behind the head's facing"),
        History.Get_Sample(0).Get_Location().Equals(FVector{30, 30, 50}, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_Slice_RejectsUnrepresentableArcRebase,
    "Ck.Chain.PathHistory.Slice_RejectsUnrepresentableArcRebase", kCkUnitTestFlags)
bool FCk_Chain_Slice_RejectsUnrepresentableArcRebase::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    constexpr auto HugeSpacing = 3.0e38f;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), HugeSpacing);
    History.Reserve_ForDistance(HugeSpacing, HugeSpacing);
    TestTrue(TEXT("large positive arc sample accepted"),
        History.Record(MakePose(FVector{static_cast<double>(HugeSpacing), 0, 0}), HugeSpacing));
    const auto Before = History.Get_Samples();
    AddExpectedError(TEXT("Chain history slice arc rebase exceeded the finite float domain"), EAutomationExpectedErrorFlags::Contains, 2);
    const auto Slice = History.Slice_Behind(HugeSpacing);
    TestEqual(TEXT("unrepresentable slice is empty"), Slice.Get_NumSamples(), 0);
    TestEqual(TEXT("failed slice leaves the source count untouched"), History.Get_NumSamples(), Before.Num());
    for (auto Index = 0; Index < Before.Num(); ++Index)
    { TestEqual(TEXT("failed slice leaves source arcs untouched"), History.Get_Sample(Index).Get_ArcDistanceCm(), Before[Index].Get_ArcDistanceCm()); }

    auto Ordering = FPathHistory{};
    Ordering.Reseed(MakePose(FVector::ZeroVector), 1.0e30f);
    Ordering.Reserve_ForDistance(1.0e30f, 1.0e30f);
    TestTrue(TEXT("large ordering sample accepted"), Ordering.Record(MakePose(FVector{1.0e38, 0, 0}), 1.0e30f));
    AddExpectedError(TEXT("Chain history slice arc rebase cannot preserve sample ordering"), EAutomationExpectedErrorFlags::Contains, 2);
    TestEqual(TEXT("slice rejects arcs that collapse after the float rebase"), Ordering.Slice_Behind(1.0e38f).Get_NumSamples(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_MoveAndCopy_PreserveValueInvariants,
    "Ck.Chain.PathHistory.MoveAndCopy_PreserveValueInvariants", kCkUnitTestFlags)
bool FCk_Chain_MoveAndCopy_PreserveValueInvariants::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto Source = FPathHistory{};
    Source.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    Source.Reserve_ForDistance(30.0f, 10.0f);
    for (auto Index = 1; Index <= 10; ++Index)
    { Source.Record(MakePose(FVector{Index * 10.0f, 0, 0}), 10.0f); }

    const auto OriginalCount = Source.Get_NumSamples();
    TestEqual(TEXT("wrapped fixture retains five samples"), OriginalCount, 5);
    TestTrue(TEXT("wrapped fixture oldest is ordered"), Source.Get_Sample(0).Get_Location().Equals(FVector{60, 0, 0}, 1.0e-3));

    auto Moved = MoveTemp(Source);
    TestEqual(TEXT("move construction preserves the history"), Moved.Get_NumSamples(), OriginalCount);
    TestTrue(TEXT("move construction preserves the wrapped oldest"), Moved.Get_Sample(0).Get_Location().Equals(FVector{60, 0, 0}, 1.0e-3));
    TestTrue(TEXT("move construction preserves the wrapped newest"), Moved.Get_Sample(4).Get_Location().Equals(FVector{100, 0, 0}, 1.0e-3));
    TestEqual(TEXT("move construction empties the source"), Source.Get_NumSamples(), 0);
    TestFalse(TEXT("moved-from history samples as empty"), Source.Sample_AtArcDistance(0.0f, ECk_Chain_HistorySeed::StraightBehindHead).IsSet());
    TestTrue(TEXT("moved-from history has no tangent"), Source.Tangent_AtArcDistance(0.0f).IsZero());
    Source.Reseed(MakePose(FVector{1000, 0, 0}), 10.0f);
    TestEqual(TEXT("moved-from history can reseed"), Source.Get_NumSamples(), 2);
    TestTrue(TEXT("reseeded head is correct"), Source.Get_Sample(1).Get_Location().Equals(FVector{1000, 0, 0}, 1.0e-3));
    TestTrue(TEXT("reseeded history records"), Source.Record(MakePose(FVector{1010, 0, 0}), 10.0f));

    auto Destination = FPathHistory{};
    Destination = MoveTemp(Moved);
    TestEqual(TEXT("move assignment preserves the history"), Destination.Get_NumSamples(), OriginalCount);
    TestTrue(TEXT("move assignment preserves the wrapped oldest"), Destination.Get_Sample(0).Get_Location().Equals(FVector{60, 0, 0}, 1.0e-3));
    TestEqual(TEXT("move assignment empties the source"), Moved.Get_NumSamples(), 0);
    Moved.Reseed(MakePose(FVector{2000, 0, 0}), 10.0f);
    TestEqual(TEXT("move-assigned source can reseed"), Moved.Get_NumSamples(), 2);

    const auto Copy = Destination;
    auto CopyAssigned = FPathHistory{};
    CopyAssigned = Destination;
    TestTrue(TEXT("destination accepts a later record"), Destination.Record(MakePose(FVector{110, 0, 0}), 10.0f));
    TestTrue(TEXT("copy construction remains independent"), Copy.Get_Sample(0).Get_Location().Equals(FVector{60, 0, 0}, 1.0e-3));
    TestTrue(TEXT("copy assignment remains independent"), CopyAssigned.Get_Sample(0).Get_Location().Equals(FVector{60, 0, 0}, 1.0e-3));
    TestTrue(TEXT("destination wrap advances its oldest"), Destination.Get_Sample(0).Get_Location().Equals(FVector{70, 0, 0}, 1.0e-3));
    const auto BeforeSelfMove = Destination.Get_NumSamples();
    const auto BeforeSelfMoveOldest = Destination.Get_Sample(0).Get_Location();
    auto& Alias = Destination;
    Destination = MoveTemp(Alias);
    TestEqual(TEXT("self move leaves a valid history"), Destination.Get_NumSamples(), BeforeSelfMove);
    TestTrue(TEXT("self move keeps sample ordering"), Destination.Get_Sample(0).Get_Location().Equals(BeforeSelfMoveOldest, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_LiveHead_SubspacingMotionAndStopStayContinuous,
    "Ck.Chain.PathHistory.LiveHead_SubspacingMotionAndStopStayContinuous", kCkUnitTestFlags)
bool FCk_Chain_LiveHead_SubspacingMotionAndStopStayContinuous::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    History.Reserve_ForDistance(30.0f, 10.0f);
    const auto AllocatedBefore = History.Get_AllocatedSize();
    const auto Link = FTransform{FQuat::Identity, FVector{-5, 0, 0}, FVector{2, 3, 4}};
    const auto SolveAt = [&](const FTransform& InHead) -> TOptional<FTransform>
    {
        return Solve_PathHistoryPose(History, InHead, 5.0f, ECk_Chain_LinkOrientation::FollowPath, FVector::UpVector,
            ECk_Chain_HistorySeed::StraightBehindHead, Link);
    };
    for (auto X = 1; X <= 69; ++X)
    {
        const auto Head = MakePose(FVector{static_cast<double>(X), 0, 0});
        TestEqual(TEXT("Record accepts exactly on ten-centimetre boundaries"), History.Record(Head, 10.0f), X % 10 == 0);
        TestEqual(TEXT("retained head arc changes only on Record"), History.Get_HeadArcDistance(), static_cast<float>((X / 10) * 10));
        const auto Solved = SolveAt(Head);
        if (TestTrue(TEXT("sub-spacing live pose exists"), Solved.IsSet()))
        {
            TestTrue(TEXT("sub-spacing output moves one centimetre per step"),
                Solved.GetValue().GetLocation().Equals(FVector{static_cast<double>(X - 5), 0, 0}, 1.0e-3));
            TestTrue(TEXT("live tangent faces motion"), Solved.GetValue().GetRotation().GetForwardVector().Equals(FVector::ForwardVector, 1.0e-3));
            TestTrue(TEXT("live pose keeps link scale"), Solved.GetValue().GetScale3D().Equals(FVector{2, 3, 4}, 1.0e-3));
        }

        TestEqual(TEXT("live reads and wrapped Record keep ring bytes fixed"), History.Get_AllocatedSize(), AllocatedBefore);
        if (X % 10 == 9)
        {
            TestFalse(TEXT("stopped head does not append"), History.Record(Head, 10.0f));
            const auto Stopped = SolveAt(Head);
            if (TestTrue(TEXT("stopped live pose exists"), Stopped.IsSet()))
            { TestTrue(TEXT("stopped live output holds its location"), Stopped.GetValue().GetLocation().Equals(FVector{static_cast<double>(X - 5), 0, 0}, 1.0e-3)); }
        }
    }

    TestEqual(TEXT("wrapped ring retains its bounded sample count"), History.Get_NumSamples(), 5);
    TestEqual(TEXT("retained arc before the final crossing"), History.Get_HeadArcDistance(), 60.0f);
    const auto CrossingHead = MakePose(FVector{70, 0, 0});
    TestTrue(TEXT("spacing crossing appends exactly once"), History.Record(CrossingHead, 10.0f));
    const auto Crossing = SolveAt(CrossingHead);
    if (TestTrue(TEXT("crossing pose exists"), Crossing.IsSet()))
    { TestTrue(TEXT("crossing advances one centimetre, without a spacing jump"), Crossing.GetValue().GetLocation().Equals(FVector{65, 0, 0}, 1.0e-3)); }

    TestEqual(TEXT("crossing preserves the bounded ring count"), History.Get_NumSamples(), 5);
    TestEqual(TEXT("live reads and Record do not grow the reserved ring"), History.Get_AllocatedSize(), AllocatedBefore);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_LiveHead_OrientationsAndScaleUseTransientSegment,
    "Ck.Chain.PathHistory.LiveHead_OrientationsAndScaleUseTransientSegment", kCkUnitTestFlags)
bool FCk_Chain_LiveHead_OrientationsAndScaleUseTransientSegment::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    const auto OwnRotation = FRotator{0, 123, 0}.Quaternion();
    const auto Head = MakePose(FVector{4, 0, 0}, FRotator{0, 90, 0}.Quaternion());
    const auto Link = FTransform{OwnRotation, FVector{-2, 0, 0}, FVector{2, 3, 4}};
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath,
        ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_LinkOrientation::KeepOwn};
    const auto ExpectedRotations = TArray<FQuat>{FQuat::Identity, FRotator{0, 45, 0}.Quaternion(), OwnRotation};
    for (auto Index = 0; Index < Orientations.Num(); ++Index)
    {
        const auto Solved = Solve_PathHistoryPose(History, Head, 2.0f, Orientations[Index], FVector::UpVector,
            ECk_Chain_HistorySeed::StraightBehindHead, Link);
        if (NOT TestTrue(TEXT("live orientation pose exists"), Solved.IsSet()))
        { continue; }

        TestTrue(TEXT("live orientation uses the interpolated location"), Solved.GetValue().GetLocation().Equals(FVector{2, 0, 0}, 1.0e-3));
        TestTrue(TEXT("live orientation follows the selected policy"), Solved.GetValue().GetRotation().Equals(ExpectedRotations[Index], 1.0e-3));
        TestTrue(TEXT("live orientation preserves link scale"), Solved.GetValue().GetScale3D().Equals(FVector{2, 3, 4}, 1.0e-3));
    }

    TestEqual(TEXT("live reads do not append"), History.Get_NumSamples(), 2);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_LiveHead_OneSampleAndRotationOnlyAreDefined,
    "Ck.Chain.PathHistory.LiveHead_OneSampleAndRotationOnlyAreDefined", kCkUnitTestFlags)
bool FCk_Chain_LiveHead_OneSampleAndRotationOnlyAreDefined::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto Seeded = FPathHistory{};
    Seeded.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    const auto One = Seeded.Slice_Behind(-10.0f);
    if (NOT TestEqual(TEXT("one-sample fixture has one retained pose"), One.Get_NumSamples(), 1))
    { return false; }

    TestEqual(TEXT("one-sample slice rebases the retained arc to zero"), One.Get_Sample(0).Get_ArcDistanceCm(), 0.0f);
    const auto Head = MakePose(FVector{-7, 0, 0});
    const auto SolveAt = [&](const FTransform& InHead, float InDistance, ECk_Chain_LinkOrientation InOrientation,
        ECk_Chain_HistorySeed InSeed) -> TOptional<FTransform>
    {
        return Solve_PathHistoryPose(One, InHead, InDistance, InOrientation, FVector::UpVector, InSeed, FTransform::Identity);
    };
    TestTrue(TEXT("one-sample leading arc adds the live chord"), FMath::IsNearlyEqual(Get_LeadingArcDistance(One, Head), 3.0f, 1.0e-3f));
    const auto Middle = SolveAt(Head, 1.5f, ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("retained-to-head chord interpolates"), Middle.IsSet()))
    {
        TestTrue(TEXT("one-sample live midpoint is continuous"), Middle.GetValue().GetLocation().Equals(FVector{-8.5, 0, 0}, 1.0e-3));
        TestTrue(TEXT("one-sample live tangent follows the chord"), Middle.GetValue().GetRotation().GetForwardVector().Equals(FVector::ForwardVector, 1.0e-3));
    }

    const auto AtHead = SolveAt(Head, 0.0f, ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("zero distance reaches the head"), AtHead.IsSet()))
    { TestTrue(TEXT("one-sample head placement"), AtHead.GetValue().GetLocation().Equals(FVector{-7, 0, 0}, 1.0e-3)); }

    const auto Behind = SolveAt(Head, 4.0f, ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_HistorySeed::StraightBehindHead);
    if (TestTrue(TEXT("straight seed holds below the retained pose"), Behind.IsSet()))
    {
        TestTrue(TEXT("held location is the retained pose"), Behind.GetValue().GetLocation().Equals(FVector{-10, 0, 0}, 1.0e-3));
        TestTrue(TEXT("no retained segment keeps the sampled rotation"), Behind.GetValue().GetRotation().Equals(FQuat::Identity, 1.0e-3));
    }

    TestFalse(TEXT("hold seed stays unset below the retained pose"),
        SolveAt(Head, 4.0f, ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_HistorySeed::HoldUntilCovered).IsSet());

    const auto RotationOnly = FRotator{0, 90, 0}.Quaternion();
    const auto ZeroChordHead = MakePose(FVector{-10, 0, 0}, RotationOnly);
    for (const auto Orientation : {ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_LinkOrientation::FollowPath})
    {
        const auto Rotated = SolveAt(ZeroChordHead, 0.0f, Orientation, ECk_Chain_HistorySeed::StraightBehindHead);
        if (TestTrue(TEXT("zero-chord live pose exists"), Rotated.IsSet()))
        {
            TestTrue(TEXT("zero-chord live pose reads the head rotation"), Rotated.GetValue().GetRotation().Equals(RotationOnly, 1.0e-3));
            TestTrue(TEXT("zero-chord live pose stays at the head"), Rotated.GetValue().GetLocation().Equals(FVector{-10, 0, 0}, 1.0e-3));
        }
    }

    TestEqual(TEXT("live short-history reads do not append"), One.Get_NumSamples(), 1);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_LiveHead_ReversalPreservesCumulativePathAndContinuity,
    "Ck.Chain.PathHistory.LiveHead_ReversalPreservesCumulativePathAndContinuity", kCkUnitTestFlags)
bool FCk_Chain_LiveHead_ReversalPreservesCumulativePathAndContinuity::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    History.Reserve_ForDistance(30.0f, 10.0f);
    TestTrue(TEXT("outbound path is recorded"), History.Record(MakePose(FVector{10, 0, 0}), 10.0f));
    const auto AllocatedBefore = History.Get_AllocatedSize();
    const auto SolveAt = [&](const FTransform& InHead, float InDistance, ECk_Chain_LinkOrientation InOrientation) -> TOptional<FTransform>
    {
        return Solve_PathHistoryPose(History, InHead, InDistance, InOrientation, FVector::UpVector,
            ECk_Chain_HistorySeed::StraightBehindHead, FTransform::Identity);
    };

    const auto FirstReverseHead = MakePose(FVector{9, 0, 0});
    const auto BeforeBoundary = SolveAt(FirstReverseHead, 2.0f, ECk_Chain_LinkOrientation::FollowPath);
    if (TestTrue(TEXT("pose below the retained-to-live boundary exists"), BeforeBoundary.IsSet()))
    { TestTrue(TEXT("tangent below the boundary follows the old path"), BeforeBoundary.GetValue().GetRotation().GetForwardVector().Equals(FVector::ForwardVector, 1.0e-3)); }

    const auto AtBoundary = SolveAt(FirstReverseHead, 1.0f, ECk_Chain_LinkOrientation::FollowPath);
    if (TestTrue(TEXT("pose at the boundary exists"), AtBoundary.IsSet()))
    {
        TestTrue(TEXT("boundary stays at the retained head"), AtBoundary.GetValue().GetLocation().Equals(FVector{10, 0, 0}, 1.0e-3));
        TestTrue(TEXT("tangent at the boundary follows the reversal"), AtBoundary.GetValue().GetRotation().GetForwardVector().Equals(-FVector::ForwardVector, 1.0e-3));
    }

    for (auto X = 9; X >= 0; --X)
    {
        const auto Head = MakePose(FVector{static_cast<double>(X), 0, 0});
        TestEqual(TEXT("reverse Record accepts only the full chord"), History.Record(Head, 10.0f), X == 0);
        const auto ReverseTravel = 10 - X;
        const auto ExpectedX = ReverseTravel <= 5 ? 5 + ReverseTravel : 15 - ReverseTravel;
        const auto Solved = SolveAt(Head, 5.0f, ECk_Chain_LinkOrientation::CopyHead);
        if (TestTrue(TEXT("reverse live pose exists"), Solved.IsSet()))
        { TestTrue(TEXT("reverse placement follows the cumulative path continuously"), Solved.GetValue().GetLocation().Equals(FVector{static_cast<double>(ExpectedX), 0, 0}, 1.0e-3)); }

        TestEqual(TEXT("reverse sampling keeps ring bytes fixed"), History.Get_AllocatedSize(), AllocatedBefore);
    }

    TestEqual(TEXT("reverse Record adds its chord to the cumulative arc"), History.Get_HeadArcDistance(), 20.0f);
    TestEqual(TEXT("reverse Record appends one sample"), History.Get_NumSamples(), 4);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_LiveHead_UnrepresentablePoseRejectsWithoutMutation,
    "Ck.Chain.PathHistory.LiveHead_UnrepresentablePoseRejectsWithoutMutation", kCkUnitTestFlags)
bool FCk_Chain_LiveHead_UnrepresentablePoseRejectsWithoutMutation::RunTest(const FString& Parameters)
{
    using namespace ck_test_chain_pathhistory;
    auto History = FPathHistory{};
    History.Reseed(MakePose(FVector::ZeroVector), 10.0f);
    History.Reserve_ForDistance(40.0f, 10.0f);
    TestTrue(TEXT("fixture records"), History.Record(MakePose(FVector{10, 0, 0}), 10.0f));
    const auto Before = History.Get_Samples();
    const auto AllocatedBefore = History.Get_AllocatedSize();
    const auto CheckRejected = [&](const FTransform& InHead) -> void
    {
        TestFalse(TEXT("rejected head cannot solve a pose"), Solve_PathHistoryPose(History, InHead, 5.0f,
            ECk_Chain_LinkOrientation::FollowPath, FVector::UpVector, ECk_Chain_HistorySeed::StraightBehindHead,
            FTransform::Identity).IsSet());
        TestEqual(TEXT("rejected head leaves the leading arc at the newest sample"), Get_LeadingArcDistance(History, InHead), 10.0f);
    };
    AddExpectedError(TEXT("Chain solver head pose must be finite and normalized"), EAutomationExpectedErrorFlags::Contains, 4);
    CheckRejected(MakePose(FVector{std::numeric_limits<double>::infinity(), 0, 0}));
    AddExpectedError(TEXT("Chain history leading arc distance exceeded the finite float domain"), EAutomationExpectedErrorFlags::Contains, 8);
    CheckRejected(MakePose(FVector{4.0e38, 0, 0}));
    CheckRejected(MakePose(FVector{1.0e200, -1.0e200, 1.0e200}));

    TestEqual(TEXT("rejected heads preserve the sample count"), History.Get_NumSamples(), Before.Num());
    TestEqual(TEXT("rejected heads do not allocate"), History.Get_AllocatedSize(), AllocatedBefore);
    for (auto Index = 0; Index < Before.Num(); ++Index)
    {
        TestTrue(TEXT("rejected heads preserve sample locations"), History.Get_Sample(Index).Get_Location().Equals(Before[Index].Get_Location(), 1.0e-3));
        TestEqual(TEXT("rejected heads preserve sample arcs"), History.Get_Sample(Index).Get_ArcDistanceCm(), Before[Index].Get_ArcDistanceCm());
    }

    return true;
}
