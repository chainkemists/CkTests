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

#endif

// --------------------------------------------------------------------------------------------------------------------
