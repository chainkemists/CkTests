#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"
#include "CkProceduralAnimation/Core/CkProceduralGaitSwingProfile.h"
#include "CkProceduralAnimation/Core/CkProceduralBodySupport.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_swing_reach
{
    constexpr auto FrameDt = FCk_Time{1.0 / 60.0};
    constexpr auto Reach = 100.0f;
    constexpr auto Tolerance = 0.01;
    const auto ElevatedPlant = FVector{-90.0, 0.0, 40.0};
    const auto LowerLanding = FVector{0.0, 0.0, -60.0};
    const auto OtherPlant = FVector{30.0, 40.0, -50.0};
    const auto DisabledPlant = FVector{250.0, 0.0, 0.0};

    struct FSwingCase
    {
        ck::FProceduralGaitSolver Solver;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        explicit
            FSwingCase(
                float InReach = Reach)
        {
            Solver.Get_Settings().Get_Step().Set_Threshold(25.0f).Set_Duration(FCk_Time{0.3});
            Solver.Get_Settings().Get_Swing().Set_Height(40.0f);
            Solver.Get_Settings().Get_Settle().Set_AtRest(false);
            Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(1);
            Solver.Reset({ElevatedPlant, OtherPlant, DisabledPlant});
            Inputs.SetNum(3);
            Outputs.SetNum(3);
            Inputs[0].Set_PhaseOffset(0.0f).Set_Hip(FVector::ZeroVector).Set_Reach(InReach)
                .Set_IdealTarget(LowerLanding).Set_TargetValid(true).Set_TargetTrusted(true).Set_TargetIsFoothold(true);
            Inputs[1].Set_PhaseOffset(0.5f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
                .Set_IdealTarget(OtherPlant).Set_TargetValid(true).Set_TargetTrusted(true);
            Inputs[2].Set_Enabled(false).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
                .Set_IdealTarget(FVector::ZeroVector).Set_TargetValid(true).Set_TargetTrusted(true);
        }

        auto
            Tick()
            -> bool
        {
            return Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSwingReachArcTest,
    "Ck.ProceduralAnimation.SwingReach.BoundsElevatedArcAfterLiftoff",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSwingReachArcTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_swing_reach;
    TestTrue(TEXT("The elevated start and lower validated landing both fit the physical chain"),
        ElevatedPlant.Size() < Reach && LowerLanding.Size() < Reach);
    for (const auto MoveHip : {false, true})
    {
        auto Case = FSwingCase{};
        if (NOT TestTrue(TEXT("Takeoff preserves the elevated plant before advancing the arc"),
            Case.Tick() && Case.Solver.GetLegState(0).Get_Swing().Get_Active()
            && Case.Outputs[0].Get_Position().Equals(ElevatedPlant, Tolerance)))
        { return false; }
        if (MoveHip)
        { Case.Inputs[0].Set_Hip(FVector{2.0, 0.0, 0.0}); }
        auto Samples = 0;
        auto WorstReach = 0.0;
        auto UnboundedWitness = false;
        auto Landed = false;
        for (auto Frame = 0; Frame < 24; ++Frame)
        {
            if (NOT Case.Tick())
            { AddError(TEXT("The elevated swing failed while advancing")); return false; }
            TestTrue(TEXT("The other trusted plant stays fixed while the moving leg swings"),
                Case.Outputs[1].Get_Planted() && Case.Solver.GetLegState(1).Get_Plant().Get_Trusted()
                && Case.Outputs[1].Get_Position().Equals(OtherPlant, Tolerance));
            TestTrue(TEXT("The disabled out-of-reach pose is not altered by swing reach enforcement"),
                NOT Case.Solver.GetLegState(2).Get_Swing().Get_Active()
                && Case.Outputs[2].Get_Position().Equals(DisabledPlant, Tolerance));
            if (Case.Outputs[0].Get_Planted())
            {
                Landed = true;
                break;
            }
            ++Samples;
            const auto Position = Case.Outputs[0].Get_Position();
            WorstReach = FMath::Max(WorstReach, FVector::Dist(Position, Case.Inputs[0].Get_Hip()));
            const auto Unbounded = ck::ComputeProceduralSwingPoint(ElevatedPlant, LowerLanding, FVector::UpVector,
                Case.Solver.Get_Settings().Get_Swing(), 40.0f, Case.Outputs[0].Get_SwingAlpha());
            UnboundedWitness = UnboundedWitness || FVector::Dist(Unbounded, Case.Inputs[0].Get_Hip()) > Reach + Tolerance;
            TestTrue(TEXT("The constrained swinging sample remains finite"), NOT Position.ContainsNaN());
            if (Frame == 0)
            {
                const auto Phase = Case.Solver.GetLegState(0).Get_Swing().Get_Phase();
                TestTrue(TEXT("A zero-time observation preserves the constrained swing sample and accepted phase"),
                    Case.Solver.Step(FCk_Time{}, 0.0f, FVector::ZeroVector, Case.Inputs, Case.Outputs)
                    && Case.Outputs[0].Get_Position().Equals(Position, Tolerance)
                    && Case.Solver.GetLegState(0).Get_Swing().Get_Phase() == Phase);
            }
        }
        TestTrue(FString::Printf(TEXT("%s hip: the authored elevated arc contains a genuine unreachable sample"),
            MoveHip ? TEXT("Moving") : TEXT("Stationary")), UnboundedWitness && Samples > 5);
        TestTrue(FString::Printf(TEXT("%s hip: every published swing sample fits physical reach (worst %.6f of %.1f cm)"),
            MoveHip ? TEXT("Moving") : TEXT("Stationary"), WorstReach, Reach), WorstReach <= Reach + Tolerance);
        TestTrue(TEXT("The trusted landing remains the exact validated lower contact"),
            Landed && Case.Solver.GetLegState(0).Get_Plant().Get_Trusted()
            && Case.Outputs[0].Get_Position().Equals(LowerLanding, Tolerance));
    }

    // The flight projection must not inherit ClampToReach's separate radial fallback at exactly vertical reach.
    auto ThresholdPoints = TArray<FVector>{};
    for (const auto DesiredZ : {99.999, 100.0, 100.001})
    {
        auto Case = FSwingCase{};
        const auto Phase = static_cast<float>(FrameDt.Get_Seconds() / 0.3);
        const auto Chord = ck::ComputeProceduralSwingPoint(ElevatedPlant, LowerLanding, FVector::UpVector,
            Case.Solver.Get_Settings().Get_Swing(), 0.0f, Phase);
        const auto Arc = ck::procedural_gait_swing::ParametricArc(Phase, 0.5f, 1.0f);
        Case.Solver.Get_Settings().Get_Swing().Set_Height(static_cast<float>((DesiredZ - Chord.Z) / Arc));
        if (NOT TestTrue(TEXT("The vertical-boundary control reaches its first swinging sample"), Case.Tick() && Case.Tick()))
        { return false; }
        const auto Point = Case.Outputs[0].Get_Position();
        TestTrue(TEXT("The vertical-boundary swing remains inside physical reach"), Point.Size() <= Reach + Tolerance);
        ThresholdPoints.Add(Point);
    }
    TestTrue(TEXT("Flight reach projection stays continuous across the vertical reach boundary"),
        FVector::Dist(ThresholdPoints[0], ThresholdPoints[1]) < 0.5
        && FVector::Dist(ThresholdPoints[1], ThresholdPoints[2]) < 0.5);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSwingReachLegacyTest,
    "Ck.ProceduralAnimation.SwingReach.ZeroReachRetainsAuthoredArc",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSwingReachLegacyTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_swing_reach;
    auto Case = FSwingCase{0.0f};
    if (NOT TestTrue(TEXT("An unconstrained leg starts its elevated swing"),
        Case.Tick() && Case.Solver.GetLegState(0).Get_Swing().Get_Active()))
    { return false; }
    Case.Inputs[0].Set_Hip(FVector{2.0, 0.0, 0.0});
    auto Samples = 0;
    auto HasBeyondPhysicalControl = false;
    auto Landed = false;
    for (auto Frame = 0; Frame < 24; ++Frame)
    {
        if (NOT Case.Tick())
        { AddError(TEXT("The unconstrained control failed")); return false; }
        if (Case.Outputs[0].Get_Planted())
        { Landed = true; break; }
        ++Samples;
        const auto Expected = ck::ComputeProceduralSwingPoint(ElevatedPlant, LowerLanding, FVector::UpVector,
            Case.Solver.Get_Settings().Get_Swing(), 40.0f, Case.Outputs[0].Get_SwingAlpha());
        TestTrue(TEXT("Reach zero keeps the authored curve, even when a physical 100 cm chain would not fit"),
            Case.Outputs[0].Get_Position().Equals(Expected, Tolerance));
        HasBeyondPhysicalControl = HasBeyondPhysicalControl
            || FVector::Dist(Expected, Case.Inputs[0].Get_Hip()) > Reach + Tolerance;
    }
    TestTrue(TEXT("The zero-reach compatibility control actually exercises an unreachable authored arc"),
        Samples > 5 && HasBeyondPhysicalControl);
    TestTrue(TEXT("Reach zero still completes the original trusted landing"),
        Landed && Case.Outputs[0].Get_Position().Equals(LowerLanding, Tolerance)
        && Case.Solver.GetLegState(0).Get_Plant().Get_Trusted());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSwingReachPoseTest,
    "Ck.ProceduralAnimation.SwingReach.CurrentSwingEndpointCanConstrainPresentation",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSwingReachPoseTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_swing_reach;
    // This proves the existing projection helper accepts a bounded current swing endpoint. Collection of swinging legs
    // after gait, and the next presentation spring's freshness, require the real-rig regression separately.
    const auto CurrentSwing = FVector{-99.0, 0.0, 10.0};
    const auto Proposed = FTransform{FQuat::Identity, FVector{5.0, 0.0, 0.0}};
    const auto Anchors = TArray<ck::FProceduralBodyPoseReachAnchor>{
        {FVector::ZeroVector, CurrentSwing, Reach}};
    TestTrue(TEXT("The simulation swing endpoint fits while the unconstrained new pose would not"),
        CurrentSwing.Size() <= Reach && FVector::Dist(Proposed.TransformPosition(FVector::ZeroVector), CurrentSwing) > Reach);
    const auto Projected = ck::ProjectProceduralBodyPoseToReach(FTransform::Identity, FTransform::Identity, Proposed, Anchors);
    if (NOT TestTrue(TEXT("The current swing endpoint admits a checked presentation projection"), Projected.IsSet()))
    { return false; }
    TestTrue(TEXT("The spring keeps only a physically reachable partial pose without moving the swing endpoint"),
        Projected->Get_Fraction() > 0.0f && Projected->Get_Fraction() < 1.0f
        && FVector::Dist(Projected->Get_Offset().TransformPosition(FVector::ZeroVector), CurrentSwing) <= Reach + Tolerance
        && Anchors[0].Get_FootWorld().Equals(CurrentSwing, Tolerance));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
