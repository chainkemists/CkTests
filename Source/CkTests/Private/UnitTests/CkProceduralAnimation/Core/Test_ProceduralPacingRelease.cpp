#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"
#include "CkProceduralAnimation/Core/CkProceduralSurfaceMotion.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_pacing_release
{
    constexpr auto FrameDt = FCk_Time{1.0 / 60.0};
    constexpr auto Reach = 100.0f;
    constexpr auto Clearance = 65.0f;
    constexpr auto Tolerance = 1.0e-3;
    const auto PeerPlant = FVector{0.0, -60.0, -40.0};
    const auto HeldPlant = FVector{0.0, 60.0, -40.0};
    const auto Replacement = FVector{0.0, 45.0, -40.0};
    const auto TrialHip = FVector{0.0, -40.0, 0.0};
    const auto TrialPosedHip = FVector{0.0, -45.0, 0.0};

    auto
        MakeReliefTrial()
        -> ck::FProceduralGaitReachPaceTrial
    {
        return ck::FProceduralGaitReachPaceTrial{}
            .Set_Hip(TrialHip).Set_PosedHip(TOptional<FVector>{TrialPosedHip});
    }

    struct FReliefCase
    {
        ck::FProceduralGaitSolver Solver;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        explicit
            FReliefCase(
                int32 InBudget = 2,
                bool InPlantTrusted = true,
                bool InOccupiedTarget = false)
        {
            Solver.Get_Settings().Get_Step().Set_Threshold(25.0f).Set_Duration(FCk_Time{0.3});
            Solver.Get_Settings().Get_Settle().Set_AtRest(false);
            Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(InBudget);
            const auto Initial = InOccupiedTarget
                ? TArray<FVector>{PeerPlant, HeldPlant, Replacement} : TArray<FVector>{PeerPlant, HeldPlant};
            auto Trust = TArray<bool>{true, InPlantTrusted};
            if (InOccupiedTarget)
            { Trust.Add(true); }
            Solver.Reset(Initial, Trust);
            Inputs.SetNum(Initial.Num());
            Outputs.SetNum(Initial.Num());
            Inputs[0].Set_PhaseOffset(0.0f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
                .Set_IdealTarget(FVector{30.0, -60.0, -40.0}).Set_TargetTrusted(true).Set_TargetValid(true);
            Inputs[1].Set_PhaseOffset(0.5f).Set_Hip(FVector::ZeroVector).Set_PosedHip(TOptional<FVector>{FVector::ZeroVector})
                .Set_Reach(Reach).Set_IdealTarget(Replacement).Set_TargetValid(true).Set_TargetTrusted(true);
            if (InOccupiedTarget)
            {
                Inputs[1].Set_FootContactRadius(5.0f);
                Inputs[2].Set_PhaseOffset(0.5f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
                    .Set_IdealTarget(Replacement).Set_TargetValid(false).Set_FootContactRadius(5.0f);
            }
        }

        auto
            Tick(
                FCk_Time InStep = FrameDt)
            -> bool
        {
            return Solver.Step(InStep, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        }

        auto
            AdmitTrial()
            -> void
        {
            Inputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{MakeReliefTrial()});
        }
    };

    auto
        HitHalfSpace(
            const FVector& InNormal,
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        const auto StartSide = FVector::DotProduct(InStart, InNormal);
        const auto EndSide = FVector::DotProduct(InEnd, InNormal);
        if (StartSide > 0.0 && EndSide > 0.0)
        { return {}; }
        const auto Fraction = StartSide <= 0.0 ? 0.0 : StartSide / (StartSide - EndSide);
        return ck::FProceduralSurfaceHit{}.Set_Hit(true).Set_Normal(InNormal)
            .Set_Position(FMath::Lerp(InStart, InEnd, Fraction)).Set_Fraction(static_cast<float>(Fraction));
    }

    auto
        FloorRay(
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        return HitHalfSpace(FVector::UpVector, InStart, InEnd);
    }

    auto
        FloorAndWallRay(
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        const auto Floor = FloorRay(InStart, InEnd);
        const auto Wall = HitHalfSpace(FVector::BackwardVector, InStart, InEnd);
        return Wall.Get_Hit() && (NOT Floor.Get_Hit() || Wall.Get_Fraction() < Floor.Get_Fraction()) ? Wall : Floor;
    }

    auto
        SurfaceSettings()
        -> ck::FProceduralSurfaceMotionSettings
    {
        return ck::FProceduralSurfaceMotionSettings{}.Set_Clearance(Clearance).Set_ProbeReach(180.0f)
            .Set_SurfaceTurnRateDegrees(240.0f).Set_ClearanceSpeed(200.0f)
            .Set_Gravity(FVector{0.0, 0.0, -980.0}).Set_WallPolicy(ck::EProceduralSurfaceWallPolicy::Slide);
    }

    auto
        SurfaceState()
        -> ck::FProceduralSurfaceMotionState
    {
        return ck::FProceduralSurfaceMotionState{}.Set_Grounded(true).Set_ContactTrusted(true)
            .Set_SupportNormal(FVector::UpVector).Set_TravelTangent(FVector::ForwardVector);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralPacingReleaseTrialTest,
    "Ck.ProceduralAnimation.PacingRelease.RejectedTrialReportsOnlyBlockingAnchors",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralPacingReleaseTrialTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_pacing_release;
    const auto Settings = SurfaceSettings();
    const auto StartBody = FTransform{FQuat::Identity, FVector{0.0, 0.0, Clearance}};
    const auto HipLocal = FVector{0.0, 0.0, -Clearance};
    const auto NoFeet = TOptional<ck::FProceduralSurfaceFeetSupport>{};
    const auto Anchors = TArray<ck::FProceduralSurfaceReachPaceAnchor>{
        {FVector{-99.0, 0.0, 0.0}, HipLocal, Reach}, {FVector{25.0, 10.0, 0.0}, HipLocal, Reach}};
    auto Body = StartBody;
    auto State = SurfaceState();
    const auto Outcome = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::ForwardVector, 180.0f,
        FrameDt, FloorRay, NoFeet, Anchors, TOptional<FTransform>{}, Body, State);
    if (NOT TestTrue(TEXT("A safe initial stance rejects voluntary movement at the first anchor"),
        Outcome.Get_Scale() < 1.0f && NOT Outcome.Get_PhysicalOverride() && Outcome.Get_AttemptedStanceSpeed() > 0.0f
        && Outcome.Get_RejectedFullBody().IsSet()))
    { return false; }
    TestTrue(TEXT("Only the full-trial offending anchor is identified"),
        Outcome.Get_RejectedAnchorIndices().Num() == 1 && Outcome.Get_RejectedAnchorIndices()[0] == 0);
    const auto Full = Outcome.Get_RejectedFullBody().GetValue();
    TestTrue(TEXT("The recorded full body actually fails only the first ordinary chain bound"),
        FVector::Dist(Full.TransformPosition(HipLocal), Anchors[0].Get_FootWorld()) > Reach + Tolerance
        && FVector::Dist(Full.TransformPosition(HipLocal), Anchors[1].Get_FootWorld()) <= Reach + Tolerance);
    TestTrue(TEXT("The committed body is the checked paced trial, not the rejected full trial"),
        NOT Body.Equals(Full, Tolerance) && State.Get_Grounded()
        && FVector::Dist(Body.TransformPosition(HipLocal), Anchors[0].Get_FootWorld()) <= Reach + Tolerance
        && Outcome.Get_Trials() >= 2 && Outcome.Get_Trials() <= 8);

    const auto PoseOffset = FTransform{FQuat::Identity, FVector{2.0, 0.0, 0.0}};
    const auto PosedAnchors = TArray<ck::FProceduralSurfaceReachPaceAnchor>{
        {FVector{-96.0, 0.0, 0.0}, HipLocal, Reach}, {FVector{25.0, 10.0, 0.0}, HipLocal, Reach}};
    Body = StartBody;
    State = SurfaceState();
    const auto PosedOutcome = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::ForwardVector, 180.0f,
        FrameDt, FloorRay, NoFeet, PosedAnchors, TOptional<FTransform>{PoseOffset}, Body, State);
    if (NOT TestTrue(TEXT("A posed-only chain violation records a rejected trial"),
        PosedOutcome.Get_RejectedFullBody().IsSet() && PosedOutcome.Get_RejectedAnchorIndices().Num() == 1
        && PosedOutcome.Get_RejectedAnchorIndices()[0] == 0))
    { return false; }
    const auto PosedFull = PosedOutcome.Get_RejectedFullBody().GetValue();
    TestTrue(TEXT("The original pose offset independently identifies the posed blocker"),
        FVector::Dist(PosedFull.TransformPosition(HipLocal), PosedAnchors[0].Get_FootWorld()) <= Reach + Tolerance
        && FVector::Dist((PoseOffset * PosedFull).TransformPosition(HipLocal), PosedAnchors[0].Get_FootWorld()) > Reach + Tolerance
        && FVector::Dist((PoseOffset * Body).TransformPosition(HipLocal), PosedAnchors[0].Get_FootWorld()) <= Reach + Tolerance);

    Body = StartBody;
    State = SurfaceState();
    const auto Zero = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::ForwardVector, 180.0f,
        FCk_Time{}, FloorRay, NoFeet, Anchors, TOptional<FTransform>{}, Body, State);
    TestTrue(TEXT("Zero elapsed time publishes no release pressure"),
        NOT Zero.Get_RejectedFullBody().IsSet() && Zero.Get_RejectedAnchorIndices().IsEmpty()
        && Zero.Get_AttemptedStanceSpeed() == 0.0f && Body.Equals(StartBody, Tolerance));

    const auto OverrideAnchors = TArray<ck::FProceduralSurfaceReachPaceAnchor>{{FVector{-99.0, 0.0, 0.0}, HipLocal, 50.0f}};
    Body = StartBody;
    State = SurfaceState();
    const auto Override = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::ForwardVector, 180.0f,
        FrameDt, FloorRay, NoFeet, OverrideAnchors, TOptional<FTransform>{}, Body, State);
    TestTrue(TEXT("An already-invalid physical stance does not grant voluntary reach relief"),
        Override.Get_PhysicalOverride() && NOT Override.Get_RejectedFullBody().IsSet()
        && Override.Get_RejectedAnchorIndices().IsEmpty());

    const auto WallBody = FTransform{FQuat::Identity, FVector{-Clearance, 0.0, Clearance}};
    const auto WallAnchors = TArray<ck::FProceduralSurfaceReachPaceAnchor>{
        {FVector{-Clearance - 99.0, 0.0, 0.0}, HipLocal, Reach}};
    Body = WallBody;
    State = SurfaceState();
    const auto Collision = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::ForwardVector, 180.0f,
        FrameDt, FloorAndWallRay, NoFeet, WallAnchors, TOptional<FTransform>{}, Body, State);
    TestTrue(TEXT("A collision-stopped command supplies no reach-relief trial"),
        State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall && Body.Equals(WallBody, Tolerance)
        && NOT Collision.Get_RejectedFullBody().IsSet() && Collision.Get_RejectedAnchorIndices().IsEmpty()
        && Collision.Get_AttemptedStanceSpeed() == 0.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralPacingReleaseAdmissionTest,
    "Ck.ProceduralAnimation.PacingRelease.ValidatedReliefUsesBudgetedBeyondSchedule",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralPacingReleaseAdmissionTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_pacing_release;
    TestTrue(TEXT("The held plant is currently below force reach but breaks the unpaced trial"),
        HeldPlant.Size() < 0.92 * Reach && FVector::Dist(HeldPlant, TrialHip) > Reach + Tolerance
        && FVector::Dist(Replacement, TrialHip) <= Reach + Tolerance
        && FVector::Dist(Replacement, TrialPosedHip) <= Reach + Tolerance);
    auto Admitted = FReliefCase{};
    if (NOT TestTrue(TEXT("The peer swings first while the other phase stays planted"),
        Admitted.Tick() && Admitted.Solver.GetLegState(0).Get_Swing().Get_Active() && Admitted.Outputs[1].Get_Planted()))
    { return false; }
    TestTrue(TEXT("Absent an authoritative trial the inhibited under-chain plant stays fixed"),
        Admitted.Tick() && Admitted.Outputs[1].Get_Planted()
        && Admitted.Outputs[1].Get_Position().Equals(HeldPlant, Tolerance));
    Admitted.AdmitTrial();
    TestTrue(TEXT("A trusted dual-hip-fit replacement admits a budgeted exceptional swing"),
        Admitted.Tick() && Admitted.Solver.GetLegState(0).Get_Swing().Get_Active()
        && Admitted.Solver.GetLegState(1).Get_Swing().Get_Active()
        && Admitted.Solver.GetLegState(1).Get_Swing().Get_BeyondSchedule()
        && NOT Admitted.Solver.GetLegState(1).Get_Swing().Get_Overshoot()
        && Admitted.Outputs[1].Get_Position().Equals(HeldPlant, Tolerance));
    Admitted.Inputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{});
    auto Landed = false;
    for (auto Frame = 0; Frame < 90; ++Frame)
    {
        if (NOT Admitted.Tick())
        { AddError(TEXT("The admitted relief failed during landing")); return false; }
        if (Admitted.Outputs[1].Get_Planted())
        {
            Landed = true;
            break;
        }
    }
    TestTrue(TEXT("Relief lands exactly on the validated contact and leaves no persistent release"),
        Landed && Admitted.Solver.GetLegState(1).Get_Plant().Get_Trusted()
        && Admitted.Outputs[1].Get_Position().Equals(Replacement, Tolerance)
        && Admitted.Tick() && Admitted.Outputs[1].Get_Planted());

    enum class EGuard : uint8 { NoTarget, UntrustedTarget, UntrustedPlant, SimMiss, PosedMiss, NoViolation, NoBudget, Occupied, Disabled, ZeroTime };
    for (const auto Guard : {EGuard::NoTarget, EGuard::UntrustedTarget, EGuard::UntrustedPlant, EGuard::SimMiss,
        EGuard::PosedMiss, EGuard::NoViolation, EGuard::NoBudget, EGuard::Occupied, EGuard::Disabled, EGuard::ZeroTime})
    {
        auto Case = FReliefCase{Guard == EGuard::NoBudget ? 1 : 2, Guard != EGuard::UntrustedPlant, Guard == EGuard::Occupied};
        if (NOT TestTrue(TEXT("Guard precondition retains the initially inhibited plant"), Case.Tick() && Case.Outputs[1].Get_Planted()))
        { return false; }
        Case.AdmitTrial();
        switch (Guard)
        {
            case EGuard::NoTarget: Case.Inputs[1].Set_TargetValid(false); break;
            case EGuard::UntrustedTarget: Case.Inputs[1].Set_TargetTrusted(false); break;
            case EGuard::SimMiss: Case.Inputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{
                MakeReliefTrial().Set_Hip(FVector{0.0, -60.0, 0.0})}); break;
            case EGuard::PosedMiss: Case.Inputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{
                MakeReliefTrial().Set_PosedHip(TOptional<FVector>{FVector{0.0, -55.0, 0.0}})}); break;
            case EGuard::NoViolation: Case.Inputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{
                ck::FProceduralGaitReachPaceTrial{}.Set_Hip(FVector::ZeroVector)}); break;
            case EGuard::Disabled: Case.Inputs[1].Set_Enabled(false); break;
            default: break;
        }
        const auto Clock = Case.Solver.GetGaitClock();
        TestTrue(FString::Printf(TEXT("Guard %d keeps the existing plant without a release"), static_cast<int32>(Guard)),
            Case.Tick(Guard == EGuard::ZeroTime ? FCk_Time{} : FrameDt)
            && NOT Case.Solver.GetLegState(1).Get_Swing().Get_Active()
            && Case.Solver.GetLegState(1).Get_Plant().Get_Position().Equals(HeldPlant, Tolerance));
        if (Guard == EGuard::ZeroTime)
        { TestTrue(TEXT("Zero-time admission does not advance the gait clock"), Case.Solver.GetGaitClock() == Clock); }
    }

    auto Invalid = FReliefCase{};
    Invalid.Tick();
    const auto Clock = Invalid.Solver.GetGaitClock();
    const auto Plant = Invalid.Solver.GetLegState(1).Get_Plant().Get_Position();
    const auto Output = Invalid.Outputs[1].Get_Position();
    Invalid.Inputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{MakeReliefTrial().Set_Hip(
        FVector{std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0})});
    TestFalse(TEXT("Malformed trial hips reject the whole solve"), Invalid.Tick());
    TestTrue(TEXT("Rejected trial input retains accepted clock, plant and output"),
        Invalid.Solver.GetGaitClock() == Clock && Invalid.Solver.GetLegState(1).Get_Plant().Get_Position().Equals(Plant, Tolerance)
        && Invalid.Outputs[1].Get_Position().Equals(Output, Tolerance));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralPacingReleasePriorityTest,
    "Ck.ProceduralAnimation.PacingRelease.ReliefPriorityAndExceptionalGroupLimit",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralPacingReleasePriorityTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_pacing_release;
    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Step().Set_Threshold(25.0f).Set_Duration(FCk_Time{0.3});
    Solver.Get_Settings().Get_Settle().Set_AtRest(false);
    Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(2);
    const auto OrdinaryPlant = FVector{-60.0, 0.0, -40.0};
    Solver.Reset({OrdinaryPlant, PeerPlant, HeldPlant});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Inputs.SetNum(3);
    Outputs.SetNum(3);
    Inputs[0].Set_PhaseOffset(0.5f).Set_IdealTarget(OrdinaryPlant);
    Inputs[1].Set_PhaseOffset(0.0f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
        .Set_IdealTarget(FVector{30.0, -60.0, -40.0});
    Inputs[2].Set_PhaseOffset(0.75f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach).Set_IdealTarget(Replacement);
    const auto Tick = [&]() { return Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs); };
    if (NOT TestTrue(TEXT("The middle-index ordinary peer starts alone"),
        Tick() && Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted() && Outputs[2].Get_Planted()))
    { return false; }
    Inputs[0].Set_IdealTarget(FVector{60.0, 0.0, -40.0});
    Inputs[2].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{MakeReliefTrial()});
    TestTrue(TEXT("The later limiting leg reserves the free budget slot ahead of an unrelated earlier-index error emergency"),
        Tick() && Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted() && NOT Outputs[2].Get_Planted()
        && Solver.GetLegState(2).Get_Swing().Get_BeyondSchedule());
    Inputs[2].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{});
    Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(3);
    Inputs[0].Set_Hip(FVector::ZeroVector).Set_Reach(Reach).Set_IdealTarget(FVector{-45.0, 0.0, -40.0})
        .Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{
            ck::FProceduralGaitReachPaceTrial{}.Set_Hip(FVector{40.0, 0.0, 0.0})});
    TestTrue(TEXT("Free capacity does not admit a second exceptional phase group"),
        Tick() && Outputs[0].Get_Planted() && Solver.GetLegState(2).Get_Swing().Get_BeyondSchedule());
    Inputs[0].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{});
    Inputs[0].Set_Reach(0.0f).Set_IdealTarget(FVector{60.0, 0.0, -40.0});
    auto OrdinaryResumed = false;
    for (auto Frame = 0; Frame < 90; ++Frame)
    {
        if (NOT Tick())
        { AddError(TEXT("The bounded exceptional schedule failed")); return false; }
        if (NOT Outputs[0].Get_Planted())
        { OrdinaryResumed = true; break; }
    }
    TestTrue(TEXT("The unrelated waiting phase resumes after pressure feedback clears"), OrdinaryResumed);

    // Both legs can ordinarily start in this inactive phase. A high-index limiting leg must be processed before the
    // earlier error emergency consumes the only free slot. Legacy emergency capacity rules are a separate contract.
    auto SamePhase = ck::FProceduralGaitSolver{};
    SamePhase.Get_Settings().Get_Step().Set_Threshold(25.0f).Set_Duration(FCk_Time{0.3});
    SamePhase.Get_Settings().Get_Settle().Set_AtRest(false);
    SamePhase.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(1);
    SamePhase.Reset({OrdinaryPlant, HeldPlant});
    auto SameInputs = TArray<ck::FProceduralGaitLegInput>{};
    auto SameOutputs = TArray<ck::FProceduralGaitLegOutput>{};
    SameInputs.SetNum(2);
    SameOutputs.SetNum(2);
    SameInputs[0].Set_PhaseOffset(0.5f).Set_IdealTarget(FVector{60.0, 0.0, -40.0})
        .Set_TargetValid(true).Set_TargetTrusted(true);
    SameInputs[1].Set_PhaseOffset(0.5f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
        .Set_IdealTarget(Replacement).Set_TargetValid(true).Set_TargetTrusted(true)
        .Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{MakeReliefTrial()});
    TestTrue(TEXT("A high-index inactive-phase limiter receives the sole free slot ahead of its same-phase error emergency"),
        SamePhase.Step(FrameDt, 0.0f, FVector::ZeroVector, SameInputs, SameOutputs)
        && SamePhase.GetLegState(1).Get_Swing().Get_Active()
        && NOT SamePhase.GetLegState(1).Get_Swing().Get_Overshoot());

    // At alpha .8 there is no remaining first-half join deadline. Pressure in that already-active phase may use a
    // budgeted exceptional swing, but must not prolong its scheduled peer's inhibition of the waiting ordinary phase.
    auto Late = ck::FProceduralGaitSolver{};
    Late.Get_Settings().Get_Step().Set_Threshold(25.0f).Set_Duration(FCk_Time{0.3});
    Late.Get_Settings().Get_Settle().Set_AtRest(false);
    Late.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(2);
    Late.Reset({PeerPlant, HeldPlant, OrdinaryPlant});
    auto LateInputs = TArray<ck::FProceduralGaitLegInput>{};
    auto LateOutputs = TArray<ck::FProceduralGaitLegOutput>{};
    LateInputs.SetNum(3);
    LateOutputs.SetNum(3);
    LateInputs[0].Set_PhaseOffset(0.0f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
        .Set_IdealTarget(FVector{30.0, -60.0, -40.0}).Set_TargetValid(true).Set_TargetTrusted(true);
    LateInputs[1].Set_PhaseOffset(0.0f).Set_Hip(FVector::ZeroVector).Set_Reach(Reach)
        .Set_IdealTarget(Replacement).Set_TargetValid(true).Set_TargetTrusted(true);
    LateInputs[2].Set_PhaseOffset(0.5f).Set_IdealTarget(OrdinaryPlant).Set_TargetValid(true).Set_TargetTrusted(true);
    const auto TickLate = [&]() { return Late.Step(FrameDt, 0.0f, FVector::ZeroVector, LateInputs, LateOutputs); };
    if (NOT TestTrue(TEXT("The late-join control begins with one scheduled peer and two held plants"),
        TickLate() && Late.GetLegState(0).Get_Swing().Get_Active()
        && LateOutputs[1].Get_Planted() && LateOutputs[2].Get_Planted()))
    { return false; }
    for (auto Frame = 0; Frame < 18 && Late.GetLegState(0).Get_Swing().Get_Phase() < 0.8f; ++Frame)
    {
        if (NOT TickLate())
        { AddError(TEXT("The late-join control failed before pressure admission")); return false; }
    }
    if (NOT TestTrue(TEXT("The original scheduled peer is still active past alpha .8 before the relief trial"),
        Late.GetLegState(0).Get_Swing().Get_Active() && Late.GetLegState(0).Get_Swing().Get_Phase() >= 0.8f
        && NOT Late.GetLegState(0).Get_Swing().Get_BeyondSchedule() && LateOutputs[1].Get_Planted()))
    { return false; }
    LateInputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{MakeReliefTrial()});
    LateInputs[2].Set_IdealTarget(FVector{60.0, 0.0, -40.0});
    TestTrue(TEXT("Late same-phase relief is exceptional and leaves the unrelated waiting emergency planted"),
        TickLate() && Late.GetLegState(0).Get_Swing().Get_Active()
        && Late.GetLegState(1).Get_Swing().Get_Active() && Late.GetLegState(1).Get_Swing().Get_BeyondSchedule()
        && LateOutputs[2].Get_Planted());
    LateInputs[1].Set_ReachPaceTrial(TOptional<ck::FProceduralGaitReachPaceTrial>{});
    auto WaitingResumedBeforeReliefLanded = false;
    for (auto Frame = 0; Frame < 12; ++Frame)
    {
        if (NOT TickLate())
        { AddError(TEXT("The late relief failed while the scheduled deadline expired")); return false; }
        if (Late.GetLegState(2).Get_Swing().Get_Active())
        {
            WaitingResumedBeforeReliefLanded = NOT Late.GetLegState(0).Get_Swing().Get_Active()
                && Late.GetLegState(1).Get_Swing().Get_Active() && Late.GetLegState(1).Get_Swing().Get_BeyondSchedule();
            break;
        }
    }
    TestTrue(TEXT("The waiting phase resumes after the original peer lands, while late relief remains exceptional"),
        WaitingResumedBeforeReliefLanded);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
