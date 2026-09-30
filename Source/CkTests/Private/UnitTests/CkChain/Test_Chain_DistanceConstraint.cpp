#include "Misc/AutomationTest.h"
#include "Math/RandomStream.h"

#include "CkChain/CkChain_PathHistory.h"
#include "../CkUnitTest_Common.h"

// Editor automation records both the ensure log and its outside-PIE error message.

namespace ck_test_chain_distanceconstraint
{
    auto TestLengths(FAutomationTestBase& InTest, const FTransform& InHead,
        const TArray<float>& InLengths, const TArray<FTransform>& InPoses) -> void
    {
        auto Previous = InHead.GetLocation();
        for (auto Index = 0; Index < InPoses.Num(); ++Index)
        {
            InTest.TestTrue(TEXT("solved segment has requested length"),
                FMath::Abs(FVector::Distance(Previous, InPoses[Index].GetLocation()) - InLengths[Index]) <= 1.0e-3);
            Previous = InPoses[Index].GetLocation();
        }
    }
}

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_PreservesSegmentLengths,
    "Ck.Chain.DistanceConstraint.DistanceConstraint_PreservesSegmentLengths", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_PreservesSegmentLengths::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    auto Random = FRandomStream{314159};
    const auto Head = FTransform{FRotator{0, 25, 0}.Quaternion(), FVector{100, 200, 300}};
    const auto Lengths = TArray<float>{35.0f, 110.0f, 75.0f};
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath,
        ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_LinkOrientation::KeepOwn};
    for (auto Trial = 0; Trial < 50; ++Trial)
    {
        auto Poses = TArray<FTransform>{};
        for (auto Index = 0; Index < Lengths.Num(); ++Index)
        {
            Poses.Add(FTransform{FRotator{0, Random.FRandRange(-180.0f, 180.0f), 0}.Quaternion(),
                FVector{Random.FRandRange(-500.0f, 500.0f), Random.FRandRange(-500.0f, 500.0f), 300},
                FVector{2.0 + Index, 3.0 + Index, 4.0 + Index}});
        }
        const auto Before = Poses;
        Solve_DistanceConstraint(Head, Lengths, Orientations, FVector::UpVector, Poses);
        ck_test_chain_distanceconstraint::TestLengths(*this, Head, Lengths, Poses);
        auto Previous = Head.GetLocation();
        for (auto Index = 0; Index < Poses.Num(); ++Index)
        {
            TestTrue(TEXT("nonuniform scale preserved"), Poses[Index].GetScale3D().Equals(Before[Index].GetScale3D(), 1.0e-3));
            if (Orientations[Index] == ECk_Chain_LinkOrientation::KeepOwn)
            { TestTrue(TEXT("KeepOwn retains current rotation"), Poses[Index].GetRotation().Equals(Before[Index].GetRotation(), 1.0e-3)); }
            else
            {
                const auto ExpectedForward = (Previous - Poses[Index].GetLocation()).GetSafeNormal();
                TestTrue(TEXT("FollowPath and CopyHead face solved predecessor"),
                    Poses[Index].GetRotation().GetForwardVector().Equals(ExpectedForward, 1.0e-3));
                TestTrue(TEXT("up follows reference"), Poses[Index].GetRotation().GetUpVector().Equals(FVector::UpVector, 1.0e-3));
            }
            Previous = Poses[Index].GetLocation();
        }
    }
    auto InvalidPoses = TArray<FTransform>{FTransform{FQuat::Identity, FVector{20, 30, 300}},
        FTransform{FQuat::Identity, FVector{40, 50, 300}}, FTransform{FQuat::Identity, FVector{60, 70, 300}}};
    const auto BeforeInvalid = InvalidPoses;
    const auto InvalidLengths = TArray<float>{35.0f, -1.0f, 75.0f};
    AddExpectedError(TEXT("Chain distance solver link input is invalid"), EAutomationExpectedErrorFlags::Contains, 2);
    Solve_DistanceConstraint(Head, InvalidLengths, Orientations, FVector::UpVector, InvalidPoses);
    for (auto Index = 0; Index < InvalidPoses.Num(); ++Index)
    { TestTrue(TEXT("invalid segment leaves entire roster unchanged"), InvalidPoses[Index].Equals(BeforeInvalid[Index], 1.0e-3)); }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_ZeroDirectionUsesHeadBackward,
    "Ck.Chain.DistanceConstraint.DistanceConstraint_ZeroDirectionUsesHeadBackward", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_ZeroDirectionUsesHeadBackward::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    const auto Head = FTransform{FRotator{0, 90, 0}.Quaternion(), FVector{100, 200, 300}};
    const auto Lengths = TArray<float>{40.0f, 60.0f};
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath,
        ECk_Chain_LinkOrientation::KeepOwn};
    const auto OwnRotation = FRotator{0, -25, 0}.Quaternion();
    auto Poses = TArray<FTransform>{FTransform{FQuat::Identity, Head.GetLocation(), FVector{2, 3, 4}},
        FTransform{OwnRotation, Head.GetLocation() - Head.GetRotation().GetForwardVector() * 40.0f, FVector{4, 5, 6}}};
    Solve_DistanceConstraint(Head, Lengths, Orientations, FVector::UpVector, Poses);
    TestTrue(TEXT("coincident first link uses head backward"), Poses[0].GetLocation().Equals(FVector{100, 160, 300}, 1.0e-3));
    TestTrue(TEXT("coincident solved predecessor also uses head backward"), Poses[1].GetLocation().Equals(FVector{100, 100, 300}, 1.0e-3));
    TestTrue(TEXT("first link faces head"), Poses[0].GetRotation().GetForwardVector().Equals(FVector::RightVector, 1.0e-3));
    TestTrue(TEXT("fallback retains KeepOwn"), Poses[1].GetRotation().Equals(OwnRotation, 1.0e-3));
    TestTrue(TEXT("fallback preserves first scale"), Poses[0].GetScale3D().Equals(FVector{2, 3, 4}, 1.0e-3));
    TestTrue(TEXT("fallback preserves second scale"), Poses[1].GetScale3D().Equals(FVector{4, 5, 6}, 1.0e-3));
    ck_test_chain_distanceconstraint::TestLengths(*this, Head, Lengths, Poses);
    const auto ThresholdLengths = TArray<float>{100.0f};
    const auto ThresholdOrientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath};
    auto ThresholdPoses = TArray<FTransform>{FTransform{FQuat::Identity, FVector{0.000099999998, 0, 0}}};
    Solve_DistanceConstraint(FTransform::Identity, ThresholdLengths, ThresholdOrientations, FVector::UpVector, ThresholdPoses);
    ck_test_chain_distanceconstraint::TestLengths(*this, FTransform::Identity, ThresholdLengths, ThresholdPoses);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_IsOrderIndependentOfDeltaT,
    "Ck.Chain.DistanceConstraint.DistanceConstraint_IsOrderIndependentOfDeltaT", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_IsOrderIndependentOfDeltaT::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    const auto Head = FTransform{FRotator{0, 15, 0}.Quaternion(), FVector{30, 40, 50}};
    const auto Lengths = TArray<float>{50.0f, 80.0f, 120.0f};
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath,
        ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_LinkOrientation::KeepOwn};
    const auto Initial = TArray<FTransform>{FTransform{FQuat::Identity, FVector{-100, 80, 50}, FVector{2, 3, 4}},
        FTransform{FQuat::Identity, FVector{50, -200, 50}, FVector{3, 4, 5}},
        FTransform{FRotator{0, 42, 0}.Quaternion(), FVector{-300, -250, 50}, FVector{4, 5, 6}}};
    auto First = Initial;
    auto Second = Initial;
    Solve_DistanceConstraint(Head, Lengths, Orientations, FVector::UpVector, First);
    Solve_DistanceConstraint(Head, Lengths, Orientations, FVector::UpVector, Second);
    for (auto Index = 0; Index < First.Num(); ++Index)
    { TestTrue(TEXT("identical inputs produce identical full poses"), First[Index].Equals(Second[Index], 1.0e-3)); }
    const auto Solved = First;
    Solve_DistanceConstraint(Head, Lengths, Orientations, FVector::UpVector, First);
    for (auto Index = 0; Index < First.Num(); ++Index)
    { TestTrue(TEXT("solving output again is idempotent"), First[Index].Equals(Solved[Index], 1.0e-3)); }
    const auto TieLengths = TArray<float>{50.0f, 0.0f, 120.0f};
    auto Tied = Initial;
    Solve_DistanceConstraint(Head, TieLengths, Orientations, FVector::UpVector, Tied);
    TestTrue(TEXT("zero segment places link at solved predecessor"), Tied[1].GetLocation().Equals(Tied[0].GetLocation(), 1.0e-3));
    TestTrue(TEXT("zero segment preserves authored rotation"), Tied[1].GetRotation().Equals(Initial[1].GetRotation(), 1.0e-3));
    const auto TiedSolved = Tied;
    Solve_DistanceConstraint(Head, TieLengths, Orientations, FVector::UpVector, Tied);
    for (auto Index = 0; Index < Tied.Num(); ++Index)
    { TestTrue(TEXT("zero-length tie remains idempotent"), Tied[Index].Equals(TiedSolved[Index], 1.0e-3)); }
    ck_test_chain_distanceconstraint::TestLengths(*this, Head, TieLengths, Tied);
    auto EmptyPoses = TArray<FTransform>{};
    const auto EmptyLengths = TArray<float>{};
    const auto EmptyOrientations = TArray<ECk_Chain_LinkOrientation>{};
    Solve_DistanceConstraint(Head, EmptyLengths, EmptyOrientations, FVector::UpVector, EmptyPoses);
    TestTrue(TEXT("empty roster remains empty"), EmptyPoses.IsEmpty());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_InvalidInput_RejectsWithoutPartialMutation,
    "Ck.Chain.DistanceConstraint.InvalidInput_RejectsWithoutPartialMutation", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_InvalidInput_RejectsWithoutPartialMutation::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath,
        ECk_Chain_LinkOrientation::KeepOwn};
    const auto Initial = TArray<FTransform>{FTransform{FQuat::Identity, FVector{-35, 0, 0}},
        FTransform{FQuat::Identity, FVector{-70, 0, 0}}};
    const auto SingleLength = TArray<float>{100.0f};
    const auto LateInvalidLengths = TArray<float>{100.0f, -1.0f};
    const auto ValidLengths = TArray<float>{100.0f, 100.0f};
    const auto LateDerivedLengths = TArray<float>{1.0e20f, 100.0f};
    const auto SingleKeepOwn = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::KeepOwn};
    const auto SingleFollowPath = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath};
    const auto TestUntouched = [&](const TCHAR* InWhat, const TArray<FTransform>& InPoses, const TArray<FTransform>& InBefore) -> void
    {
        for (auto Index = 0; Index < InPoses.Num(); ++Index)
        { TestTrue(InWhat, InPoses[Index].Equals(InBefore[Index], 0.0)); }
    };

    auto Poses = Initial;
    AddExpectedError(TEXT("Chain distance solver input arrays must have matching lengths"), EAutomationExpectedErrorFlags::Contains, 2);
    Solve_DistanceConstraint(FTransform::Identity, SingleLength, Orientations, FVector::UpVector, Poses);
    TestUntouched(TEXT("mismatched arrays leave every pose untouched"), Poses, Initial);

    AddExpectedError(TEXT("Chain distance solver link input is invalid"), EAutomationExpectedErrorFlags::Contains, 2);
    Solve_DistanceConstraint(FTransform::Identity, LateInvalidLengths, Orientations, FVector::UpVector, Poses);
    TestUntouched(TEXT("late invalid segment leaves the earlier pose untouched"), Poses, Initial);

    AddExpectedError(TEXT("Chain distance solver head pose must be finite and normalized"), EAutomationExpectedErrorFlags::Contains, 2);
    Solve_DistanceConstraint(FTransform{FQuat{0, 0, 0, 2}}, ValidLengths, Orientations, FVector::UpVector, Poses);
    TestUntouched(TEXT("unnormalized head leaves every pose untouched"), Poses, Initial);

    AddExpectedError(TEXT("Chain distance solver produced an unrepresentable segment"), EAutomationExpectedErrorFlags::Contains, 4);
    Solve_DistanceConstraint(FTransform{FQuat::Identity, FVector{1.0e200, 0, 0}}, ValidLengths, Orientations,
        FVector::UpVector, Poses);
    TestUntouched(TEXT("segment lost at a huge head coordinate leaves every pose untouched"), Poses, Initial);

    auto LateDerived = TArray<FTransform>{FTransform{FQuat::Identity, FVector{1, 0, 0}}, FTransform{FQuat::Identity, FVector{2, 0, 0}}};
    const auto LateDerivedBefore = LateDerived;
    Solve_DistanceConstraint(FTransform::Identity, LateDerivedLengths, Orientations, FVector::UpVector, LateDerived);
    TestUntouched(TEXT("second segment lost at the first solved coordinate leaves the first pose untouched"), LateDerived, LateDerivedBefore);

    auto FarButSolvable = TArray<FTransform>{FTransform{FQuat::Identity, FVector{1.0e18, 0, 0}}};
    Solve_DistanceConstraint(FTransform::Identity, SingleLength, SingleKeepOwn,
        FVector::UpVector, FarButSolvable);
    TestTrue(TEXT("a far current pose still solves to a representable head-relative location"),
        FarButSolvable[0].GetLocation().Equals(FVector{100, 0, 0}, 1.0e-3));

    auto HugeOffset = TArray<FTransform>{FTransform{FQuat::Identity, FVector{1.0e200, 1.0e200, 0}}};
    Solve_DistanceConstraint(FTransform::Identity, SingleLength, SingleFollowPath,
        FVector::UpVector, HugeOffset);
    TestTrue(TEXT("a finite huge offset normalizes to its direction"),
        HugeOffset[0].GetLocation().Equals(FVector{100.0 / FMath::Sqrt(2.0), 100.0 / FMath::Sqrt(2.0), 0}, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_NearUnitHeadRotationFallbackKeepsSegmentLength,
    "Ck.Chain.DistanceConstraint.NearUnitHeadRotationFallbackKeepsSegmentLength", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_NearUnitHeadRotationFallbackKeepsSegmentLength::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    auto NearUnit = FRotator{0, 90, 0}.Quaternion();
    NearUnit *= FMath::Sqrt(1.005);
    const auto Head = FTransform{NearUnit, FVector{100, 200, 300}};
    if (NOT TestTrue(TEXT("fixture rotation is inside the normalized tolerance"), Head.IsRotationNormalized()))
    { return false; }

    const auto Lengths = TArray<float>{100.0f};
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::KeepOwn};
    auto Poses = TArray<FTransform>{FTransform{FQuat::Identity, Head.GetLocation()}};
    Solve_DistanceConstraint(Head, Lengths, Orientations, FVector::UpVector, Poses);
    ck_test_chain_distanceconstraint::TestLengths(*this, Head, Lengths, Poses);
    TestTrue(TEXT("coincident link falls back behind the head's facing"), Poses[0].GetLocation().Equals(FVector{100, 100, 300}, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_HeadAlias_MatchesCopiedHead,
    "Ck.Chain.DistanceConstraint.HeadAlias_MatchesCopiedHead", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_HeadAlias_MatchesCopiedHead::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    const auto Lengths = TArray<float>{100.0f, 100.0f, 100.0f};
    const auto Orientations = TArray<ECk_Chain_LinkOrientation>{ECk_Chain_LinkOrientation::FollowPath,
        ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_LinkOrientation::FollowPath};
    const auto Initial = TArray<FTransform>{FTransform{FQuat::Identity, FVector{100, 100, 0}}, FTransform::Identity, FTransform::Identity};

    auto CopiedHeadPoses = Initial;
    const auto HeadCopy = CopiedHeadPoses[1];
    Solve_DistanceConstraint(HeadCopy, Lengths, Orientations, FVector::UpVector, CopiedHeadPoses);
    TestFalse(TEXT("fixture rewrites the aliased element's rotation before the last link falls back to head backward"),
        CopiedHeadPoses[1].GetRotation().Equals(HeadCopy.GetRotation(), 1.0e-3));

    auto AliasedHeadPoses = Initial;
    Solve_DistanceConstraint(AliasedHeadPoses[1], Lengths, Orientations, FVector::UpVector, AliasedHeadPoses);
    for (auto Index = 0; Index < AliasedHeadPoses.Num(); ++Index)
    { TestTrue(TEXT("aliased and copied heads produce the same poses"), AliasedHeadPoses[Index].Equals(CopiedHeadPoses[Index], 1.0e-3)); }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Chain_DistanceConstraint_ZeroLength_RetainsIncomingRotationForEveryMode,
    "Ck.Chain.DistanceConstraint.ZeroLength_RetainsIncomingRotationForEveryMode", kCkUnitTestFlags)
bool FCk_Chain_DistanceConstraint_ZeroLength_RetainsIncomingRotationForEveryMode::RunTest(const FString& Parameters)
{
    using namespace ck::chain;
    const auto Head = FTransform{FRotator{0, 90, 0}.Quaternion(), FVector{50, 20, 0}};
    const auto OwnRotation = FRotator{10, 37, 15}.Quaternion();
    for (const auto Orientation : {ECk_Chain_LinkOrientation::FollowPath, ECk_Chain_LinkOrientation::CopyHead, ECk_Chain_LinkOrientation::KeepOwn})
    {
        auto Poses = TArray<FTransform>{FTransform{OwnRotation, FVector{300, -40, 0}, FVector{2, 3, 4}}};
        const auto ZeroLength = TArray<float>{0.0f};
        const auto SingleOrientation = TArray<ECk_Chain_LinkOrientation>{Orientation};
        Solve_DistanceConstraint(Head, ZeroLength, SingleOrientation, FVector::UpVector, Poses);
        TestTrue(TEXT("zero-length link lies at its predecessor"), Poses[0].GetLocation().Equals(Head.GetLocation(), 1.0e-3));
        TestTrue(TEXT("zero-length link keeps its incoming rotation"), Poses[0].GetRotation().Equals(OwnRotation, 1.0e-3));
        TestTrue(TEXT("zero-length link keeps its scale"), Poses[0].GetScale3D().Equals(FVector{2, 3, 4}, 1.0e-3));
    }

    return true;
}
