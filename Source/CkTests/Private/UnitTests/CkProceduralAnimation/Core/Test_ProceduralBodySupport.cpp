#include "CkProceduralAnimation/Core/CkProceduralBodySupport.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_body_support
{
    constexpr auto CollapseDrop = 40.0f;
    constexpr auto MaxTilt = 20.0f;
    constexpr auto DistanceTolerance = 1.0e-3;
    constexpr auto AngleToleranceDegrees = 0.05;
    constexpr auto IdentityTolerance = 1.0e-4;
    constexpr auto HipX = 30.0;
    constexpr auto HipY = 20.0;

    auto
        MakeSettings()
        -> ck::FProceduralBodySupportSettings
    {
        return ck::FProceduralBodySupportSettings{}
            .Set_CollapseDrop(CollapseDrop)
            .Set_MaxTiltDegrees(MaxTilt);
    }

    // Front-left, front-right, rear-left, rear-right; the front is +X.
    auto
        MakeQuadruped(
            TArrayView<const float> InWeights)
        -> TArray<ck::FProceduralBodySupportLeg>
    {
        return TArray<ck::FProceduralBodySupportLeg>{
            ck::FProceduralBodySupportLeg{FVector{HipX, HipY, 0.0}, InWeights[0]},
            ck::FProceduralBodySupportLeg{FVector{HipX, -HipY, 0.0}, InWeights[1]},
            ck::FProceduralBodySupportLeg{FVector{-HipX, HipY, 0.0}, InWeights[2]},
            ck::FProceduralBodySupportLeg{FVector{-HipX, -HipY, 0.0}, InWeights[3]}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodySupportDropTest,
    "Ck.ProceduralAnimation.BodySupport.DropScalesWithMissingSupport",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodySupportDropTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_support;

    const auto FullSupport = ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, 1.0f, 1.0f, 1.0f}), MakeSettings());
    const auto HalfSupport = ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, 1.0f, 0.0f, 0.0f}), MakeSettings());
    const auto NoSupport = ck::ComputeProceduralBodySupportPose(MakeQuadruped({0.0f, 0.0f, 0.0f, 0.0f}), MakeSettings());
    if (NOT TestTrue(TEXT("Every well-formed support input yields a pose"), FullSupport.IsSet() && HalfSupport.IsSet() && NoSupport.IsSet()))
    { return false; }

    TestTrue(TEXT("Full support leaves the body at its rest height"),
        FMath::IsNearlyZero(FullSupport->GetLocation().Z, DistanceTolerance));
    TestTrue(FString::Printf(TEXT("Half support drops half the collapse distance (got %.4f)"), HalfSupport->GetLocation().Z),
        FMath::IsNearlyEqual(HalfSupport->GetLocation().Z, -CollapseDrop * 0.5, DistanceTolerance));
    TestTrue(FString::Printf(TEXT("No support drops the full collapse distance (got %.4f)"), NoSupport->GetLocation().Z),
        FMath::IsNearlyEqual(NoSupport->GetLocation().Z, -CollapseDrop, DistanceTolerance));

    for (const auto& Pose : {*FullSupport, *HalfSupport, *NoSupport})
    {
        TestTrue(TEXT("The drop never shifts the body sideways"),
            FMath::IsNearlyZero(Pose.GetLocation().X, DistanceTolerance) && FMath::IsNearlyZero(Pose.GetLocation().Y, DistanceTolerance));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodySupportTiltTest,
    "Ck.ProceduralAnimation.BodySupport.TiltDipsTheUnsupportedSide",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodySupportTiltTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_support;

    const auto Pose = ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, 1.0f, 0.0f, 0.0f}), MakeSettings());
    if (NOT TestTrue(TEXT("Front-only support yields a pose"), Pose.IsSet()))
    { return false; }

    const auto Rotation = Pose->GetRotation();
    const auto Nose = Rotation.RotateVector(FVector::ForwardVector);
    const auto Tail = Rotation.RotateVector(FVector::BackwardVector);
    TestTrue(FString::Printf(TEXT("The supported nose rises (forward Z %.4f)"), Nose.Z), Nose.Z > 0.0);
    TestTrue(FString::Printf(TEXT("The unsupported tail dips (backward Z %.4f)"), Tail.Z), Tail.Z < 0.0);
    TestTrue(TEXT("A front-to-back gap pitches without rolling"), FMath::IsNearlyZero(Nose.Y, DistanceTolerance));

    const auto Gap = HipX;
    const auto Extent = FMath::Sqrt(HipX * HipX + HipY * HipY);
    const auto ExpectedDegrees = MaxTilt * FMath::Clamp(Gap / Extent, 0.0, 1.0);
    const auto ActualDegrees = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(FVector::ForwardVector, Nose), -1.0, 1.0)));
    TestTrue(FString::Printf(TEXT("The tilt is MaxTilt x gap / extent (expected %.3f, got %.3f degrees)"), ExpectedDegrees, ActualDegrees),
        FMath::IsNearlyEqual(ActualDegrees, ExpectedDegrees, AngleToleranceDegrees));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodySupportNoLegsTest,
    "Ck.ProceduralAnimation.BodySupport.NoLegsCollapsesWithoutTilt",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodySupportNoLegsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_support;

    const auto Pose = ck::ComputeProceduralBodySupportPose(MakeQuadruped({0.0f, 0.0f, 0.0f, 0.0f}), MakeSettings());
    if (NOT TestTrue(TEXT("Zero support yields a pose"), Pose.IsSet()))
    { return false; }

    TestTrue(FString::Printf(TEXT("Zero support drops the full collapse distance (got %.4f)"), Pose->GetLocation().Z),
        FMath::IsNearlyEqual(Pose->GetLocation().Z, -CollapseDrop, DistanceTolerance));

    const auto Tilt = Pose->GetRotation().AngularDistance(FQuat::Identity);
    TestTrue(FString::Printf(TEXT("With no supporting side there is nothing to tilt toward (%.6f rad)"), Tilt),
        Tilt < IdentityTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodySupportRejectsTest,
    "Ck.ProceduralAnimation.BodySupport.RejectsMalformedInput",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodySupportRejectsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_support;

    const auto Settings = MakeSettings();
    TestTrue(TEXT("Positive control: a well-formed input yields a pose"),
        ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, 0.5f, 0.0f, 1.0f}), Settings).IsSet());

    TestFalse(TEXT("No legs is rejected"),
        ck::ComputeProceduralBodySupportPose(TArrayView<const ck::FProceduralBodySupportLeg>{}, Settings).IsSet());

    auto NanHip = MakeQuadruped({1.0f, 1.0f, 1.0f, 1.0f});
    NanHip[2].Set_HipLocal(FVector{std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0});
    TestFalse(TEXT("A NaN hip is rejected"), ck::ComputeProceduralBodySupportPose(NanHip, Settings).IsSet());

    TestFalse(TEXT("A negative weight is rejected"),
        ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, -0.5f, 1.0f, 1.0f}), Settings).IsSet());

    auto SteepTilt = MakeSettings();
    SteepTilt.Set_MaxTiltDegrees(95.0f);
    TestFalse(TEXT("A max tilt past 89 degrees is rejected"),
        ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, 1.0f, 0.0f, 0.0f}), SteepTilt).IsSet());

    auto NanDrop = MakeSettings();
    NanDrop.Set_CollapseDrop(std::numeric_limits<float>::quiet_NaN());
    TestFalse(TEXT("A NaN collapse drop is rejected"),
        ck::ComputeProceduralBodySupportPose(MakeQuadruped({1.0f, 1.0f, 0.0f, 0.0f}), NanDrop).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_body_conform
{
    constexpr auto FootX = 60.0;
    constexpr auto FootY = 50.0;
    constexpr auto RestZ = -60.0;
    constexpr auto MaxTilt = 20.0f;
    constexpr auto HeightWeight = 0.5f;
    constexpr auto MaxHeight = 10.0f;
    constexpr auto AngleToleranceDegrees = 0.05;
    constexpr auto DistanceTolerance = 1.0e-3;
    const auto Sentinel = FTransform{FQuat{FVector::ForwardVector, 0.3}, FVector{1.0, 2.0, 3.0}};

    auto
        MakeSettings()
        -> ck::FProceduralBodyConformSettings
    {
        return ck::FProceduralBodyConformSettings{}
            .Set_MaxTiltDegrees(MaxTilt)
            .Set_HeightWeight(HeightWeight)
            .Set_MaxHeight(MaxHeight);
    }

    // Four feet at the corners of the body; each sits InLift(x, y) above its rest height.
    template <typename T_Lift>
    auto
        MakeFeet(
            T_Lift InLift,
            TArrayView<const float> InWeights = {})
        -> TArray<ck::FProceduralBodyConformFoot>
    {
        auto Feet = TArray<ck::FProceduralBodyConformFoot>{};
        const auto Corners = TArray<FVector2D>{{FootX, FootY}, {FootX, -FootY}, {-FootX, FootY}, {-FootX, -FootY}};
        for (auto Index = 0; Index < Corners.Num(); ++Index)
        {
            const auto& Corner = Corners[Index];
            const auto Rest = FVector{Corner.X, Corner.Y, RestZ};
            const auto Weight = InWeights.IsValidIndex(Index) ? InWeights[Index] : 1.0f;
            Feet.Emplace(Rest + FVector{0.0, 0.0, InLift(Corner.X, Corner.Y)}, Rest, Weight);
        }
        return Feet;
    }

    auto
        Get_Up(
            const FTransform& InTarget)
        -> FVector
    {
        return InTarget.GetRotation().RotateVector(FVector::UpVector);
    }

    auto
        Get_AngleDegrees(
            const FVector& InA,
            const FVector& InB)
        -> double
    {
        return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(InA.GetSafeNormal(), InB.GetSafeNormal()), -1.0, 1.0)));
    }

    auto
        Get_IsSentinel(
            const FTransform& InTarget)
        -> bool
    {
        return InTarget.Equals(Sentinel, 0.0);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformFlatTest,
    "Ck.ProceduralAnimation.BodyConform.FlatFeetGiveIdentity",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformFlatTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    auto Target = Sentinel;
    const auto Result = ck::ComputeProceduralBodyConformPose(MakeFeet([](double, double) { return 0.0; }), MakeSettings(), Target);
    if (NOT TestTrue(TEXT("Four feet at rest are fitted"), Result == ck::EProceduralBodyConformResult::Fitted))
    { return false; }

    const auto Tilt = Target.GetRotation().AngularDistance(FQuat::Identity);
    TestTrue(FString::Printf(TEXT("Feet at rest leave the body level (%.6f rad)"), Tilt), Tilt < 1.0e-6);
    TestTrue(FString::Printf(TEXT("Feet at rest leave the body at its height (%s)"), *Target.GetLocation().ToString()),
        Target.GetLocation().IsNearlyZero(DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformSlopeTest,
    "Ck.ProceduralAnimation.BodyConform.SlopedFeetTiltToThePlane",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformSlopeTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    const auto SlopeX = FMath::Tan(FMath::DegreesToRadians(10.0));
    const auto SlopeY = FMath::Tan(FMath::DegreesToRadians(-6.0));
    auto Target = Sentinel;
    const auto Result = ck::ComputeProceduralBodyConformPose(
        MakeFeet([&](double InX, double InY) { return SlopeX * InX + SlopeY * InY; }), MakeSettings(), Target);
    if (NOT TestTrue(TEXT("Four feet on a slope are fitted"), Result == ck::EProceduralBodyConformResult::Fitted))
    { return false; }

    const auto PlaneNormal = FVector{-SlopeX, -SlopeY, 1.0}.GetSafeNormal();
    const auto Error = Get_AngleDegrees(Get_Up(Target), PlaneNormal);
    TestTrue(FString::Printf(TEXT("The body's up turns onto the feet's plane normal (off by %.4f degrees)"), Error),
        Error < AngleToleranceDegrees);

    const auto Nose = Target.GetRotation().RotateVector(FVector::ForwardVector);
    TestTrue(FString::Printf(TEXT("Higher front feet raise the nose (forward Z %.4f)"), Nose.Z), Nose.Z > 0.0);

    const auto Twist = Target.GetRotation().GetTwistAngle(FVector::UpVector);
    TestTrue(FString::Printf(TEXT("The tilt has no turn about the body's up (%.6f rad)"), Twist), FMath::Abs(Twist) < 1.0e-6);
    TestTrue(FString::Printf(TEXT("A plane through the rest height under the body keeps the height (%.4f)"), Target.GetLocation().Z),
        FMath::IsNearlyZero(Target.GetLocation().Z, DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformClampTest,
    "Ck.ProceduralAnimation.BodyConform.TiltIsClamped",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformClampTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    const auto Slope = FMath::Tan(FMath::DegreesToRadians(35.0));
    auto Target = Sentinel;
    const auto Result = ck::ComputeProceduralBodyConformPose(
        MakeFeet([&](double InX, double) { return Slope * InX; }), MakeSettings(), Target);
    if (NOT TestTrue(TEXT("Feet on a 35 degree slope are fitted"), Result == ck::EProceduralBodyConformResult::Fitted))
    { return false; }

    const auto Up = Get_Up(Target);
    const auto Tilt = Get_AngleDegrees(Up, FVector::UpVector);
    TestTrue(FString::Printf(TEXT("The tilt stops at MaxTilt (expected %.2f, got %.4f degrees)"), MaxTilt, Tilt),
        FMath::IsNearlyEqual(Tilt, static_cast<double>(MaxTilt), AngleToleranceDegrees));
    TestTrue(FString::Printf(TEXT("The clamped tilt leans toward the plane (up %s)"), *Up.ToString()), Up.X < 0.0 && FMath::IsNearlyZero(Up.Y, 1.0e-6));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformHeightTest,
    "Ck.ProceduralAnimation.BodyConform.HeightFollowsTheFeetAndIsClamped",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformHeightTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    auto Lowered = Sentinel;
    TestTrue(TEXT("Feet 8 cm below rest are fitted"), ck::ComputeProceduralBodyConformPose(
        MakeFeet([](double, double) { return -8.0; }), MakeSettings(), Lowered) == ck::EProceduralBodyConformResult::Fitted);
    TestTrue(FString::Printf(TEXT("The body follows HeightWeight of the drop (expected %.2f, got %.4f)"), -8.0 * HeightWeight,
        Lowered.GetLocation().Z), FMath::IsNearlyEqual(Lowered.GetLocation().Z, -8.0 * HeightWeight, DistanceTolerance));
    TestTrue(TEXT("Level feet leave the body level"), Lowered.GetRotation().AngularDistance(FQuat::Identity) < 1.0e-6);

    auto Deep = Sentinel;
    TestTrue(TEXT("Feet 40 cm below rest are fitted"), ck::ComputeProceduralBodyConformPose(
        MakeFeet([](double, double) { return -40.0; }), MakeSettings(), Deep) == ck::EProceduralBodyConformResult::Fitted);
    TestTrue(FString::Printf(TEXT("The height stops at MaxHeight (expected %.2f, got %.4f)"), -MaxHeight, Deep.GetLocation().Z),
        FMath::IsNearlyEqual(Deep.GetLocation().Z, static_cast<double>(-MaxHeight), DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformFewFeetTest,
    "Ck.ProceduralAnimation.BodyConform.FewerThanThreeFeetUnderdetermined",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformFewFeetTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    const auto Lift = [](double InX, double) { return 0.1 * InX; };
    auto Target = Sentinel;
    TestTrue(TEXT("Positive control: three weighted feet are fitted"), ck::ComputeProceduralBodyConformPose(
        MakeFeet(Lift, TArray<float>{1.0f, 1.0f, 1.0f, 0.0f}), MakeSettings(), Target) == ck::EProceduralBodyConformResult::Fitted);

    auto Held = Sentinel;
    TestTrue(TEXT("Two weighted feet are underdetermined"), ck::ComputeProceduralBodyConformPose(
        MakeFeet(Lift, TArray<float>{1.0f, 0.0f, 0.0f, 1.0f}), MakeSettings(), Held) == ck::EProceduralBodyConformResult::Underdetermined);
    TestTrue(TEXT("An underdetermined fit leaves the target untouched"), Get_IsSentinel(Held));

    TestTrue(TEXT("No feet are underdetermined"), ck::ComputeProceduralBodyConformPose(
        TArrayView<const ck::FProceduralBodyConformFoot>{}, MakeSettings(), Held) == ck::EProceduralBodyConformResult::Underdetermined);
    TestTrue(TEXT("No feet leave the target untouched"), Get_IsSentinel(Held));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformCollinearTest,
    "Ck.ProceduralAnimation.BodyConform.CollinearFeetUnderdetermined",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformCollinearTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    const auto MakeRow = [](double InSpreadY)
    {
        auto Feet = TArray<ck::FProceduralBodyConformFoot>{};
        for (auto Index = 0; Index < 4; ++Index)
        {
            const auto Rest = FVector{-90.0 + 60.0 * Index, Index % 2 == 0 ? InSpreadY : -InSpreadY, RestZ};
            Feet.Emplace(Rest + FVector{0.0, 0.0, 0.05 * Rest.X}, Rest, 1.0f);
        }
        return Feet;
    };

    auto Target = Sentinel;
    TestTrue(TEXT("Positive control: a row with sideways spread is fitted"),
        ck::ComputeProceduralBodyConformPose(MakeRow(40.0), MakeSettings(), Target) == ck::EProceduralBodyConformResult::Fitted);

    auto Held = Sentinel;
    TestTrue(TEXT("Feet on one line are underdetermined"),
        ck::ComputeProceduralBodyConformPose(MakeRow(0.0), MakeSettings(), Held) == ck::EProceduralBodyConformResult::Underdetermined);
    TestTrue(TEXT("Feet within half a centimetre of one line are underdetermined"),
        ck::ComputeProceduralBodyConformPose(MakeRow(0.5), MakeSettings(), Held) == ck::EProceduralBodyConformResult::Underdetermined);
    TestTrue(TEXT("Collinear feet leave the target untouched"), Get_IsSentinel(Held));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformMalformedTest,
    "Ck.ProceduralAnimation.BodyConform.MalformedFeetMalformed",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformMalformedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform;

    const auto Level = [](double, double) { return 0.0; };
    auto Target = Sentinel;
    TestTrue(TEXT("Positive control: well-formed feet are fitted"),
        ck::ComputeProceduralBodyConformPose(MakeFeet(Level), MakeSettings(), Target) == ck::EProceduralBodyConformResult::Fitted);

    const auto DoExpectMalformed = [&](const TArray<ck::FProceduralBodyConformFoot>& InFeet,
        const ck::FProceduralBodyConformSettings& InSettings, const TCHAR* InCase)
    {
        auto Held = Sentinel;
        TestTrue(FString::Printf(TEXT("%s is malformed"), InCase),
            ck::ComputeProceduralBodyConformPose(InFeet, InSettings, Held) == ck::EProceduralBodyConformResult::Malformed);
        TestTrue(FString::Printf(TEXT("%s leaves the target untouched"), InCase), Get_IsSentinel(Held));
    };

    const auto NaN = std::numeric_limits<double>::quiet_NaN();
    auto NanPosition = MakeFeet(Level);
    NanPosition[1].Set_PositionLocal(FVector{NaN, 0.0, 0.0});
    DoExpectMalformed(NanPosition, MakeSettings(), TEXT("A NaN foot position"));

    auto InfiniteRest = MakeFeet(Level);
    InfiniteRest[2].Set_RestLocal(FVector{0.0, std::numeric_limits<double>::infinity(), 0.0});
    DoExpectMalformed(InfiniteRest, MakeSettings(), TEXT("An infinite rest foot"));

    DoExpectMalformed(MakeFeet(Level, TArray<float>{1.0f, -0.5f, 1.0f, 1.0f}), MakeSettings(), TEXT("A negative weight"));
    DoExpectMalformed(MakeFeet(Level, TArray<float>{1.0f, 1.0f, std::numeric_limits<float>::quiet_NaN(), 1.0f}), MakeSettings(),
        TEXT("A NaN weight"));
    DoExpectMalformed(MakeFeet(Level), MakeSettings().Set_MaxTiltDegrees(95.0f), TEXT("A max tilt past 89 degrees"));
    DoExpectMalformed(MakeFeet(Level), MakeSettings().Set_HeightWeight(1.5f), TEXT("A height weight above 1"));
    DoExpectMalformed(MakeFeet(Level), MakeSettings().Set_MaxHeight(-1.0f), TEXT("A negative max height"));
    DoExpectMalformed(MakeFeet(Level), MakeSettings().Set_MaxHeight(std::numeric_limits<float>::quiet_NaN()), TEXT("A NaN max height"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_body_conform_slew
{
    constexpr auto FrameDt = FCk_Time{1.0 / 60.0};
    constexpr auto MaxTiltRateDegrees = 120.0f;
    constexpr auto MaxHeightRate = 60.0f;
    constexpr auto JumpDegrees = 30.0;
    constexpr auto JumpHeight = 10.0;
    constexpr auto AngleToleranceDegrees = 1.0e-3;
    constexpr auto DistanceTolerance = 1.0e-3;

    auto
        MakeSettings()
        -> ck::FProceduralBodyConformSlewSettings
    {
        return ck::FProceduralBodyConformSlewSettings{}
            .Set_MaxTiltRateDegrees(MaxTiltRateDegrees)
            .Set_MaxHeightRate(MaxHeightRate);
    }

    auto
        Get_AngleDegrees(
            const FTransform& InA,
            const FTransform& InB)
        -> double
    {
        return FMath::RadiansToDegrees(InA.GetRotation().AngularDistance(InB.GetRotation()));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformSlewRateTest,
    "Ck.ProceduralAnimation.BodyConform.SlewAdvancesAtMostTheRatePerFrame",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformSlewRateTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform_slew;

    const auto MaxStepDegrees = MaxTiltRateDegrees * FrameDt.Get_Seconds();
    const auto MaxStepHeight = MaxHeightRate * FrameDt.Get_Seconds();
    const auto Target = FTransform{FQuat{FVector{1.0, 1.0, 0.0}.GetSafeNormal(), FMath::DegreesToRadians(JumpDegrees)},
        FVector{0.0, 0.0, JumpHeight}};
    const auto RotationFrames = static_cast<int32>(FMath::CeilToInt(JumpDegrees / MaxStepDegrees - AngleToleranceDegrees));
    const auto HeightFrames = static_cast<int32>(FMath::CeilToInt(JumpHeight / MaxStepHeight - DistanceTolerance));

    auto Applied = FTransform::Identity;
    auto WorstStepDegrees = 0.0;
    auto WorstStepHeight = 0.0;
    auto ReachedRotationFrame = int32{INDEX_NONE};
    auto ReachedHeightFrame = int32{INDEX_NONE};
    for (auto Frame = 1; Frame <= RotationFrames + 5; ++Frame)
    {
        const auto Slewed = ck::SlewProceduralBodyConformPose(Applied, Target, MakeSettings(), FrameDt);
        if (NOT TestTrue(FString::Printf(TEXT("Frame %d: a well-formed slew is set"), Frame), Slewed.IsSet()))
        { return false; }

        const auto StepDegrees = Get_AngleDegrees(*Slewed, Applied);
        const auto StepHeight = FVector::Distance(Slewed->GetLocation(), Applied.GetLocation());
        TestTrue(FString::Printf(TEXT("Frame %d: the applied target never moves away from the fit (%.4f -> %.4f degrees)"), Frame,
            Get_AngleDegrees(Applied, Target), Get_AngleDegrees(*Slewed, Target)),
            Get_AngleDegrees(*Slewed, Target) <= Get_AngleDegrees(Applied, Target) + AngleToleranceDegrees);
        WorstStepDegrees = FMath::Max(WorstStepDegrees, StepDegrees);
        WorstStepHeight = FMath::Max(WorstStepHeight, StepHeight);
        Applied = *Slewed;

        if (ReachedRotationFrame == INDEX_NONE && Get_AngleDegrees(Applied, Target) <= AngleToleranceDegrees)
        { ReachedRotationFrame = Frame; }
        if (ReachedHeightFrame == INDEX_NONE && FVector::Distance(Applied.GetLocation(), Target.GetLocation()) <= DistanceTolerance)
        { ReachedHeightFrame = Frame; }
    }

    TestTrue(FString::Printf(TEXT("A %.0f degree conform jump advances at most %.2f degrees per frame at 60 fps (worst %.4f)"),
        JumpDegrees, MaxStepDegrees, WorstStepDegrees), WorstStepDegrees <= MaxStepDegrees + AngleToleranceDegrees);
    TestTrue(FString::Printf(TEXT("A %.0f cm height jump advances at most %.2f cm per frame (worst %.4f)"), JumpHeight, MaxStepHeight,
        WorstStepHeight), WorstStepHeight <= MaxStepHeight + DistanceTolerance);
    TestEqual(TEXT("The rotation reaches the fit on the frame the rate allows"), ReachedRotationFrame, RotationFrames);
    TestEqual(TEXT("The height reaches the fit on the frame the rate allows"), ReachedHeightFrame, HeightFrames);

    const auto Near = FTransform{FQuat{FVector::ForwardVector, FMath::DegreesToRadians(MaxStepDegrees * 0.5)}, FVector{0.0, 0.0, 0.2}};
    const auto OneStep = ck::SlewProceduralBodyConformPose(FTransform::Identity, Near, MakeSettings(), FrameDt);
    TestTrue(TEXT("A fit within one frame's rate is reached in that frame"), OneStep.IsSet()
        && Get_AngleDegrees(*OneStep, Near) <= AngleToleranceDegrees
        && FVector::Distance(OneStep->GetLocation(), Near.GetLocation()) <= DistanceTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyConformSlewMalformedTest,
    "Ck.ProceduralAnimation.BodyConform.SlewRejectsMalformedInput",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBodyConformSlewMalformedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_conform_slew;

    const auto Target = FTransform{FQuat{FVector::RightVector, FMath::DegreesToRadians(JumpDegrees)}, FVector{0.0, 0.0, JumpHeight}};
    TestTrue(TEXT("Positive control: a well-formed slew is set"),
        ck::SlewProceduralBodyConformPose(FTransform::Identity, Target, MakeSettings(), FrameDt).IsSet());

    const auto Still = ck::SlewProceduralBodyConformPose(FTransform::Identity, Target, MakeSettings(), FCk_Time{});
    TestTrue(TEXT("A zero delta time leaves the applied target where it was"), Still.IsSet()
        && Get_AngleDegrees(*Still, FTransform::Identity) <= AngleToleranceDegrees
        && Still->GetLocation().IsNearlyZero(DistanceTolerance));

    const auto NaN = std::numeric_limits<float>::quiet_NaN();
    const auto DoExpectUnset = [&](const FTransform& InApplied, const FTransform& InTarget,
        const ck::FProceduralBodyConformSlewSettings& InSettings, FCk_Time InDeltaTime, const TCHAR* InCase)
    {
        TestFalse(FString::Printf(TEXT("%s is rejected"), InCase),
            ck::SlewProceduralBodyConformPose(InApplied, InTarget, InSettings, InDeltaTime).IsSet());
    };

    DoExpectUnset(FTransform::Identity, Target, MakeSettings().Set_MaxTiltRateDegrees(0.0f), FrameDt, TEXT("A zero tilt rate"));
    DoExpectUnset(FTransform::Identity, Target, MakeSettings().Set_MaxTiltRateDegrees(-10.0f), FrameDt, TEXT("A negative tilt rate"));
    DoExpectUnset(FTransform::Identity, Target, MakeSettings().Set_MaxTiltRateDegrees(NaN), FrameDt, TEXT("A NaN tilt rate"));
    DoExpectUnset(FTransform::Identity, Target, MakeSettings().Set_MaxHeightRate(0.0f), FrameDt, TEXT("A zero height rate"));
    DoExpectUnset(FTransform::Identity, Target, MakeSettings().Set_MaxHeightRate(-10.0f), FrameDt, TEXT("A negative height rate"));
    DoExpectUnset(FTransform::Identity, Target, MakeSettings(), FCk_Time{-1.0 / 60.0}, TEXT("A negative delta time"));
    DoExpectUnset(FTransform::Identity, Target, MakeSettings(), FCk_Time{std::numeric_limits<double>::quiet_NaN()},
        TEXT("A NaN delta time"));
    DoExpectUnset(FTransform{FVector{0.0, 0.0, std::numeric_limits<double>::quiet_NaN()}}, Target, MakeSettings(), FrameDt,
        TEXT("A NaN applied target"));
    DoExpectUnset(FTransform::Identity, FTransform{FVector{std::numeric_limits<double>::infinity(), 0.0, 0.0}}, MakeSettings(), FrameDt,
        TEXT("An infinite fitted target"));

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
