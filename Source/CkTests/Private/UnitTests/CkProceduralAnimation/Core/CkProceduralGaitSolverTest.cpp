#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

namespace CkProceduralGaitSolverTestLocal
{
    constexpr EAutomationTestFlags TestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::EngineFilter;

    constexpr FCk_Time FrameDt{1.f / 60.f};

    struct FGaitHarness
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

        void Tick(FCk_Time Dt, bool Airborne = false)
        {
            BodyPosition += BodyVelocity * Dt.Get_Seconds();
            for (int32 i = 0; i < Offsets.Num(); ++i)
            {
                Inputs[i].Get_IdealTarget() = BodyPosition + Offsets[i];
            }
            Solver.Step(Dt, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs, Airborne);
        }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitVelocityTrackerTest,
    "Ck.ProceduralAnimation.Gait.VelocityTracker", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitVelocityTrackerTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitVelocityTracker Tracker;

    TestTrue(TEXT("Zero velocity before any samples"), Tracker.Update(FVector::ZeroVector, CkProceduralGaitSolverTestLocal::FrameDt).IsNearlyZero());

    const FVector TrueVelocity(120.f, -40.f, 0.f);
    FVector Position = FVector::ZeroVector;
    FVector Smoothed = FVector::ZeroVector;
    for (int32 Frame = 0; Frame < 10; ++Frame)
    {
        Position += TrueVelocity * CkProceduralGaitSolverTestLocal::FrameDt.Get_Seconds();
        Smoothed = Tracker.Update(Position, CkProceduralGaitSolverTestLocal::FrameDt);
    }
    TestTrue(TEXT("Converges to true velocity under constant motion"),
        Smoothed.Equals(TrueVelocity, 0.1f));

    Smoothed = Tracker.Update(Position, FCk_Time{});
    TestTrue(TEXT("Zero-dt update leaves the estimate intact"),
        Smoothed.Equals(TrueVelocity, 0.1f));

