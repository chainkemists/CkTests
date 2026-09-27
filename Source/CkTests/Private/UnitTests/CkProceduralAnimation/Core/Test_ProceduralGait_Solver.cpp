#include "CkProceduralAnimation/Core/CkProceduralFootProbe.h"
#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_solver
{
    constexpr auto FrameDt = FCk_Time{1.0f / 60.0f};

    struct FGaitHarness
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
                FCk_Time InDeltaTime,
                bool InAirborne = false)
            -> void
        {
            BodyPosition += BodyVelocity * InDeltaTime.Get_Seconds();
            for (auto Index = 0; Index < Offsets.Num(); ++Index)
            {
                Inputs[Index].Set_IdealTarget(BodyPosition + Offsets[Index]);
            }
            Solver.Step(InDeltaTime, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs, InAirborne);
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitVelocityTrackerTest,
    "Ck.ProceduralAnimation.Gait.VelocityTracker",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitVelocityTrackerTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Tracker = ck::FProceduralGaitVelocityTracker{};

    TestTrue(TEXT("Zero velocity before any samples"), Tracker.Update(FVector::ZeroVector, FrameDt).IsNearlyZero());

    const auto TrueVelocity = FVector{120.0, -40.0, 0.0};
    auto Position = FVector::ZeroVector;
    auto Smoothed = FVector::ZeroVector;
    for (auto Frame = 0; Frame < 10; ++Frame)
    {
        Position += TrueVelocity * FrameDt.Get_Seconds();
        Smoothed = Tracker.Update(Position, FrameDt);
    }
    TestTrue(TEXT("Converges to true velocity under constant motion"),
        Smoothed.Equals(TrueVelocity, 0.1f));

    Smoothed = Tracker.Update(Position, FCk_Time{});
    TestTrue(TEXT("Zero-dt update leaves the estimate intact"),
        Smoothed.Equals(TrueVelocity, 0.1f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitVelocityFrameInvarianceTest,
    "Ck.ProceduralAnimation.Gait.VelocityIsFrameInvariant",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitVelocityFrameInvarianceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    const auto WorldPosition = FVector{1600.0, 1900.0, 90.0};
    constexpr auto OmegaRadPerSecond = 0.18f;

    auto FrameSpaceTracker = ck::FProceduralGaitVelocityTracker{};
    auto WorldSpaceTracker = ck::FProceduralGaitVelocityTracker{};
    auto Frame = FQuat::Identity;

    auto FrameSpaceVelocity = FVector::ZeroVector;
    auto WorldSpaceVelocity = FVector::ZeroVector;
    for (auto FrameIndex = 0; FrameIndex < 12; ++FrameIndex)
    {
        Frame = FQuat{FVector::RightVector, OmegaRadPerSecond * FrameDt.Get_Seconds()} * Frame;

        FrameSpaceVelocity = FrameSpaceTracker.Update(Frame.UnrotateVector(WorldPosition), FrameDt);

        WorldSpaceVelocity = Frame.UnrotateVector(WorldSpaceTracker.Update(WorldPosition, FrameDt));
    }

    TestTrue(TEXT("A still body reads zero however fast its frame turns"),
        WorldSpaceVelocity.IsNearlyZero(0.01f));

    TestTrue(TEXT("Frame-space sampling invents a walk-sized phantom velocity"),
        FrameSpaceVelocity.Size() > 150.0);

    auto MovingTracker = ck::FProceduralGaitVelocityTracker{};
    const auto TrueVelocity = FVector{0.0, 150.0, 0.0};
    auto Position = WorldPosition;
    auto Measured = FVector::ZeroVector;
    Frame = FQuat::Identity;
    for (auto FrameIndex = 0; FrameIndex < 12; ++FrameIndex)
    {
        Frame = FQuat{FVector::RightVector, OmegaRadPerSecond * FrameDt.Get_Seconds()} * Frame;
        Position += TrueVelocity * FrameDt.Get_Seconds();
        Measured = Frame.UnrotateVector(MovingTracker.Update(Position, FrameDt));
    }
    TestTrue(TEXT("Real motion still measures at its true speed"),
        FMath::IsNearlyEqual(Measured.Size(), TrueVelocity.Size(), 1.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitStandingTest,
    "Ck.ProceduralAnimation.Gait.StandingHoldsPlant",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitStandingTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto H = FGaitHarness{};
    H.Init(
        {FVector{30.0, 20.0, 0.0}, FVector{30.0, -20.0, 0.0}, FVector{-30.0, 20.0, 0.0}, FVector{-30.0, -20.0, 0.0}},
        {0.0f, 0.5f, 0.5f, 0.0f});

    for (auto Frame = 0; Frame < 300; ++Frame)
    {
        H.Tick(FrameDt);
        for (auto Leg = 0; Leg < 4; ++Leg)
        {
            if (NOT H.Outputs[Leg].Get_Planted())
            {
                AddError(FString::Printf(TEXT("Leg %d unplanted while standing (frame %d)"), Leg, Frame));
                return false;
            }
        }
    }

    TestTrue(TEXT("Feet still at initial positions"),
        H.Outputs[0].Get_Position().Equals(FVector{30.0, 20.0, 0.0}, KINDA_SMALL_NUMBER));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitStepCompletionTest,
    "Ck.ProceduralAnimation.Gait.StepCompletesOnTarget",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitStepCompletionTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto H = FGaitHarness{};
    H.Init({FVector{30.0, 0.0, 0.0}}, {0.0f});
    H.BodyVelocity = FVector{100.0, 0.0, 0.0};

    H.Solver.Get_Settings().Get_Step().Set_StrokeOvershootFraction(0.0f);

    auto SwingStartFrame = int32{INDEX_NONE};
    for (auto Frame = 0; Frame < 120; ++Frame)
    {
        H.Tick(FrameDt);
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

    const auto MaxSwingFrames = FMath::CeilToInt32(H.Solver.Get_Settings().Get_Step().Get_Duration() / FrameDt) + 2;
    for (auto Frame = 0; Frame < MaxSwingFrames; ++Frame)
    {
        H.Tick(FrameDt);
        if (H.Outputs[0].Get_Planted())
        {
            const auto LandingError = FVector::Dist(H.Outputs[0].Get_Position(), H.Inputs[0].Get_IdealTarget());
            TestTrue(FString::Printf(TEXT("Predicted landing matches the live target (error %.1f)"), LandingError),
                LandingError < 100.0f * FrameDt.Get_Seconds() * 2.0f + 1.0f);
            return true;
        }
        TestTrue(TEXT("SwingAlpha is monotonic-ish and in range"),
            H.Outputs[0].Get_SwingAlpha() >= 0.0f && H.Outputs[0].Get_SwingAlpha() <= 1.0f);
    }

    AddError(TEXT("Swing never completed within StepDuration"));
    return false;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPhaseAlternationTest,
    "Ck.ProceduralAnimation.Gait.PhaseGroupsAlternate",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPhaseAlternationTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto H = FGaitHarness{};
    H.Init({FVector{30.0, 20.0, 0.0}, FVector{30.0, -20.0, 0.0}}, {0.0f, 0.5f});
    H.BodyVelocity = FVector{80.0, 0.0, 0.0};

    auto StepsSeen = 0;
    for (auto Frame = 0; Frame < 600; ++Frame)
    {
        H.Tick(FrameDt);
        const auto Swing0 = NOT H.Outputs[0].Get_Planted();
        const auto Swing1 = NOT H.Outputs[1].Get_Planted();
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

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitEmergencyStepTest,
    "Ck.ProceduralAnimation.Gait.EmergencyStepIgnoresWindow",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitEmergencyStepTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};

    constexpr auto ClosedPhaseOffset = 0.25f;
    Solver.Reset({FVector::ZeroVector});
    if (NOT TestFalse(TEXT("Chosen phase offset's window is closed at clock 0"), Solver.IsWindowOpen(ClosedPhaseOffset)))
    {
        return false;
    }

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    Inputs[0].Set_PhaseOffset(ClosedPhaseOffset);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    Inputs[0].Set_IdealTarget(FVector{Solver.Get_Settings().Get_Step().Get_Threshold() * 1.2f, 0.0, 0.0});
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Sub-emergency error waits for its window"), Outputs[0].Get_Planted());

    Inputs[0].Set_IdealTarget(FVector{
        Solver.Get_Settings().Get_Step().Get_Threshold() * Solver.Get_Settings().Get_Step().Get_EmergencyFactor() * 1.1f, 0.0, 0.0});
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    TestFalse(TEXT("Emergency error steps through a closed window"), Outputs[0].Get_Planted());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitZeroDtTest,
    "Ck.ProceduralAnimation.Gait.ZeroDtIsAPureRead",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitZeroDtTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Reset({FVector::ZeroVector});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    Inputs[0].Set_IdealTarget(FVector{1000.0, 0.0, 0.0});
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    constexpr auto SentinelPlanted = false;
    Outputs[0].Set_Position(FVector{777.0, 888.0, 999.0}).Set_Planted(SentinelPlanted).Set_SwingAlpha(0.75f);
    TestTrue(TEXT("Zero-delta evaluation succeeds"),
        Solver.Step(FCk_Time{}, 500.0f, FVector::ZeroVector, Inputs, Outputs));
    TestTrue(TEXT("Zero-delta evaluation replaces the output sentinel with the current plant"),
        Outputs[0].Get_Position().Equals(FVector::ZeroVector));
    TestEqual(TEXT("Zero-delta evaluation replaces the phase sentinel"), Outputs[0].Get_SwingAlpha(), 0.0f);
    TestTrue(TEXT("No trigger at dt=0 despite huge error"), Outputs[0].Get_Planted());
    TestEqual(TEXT("Clock did not advance at dt=0"), Solver.GetGaitClock(), 0.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSwingBudgetTest,
    "Ck.ProceduralAnimation.Gait.SwingBudgetCaps",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSwingBudgetTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(1).Set_SwingWindow(1.0f);
    Solver.Reset({FVector::ZeroVector, FVector::ZeroVector, FVector::ZeroVector});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(3);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(3);
    for (auto& In : Inputs)
    {
        In.Set_IdealTarget(FVector{Solver.Get_Settings().Get_Step().Get_Threshold() * 1.3f, 0.0, 0.0});
    }

    Solver.Step(FrameDt, 100.0f, FVector::ZeroVector, Inputs, Outputs);

    auto NumSwinging = 0;
    for (const auto& Out : Outputs)
    {
        NumSwinging += Out.Get_Planted() ? 0 : 1;
    }
    TestEqual(TEXT("Exactly one leg swings under a budget of 1"), NumSwinging, 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCadenceScaleTest,
    "Ck.ProceduralAnimation.Gait.CadenceScalesWithSpeed",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitCadenceScaleTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    const auto ClockAfterOneStep = [this, &Inputs, &Outputs](float InCadenceSpeedRef, float InSpeed) -> float
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Cadence().Set_CadenceSpeedRef(InCadenceSpeedRef);
        Solver.Reset({FVector::ZeroVector});
        const auto Stepped = Solver.Step(FrameDt, InSpeed, FVector::ZeroVector, Inputs, Outputs);
        TestTrue(TEXT("The solver accepts the cadence step"), Stepped);
        return Solver.GetGaitClock();
    };

    const auto BaseClock = ClockAfterOneStep(0.0f, 300.0f);
    TestTrue(TEXT("Precondition: the authored cadence advances the clock"), BaseClock > 0.0f);
    TestEqual(TEXT("Feature off: cadence fixed regardless of speed"),
        ClockAfterOneStep(0.0f, 600.0f), BaseClock);
    TestEqual(TEXT("At reference speed: authored cadence"),
        ClockAfterOneStep(300.0f, 300.0f), BaseClock);
    TestEqual(TEXT("Below reference: never slower than authored"),
        ClockAfterOneStep(300.0f, 100.0f), BaseClock);
    TestTrue(TEXT("Double speed: clock advances ~2x"),
        FMath::IsNearlyEqual(ClockAfterOneStep(300.0f, 600.0f), BaseClock * 2.0f, KINDA_SMALL_NUMBER));
    TestTrue(TEXT("Clamped by MaxCadenceScale (3x)"),
        FMath::IsNearlyEqual(ClockAfterOneStep(300.0f, 3000.0f), BaseClock * 3.0f, KINDA_SMALL_NUMBER));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitObstacleClearanceTest,
    "Ck.ProceduralAnimation.Gait.ObstacleClearanceLiftsSwings",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitObstacleClearanceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto H = FGaitHarness{};
    H.Init({FVector{30.0, 0.0, 0.0}}, {0.0f});
    H.BodyVelocity = FVector{100.0, 0.0, 0.0};

    auto SawSwing = false;
    auto MaxSwingZ = -FLT_MAX;
    constexpr auto ObstacleTopZ = 40.0f;
    for (auto Frame = 0; Frame < 240; ++Frame)
    {
        H.Inputs[0].Set_ClearanceGroundZ(SawSwing ? ObstacleTopZ : -FLT_MAX);
        H.Tick(FrameDt);
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

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSetPlantedPoseTest,
    "Ck.ProceduralAnimation.Gait.SetPlantedPoseMovesPlantsOnly",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSetPlantedPoseTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Reset({FVector::ZeroVector});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    const auto Moved = FVector{50.0, 20.0, 5.0};
    Solver.SetPlantedPose(0, Moved, FVector::UpVector);
    Inputs[0].Set_IdealTarget(Moved);
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Planted foot follows the external pose"), Outputs[0].Get_Position().Equals(Moved, KINDA_SMALL_NUMBER));

    Inputs[0].Set_IdealTarget(Moved + FVector{200.0, 0.0, 0.0});
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestFalse(TEXT("Leg is swinging"), Outputs[0].Get_Planted()))
    {
        return false;
    }
    Solver.SetPlantedPose(0, FVector{-999.0, 0.0, 0.0}, FVector::UpVector);
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Swinging leg ignored the external pose"), Outputs[0].Get_Position().X > -100.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSettleAtRestTest,
    "Ck.ProceduralAnimation.Gait.SettleStepsHomeAtRest",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSettleAtRestTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Reset({FVector::ZeroVector});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    const auto Ideal = FVector{Solver.Get_Settings().Get_Step().Get_Threshold() * 0.5f, 0.0, 0.0};
    Inputs[0].Set_IdealTarget(Ideal);

    const auto DelayFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_Settle().Get_Delay() / FrameDt);
    for (auto Frame = 0; Frame < DelayFrames - 2; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted())
        {
            AddError(FString::Printf(TEXT("Settled before SettleDelay elapsed (frame %d)"), Frame));
            return false;
        }
    }

    auto SawSwing = false;
    const auto MaxFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_Settle().Get_Delay() + Solver.Get_Settings().Get_Step().Get_Duration()) / FrameDt) + 10;
    for (auto Frame = 0; Frame < MaxFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        SawSwing |= NOT Outputs[0].Get_Planted();
        if (SawSwing && Outputs[0].Get_Planted())
        {
            break;
        }
    }

    TestTrue(TEXT("A settle swing occurred"), SawSwing);
    TestTrue(TEXT("The foot settled onto its neutral spot"),
        Outputs[0].Get_Position().Equals(Ideal, 1.0f));

    for (auto Frame = 0; Frame < 60; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted())
        {
            AddError(TEXT("Settle re-fired after the foot was already home"));
            return false;
        }
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitAirborneTest,
    "Ck.ProceduralAnimation.Gait.AirborneTucksThenReplants",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitAirborneTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto H = FGaitHarness{};
    H.Init(
        {FVector{30.0, 20.0, 0.0}, FVector{30.0, -20.0, 0.0}, FVector{-30.0, 20.0, 0.0}, FVector{-30.0, -20.0, 0.0}},
        {0.0f, 0.5f, 0.5f, 0.0f});

    constexpr auto Airborne = true;
    for (auto Frame = 0; Frame < 60; ++Frame)
    {
        H.Tick(FrameDt, Airborne);
        for (auto Leg = 0; Leg < 4; ++Leg)
        {
            if (H.Outputs[Leg].Get_Planted())
            {
                AddError(FString::Printf(TEXT("Leg %d planted while airborne (frame %d)"), Leg, Frame));
                return false;
            }
        }
    }
    const auto ExpectedTuck = H.Inputs[0].Get_IdealTarget()
        + FVector{0.0, 0.0, H.Solver.Get_Settings().Get_Airborne().Get_TuckLift()};
    TestTrue(FString::Printf(TEXT("Airborne foot converged on the tuck hold (at %s, expected %s)"),
            *H.Outputs[0].Get_Position().ToCompactString(), *ExpectedTuck.ToCompactString()),
        H.Outputs[0].Get_Position().Equals(ExpectedTuck, 2.0f));

    const auto MaxLandingFrames = FMath::CeilToInt32(
        H.Solver.Get_Settings().Get_Step().Get_Duration() * H.Solver.Get_Settings().Get_Airborne().Get_LandingStepDurationScale() / FrameDt) + 3;
    constexpr auto Grounded = false;
    auto LandedFrame = int32{INDEX_NONE};
    for (auto Frame = 0; Frame < MaxLandingFrames; ++Frame)
    {
        H.Tick(FrameDt, Grounded);
        auto AllPlanted = true;
        for (const auto& Out : H.Outputs)
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
    for (auto Leg = 0; Leg < 4; ++Leg)
    {
        TestTrue(FString::Printf(TEXT("Leg %d landed on its ideal target"), Leg),
            H.Outputs[Leg].Get_Position().Equals(H.Inputs[Leg].Get_IdealTarget(), 1.0f));
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPatternSwitchTest,
    "Ck.ProceduralAnimation.Gait.PatternSwitchIsContinuous",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPatternSwitchTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    {
        auto Walk = ck::FProceduralGaitPattern{};
        Walk.Set_MinSpeed(0.0f).Set_PhaseOffsets({0.0f, 0.5f});
        auto Pace = ck::FProceduralGaitPattern{};
        Pace.Set_MinSpeed(200.0f).Set_PhaseOffsets({0.0f, 0.25f}).Set_CycleDurationScale(0.75f);
        Solver.Get_Settings().Get_Pattern().Set_Patterns({Walk, Pace});
    }
    Solver.Reset({FVector{30.0, 20.0, 0.0}, FVector{30.0, -20.0, 0.0}});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(2);
    Inputs[0].Set_IdealTarget(FVector{30.0, 20.0, 0.0});
    Inputs[1].Set_IdealTarget(FVector{30.0, -20.0, 0.0});
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(2);

    const auto TickAt = [&Solver, &Inputs, &Outputs](float InSpeed) -> void
    {
        Solver.Step(FrameDt, InSpeed, FVector::ZeroVector, Inputs, Outputs);
    };

    for (auto Frame = 0; Frame < 10; ++Frame)
    {
        TickAt(100.0f);
    }
    TestEqual(TEXT("Slow speed selects the walk pattern"), Solver.GetCurrentPatternIndex(), 0);
    TestTrue(TEXT("Walk offsets active"),
        FMath::IsNearlyEqual(Solver.GetEffectivePhaseOffset(1), 0.5f, KINDA_SMALL_NUMBER));

    auto Previous = Solver.GetEffectivePhaseOffset(1);
    const auto BlendFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_Pattern().Get_BlendTime() / FrameDt) + 10;
    for (auto Frame = 0; Frame < BlendFrames; ++Frame)
    {
        TickAt(300.0f);
        const auto Current = Solver.GetEffectivePhaseOffset(1);

        const auto FrameDelta = FMath::Abs(FMath::Frac(Current - Previous + 1.5f) - 0.5f);
        if (FrameDelta > 0.05f)
        {
            AddError(FString::Printf(TEXT("Pattern re-phase popped %.3f in one frame (frame %d)"), FrameDelta, Frame));
            return false;
        }
        Previous = Current;
    }
    TestEqual(TEXT("Fast speed selected the pace pattern"), Solver.GetCurrentPatternIndex(), 1);
    TestTrue(FString::Printf(TEXT("Offsets arrived at the pace pattern (%.3f)"), Solver.GetEffectivePhaseOffset(1)),
        FMath::IsNearlyEqual(Solver.GetEffectivePhaseOffset(1), 0.25f, 1.0e-3f));

    for (auto Frame = 0; Frame < 10; ++Frame)
    {
        TickAt(180.0f);
    }
    TestEqual(TEXT("Hysteresis holds the pace pattern just under its threshold"),
        Solver.GetCurrentPatternIndex(), 1);

    for (auto Frame = 0; Frame < 10; ++Frame)
    {
        TickAt(150.0f);
    }
    TestEqual(TEXT("Dropping below the band returns to walk"), Solver.GetCurrentPatternIndex(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitFootRotationTest,
    "Ck.ProceduralAnimation.Gait.FootRotationConformsWithoutSkate",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitFootRotationTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    const auto Flat = ck::FProceduralGaitSolver::MakeFootRotation(FVector::ForwardVector, FVector::UpVector);
    TestTrue(TEXT("Forward facing on flat ground is the identity frame"),
        Flat.Equals(FQuat::Identity, 1.0e-4f));

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Reset({FVector::ZeroVector});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    const auto SlopeNormal = FVector{0.3f, 0.0f, 1.0f}.GetSafeNormal();
    const auto Facing = FVector{0.0, 1.0, 0.0};
    Inputs[0].Set_IdealTarget(FVector{200.0, 0.0, 0.0}).Set_GroundNormal(SlopeNormal).Set_FacingDirection(Facing);

    const auto SwingFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_Step().Get_Duration() / FrameDt) + 3;
    for (auto Frame = 0; Frame < SwingFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    }
    if (NOT TestTrue(TEXT("The step completed"), Outputs[0].Get_Planted()))
    {
        return false;
    }

    TestTrue(TEXT("Planted frame's Z aligns to the ground normal"),
        Outputs[0].Get_Rotation().GetAxisZ().Equals(SlopeNormal, 1.0e-3f));
    TestTrue(TEXT("Planted frame's X follows the facing (projected on the slope)"),
        FVector::DotProduct(Outputs[0].Get_Rotation().GetAxisX(), Facing) > 0.95);

    const auto PlantedRotation = Outputs[0].Get_Rotation();
    Inputs[0].Set_IdealTarget(Outputs[0].Get_Position()).Set_FacingDirection(FVector{1.0, 0.0, 0.0});
    for (auto Frame = 0; Frame < 30; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    }
    TestTrue(TEXT("Planted rotation is frozen against facing changes"),
        Outputs[0].Get_Rotation().Equals(PlantedRotation, 1.0e-4f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitStrokeOvershootTest,
    "Ck.ProceduralAnimation.Gait.StrokeOvershootPullsThrough",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitStrokeOvershootTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    const auto LandingXForFraction = [](float InFraction, float InMaxOvershoot) -> double
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Step().Set_StrokeOvershootFraction(InFraction).Set_MaxStrokeOvershoot(InMaxOvershoot);
        Solver.Reset({FVector::ZeroVector});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);
        Inputs[0].Set_IdealTarget(FVector{100.0, 0.0, 0.0});

        const auto Frames = FMath::CeilToInt32(Solver.Get_Settings().Get_Step().Get_Duration() / FrameDt) + 3;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        }
        return Outputs[0].Get_Planted() ? Outputs[0].Get_Position().X : TNumericLimits<float>::Lowest();
    };

    const auto NoOvershoot = LandingXForFraction(0.0f, 100.0f);
    TestTrue(FString::Printf(TEXT("Overshoot off lands on the target (%.2f)"), NoOvershoot),
        FMath::IsNearlyEqual(NoOvershoot, 100.0, 0.5));

    const auto Quarter = LandingXForFraction(0.25f, 100.0f);
    TestTrue(FString::Printf(TEXT("25%% of a 100-unit stroke lands at ~125 (%.2f)"), Quarter),
        FMath::IsNearlyEqual(Quarter, 125.0, 0.5));

    const auto Capped = LandingXForFraction(0.25f, 10.0f);
    TestTrue(FString::Printf(TEXT("MaxStrokeOvershoot caps the pull-through (%.2f)"), Capped),
        FMath::IsNearlyEqual(Capped, 110.0, 0.5));

    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Step().Set_StrokeOvershootFraction(0.5f);
        Solver.Reset({FVector::ZeroVector});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        const auto Home = FVector{Solver.Get_Settings().Get_Step().Get_Threshold() * 0.5f, 0.0, 0.0};
        Inputs[0].Set_IdealTarget(Home);

        const auto Frames = FMath::CeilToInt32(
            (Solver.Get_Settings().Get_Settle().Get_Delay() + Solver.Get_Settings().Get_Step().Get_Duration()) / FrameDt) + 10;
        auto SawSwing = false;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            SawSwing |= NOT Outputs[0].Get_Planted();
            if (SawSwing && Outputs[0].Get_Planted())
            {
                break;
            }
        }
        TestTrue(TEXT("A settle swing occurred"), SawSwing);
        TestTrue(FString::Printf(TEXT("Settle landed home, not past it (%.2f vs %.2f)"),
                Outputs[0].Get_Position().X, Home.X),
            Outputs[0].Get_Position().Equals(Home, 1.0f));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitScheduleAdvanceTest,
    "Ck.ProceduralAnimation.Gait.ScheduleAdvanceBeatsStranding",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitScheduleAdvanceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    constexpr auto ClosedPhaseOffset = 0.25f;

    const auto RunWithError = [ClosedPhaseOffset](float InErrorFactor, float InAdvanceFraction, int32 InFrames,
        float& OutClock, bool& OutStepped) -> void
    {
        constexpr auto SettleAtRest = false;
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Schedule().Set_AdvanceFraction(InAdvanceFraction);
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        Solver.Reset({FVector::ZeroVector});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_PhaseOffset(ClosedPhaseOffset)
            .Set_IdealTarget(FVector{Solver.Get_Settings().Get_Step().Get_Threshold() * InErrorFactor, 0.0, 0.0});
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        OutStepped = false;
        for (auto Frame = 0; Frame < InFrames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            OutStepped |= NOT Outputs[0].Get_Planted();
        }
        OutClock = Solver.GetGaitClock();
    };

    auto Clock = 0.0f;
    auto Stepped = false;
    RunWithError(0.8f, 0.6f, 30, Clock, Stepped);
    TestEqual(TEXT("A comfortable error does not move the clock"), Clock, 0.0f);
    TestFalse(TEXT("A comfortable error does not step"), Stepped);

    RunWithError(1.4f, 0.6f, 30, Clock, Stepped);
    TestTrue(FString::Printf(TEXT("An overstretched leg pulls the clock forward (%.3f)"), Clock),
        Clock > 0.0f);
    TestTrue(FString::Printf(TEXT("The clock never overshoots the window it chases (%.3f)"), Clock),
        Clock <= ClosedPhaseOffset + KINDA_SMALL_NUMBER);

    auto OffClock = 0.0f;
    auto OffStepped = false;
    RunWithError(1.4f, 0.0f, 30, OffClock, OffStepped);
    TestEqual(TEXT("Feature off leaves the clock pinned"), OffClock, 0.0f);
    TestFalse(TEXT("Feature off strands the leg"), OffStepped);

    RunWithError(1.4f, 0.6f, 120, Clock, Stepped);
    TestTrue(TEXT("The advance eventually opens the window and the leg steps"), Stepped);

    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Cadence().Set_SwingWindow(1.0f);
        Solver.Reset({FVector::ZeroVector, FVector::ZeroVector});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(2);
        Inputs[0].Set_PhaseOffset(0.0f).Set_IdealTarget(FVector{300.0, 0.0, 0.0});
        Inputs[1].Set_PhaseOffset(0.5f).Set_IdealTarget(FVector{300.0, 0.0, 0.0});
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(2);

        auto SawSwing = false;
        for (auto Frame = 0; Frame < 200; ++Frame)
        {
            Solver.Step(FrameDt, 200.0f, FVector{200.0, 0.0, 0.0}, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
            {
                AddError(FString::Printf(
                    TEXT("Opposing phase groups swung together at frame %d — inhibition was bypassed"), Frame));
                return false;
            }

            SawSwing = SawSwing || NOT Outputs[0].Get_Planted() || NOT Outputs[1].Get_Planted();
        }
        TestTrue(TEXT("At least one leg swung, so the inhibition check was exercised"), SawSwing);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPlantTrustTest,
    "Ck.ProceduralAnimation.Gait.PlantRecordsTrustAtTouchdown",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPlantTrustTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    constexpr auto Untrusted = false;
    const auto Plant = FVector::ZeroVector;
    const auto Get_Trusted = [&]() { return Solver.GetLegState(0).Get_Plant().Get_Trusted(); };

    TestTrue(TEXT("A reset without trust flags trusts every foot"), Solver.Reset({Plant}) && Get_Trusted());
    TestTrue(TEXT("A reset records the caller's trust flag"), Solver.Reset({Plant}, {Untrusted}) && NOT Get_Trusted());
    TestFalse(TEXT("A reset with a trust flag per foot missing is rejected"), Solver.Reset({Plant, Plant}, {Untrusted}));
    TestTrue(TEXT("The rejected reset left the solver as it was"), Solver.NumLegs() == 1 && NOT Get_Trusted());
    Solver.SetPlantedPose(0, Plant, FVector::UpVector);
    TestTrue(TEXT("A planted pose set without a flag is trusted"), Get_Trusted());
    Solver.SetPlantedPose(0, Plant, FVector::UpVector, Untrusted);
    TestFalse(TEXT("A planted pose records the caller's trust flag"), Get_Trusted());

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    // An error beyond the Emergency steps at once, window or not.
    const auto EmergencyStride = Solver.Get_Settings().Get_Step().Get_Threshold() * Solver.Get_Settings().Get_Step().Get_EmergencyFactor() * 1.25;
    const auto StepToTouchdown = [&]() -> bool
    {
        auto Swung = false;
        for (auto Frame = 0; Frame < 120; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted())
            {
                Swung = true;
                continue;
            }
            if (Swung)
            { return true; }
        }
        return false;
    };

    const auto TrustedTarget = FVector{EmergencyStride, 0.0, 0.0};
    Inputs[0].Set_IdealTarget(TrustedTarget).Set_TargetTrusted(true);
    if (NOT TestTrue(TEXT("The leg steps onto a trusted target"), StepToTouchdown()))
    { return false; }
    TestTrue(FString::Printf(TEXT("A swing landing on a trusted target records a trusted plant (plant %s)"),
        *Solver.GetLegState(0).Get_Plant().Get_Position().ToString()), Get_Trusted());

    // Past its contact grace a leg gathers toward its rest target, a valid target on ground nobody probed.
    const auto GatherTarget = FVector{2.0 * EmergencyStride, 0.0, 0.0};
    Inputs[0].Set_IdealTarget(GatherTarget).Set_TargetTrusted(false);
    if (NOT TestTrue(TEXT("The leg gathers toward an untrusted target"), StepToTouchdown()))
    { return false; }
    TestFalse(TEXT("A gather landing on an untrusted target records an untrusted plant"), Get_Trusted());

    // The plant keeps its trust whatever later solves report, until the foot touches down again.
    Inputs[0].Set_IdealTarget(Solver.GetLegState(0).Get_Plant().Get_Position()).Set_TargetTrusted(true);
    constexpr auto HeldFrames = 30;
    for (auto Frame = 0; Frame < HeldFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT TestTrue(FString::Printf(TEXT("Frame %d: the foot stays planted and untrusted while its target reads trusted"), Frame),
                Outputs[0].Get_Planted() && NOT Get_Trusted()))
        { return false; }
    }

    Inputs[0].Set_IdealTarget(FVector{3.0 * EmergencyStride, 0.0, 0.0});
    if (NOT TestTrue(TEXT("The leg steps again"), StepToTouchdown()))
    { return false; }
    TestTrue(TEXT("The next touchdown on a trusted target records a trusted plant again"), Get_Trusted());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPlantTrustFollowsTheLandingGroundTest,
    "Ck.ProceduralAnimation.Gait.PlantTrustFollowsTheLandingGround",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPlantTrustFollowsTheLandingGroundTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Reset({FVector::ZeroVector});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    // An error beyond the Emergency steps at once, window or not; each step is told the same report on every swing frame.
    const auto EmergencyStride = Solver.Get_Settings().Get_Step().Get_Threshold() * Solver.Get_Settings().Get_Step().Get_EmergencyFactor() * 1.25;
    auto Steps = 0;
    const auto TrustAfterStep = [&](ck::EProceduralGaitLandingGround InReport, bool InTargetTrusted) -> TOptional<bool>
    {
        ++Steps;
        const auto Target = FVector{Steps * EmergencyStride, 0.0, 0.0};
        Inputs[0].Set_IdealTarget(Target).Set_TargetTrusted(InTargetTrusted)
            .Set_LandingGround(InReport).Set_LandingGroundZ(static_cast<float>(Target.Z));

        auto Swung = false;
        for (auto Frame = 0; Frame < 120; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted())
            {
                Swung = true;
                continue;
            }
            if (Swung)
            { return Solver.GetLegState(0).Get_Plant().Get_Trusted(); }
        }
        return {};
    };

    constexpr auto TargetTrusted = true;
    constexpr auto TargetUntrusted = false;
    const auto FoundUntrustedTarget = TrustAfterStep(ck::EProceduralGaitLandingGround::Found, TargetUntrusted);
    const auto NoneTrustedTarget = TrustAfterStep(ck::EProceduralGaitLandingGround::None, TargetTrusted);
    const auto UnknownTrustedTarget = TrustAfterStep(ck::EProceduralGaitLandingGround::Unknown, TargetTrusted);
    const auto UnknownUntrustedTarget = TrustAfterStep(ck::EProceduralGaitLandingGround::Unknown, TargetUntrusted);
    if (NOT TestTrue(TEXT("Every step touches down"), FoundUntrustedTarget.IsSet() && NoneTrustedTarget.IsSet()
            && UnknownTrustedTarget.IsSet() && UnknownUntrustedTarget.IsSet()))
    { return false; }

    TestTrue(TEXT("Ground Found under the landing point makes a trusted plant, whatever the target's trust"), FoundUntrustedTarget.GetValue());
    TestFalse(TEXT("No ground under the landing point makes an untrusted plant, whatever the target's trust"), NoneTrustedTarget.GetValue());
    TestTrue(TEXT("With no probe cast, a trusted target makes a trusted plant"), UnknownTrustedTarget.GetValue());
    TestFalse(TEXT("With no probe cast, an untrusted target makes an untrusted plant"), UnknownUntrustedTarget.GetValue());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSwingKeepsItsTargetsTrustTest,
    "Ck.ProceduralAnimation.Gait.SwingKeepsItsTargetsTrust",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSwingKeepsItsTargetsTrustTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    constexpr auto Tolerance = 1.0e-3;
    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Reset({FVector::ZeroVector});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    // An error beyond the Emergency steps at once toward a trusted target on a slope; from its first swing frame on the input
    // has no valid target, names another point, an up normal and no trust.
    const auto EmergencyStride = Solver.Get_Settings().Get_Step().Get_Threshold() * Solver.Get_Settings().Get_Step().Get_EmergencyFactor() * 1.25;
    const auto Target = FVector{EmergencyStride, 0.0, 0.0};
    const auto SlopeNormal = FVector{0.2, 0.0, 1.0}.GetSafeNormal();
    Inputs[0].Set_IdealTarget(Target).Set_GroundNormal(SlopeNormal).Set_TargetTrusted(true);

    auto SwingFrames = 0;
    auto Landed = false;
    for (auto Frame = 0; Frame < 120 && NOT Landed; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (Outputs[0].Get_Planted())
        {
            Landed = SwingFrames > 0;
            continue;
        }

        const auto& Swing = Solver.GetLegState(0).Get_Swing();
        if (NOT TestTrue(FString::Printf(TEXT("Swing frame %d: the swing keeps the target, trust and normal it was given (target %s, trusted %d, normal %s)"),
                SwingFrames, *Swing.Get_Target().ToString(), Swing.Get_TargetTrusted() ? 1 : 0, *Swing.Get_TargetNormal().ToString()),
                Swing.Get_Target().Equals(Target, Tolerance) && Swing.Get_TargetTrusted()
                && Swing.Get_TargetNormal().Equals(SlopeNormal, Tolerance)))
        { return false; }

        ++SwingFrames;
        Inputs[0].Set_TargetValid(false).Set_IdealTarget(FVector{0.0, 3.0 * EmergencyStride, 0.0}).Set_GroundNormal(FVector::UpVector)
            .Set_TargetTrusted(false);
    }

    TestTrue(TEXT("The swing lands"), Landed);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPlantTrustPersistsThroughTheStanceTest,
    "Ck.ProceduralAnimation.Gait.PlantTrustPersistsThroughTheStance",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPlantTrustPersistsThroughTheStanceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_solver;

    constexpr auto StanceFrames = 60;
    constexpr auto SwingFrames = 120;
    constexpr auto SettleAtRest = false;
    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
    Solver.Reset({FVector::ZeroVector});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    // An error beyond the Emergency steps at once. At touchdown the gait's own verdict (SetPlantedPose) disagrees with the
    // input; through the stance that follows the input keeps saying the opposite, and the plant's trust must not follow it.
    const auto EmergencyStride = Solver.Get_Settings().Get_Step().Get_Threshold() * Solver.Get_Settings().Get_Step().Get_EmergencyFactor() * 1.25;
    auto Steps = 0;
    const auto StanceKeepsTrust = [&](bool InTouchdownTrusted) -> bool
    {
        ++Steps;
        const auto Target = FVector{Steps * EmergencyStride, 0.0, 0.0};
        const auto InputTrusted = NOT InTouchdownTrusted;
        Inputs[0].Set_IdealTarget(Target).Set_TargetTrusted(InputTrusted)
            .Set_LandingGround(InputTrusted ? ck::EProceduralGaitLandingGround::Found : ck::EProceduralGaitLandingGround::None)
            .Set_LandingGroundZ(static_cast<float>(Target.Z));

        auto Swung = false;
        auto TouchedDown = false;
        for (auto Frame = 0; Frame < SwingFrames && NOT TouchedDown; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted())
            {
                Swung = true;
                continue;
            }
            TouchedDown = Swung;
        }
        if (NOT TestTrue(FString::Printf(TEXT("Step %d touches down"), Steps), TouchedDown))
        { return false; }

        Solver.SetPlantedPose(0, Outputs[0].Get_Position(), FVector::UpVector, InTouchdownTrusted);
        auto Planted = 0;
        auto Kept = 0;
        for (auto Frame = 0; Frame < StanceFrames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted())
            { break; }
            ++Planted;
            if (Solver.GetLegState(0).Get_Plant().Get_Trusted() == InTouchdownTrusted)
            { ++Kept; }
        }
        TestTrue(FString::Printf(TEXT("Precondition: step %d's foot stays planted through the watched stance (%d of %d frames)"), Steps,
            Planted, StanceFrames), Planted == StanceFrames);
        return Planted > 0 && Kept == Planted;
    };

    constexpr auto Trusted = true;
    constexpr auto Untrusted = false;
    TestTrue(TEXT("A plant set untrusted at touchdown stays untrusted through its stance while the input reports trusted ground"),
        StanceKeepsTrust(Untrusted));
    TestTrue(TEXT("A plant set trusted at touchdown stays trusted through its stance while the input reports no ground"),
        StanceKeepsTrust(Trusted));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitTouchdownSettlesOntoTheHitTest,
    "Ck.ProceduralAnimation.Gait.TouchdownSettlesOntoTheHit",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitTouchdownSettlesOntoTheHitTest::
    RunTest(const FString&)
    -> bool
{
    constexpr auto Tolerance = 0.01;
    constexpr auto HalfSpan = 10.0f;
    // A wall filling x <= 0, its face at x = 0 facing +X. A ray that starts inside it reports a hit at its origin, as Jolt does.
    const auto FaceNormal = FVector::ForwardVector;
    const auto RayCast = [](const FVector& InStart, const FVector& InEnd) -> ck::FProceduralSurfaceHit
    {
        if (InStart.X <= 0.0)
        { return ck::FProceduralSurfaceHit{}.Set_Hit(true).Set_Position(InStart).Set_Normal(FVector::ForwardVector).Set_Fraction(0.0f); }
        if (InEnd.X > 0.0)
        { return ck::FProceduralSurfaceHit{}; }
        const auto Fraction = InStart.X / (InStart.X - InEnd.X);
        return ck::FProceduralSurfaceHit{}.Set_Hit(true).Set_Position(FMath::Lerp(InStart, InEnd, Fraction))
            .Set_Normal(FVector::ForwardVector).Set_Fraction(static_cast<float>(Fraction));
    };

    // A plant 4 cm in front of the face along its normal, where the swing's validated target also lies.
    {
        const auto Plant = FVector{4.0, 20.0, 150.0};
        const auto Touchdown = ck::ResolveProceduralTouchdown(Plant, Plant, FaceNormal, FVector::UpVector, HalfSpan, RayCast);
        TestTrue(FString::Printf(TEXT("A plant 4 cm in front of a face ends on the face, trusted, with its normal (at %s, normal %s, "
                "trusted %d, rays %d)"), *Touchdown.Get_Position().ToString(), *Touchdown.Get_Normal().ToString(),
                Touchdown.Get_Trusted() ? 1 : 0, Touchdown.Get_Rays()),
            Touchdown.Get_Position().Equals(FVector{0.0, 20.0, 150.0}, Tolerance) && Touchdown.Get_Normal().Equals(FaceNormal, Tolerance)
            && Touchdown.Get_Trusted() && Touchdown.Get_Rays() == 1);
    }

    // The plant lies beyond the ray's reach of the face; the validated target 3 cm in front of it: the second ray settles the
    // foot on the face there.
    {
        const auto Plant = FVector{15.0, 20.0, 150.0};
        const auto Validated = FVector{3.0, 20.0, 140.0};
        const auto Touchdown = ck::ResolveProceduralTouchdown(Plant, Validated, FaceNormal, FVector::UpVector, HalfSpan, RayCast);
        TestTrue(FString::Printf(TEXT("A plant the ray misses settles onto the face at the validated target (at %s, trusted %d, rays %d)"),
                *Touchdown.Get_Position().ToString(), Touchdown.Get_Trusted() ? 1 : 0, Touchdown.Get_Rays()),
            Touchdown.Get_Position().Equals(FVector{0.0, 20.0, 140.0}, Tolerance) && Touchdown.Get_Trusted() && Touchdown.Get_Rays() == 2);
    }

    // Both lie beyond the ray's reach: the plant stays where it landed, untrusted, with the support up.
    {
        const auto Plant = FVector{15.0, 20.0, 150.0};
        const auto Validated = FVector{12.0, 20.0, 140.0};
        const auto Touchdown = ck::ResolveProceduralTouchdown(Plant, Validated, FaceNormal, FVector::UpVector, HalfSpan, RayCast);
        TestTrue(FString::Printf(TEXT("A plant no ray confirms stays where it landed, untrusted, with the support up (at %s, normal %s, "
                "trusted %d, rays %d)"), *Touchdown.Get_Position().ToString(), *Touchdown.Get_Normal().ToString(),
                Touchdown.Get_Trusted() ? 1 : 0, Touchdown.Get_Rays()),
            Touchdown.Get_Position().Equals(Plant, Tolerance) && Touchdown.Get_Normal().Equals(FVector::UpVector, Tolerance)
            && NOT Touchdown.Get_Trusted() && Touchdown.Get_Rays() == 2);
    }

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
