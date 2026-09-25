#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

namespace CkProceduralGaitBipedTestLocal
{
    constexpr EAutomationTestFlags BipedTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::EngineFilter;

    constexpr FCk_Time BipedFrameDt{1.f / 60.f};

    struct FBipedGaitHarness
    {
        ck::FProceduralGaitSolver Solver;
        TArray<FVector> Offsets;
        FVector BodyPosition = FVector::ZeroVector;
        FVector BodyVelocity = FVector::ZeroVector;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        void Init(std::initializer_list<FVector> InOffsets, std::initializer_list<float> PhaseOffsets)
        {
            Offsets = InOffsets;
            Inputs.SetNum(Offsets.Num());
            Outputs.SetNum(Offsets.Num());

            TArray<FVector> Initial;
            for (int32 i = 0; i < Offsets.Num(); ++i)
            {
                Initial.Add(BodyPosition + Offsets[i]);
                Inputs[i].Get_PhaseOffset() = PhaseOffsets.begin()[i];
            }
            Solver.Reset(Initial);
        }

        void Tick(FCk_Time Dt)
        {
            BodyPosition += BodyVelocity * Dt.Get_Seconds();
            for (int32 i = 0; i < Offsets.Num(); ++i)
            {
                Inputs[i].Get_IdealTarget() = BodyPosition + Offsets[i];
            }
            Solver.Step(Dt, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs);
        }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitBipedSingleSupportTest,
    "Ck.ProceduralAnimation.Gait.BipedNeverBothFeetAirborne", CkProceduralGaitBipedTestLocal::BipedTestFlags)

auto
FCkProceduralGaitBipedSingleSupportTest::RunTest(const FString& InParameters) -> bool
{
    auto WalkAndCheck = [this](CkProceduralGaitBipedTestLocal::FBipedGaitHarness& H, int32 Frames, const TCHAR* Label,
        int32& OutStepsLeg0, int32& OutStepsLeg1)
    {
        OutStepsLeg0 = 0;
        OutStepsLeg1 = 0;
        bool WasSwinging0 = false;
        bool WasSwinging1 = false;

        for (int32 Frame = 0; Frame < Frames; ++Frame)
        {
            H.Tick(CkProceduralGaitBipedTestLocal::BipedFrameDt);
            const bool Swing0 = NOT H.Outputs[0].Get_Planted();
            const bool Swing1 = NOT H.Outputs[1].Get_Planted();

            if (Swing0 && Swing1)
            {
                AddError(FString::Printf(
                    TEXT("%s: both feet airborne at frame %d — the biped hopped"), Label, Frame));
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
        CkProceduralGaitBipedTestLocal::FBipedGaitHarness H;
        H.Init({ FVector(0.f, 20.f, 0.f), FVector(0.f, -20.f, 0.f) }, { 0.f, 0.5f });
        H.Solver.Get_Settings().Get_MaxSimultaneousSwings() = 1;
        H.BodyVelocity = FVector(80.f, 0.f, 0.f);

        int32 StepsLeg0 = 0;
        int32 StepsLeg1 = 0;
        if (NOT WalkAndCheck(H, 1200, TEXT("Opposed offsets"), StepsLeg0, StepsLeg1))
        {
            return false;
        }
        TestTrue(FString::Printf(TEXT("Both legs actually walked (leg0 %d steps, leg1 %d steps)"),
                StepsLeg0, StepsLeg1),
            StepsLeg0 >= 10 && StepsLeg1 >= 10);
    }

    {
        CkProceduralGaitBipedTestLocal::FBipedGaitHarness H;
        H.Init({ FVector(0.f, 20.f, 0.f), FVector(0.f, -20.f, 0.f) }, { 0.f, 0.f });
        H.Solver.Get_Settings().Get_MaxSimultaneousSwings() = 1;

        H.Solver.Get_Settings().Get_SwingWindow() = 1.f;

        H.BodyVelocity = FVector(40.f, 0.f, 0.f);

        int32 StepsLeg0 = 0;
        int32 StepsLeg1 = 0;
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitBipedSettleTest,
    "Ck.ProceduralAnimation.Gait.BipedSettleConvergesFromStraddle", CkProceduralGaitBipedTestLocal::BipedTestFlags)

auto
FCkProceduralGaitBipedSettleTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;

    const FVector Neutral0(0.f, 20.f, 0.f);
    const FVector Neutral1(0.f, -20.f, 0.f);

    Solver.Reset({ Neutral0 + FVector(18.f, 0.f, 0.f), Neutral1 - FVector(11.f, 0.f, 0.f) });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(2);
    Inputs[0].Get_IdealTarget() = Neutral0;
    Inputs[0].Get_PhaseOffset() = 0.f;
    Inputs[1].Get_IdealTarget() = Neutral1;
    Inputs[1].Get_PhaseOffset() = 0.5f;

    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(2);

    const int32 DelayFrames = FMath::FloorToInt32(Solver.Get_Settings().Get_SettleDelay() / CkProceduralGaitBipedTestLocal::BipedFrameDt);
    const int32 BoundFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_SettleDelay() + Solver.Get_Settings().Get_StepDuration() * 2.f + FCk_Time{0.5f}) / CkProceduralGaitBipedTestLocal::BipedFrameDt);

    int32 ConvergedFrame = -1;
    for (int32 Frame = 0; Frame < BoundFrames; ++Frame)
    {
        Solver.Step(CkProceduralGaitBipedTestLocal::BipedFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);

        if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(TEXT("Both feet airborne while settling (frame %d)"), Frame));
            return false;
        }

        if (Outputs[0].Get_Planted() && Outputs[1].Get_Planted()
            && Outputs[0].Get_Position().Equals(Neutral0, 1.f)
            && Outputs[1].Get_Position().Equals(Neutral1, 1.f))
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

    for (int32 Frame = 0; Frame < 120; ++Frame)
    {
        Solver.Step(CkProceduralGaitBipedTestLocal::BipedFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted() || NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(
                TEXT("Settle re-fired after the stance was already neutral (frame %d)"), Frame));
            return false;
        }
    }

    TestTrue(TEXT("Leg 0 finished on its neutral foothold"), Outputs[0].Get_Position().Equals(Neutral0, 1.f));
    TestTrue(TEXT("Leg 1 finished on its neutral foothold"), Outputs[1].Get_Position().Equals(Neutral1, 1.f));

    return true;
}

#endif
