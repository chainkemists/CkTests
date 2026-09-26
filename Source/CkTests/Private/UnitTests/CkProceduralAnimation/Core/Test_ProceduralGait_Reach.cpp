#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_reach
{
    constexpr auto FrameDt = FCk_Time{1.0f / 60.0f};
    constexpr auto LegReach = 100.0f;
    constexpr auto ReachTolerance = 0.01;
    constexpr auto AirborneFrames = 30;
    constexpr auto WalkFrames = 180;

    struct FReachHarness
    {
        ck::FProceduralGaitSolver Solver;
        TArray<FVector> Hips;
        TArray<FVector> Targets;
        FVector BodyPosition = FVector::ZeroVector;
        FVector BodyVelocity = FVector::ZeroVector;
        FVector Lead = FVector::ZeroVector;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        auto
            Init(
                TArrayView<const FVector> InHips,
                TArrayView<const FVector> InTargets,
                TArrayView<const float> InPhaseOffsets,
                float InReach)
            -> void
        {
            Hips = TArray<FVector>{InHips};
            Targets = TArray<FVector>{InTargets};
            Inputs.SetNum(Hips.Num());
            Outputs.SetNum(Hips.Num());

            auto Initial = TArray<FVector>{};
            for (auto Index = 0; Index < Hips.Num(); ++Index)
            {
                Initial.Add(BodyPosition + Targets[Index]);
                Inputs[Index].Set_PhaseOffset(InPhaseOffsets[Index]).Set_Reach(InReach);
            }
            Solver.Reset(Initial);
            UpdateInputs();
        }

        auto
            UpdateInputs()
            -> void
        {
            for (auto Index = 0; Index < Hips.Num(); ++Index)
            {
                Inputs[Index].Set_Hip(BodyPosition + Hips[Index])
                    .Set_IdealTarget(BodyPosition + Targets[Index] + Lead);
            }
        }

        auto
            Tick(
                FCk_Time InDeltaTime,
                bool InAirborne = false)
            -> bool
        {
            BodyPosition += BodyVelocity * InDeltaTime.Get_Seconds();
            UpdateInputs();
            return Solver.Step(InDeltaTime, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs, InAirborne);
        }

        auto
            Get_TargetLimit(
                int32 InLegIndex) const
            -> double
        {
            return Solver.Get_Settings().Get_Reach().Get_TargetFraction() * Inputs[InLegIndex].Get_Reach();
        }

        auto
            Get_HipDistance(
                int32 InLegIndex,
                const FVector& InPoint) const
            -> double
        {
            return FVector::Dist(InPoint, Inputs[InLegIndex].Get_Hip());
        }
    };

    // Four legs whose ideal targets sit 87.7 cm from their hips: beyond 0.8 of a 100 cm reach, inside 0.92 of it.
    auto
        InitOverreachingQuadruped(
            FReachHarness& InOutHarness,
            float InReach)
        -> void
    {
        InOutHarness.Init(
            {FVector{30.0, 20.0, 0.0}, FVector{30.0, -20.0, 0.0}, FVector{-30.0, 20.0, 0.0}, FVector{-30.0, -20.0, 0.0}},
            {FVector{90.0, 70.0, -40.0}, FVector{90.0, -70.0, -40.0}, FVector{30.0, 70.0, -40.0}, FVector{30.0, -70.0, -40.0}},
            {0.0f, 0.5f, 0.5f, 0.0f},
            InReach);
    }

    // Checks every swing that began on the last tick targets a point within reach, and every plant made on it lies
    // within reach. Disabled legs are skipped; their frozen pose is neither a lift nor a landing.
    struct FReachWatch
    {
        TArray<bool> WasPlanted;
        int32 Lifts = 0;
        int32 Landings = 0;
        int32 Violations = 0;

        auto
            Init(
                const FReachHarness& InHarness)
            -> void
        {
            WasPlanted.Init(true, InHarness.Outputs.Num());
        }

        auto
            Check(
                FAutomationTestBase& InTest,
                const FReachHarness& InHarness,
                const TCHAR* InSite)
            -> void
        {
            for (auto Leg = 0; Leg < InHarness.Outputs.Num(); ++Leg)
            {
                const auto Planted = InHarness.Outputs[Leg].Get_Planted();
                if (NOT InHarness.Inputs[Leg].Get_Enabled())
                {
                    WasPlanted[Leg] = true;
                    continue;
                }

                const auto Limit = InHarness.Get_TargetLimit(Leg) + ReachTolerance;
                if (WasPlanted[Leg] && NOT Planted)
                {
                    ++Lifts;
                    const auto Distance = InHarness.Get_HipDistance(Leg, InHarness.Solver.GetLegState(Leg).Get_Swing().Get_Target());
                    if (Distance > Limit)
                    {
                        ++Violations;
                        InTest.AddError(FString::Printf(TEXT("%s: leg %d began a swing toward a target %.2f cm from its hip (limit %.2f)"),
                            InSite, Leg, Distance, Limit));
                    }
                }
                if (NOT WasPlanted[Leg] && Planted)
                {
                    ++Landings;
                    const auto Distance = InHarness.Get_HipDistance(Leg, InHarness.Outputs[Leg].Get_Position());
                    if (Distance > Limit)
                    {
                        ++Violations;
                        InTest.AddError(FString::Printf(TEXT("%s: leg %d planted %.2f cm from its hip (limit %.2f)"),
                            InSite, Leg, Distance, Limit));
                    }
                }
                WasPlanted[Leg] = Planted;
            }
        }
    };

    // The centipede layout: sixteen 100 cm legs in four phase groups a quarter cycle apart, each right leg half a cycle
    // behind its left.
    auto
        InitCentipede(
            FReachHarness& InOutHarness)
        -> void
    {
        auto Hips = TArray<FVector>{};
        auto Rests = TArray<FVector>{};
        auto PhaseOffsets = TArray<float>{};
        for (auto Pair = 0; Pair < 8; ++Pair)
        {
            const auto HipX = 105.0 - 30.0 * Pair;
            for (auto SideIndex = 0; SideIndex < 2; ++SideIndex)
            {
                const auto Side = SideIndex == 0 ? -1.0 : 1.0;
                Hips.Add(FVector{HipX, Side * 24.0, 0.0});
                Rests.Add(FVector{HipX, Side * 75.0, -45.0});
                PhaseOffsets.Add(FMath::Frac((Pair % 4) * 0.25f + (SideIndex == 0 ? 0.0f : 0.5f)));
            }
        }
        InOutHarness.Init(Hips, Rests, PhaseOffsets, LegReach);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitReachClampsSwingTargetsTest,
    "Ck.ProceduralAnimation.Gait.ReachClampsSwingTargets",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitReachClampsSwingTargetsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    auto H = FReachHarness{};
    InitOverreachingQuadruped(H, LegReach);
    H.BodyVelocity = FVector{100.0, 0.0, 0.0};
    auto Watch = FReachWatch{};
    Watch.Init(H);

    for (auto Frame = 0; Frame < WalkFrames; ++Frame)
    {
        H.Tick(FrameDt);
        Watch.Check(*this, H, TEXT("Walking take-off, retarget, freeze push and overshoot"));
    }
    if (NOT TestTrue(FString::Printf(TEXT("Walking lifts and plants every leg (lifts %d, landings %d)"), Watch.Lifts, Watch.Landings),
            Watch.Lifts >= 4 && Watch.Landings >= 4))
    {
        return false;
    }

    constexpr auto ReconciledLeg = 1;
    constexpr auto Disabled = false;
    constexpr auto Enabled = true;
    H.Inputs[ReconciledLeg].Set_Enabled(Disabled);
    for (auto Frame = 0; Frame < WalkFrames / 3; ++Frame)
    {
        H.Tick(FrameDt);
        Watch.Check(*this, H, TEXT("Walking with a disabled leg"));
    }
    H.Inputs[ReconciledLeg].Set_Enabled(Enabled);
    H.Tick(FrameDt);
    const auto ReconcileSwing = H.Solver.GetLegState(ReconciledLeg).Get_Swing();
    if (TestTrue(TEXT("Re-enabling the leg begins a swing"), ReconcileSwing.Get_Active()))
    {
        const auto Distance = H.Get_HipDistance(ReconciledLeg, ReconcileSwing.Get_Target());
        TestTrue(FString::Printf(TEXT("The re-enable swing targets a point within reach (%.2f cm)"), Distance),
            Distance <= H.Get_TargetLimit(ReconciledLeg) + ReachTolerance);
    }
    Watch.WasPlanted[ReconciledLeg] = false;

    constexpr auto Airborne = true;
    for (auto Frame = 0; Frame < AirborneFrames; ++Frame)
    {
        H.Tick(FrameDt, Airborne);
    }
    H.Tick(FrameDt);
    for (auto Leg = 0; Leg < H.Outputs.Num(); ++Leg)
    {
        const auto& Swing = H.Solver.GetLegState(Leg).Get_Swing();
        if (NOT TestTrue(FString::Printf(TEXT("Leg %d begins a landing swing"), Leg), Swing.Get_Active()))
        {
            continue;
        }
        const auto Distance = H.Get_HipDistance(Leg, Swing.Get_Target());
        TestTrue(FString::Printf(TEXT("Leg %d's landing swing targets a point within reach (%.2f cm)"), Leg, Distance),
            Distance <= H.Get_TargetLimit(Leg) + ReachTolerance);
        Watch.WasPlanted[Leg] = false;
    }
    const auto LandingsBefore = Watch.Landings;
    for (auto Frame = 0; Frame < WalkFrames / 3; ++Frame)
    {
        H.Tick(FrameDt);
        Watch.Check(*this, H, TEXT("Landing after airborne"));
    }
    TestTrue(TEXT("Every leg plants after the airborne landing"), Watch.Landings - LandingsBefore >= H.Outputs.Num());

    constexpr auto CatchLeg = 0;
    const auto FarTarget = H.BodyPosition + FVector{300.0, 0.0, -40.0};
    H.Solver.Get_Settings().Get_Schedule().Set_CatchStepLifetime(FCk_Time{1.0});
    if (NOT TestTrue(TEXT("The catch step is accepted"), H.Solver.RequestStep(CatchLeg, FarTarget)))
    {
        return false;
    }
    auto CatchSwingSeen = false;
    for (auto Frame = 0; Frame < WalkFrames; ++Frame)
    {
        H.Tick(FrameDt);
        const auto& Swing = H.Solver.GetLegState(CatchLeg).Get_Swing();
        if (NOT CatchSwingSeen && Swing.Get_Active() && Swing.Get_CatchStep())
        {
            CatchSwingSeen = true;
            const auto Distance = H.Get_HipDistance(CatchLeg, Swing.Get_Target());
            TestTrue(FString::Printf(TEXT("The catch step keeps its target, clamped within reach (%.2f cm)"), Distance),
                Distance <= H.Get_TargetLimit(CatchLeg) + ReachTolerance);
        }
        Watch.Check(*this, H, TEXT("Catch step"));
    }
    TestTrue(TEXT("The requested catch step swings"), CatchSwingSeen);
    TestEqual(TEXT("No swing target or plant exceeds the reach limit"), Watch.Violations, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitReachJoinsEmergencyTest,
    "Ck.ProceduralAnimation.Gait.ReachJoinsEmergencyAndKeepsInhibition",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitReachJoinsEmergencyTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto SettleAtRest = false;
    constexpr auto ClosedPhaseOffset = 0.25f;
    const auto OverstretchedPlant = FVector{0.0, 88.0, -40.0};
    const auto NearbyIdeal = FVector{0.0, 65.0, -40.0};

    const auto PlantedAfterOneStep = [&](float InReach) -> bool
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        Solver.Reset({OverstretchedPlant});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_PhaseOffset(ClosedPhaseOffset).Set_Hip(FVector::ZeroVector).Set_Reach(InReach).Set_IdealTarget(NearbyIdeal);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        return Outputs[0].Get_Planted();
    };

    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Reset({FVector::ZeroVector});
        TestFalse(TEXT("Precondition: the leg's window is closed"), Solver.IsWindowOpen(ClosedPhaseOffset));
        TestTrue(TEXT("Precondition: the plant is beyond ForceStepFraction of the reach"),
            OverstretchedPlant.Size() > Solver.Get_Settings().Get_Reach().Get_ForceStepFraction() * LegReach);
        TestTrue(TEXT("Precondition: the plant is within a step threshold of its ideal target"),
            FVector::Dist(OverstretchedPlant, NearbyIdeal) < Solver.Get_Settings().Get_Step().Get_Threshold());
    }
    TestTrue(TEXT("Without a reach the overstretched leg holds its plant"), PlantedAfterOneStep(0.0f));
    TestFalse(TEXT("With a reach the overstretched leg steps through its closed window"), PlantedAfterOneStep(LegReach));

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
    const auto SwingingLegPlant = FVector{0.0, -60.0, -40.0};
    const auto InhibitedLegPlant = FVector{0.0, 108.0, -40.0};
    Solver.Reset({SwingingLegPlant, InhibitedLegPlant});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(2);
    Inputs[0].Set_PhaseOffset(0.0f).Set_Hip(FVector{0.0, -20.0, 0.0}).Set_IdealTarget(FVector{100.0, -60.0, -40.0});
    Inputs[1].Set_PhaseOffset(0.5f).Set_Hip(FVector{0.0, 20.0, 0.0}).Set_Reach(LegReach).Set_IdealTarget(FVector{0.0, 85.0, -40.0});
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(2);

    auto FirstLegLanding = int32{INDEX_NONE};
    auto SecondLegLift = int32{INDEX_NONE};
    for (auto Frame = 0; Frame < 60 && SecondLegLift == INDEX_NONE; ++Frame)
    {
        const auto FirstWasSwinging = Solver.GetLegState(0).Get_Swing().Get_Active();
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(TEXT("Both phase groups swung at frame %d: the reach Emergency bypassed inhibition"), Frame));
            return false;
        }
        if (FirstWasSwinging && Outputs[0].Get_Planted() && FirstLegLanding == INDEX_NONE)
        {
            FirstLegLanding = Frame;
        }
        if (NOT Outputs[1].Get_Planted())
        {
            SecondLegLift = Frame;
        }
    }

    if (NOT TestTrue(TEXT("The Emergency leg of the other group lands"), FirstLegLanding != INDEX_NONE))
    {
        return false;
    }
    if (NOT TestTrue(TEXT("The overstretched leg steps once the other group's swing ends"), SecondLegLift != INDEX_NONE))
    {
        return false;
    }
    TestTrue(FString::Printf(TEXT("The overstretched leg waits for the landing (landing frame %d, lift frame %d)"),
            FirstLegLanding, SecondLegLift),
        SecondLegLift > FirstLegLanding && SecondLegLift <= FirstLegLanding + 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitZeroReachKeepsLegacyScheduleTest,
    "Ck.ProceduralAnimation.Gait.ZeroReachKeepsLegacySchedule",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitZeroReachKeepsLegacyScheduleTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    auto Legacy = FReachHarness{};
    InitOverreachingQuadruped(Legacy, 0.0f);
    auto ZeroReach = FReachHarness{};
    InitOverreachingQuadruped(ZeroReach, 0.0f);
    auto WithReach = FReachHarness{};
    InitOverreachingQuadruped(WithReach, LegReach);

    Legacy.Hips.Init(FVector::ZeroVector, Legacy.Hips.Num());

    const auto Velocity = FVector{120.0, 0.0, 0.0};
    Legacy.BodyVelocity = Velocity;
    ZeroReach.BodyVelocity = Velocity;
    WithReach.BodyVelocity = Velocity;

    auto Swings = 0;
    auto ReachChangedOutput = false;
    for (auto Frame = 0; Frame < WalkFrames; ++Frame)
    {
        Legacy.Tick(FrameDt);
        ZeroReach.Tick(FrameDt);
        WithReach.Tick(FrameDt);
        for (auto Leg = 0; Leg < Legacy.Outputs.Num(); ++Leg)
        {
            const auto& Expected = Legacy.Outputs[Leg];
            const auto& Actual = ZeroReach.Outputs[Leg];
            if (NOT Actual.Get_Position().Equals(Expected.Get_Position(), 0.0) || Actual.Get_Planted() != Expected.Get_Planted()
                || Actual.Get_SwingAlpha() != Expected.Get_SwingAlpha())
            {
                AddError(FString::Printf(TEXT("A zero reach with a hip changed leg %d's output at frame %d"), Leg, Frame));
                return false;
            }
            Swings += Expected.Get_Planted() ? 0 : 1;
            ReachChangedOutput |= NOT WithReach.Outputs[Leg].Get_Position().Equals(Expected.Get_Position(), 0.0);
        }
    }

    TestTrue(TEXT("The walk exercised swings"), Swings > 0);
    TestTrue(TEXT("Control: a non-zero reach with the same hips changes the schedule"), ReachChangedOutput);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLandingOnIdealDoesNotRetriggerTest,
    "Ck.ProceduralAnimation.Gait.LandingOnIdealDoesNotRetrigger",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLandingOnIdealDoesNotRetriggerTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto ClosedPhaseOffset = 0.25f;
    constexpr auto OnlyReachIsAnEmergency = 10.0f;
    constexpr auto Frames = 120;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Step().Set_EmergencyFactor(OnlyReachIsAnEmergency);
    const auto Hip = FVector::ZeroVector;
    const auto Ideal = FVector{65.0, 0.0, -40.0};
    Solver.Reset({FVector{-85.0, 0.0, -40.0}});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    Inputs[0].Set_PhaseOffset(ClosedPhaseOffset).Set_Hip(Hip).Set_Reach(LegReach).Set_IdealTarget(Ideal);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    const auto Limit = Solver.Get_Settings().Get_Reach().Get_TargetFraction() * LegReach;
    TestTrue(TEXT("Precondition: the ideal target is within reach"), FVector::Dist(Ideal, Hip) < Limit);

    auto Lifts = 0;
    auto LandingFrame = int32{INDEX_NONE};
    auto WasPlanted = true;
    for (auto Frame = 0; Frame < Frames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        const auto Planted = Outputs[0].Get_Planted();
        if (WasPlanted && NOT Planted)
        {
            ++Lifts;
        }
        if (NOT WasPlanted && Planted && LandingFrame == INDEX_NONE)
        {
            LandingFrame = Frame;
            const auto Distance = FVector::Dist(Outputs[0].Get_Position(), Hip);
            TestTrue(FString::Printf(TEXT("The overshooting stroke lands within reach (%.2f cm from the hip)"), Distance),
                Distance <= Limit + ReachTolerance);
        }
        WasPlanted = Planted;
    }

    if (NOT TestTrue(TEXT("The overstretched leg steps and lands"), LandingFrame != INDEX_NONE))
    {
        return false;
    }
    TestTrue(FString::Printf(TEXT("The landing leaves at least a second of stance to observe (landing frame %d)"), LandingFrame),
        Frames - LandingFrame >= 60);
    TestEqual(TEXT("The landed leg never lifts again while the body stands still"), Lifts, 1);
    TestTrue(TEXT("The leg ends planted"), Outputs[0].Get_Planted());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitInhibitedEmergencyGetsPriorityTest,
    "Ck.ProceduralAnimation.Gait.InhibitedEmergencyGetsPriority",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitInhibitedEmergencyGetsPriorityTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Speed = 200.0;
    constexpr auto MaxLeadCm = 25.0;
    constexpr auto Frames = 600;
    constexpr auto MinLiftsPerLeg = 10;
    constexpr auto MaxStanceCycles = 2.0;

    auto H = FReachHarness{};
    H.Solver.Get_Settings().Get_Cadence().Set_CycleDuration(FCk_Time{1.0}).Set_CadenceSpeedRef(60.0f).Set_MaxSimultaneousSwings(8);
    H.Solver.Get_Settings().Get_Step().Set_Duration(FCk_Time{0.2}).Set_Threshold(20.0f);
    InitCentipede(H);
    H.BodyVelocity = FVector{Speed, 0.0, 0.0};
    H.Lead = FVector{FMath::Min(Speed * H.Solver.Get_Settings().Get_Step().Get_Duration().Get_Seconds(), MaxLeadCm), 0.0, 0.0};

    const auto LegCount = H.Outputs.Num();
    auto Lifts = TArray<int32>{};
    Lifts.Init(0, LegCount);
    auto StanceStart = TArray<double>{};
    StanceStart.Init(0.0, LegCount);
    auto MaxStance = TArray<double>{};
    MaxStance.Init(0.0, LegCount);
    auto WasPlanted = TArray<bool>{};
    WasPlanted.Init(true, LegCount);
    auto MultiGroupFrames = 0;
    auto Time = 0.0;

    for (auto Frame = 0; Frame < Frames; ++Frame)
    {
        if (NOT H.Tick(FrameDt))
        {
            AddError(TEXT("The solver rejected the walk"));
            return false;
        }
        Time += FrameDt.Get_Seconds();

        auto SwingingGroups = TArray<float, TInlineAllocator<4>>{};
        for (auto Leg = 0; Leg < LegCount; ++Leg)
        {
            const auto Planted = H.Outputs[Leg].Get_Planted();
            if (WasPlanted[Leg] && NOT Planted)
            {
                ++Lifts[Leg];
                MaxStance[Leg] = FMath::Max(MaxStance[Leg], Time - StanceStart[Leg]);
            }
            if (NOT WasPlanted[Leg] && Planted)
            {
                StanceStart[Leg] = Time;
            }
            WasPlanted[Leg] = Planted;

            if (NOT Planted)
            {
                const auto Offset = H.Inputs[Leg].Get_PhaseOffset();
                if (NOT SwingingGroups.ContainsByPredicate([Offset](float InOffset) { return FMath::IsNearlyEqual(InOffset, Offset, 1.0e-3f); }))
                {
                    SwingingGroups.Add(Offset);
                }
            }
        }
        MultiGroupFrames += SwingingGroups.Num() >= 2 ? 1 : 0;
    }
    for (auto Leg = 0; Leg < LegCount; ++Leg)
    {
        if (WasPlanted[Leg])
        {
            MaxStance[Leg] = FMath::Max(MaxStance[Leg], Time - StanceStart[Leg]);
        }
    }

    const auto CadenceScale = H.Solver.Get_LastCadenceScale();
    const auto Cycle = H.Solver.Get_Settings().Get_Cadence().Get_CycleDuration().Get_Seconds() / CadenceScale;
    for (auto Leg = 0; Leg < LegCount; ++Leg)
    {
        TestTrue(FString::Printf(TEXT("Leg %d replants (lifted %d times)"), Leg, Lifts[Leg]), Lifts[Leg] >= MinLiftsPerLeg);
        TestTrue(FString::Printf(TEXT("Leg %d's longest stance is below %.0f cycles (%.3f s, %.2f cycles)"),
                Leg, MaxStanceCycles, MaxStance[Leg], MaxStance[Leg] / Cycle),
            MaxStance[Leg] < MaxStanceCycles * Cycle);
    }
    TestEqual(TEXT("Priority never lets two phase groups swing at once"), MultiGroupFrames, 0);

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
