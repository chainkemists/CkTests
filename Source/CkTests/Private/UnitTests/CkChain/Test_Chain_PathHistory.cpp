#include "Misc/AutomationTest.h"
#include "Math/RandomStream.h"

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
