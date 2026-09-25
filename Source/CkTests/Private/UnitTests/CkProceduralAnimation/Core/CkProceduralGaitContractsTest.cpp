#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"
#include "CkProceduralAnimation/Core/CkProceduralFootProbe.h"
#include "Misc/AutomationTest.h"
#include <limits>

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_procedural_gait_contracts_test
{
    constexpr auto Flags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr FCk_Time DeltaTime{1.0 / 60.0};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitRejectsInvalidInput,
    "Ck.ProceduralAnimation.Gait.InvalidInputIsAtomic", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralGaitRejectsInvalidInput::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    TArray<FVector> Plants = {FVector{10.0, 20.0, 30.0}};
    TestTrue(TEXT("Valid reset"), Solver.Reset(Plants));
    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    Inputs[0].Set_IdealTarget(Plants[0]);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);
    Outputs[0].Set_Position(FVector{777.0, 888.0, 999.0});
    const auto OutputBefore = Outputs[0].Get_Position();
    const auto NaN = std::numeric_limits<float>::quiet_NaN();
    const auto AssertUnchanged = [this, &Solver, &Plants, &Outputs, &OutputBefore]()
    {
        TestEqual(TEXT("Topology unchanged"), Solver.NumLegs(), 1);
        TestTrue(TEXT("Plant unchanged"), Solver.GetLegState(0).Get_PlantedPosition().Equals(Plants[0]));
        TestEqual(TEXT("Clock unchanged"), Solver.GetGaitClock(), 0.0f);
        TestTrue(TEXT("Output unchanged"), Outputs[0].Get_Position().Equals(OutputBefore));
    };
    const auto SettingsBefore = Solver.Get_Settings();
    Solver.Get_Settings().Set_StepDuration(FCk_Time{});
    TestFalse(TEXT("Reject zero step duration"), Solver.Step(ck_procedural_gait_contracts_test::DeltaTime,
        100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Solver.Set_Settings(SettingsBefore);
    Inputs[0].Set_IdealTarget(FVector{NaN, 0.0, 0.0});
    TestFalse(TEXT("Reject nonfinite target"), Solver.Step(ck_procedural_gait_contracts_test::DeltaTime,
        100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs[0].Set_IdealTarget(Plants[0]);
    TestFalse(TEXT("Reject nonfinite delta"), Solver.Step(FCk_Time{NaN}, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs.AddDefaulted();
    TestFalse(TEXT("Reject topology changes without reset"), Solver.Step(ck_procedural_gait_contracts_test::DeltaTime,
        100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    TArray<FVector> InvalidPlants = {FVector{0.0, 0.0, 0.0}, FVector{NaN, 0.0, 0.0}};
    TestFalse(TEXT("Reject reset atomically"), Solver.Reset(InvalidPlants));
    AssertUnchanged();
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitPreviewPreservesState,
    "Ck.ProceduralAnimation.Gait.PreviewDoesNotInitializePatternState", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralGaitPreviewPreservesState::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    TArray<FVector> Plants = {FVector{}};
    Solver.Reset(Plants);
    Solver.Get_Settings().Get_Patterns().Add(ck::FProceduralGaitPattern{}.Set_MinSpeed(0.0f));
    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);
    TestTrue(TEXT("Accept preview"), Solver.Step(FCk_Time{}, 100.0f, FVector{}, Inputs, Outputs));
    TestEqual(TEXT("Preview preserves uninitialized pattern state"), Solver.GetCurrentPatternIndex(), INDEX_NONE);
    TestEqual(TEXT("Preview preserves gait clock"), Solver.GetGaitClock(), 0.0f);
    TestTrue(TEXT("Preview preserves rest time"), Solver.GetRestTime() == FCk_Time{});
    TestTrue(TEXT("Preview emits plant"), Outputs[0].Get_Planted());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralContactGraceUsesElapsedTime,
    "Ck.ProceduralAnimation.Gait.ContactGraceIsTimestepIndependent", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralContactGraceUsesElapsedTime::RunTest(const FString& InParameters) -> bool
{
    constexpr FCk_Time Grace{0.125};
    for (const auto Substeps : {1, 2, 4, 8, 16})
    {
        ck::FProceduralFootProbeState Probe;
        const auto Delta = Grace / Substeps;
        for (auto Index = 0; Index < Substeps; ++Index)
        {
            TestTrue(TEXT("Accept valid probe sample"), Probe.Advance(false, Delta, Grace));
            const auto Expected = Index == Substeps - 1
                ? ck::EProceduralFootProbeState::Lost : ck::EProceduralFootProbeState::Guessing;
            TestTrue(TEXT("Grace state depends on elapsed time"), Probe.Get_State() == Expected);
        }
        TestTrue(TEXT("Saturated missing duration"), Probe.Get_MissingDuration() == Grace);
        TestTrue(TEXT("Paused sample accepted"), Probe.Advance(true, FCk_Time{}, Grace));
        TestTrue(TEXT("Pause preserves contact state"), Probe.Get_State() == ck::EProceduralFootProbeState::Lost);
        TestFalse(TEXT("Reject negative grace"), Probe.Advance(true, Delta, FCk_Time{-1.0}));
        TestTrue(TEXT("Invalid duration preserves contact state"), Probe.Get_State() == ck::EProceduralFootProbeState::Lost);
        TestTrue(TEXT("Accept recovery"), Probe.Advance(true, Delta, Grace));
        TestTrue(TEXT("Recovery clears missing duration"), Probe.Get_MissingDuration() == FCk_Time{});
        TestTrue(TEXT("Recovery restores grounded"), Probe.Get_State() == ck::EProceduralFootProbeState::Grounded);
    }
    ck::FProceduralFootProbeState Immediate;
    Immediate.Advance(false, ck_procedural_gait_contracts_test::DeltaTime, FCk_Time{});
    TestTrue(TEXT("Zero grace loses contact immediately"), Immediate.Get_State() == ck::EProceduralFootProbeState::Lost);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralProbeSpansAreBounded,
    "Ck.ProceduralAnimation.Gait.ProbeRetriesAreBoundedAndDropConvexLean", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralProbeSpansAreBounded::RunTest(const FString& InParameters) -> bool
{
    const auto Authored = ck::MakeProceduralGroundProbeSpan(0, 50.0f, 100.0f, 0.6f);
    const auto Retry = ck::MakeProceduralGroundProbeSpan(1, 50.0f, 100.0f, 0.6f);
    const auto Last = ck::MakeProceduralGroundProbeSpan(2, 50.0f, 100.0f, 0.6f);
    const auto Excess = ck::MakeProceduralGroundProbeSpan(MAX_int32, 50.0f, 100.0f, 0.6f);
    TestEqual(TEXT("Authored span preserved"), Authored.Get_UpDistance(), 50.0f);
    TestEqual(TEXT("Authored lean preserved"), Authored.Get_OutwardLean(), 0.6f);
    TestEqual(TEXT("First retry backs out of buried start"), Retry.Get_UpDistance(), 200.0f);
    TestEqual(TEXT("Retry drops convex lean for concave surfaces"), Retry.Get_OutwardLean(), 0.0f);
    TestEqual(TEXT("Last retry reach"), Last.Get_DownDistance(), 250.0f);
    TestEqual(TEXT("Extra attempts cannot grow ray"), Excess.Get_UpDistance(), Last.Get_UpDistance());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralSupportFramePreservesWorldPlants,
    "Ck.ProceduralAnimation.Gait.SupportFrameReexpressionPreservesWorldPlantsAndRequests", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralSupportFramePreservesWorldPlants::RunTest(const FString& InParameters) -> bool
{
    const auto OldBasis = FQuat{FVector::ForwardVector, 0.3};
    const auto NewBasis = FQuat{FVector::RightVector, 1.1};
    const auto WorldPlant = FVector{2700.0, -1400.0, 625.0};
    const auto WorldRequest = FVector{2800.0, -1300.0, 615.0};
    ck::FProceduralGaitSolver Solver;
    TArray<FVector> Plants = {OldBasis.UnrotateVector(WorldPlant)};
    Solver.Reset(Plants);
    TestTrue(TEXT("Accept pending catch step"), Solver.RequestStep(0, OldBasis.UnrotateVector(WorldRequest)));
    const auto PendingBefore = Solver.GetLegState(0).Get_PendingStepTime();
    Solver.TransformState(NewBasis.Inverse() * OldBasis);
    const auto& State = Solver.GetLegState(0);
    TestTrue(TEXT("World plant welded through basis change"),
        NewBasis.RotateVector(State.Get_PlantedPosition()).Equals(WorldPlant, 0.001));
    TestTrue(TEXT("Requested world landing survives basis change"),
        NewBasis.RotateVector(State.Get_PendingStepTarget()).Equals(WorldRequest, 0.001));
    TestTrue(TEXT("Basis change does not age request"), State.Get_PendingStepTime() == PendingBefore);
    TestEqual(TEXT("Basis change does not advance clock"), Solver.GetGaitClock(), 0.0f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralSwingProfileRejectsNonfiniteSamples,
    "Ck.ProceduralAnimation.Gait.SwingProfileRejectsNonfiniteSamplesAtomically", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralSwingProfileRejectsNonfiniteSamples::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSwingProfile Profile;
    TestTrue(TEXT("Accept initial curve"), Profile.SetEase([](float InPhase) { return InPhase * 2.0f; }));
    TestFalse(TEXT("Reject curve with nonfinite sample"), Profile.SetEase([](float InPhase)
    { return InPhase > 0.5f ? std::numeric_limits<float>::quiet_NaN() : InPhase; }));
    TestEqual(TEXT("Earlier samples were not partially overwritten"), Profile.SampleEase(0.25f), 0.5f);
    TestEqual(TEXT("Later samples remain from accepted curve"), Profile.SampleEase(1.0f), 2.0f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralFootOrientationHandlesParallelAxes,
    "Ck.ProceduralAnimation.Gait.FootOrientationHandlesParallelFacingAndNormal", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralFootOrientationHandlesParallelAxes::RunTest(const FString& InParameters) -> bool
{
    for (const auto Normal : {FVector::ForwardVector, FVector::RightVector, FVector::UpVector})
    {
        const auto Rotation = ck::FProceduralGaitSolver::MakeFootRotation(Normal, Normal);
        TestTrue(TEXT("Parallel inputs yield finite normalized frame"), NOT Rotation.ContainsNaN() && Rotation.IsNormalized());
        TestTrue(TEXT("Foot up agrees with support normal"), Rotation.GetAxisZ().Equals(Normal, 0.0001));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitRejectsInvalidSettingRanges,
    "Ck.ProceduralAnimation.Gait.SettingRangesRejectWithoutMutation", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralGaitRejectsInvalidSettingRanges::RunTest(const FString& InParameters) -> bool
{
    using SettingsType = ck::FProceduralGaitSettings;
    const TArray<SettingsType> InvalidSettings =
    {
        SettingsType{}.Set_RetargetSmoothing(-1.0f),
        SettingsType{}.Set_AirborneFollowSpeed(-1.0f),
        SettingsType{}.Set_EmergencyStepFactor(0.5f),
        SettingsType{}.Set_RetargetFreezePhase(1.1f),
        SettingsType{}.Set_SwingApexPhase(-0.1f),
        SettingsType{}.Set_SwingApexSharpness(0.0f),
        SettingsType{}.Set_ScheduleAdvanceFraction(1.1f),
        SettingsType{}.Set_SettleThresholdFraction(0.0f),
        SettingsType{}.Set_LandingStepDurationScale(1.1f),
        SettingsType{}.Set_PatternSwitchHysteresis(0.0f),
        SettingsType{}.Set_ObstacleClearance(-1.0f),
        SettingsType{}.Set_MaxStrokeOvershoot(-1.0f),
    };
    ck::FProceduralGaitSolver Solver;
    TArray<FVector> Plants = {FVector{}};
    Solver.Reset(Plants);
    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);
    Outputs[0].Set_Position(FVector{123.0, 456.0, 789.0});
    const auto Before = Outputs[0].Get_Position();
    for (const auto& Settings : InvalidSettings)
    {
        TestFalse(TEXT("Reject invalid rate or normalized phase range"), Solver.ValidateSettings(Settings));
        Solver.Set_Settings(Settings);
        TestFalse(TEXT("Invalid settings reject simulation"), Solver.Step(ck_procedural_gait_contracts_test::DeltaTime,
            100.0f, FVector{}, Inputs, Outputs));
        TestEqual(TEXT("Rejected settings do not advance clock"), Solver.GetGaitClock(), 0.0f);
        TestTrue(TEXT("Rejected settings do not alter output"), Outputs[0].Get_Position().Equals(Before));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralSwingProfileRejectsNonfinitePhase,
    "Ck.ProceduralAnimation.Gait.NonfiniteSwingPhaseDoesNotIndexSamples", ck_procedural_gait_contracts_test::Flags)

auto FCkProceduralSwingProfileRejectsNonfinitePhase::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSwingProfile Profile;
    Profile.SetEase([](float InPhase) { return InPhase; });
    Profile.SetArc([](float InPhase) { return InPhase * (1.0f - InPhase); });
    for (const auto Phase : {std::numeric_limits<float>::quiet_NaN(), std::numeric_limits<float>::infinity()})
    {
        TestFalse(TEXT("Nonfinite ease phase remains visibly invalid"), FMath::IsFinite(Profile.SampleEase(Phase)));
        TestFalse(TEXT("Nonfinite arc phase remains visibly invalid"), FMath::IsFinite(Profile.SampleArc(Phase)));
    }
    TestEqual(TEXT("Malformed queries do not alter authored samples"), Profile.SampleEase(0.5f), 0.5f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitSupportLossPreservesSwingPose,
    "Ck.ProceduralAnimation.Gait.MidSwingSupportLossPreservesRenderedPose", ck_procedural_gait_contracts_test::Flags)

auto
    FCkProceduralGaitSupportLossPreservesSwingPose::
    RunTest(const FString& InParameters)
    -> bool
{
    ck::FProceduralGaitSolver Solver;
    Solver.Get_Settings().Set_StepDuration(FCk_Time{1.0}).Set_CycleDuration(FCk_Time{1.0})
        .Set_StepHeight(40.0f).Set_ObstacleClearance(10.0f).Set_StrokeOvershootFraction(0.25f)
        .Set_MaxStrokeOvershoot(25.0f).Set_RetargetFreezePhase(0.0f).Set_SwingToePitchDegrees(30.0f);
    TArray<FVector> Plants = {FVector{}};
    TestTrue(TEXT("Initialize one leg"), Solver.Reset(Plants));
    TArray<ck::FProceduralGaitLegInput> Inputs;
    Inputs.SetNum(1);
    Inputs[0].Set_IdealTarget(FVector{100.0, 0.0, 0.0}).Set_FacingDirection(FVector::RightVector)
        .Set_ClearanceGroundZ(70.0f);
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Outputs.SetNum(1);
    TestTrue(TEXT("Trigger swing"), Solver.Step(FCk_Time{0.01}, 0.0f, FVector{}, Inputs, Outputs));
    TestTrue(TEXT("Advance to swing apex"), Solver.Step(FCk_Time{0.5}, 0.0f, FVector{}, Inputs, Outputs));
    const auto Before = Outputs[0];
    TestFalse(TEXT("Support is lost during a real swing"), Before.Get_Planted());
    TestTrue(TEXT("Before pose includes the arc and obstacle clearance"), Before.Get_Position().Z > 70.0);
    TestTrue(TEXT("Before pose includes stroke overshoot"), Before.Get_Position().X > 60.0);
    TestTrue(TEXT("Before pose includes swing rotation"), Before.Get_Rotation().AngularDistance(FQuat::Identity) > 0.1);

    auto ReframedSolver = Solver;
    constexpr auto Airborne = true;
    TestTrue(TEXT("Advance into airborne with negligible elapsed time"),
        Solver.Step(FCk_Time{0.000001}, 0.0f, FVector{}, Inputs, Outputs, Airborne));
    TestTrue(TEXT("Losing support starts from the actual rendered foot position"),
        Outputs[0].Get_Position().Equals(Before.Get_Position(), 0.01));
    TestTrue(TEXT("Losing support starts from the actual rendered foot rotation"),
        Outputs[0].Get_Rotation().AngularDistance(Before.Get_Rotation()) < 0.001);

    const auto BasisChange = FQuat{FVector::RightVector, 0.65};
    ReframedSolver.TransformState(BasisChange);
    Inputs[0].Set_IdealTarget(BasisChange.RotateVector(Inputs[0].Get_IdealTarget()))
        .Set_GroundNormal(BasisChange.RotateVector(FVector::UpVector))
        .Set_FacingDirection(BasisChange.RotateVector(FVector::RightVector));
    TestTrue(TEXT("Support-frame change accepts subsequent airborne transition"),
        ReframedSolver.Step(FCk_Time{0.000001}, 0.0f, FVector{}, Inputs, Outputs, Airborne));
    TestTrue(TEXT("Rendered position survives support-frame change before takeoff"),
        Outputs[0].Get_Position().Equals(BasisChange.RotateVector(Before.Get_Position()), 0.01));
    TestTrue(TEXT("Rendered rotation survives support-frame change before takeoff"),
        Outputs[0].Get_Rotation().AngularDistance(BasisChange * Before.Get_Rotation()) < 0.001);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralVelocityNegativeDeltaPreservesHistory,
    "Ck.ProceduralAnimation.Gait.NegativeDeltaPreservesVelocityHistory", ck_procedural_gait_contracts_test::Flags)

auto
    FCkProceduralVelocityNegativeDeltaPreservesHistory::
    RunTest(const FString& InParameters)
    -> bool
{
    ck::FProceduralGaitVelocityTracker Tracker;
    TestTrue(TEXT("Initialize position history"), Tracker.Update(FVector{}, FCk_Time{1.0}).IsNearlyZero());
    TestTrue(TEXT("Negative delta leaves velocity estimate unchanged"),
        Tracker.Update(FVector{100.0, 0.0, 0.0}, FCk_Time{-1.0}).IsNearlyZero());
    const auto Velocity = Tracker.Update(FVector{10.0, 0.0, 0.0}, FCk_Time{1.0});
    TestTrue(TEXT("Next sample measures from the last accepted position"),
        Velocity.Equals(FVector{10.0, 0.0, 0.0}, 0.0001));
    return true;
}
#endif
