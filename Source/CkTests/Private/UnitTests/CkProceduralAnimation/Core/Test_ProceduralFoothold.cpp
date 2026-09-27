#include "CkProceduralAnimation/Core/CkProceduralFoothold.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_foothold
{
    constexpr auto Reach = 140.0f;
    const auto Ideal = FVector{0.0, 0.0, 0.0};
    const auto Plant = FVector{-50.0, 0.0, 0.0};

    auto
        MakeLevel(
            const FVector& InPosition,
            ck::EProceduralFootholdVerdict InVerdict = ck::EProceduralFootholdVerdict::Usable)
        -> ck::FProceduralFootholdCandidate
    {
        return ck::FProceduralFootholdCandidate{InPosition, FVector::UpVector, ck::EProceduralFootholdSource::Ring, InVerdict};
    }

    auto
        Select(
            TArrayView<const ck::FProceduralFootholdCandidate> InCandidates,
            bool InPlanted,
            const ck::FProceduralFootholdSettings& InSettings = {},
            const FVector& InIdeal = Ideal)
        -> int32
    {
        return ck::SelectProceduralFoothold(InCandidates, InIdeal, Plant, InPlanted, Reach, InSettings);
    }

    auto
        Get_AreSame(
            TArrayView<const ck::FProceduralFootholdCandidate> InA,
            TArrayView<const ck::FProceduralFootholdCandidate> InB)
        -> bool
    {
        if (InA.Num() != InB.Num())
        { return false; }

        for (auto Index = 0; Index < InA.Num(); ++Index)
        {
            const auto& A = InA[Index];
            const auto& B = InB[Index];
            const auto PositionsMatch = A.Get_Position().ContainsNaN() == B.Get_Position().ContainsNaN()
                && (A.Get_Position().ContainsNaN() || A.Get_Position() == B.Get_Position());
            if (NOT PositionsMatch || A.Get_Normal() != B.Get_Normal() || A.Get_Source() != B.Get_Source()
                || A.Get_Verdict() != B.Get_Verdict())
            { return false; }
        }
        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdSelectsNearestUsableTest,
    "Ck.ProceduralAnimation.Foothold.SelectsNearestUsable",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdSelectsNearestUsableTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto Swinging = false;
    const auto Nearest = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(FVector{10.0, 0.0, 0.0}), MakeLevel(FVector{0.0, 30.0, 0.0}), MakeLevel(FVector{-50.0, 0.0, 0.0})};
    TestEqual(TEXT("Three level candidates at 10, 30 and 50 cm pick the nearest"), Select(Nearest, Swinging), 0);

    const auto Shuffled = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(FVector{0.0, 30.0, 0.0}), MakeLevel(FVector{-50.0, 0.0, 0.0}), MakeLevel(FVector{10.0, 0.0, 0.0})};
    TestEqual(TEXT("The pick follows the distance, not the order"), Select(Shuffled, Swinging), 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdSkipsEveryNonUsableVerdictTest,
    "Ck.ProceduralAnimation.Foothold.SkipsEveryNonUsableVerdict",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdSkipsEveryNonUsableVerdictTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto Swinging = false;
    const auto Close = FVector{1.0, 0.0, 0.0};
    const auto Candidates = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(Close, ck::EProceduralFootholdVerdict::Miss),
        MakeLevel(Close, ck::EProceduralFootholdVerdict::Unreachable),
        MakeLevel(Close, ck::EProceduralFootholdVerdict::TooSteep),
        MakeLevel(Close, ck::EProceduralFootholdVerdict::Occluded),
        MakeLevel(FVector{60.0, 0.0, 0.0})};
    TestEqual(TEXT("Only the Usable candidate 60 cm away is chosen over four rejected ones at 1 cm"), Select(Candidates, Swinging), 4);

    const auto NoneUsable = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(Close, ck::EProceduralFootholdVerdict::Miss), MakeLevel(Close, ck::EProceduralFootholdVerdict::Occluded)};
    TestEqual(TEXT("Without a Usable candidate there is no pick"), Select(NoneUsable, Swinging), static_cast<int32>(INDEX_NONE));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdLevelEnoughGateTest,
    "Ck.ProceduralAnimation.Foothold.LevelEnoughGateOnEitherSide",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdLevelEnoughGateTest::
    RunTest(const FString&)
    -> bool
{
    const auto Tilt = FMath::DegreesToRadians(70.0);
    const auto SeventyDegrees = FVector{FMath::Sin(Tilt), 0.0, FMath::Cos(Tilt)};
    TestFalse(TEXT("A normal 70 degrees from up exceeds a 60 degree limit"), ck::Get_IsFootholdLevelEnough(SeventyDegrees, 60.0f));
    TestTrue(TEXT("A normal 70 degrees from up is within a 75 degree limit"), ck::Get_IsFootholdLevelEnough(SeventyDegrees, 75.0f));
    TestTrue(TEXT("A vertical face is within the default 90 degree limit"), ck::Get_IsFootholdLevelEnough(FVector::ForwardVector, 90.0f));
    TestFalse(TEXT("An overhang facing down is beyond 90 degrees"), ck::Get_IsFootholdLevelEnough(FVector{1.0, 0.0, -0.2}, 90.0f));
    TestFalse(TEXT("A zero normal is never level"), ck::Get_IsFootholdLevelEnough(FVector::ZeroVector, 90.0f));

    const auto NaN = std::numeric_limits<double>::quiet_NaN();
    TestFalse(TEXT("A NaN normal is never level"), ck::Get_IsFootholdLevelEnough(FVector{0.0, 0.0, NaN}, 90.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdSlopeWeightTest,
    "Ck.ProceduralAnimation.Foothold.SlopeWeightPrefersLevelOverVertical",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdSlopeWeightTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto Swinging = false;
    const auto Vertical = ck::FProceduralFootholdCandidate{FVector{10.0, 0.0, 0.0}, FVector::BackwardVector,
        ck::EProceduralFootholdSource::Inward, ck::EProceduralFootholdVerdict::Usable};
    const auto Level = MakeLevel(FVector{0.0, 30.0, 0.0});
    const auto Candidates = TArray<ck::FProceduralFootholdCandidate>{Vertical, Level};

    const auto Defaults = ck::FProceduralFootholdSettings{};
    const auto VerticalCost = ck::ComputeProceduralFootholdCost(Vertical, Ideal, Plant, Swinging, Reach, Defaults);
    const auto LevelCost = ck::ComputeProceduralFootholdCost(Level, Ideal, Plant, Swinging, Reach, Defaults);
    TestTrue(FString::Printf(TEXT("The vertical face 10 cm away costs 10/140 + 0.5 (got %.4f)"), VerticalCost),
        FMath::IsNearlyEqual(VerticalCost, 10.0 / Reach + 0.5, 1.0e-4));
    TestTrue(FString::Printf(TEXT("The level candidate 30 cm away costs 30/140 (got %.4f)"), LevelCost),
        FMath::IsNearlyEqual(LevelCost, 30.0 / Reach, 1.0e-4));
    TestEqual(TEXT("With the default slope weight the level candidate wins"), Select(Candidates, Swinging), 1);

    const auto Flat = ck::FProceduralFootholdSettings{}.Set_SlopeWeight(0.0f);
    TestEqual(TEXT("Without a slope weight the nearer vertical face wins"), Select(Candidates, Swinging, Flat), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdContinuityTest,
    "Ck.ProceduralAnimation.Foothold.ContinuityPrefersPlantHeight",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdContinuityTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto Planted = true;
    constexpr auto Swinging = false;
    const auto IdealBetween = FVector{0.0, 0.0, 20.0};
    const auto AtPlantHeight = MakeLevel(FVector{0.0, 0.0, 0.0});
    const auto Higher = MakeLevel(FVector{0.0, 0.0, 40.0});
    const auto PlantHeightFirst = TArray<ck::FProceduralFootholdCandidate>{AtPlantHeight, Higher};
    const auto HigherFirst = TArray<ck::FProceduralFootholdCandidate>{Higher, AtPlantHeight};

    TestEqual(TEXT("Planted: the candidate at the plant's height wins when listed first"),
        Select(PlantHeightFirst, Planted, {}, IdealBetween), 0);
    TestEqual(TEXT("Planted: the candidate at the plant's height wins when listed second"),
        Select(HigherFirst, Planted, {}, IdealBetween), 1);
    TestEqual(TEXT("Swinging: equal distances tie and the lower index wins"), Select(PlantHeightFirst, Swinging, {}, IdealBetween), 0);
    TestEqual(TEXT("Swinging: equal distances tie and the lower index wins in either order"), Select(HigherFirst, Swinging, {}, IdealBetween), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdRejectsMalformedInputTest,
    "Ck.ProceduralAnimation.Foothold.RejectsMalformedInput",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdRejectsMalformedInputTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto Swinging = false;
    const auto Settings = ck::FProceduralFootholdSettings{};
    const auto WellFormed = TArray<ck::FProceduralFootholdCandidate>{MakeLevel(FVector{10.0, 0.0, 0.0})};
    TestEqual(TEXT("Positive control: a well-formed input yields a pick"), Select(WellFormed, Swinging), 0);

    TestEqual(TEXT("An empty view has no pick"),
        ck::SelectProceduralFoothold({}, Ideal, Plant, Swinging, Reach, Settings), static_cast<int32>(INDEX_NONE));

    const auto WellFormedCopy = WellFormed;
    TestEqual(TEXT("A zero reach has no pick"),
        ck::SelectProceduralFoothold(WellFormed, Ideal, Plant, Swinging, 0.0f, Settings), static_cast<int32>(INDEX_NONE));
    TestTrue(TEXT("A rejected zero reach leaves the candidates unchanged"), Get_AreSame(WellFormed, WellFormedCopy));

    const auto NaN = std::numeric_limits<double>::quiet_NaN();
    const auto WithNaN = TArray<ck::FProceduralFootholdCandidate>{MakeLevel(FVector{10.0, 0.0, 0.0}), MakeLevel(FVector{NaN, 0.0, 0.0})};
    const auto WithNaNCopy = WithNaN;
    TestEqual(TEXT("A NaN position has no pick, even beside a well-formed candidate"), Select(WithNaN, Swinging),
        static_cast<int32>(INDEX_NONE));
    TestTrue(TEXT("A rejected NaN position leaves the candidates unchanged"), Get_AreSame(WithNaN, WithNaNCopy));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdRejectsInboardCandidatesTest,
    "Ck.ProceduralAnimation.Foothold.RejectsInboardCandidates",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdRejectsInboardCandidatesTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto InboardTolerance = 0.1f * Reach;
    const auto Outboard = FVector{0.0, 1.0, 0.0};
    const auto FarInboard = FVector{0.0, -20.0, -30.0};
    const auto NearInboard = FVector{0.0, -10.0, -30.0};
    const auto Outward = FVector{0.0, 40.0, -30.0};

    TestFalse(TEXT("A point 20 cm inboard of the hip, beyond the 14 cm tolerance, is off the leg's own side"),
        ck::Get_IsFootholdOnOwnSide(FarInboard, Outboard, InboardTolerance));
    TestTrue(TEXT("A point 10 cm inboard, within the tolerance, is on it"),
        ck::Get_IsFootholdOnOwnSide(NearInboard, Outboard, InboardTolerance));
    TestTrue(TEXT("A point outboard of the hip is on it"), ck::Get_IsFootholdOnOwnSide(Outward, Outboard, InboardTolerance));
    TestTrue(TEXT("An unnormalised outboard direction reads the same"),
        ck::Get_IsFootholdOnOwnSide(NearInboard, Outboard * 5.0, InboardTolerance)
        && NOT ck::Get_IsFootholdOnOwnSide(FarInboard, Outboard * 5.0, InboardTolerance));
    TestTrue(TEXT("A leg with no lateral rest direction has no own side: every point is on it"),
        ck::Get_IsFootholdOnOwnSide(FarInboard, FVector::ZeroVector, InboardTolerance));
    TestFalse(TEXT("A non-finite point is on no side"),
        ck::Get_IsFootholdOnOwnSide(FVector{std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0}, Outboard, InboardTolerance));

    constexpr auto Swinging = false;
    const auto Candidates = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(FVector{0.0, 5.0, 0.0}, ck::EProceduralFootholdVerdict::Inboard),
        MakeLevel(FVector{0.0, 40.0, 0.0})};
    TestEqual(TEXT("An Inboard candidate is never chosen, however near the ideal"), Select(Candidates, Swinging), 1);

    const auto OnlyInboard = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(FVector{0.0, 5.0, 0.0}, ck::EProceduralFootholdVerdict::Inboard)};
    TestEqual(TEXT("Only Inboard candidates choose nothing"), Select(OnlyInboard, Swinging), int32{INDEX_NONE});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdRejectsUnderBodyCandidatesTest,
    "Ck.ProceduralAnimation.Foothold.RejectsUnderBodyCandidates",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdRejectsUnderBodyCandidatesTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto MaxHipLateral = 30.0f;
    constexpr auto RestDrop = 60.0f;
    constexpr auto Margin = 5.0f;
    constexpr auto DeepBelowHip = 40.0f;

    TestTrue(TEXT("A point 10 cm from the centreline, 40 cm below the hip, is under the body"),
        ck::Get_IsFootholdUnderBody(10.0f, DeepBelowHip, MaxHipLateral, RestDrop, Margin));
    TestTrue(TEXT("The lateral bound is symmetric"), ck::Get_IsFootholdUnderBody(-10.0f, DeepBelowHip, MaxHipLateral, RestDrop, Margin));
    TestTrue(TEXT("Just inside the widest hip less the margin (24 cm) is under the body"),
        ck::Get_IsFootholdUnderBody(24.0f, DeepBelowHip, MaxHipLateral, RestDrop, Margin));
    TestFalse(TEXT("Just outside it (26 cm) is not"), ck::Get_IsFootholdUnderBody(26.0f, DeepBelowHip, MaxHipLateral, RestDrop, Margin));
    TestTrue(TEXT("Just deeper than a quarter rest drop below the hip (16 cm) is under the body"),
        ck::Get_IsFootholdUnderBody(10.0f, 16.0f, MaxHipLateral, RestDrop, Margin));
    TestFalse(TEXT("Just shallower (14 cm) is not: a foothold near the hip's height is beside the body"),
        ck::Get_IsFootholdUnderBody(10.0f, 14.0f, MaxHipLateral, RestDrop, Margin));
    TestFalse(TEXT("A point above the hip is not under the body"),
        ck::Get_IsFootholdUnderBody(10.0f, -20.0f, MaxHipLateral, RestDrop, Margin));
    TestFalse(TEXT("A body whose hips all lie on its centreline has no width to be under"),
        ck::Get_IsFootholdUnderBody(0.0f, DeepBelowHip, 0.0f, RestDrop, Margin));
    TestFalse(TEXT("A non-finite input is not under the body"),
        ck::Get_IsFootholdUnderBody(std::numeric_limits<float>::quiet_NaN(), DeepBelowHip, MaxHipLateral, RestDrop, Margin));

    constexpr auto Swinging = false;
    const auto Candidates = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(FVector{0.0, 5.0, 0.0}, ck::EProceduralFootholdVerdict::UnderBody),
        MakeLevel(FVector{0.0, 40.0, 0.0})};
    TestEqual(TEXT("An UnderBody candidate is never chosen, however near the ideal"), Select(Candidates, Swinging), 1);

    const auto OnlyUnderBody = TArray<ck::FProceduralFootholdCandidate>{
        MakeLevel(FVector{0.0, 5.0, 0.0}, ck::EProceduralFootholdVerdict::UnderBody)};
    TestEqual(TEXT("Only UnderBody candidates choose nothing"), Select(OnlyUnderBody, Swinging), int32{INDEX_NONE});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootholdFaceIdealCompetesOnCostTest,
    "Ck.ProceduralAnimation.Foothold.FaceIdealCompetesOnCost",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootholdFaceIdealCompetesOnCostTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_foothold;

    constexpr auto Swinging = false;
    // The ideal on a vertical face, at the ideal itself: it costs the slope term alone, 0.5 with the default weight.
    const auto FaceIdeal = ck::FProceduralFootholdCandidate{Ideal, FVector::BackwardVector, ck::EProceduralFootholdSource::Ideal,
        ck::EProceduralFootholdVerdict::Usable};
    const auto NearTop = MakeLevel(Ideal + FVector{0.4 * Reach, 0.0, 0.0});
    const auto FarTop = MakeLevel(Ideal + FVector{0.6 * Reach, 0.0, 0.0});

    TestEqual(TEXT("A level candidate at 0.4 of the reach beats the face ideal"),
        Select(TArray<ck::FProceduralFootholdCandidate>{FaceIdeal, NearTop}, Swinging), 1);
    TestEqual(TEXT("The face ideal beats a level candidate at 0.6 of the reach"),
        Select(TArray<ck::FProceduralFootholdCandidate>{FaceIdeal, FarTop}, Swinging), 0);

    return true;
}

#endif
