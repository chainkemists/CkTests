#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"
#include "CkProceduralAnimation/Core/CkProceduralGaitSwingProfile.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSwingProfileDefaultTest,
    "Ck.ProceduralAnimation.Gait.SwingProfileDefaultsAreInert",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSwingProfileDefaultTest::
    RunTest(const FString&)
    -> bool
{
    auto Profile = ck::FProceduralGaitSwingProfile{};

    TestFalse(TEXT("Ease starts unauthored"), Profile.IsEaseValid());
    TestFalse(TEXT("Arc starts unauthored"), Profile.IsArcValid());

    TestEqual(TEXT("Unauthored ease is the identity at 0"), Profile.SampleEase(0.0f), 0.0f);
    TestEqual(TEXT("Unauthored ease is the identity at 1"), Profile.SampleEase(1.0f), 1.0f);
    TestEqual(TEXT("Unauthored ease is the identity mid-swing"), Profile.SampleEase(0.5f), 0.5f);
    TestEqual(TEXT("Unauthored arc adds no lift"), Profile.SampleArc(0.5f), 0.0f);

    TestEqual(TEXT("Negative phase clamps to the start"), Profile.SampleEase(-3.0f), 0.0f);
    TestEqual(TEXT("Phase past 1 clamps to the end"), Profile.SampleEase(4.0f), 1.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSwingProfileSamplingTest,
    "Ck.ProceduralAnimation.Gait.SwingProfileSamplesTheCurve",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSwingProfileSamplingTest::
    RunTest(const FString&)
    -> bool
{
    auto Profile = ck::FProceduralGaitSwingProfile{};

    Profile.SetEase([](float InPhase) -> float { return InPhase * 2.0f - 0.5f; });
    TestTrue(TEXT("Ease reports authored"), Profile.IsEaseValid());
    TestTrue(TEXT("Authored ease at 0"), FMath::IsNearlyEqual(Profile.SampleEase(0.0f), -0.5f, 1.0e-5f));
    TestTrue(TEXT("Authored ease at 1"), FMath::IsNearlyEqual(Profile.SampleEase(1.0f), 1.5f, 1.0e-5f));

    TestTrue(TEXT("Authored ease interpolates between samples"),
        FMath::IsNearlyEqual(Profile.SampleEase(0.3f), 0.1f, 1.0e-4f));

    TestTrue(TEXT("Ease values outside 0..1 survive"), Profile.SampleEase(1.0f) > 1.0f);

    Profile.SetArc([](float InPhase) -> float { return FMath::Sin(InPhase * PI) * 0.5f; });
    TestTrue(TEXT("Arc reports authored"), Profile.IsArcValid());
    TestTrue(TEXT("Authored arc is zero at takeoff"), FMath::IsNearlyZero(Profile.SampleArc(0.0f), 1.0e-5f));
    TestTrue(TEXT("Authored arc is zero at landing"), FMath::IsNearlyZero(Profile.SampleArc(1.0f), 1.0e-5f));
    TestTrue(TEXT("Authored arc peaks mid-swing"), FMath::IsNearlyEqual(Profile.SampleArc(0.5f), 0.5f, 1.0e-4f));

    Profile.ClearEase();
    TestFalse(TEXT("Cleared ease is unauthored again"), Profile.IsEaseValid());
    TestTrue(TEXT("Clearing one half leaves the other"), Profile.IsArcValid());

    Profile.Reset();
    TestFalse(TEXT("Reset clears the arc too"), Profile.IsArcValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSwingPointTest,
    "Ck.ProceduralAnimation.Gait.SwingPointFollowsTheSolverArc",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSwingPointTest::
    RunTest(const FString&)
    -> bool
{
    const auto Start = FVector{10.0, -20.0, 5.0};
    const auto Target = FVector{70.0, 10.0, 25.0};
    const auto Swing = ck::FProceduralGaitSwingSettings{};
    constexpr auto Height = 24.0f;
    constexpr auto Apex = 0.5f;

    TestTrue(TEXT("Alpha 0 is the start"),
        ck::ComputeProceduralSwingPoint(Start, Target, FVector::UpVector, Swing, Height, 0.0f).Equals(Start, 1.0e-3));
    TestTrue(TEXT("Alpha 1 is the target"),
        ck::ComputeProceduralSwingPoint(Start, Target, FVector::UpVector, Swing, Height, 1.0f).Equals(Target, 1.0e-3));

    TestEqual(TEXT("The default arc peaks mid-swing"), Swing.Get_ApexPhase(), Apex);
    const auto ChordMidpoint = (Start + Target) * 0.5;
    TestTrue(TEXT("The apex lies above the chord by the height"),
        ck::ComputeProceduralSwingPoint(Start, Target, FVector::UpVector, Swing, Height, Apex)
            .Equals(ChordMidpoint + FVector::UpVector * Height, 1.0e-3));

    const auto WallUp = FVector{1.0, 0.0, 0.0};
    TestTrue(TEXT("The lift follows the given up"),
        ck::ComputeProceduralSwingPoint(Start, Target, WallUp, Swing, Height, Apex)
            .Equals(ChordMidpoint + WallUp * Height, 1.0e-3));

    const auto Early = ck::ComputeProceduralSwingPoint(Start, Target, FVector::UpVector, Swing, Height, 0.2f);
    const auto EarlyChord = FMath::Lerp(Start, Target, FMath::SmoothStep(0.0f, 1.0f, 0.2f));
    TestTrue(TEXT("An early point lies on the eased chord, lifted less than the apex"),
        FMath::IsNearlyEqual(Early.X, EarlyChord.X, 1.0e-3) && FMath::IsNearlyEqual(Early.Y, EarlyChord.Y, 1.0e-3)
            && Early.Z > EarlyChord.Z && Early.Z < EarlyChord.Z + Height);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitTraceAxisTest,
    "Ck.ProceduralAnimation.Gait.TraceAxisLeansOutward",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitTraceAxisTest::
    RunTest(const FString&)
    -> bool
{
    const auto Radial = FVector{1.0, 0.0, 0.0};

    TestTrue(TEXT("Zero lean is pure body-down"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 0.0f)
            .Equals(FVector::UpVector, 1.0e-5f));

    const auto Leaned = ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 1.0f);
    TestTrue(TEXT("Leaned axis stays normalized"), FMath::IsNearlyEqual(Leaned.Size(), 1.0, 1.0e-4));

    TestTrue(TEXT("Axis tilts away from the radial"), Leaned.X < 0.0);
    TestTrue(TEXT("Axis keeps a positive up component"), Leaned.Z > 0.0);

    TestTrue(TEXT("Lean 1 is 45 degrees"),
        FMath::IsNearlyEqual(FVector::DotProduct(Leaned, FVector::UpVector), FMath::Sqrt(0.5), 1.0e-4));

    const auto Half = ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 0.5f);
    TestTrue(TEXT("Half lean is between none and full"), Half.X < 0.0 && Half.X > Leaned.X);

    TestTrue(TEXT("Lean is clamped at 1"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 5.0f).Equals(Leaned, 1.0e-5f));

    TestTrue(TEXT("Zero radial falls back to body-down"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, FVector::ZeroVector, 1.0f)
            .Equals(FVector::UpVector, 1.0e-5f));
    TestTrue(TEXT("Radial parallel to up falls back to body-down"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, FVector::UpVector, 1.0f)
            .Equals(FVector::UpVector, 1.0e-5f));

    const auto WallUp = FVector{1.0, 0.0, 0.0};
    const auto WallRadial = FVector{0.0, 1.0, 0.0};
    const auto WallLeaned = ck::FProceduralGaitSolver::ComputeTraceAxis(WallUp, WallRadial, 1.0f);
    TestTrue(TEXT("Wall-basis lean tilts against its own radial"), WallLeaned.Y < 0.0);
    TestTrue(TEXT("Wall-basis lean keeps its up component"), WallLeaned.X > 0.0);
    TestTrue(TEXT("Wall-basis lean introduces no third-axis drift"),
        FMath::IsNearlyZero(WallLeaned.Z, 1.0e-5));

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
