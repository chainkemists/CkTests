#include "CkProceduralAnimation/Core/CkProceduralChainClearance.h"
#include "CkProceduralAnimation/Core/CkProceduralLegCurve.h"

#include "../../CkUnitTest_Common.h"

#include <FABRIK.h>
#include <TwoBoneIK.h>
#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBendSideRecordedPoleAndKneeTest,
    "Ck.ProceduralAnimation.ChainClearance.BendSideRecordedPoleAndKnee",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBendSideRecordedPoleAndKneeTest::
    RunTest(
        const FString&)
    -> bool
{
    // Published Ledge Spider Leg5 at t14.859569: +90 is on the bend-plane boundary, but its pole points inward.
    const auto Hip = FVector{1074.590, 14.837, 90.360};
    const auto Foot = FVector{1152.336, 76.094, 0.0};
    const auto Up = FVector{0.0000967838, 0.0003329082, 0.9999999399};
    const auto Pole = FVector{1136.615037, 47.363211, 240.343178};
    const auto Knee = FVector{1108.026, -21.228, 81.340};
    const auto ChosenPole = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 90.0f);
    const auto Lengths = TArray<float>{50.0f, 60.0f, 60.0f, 50.0f};
    auto Authored = TArray<FVector>{};
    Authored.SetNumZeroed(5);
    TestTrue(TEXT("Recorded authored Curve pose solves"), ck::SolveProceduralLegCurve(Hip, Foot, Pole - Hip, Lengths, Authored));
    TestFalse(TEXT("A bend-plane boundary knee does not excuse an inward pole"),
        ck::Get_IsProceduralBendSidePreserved(Hip, Foot, Pole, Up, Authored[1], ChosenPole, Knee));
    TestTrue(TEXT("Authored pose remains admitted"),
        ck::Get_IsProceduralBendSidePreserved(Hip, Foot, Pole, Up, Authored[1], Pole, Authored[1]));

    // Source-equivalent +150 candidate from the same accepted body frame, Leg6: both actual knee sides are negative.
    const auto OtherHip = FVector{1055.512, 30.765, 90.356};
    const auto OtherFoot = FVector{1176.568972, 41.027916, 13.003954};
    const auto OtherPole = FVector{1076.410323, 97.627007, 240.331727};
    const auto OtherKnee = FVector{1053.417055, -9.308019, 60.527081};
    TestTrue(TEXT("Second recorded authored pose solves"),
        ck::SolveProceduralLegCurve(OtherHip, OtherFoot, OtherPole - OtherHip, Lengths, Authored));
    TestFalse(TEXT("Actual J1 inversion rejects even if supplied pole retains its authored side"),
        ck::Get_IsProceduralBendSidePreserved(OtherHip, OtherFoot, OtherPole, Up, Authored[1], OtherPole, OtherKnee));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBendSideAuthoredAndDegenerateControlsTest,
    "Ck.ProceduralAnimation.ChainClearance.BendSideAuthoredAndDegenerateControls",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBendSideAuthoredAndDegenerateControlsTest::
    RunTest(
        const FString&)
    -> bool
{
    const auto Hip = FVector::ZeroVector;
    const auto Foot = FVector{100.0, 0.0, 0.0};
    const auto Up = FVector::UpVector;
    const auto Pole = FVector{0.0, 40.0, 50.0};
    const auto Knee = FVector{50.0, 30.0, 30.0};
    const auto Admits = [&](const FVector& InPole, const FVector& InAuthoredKnee,
        const FVector& InCandidatePole, const FVector& InKnee) -> bool
    {
        return ck::Get_IsProceduralBendSidePreserved(Hip, Foot, InPole, Up,
            InAuthoredKnee, InCandidatePole, InKnee);
    };
    TestTrue(TEXT("Ordinary authored branch"), Admits(Pole, Knee, Pole, Knee));
    TestFalse(TEXT("Inward actual knee cannot hide behind an outward pole"),
        Admits(Pole, Knee, Pole, FVector{50.0, -30.0, 30.0}));
    const auto ReversePole = FVector{0.0, -40.0, 50.0};
    const auto ReverseKnee = FVector{50.0, -30.0, 30.0};
    TestTrue(TEXT("Reverse authoring preserves its own side"), Admits(ReversePole, ReverseKnee, ReversePole, ReverseKnee));
    TestFalse(TEXT("Reverse authoring does not inherit positive body-radial policy"),
        Admits(ReversePole, ReverseKnee, ReversePole, Knee));
    TestTrue(TEXT("A deliberately authored negative knee remains available"), Admits(Pole, ReverseKnee, Pole, ReverseKnee));
    TestTrue(TEXT("A deliberately negative knee may become less negative"),
        Admits(Pole, ReverseKnee, Pole, FVector{50.0, -20.0, 30.0}));
    TestFalse(TEXT("A deliberately negative knee cannot become more negative"),
        Admits(Pole, ReverseKnee, Pole, FVector{50.0, -40.0, 30.0}));
    TestTrue(TEXT("An exactly straight actual knee is a halfspace boundary"), Admits(Pole, Knee, Pole, FVector{50.0, 0.0, 0.0}));
    const auto ParallelPole = FVector{50.0, 0.0, 0.0};
    TestTrue(TEXT("Projected-pole degeneracy uses actual authored knee"), Admits(ParallelPole, Knee, ParallelPole, Knee));
    TestFalse(TEXT("Actual authored fallback bend cannot invert"),
        Admits(ParallelPole, Knee, ParallelPole, -Knee));
    const auto VerticalPole = FVector{0.0, 0.0, 50.0};
    TestTrue(TEXT("Pure-up authoring invents no horizontal knee restriction"),
        Admits(VerticalPole, FVector{50.0, 0.0, 30.0}, VerticalPole, FVector{50.0, -30.0, 30.0}));

    const auto Rotation = FQuat{FRotator{37.0, 81.0, -23.0}};
    const auto Translation = FVector{456.0, -123.0, 789.0};
    const auto Position = [&](const FVector& InPosition) -> FVector
    { return Translation + Rotation.RotateVector(InPosition); };
    TestTrue(TEXT("Full three-axis posed-body rotation preserves authored admission"),
        ck::Get_IsProceduralBendSidePreserved(Position(Hip), Position(Foot), Position(Pole),
            Rotation.RotateVector(Up), Position(Knee), Position(Pole), Position(Knee)));
    TestFalse(TEXT("Full three-axis posed-body rotation still rejects inward knee"),
        ck::Get_IsProceduralBendSidePreserved(Position(Hip), Position(Foot), Position(Pole),
            Rotation.RotateVector(Up), Position(Knee), Position(Pole), Position(FVector{50.0, -30.0, 30.0})));
    TestFalse(TEXT("Nonfinite candidate rejects"), Admits(Pole, Knee, Pole,
        FVector{std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0}));
    TestTrue(TEXT("Coincident finite endpoints retain the authored pose"),
        ck::Get_IsProceduralBendSidePreserved(Hip, Hip, Pole, Up, Knee, Pole, Knee));
    TestFalse(TEXT("No posed body-up rejects"),
        ck::Get_IsProceduralBendSidePreserved(Hip, Foot, Pole, FVector::ZeroVector, Knee, Pole, Knee));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBendSideActualSolverJointsTest,
    "Ck.ProceduralAnimation.ChainClearance.BendSideActualSolverJoints",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralBendSideActualSolverJointsTest::
    RunTest(
        const FString&)
    -> bool
{
    const auto Hip = FVector::ZeroVector;
    const auto Foot = FVector{100.0, 0.0, 0.0};
    const auto Pole = FVector{30.0, 80.0, 40.0};
    const auto Swivelled = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 150.0f);
    const auto Lengths = TArray<float>{60.0f, 80.0f};
    const auto Solve = [&](int32 InSolver, const FVector& InPole) -> TArray<FVector>
    {
        auto Joints = TArray<FVector>{Hip, FVector::ZeroVector, Foot};
        const auto Direction = (InPole - Hip).GetSafeNormal();
        if (InSolver == 0)
        {
            const auto Seed = Hip + Direction * Lengths[0];
            AnimationCore::SolveTwoBoneIK(Hip, Seed, Foot, InPole, Foot, Joints[1], Joints[2],
                Lengths[0], Lengths[1], false, 1.0, 1.0);
        }
        else if (InSolver == 1)
        {
            auto Links = TArray<FFABRIKChainLink>{};
            Links.Emplace(Hip, 0.0, 0, 0);
            Links.Emplace(Hip + Direction * Lengths[0], Lengths[0], 1, 1);
            Links.Emplace(Links[1].Position + (Foot - Links[1].Position).GetSafeNormal() * Lengths[1], Lengths[1], 2, 2);
            AnimationCore::SolveFabrik(Links, Foot, 140.0, 0.1, 10);
            Joints[1] = Links[1].Position;
            Joints[2] = Links[2].Position;
        }
        else
        {
            TestTrue(TEXT("Curve actual pose solves"), ck::SolveProceduralLegCurve(Hip, Foot, InPole - Hip, Lengths, Joints));
        }
        return Joints;
    };
    for (auto Solver = 0; Solver < 3; ++Solver)
    {
        const auto Authored = Solve(Solver, Pole);
        const auto Candidate = Solve(Solver, Swivelled);
        TestTrue(FString::Printf(TEXT("Solver %d authored result remains available"), Solver),
            ck::Get_IsProceduralBendSidePreserved(Hip, Foot, Pole, FVector::UpVector, Authored[1], Pole, Authored[1]));
        TestFalse(FString::Printf(TEXT("Solver %d actual inverted first joint rejects independent of candidate pole"), Solver),
            ck::Get_IsProceduralBendSidePreserved(Hip, Foot, Pole, FVector::UpVector, Authored[1], Pole, Candidate[1]));
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_DEV_AUTOMATION_TESTS
