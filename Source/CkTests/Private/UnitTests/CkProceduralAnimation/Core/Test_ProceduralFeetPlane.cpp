#include "CkProceduralAnimation/Core/CkProceduralFeetPlane.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_feet_plane
{
    constexpr auto Tolerance = 1.0e-4;
    constexpr auto SlopeX = 0.1;
    constexpr auto SlopeY = 0.2;
    constexpr auto Height = -50.0;
    constexpr auto MaxAngle = 45.0f;

    auto
        MakeFoot(
            double InX,
            double InY,
            float InWeight,
            double InSlopeX = SlopeX,
            double InSlopeY = SlopeY,
            double InHeight = Height)
        -> ck::FProceduralFeetPlaneFoot
    {
        return ck::FProceduralFeetPlaneFoot{FVector{InX, InY, InSlopeX * InX + InSlopeY * InY + InHeight}, InWeight};
    }

    auto
        MakeThreeFeet()
        -> TArray<ck::FProceduralFeetPlaneFoot>
    {
        return TArray<ck::FProceduralFeetPlaneFoot>{MakeFoot(100.0, 0.0, 1.0f), MakeFoot(-50.0, 80.0, 1.0f), MakeFoot(-50.0, -80.0, 1.0f)};
    }

    // Distinct from any plane a fit produces, so a fit that must not write can be caught writing.
    auto
        MakeSentinel()
        -> ck::FProceduralFeetPlane
    {
        return ck::FProceduralFeetPlane{}.Set_Point(FVector{7.0, 8.0, 9.0}).Set_Normal(FVector::RightVector);
    }

    auto
        Get_IsSentinel(
            const ck::FProceduralFeetPlane& InPlane)
        -> bool
    {
        const auto Sentinel = MakeSentinel();
        return FMemory::Memcmp(&InPlane.Get_Point(), &Sentinel.Get_Point(), sizeof(FVector)) == 0
            && FMemory::Memcmp(&InPlane.Get_Normal(), &Sentinel.Get_Normal(), sizeof(FVector)) == 0;
    }

    // z = a x + b y + c recovered from the plane: its normal is (-a, -b, 1) scaled, and it crosses the up axis at c.
    auto
        Get_Coefficients(
            const ck::FProceduralFeetPlane& InPlane)
        -> FVector
    {
        const auto& Normal = InPlane.Get_Normal();
        return FVector{-Normal.X / Normal.Z, -Normal.Y / Normal.Z, InPlane.Get_Point().Z};
    }

    auto
        Get_ResultName(
            ck::EProceduralFeetPlaneResult InResult)
        -> const TCHAR*
    {
        switch (InResult)
        {
            case ck::EProceduralFeetPlaneResult::Fitted: return TEXT("Fitted");
            case ck::EProceduralFeetPlaneResult::Underdetermined: return TEXT("Underdetermined");
            case ck::EProceduralFeetPlaneResult::TooSteep: return TEXT("TooSteep");
            case ck::EProceduralFeetPlaneResult::Malformed: return TEXT("Malformed");
        }
        return TEXT("?");
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFeetPlaneFitsThreeFeetExactlyTest,
    "Ck.ProceduralAnimation.FeetPlane.FitsThreeFeetExactly",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFeetPlaneFitsThreeFeetExactlyTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_feet_plane;

    auto Plane = MakeSentinel();
    const auto Result = ck::FitProceduralFeetPlane(MakeThreeFeet(), MaxAngle, Plane);
    if (NOT TestTrue(FString::Printf(TEXT("Three feet off one line fit a plane (got %s)"), Get_ResultName(Result)),
            Result == ck::EProceduralFeetPlaneResult::Fitted))
    { return false; }

    const auto Coefficients = Get_Coefficients(Plane);
    TestTrue(FString::Printf(TEXT("The plane is z = 0.1 x + 0.2 y - 50 (got a %.6f, b %.6f, c %.6f)"),
        Coefficients.X, Coefficients.Y, Coefficients.Z),
        FMath::IsNearlyEqual(Coefficients.X, SlopeX, Tolerance) && FMath::IsNearlyEqual(Coefficients.Y, SlopeY, Tolerance)
        && FMath::IsNearlyEqual(Coefficients.Z, Height, Tolerance));
    TestTrue(FString::Printf(TEXT("The point lies on the frame's up axis (got %s)"), *Plane.Get_Point().ToString()),
        FMath::IsNearlyZero(Plane.Get_Point().X, Tolerance) && FMath::IsNearlyZero(Plane.Get_Point().Y, Tolerance));
    TestTrue(FString::Printf(TEXT("The normal is a unit vector pointing up (got %s)"), *Plane.Get_Normal().ToString()),
        FMath::IsNearlyEqual(Plane.Get_Normal().Size(), 1.0, Tolerance) && Plane.Get_Normal().Z > 0.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFeetPlaneWeightsScaleInfluenceTest,
    "Ck.ProceduralAnimation.FeetPlane.WeightsScaleInfluence",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFeetPlaneWeightsScaleInfluenceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_feet_plane;

    auto Reference = MakeSentinel();
    if (NOT TestTrue(TEXT("Precondition: the three feet fit"),
            ck::FitProceduralFeetPlane(MakeThreeFeet(), MaxAngle, Reference) == ck::EProceduralFeetPlaneResult::Fitted))
    { return false; }

    // A fourth foot 30 cm above the three feet's plane, under the body.
    const auto HeightWithFourth = [&](float InWeight) -> TOptional<double>
    {
        auto Feet = MakeThreeFeet();
        Feet.Add(ck::FProceduralFeetPlaneFoot{FVector{0.0, 0.0, Height + 30.0}, InWeight});
        auto Plane = MakeSentinel();
        if (ck::FitProceduralFeetPlane(Feet, MaxAngle, Plane) != ck::EProceduralFeetPlaneResult::Fitted)
        { return {}; }
        return Get_Coefficients(Plane).Z;
    };

    auto Unweighted = MakeSentinel();
    auto FeetWithUnweighted = MakeThreeFeet();
    FeetWithUnweighted.Add(ck::FProceduralFeetPlaneFoot{FVector{0.0, 0.0, Height + 30.0}, 0.0f});
    const auto UnweightedResult = ck::FitProceduralFeetPlane(FeetWithUnweighted, MaxAngle, Unweighted);
    TestTrue(FString::Printf(TEXT("A fourth foot with weight 0 changes nothing (got %s, point %s, normal %s)"),
        Get_ResultName(UnweightedResult), *Unweighted.Get_Point().ToString(), *Unweighted.Get_Normal().ToString()),
        UnweightedResult == ck::EProceduralFeetPlaneResult::Fitted
        && Unweighted.Get_Point().Equals(Reference.Get_Point(), 1.0e-9) && Unweighted.Get_Normal().Equals(Reference.Get_Normal(), 1.0e-9));

    const auto Half = HeightWithFourth(0.5f);
    const auto Full = HeightWithFourth(1.0f);
    if (NOT TestTrue(TEXT("The weighted fourth foot still fits"), Half.IsSet() && Full.IsSet()))
    { return false; }

    TestTrue(FString::Printf(TEXT("A fourth foot with weight 1 moves c toward it (c %.4f, three feet %.4f)"), *Full, Height),
        *Full > Height + 1.0);
    TestTrue(FString::Printf(TEXT("Half the weight moves c less than the full weight (c %.4f, full %.4f)"), *Half, *Full),
        *Half > Height + Tolerance && *Half < *Full - Tolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFeetPlaneUnderdeterminedTest,
    "Ck.ProceduralAnimation.FeetPlane.UnderdeterminedBelowThreeOrCollinear",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFeetPlaneUnderdeterminedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_feet_plane;

    const auto Expect = [&](const FString& InCase, TArrayView<const ck::FProceduralFeetPlaneFoot> InFeet,
        ck::EProceduralFeetPlaneResult InExpected)
    {
        auto Plane = MakeSentinel();
        const auto Result = ck::FitProceduralFeetPlane(InFeet, MaxAngle, Plane);
        TestTrue(FString::Printf(TEXT("%s: %s (got %s)"), *InCase, Get_ResultName(InExpected), Get_ResultName(Result)), Result == InExpected);
        if (InExpected != ck::EProceduralFeetPlaneResult::Fitted)
        { TestTrue(FString::Printf(TEXT("%s: the plane is not written"), *InCase), Get_IsSentinel(Plane)); }
    };

    Expect(TEXT("No feet"), TArray<ck::FProceduralFeetPlaneFoot>{}, ck::EProceduralFeetPlaneResult::Underdetermined);

    auto TwoWeighted = MakeThreeFeet();
    TwoWeighted[2].Set_Weight(0.0f);
    Expect(TEXT("Two weighted feet and one of weight 0"), TwoWeighted, ck::EProceduralFeetPlaneResult::Underdetermined);

    const auto Collinear = TArray<ck::FProceduralFeetPlaneFoot>{MakeFoot(0.0, 0.0, 1.0f), MakeFoot(50.0, 50.0, 1.0f), MakeFoot(100.0, 100.0, 1.0f)};
    Expect(TEXT("Three weighted feet along one line"), Collinear, ck::EProceduralFeetPlaneResult::Underdetermined);

    auto OffTheLine = Collinear;
    OffTheLine.Add(MakeFoot(100.0, 0.0, 1.0f));
    Expect(TEXT("Positive control: the same line and a foot off it"), OffTheLine, ck::EProceduralFeetPlaneResult::Fitted);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFeetPlaneTooSteepTest,
    "Ck.ProceduralAnimation.FeetPlane.TooSteepBeyondMaxAngle",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFeetPlaneTooSteepTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_feet_plane;

    constexpr auto PlaneDegrees = 60.0;
    const auto Slope = FMath::Tan(FMath::DegreesToRadians(PlaneDegrees));
    const auto Feet = TArray<ck::FProceduralFeetPlaneFoot>{
        MakeFoot(100.0, 0.0, 1.0f, Slope, 0.0), MakeFoot(-50.0, 80.0, 1.0f, Slope, 0.0), MakeFoot(-50.0, -80.0, 1.0f, Slope, 0.0)};

    auto Steep = MakeSentinel();
    const auto SteepResult = ck::FitProceduralFeetPlane(Feet, 45.0f, Steep);
    TestTrue(FString::Printf(TEXT("A 60 degree plane with a 45 degree max is too steep (got %s)"), Get_ResultName(SteepResult)),
        SteepResult == ck::EProceduralFeetPlaneResult::TooSteep);
    TestTrue(TEXT("A plane too steep is not written"), Get_IsSentinel(Steep));

    auto Allowed = MakeSentinel();
    const auto AllowedResult = ck::FitProceduralFeetPlane(Feet, 70.0f, Allowed);
    const auto AngleDegrees = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(Allowed.Get_Normal().Z, -1.0, 1.0)));
    TestTrue(FString::Printf(TEXT("A 60 degree plane with a 70 degree max fits, 60 degrees off up (got %s, %.4f degrees)"),
        Get_ResultName(AllowedResult), AngleDegrees),
        AllowedResult == ck::EProceduralFeetPlaneResult::Fitted && FMath::IsNearlyEqual(AngleDegrees, PlaneDegrees, 1.0e-3));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFeetPlaneMalformedTest,
    "Ck.ProceduralAnimation.FeetPlane.MalformedInputsWriteNothing",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFeetPlaneMalformedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_feet_plane;

    const auto NaN = std::numeric_limits<double>::quiet_NaN();
    const auto Expect = [&](const FString& InCase, TArrayView<const ck::FProceduralFeetPlaneFoot> InFeet, float InMaxAngle,
        ck::EProceduralFeetPlaneResult InExpected)
    {
        auto Plane = MakeSentinel();
        const auto Result = ck::FitProceduralFeetPlane(InFeet, InMaxAngle, Plane);
        TestTrue(FString::Printf(TEXT("%s: %s (got %s)"), *InCase, Get_ResultName(InExpected), Get_ResultName(Result)), Result == InExpected);
        if (InExpected != ck::EProceduralFeetPlaneResult::Fitted)
        { TestTrue(FString::Printf(TEXT("%s: the plane is not written"), *InCase), Get_IsSentinel(Plane)); }
    };

    Expect(TEXT("Positive control"), MakeThreeFeet(), MaxAngle, ck::EProceduralFeetPlaneResult::Fitted);

    auto NaNPosition = MakeThreeFeet();
    NaNPosition.Add(ck::FProceduralFeetPlaneFoot{FVector{NaN, 0.0, 0.0}, 0.0f});
    Expect(TEXT("A NaN position, even on a foot of weight 0"), NaNPosition, MaxAngle, ck::EProceduralFeetPlaneResult::Malformed);

    auto NegativeWeight = MakeThreeFeet();
    NegativeWeight[1].Set_Weight(-0.5f);
    Expect(TEXT("A negative weight"), NegativeWeight, MaxAngle, ck::EProceduralFeetPlaneResult::Malformed);

    auto NaNWeight = MakeThreeFeet();
    NaNWeight[0].Set_Weight(static_cast<float>(NaN));
    Expect(TEXT("A NaN weight"), NaNWeight, MaxAngle, ck::EProceduralFeetPlaneResult::Malformed);

    Expect(TEXT("A max angle of 95 degrees"), MakeThreeFeet(), 95.0f, ck::EProceduralFeetPlaneResult::Malformed);
    Expect(TEXT("A negative max angle"), MakeThreeFeet(), -1.0f, ck::EProceduralFeetPlaneResult::Malformed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
