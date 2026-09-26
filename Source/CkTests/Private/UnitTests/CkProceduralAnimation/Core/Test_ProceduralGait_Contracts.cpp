#include "CkProceduralAnimation/Core/CkProceduralFootProbe.h"
#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_contracts
{
    constexpr auto DeltaTime = FCk_Time{1.0 / 60.0};
    constexpr auto NaN = std::numeric_limits<float>::quiet_NaN();
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitRejectsInvalidInput,
    "Ck.ProceduralAnimation.Gait.InvalidInputIsAtomic",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitRejectsInvalidInput::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_contracts;

    auto Solver = ck::FProceduralGaitSolver{};
    const auto Plants = TArray<FVector>{FVector{10.0, 20.0, 30.0}};
    TestTrue(TEXT("Valid reset"), Solver.Reset(Plants));
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    Inputs[0].Set_IdealTarget(Plants[0]);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);
    Outputs[0].Set_Position(FVector{777.0, 888.0, 999.0});
    const auto OutputBefore = Outputs[0].Get_Position();
    const auto AssertUnchanged = [this, &Solver, &Plants, &Outputs, &OutputBefore]() -> void
    {
        TestEqual(TEXT("Topology unchanged"), Solver.NumLegs(), 1);
        TestTrue(TEXT("Plant unchanged"), Solver.GetLegState(0).Get_Plant().Get_Position().Equals(Plants[0]));
        TestEqual(TEXT("Clock unchanged"), Solver.GetGaitClock(), 0.0f);
        TestTrue(TEXT("Output unchanged"), Outputs[0].Get_Position().Equals(OutputBefore));
    };
    const auto SettingsBefore = Solver.Get_Settings();
    Solver.Get_Settings().Get_Step().Set_Duration(FCk_Time{});
    TestFalse(TEXT("Reject zero step duration"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Solver.Set_Settings(SettingsBefore);
    Inputs[0].Set_IdealTarget(FVector{NaN, 0.0, 0.0});
    TestFalse(TEXT("Reject nonfinite target"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs[0].Set_IdealTarget(Plants[0]);
    Inputs[0].Set_Hip(FVector{NaN, 0.0, 0.0});
    TestFalse(TEXT("Reject nonfinite hip"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs[0].Set_Hip(FVector::ZeroVector);
    Inputs[0].Set_Reach(-1.0f);
    TestFalse(TEXT("Reject negative reach"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs[0].Set_Reach(NaN);
    TestFalse(TEXT("Reject nonfinite reach"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs[0].Set_Reach(0.0f);
    TestFalse(TEXT("Reject nonfinite delta"), Solver.Step(FCk_Time{NaN}, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    Inputs.AddDefaulted();
    TestFalse(TEXT("Reject topology changes without reset"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    AssertUnchanged();
    const auto InvalidPlants = TArray<FVector>{FVector{0.0, 0.0, 0.0}, FVector{NaN, 0.0, 0.0}};
    TestFalse(TEXT("Reject reset atomically"), Solver.Reset(InvalidPlants));
    AssertUnchanged();

    constexpr auto Disabled = false;
    Inputs.SetNum(1);
    Inputs[0].Set_Enabled(Disabled);
    TestTrue(TEXT("Accept a step that disables the leg"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
    TestFalse(TEXT("The stepped leg reads disabled"), Solver.IsLegEnabled(0));
    TestFalse(TEXT("Reject reset atomically while a leg is disabled"), Solver.Reset(InvalidPlants));
    TestFalse(TEXT("A rejected reset leaves the leg disabled"), Solver.IsLegEnabled(0));
    TestTrue(TEXT("Accept reset"), Solver.Reset(Plants));
    TestTrue(TEXT("Reset re-enables a previously disabled leg"), Solver.IsLegEnabled(0));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPreviewPreservesState,
    "Ck.ProceduralAnimation.Gait.PreviewDoesNotInitializePatternState",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPreviewPreservesState::
    RunTest(const FString&)
    -> bool
{
    auto Solver = ck::FProceduralGaitSolver{};
    const auto Plants = TArray<FVector>{FVector{}};
    Solver.Reset(Plants);
    Solver.Get_Settings().Get_Pattern().Set_Patterns({ck::FProceduralGaitPattern{}.Set_MinSpeed(0.0f)});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);
    TestTrue(TEXT("Accept preview"), Solver.Step(FCk_Time{}, 100.0f, FVector{}, Inputs, Outputs));
    TestEqual(TEXT("Preview preserves uninitialized pattern state"), Solver.GetCurrentPatternIndex(), INDEX_NONE);
    TestEqual(TEXT("Preview preserves gait clock"), Solver.GetGaitClock(), 0.0f);
    TestTrue(TEXT("Preview preserves rest time"), Solver.GetRestTime() == FCk_Time{});
    TestTrue(TEXT("Preview emits plant"), Outputs[0].Get_Planted());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralContactGraceUsesElapsedTime,
    "Ck.ProceduralAnimation.Gait.ContactGraceIsTimestepIndependent",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralContactGraceUsesElapsedTime::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_contracts;

    constexpr auto Grace = FCk_Time{0.125};
    constexpr auto Hit = true;
    constexpr auto Miss = false;
    for (const auto Substeps : {1, 2, 4, 8, 16})
    {
        auto Probe = ck::FProceduralFootProbeState{};
        const auto Delta = Grace / Substeps;
        for (auto Index = 0; Index < Substeps; ++Index)
        {
            TestTrue(TEXT("Accept valid probe sample"), Probe.Advance(Miss, Delta, Grace));
            const auto Expected = Index == Substeps - 1
                ? ck::EProceduralFootProbeState::Lost : ck::EProceduralFootProbeState::Guessing;
            TestTrue(TEXT("Grace state depends on elapsed time"), Probe.Get_State() == Expected);
        }
        TestTrue(TEXT("Saturated missing duration"), Probe.Get_MissingDuration() == Grace);
        TestTrue(TEXT("Paused sample accepted"), Probe.Advance(Hit, FCk_Time{}, Grace));
        TestTrue(TEXT("Pause preserves contact state"), Probe.Get_State() == ck::EProceduralFootProbeState::Lost);
        TestFalse(TEXT("Reject negative grace"), Probe.Advance(Hit, Delta, FCk_Time{-1.0}));
        TestTrue(TEXT("Invalid duration preserves contact state"), Probe.Get_State() == ck::EProceduralFootProbeState::Lost);
        TestTrue(TEXT("Accept recovery"), Probe.Advance(Hit, Delta, Grace));
        TestTrue(TEXT("Recovery clears missing duration"), Probe.Get_MissingDuration() == FCk_Time{});
        TestTrue(TEXT("Recovery restores grounded"), Probe.Get_State() == ck::EProceduralFootProbeState::Grounded);
    }
    auto Immediate = ck::FProceduralFootProbeState{};
    Immediate.Advance(Miss, DeltaTime, FCk_Time{});
    TestTrue(TEXT("Zero grace loses contact immediately"), Immediate.Get_State() == ck::EProceduralFootProbeState::Lost);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralProbeSpansAreBounded,
    "Ck.ProceduralAnimation.Gait.ProbeRetriesAreBoundedAndDropConvexLean",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralProbeSpansAreBounded::
    RunTest(const FString&)
    -> bool
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

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSupportFramePreservesWorldPlants,
    "Ck.ProceduralAnimation.Gait.SupportFrameReexpressionPreservesWorldPlantsAndRequests",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSupportFramePreservesWorldPlants::
    RunTest(const FString&)
    -> bool
{
    const auto OldBasis = FQuat{FVector::ForwardVector, 0.3};
    const auto NewBasis = FQuat{FVector::RightVector, 1.1};
    const auto WorldPlant = FVector{2700.0, -1400.0, 625.0};
    const auto WorldRequest = FVector{2800.0, -1300.0, 615.0};
    auto Solver = ck::FProceduralGaitSolver{};
    const auto Plants = TArray<FVector>{OldBasis.UnrotateVector(WorldPlant)};
    Solver.Reset(Plants);
    TestTrue(TEXT("Accept pending catch step"), Solver.RequestStep(0, OldBasis.UnrotateVector(WorldRequest)));
    const auto PendingBefore = Solver.GetLegState(0).Get_PendingStep().Get_Time();
    Solver.TransformState(NewBasis.Inverse() * OldBasis);
    const auto& State = Solver.GetLegState(0);
    TestTrue(TEXT("World plant welded through basis change"),
        NewBasis.RotateVector(State.Get_Plant().Get_Position()).Equals(WorldPlant, 0.001));
    TestTrue(TEXT("Requested world landing survives basis change"),
        NewBasis.RotateVector(State.Get_PendingStep().Get_Target()).Equals(WorldRequest, 0.001));
    TestTrue(TEXT("Basis change does not age request"), State.Get_PendingStep().Get_Time() == PendingBefore);
    TestEqual(TEXT("Basis change does not advance clock"), Solver.GetGaitClock(), 0.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSwingProfileRejectsNonfiniteSamples,
    "Ck.ProceduralAnimation.Gait.SwingProfileRejectsNonfiniteSamplesAtomically",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSwingProfileRejectsNonfiniteSamples::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_contracts;

    auto Profile = ck::FProceduralGaitSwingProfile{};
    TestTrue(TEXT("Accept initial curve"), Profile.SetEase([](float InPhase) -> float { return InPhase * 2.0f; }));
    TestFalse(TEXT("Reject curve with nonfinite sample"), Profile.SetEase([](float InPhase) -> float
    {
        return InPhase > 0.5f ? NaN : InPhase;
    }));
    TestEqual(TEXT("Earlier samples were not partially overwritten"), Profile.SampleEase(0.25f), 0.5f);
    TestEqual(TEXT("Later samples remain from accepted curve"), Profile.SampleEase(1.0f), 2.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootOrientationHandlesParallelAxes,
    "Ck.ProceduralAnimation.Gait.FootOrientationHandlesParallelFacingAndNormal",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootOrientationHandlesParallelAxes::
    RunTest(const FString&)
    -> bool
{
    for (const auto Normal : {FVector::ForwardVector, FVector::RightVector, FVector::UpVector})
    {
        const auto Rotation = ck::FProceduralGaitSolver::MakeFootRotation(Normal, Normal);
        TestTrue(TEXT("Parallel inputs yield finite normalized frame"), NOT Rotation.ContainsNaN() && Rotation.IsNormalized());
        TestTrue(TEXT("Foot up agrees with support normal"), Rotation.GetAxisZ().Equals(Normal, 0.0001));
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitRejectsInvalidSettingRanges,
    "Ck.ProceduralAnimation.Gait.SettingRangesRejectWithoutMutation",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitRejectsInvalidSettingRanges::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_contracts;

    using SettingsType = ck::FProceduralGaitSettings;
    const auto InvalidSettings = TArray<SettingsType>
    {
        SettingsType{}.Set_Step(ck::FProceduralGaitStepSettings{}.Set_RetargetSmoothing(-1.0f)),
        SettingsType{}.Set_Airborne(ck::FProceduralGaitAirborneSettings{}.Set_FollowSpeed(-1.0f)),
        SettingsType{}.Set_Step(ck::FProceduralGaitStepSettings{}.Set_EmergencyFactor(0.5f)),
        SettingsType{}.Set_Step(ck::FProceduralGaitStepSettings{}.Set_RetargetFreezePhase(1.1f)),
        SettingsType{}.Set_Swing(ck::FProceduralGaitSwingSettings{}.Set_ApexPhase(-0.1f)),
        SettingsType{}.Set_Swing(ck::FProceduralGaitSwingSettings{}.Set_ApexSharpness(0.0f)),
        SettingsType{}.Set_Schedule(ck::FProceduralGaitScheduleSettings{}.Set_AdvanceFraction(1.1f)),
        SettingsType{}.Set_Settle(ck::FProceduralGaitSettleSettings{}.Set_ThresholdFraction(0.0f)),
        SettingsType{}.Set_Airborne(ck::FProceduralGaitAirborneSettings{}.Set_LandingStepDurationScale(1.1f)),
        SettingsType{}.Set_Pattern(ck::FProceduralGaitPatternSettings{}.Set_SwitchHysteresis(0.0f)),
        SettingsType{}.Set_Swing(ck::FProceduralGaitSwingSettings{}.Set_ObstacleClearance(-1.0f)),
        SettingsType{}.Set_Step(ck::FProceduralGaitStepSettings{}.Set_MaxStrokeOvershoot(-1.0f)),
        SettingsType{}.Set_Reach(ck::FProceduralGaitReachSettings{}.Set_TargetFraction(0.0f)),
        SettingsType{}.Set_Reach(ck::FProceduralGaitReachSettings{}.Set_TargetFraction(0.95f)),
        SettingsType{}.Set_Reach(ck::FProceduralGaitReachSettings{}.Set_ForceStepFraction(1.1f)),
        SettingsType{}.Set_Reach(ck::FProceduralGaitReachSettings{}.Set_HardOverstretchFraction(0.99f)),
        SettingsType{}.Set_Reach(ck::FProceduralGaitReachSettings{}.Set_HardOverstretchFraction(1.51f)),
        SettingsType{}.Set_Reach(ck::FProceduralGaitReachSettings{}.Set_ForceStepFraction(1.0f).Set_HardOverstretchFraction(1.0f)),
    };
    auto Solver = ck::FProceduralGaitSolver{};
    const auto Plants = TArray<FVector>{FVector{}};
    Solver.Reset(Plants);
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);
    Outputs[0].Set_Position(FVector{123.0, 456.0, 789.0});
    const auto Before = Outputs[0].Get_Position();
    for (const auto& Settings : InvalidSettings)
    {
        TestFalse(TEXT("Reject invalid rate or normalized phase range"), Solver.ValidateSettings(Settings));
        Solver.Set_Settings(Settings);
        TestFalse(TEXT("Invalid settings reject simulation"), Solver.Step(DeltaTime, 100.0f, FVector{}, Inputs, Outputs));
        TestEqual(TEXT("Rejected settings do not advance clock"), Solver.GetGaitClock(), 0.0f);
        TestTrue(TEXT("Rejected settings do not alter output"), Outputs[0].Get_Position().Equals(Before));
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSwingProfileRejectsNonfinitePhase,
    "Ck.ProceduralAnimation.Gait.NonfiniteSwingPhaseDoesNotIndexSamples",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSwingProfileRejectsNonfinitePhase::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_contracts;

    auto Profile = ck::FProceduralGaitSwingProfile{};
    Profile.SetEase([](float InPhase) -> float { return InPhase; });
    Profile.SetArc([](float InPhase) -> float { return InPhase * (1.0f - InPhase); });
    for (const auto Phase : {NaN, std::numeric_limits<float>::infinity()})
    {
        TestFalse(TEXT("Nonfinite ease phase remains visibly invalid"), FMath::IsFinite(Profile.SampleEase(Phase)));
        TestFalse(TEXT("Nonfinite arc phase remains visibly invalid"), FMath::IsFinite(Profile.SampleArc(Phase)));
    }
    TestEqual(TEXT("Malformed queries do not alter authored samples"), Profile.SampleEase(0.5f), 0.5f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSupportLossPreservesSwingPose,
    "Ck.ProceduralAnimation.Gait.MidSwingSupportLossPreservesRenderedPose",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSupportLossPreservesSwingPose::
    RunTest(const FString&)
    -> bool
{
    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Step().Set_Duration(FCk_Time{1.0}).Set_StrokeOvershootFraction(0.25f)
        .Set_MaxStrokeOvershoot(25.0f).Set_RetargetFreezePhase(0.0f);
    Solver.Get_Settings().Get_Cadence().Set_CycleDuration(FCk_Time{1.0});
    Solver.Get_Settings().Get_Swing().Set_Height(40.0f).Set_ObstacleClearance(10.0f).Set_ToePitchDegrees(30.0f);
    const auto Plants = TArray<FVector>{FVector{}};
    TestTrue(TEXT("Initialize one leg"), Solver.Reset(Plants));
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    Inputs[0].Set_IdealTarget(FVector{100.0, 0.0, 0.0}).Set_FacingDirection(FVector::RightVector)
        .Set_ClearanceGroundZ(70.0f);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
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

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralVelocityNegativeDeltaPreservesHistory,
    "Ck.ProceduralAnimation.Gait.NegativeDeltaPreservesVelocityHistory",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralVelocityNegativeDeltaPreservesHistory::
    RunTest(const FString&)
    -> bool
{
    auto Tracker = ck::FProceduralGaitVelocityTracker{};
    TestTrue(TEXT("Initialize position history"), Tracker.Update(FVector{}, FCk_Time{1.0}).IsNearlyZero());
    TestTrue(TEXT("Negative delta leaves velocity estimate unchanged"),
        Tracker.Update(FVector{100.0, 0.0, 0.0}, FCk_Time{-1.0}).IsNearlyZero());
    const auto Velocity = Tracker.Update(FVector{10.0, 0.0, 0.0}, FCk_Time{1.0});
    TestTrue(TEXT("Next sample measures from the last accepted position"),
        Velocity.Equals(FVector{10.0, 0.0, 0.0}, 0.0001));
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
