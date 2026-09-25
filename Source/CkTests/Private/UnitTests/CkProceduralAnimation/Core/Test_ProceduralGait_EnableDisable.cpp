#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_enable_disable
{
    constexpr auto FrameDt = FCk_Time{1.0f / 60.0f};
    constexpr auto MidSwingSearchFrames = 600;
    constexpr auto FrozenLeg = 1;
    constexpr auto LostLeg = 3;
    constexpr auto LegLossBlendTime = FCk_Time{0.2};
    constexpr auto WalkBeforeLoss = FCk_Time{1.0};
    constexpr auto WalkAfterLoss = FCk_Time{0.5};
    constexpr auto BlendProbeWindow = FCk_Time{0.1};
    constexpr auto PhaseTolerance = 1.0e-3f;

    struct FGaitHarness
    {
        ck::FProceduralGaitSolver Solver;
        TArray<FVector> Offsets;
        FVector BodyPosition = FVector::ZeroVector;
        FVector BodyVelocity = FVector::ZeroVector;
        bool Airborne = false;
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
            -> bool
        {
            BodyPosition += BodyVelocity * InDeltaTime.Get_Seconds();
            for (auto Index = 0; Index < Offsets.Num(); ++Index)
            {
                Inputs[Index].Set_IdealTarget(BodyPosition + Offsets[Index]);
            }
            return Solver.Step(InDeltaTime, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs, Airborne);
        }
    };

    auto
        InitQuadruped(
            FGaitHarness& InOutHarness,
            TArrayView<const float> InPhaseOffsets)
        -> void
    {
        InOutHarness.Init(
            {FVector{30.0, 20.0, 0.0}, FVector{30.0, -20.0, 0.0}, FVector{-30.0, 20.0, 0.0}, FVector{-30.0, -20.0, 0.0}},
            InPhaseOffsets);
    }

    auto
        InitQuadruped(
            FGaitHarness& InOutHarness)
        -> void
    {
        InitQuadruped(InOutHarness, {0.0f, 0.5f, 0.5f, 0.0f});
    }

    auto
        InitTrotQuadruped(
            FGaitHarness& InOutHarness)
        -> void
    {
        InOutHarness.Solver.Get_Settings().Get_Pattern().Set_BlendTime(LegLossBlendTime);
        InitQuadruped(InOutHarness, {0.0f, 0.5f, 0.0f, 0.5f});
    }

    auto
        FramesIn(
            FCk_Time InDuration)
        -> int32
    {
        return FMath::RoundToInt32(InDuration / FrameDt);
    }

    auto
        WrappedPhaseDelta(
            float InFrom,
            float InTo)
        -> float
    {
        return FMath::Frac(InTo - InFrom + 1.5f) - 0.5f;
    }

    auto
        Walk(
            FGaitHarness& InOutHarness,
            FCk_Time InDuration)
        -> bool
    {
        InOutHarness.BodyVelocity = FVector{100.0, 0.0, 0.0};
        for (auto Frame = 0; Frame < FramesIn(InDuration); ++Frame)
        {
            if (NOT InOutHarness.Tick(FrameDt))
            {
                return false;
            }
        }
        return true;
    }

    auto
        ReadEffectiveOffsets(
            const ck::FProceduralGaitSolver& InSolver)
        -> TArray<float>
    {
        auto Offsets = TArray<float>{};
        for (auto Leg = 0; Leg < InSolver.NumLegs(); ++Leg)
        {
            Offsets.Add(InSolver.GetEffectivePhaseOffset(Leg));
        }
        return Offsets;
    }

    auto
        SettleRedistributedTrot(
            FGaitHarness& InOutHarness)
        -> bool
    {
        InOutHarness.Solver.Get_Settings().Get_Pattern().Set_LegLossPolicy(ck::EProceduralGaitLegLossPolicy::RedistributeOffsets);
        InitTrotQuadruped(InOutHarness);
        if (NOT Walk(InOutHarness, WalkBeforeLoss))
        {
            return false;
        }

        constexpr auto Disabled = false;
        InOutHarness.Inputs[LostLeg].Set_Enabled(Disabled);
        return Walk(InOutHarness, WalkAfterLoss);
    }

    auto
        WalkUntilMidSwing(
            FGaitHarness& InOutHarness,
            int32 InLegIndex)
        -> bool
    {
        InOutHarness.BodyVelocity = FVector{100.0, 0.0, 0.0};
        for (auto Frame = 0; Frame < MidSwingSearchFrames; ++Frame)
        {
            InOutHarness.Tick(FrameDt);
            const auto SwingAlpha = InOutHarness.Outputs[InLegIndex].Get_SwingAlpha();
            if (SwingAlpha > 0.2f && SwingAlpha < 0.8f)
            {
                return true;
            }
        }
        return false;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitDisabledLegFreezesTest,
    "Ck.ProceduralAnimation.Gait.DisabledLegFreezesAndLeavesSchedule",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitDisabledLegFreezesTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    InitQuadruped(H);
    if (NOT TestTrue(TEXT("Leg 1 reaches mid-swing while walking"), WalkUntilMidSwing(H, FrozenLeg)))
    {
        return false;
    }

    const auto Recorded = H.Outputs;
    auto PlantsBefore = TArray<FVector>{};
    for (auto Leg = 0; Leg < H.Solver.NumLegs(); ++Leg)
    {
        PlantsBefore.Add(H.Solver.GetLegState(Leg).Get_Plant().Get_Position());
    }

    constexpr auto Disabled = false;
    H.Inputs[FrozenLeg].Set_Enabled(Disabled);
    H.Tick(FrameDt);

    const auto& Frozen = H.Outputs[FrozenLeg];
    TestTrue(TEXT("The disabled leg holds its mid-swing position"),
        Frozen.Get_Position().Equals(Recorded[FrozenLeg].Get_Position(), 1.0e-3f));
    TestTrue(TEXT("The disabled leg holds its mid-swing rotation"),
        Frozen.Get_Rotation().Equals(Recorded[FrozenLeg].Get_Rotation(), 1.0e-3f));
    TestTrue(TEXT("The disabled leg reports planted"), Frozen.Get_Planted());
    TestEqual(TEXT("The disabled leg reports no swing"), Frozen.Get_SwingAlpha(), 0.0f);

    for (auto Leg = 0; Leg < H.Solver.NumLegs(); ++Leg)
    {
        if (Leg == FrozenLeg)
        {
            continue;
        }
        TestTrue(FString::Printf(TEXT("Leg %d's plant does not pop when leg 1 is disabled"), Leg),
            H.Solver.GetLegState(Leg).Get_Plant().Get_Position().Equals(PlantsBefore[Leg], 1.0e-3f));
    }

    const auto TwoCycleFrames = FMath::CeilToInt32(H.Solver.Get_Settings().Get_Cadence().Get_CycleDuration() * 2.0f / FrameDt);
    for (auto Frame = 0; Frame < TwoCycleFrames; ++Frame)
    {
        H.Tick(FrameDt);
        if (H.Outputs[FrozenLeg].Get_SwingAlpha() > 0.0f)
        {
            AddError(FString::Printf(TEXT("The disabled leg swung again (frame %d)"), Frame));
            return false;
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitReenabledLegSwingsTest,
    "Ck.ProceduralAnimation.Gait.ReenabledLegSwingsFromFrozenPose",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitReenabledLegSwingsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    InitQuadruped(H);
    if (NOT TestTrue(TEXT("Leg 1 reaches mid-swing while walking"), WalkUntilMidSwing(H, FrozenLeg)))
    {
        return false;
    }

    constexpr auto Disabled = false;
    H.Inputs[FrozenLeg].Set_Enabled(Disabled);
    const auto OneCycleFrames = FMath::CeilToInt32(H.Solver.Get_Settings().Get_Cadence().Get_CycleDuration() / FrameDt);
    for (auto Frame = 0; Frame < OneCycleFrames; ++Frame)
    {
        H.Tick(FrameDt);
    }

    const auto FrozenPosition = H.Outputs[FrozenLeg].Get_Position();
    const auto StepThreshold = H.Solver.Get_Settings().Get_Step().Get_Threshold();
    TestTrue(TEXT("A cycle of walking leaves the ideal target beyond a step threshold of the frozen pose"),
        FVector::Dist(FrozenPosition, H.Inputs[FrozenLeg].Get_IdealTarget()) > StepThreshold);

    constexpr auto Enabled = true;
    H.Inputs[FrozenLeg].Set_Enabled(Enabled);
    H.Tick(FrameDt);

    const auto Displacement = FVector::Dist(H.Outputs[FrozenLeg].Get_Position(), FrozenPosition);
    TestTrue(FString::Printf(TEXT("The re-enabled leg does not teleport (moved %.2f)"), Displacement),
        Displacement < H.Solver.Get_Settings().Get_Swing().Get_Height());
    TestTrue(TEXT("The re-enabled leg starts a swing"), H.Outputs[FrozenLeg].Get_SwingAlpha() > 0.0f);

    const auto LandingBudgetFrames = FMath::CeilToInt32(H.Solver.Get_Settings().Get_Step().Get_Duration() * 1.5f / FrameDt);
    auto Landed = false;
    for (auto Frame = 1; Frame < LandingBudgetFrames; ++Frame)
    {
        H.Tick(FrameDt);
        if (H.Outputs[FrozenLeg].Get_Planted())
        {
            Landed = true;
            break;
        }
    }
    if (NOT TestTrue(TEXT("The re-enabled leg plants within 1.5 step durations"), Landed))
    {
        return false;
    }

    const auto LandingError = FVector::Dist(H.Outputs[FrozenLeg].Get_Position(), H.Inputs[FrozenLeg].Get_IdealTarget());
    TestTrue(FString::Printf(TEXT("The re-enabled leg plants within a step threshold of its ideal target (error %.2f)"),
            LandingError),
        LandingError < StepThreshold);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitDisabledLegBudgetTest,
    "Ck.ProceduralAnimation.Gait.DisabledLegsDoNotConsumeSwingBudget",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitDisabledLegBudgetTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

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
    if (NOT TestFalse(TEXT("Leg 0 takes the only swing slot"), Outputs[0].Get_Planted()))
    {
        return false;
    }
    TestTrue(TEXT("Leg 1 waits on the budget"), Outputs[1].Get_Planted());
    TestTrue(TEXT("Leg 2 waits on the budget"), Outputs[2].Get_Planted());

    constexpr auto Disabled = false;
    Inputs[0].Set_Enabled(Disabled);

    Solver.Step(FrameDt, 100.0f, FVector::ZeroVector, Inputs, Outputs);
    TestTrue(TEXT("Another leg lifts on the step that disables the swinging leg"),
        NOT Outputs[1].Get_Planted() || NOT Outputs[2].Get_Planted());

    const auto OneCycleFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_Cadence().Get_CycleDuration() / FrameDt);
    auto OtherLegSwung = false;
    for (auto Frame = 0; Frame < OneCycleFrames && NOT OtherLegSwung; ++Frame)
    {
        Solver.Step(FrameDt, 100.0f, FVector::ZeroVector, Inputs, Outputs);
        OtherLegSwung = Outputs[1].Get_SwingAlpha() > 0.0f || Outputs[2].Get_SwingAlpha() > 0.0f;
    }
    TestTrue(TEXT("A remaining leg swings within one cycle once the disabled leg frees the budget"), OtherLegSwung);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitAllLegsDisabledTest,
    "Ck.ProceduralAnimation.Gait.AllLegsDisabledStepSucceedsWithoutMotion",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitAllLegsDisabledTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    InitQuadruped(H);
    if (NOT TestTrue(TEXT("Leg 1 reaches mid-swing while walking"), WalkUntilMidSwing(H, FrozenLeg)))
    {
        return false;
    }

    constexpr auto Disabled = false;
    for (auto& Input : H.Inputs)
    {
        Input.Set_Enabled(Disabled);
    }
    if (NOT TestTrue(TEXT("A step with every leg disabled succeeds"), H.Tick(FrameDt)))
    {
        return false;
    }
    TestEqual(TEXT("No leg reports enabled"), H.Solver.NumEnabledLegs(), 0);

    const auto Held = H.Outputs;
    for (auto Frame = 0; Frame < 60; ++Frame)
    {
        if (NOT H.Tick(FrameDt))
        {
            AddError(FString::Printf(TEXT("Step rejected with every leg disabled (frame %d)"), Frame));
            return false;
        }
        for (auto Leg = 0; Leg < H.Outputs.Num(); ++Leg)
        {
            const auto& Out = H.Outputs[Leg];
            const auto Unchanged = Out.Get_Position().Equals(Held[Leg].Get_Position(), 1.0e-3f)
                && Out.Get_Rotation().Equals(Held[Leg].Get_Rotation(), 1.0e-3f)
                && Out.Get_Normal().Equals(Held[Leg].Get_Normal(), 1.0e-3f)
                && Out.Get_Planted() == Held[Leg].Get_Planted()
                && Out.Get_SwingAlpha() == Held[Leg].Get_SwingAlpha();
            if (NOT Unchanged)
            {
                AddError(FString::Printf(TEXT("Leg %d's output moved with every leg disabled (frame %d, at %s)"),
                    Leg, Frame, *Out.Get_Position().ToCompactString()));
                return false;
            }
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitDisabledLegIndexStabilityTest,
    "Ck.ProceduralAnimation.Gait.IndexStabilityUnderPatternsWithDisabledLeg",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitDisabledLegIndexStabilityTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    const auto Pattern = ck::FProceduralGaitPattern{}.Set_MinSpeed(0.0f).Set_PhaseOffsets({0.0f, 0.5f, 0.25f, 0.75f});

    auto H = FGaitHarness{};
    H.Solver.Get_Settings().Get_Pattern().Set_Patterns({Pattern});
    InitQuadruped(H);

    H.Tick(FrameDt);
    const auto OffsetBefore = H.Solver.GetEffectivePhaseOffset(2);
    TestTrue(FString::Printf(TEXT("Leg 2 takes its pattern offset (%.3f)"), OffsetBefore),
        FMath::IsNearlyEqual(OffsetBefore, 0.25f, KINDA_SMALL_NUMBER));

    constexpr auto Disabled = false;
    H.Inputs[1].Set_Enabled(Disabled);
    H.Tick(FrameDt);

    TestEqual(TEXT("Disabling leg 1 leaves leg 2's pattern offset in place"),
        H.Solver.GetEffectivePhaseOffset(2), OffsetBefore);
    TestFalse(TEXT("Leg 1 reads disabled"), H.Solver.IsLegEnabled(1));
    TestEqual(TEXT("Three legs remain enabled"), H.Solver.NumEnabledLegs(), 3);
    TestFalse(TEXT("A catch step on the disabled leg is refused"),
        H.Solver.RequestStep(1, H.Inputs[1].Get_IdealTarget()));

    auto Redistributing = FGaitHarness{};
    Redistributing.Solver.Get_Settings().Get_Pattern()
        .Set_Patterns({Pattern})
        .Set_LegLossPolicy(ck::EProceduralGaitLegLossPolicy::RedistributeOffsets);
    InitQuadruped(Redistributing);

    Redistributing.Tick(FrameDt);
    const auto PatternIndexBefore = Redistributing.Solver.GetCurrentPatternIndex();

    Redistributing.Inputs[1].Set_Enabled(Disabled);
    const auto BlendFrames = FramesIn(Redistributing.Solver.Get_Settings().Get_Pattern().Get_BlendTime()) + 2;
    for (auto Frame = 0; Frame < BlendFrames; ++Frame)
    {
        Redistributing.Tick(FrameDt);
    }

    const auto EnabledLegs = TArray<int32>{0, 2, 3};
    const auto EvenlySpaced = TArray<float>{0.0f, 1.0f / 3.0f, 2.0f / 3.0f};
    for (auto Rank = 0; Rank < EnabledLegs.Num(); ++Rank)
    {
        const auto Offset = Redistributing.Solver.GetEffectivePhaseOffset(EnabledLegs[Rank]);
        TestTrue(FString::Printf(TEXT("Under RedistributeOffsets leg %d re-spaces to %.3f over the pattern table (got %.4f)"),
                EnabledLegs[Rank], EvenlySpaced[Rank], Offset),
            FMath::Abs(WrappedPhaseDelta(EvenlySpaced[Rank], Offset)) < PhaseTolerance);
    }
    TestEqual(TEXT("Redistributing offsets leaves the selected pattern unchanged"),
        Redistributing.Solver.GetCurrentPatternIndex(), PatternIndexBefore);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLegLossRedistributesTest,
    "Ck.ProceduralAnimation.Gait.LegLossRedistributesOffsetsWhenPolicySet",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLegLossRedistributesTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    H.Solver.Get_Settings().Get_Pattern().Set_LegLossPolicy(ck::EProceduralGaitLegLossPolicy::RedistributeOffsets);
    InitTrotQuadruped(H);

    if (NOT TestTrue(TEXT("The solver accepts the RedistributeOffsets policy"), Walk(H, WalkBeforeLoss)))
    {
        return false;
    }

    const auto Before = ReadEffectiveOffsets(H.Solver);
    const auto Authored = TArray<float>{0.0f, 0.5f, 0.0f, 0.5f};
    for (auto Leg = 0; Leg < Authored.Num(); ++Leg)
    {
        TestTrue(FString::Printf(TEXT("Before the loss leg %d runs its authored offset %.2f (got %.4f)"),
                Leg, Authored[Leg], Before[Leg]),
            Before[Leg] == Authored[Leg]);
    }

    constexpr auto Disabled = false;
    H.Inputs[LostLeg].Set_Enabled(Disabled);

    const auto Redistributed = TArray<float>{0.0f, 1.0f / 3.0f, 2.0f / 3.0f};
    const auto MovingLegs = TArray<int32>{1, 2};
    const auto ProbeFrames = FramesIn(BlendProbeWindow);
    for (auto Frame = 0; Frame < ProbeFrames; ++Frame)
    {
        if (NOT H.Tick(FrameDt))
        {
            AddError(FString::Printf(TEXT("Step rejected after the loss (frame %d)"), Frame));
            return false;
        }
        for (const auto Leg : MovingLegs)
        {
            const auto Current = H.Solver.GetEffectivePhaseOffset(Leg);
            const auto Progress = WrappedPhaseDelta(Before[Leg], Current) / WrappedPhaseDelta(Before[Leg], Redistributed[Leg]);
            if (NOT (Progress > 0.0f && Progress < 1.0f))
            {
                AddError(FString::Printf(
                    TEXT("Leg %d's offset is not strictly between %.4f and %.4f on frame %d after the loss (got %.4f)"),
                    Leg, Before[Leg], Redistributed[Leg], Frame, Current));
                return false;
            }
        }
    }

    if (NOT TestTrue(TEXT("The walk after the loss is accepted"), Walk(H, WalkAfterLoss - FrameDt * ProbeFrames)))
    {
        return false;
    }

    for (auto Leg = 0; Leg < Redistributed.Num(); ++Leg)
    {
        const auto Offset = H.Solver.GetEffectivePhaseOffset(Leg);
        TestTrue(FString::Printf(TEXT("Survivor %d re-spaces to %.4f (got %.4f)"), Leg, Redistributed[Leg], Offset),
            FMath::Abs(WrappedPhaseDelta(Redistributed[Leg], Offset)) < PhaseTolerance);
    }
    TestTrue(FString::Printf(TEXT("The lost leg keeps its offset %.4f (got %.4f)"),
            Before[LostLeg], H.Solver.GetEffectivePhaseOffset(LostLeg)),
        H.Solver.GetEffectivePhaseOffset(LostLeg) == Before[LostLeg]);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLegLossKeepsAuthoredTest,
    "Ck.ProceduralAnimation.Gait.LegLossKeepsAuthoredOffsetsByDefault",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLegLossKeepsAuthoredTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    InitTrotQuadruped(H);
    TestTrue(TEXT("KeepAuthoredOffsets is the default leg-loss policy"),
        H.Solver.Get_Settings().Get_Pattern().Get_LegLossPolicy() == ck::EProceduralGaitLegLossPolicy::KeepAuthoredOffsets);

    if (NOT TestTrue(TEXT("The walk before the loss is accepted"), Walk(H, WalkBeforeLoss)))
    {
        return false;
    }
    const auto Before = ReadEffectiveOffsets(H.Solver);

    constexpr auto Disabled = false;
    H.Inputs[LostLeg].Set_Enabled(Disabled);
    if (NOT TestTrue(TEXT("The walk after the loss is accepted"), Walk(H, WalkAfterLoss)))
    {
        return false;
    }

    const auto Authored = TArray<float>{0.0f, 0.5f, 0.0f};
    for (auto Leg = 0; Leg < Authored.Num(); ++Leg)
    {
        const auto Offset = H.Solver.GetEffectivePhaseOffset(Leg);
        TestTrue(FString::Printf(TEXT("Survivor %d keeps its authored offset %.2f exactly (before %.4f, after %.4f)"),
                Leg, Authored[Leg], Before[Leg], Offset),
            Offset == Authored[Leg] && Offset == Before[Leg]);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitReenableWhileAirborneTest,
    "Ck.ProceduralAnimation.Gait.ReenableWhileAirborneStartsFromFrozenPose",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitReenableWhileAirborneTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    constexpr auto AirborneFramesBeforeEnable = 10;
    constexpr auto AirborneFramesAfterEnable = 30;

    auto H = FGaitHarness{};
    InitQuadruped(H);
    if (NOT TestTrue(TEXT("The walk away from the rest pose is accepted"), Walk(H, WalkBeforeLoss)))
    {
        return false;
    }
    if (NOT TestTrue(TEXT("Leg 1 reaches mid-swing while walking"), WalkUntilMidSwing(H, FrozenLeg)))
    {
        return false;
    }

    constexpr auto Disabled = false;
    H.Inputs[FrozenLeg].Set_Enabled(Disabled);
    if (NOT TestTrue(TEXT("The walk with leg 1 disabled is accepted"), Walk(H, WalkAfterLoss)))
    {
        return false;
    }
    const auto Frozen = H.Outputs[FrozenLeg].Get_Position();

    H.BodyVelocity = FVector::ZeroVector;
    H.Airborne = true;
    for (auto Frame = 0; Frame < AirborneFramesBeforeEnable; ++Frame)
    {
        H.Tick(FrameDt);
    }

    const auto& Settings = H.Solver.Get_Settings();
    TestTrue(TEXT("The disabled leg holds its frozen pose while airborne"),
        H.Outputs[FrozenLeg].Get_Position().Equals(Frozen, 1.0e-3f));
    const auto StaleAirDistance = FVector::Dist(H.Solver.GetLegState(FrozenLeg).Get_Emitted().Get_AirPosition(), Frozen);
    if (NOT TestTrue(FString::Printf(TEXT("The disabled leg's stored air pose is stale (%.2f from the frozen pose)"),
            StaleAirDistance),
        StaleAirDistance > Settings.Get_Swing().Get_Height()))
    {
        return false;
    }

    constexpr auto Enabled = true;
    H.Inputs[FrozenLeg].Set_Enabled(Enabled);
    H.Tick(FrameDt);

    const auto EnableDisplacement = FVector::Dist(H.Outputs[FrozenLeg].Get_Position(), Frozen);
    TestTrue(FString::Printf(TEXT("The leg re-enabled mid-air starts from its frozen pose (moved %.2f)"), EnableDisplacement),
        EnableDisplacement < Settings.Get_Swing().Get_Height());

    const auto TuckTarget = H.Inputs[FrozenLeg].Get_IdealTarget() + FVector{0.0, 0.0, Settings.Get_Airborne().Get_TuckLift()};
    auto PreviousDistance = FVector::Dist(H.Outputs[FrozenLeg].Get_Position(), TuckTarget);
    for (auto Frame = 0; Frame < AirborneFramesAfterEnable; ++Frame)
    {
        H.Tick(FrameDt);
        const auto Distance = FVector::Dist(H.Outputs[FrozenLeg].Get_Position(), TuckTarget);
        if (NOT (Distance < PreviousDistance))
        {
            AddError(FString::Printf(TEXT("The re-enabled leg stopped closing on its tuck target (frame %d, %.3f -> %.3f)"),
                Frame, PreviousDistance, Distance));
            return false;
        }
        PreviousDistance = Distance;
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitRedistributionRevertsTest,
    "Ck.ProceduralAnimation.Gait.RedistributionRevertsWhenAllLegsReturn",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitRedistributionRevertsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    if (NOT TestTrue(TEXT("The walk into the redistributed state is accepted"), SettleRedistributedTrot(H)))
    {
        return false;
    }

    const auto Redistributed = TArray<float>{0.0f, 1.0f / 3.0f, 2.0f / 3.0f};
    const auto Settled = ReadEffectiveOffsets(H.Solver);
    for (auto Leg = 0; Leg < Redistributed.Num(); ++Leg)
    {
        if (NOT TestTrue(FString::Printf(TEXT("Survivor %d settled at %.4f before the return (got %.4f)"),
                Leg, Redistributed[Leg], Settled[Leg]),
            FMath::Abs(WrappedPhaseDelta(Redistributed[Leg], Settled[Leg])) < PhaseTolerance))
        {
            return false;
        }
    }

    constexpr auto Enabled = true;
    H.Inputs[LostLeg].Set_Enabled(Enabled);

    const auto Authored = TArray<float>{0.0f, 0.5f, 0.0f, 0.5f};
    const auto MovingLegs = TArray<int32>{1, 2};
    const auto ProbeFrames = FramesIn(BlendProbeWindow);
    for (auto Frame = 0; Frame < ProbeFrames; ++Frame)
    {
        if (NOT H.Tick(FrameDt))
        {
            AddError(FString::Printf(TEXT("Step rejected after the return (frame %d)"), Frame));
            return false;
        }
        for (const auto Leg : MovingLegs)
        {
            const auto Current = H.Solver.GetEffectivePhaseOffset(Leg);
            const auto Progress = WrappedPhaseDelta(Settled[Leg], Current) / WrappedPhaseDelta(Settled[Leg], Authored[Leg]);
            if (NOT (Progress > 0.0f && Progress < 1.0f))
            {
                AddError(FString::Printf(
                    TEXT("Leg %d's offset is not strictly between %.4f and %.4f on frame %d after the return (got %.4f)"),
                    Leg, Settled[Leg], Authored[Leg], Frame, Current));
                return false;
            }
        }
    }

    if (NOT TestTrue(TEXT("The walk after the return is accepted"), Walk(H, WalkAfterLoss - FrameDt * ProbeFrames)))
    {
        return false;
    }

    for (auto Leg = 0; Leg < Authored.Num(); ++Leg)
    {
        const auto Offset = H.Solver.GetEffectivePhaseOffset(Leg);
        TestTrue(FString::Printf(TEXT("Leg %d returns to its authored offset %.2f (got %.4f)"), Leg, Authored[Leg], Offset),
            FMath::Abs(WrappedPhaseDelta(Authored[Leg], Offset)) < PhaseTolerance);
    }
    TestTrue(TEXT("The returned leg reads enabled"), H.Solver.IsLegEnabled(LostLeg));
    TestEqual(TEXT("All four legs are enabled"), H.Solver.NumEnabledLegs(), 4);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitKeepPolicyClearsRedistributionTest,
    "Ck.ProceduralAnimation.Gait.KeepPolicyClearsPriorRedistribution",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitKeepPolicyClearsRedistributionTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    auto H = FGaitHarness{};
    if (NOT TestTrue(TEXT("The walk into the redistributed state is accepted"), SettleRedistributedTrot(H)))
    {
        return false;
    }

    const auto Redistributed = TArray<float>{0.0f, 1.0f / 3.0f, 2.0f / 3.0f};
    const auto Settled = ReadEffectiveOffsets(H.Solver);
    for (auto Leg = 0; Leg < Redistributed.Num(); ++Leg)
    {
        if (NOT TestTrue(FString::Printf(TEXT("Survivor %d settled at %.4f before the policy flip (got %.4f)"),
                Leg, Redistributed[Leg], Settled[Leg]),
            FMath::Abs(WrappedPhaseDelta(Redistributed[Leg], Settled[Leg])) < PhaseTolerance))
        {
            return false;
        }
    }
    const auto FrozenPosition = H.Outputs[LostLeg].Get_Position();

    auto Settings = H.Solver.Get_Settings();
    Settings.Get_Pattern().Set_LegLossPolicy(ck::EProceduralGaitLegLossPolicy::KeepAuthoredOffsets);
    H.Solver.Set_Settings(Settings);

    if (NOT TestTrue(TEXT("The first step after the policy flip is accepted"), H.Tick(FrameDt)))
    {
        return false;
    }
    constexpr auto AuthoredLeg1 = 0.5f;
    const auto FirstStepProgress = WrappedPhaseDelta(Settled[1], H.Solver.GetEffectivePhaseOffset(1))
        / WrappedPhaseDelta(Settled[1], AuthoredLeg1);
    TestTrue(FString::Printf(TEXT("Leg 1 blends back rather than jumping (progress %.3f on the first step)"), FirstStepProgress),
        FirstStepProgress > 0.0f && FirstStepProgress < 1.0f);

    if (NOT TestTrue(TEXT("The walk after the policy flip is accepted"), Walk(H, WalkAfterLoss - FrameDt)))
    {
        return false;
    }

    const auto Authored = TArray<float>{0.0f, 0.5f, 0.0f};
    for (auto Leg = 0; Leg < Authored.Num(); ++Leg)
    {
        const auto Offset = H.Solver.GetEffectivePhaseOffset(Leg);
        TestTrue(FString::Printf(TEXT("Survivor %d returns to its authored offset %.2f (got %.4f)"), Leg, Authored[Leg], Offset),
            FMath::Abs(WrappedPhaseDelta(Authored[Leg], Offset)) < PhaseTolerance);
    }
    TestFalse(TEXT("The lost leg stays disabled"), H.Solver.IsLegEnabled(LostLeg));
    TestEqual(TEXT("Three legs remain enabled"), H.Solver.NumEnabledLegs(), 3);
    TestTrue(TEXT("The lost leg stays frozen"), H.Outputs[LostLeg].Get_Position().Equals(FrozenPosition, 1.0e-3f));
    TestTrue(TEXT("The lost leg reports planted"), H.Outputs[LostLeg].Get_Planted());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSetDisabledPoseTest,
    "Ck.ProceduralAnimation.Gait.SetDisabledPoseMovesFrozenLegAndReenableStartsThere",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSetDisabledPoseTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_enable_disable;

    constexpr auto MovedPoseDistance = 40.0;
    constexpr auto EnabledLeg = 0;

    auto H = FGaitHarness{};
    InitQuadruped(H);
    if (NOT TestTrue(TEXT("Leg 1 reaches mid-swing while walking"), WalkUntilMidSwing(H, FrozenLeg)))
    {
        return false;
    }

    constexpr auto Disabled = false;
    H.Inputs[FrozenLeg].Set_Enabled(Disabled);
    H.Tick(FrameDt);
    if (NOT TestFalse(TEXT("Leg 1 reads disabled after the step that disables it"), H.Solver.IsLegEnabled(FrozenLeg)))
    {
        return false;
    }

    const auto Frozen = H.Outputs[FrozenLeg].Get_Position();
    const auto MovedPosition = Frozen + FVector{0.0, MovedPoseDistance, 0.0};
    const auto MovedRotation = FQuat{FVector::UpVector, 0.3};
    const auto MovedNormal = FVector::UpVector;

    const auto EnabledBefore = H.Solver.GetLegState(EnabledLeg);
    TestFalse(TEXT("SetDisabledPose on an enabled leg is refused"),
        H.Solver.SetDisabledPose(EnabledLeg, MovedPosition, MovedRotation, MovedNormal));
    const auto& EnabledAfter = H.Solver.GetLegState(EnabledLeg);
    TestTrue(TEXT("A refused SetDisabledPose leaves the enabled leg's current pose unchanged"),
        EnabledAfter.Get_Emitted().Get_Position().Equals(EnabledBefore.Get_Emitted().Get_Position(), 0.0f)
        && EnabledAfter.Get_Emitted().Get_Rotation().Equals(EnabledBefore.Get_Emitted().Get_Rotation(), 0.0f));
    TestTrue(TEXT("A refused SetDisabledPose leaves the enabled leg's planted pose unchanged"),
        EnabledAfter.Get_Plant().Get_Position().Equals(EnabledBefore.Get_Plant().Get_Position(), 0.0f)
        && EnabledAfter.Get_Plant().Get_Normal().Equals(EnabledBefore.Get_Plant().Get_Normal(), 0.0f));
    TestFalse(TEXT("SetDisabledPose on an out-of-range leg is refused"),
        H.Solver.SetDisabledPose(H.Solver.NumLegs(), MovedPosition, MovedRotation, MovedNormal));

    if (NOT TestTrue(TEXT("SetDisabledPose on the disabled leg is accepted"),
        H.Solver.SetDisabledPose(FrozenLeg, MovedPosition, MovedRotation, MovedNormal)))
    {
        return false;
    }

    H.Tick(FrameDt);
    TestTrue(TEXT("The disabled leg's output moves to the set position"),
        H.Outputs[FrozenLeg].Get_Position().Equals(MovedPosition, 1.0e-3f));
    TestTrue(TEXT("The disabled leg's output takes the set rotation"),
        H.Outputs[FrozenLeg].Get_Rotation().Equals(MovedRotation, 1.0e-3f));
    TestTrue(TEXT("The disabled leg still reports planted"), H.Outputs[FrozenLeg].Get_Planted());

    constexpr auto Enabled = true;
    H.Inputs[FrozenLeg].Set_Enabled(Enabled);
    H.Tick(FrameDt);

    const auto Displacement = FVector::Dist(H.Outputs[FrozenLeg].Get_Position(), MovedPosition);
    TestTrue(FString::Printf(TEXT("The re-enabled leg starts from the set pose (moved %.2f)"), Displacement),
        Displacement < H.Solver.Get_Settings().Get_Swing().Get_Height());

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
