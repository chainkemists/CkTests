#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_biped
{
    constexpr auto FrameDt = FCk_Time{1.0f / 60.0f};

    struct FBipedGaitHarness
    {
        ck::FProceduralGaitSolver Solver;
        TArray<FVector> Offsets;
        FVector BodyPosition = FVector::ZeroVector;
        FVector BodyVelocity = FVector::ZeroVector;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        auto
            Init(
                TArrayView<const FVector> InOffsets,
                TArrayView<const float> InPhaseOffsets)
            -> void
        {
            Offsets = TArray<FVector>{InOffsets};
            Inputs.SetNum(Offsets.Num());
            Outputs.SetNum(Offsets.Num());

            auto Initial = TArray<FVector>{};
            for (auto Index = 0; Index < Offsets.Num(); ++Index)
            {
                Initial.Add(BodyPosition + Offsets[Index]);
                Inputs[Index].Set_PhaseOffset(InPhaseOffsets[Index]);
            }
            Solver.Reset(Initial);
        }

        auto
            Tick(
                FCk_Time InDeltaTime)
            -> void
        {
            BodyPosition += BodyVelocity * InDeltaTime.Get_Seconds();
            for (auto Index = 0; Index < Offsets.Num(); ++Index)
            {
                Inputs[Index].Set_IdealTarget(BodyPosition + Offsets[Index]);
            }
            Solver.Step(InDeltaTime, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs);
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitBipedSingleSupportTest,
    "Ck.ProceduralAnimation.Gait.BipedNeverBothFeetAirborne",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitBipedSingleSupportTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_biped;

    const auto WalkAndCheck = [this](FBipedGaitHarness& InHarness, int32 InFrames, const TCHAR* InLabel,
        int32& OutStepsLeg0, int32& OutStepsLeg1) -> bool
    {
        OutStepsLeg0 = 0;
        OutStepsLeg1 = 0;
        auto WasSwinging0 = false;
        auto WasSwinging1 = false;

        for (auto Frame = 0; Frame < InFrames; ++Frame)
        {
            InHarness.Tick(FrameDt);
            const auto Swing0 = NOT InHarness.Outputs[0].Get_Planted();
            const auto Swing1 = NOT InHarness.Outputs[1].Get_Planted();

            if (Swing0 && Swing1)
            {
                AddError(FString::Printf(
                    TEXT("%s: both feet airborne at frame %d — the biped hopped"), InLabel, Frame));
                return false;
            }

            OutStepsLeg0 += (Swing0 && NOT WasSwinging0) ? 1 : 0;
            OutStepsLeg1 += (Swing1 && NOT WasSwinging1) ? 1 : 0;
            WasSwinging0 = Swing0;
            WasSwinging1 = Swing1;
        }
        return true;
    };

    {
        auto H = FBipedGaitHarness{};
        H.Init({FVector{0.0, 20.0, 0.0}, FVector{0.0, -20.0, 0.0}}, {0.0f, 0.5f});
        H.Solver.Get_Settings().Set_MaxSimultaneousSwings(1);
        H.BodyVelocity = FVector{80.0, 0.0, 0.0};

        auto StepsLeg0 = 0;
        auto StepsLeg1 = 0;
        if (NOT WalkAndCheck(H, 1200, TEXT("Opposed offsets"), StepsLeg0, StepsLeg1))
        {
            return false;
        }
        TestTrue(FString::Printf(TEXT("Both legs actually walked (leg0 %d steps, leg1 %d steps)"),
                StepsLeg0, StepsLeg1),
            StepsLeg0 >= 10 && StepsLeg1 >= 10);
    }

    {
        auto H = FBipedGaitHarness{};
        H.Init({FVector{0.0, 20.0, 0.0}, FVector{0.0, -20.0, 0.0}}, {0.0f, 0.0f});
        H.Solver.Get_Settings().Set_MaxSimultaneousSwings(1).Set_SwingWindow(1.0f);

        H.BodyVelocity = FVector{40.0, 0.0, 0.0};

        auto StepsLeg0 = 0;
        auto StepsLeg1 = 0;
        if (NOT WalkAndCheck(H, 1200, TEXT("Equal offsets"), StepsLeg0, StepsLeg1))
        {
            return false;
        }
        TestTrue(FString::Printf(TEXT("The budget serialized rather than starved a leg (leg0 %d, leg1 %d)"),
                StepsLeg0, StepsLeg1),
            StepsLeg0 >= 5 && StepsLeg1 >= 5);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitBipedSettleTest,
    "Ck.ProceduralAnimation.Gait.BipedSettleConvergesFromStraddle",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitBipedSettleTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_biped;

    auto Solver = ck::FProceduralGaitSolver{};

    const auto Neutral0 = FVector{0.0, 20.0, 0.0};
    const auto Neutral1 = FVector{0.0, -20.0, 0.0};

    Solver.Reset({Neutral0 + FVector{18.0, 0.0, 0.0}, Neutral1 - FVector{11.0, 0.0, 0.0}});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(2);
    Inputs[0].Set_IdealTarget(Neutral0).Set_PhaseOffset(0.0f);
    Inputs[1].Set_IdealTarget(Neutral1).Set_PhaseOffset(0.5f);

    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(2);

    const auto DelayFrames = FMath::FloorToInt32(Solver.Get_Settings().Get_SettleDelay() / FrameDt);
    const auto BoundFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_SettleDelay() + Solver.Get_Settings().Get_StepDuration() * 2.0f + FCk_Time{0.5f}) / FrameDt);

    auto ConvergedFrame = int32{INDEX_NONE};
    for (auto Frame = 0; Frame < BoundFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);

        if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(TEXT("Both feet airborne while settling (frame %d)"), Frame));
            return false;
        }

        if (Outputs[0].Get_Planted() && Outputs[1].Get_Planted()
            && Outputs[0].Get_Position().Equals(Neutral0, 1.0f)
            && Outputs[1].Get_Position().Equals(Neutral1, 1.0f))
        {
            ConvergedFrame = Frame;
            break;
        }
    }

    if (NOT TestTrue(FString::Printf(
            TEXT("Settle converged within %d frames (feet at %s / %s)"), BoundFrames,
            *Outputs[0].Get_Position().ToCompactString(), *Outputs[1].Get_Position().ToCompactString()),
        ConvergedFrame >= 0))
    {
        return false;
    }

    TestTrue(FString::Printf(TEXT("Settle waited out SettleDelay (converged at frame %d, delay %d)"),
            ConvergedFrame, DelayFrames),
        ConvergedFrame >= DelayFrames);

    for (auto Frame = 0; Frame < 120; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted() || NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(
                TEXT("Settle re-fired after the stance was already neutral (frame %d)"), Frame));
            return false;
        }
    }

    TestTrue(TEXT("Leg 0 finished on its neutral foothold"), Outputs[0].Get_Position().Equals(Neutral0, 1.0f));
    TestTrue(TEXT("Leg 1 finished on its neutral foothold"), Outputs[1].Get_Position().Equals(Neutral1, 1.0f));

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