    Tracker.Reset();
    TestTrue(TEXT("Reset clears the estimate"), Tracker.GetVelocity().IsNearlyZero());

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitVelocityFrameInvarianceTest,
    "Ck.ProceduralAnimation.Gait.VelocityIsFrameInvariant", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitVelocityFrameInvarianceTest::RunTest(const FString& InParameters) -> bool
{
    const FVector WorldPosition(1600.f, 1900.f, 90.f);
    constexpr float OmegaRadPerSecond = 0.18f;

    ck::FProceduralGaitVelocityTracker FrameSpaceTracker;
    ck::FProceduralGaitVelocityTracker WorldSpaceTracker;
    FQuat Frame = FQuat::Identity;

    FVector FrameSpaceVelocity = FVector::ZeroVector;
    FVector WorldSpaceVelocity = FVector::ZeroVector;
    for (int32 FrameIndex = 0; FrameIndex < 12; ++FrameIndex)
    {
        Frame = FQuat(FVector::RightVector, OmegaRadPerSecond * CkProceduralGaitSolverTestLocal::FrameDt.Get_Seconds()) * Frame;

        FrameSpaceVelocity = FrameSpaceTracker.Update(Frame.UnrotateVector(WorldPosition), CkProceduralGaitSolverTestLocal::FrameDt);

        WorldSpaceVelocity = Frame.UnrotateVector(WorldSpaceTracker.Update(WorldPosition, CkProceduralGaitSolverTestLocal::FrameDt));
    }

    TestTrue(TEXT("A still body reads zero however fast its frame turns"),
        WorldSpaceVelocity.IsNearlyZero(0.01f));

    TestTrue(TEXT("Frame-space sampling invents a walk-sized phantom velocity"),
        FrameSpaceVelocity.Size() > 150.f);

    ck::FProceduralGaitVelocityTracker MovingTracker;
    const FVector TrueVelocity(0.f, 150.f, 0.f);
    FVector Position = WorldPosition;
    FVector Measured = FVector::ZeroVector;
    Frame = FQuat::Identity;
    for (int32 FrameIndex = 0; FrameIndex < 12; ++FrameIndex)
    {
        Frame = FQuat(FVector::RightVector, OmegaRadPerSecond * CkProceduralGaitSolverTestLocal::FrameDt.Get_Seconds()) * Frame;
        Position += TrueVelocity * CkProceduralGaitSolverTestLocal::FrameDt.Get_Seconds();
        Measured = Frame.UnrotateVector(MovingTracker.Update(Position, CkProceduralGaitSolverTestLocal::FrameDt));
    }
    TestTrue(TEXT("Real motion still measures at its true speed"),
        FMath::IsNearlyEqual(Measured.Size(), TrueVelocity.Size(), 1.f));

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitStandingTest,
    "Ck.ProceduralAnimation.Gait.StandingHoldsPlant", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitStandingTest::RunTest(const FString& InParameters) -> bool
{
    CkProceduralGaitSolverTestLocal::FGaitHarness H;
    H.Init(
        { FVector(30, 20, 0), FVector(30, -20, 0), FVector(-30, 20, 0), FVector(-30, -20, 0) },
        { 0.f, 0.5f, 0.5f, 0.f });

    for (int32 Frame = 0; Frame < 300; ++Frame)
    {
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt);
        for (int32 Leg = 0; Leg < 4; ++Leg)
        {
            if (NOT H.Outputs[Leg].Get_Planted())
            {
                AddError(FString::Printf(TEXT("Leg %d unplanted while standing (frame %d)"), Leg, Frame));
                return false;
            }
        }
    }

    TestTrue(TEXT("Feet still at initial positions"),
        H.Outputs[0].Get_Position().Equals(FVector(30, 20, 0), KINDA_SMALL_NUMBER));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitStepCompletionTest,
    "Ck.ProceduralAnimation.Gait.StepCompletesOnTarget", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitStepCompletionTest::RunTest(const FString& InParameters) -> bool
{
    CkProceduralGaitSolverTestLocal::FGaitHarness H;
    H.Init({ FVector(30, 0, 0) }, { 0.f });
    H.BodyVelocity = FVector(100.f, 0.f, 0.f);

    H.Solver.Get_Settings().Get_StrokeOvershootFraction() = 0.f;

    int32 SwingStartFrame = -1;
    for (int32 Frame = 0; Frame < 120; ++Frame)
    {
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt);
        if (NOT H.Outputs[0].Get_Planted())
        {
            SwingStartFrame = Frame;
            break;
        }
    }
    if (NOT TestTrue(TEXT("A moving body eventually steps"), SwingStartFrame >= 0))
    {
        return false;
    }

    const int32 MaxSwingFrames = FMath::CeilToInt32(H.Solver.Get_Settings().Get_StepDuration() / CkProceduralGaitSolverTestLocal::FrameDt) + 2;
    for (int32 Frame = 0; Frame < MaxSwingFrames; ++Frame)
    {
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt);
        if (H.Outputs[0].Get_Planted())
        {
            const float LandingError = FVector::Dist(H.Outputs[0].Get_Position(), H.Inputs[0].Get_IdealTarget());
            TestTrue(FString::Printf(TEXT("Predicted landing matches the live target (error %.1f)"), LandingError),
                LandingError < 100.f * CkProceduralGaitSolverTestLocal::FrameDt.Get_Seconds() * 2.f + 1.f);
            return true;
        }
        TestTrue(TEXT("SwingAlpha is monotonic-ish and in range"),
            H.Outputs[0].Get_SwingAlpha() >= 0.f && H.Outputs[0].Get_SwingAlpha() <= 1.f);
    }

    AddError(TEXT("Swing never completed within StepDuration"));
    return false;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitPhaseAlternationTest,
    "Ck.ProceduralAnimation.Gait.PhaseGroupsAlternate", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitPhaseAlternationTest::RunTest(const FString& InParameters) -> bool
{
    CkProceduralGaitSolverTestLocal::FGaitHarness H;
    H.Init({ FVector(30, 20, 0), FVector(30, -20, 0) }, { 0.f, 0.5f });
    H.BodyVelocity = FVector(80.f, 0.f, 0.f);

    int32 StepsSeen = 0;
    for (int32 Frame = 0; Frame < 600; ++Frame)
    {
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt);
        const bool Swing0 = NOT H.Outputs[0].Get_Planted();
        const bool Swing1 = NOT H.Outputs[1].Get_Planted();
        if (Swing0 && Swing1)
        {
            AddError(FString::Printf(TEXT("Opposing phase legs swung simultaneously at frame %d"), Frame));
            return false;
        }
        StepsSeen += (Swing0 || Swing1) ? 1 : 0;
    }

