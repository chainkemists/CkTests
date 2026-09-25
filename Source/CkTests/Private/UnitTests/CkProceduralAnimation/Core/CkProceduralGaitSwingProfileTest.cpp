#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"
#include "CkProceduralAnimation/Core/CkProceduralGaitSwingProfile.h"

namespace CkProceduralGaitSwingProfileTestLocal
{
    constexpr EAutomationTestFlags SwingProfileTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::EngineFilter;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitSwingProfileDefaultTest,
    "Ck.ProceduralAnimation.Gait.SwingProfileDefaultsAreInert", CkProceduralGaitSwingProfileTestLocal::SwingProfileTestFlags)

auto
FCkProceduralGaitSwingProfileDefaultTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSwingProfile Profile;

    TestFalse(TEXT("Ease starts unauthored"), Profile.IsEaseValid());
    TestFalse(TEXT("Arc starts unauthored"), Profile.IsArcValid());

    TestEqual(TEXT("Unauthored ease is the identity at 0"), Profile.SampleEase(0.f), 0.f);
    TestEqual(TEXT("Unauthored ease is the identity at 1"), Profile.SampleEase(1.f), 1.f);
    TestEqual(TEXT("Unauthored ease is the identity mid-swing"), Profile.SampleEase(0.5f), 0.5f);
    TestEqual(TEXT("Unauthored arc adds no lift"), Profile.SampleArc(0.5f), 0.f);

    TestEqual(TEXT("Negative phase clamps to the start"), Profile.SampleEase(-3.f), 0.f);
    TestEqual(TEXT("Phase past 1 clamps to the end"), Profile.SampleEase(4.f), 1.f);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitSwingProfileSamplingTest,
    "Ck.ProceduralAnimation.Gait.SwingProfileSamplesTheCurve", CkProceduralGaitSwingProfileTestLocal::SwingProfileTestFlags)

auto
FCkProceduralGaitSwingProfileSamplingTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSwingProfile Profile;

    Profile.SetEase([](float Phase) { return Phase * 2.f - 0.5f; });
    TestTrue(TEXT("Ease reports authored"), Profile.IsEaseValid());
    TestTrue(TEXT("Authored ease at 0"), FMath::IsNearlyEqual(Profile.SampleEase(0.f), -0.5f, 1.e-5f));
    TestTrue(TEXT("Authored ease at 1"), FMath::IsNearlyEqual(Profile.SampleEase(1.f), 1.5f, 1.e-5f));

    TestTrue(TEXT("Authored ease interpolates between samples"),
        FMath::IsNearlyEqual(Profile.SampleEase(0.3f), 0.1f, 1.e-4f));

    TestTrue(TEXT("Ease values outside 0..1 survive"), Profile.SampleEase(1.f) > 1.f);

    Profile.SetArc([](float Phase) { return FMath::Sin(Phase * PI) * 0.5f; });
    TestTrue(TEXT("Arc reports authored"), Profile.IsArcValid());
    TestTrue(TEXT("Authored arc is zero at takeoff"), FMath::IsNearlyZero(Profile.SampleArc(0.f), 1.e-5f));
    TestTrue(TEXT("Authored arc is zero at landing"), FMath::IsNearlyZero(Profile.SampleArc(1.f), 1.e-5f));
    TestTrue(TEXT("Authored arc peaks mid-swing"), FMath::IsNearlyEqual(Profile.SampleArc(0.5f), 0.5f, 1.e-4f));

    Profile.ClearEase();
    TestFalse(TEXT("Cleared ease is unauthored again"), Profile.IsEaseValid());
    TestTrue(TEXT("Clearing one half leaves the other"), Profile.IsArcValid());

    Profile.Reset();
    TestFalse(TEXT("Reset clears the arc too"), Profile.IsArcValid());

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitTraceAxisTest,
    "Ck.ProceduralAnimation.Gait.TraceAxisLeansOutward", CkProceduralGaitSwingProfileTestLocal::SwingProfileTestFlags)

auto
FCkProceduralGaitTraceAxisTest::RunTest(const FString& InParameters) -> bool
{
    const FVector Radial(1.f, 0.f, 0.f);

    TestTrue(TEXT("Zero lean is pure body-down"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 0.f)
            .Equals(FVector::UpVector, 1.e-5f));

    const FVector Leaned = ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 1.f);
    TestTrue(TEXT("Leaned axis stays normalized"), FMath::IsNearlyEqual(Leaned.Size(), 1.f, 1.e-4f));

    TestTrue(TEXT("Axis tilts away from the radial"), Leaned.X < 0.f);
    TestTrue(TEXT("Axis keeps a positive up component"), Leaned.Z > 0.f);

    TestTrue(TEXT("Lean 1 is 45 degrees"),
        FMath::IsNearlyEqual(FVector::DotProduct(Leaned, FVector::UpVector), FMath::Sqrt(0.5f), 1.e-4f));

    const FVector Half = ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 0.5f);
    TestTrue(TEXT("Half lean is between none and full"), Half.X < 0.f && Half.X > Leaned.X);

    TestTrue(TEXT("Lean is clamped at 1"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, Radial, 5.f).Equals(Leaned, 1.e-5f));

    TestTrue(TEXT("Zero radial falls back to body-down"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, FVector::ZeroVector, 1.f)
            .Equals(FVector::UpVector, 1.e-5f));
    TestTrue(TEXT("Radial parallel to up falls back to body-down"),
        ck::FProceduralGaitSolver::ComputeTraceAxis(FVector::UpVector, FVector::UpVector, 1.f)
            .Equals(FVector::UpVector, 1.e-5f));

    const FVector WallUp(1.f, 0.f, 0.f);
    const FVector WallRadial(0.f, 1.f, 0.f);
    const FVector WallLeaned = ck::FProceduralGaitSolver::ComputeTraceAxis(WallUp, WallRadial, 1.f);
    TestTrue(TEXT("Wall-basis lean tilts against its own radial"), WallLeaned.Y < 0.f);
    TestTrue(TEXT("Wall-basis lean keeps its up component"), WallLeaned.X > 0.f);
    TestTrue(TEXT("Wall-basis lean introduces no third-axis drift"),
        FMath::IsNearlyZero(WallLeaned.Z, 1.e-5f));

    return true;
}

#endif