    TestTrue(TEXT("Walking actually produced steps"), StepsSeen > 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitEmergencyStepTest,
    "Ck.ProceduralAnimation.Gait.EmergencyStepIgnoresWindow", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitEmergencyStepTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;

    const float ClosedPhaseOffset = 0.25f;
    Solver.Reset({ FVector::ZeroVector });
    if (NOT TestFalse(TEXT("Chosen phase offset's window is closed at clock 0"), Solver.IsWindowOpen(ClosedPhaseOffset)))
    {
        return false;
    }

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    Inputs[0].Get_PhaseOffset() = ClosedPhaseOffset;
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);

    Inputs[0].Get_IdealTarget() = FVector(Solver.Get_Settings().Get_StepThreshold() * 1.2f, 0, 0);
    Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Sub-emergency error waits for its window"), Outputs[0].Get_Planted());

    Inputs[0].Get_IdealTarget() = FVector(Solver.Get_Settings().Get_StepThreshold() * Solver.Get_Settings().Get_EmergencyStepFactor() * 1.1f, 0, 0);
    Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    TestFalse(TEXT("Emergency error steps through a closed window"), Outputs[0].Get_Planted());

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitZeroDtTest,
    "Ck.ProceduralAnimation.Gait.ZeroDtIsAPureRead", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitZeroDtTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    Solver.Reset({ FVector::ZeroVector });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    Inputs[0].Get_IdealTarget() = FVector(1000.f, 0, 0);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);

    Outputs[0].Set_Position(FVector{777.0, 888.0, 999.0}).Set_Planted(false).Set_SwingAlpha(0.75f);
    TestTrue(TEXT("Zero-delta evaluation succeeds"),
        Solver.Step(FCk_Time{}, 500.f, FVector::ZeroVector, Inputs, Outputs));
    TestTrue(TEXT("Zero-delta evaluation replaces the output sentinel with the current plant"),
        Outputs[0].Get_Position().Equals(FVector::ZeroVector));
    TestEqual(TEXT("Zero-delta evaluation replaces the phase sentinel"), Outputs[0].Get_SwingAlpha(), 0.0f);
    TestTrue(TEXT("No trigger at dt=0 despite huge error"), Outputs[0].Get_Planted());
    TestEqual(TEXT("Clock did not advance at dt=0"), Solver.GetGaitClock(), 0.f);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitSwingBudgetTest,
    "Ck.ProceduralAnimation.Gait.SwingBudgetCaps", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitSwingBudgetTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    Solver.Get_Settings().Get_MaxSimultaneousSwings() = 1;
    Solver.Get_Settings().Get_SwingWindow() = 1.f;
    Solver.Reset({ FVector::ZeroVector, FVector::ZeroVector, FVector::ZeroVector });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(3);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(3);
    for (ck::FProceduralGaitLegInput& In : Inputs)
    {
        In.Get_IdealTarget() = FVector(Solver.Get_Settings().Get_StepThreshold() * 1.3f, 0, 0);
    }

    Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 100.f, FVector::ZeroVector, Inputs, Outputs);

    int32 NumSwinging = 0;
    for (const ck::FProceduralGaitLegOutput& Out : Outputs)
    {
        NumSwinging += Out.Get_Planted() ? 0 : 1;
    }
    TestEqual(TEXT("Exactly one leg swings under a budget of 1"), NumSwinging, 1);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitCadenceScaleTest,
    "Ck.ProceduralAnimation.Gait.CadenceScalesWithSpeed", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitCadenceScaleTest::RunTest(const FString& InParameters) -> bool
{
    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);

    auto ClockAfterOneStep = [&](float CadenceSpeedRef, float Speed)
    {
        ck::FProceduralGaitSolver Solver;
        Solver.Get_Settings().Get_CadenceSpeedRef() = CadenceSpeedRef;
        Solver.Reset({ FVector::ZeroVector });
        Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, Speed, FVector::ZeroVector, Inputs, Outputs);
        return Solver.GetGaitClock();
    };

    const float BaseClock = ClockAfterOneStep( 0.f,  300.f);
    TestEqual(TEXT("Feature off: cadence fixed regardless of speed"),
        ClockAfterOneStep(0.f, 600.f), BaseClock);
    TestEqual(TEXT("At reference speed: authored cadence"),
        ClockAfterOneStep(300.f, 300.f), BaseClock);
    TestEqual(TEXT("Below reference: never slower than authored"),
        ClockAfterOneStep(300.f, 100.f), BaseClock);
    TestTrue(TEXT("Double speed: clock advances ~2x"),
        FMath::IsNearlyEqual(ClockAfterOneStep(300.f, 600.f), BaseClock * 2.f, KINDA_SMALL_NUMBER));
    TestTrue(TEXT("Clamped by MaxCadenceScale (3x)"),
        FMath::IsNearlyEqual(ClockAfterOneStep(300.f, 3000.f), BaseClock * 3.f, KINDA_SMALL_NUMBER));

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitObstacleClearanceTest,
    "Ck.ProceduralAnimation.Gait.ObstacleClearanceLiftsSwings", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitObstacleClearanceTest::RunTest(const FString& InParameters) -> bool
{
    CkProceduralGaitSolverTestLocal::FGaitHarness H;
    H.Init({ FVector(30, 0, 0) }, { 0.f });
    H.BodyVelocity = FVector(100.f, 0.f, 0.f);

    bool SawSwing = false;
    float MaxSwingZ = -FLT_MAX;
    const float ObstacleTopZ = 40.f;
    for (int32 Frame = 0; Frame < 240; ++Frame)
    {
        H.Inputs[0].Get_ClearanceGroundZ() = SawSwing ? ObstacleTopZ : -FLT_MAX;
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt);
        if (NOT H.Outputs[0].Get_Planted())
        {
            SawSwing = true;
            MaxSwingZ = FMath::Max(MaxSwingZ, H.Outputs[0].Get_Position().Z);
        }
        else if (SawSwing)
        {
            break;
        }
    }

    TestTrue(TEXT("A swing occurred"), SawSwing);

    TestTrue(FString::Printf(TEXT("Swing apex cleared the obstacle (max Z %.1f)"), MaxSwingZ),
        MaxSwingZ > ObstacleTopZ);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitSetPlantedPoseTest,
    "Ck.ProceduralAnimation.Gait.SetPlantedPoseMovesPlantsOnly", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitSetPlantedPoseTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    Solver.Reset({ FVector::ZeroVector });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);

    const FVector Moved(50.f, 20.f, 5.f);
    Solver.SetPlantedPose(0, Moved, FVector::UpVector);
    Inputs[0].Get_IdealTarget() = Moved;
    Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Planted foot follows the external pose"), Outputs[0].Get_Position().Equals(Moved, KINDA_SMALL_NUMBER));

    Inputs[0].Get_IdealTarget() = Moved + FVector(200.f, 0, 0);
    Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestFalse(TEXT("Leg is swinging"), Outputs[0].Get_Planted()))
    {
        return false;
    }
    Solver.SetPlantedPose(0, FVector(-999.f, 0, 0), FVector::UpVector);
    Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Swinging leg ignored the external pose"), Outputs[0].Get_Position().X > -100.f);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitSettleAtRestTest,
    "Ck.ProceduralAnimation.Gait.SettleStepsHomeAtRest", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitSettleAtRestTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    Solver.Reset({ FVector::ZeroVector });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);

    const FVector Ideal(Solver.Get_Settings().Get_StepThreshold() * 0.5f, 0, 0);
    Inputs[0].Get_IdealTarget() = Ideal;

    const int32 DelayFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_SettleDelay() / CkProceduralGaitSolverTestLocal::FrameDt);
    for (int32 Frame = 0; Frame < DelayFrames - 2; ++Frame)
    {
        Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted())
        {
            AddError(FString::Printf(TEXT("Settled before SettleDelay elapsed (frame %d)"), Frame));
            return false;
        }
    }

    bool SawSwing = false;
    const int32 MaxFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_SettleDelay() + Solver.Get_Settings().Get_StepDuration()) / CkProceduralGaitSolverTestLocal::FrameDt) + 10;
    for (int32 Frame = 0; Frame < MaxFrames; ++Frame)
    {
        Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        SawSwing |= NOT Outputs[0].Get_Planted();
        if (SawSwing && Outputs[0].Get_Planted())
        {
            break;
        }
    }

    TestTrue(TEXT("A settle swing occurred"), SawSwing);
    TestTrue(TEXT("The foot settled onto its neutral spot"),
        Outputs[0].Get_Position().Equals(Ideal, 1.f));

    for (int32 Frame = 0; Frame < 60; ++Frame)
    {
        Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted())
        {
            AddError(TEXT("Settle re-fired after the foot was already home"));
            return false;
        }
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitAirborneTest,
    "Ck.ProceduralAnimation.Gait.AirborneTucksThenReplants", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitAirborneTest::RunTest(const FString& InParameters) -> bool
{
    CkProceduralGaitSolverTestLocal::FGaitHarness H;
    H.Init(
        { FVector(30, 20, 0), FVector(30, -20, 0), FVector(-30, 20, 0), FVector(-30, -20, 0) },
        { 0.f, 0.5f, 0.5f, 0.f });

    for (int32 Frame = 0; Frame < 60; ++Frame)
    {
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt,  true);
        for (int32 Leg = 0; Leg < 4; ++Leg)
        {
            if (H.Outputs[Leg].Get_Planted())
            {
                AddError(FString::Printf(TEXT("Leg %d planted while airborne (frame %d)"), Leg, Frame));
                return false;
            }
        }
    }
    const FVector ExpectedTuck = H.Inputs[0].Get_IdealTarget()
        + FVector(0, 0, H.Solver.Get_Settings().Get_AirborneTuckLift());
    TestTrue(FString::Printf(TEXT("Airborne foot converged on the tuck hold (at %s, expected %s)"),
            *H.Outputs[0].Get_Position().ToCompactString(), *ExpectedTuck.ToCompactString()),
        H.Outputs[0].Get_Position().Equals(ExpectedTuck, 2.f));

    const int32 MaxLandingFrames = FMath::CeilToInt32(
        H.Solver.Get_Settings().Get_StepDuration() * H.Solver.Get_Settings().Get_LandingStepDurationScale() / CkProceduralGaitSolverTestLocal::FrameDt) + 3;
    int32 LandedFrame = -1;
    for (int32 Frame = 0; Frame < MaxLandingFrames; ++Frame)
    {
        H.Tick(CkProceduralGaitSolverTestLocal::FrameDt,  false);
        bool AllPlanted = true;
        for (const ck::FProceduralGaitLegOutput& Out : H.Outputs)
        {
            AllPlanted &= Out.Get_Planted();
        }
        if (AllPlanted)
        {
            LandedFrame = Frame;
            break;
        }
    }

    if (NOT TestTrue(TEXT("All legs re-planted within the landing swing"), LandedFrame >= 0))
    {
        return false;
    }
    for (int32 Leg = 0; Leg < 4; ++Leg)
    {
        TestTrue(FString::Printf(TEXT("Leg %d landed on its ideal target"), Leg),
            H.Outputs[Leg].Get_Position().Equals(H.Inputs[Leg].Get_IdealTarget(), 1.f));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitPatternSwitchTest,
    "Ck.ProceduralAnimation.Gait.PatternSwitchIsContinuous", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitPatternSwitchTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    {
        ck::FProceduralGaitPattern Walk;
        Walk.Get_MinSpeed() = 0.f;
        Walk.Get_PhaseOffsets() = { 0.f, 0.5f };
        ck::FProceduralGaitPattern Pace;
        Pace.Get_MinSpeed() = 200.f;
        Pace.Get_PhaseOffsets() = { 0.f, 0.25f };
        Pace.Get_CycleDurationScale() = 0.75f;
        Solver.Get_Settings().Get_Patterns() = { Walk, Pace };
    }
    Solver.Reset({ FVector(30, 20, 0), FVector(30, -20, 0) });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(2);
    Inputs[0].Get_IdealTarget() = FVector(30, 20, 0);
    Inputs[1].Get_IdealTarget() = FVector(30, -20, 0);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(2);

    auto TickAt = [&](float Speed) { Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, Speed, FVector::ZeroVector, Inputs, Outputs); };

    for (int32 Frame = 0; Frame < 10; ++Frame)
    {
        TickAt(100.f);
    }
    TestEqual(TEXT("Slow speed selects the walk pattern"), Solver.GetCurrentPatternIndex(), 0);
    TestTrue(TEXT("Walk offsets active"),
        FMath::IsNearlyEqual(Solver.GetEffectivePhaseOffset(1), 0.5f, KINDA_SMALL_NUMBER));

    float Previous = Solver.GetEffectivePhaseOffset(1);
    const int32 BlendFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_PatternBlendTime() / CkProceduralGaitSolverTestLocal::FrameDt) + 10;
    for (int32 Frame = 0; Frame < BlendFrames; ++Frame)
    {
        TickAt(300.f);
        const float Current = Solver.GetEffectivePhaseOffset(1);

        const float FrameDelta = FMath::Abs(FMath::Frac(Current - Previous + 1.5f) - 0.5f);
        if (FrameDelta > 0.05f)
        {
            AddError(FString::Printf(TEXT("Pattern re-phase popped %.3f in one frame (frame %d)"), FrameDelta, Frame));
            return false;
        }
        Previous = Current;
    }
    TestEqual(TEXT("Fast speed selected the pace pattern"), Solver.GetCurrentPatternIndex(), 1);
    TestTrue(FString::Printf(TEXT("Offsets arrived at the pace pattern (%.3f)"), Solver.GetEffectivePhaseOffset(1)),
        FMath::IsNearlyEqual(Solver.GetEffectivePhaseOffset(1), 0.25f, 1.e-3f));

    for (int32 Frame = 0; Frame < 10; ++Frame)
    {
        TickAt(180.f);
    }
    TestEqual(TEXT("Hysteresis holds the pace pattern just under its threshold"),
        Solver.GetCurrentPatternIndex(), 1);

    for (int32 Frame = 0; Frame < 10; ++Frame)
    {
        TickAt(150.f);
    }
    TestEqual(TEXT("Dropping below the band returns to walk"), Solver.GetCurrentPatternIndex(), 0);

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitFootRotationTest,
    "Ck.ProceduralAnimation.Gait.FootRotationConformsWithoutSkate", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitFootRotationTest::RunTest(const FString& InParameters) -> bool
{
    const FQuat Flat = ck::FProceduralGaitSolver::MakeFootRotation(FVector::ForwardVector, FVector::UpVector);
    TestTrue(TEXT("Forward facing on flat ground is the identity frame"),
        Flat.Equals(FQuat::Identity, 1.e-4f));

    ck::FProceduralGaitSolver Solver;
    Solver.Reset({ FVector::ZeroVector });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);

    const FVector SlopeNormal = FVector(0.3f, 0.f, 1.f).GetSafeNormal();
    const FVector Facing = FVector(0.f, 1.f, 0.f);
    Inputs[0].Get_IdealTarget() = FVector(200.f, 0, 0);
    Inputs[0].Get_GroundNormal() = SlopeNormal;
    Inputs[0].Get_FacingDirection() = Facing;

    const int32 SwingFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_StepDuration() / CkProceduralGaitSolverTestLocal::FrameDt) + 3;
    for (int32 Frame = 0; Frame < SwingFrames; ++Frame)
    {
        Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    }
    if (NOT TestTrue(TEXT("The step completed"), Outputs[0].Get_Planted()))
    {
        return false;
    }

    TestTrue(TEXT("Planted frame's Z aligns to the ground normal"),
        Outputs[0].Get_Rotation().GetAxisZ().Equals(SlopeNormal, 1.e-3f));
    TestTrue(TEXT("Planted frame's X follows the facing (projected on the slope)"),
        FVector::DotProduct(Outputs[0].Get_Rotation().GetAxisX(), Facing) > 0.95f);

    const FQuat PlantedRotation = Outputs[0].Get_Rotation();
    Inputs[0].Get_IdealTarget() = Outputs[0].Get_Position();
    Inputs[0].Get_FacingDirection() = FVector(1.f, 0.f, 0.f);
    for (int32 Frame = 0; Frame < 30; ++Frame)
    {
        Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    }
    TestTrue(TEXT("Planted rotation is frozen against facing changes"),
        Outputs[0].Get_Rotation().Equals(PlantedRotation, 1.e-4f));

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitStrokeOvershootTest,
    "Ck.ProceduralAnimation.Gait.StrokeOvershootPullsThrough", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitStrokeOvershootTest::RunTest(const FString& InParameters) -> bool
{
    auto LandingXForFraction = [](float Fraction, float MaxOvershoot)
    {
        ck::FProceduralGaitSolver Solver;
        Solver.Get_Settings().Get_StrokeOvershootFraction() = Fraction;
        Solver.Get_Settings().Get_MaxStrokeOvershoot() = MaxOvershoot;
        Solver.Reset({ FVector::ZeroVector });

        TArray<ck::FProceduralGaitLegInput> Inputs;
        Inputs.SetNum(1);
        TArray<ck::FProceduralGaitLegOutput> Outputs;
        Outputs.SetNum(1);
        Inputs[0].Get_IdealTarget() = FVector(100.f, 0.f, 0.f);

        const int32 Frames = FMath::CeilToInt32(Solver.Get_Settings().Get_StepDuration() / CkProceduralGaitSolverTestLocal::FrameDt) + 3;
        for (int32 Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        }
        return Outputs[0].Get_Planted() ? Outputs[0].Get_Position().X : TNumericLimits<float>::Lowest();
    };

    const float NoOvershoot = LandingXForFraction(0.f, 100.f);
    TestTrue(FString::Printf(TEXT("Overshoot off lands on the target (%.2f)"), NoOvershoot),
        FMath::IsNearlyEqual(NoOvershoot, 100.f, 0.5f));

    const float Quarter = LandingXForFraction(0.25f, 100.f);
    TestTrue(FString::Printf(TEXT("25%% of a 100-unit stroke lands at ~125 (%.2f)"), Quarter),
        FMath::IsNearlyEqual(Quarter, 125.f, 0.5f));

    const float Capped = LandingXForFraction(0.25f, 10.f);
    TestTrue(FString::Printf(TEXT("MaxStrokeOvershoot caps the pull-through (%.2f)"), Capped),
        FMath::IsNearlyEqual(Capped, 110.f, 0.5f));

    {
        ck::FProceduralGaitSolver Solver;
        Solver.Get_Settings().Get_StrokeOvershootFraction() = 0.5f;
        Solver.Reset({ FVector::ZeroVector });

        TArray<ck::FProceduralGaitLegInput> Inputs;
        Inputs.SetNum(1);
        TArray<ck::FProceduralGaitLegOutput> Outputs;
        Outputs.SetNum(1);

        const FVector Home(Solver.Get_Settings().Get_StepThreshold() * 0.5f, 0.f, 0.f);
        Inputs[0].Get_IdealTarget() = Home;

        const int32 Frames = FMath::CeilToInt32(
            (Solver.Get_Settings().Get_SettleDelay() + Solver.Get_Settings().Get_StepDuration()) / CkProceduralGaitSolverTestLocal::FrameDt) + 10;
        bool SawSwing = false;
        for (int32 Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
            SawSwing |= NOT Outputs[0].Get_Planted();
            if (SawSwing && Outputs[0].Get_Planted())
            {
                break;
            }
        }
        TestTrue(TEXT("A settle swing occurred"), SawSwing);
        TestTrue(FString::Printf(TEXT("Settle landed home, not past it (%.2f vs %.2f)"),
                Outputs[0].Get_Position().X, Home.X),
            Outputs[0].Get_Position().Equals(Home, 1.f));
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitScheduleAdvanceTest,
    "Ck.ProceduralAnimation.Gait.ScheduleAdvanceBeatsStranding", CkProceduralGaitSolverTestLocal::TestFlags)

auto
FCkProceduralGaitScheduleAdvanceTest::RunTest(const FString& InParameters) -> bool
{
    const float ClosedPhaseOffset = 0.25f;

    auto RunWithError = [ClosedPhaseOffset](float ErrorFactor, float AdvanceFraction, int32 Frames,
        float& OutClock, bool& OutStepped)
    {
        ck::FProceduralGaitSolver Solver;
        Solver.Get_Settings().Get_ScheduleAdvanceFraction() = AdvanceFraction;

        Solver.Get_Settings().Get_SettleAtRest() = false;
        Solver.Reset({ FVector::ZeroVector });

        TArray<ck::FProceduralGaitLegInput> Inputs;
        Inputs.SetNum(1);
        Inputs[0].Get_PhaseOffset() = ClosedPhaseOffset;
        Inputs[0].Get_IdealTarget() = FVector(Solver.Get_Settings().Get_StepThreshold() * ErrorFactor, 0.f, 0.f);
        TArray<ck::FProceduralGaitLegOutput> Outputs;
        Outputs.SetNum(1);

        OutStepped = false;
        for (int32 Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
            OutStepped |= NOT Outputs[0].Get_Planted();
        }
        OutClock = Solver.GetGaitClock();
    };

    float Clock = 0.f;
    bool Stepped = false;
    RunWithError( 0.8f,  0.6f, 30, Clock, Stepped);
    TestEqual(TEXT("A comfortable error does not move the clock"), Clock, 0.f);
    TestFalse(TEXT("A comfortable error does not step"), Stepped);

    RunWithError( 1.4f,  0.6f, 30, Clock, Stepped);
    TestTrue(FString::Printf(TEXT("An overstretched leg pulls the clock forward (%.3f)"), Clock),
        Clock > 0.f);
    TestTrue(FString::Printf(TEXT("The clock never overshoots the window it chases (%.3f)"), Clock),
        Clock <= ClosedPhaseOffset + KINDA_SMALL_NUMBER);

    float OffClock = 0.f;
    bool OffStepped = false;
    RunWithError( 1.4f,  0.f, 30, OffClock, OffStepped);
    TestEqual(TEXT("Feature off leaves the clock pinned"), OffClock, 0.f);
    TestFalse(TEXT("Feature off strands the leg"), OffStepped);

    RunWithError( 1.4f,  0.6f, 120, Clock, Stepped);
    TestTrue(TEXT("The advance eventually opens the window and the leg steps"), Stepped);

    {
        ck::FProceduralGaitSolver Solver;
        Solver.Get_Settings().Get_SwingWindow() = 1.f;
        Solver.Reset({ FVector::ZeroVector, FVector::ZeroVector });

        TArray<ck::FProceduralGaitLegInput> Inputs;
        Inputs.SetNum(2);
        Inputs[0].Get_PhaseOffset() = 0.f;
        Inputs[1].Get_PhaseOffset() = 0.5f;
        TArray<ck::FProceduralGaitLegOutput> Outputs;
        Outputs.SetNum(2);

        Inputs[0].Get_IdealTarget() = FVector(300.f, 0.f, 0.f);
        Inputs[1].Get_IdealTarget() = FVector(300.f, 0.f, 0.f);

        for (int32 Frame = 0; Frame < 200; ++Frame)
        {
            Solver.Step(CkProceduralGaitSolverTestLocal::FrameDt, 200.f, FVector(200.f, 0.f, 0.f), Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
            {
                AddError(FString::Printf(
                    TEXT("Opposing phase groups swung together at frame %d — inhibition was bypassed"), Frame));
                return false;
            }
        }
    }

    return true;
}

#endif
