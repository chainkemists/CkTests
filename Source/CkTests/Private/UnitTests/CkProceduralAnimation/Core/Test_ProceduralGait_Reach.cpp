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

            // The targets are geometry with no ground under them, so the solver holds them to the target reach; a trusted target
            // within the force-step reach would be left where it is.
            constexpr auto NoValidatedGround = false;
            auto Initial = TArray<FVector>{};
            for (auto Index = 0; Index < Hips.Num(); ++Index)
            {
                Initial.Add(BodyPosition + Targets[Index]);
                Inputs[Index].Set_PhaseOffset(InPhaseOffsets[Index]).Set_Reach(InReach).Set_TargetTrusted(NoValidatedGround);
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

    struct FCentipedeLayout
    {
        TArray<FVector> Hips;
        TArray<FVector> Rests;
        TArray<float> PhaseOffsets;
    };

    // The centipede layout: sixteen 100 cm legs in four phase groups a quarter cycle apart, each right leg half a cycle
    // behind its left.
    auto
        MakeCentipedeLayout()
        -> FCentipedeLayout
    {
        auto Layout = FCentipedeLayout{};
        for (auto Pair = 0; Pair < 8; ++Pair)
        {
            const auto HipX = 105.0 - 30.0 * Pair;
            for (auto SideIndex = 0; SideIndex < 2; ++SideIndex)
            {
                const auto Side = SideIndex == 0 ? -1.0 : 1.0;
                Layout.Hips.Add(FVector{HipX, Side * 24.0, 0.0});
                Layout.Rests.Add(FVector{HipX, Side * 75.0, -45.0});
                Layout.PhaseOffsets.Add(FMath::Frac((Pair % 4) * 0.25f + (SideIndex == 0 ? 0.0f : 0.5f)));
            }
        }
        return Layout;
    }

    auto
        InitCentipede(
            FReachHarness& InOutHarness)
        -> void
    {
        const auto Layout = MakeCentipedeLayout();
        InOutHarness.Init(Layout.Hips, Layout.Rests, Layout.PhaseOffsets, LegReach);
    }

    // The gym centipede's timing: a 1 s cycle at a cadence reference of 60 cm/s, 0.2 s steps and the ECS swing budget for
    // sixteen legs.
    auto
        ApplyCentipedeGait(
            ck::FProceduralGaitSolver& InOutSolver)
        -> void
    {
        InOutSolver.Get_Settings().Get_Cadence().Set_CycleDuration(FCk_Time{1.0}).Set_CadenceSpeedRef(60.0f).Set_MaxSimultaneousSwings(8);
        InOutSolver.Get_Settings().Get_Step().Set_Duration(FCk_Time{0.2});
    }

    // The tentacled walker's layout: six 144 cm legs on a 34.6 cm hip ring, resting 100.7 cm out and 55 cm down, in two
    // alternating phase groups.
    auto
        MakeTentacledLayout()
        -> FCentipedeLayout
    {
        auto Layout = FCentipedeLayout{};
        for (auto Leg = 0; Leg < 6; ++Leg)
        {
            const auto Angle = FMath::DegreesToRadians(30.0 + 60.0 * Leg);
            const auto Radial = FVector{FMath::Cos(Angle), FMath::Sin(Angle), 0.0};
            Layout.Hips.Add(Radial * 34.64);
            Layout.Rests.Add(Radial * 100.7 + FVector{0.0, 0.0, -55.0});
            Layout.PhaseOffsets.Add(Leg % 2 == 0 ? 0.0f : 0.5f);
        }
        return Layout;
    }

    // The gym tentacled walker's timing: a 1.1 s cycle at the default cadence reference, 0.35 s steps, a 35 cm threshold and
    // the ECS swing budget for six legs.
    auto
        ApplyTentacledGait(
            ck::FProceduralGaitSolver& InOutSolver)
        -> void
    {
        InOutSolver.Get_Settings().Get_Cadence().Set_CycleDuration(FCk_Time{1.1}).Set_CadenceSpeedRef(120.0f).Set_MaxSimultaneousSwings(3);
        InOutSolver.Get_Settings().Get_Step().Set_Duration(FCk_Time{0.35}).Set_Threshold(35.0f);
    }

    auto
        Get_SwingingGroups(
            const ck::FProceduralGaitSolver& InSolver,
            TArrayView<const ck::FProceduralGaitLegInput> InInputs)
        -> int32
    {
        auto Groups = TArray<float, TInlineAllocator<8>>{};
        for (auto Leg = 0; Leg < InInputs.Num(); ++Leg)
        {
            if (NOT InSolver.GetLegState(Leg).Get_Swing().Get_Active())
            { continue; }

            const auto Offset = InInputs[Leg].Get_PhaseOffset();
            if (NOT Groups.ContainsByPredicate([Offset](float InOffset) { return FMath::IsNearlyEqual(InOffset, Offset, 1.0e-3f); }))
            { Groups.Add(Offset); }
        }
        return Groups.Num();
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
    ApplyCentipedeGait(H.Solver);
    H.Solver.Get_Settings().Get_Step().Set_Threshold(20.0f);
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

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitYawRateIgnoresTiltStepsTest,
    "Ck.ProceduralAnimation.Gait.YawRateIgnoresTiltSteps",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitYawRateIgnoresTiltStepsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto TurnDegreesPerSecond = 90.0;
    constexpr auto TiltFrames = 30;
    constexpr auto TiltStepDegrees = 4.0;
    constexpr auto CornerDegrees = 50.0;
    constexpr auto TurnFrames = 60;
    constexpr auto StillTolerance = 1.0e-3;
    constexpr auto SettledTolerance = 0.01;
    constexpr auto FirstFrameMaxShare = 0.2;

    const auto TurnRate = FMath::DegreesToRadians(TurnDegreesPerSecond);
    const auto TiltAxis = FVector{1.0, 1.0, 0.0}.GetSafeNormal();
    const auto TurnStep = [&](double InDirection) { return FQuat{FVector::UpVector, InDirection * TurnRate * FrameDt.Get_Seconds()}; };

    auto Tracker = ck::FProceduralGaitYawRateTracker{};
    auto Basis = FQuat{FVector::UpVector, FMath::DegreesToRadians(30.0)};
    auto WorstTiltRate = 0.0;
    for (auto Frame = 0; Frame <= TiltFrames; ++Frame)
    {
        const auto TiltDegrees = Frame == TiltFrames ? CornerDegrees : TiltStepDegrees;
        const auto Tilted = (Basis * FQuat{TiltAxis, FMath::DegreesToRadians(TiltDegrees)}).GetNormalized();
        WorstTiltRate = FMath::Max(WorstTiltRate, static_cast<double>(FMath::Abs(Tracker.Update(Basis, Tilted, FrameDt))));
        Basis = Tilted;
    }
    TestTrue(FString::Printf(TEXT("Tilt steps of %.0f degrees and a %.0f degree corner about a horizontal body axis read as no turn "
        "(worst %.5f rad/s)"), TiltStepDegrees, CornerDegrees, WorstTiltRate), WorstTiltRate <= StillTolerance);

    const auto FirstTurnRate = Tracker.Update(Basis, (Basis * TurnStep(1.0)).GetNormalized(), FrameDt);
    Basis = (Basis * TurnStep(1.0)).GetNormalized();
    TestTrue(FString::Printf(TEXT("The rate is low-passed: the first turning frame reads %.4f of %.4f rad/s"), FirstTurnRate, TurnRate),
        FirstTurnRate > 0.0f && FirstTurnRate <= FirstFrameMaxShare * TurnRate);

    for (auto Frame = 1; Frame < TurnFrames; ++Frame)
    {
        const auto Turned = (Basis * TurnStep(1.0)).GetNormalized();
        Tracker.Update(Basis, Turned, FrameDt);
        Basis = Turned;
    }
    TestTrue(FString::Printf(TEXT("A steady turn settles on its rate within %.0f %% after %d frames (%.4f of %.4f rad/s)"),
        SettledTolerance * 100.0, TurnFrames, Tracker.GetYawRate(), TurnRate),
        FMath::Abs(Tracker.GetYawRate() - TurnRate) <= SettledTolerance * TurnRate);

    for (auto Frame = 0; Frame < TurnFrames; ++Frame)
    {
        const auto TiltedAndTurned = (Basis * (FQuat{TiltAxis, FMath::DegreesToRadians(TiltStepDegrees)} * TurnStep(1.0))).GetNormalized();
        Tracker.Update(Basis, TiltedAndTurned, FrameDt);
        Basis = TiltedAndTurned;
    }
    TestTrue(FString::Printf(TEXT("A turn that tilts every frame reads the turn alone (%.4f of %.4f rad/s)"), Tracker.GetYawRate(), TurnRate),
        FMath::Abs(Tracker.GetYawRate() - TurnRate) <= SettledTolerance * TurnRate);

    for (auto Frame = 0; Frame < 2 * TurnFrames; ++Frame)
    {
        const auto Turned = (Basis * TurnStep(-1.0)).GetNormalized();
        Tracker.Update(Basis, Turned, FrameDt);
        Basis = Turned;
    }
    TestTrue(FString::Printf(TEXT("A turn the other way reads a negative rate (%.4f of %.4f rad/s)"), Tracker.GetYawRate(), -TurnRate),
        FMath::Abs(Tracker.GetYawRate() + TurnRate) <= SettledTolerance * TurnRate);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSpinInPlaceKeepsFeetWithinReachTest,
    "Ck.ProceduralAnimation.Gait.SpinInPlaceKeepsFeetWithinReach",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSpinInPlaceKeepsFeetWithinReachTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto SpinDegreesPerSecond = 90.0;
    constexpr auto SpinFrames = 360;
    constexpr auto WarmUpFrames = 60;
    // The gym centipede's max velocity lead, which bounds the whole lead, turn included.
    constexpr auto MaxLead = 40.0f;
    // The solver's worst planted reach in this spin is 1.08 chain lengths.
    constexpr auto MaxPlantedReachOverChain = 1.2;
    constexpr auto MaxBeyondChainFraction = 0.01;

    const auto Layout = MakeCentipedeLayout();
    const auto LegCount = Layout.Hips.Num();
    auto MeanFootRadius = 0.0;
    for (const auto& Rest : Layout.Rests)
    { MeanFootRadius += FVector{Rest.X, Rest.Y, 0.0}.Size() / LegCount; }

    for (const auto Direction : {1.0, -1.0})
    {
        auto Solver = ck::FProceduralGaitSolver{};
        ApplyCentipedeGait(Solver);
        Solver.Get_Settings().Get_Step().Set_Threshold(25.0f);
        Solver.Reset(Layout.Rests);
        const auto LeadTime = Solver.Get_Settings().Get_Step().Get_Duration();
        const auto TargetLimit = Solver.Get_Settings().Get_Reach().Get_TargetFraction() * LegReach;

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(LegCount);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(LegCount);
        for (auto Leg = 0; Leg < LegCount; ++Leg)
        { Inputs[Leg].Set_PhaseOffset(Layout.PhaseOffsets[Leg]).Set_Reach(LegReach); }

        auto Tracker = ck::FProceduralGaitYawRateTracker{};
        auto PreviousBasis = FQuat::Identity;
        auto WorstReach = 0.0;
        auto PlantedSamples = 0;
        auto BeyondChain = 0;
        auto BeyondForceStep = 0;
        for (auto Frame = 1; Frame <= SpinFrames; ++Frame)
        {
            const auto Basis = FQuat{FVector::UpVector,
                FMath::DegreesToRadians(Direction * SpinDegreesPerSecond) * FrameDt.Get_Seconds() * Frame};
            const auto YawRate = Tracker.Update(PreviousBasis, Basis, FrameDt);
            PreviousBasis = Basis;

            for (auto Leg = 0; Leg < LegCount; ++Leg)
            {
                const auto Hip = Basis.RotateVector(Layout.Hips[Leg]);
                const auto Query = ck::FProceduralGaitSolver::ComputeLeadQuery(Basis.RotateVector(Layout.Rests[Leg]), FVector::ZeroVector,
                    FVector::ZeroVector, FVector::UpVector, YawRate, LeadTime, MaxLead);
                Inputs[Leg].Set_Hip(Hip).Set_IdealTarget(ck::FProceduralGaitSolver::ClampToReach(Hip, Query, TargetLimit));
            }

            const auto CadenceSpeed = static_cast<float>(FMath::Abs(YawRate) * MeanFootRadius);
            if (NOT Solver.Step(FrameDt, CadenceSpeed, FVector::ZeroVector, Inputs, Outputs))
            {
                AddError(TEXT("The solver rejected the spin"));
                return false;
            }
            if (Frame <= WarmUpFrames)
            { continue; }

            for (auto Leg = 0; Leg < LegCount; ++Leg)
            {
                if (NOT Outputs[Leg].Get_Planted())
                { continue; }

                const auto Reach = FVector::Dist(Outputs[Leg].Get_Position(), Inputs[Leg].Get_Hip()) / LegReach;
                WorstReach = FMath::Max(WorstReach, Reach);
                ++PlantedSamples;
                BeyondChain += Reach > 1.0 ? 1 : 0;
                BeyondForceStep += Reach > Solver.Get_Settings().Get_Reach().Get_ForceStepFraction() ? 1 : 0;
            }
        }

        const auto BeyondChainFraction = static_cast<double>(BeyondChain) / FMath::Max(PlantedSamples, 1);
        AddInfo(FString::Printf(TEXT("Spinning at %+.0f deg/s: worst planted reach %.3f chain lengths, %.4f of planted samples beyond "
            "the chain, %.4f beyond the force-step reach"), Direction * SpinDegreesPerSecond, WorstReach, BeyondChainFraction,
            static_cast<double>(BeyondForceStep) / FMath::Max(PlantedSamples, 1)));
        TestTrue(FString::Printf(TEXT("Spinning at %+.0f deg/s, every planted foot stays within %.2f chain lengths of its hip (worst %.3f)"),
            Direction * SpinDegreesPerSecond, MaxPlantedReachOverChain, WorstReach), WorstReach <= MaxPlantedReachOverChain);
        TestTrue(FString::Printf(TEXT("Spinning at %+.0f deg/s, fewer than %.0f %% of planted samples lie beyond the chain (%.4f)"),
            Direction * SpinDegreesPerSecond, MaxBeyondChainFraction * 100.0, BeyondChainFraction), BeyondChainFraction < MaxBeyondChainFraction);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLandingLiftsOntoLandingGroundTest,
    "Ck.ProceduralAnimation.Gait.LandingLiftsOntoGroundUnderTheLandingPoint",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLandingLiftsOntoLandingGroundTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto LowerTreadZ = -45.0;
    constexpr auto UpperTreadZ = -25.0;
    constexpr auto UnreachableGroundZ = 60.0;
    constexpr auto BelowTheTargetZ = -60.0;
    constexpr auto Frames = 60;
    constexpr auto Tolerance = 0.01;
    constexpr auto MinInFlightLift = 1.0;
    // The default 0.25 s swing advances a fifteenth of its phase per frame, so a swing past this phase lands next frame.
    constexpr auto LastSwingFramePhase = 0.9f;
    // A rise of three quarters of the touchdown net: a touchdown-only report of it still lifts the plant.
    constexpr auto ShareOfTheSafetyNet = 0.75;

    const auto DefaultSettings = ck::FProceduralGaitSettings{};
    const auto SafetyNet = DefaultSettings.Get_Reach().Get_TouchdownLiftFraction() * DefaultSettings.Get_Swing().Get_Height();
    const auto WithinTheSafetyNetZ = LowerTreadZ + ShareOfTheSafetyNet * SafetyNet;

    struct FLanding
    {
        bool SawFreeze = false;
        bool Landed = false;
        FVector LandingPoint = FVector::ZeroVector;
        FVector CommittedLandingPoint = FVector::ZeroVector;
        FVector BeforePlant = FVector::ZeroVector;
        FVector Plant = FVector::ZeroVector;
        TArray<double> SwingHeights;
        int32 MissedLifts = 0;
        bool LiftedBeforeFreeze = false;
        bool TookOff = false;
        FVector TakeOffLandingPoint = FVector::ZeroVector;
        FVector TakeOffTarget = FVector::ZeroVector;
    };

    constexpr auto FromTheFirstSwingFrame = 0;
    constexpr auto FromTheFreeze = 1;
    constexpr auto OnlyBeforeTouchdown = 2;

    // One leg steps from behind its hip to a target on the lower tread. From its first swing frame, from the retarget freeze
    // or only on its last swing frame, it is told the ground under its landing point, one frame late, as the ECS probe
    // tells it. The target is the ideal's geometry, not ground the gait validated (the ground is what the probe reports),
    // so the input marks it untrusted, as the gait marks such a target.
    const auto DoStep = [&](TOptional<double> InLandingGroundZ, int32 InReportFrom) -> FLanding
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Reset({FVector{-30.0, 60.0, LowerTreadZ}});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(FVector{30.0, 60.0, LowerTreadZ})
            .Set_TargetTrusted(false);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto Landing = FLanding{};
        auto WasPlanted = true;
        auto Previous = FVector::ZeroVector;
        for (auto Frame = 0; Frame < Frames && NOT Landing.Landed; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            const auto Position = Outputs[0].Get_Position();
            if (NOT WasPlanted && Outputs[0].Get_Planted())
            {
                Landing.Landed = true;
                Landing.BeforePlant = Previous;
                Landing.Plant = Position;
            }
            else if (NOT Outputs[0].Get_Planted())
            { Landing.SwingHeights.Add(Position.Z); }
            WasPlanted = Outputs[0].Get_Planted();
            Previous = Position;

            const auto& Swing = Solver.GetLegState(0).Get_Swing();
            if (NOT Swing.Get_Active())
            { continue; }

            if (NOT Landing.TookOff)
            {
                Landing.TookOff = true;
                Landing.TakeOffLandingPoint = Swing.Get_LandingPoint();
                Landing.TakeOffTarget = Swing.Get_Target();
            }
            Landing.CommittedLandingPoint = Swing.Get_CommittedLandingPoint();
            Landing.LiftedBeforeFreeze |= NOT Swing.Get_TargetFrozen() && Swing.Get_LandingLiftStartAlpha() >= 0.0f;
            if (Swing.Get_TargetFrozen())
            {
                Landing.SawFreeze = true;
                Landing.LandingPoint = Swing.Get_LandingPoint();
            }
            const auto Reports = InReportFrom == FromTheFirstSwingFrame
                || (InReportFrom == FromTheFreeze && Swing.Get_TargetFrozen())
                || (InReportFrom == OnlyBeforeTouchdown && Swing.Get_Phase() > LastSwingFramePhase);
            if (InLandingGroundZ.IsSet() && Reports)
            {
                Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::Found)
                    .Set_LandingGroundZ(static_cast<float>(InLandingGroundZ.GetValue()));
            }
        }
        Landing.MissedLifts = Solver.Get_MissedLandingLifts();
        return Landing;
    };

    const auto Unknown = DoStep({}, FromTheFreeze);
    if (NOT TestTrue(TEXT("Precondition: the swing freezes its target and lands"), Unknown.SawFreeze && Unknown.Landed))
    { return false; }
    TestTrue(FString::Printf(TEXT("On the take-off frame the exposed landing point is the swing target the ECS probes next frame "
        "(%s against %s)"), *Unknown.TakeOffLandingPoint.ToString(), *Unknown.TakeOffTarget.ToString()),
        Unknown.TookOff && Unknown.TakeOffLandingPoint.Equals(Unknown.TakeOffTarget, Tolerance));
    TestTrue(FString::Printf(TEXT("The exposed landing point is where the swing lands (%s against %s)"), *Unknown.LandingPoint.ToString(),
        *Unknown.Plant.ToString()), Unknown.LandingPoint.Equals(Unknown.Plant, Tolerance));
    TestEqual(TEXT("With no landing ground the foot plants on the lower tread"), Unknown.Plant.Z, LowerTreadZ, Tolerance);

    const auto OnUpperTread = DoStep(UpperTreadZ, FromTheFreeze);
    TestTrue(TEXT("Precondition: the lifted swing lands"), OnUpperTread.Landed);
    TestEqual(TEXT("Ground under the landing point lifts the plant onto the upper tread"), OnUpperTread.Plant.Z, UpperTreadZ, Tolerance);
    TestTrue(TEXT("The lift keeps the landing point's planar position"),
        FVector2D{OnUpperTread.Plant}.Equals(FVector2D{Unknown.LandingPoint}, Tolerance));
    auto InFlightLift = 0.0;
    for (auto Index = 0; Index < FMath::Min(OnUpperTread.SwingHeights.Num(), Unknown.SwingHeights.Num()); ++Index)
    { InFlightLift = FMath::Max(InFlightLift, OnUpperTread.SwingHeights[Index] - Unknown.SwingHeights[Index]); }
    TestTrue(FString::Printf(TEXT("The swing rises toward the upper tread before touchdown (by up to %.2f cm)"), InFlightLift),
        InFlightLift > MinInFlightLift);
    const auto OrdinaryTouchdownStep = FVector::Distance(Unknown.Plant, Unknown.BeforePlant);
    const auto LiftedTouchdownRise = OnUpperTread.Plant.Z - OnUpperTread.BeforePlant.Z;
    TestTrue(FString::Printf(TEXT("At touchdown the lifted foot rises no more than an ordinary swing moves into its plant (%.2f cm against "
        "%.2f)"), LiftedTouchdownRise, OrdinaryTouchdownStep), LiftedTouchdownRise <= OrdinaryTouchdownStep);
    TestEqual(TEXT("A lift that starts in flight is not a missed lift"), OnUpperTread.MissedLifts, 0);

    const auto Early = DoStep(UpperTreadZ, FromTheFirstSwingFrame);
    TestTrue(TEXT("A report that arrives before the retarget freeze starts the lift before it"), Early.LiftedBeforeFreeze);
    TestEqual(TEXT("A lift begun before the freeze lands on the upper tread"), Early.Plant.Z, UpperTreadZ, Tolerance);

    const auto LateSmall = DoStep(WithinTheSafetyNetZ, OnlyBeforeTouchdown);
    TestEqual(TEXT("Ground reported only at touchdown, within the safety net, lifts the plant onto it"), LateSmall.Plant.Z,
        WithinTheSafetyNetZ, Tolerance);
    TestEqual(TEXT("A lift within the safety net is not a missed lift"), LateSmall.MissedLifts, 0);

    const auto LateLarge = DoStep(UpperTreadZ, OnlyBeforeTouchdown);
    TestEqual(TEXT("Ground reported only at touchdown, beyond the safety net, leaves the plant on the lower tread"), LateLarge.Plant.Z,
        LowerTreadZ, Tolerance);
    TestEqual(TEXT("That touchdown counts one missed lift"), LateLarge.MissedLifts, 1);

    const auto Unreachable = DoStep(UnreachableGroundZ, FromTheFreeze);
    TestEqual(TEXT("Ground whose lifted point is out of reach leaves the plant on the lower tread"), Unreachable.Plant.Z, LowerTreadZ, Tolerance);
    TestEqual(TEXT("Unreachable ground is not a missed lift"), Unreachable.MissedLifts, 0);

    const auto Lower = DoStep(BelowTheTargetZ, FromTheFreeze);
    TestEqual(TEXT("Ground below the landing target never lowers the plant"), Lower.Plant.Z, LowerTreadZ, Tolerance);
    TestTrue(TEXT("Accepted upper ground publishes the point the swing actually plants on"),
        OnUpperTread.CommittedLandingPoint.Equals(OnUpperTread.Plant, Tolerance));
    TestTrue(TEXT("A lower raw report does not lower the committed support point below the accepted target"),
        Lower.CommittedLandingPoint.Equals(Lower.Plant, Tolerance));
    TestTrue(TEXT("An unreachable raw report cannot raise the committed support point"),
        Unreachable.CommittedLandingPoint.Equals(Unreachable.Plant, Tolerance));

    // Stepping down: the foot leaves the upper tread for a target on the lower one, and from its first swing frame on it is
    // told the ground under the landing point the solver exposed on the frame before, as the ECS probe tells it. The riser
    // lies past the world origin, so a stale point (the zero vector a fresh solver holds, or the plant just left) reports the
    // tread the foot is leaving, which lies above the target and within reach. A descending stroke's overshoot carries the
    // landing point below the lower tread, so lifting onto the lower tread is expected; lifting toward the upper one is not.
    {
        constexpr auto RiserX = 10.0;
        const auto GroundUnder = [&](const FVector& InPoint) -> double { return InPoint.X < RiserX ? UpperTreadZ : LowerTreadZ; };

        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Reset({FVector{-30.0, 50.0, UpperTreadZ}});
        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(FVector{25.0, 50.0, LowerTreadZ})
            .Set_TargetTrusted(false);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto WasPlanted = true;
        auto Landed = false;
        auto Plant = FVector::ZeroVector;
        auto HighestLift = -TNumericLimits<double>::Max();
        for (auto Frame = 0; Frame < Frames && NOT Landed; ++Frame)
        {
            const auto& Before = Solver.GetLegState(0).Get_Swing();
            if (Before.Get_Active())
            {
                Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::Found)
                    .Set_LandingGroundZ(static_cast<float>(GroundUnder(Before.Get_LandingPoint())));
            }
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);

            const auto& After = Solver.GetLegState(0).Get_Swing();
            if (After.Get_Active() && After.Get_LandingLiftStartAlpha() >= 0.0f)
            { HighestLift = FMath::Max(HighestLift, After.Get_LiftedLandingPoint().Z); }
            if (NOT WasPlanted && Outputs[0].Get_Planted())
            {
                Landed = true;
                Plant = Outputs[0].Get_Position();
            }
            WasPlanted = Outputs[0].Get_Planted();
        }

        if (TestTrue(TEXT("Precondition: the step-down swing lands"), Landed))
        {
            TestTrue(FString::Printf(TEXT("A step-down swing never lifts toward the tread it left (highest lifted point %.2f, lower tread "
                "%.2f)"), HighestLift, LowerTreadZ), HighestLift <= LowerTreadZ + Tolerance);
            TestEqual(TEXT("The step-down swing plants on the lower tread"), Plant.Z, LowerTreadZ, Tolerance);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitShortSwingLiftsAcrossTheFreezeSnapTest,
    "Ck.ProceduralAnimation.Gait.ShortSwingLiftsWhenTheFreezeSnapCrossesARiser",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitShortSwingLiftsAcrossTheFreezeSnapTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Speed = 180.0;
    constexpr auto LowerTreadZ = -45.0;
    constexpr auto UpperTreadZ = -25.0;
    constexpr auto Frames = 120;
    constexpr auto ShortSwingFrames = 4;
    constexpr auto Tolerance = 0.01;
    // The damped retarget trails the moving ideal by about the speed over the retarget smoothing (13 cm here); the riser sits
    // this far before where the swing lands, behind the snap's landing point and ahead of the lagging one.
    constexpr auto RiserBeforeTheLanding = 6.0;

    struct FSwing
    {
        bool Landed = false;
        int32 SwingFrames = 0;
        FVector Plant = FVector::ZeroVector;
        bool LiftedBeforeTouchdown = false;
        int32 MissedLifts = 0;
    };

    // One leg walks at 180 cm/s with the gym centipede's timing, so its swings last four frames at 60 fps. Only its first
    // swing is followed. With a riser, the ground past it is the upper tread and is reported one frame late under the
    // swing's landing point, as the ECS probe reports it.
    const auto DoWalk = [&](TOptional<double> InRiserX) -> FSwing
    {
        auto Solver = ck::FProceduralGaitSolver{};
        ApplyCentipedeGait(Solver);
        Solver.Get_Settings().Get_Step().Set_Threshold(25.0f);
        const auto Hip = FVector{0.0, 30.0, 0.0};
        const auto Rest = FVector{0.0, 60.0, LowerTreadZ};
        const auto Velocity = FVector{Speed, 0.0, 0.0};
        const auto Lead = Velocity * Solver.Get_Settings().Get_Step().Get_Duration().Get_Seconds();
        Solver.Reset({Rest});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_Reach(LegReach);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto Swing = FSwing{};
        auto Body = FVector::ZeroVector;
        auto WasPlanted = true;
        for (auto Frame = 0; Frame < Frames && NOT Swing.Landed; ++Frame)
        {
            Body += Velocity * FrameDt.Get_Seconds();
            Inputs[0].Set_Hip(Body + Hip).Set_IdealTarget(Body + Rest + Lead);
            Solver.Step(FrameDt, static_cast<float>(Speed), Velocity, Inputs, Outputs);

            const auto Planted = Outputs[0].Get_Planted();
            if (NOT Planted)
            { ++Swing.SwingFrames; }
            if (NOT WasPlanted && Planted)
            {
                Swing.Landed = true;
                Swing.Plant = Outputs[0].Get_Position();
            }
            WasPlanted = Planted;

            const auto& State = Solver.GetLegState(0).Get_Swing();
            if (NOT State.Get_Active())
            { continue; }

            Swing.LiftedBeforeTouchdown |= State.Get_LandingLiftStartAlpha() >= 0.0f;
            if (InRiserX.IsSet())
            {
                const auto PastTheRiser = State.Get_LandingPoint().X > InRiserX.GetValue();
                Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::Found)
                    .Set_LandingGroundZ(static_cast<float>(PastTheRiser ? UpperTreadZ : LowerTreadZ));
            }
        }
        Swing.MissedLifts = Solver.Get_MissedLandingLifts();
        return Swing;
    };

    const auto Reference = DoWalk({});
    if (NOT TestTrue(TEXT("Precondition: the first swing lands"), Reference.Landed))
    { return false; }
    TestEqual(TEXT("Precondition: at 180 cm/s with the centipede's timing the swing lasts four frames"), Reference.SwingFrames,
        ShortSwingFrames);
    TestEqual(TEXT("Precondition: on flat ground the swing plants on the lower tread"), Reference.Plant.Z, LowerTreadZ, Tolerance);

    const auto AcrossTheRiser = DoWalk(Reference.Plant.X - RiserBeforeTheLanding);
    TestTrue(TEXT("The swing whose freeze snap crosses the riser lands"), AcrossTheRiser.Landed);
    TestTrue(TEXT("It starts lifting before touchdown"), AcrossTheRiser.LiftedBeforeTouchdown);
    TestEqual(TEXT("It plants on the upper tread"), AcrossTheRiser.Plant.Z, UpperTreadZ, Tolerance);
    TestEqual(TEXT("No missed lift is counted"), AcrossTheRiser.MissedLifts, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitHardOverstretchStepsBeyondTheScheduleTest,
    "Ck.ProceduralAnimation.Gait.HardOverstretchStepsBeyondThePhaseSchedule",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitHardOverstretchStepsBeyondTheScheduleTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Speed = 180.0;
    constexpr auto ClimbStart = 1.0;
    constexpr auto ClimbHeight = 60.0;
    constexpr auto ClimbDuration = 0.3;
    constexpr auto Clearance = 45.0;
    constexpr auto MaxLead = 40.0;
    constexpr auto ContactGrace = 0.12;
    constexpr auto Frames = 180;
    constexpr auto MaxOverstretchSwings = 2.0;
    constexpr auto MaxSwingingGroups = 2;
    // No planted foot of this climb reaches this fraction (the worst reaches about 1.24 chains), so it runs the schedule alone.
    constexpr auto UnreachedFraction = 1.5f;

    struct FClimb
    {
        double LongestValidOverstretch = 0.0;
        int32 OverChainSamples = 0;
        int32 MostSwingingGroups = 0;
        int32 BeyondScheduleSwings = 0;
        double SwingDuration = 0.0;
        bool Solved = true;
    };

    // The centipede walks at 180 cm/s, then its body rises 60 cm in 0.3 s onto a face whose edge lies one clearance ahead,
    // as at the beam end. The ECS probe is emulated: ground under the clamped query point, re-probed within the target
    // reach, untrusted beyond the force-step reach, and withheld for the contact grace before the leg gathers toward its rest
    // pose. The floor behind the edge lies beyond the force-step reach of the raised hips, so every floor foot's target is
    // withheld for the grace at once, and the gait holds those plants by design; no take-off rule can step them then. Only
    // the time a foot spends beyond its chain with a valid target is the schedule's, so only that time is bounded.
    const auto DoClimb = [&](float InHardOverstretchFraction) -> FClimb
    {
        const auto Layout = MakeCentipedeLayout();
        const auto LegCount = Layout.Hips.Num();
        auto Solver = ck::FProceduralGaitSolver{};
        ApplyCentipedeGait(Solver);
        Solver.Get_Settings().Get_Reach().Set_HardOverstretchFraction(InHardOverstretchFraction);
        Solver.Reset(Layout.Rests);
        const auto TargetLimit = Solver.Get_Settings().Get_Reach().Get_TargetFraction() * LegReach;
        const auto ForceLimit = Solver.Get_Settings().Get_Reach().Get_ForceStepFraction() * LegReach;
        const auto RestDrop = Layout.Rests[0].Z;
        const auto Velocity = FVector{Speed, 0.0, 0.0};
        const auto Lead = FVector{FMath::Min(Speed * Solver.Get_Settings().Get_Step().Get_Duration().Get_Seconds(), MaxLead), 0.0, 0.0};

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(LegCount);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(LegCount);
        for (auto Leg = 0; Leg < LegCount; ++Leg)
        { Inputs[Leg].Set_PhaseOffset(Layout.PhaseOffsets[Leg]).Set_Reach(LegReach); }

        auto Climb = FClimb{};
        auto Missing = TArray<double>{};
        Missing.Init(0.0, LegCount);
        auto ValidOverstretch = TArray<double>{};
        ValidOverstretch.Init(0.0, LegCount);
        auto Body = FVector::ZeroVector;
        auto Edge = TOptional<double>{};
        auto Time = 0.0;
        const auto GroundAt = [&](double InX) -> double
        { return Edge.IsSet() && InX >= Edge.GetValue() ? ClimbHeight + RestDrop : RestDrop; };

        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            const auto Dt = FrameDt.Get_Seconds();
            Time += Dt;
            Body.X += Speed * Dt;
            if (Time >= ClimbStart && NOT Edge.IsSet())
            { Edge = Body.X + Clearance; }
            if (Time >= ClimbStart)
            { Body.Z = FMath::Min(ClimbHeight, ClimbHeight * (Time - ClimbStart) / ClimbDuration); }

            for (auto Leg = 0; Leg < LegCount; ++Leg)
            {
                const auto Hip = Body + Layout.Hips[Leg];
                const auto Query = ck::FProceduralGaitSolver::ClampToReach(Hip, Body + Layout.Rests[Leg] + Lead, TargetLimit);
                auto Hit = FVector{Query.X, Query.Y, GroundAt(Query.X)};
                if (FVector::Dist(Hit, Hip) > TargetLimit)
                {
                    const auto Clamped = ck::FProceduralGaitSolver::ClampToReach(Hip, Hit, TargetLimit);
                    Hit = FVector{Clamped.X, Clamped.Y, GroundAt(Clamped.X)};
                }
                const auto Trusted = FVector::Dist(Hit, Hip) <= ForceLimit;
                Missing[Leg] = Trusted ? 0.0 : FMath::Min(Missing[Leg] + Dt, ContactGrace);

                auto LandingGround = ck::EProceduralGaitLandingGround::Unknown;
                auto LandingGroundZ = 0.0f;
                const auto& Swing = Solver.GetLegState(Leg).Get_Swing();
                if (Swing.Get_Active())
                {
                    const auto& LandingPoint = Swing.Get_LandingPoint();
                    const auto Landing = FVector{LandingPoint.X, LandingPoint.Y, GroundAt(LandingPoint.X)};
                    const auto LandingWithinReach = FVector::Dist(Landing, Hip) <= ForceLimit;
                    LandingGround = LandingWithinReach ? ck::EProceduralGaitLandingGround::Found : ck::EProceduralGaitLandingGround::None;
                    LandingGroundZ = static_cast<float>(Landing.Z);
                }

                Inputs[Leg].Set_Hip(Hip)
                    .Set_IdealTarget(Trusted ? Hit : Query)
                    .Set_TargetTrusted(Trusted)
                    .Set_TargetValid(Trusted || Missing[Leg] >= ContactGrace)
                    .Set_LandingGround(LandingGround)
                    .Set_LandingGroundZ(LandingGroundZ);
            }

            if (NOT Solver.Step(FrameDt, static_cast<float>(Speed), Velocity, Inputs, Outputs))
            {
                Climb.Solved = false;
                return Climb;
            }

            Climb.MostSwingingGroups = FMath::Max(Climb.MostSwingingGroups, Get_SwingingGroups(Solver, Inputs));
            for (auto Leg = 0; Leg < LegCount; ++Leg)
            {
                const auto& State = Solver.GetLegState(Leg);
                const auto TookOff = NOT Outputs[Leg].Get_Planted() && Outputs[Leg].Get_SwingAlpha() == 0.0f;
                Climb.BeyondScheduleSwings += TookOff && State.Get_Swing().Get_BeyondSchedule() ? 1 : 0;

                const auto OverChain = Outputs[Leg].Get_Planted()
                    && FVector::Dist(State.Get_Plant().Get_Position(), Inputs[Leg].Get_Hip()) > LegReach;
                if (NOT OverChain)
                {
                    ValidOverstretch[Leg] = 0.0;
                    continue;
                }
                ++Climb.OverChainSamples;
                if (Inputs[Leg].Get_TargetValid())
                { ValidOverstretch[Leg] += Dt; }
                Climb.LongestValidOverstretch = FMath::Max(Climb.LongestValidOverstretch, ValidOverstretch[Leg]);
            }
        }
        Climb.SwingDuration = Solver.Get_Settings().Get_Step().Get_Duration().Get_Seconds() / Solver.Get_LastCadenceScale();
        return Climb;
    };

    const auto Control = DoClimb(UnreachedFraction);
    const auto WithRule = DoClimb(ck::FProceduralGaitReachSettings{}.Get_HardOverstretchFraction());
    if (NOT TestTrue(TEXT("The solver accepts both climbs"), Control.Solved && WithRule.Solved))
    { return false; }

    const auto Bound = MaxOverstretchSwings * WithRule.SwingDuration + FrameDt.Get_Seconds() * 0.5;
    AddInfo(FString::Printf(TEXT("Climb at the unreached fraction: %d over-chain samples, longest valid-target overstretch %.3f s; at the "
        "default fraction: %d samples, %.3f s, %d swings beyond the schedule"), Control.OverChainSamples, Control.LongestValidOverstretch,
        WithRule.OverChainSamples, WithRule.LongestValidOverstretch, WithRule.BeyondScheduleSwings));

    TestTrue(FString::Printf(TEXT("Control: on the schedule alone a floor foot stays beyond its chain with a valid target for more than "
        "%.0f swing durations (%.3f s against %.3f s)"), MaxOverstretchSwings, Control.LongestValidOverstretch, Bound),
        Control.LongestValidOverstretch > Bound);
    TestEqual(TEXT("Control: no swing begins beyond the schedule at the unreached fraction"), Control.BeyondScheduleSwings, 0);
    TestTrue(FString::Printf(TEXT("Hard-overstretched feet step beyond the phase schedule (%d swings)"), WithRule.BeyondScheduleSwings),
        WithRule.BeyondScheduleSwings > 0);
    TestTrue(FString::Printf(TEXT("No planted foot stays beyond its chain with a valid target for more than %.0f swing durations (%.3f s "
        "against %.3f s)"), MaxOverstretchSwings, WithRule.LongestValidOverstretch, Bound), WithRule.LongestValidOverstretch <= Bound);
    TestTrue(FString::Printf(TEXT("The bypass at least halves the over-chain samples (%d against %d)"), WithRule.OverChainSamples,
        Control.OverChainSamples), 2 * WithRule.OverChainSamples <= Control.OverChainSamples);
    TestTrue(FString::Printf(TEXT("At most %d phase groups ever swing at once (%d)"), MaxSwingingGroups, WithRule.MostSwingingGroups),
        WithRule.MostSwingingGroups <= MaxSwingingGroups);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitStraightWalkStaysOnTheScheduleTest,
    "Ck.ProceduralAnimation.Gait.StraightWalkNeverStepsBeyondTheSchedule",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitStraightWalkStaysOnTheScheduleTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Frames = 600;
    constexpr double Speeds[] = {120.0, 150.0, 180.0, 220.0, 260.0};
    constexpr auto TentacledReach = 144.0f;
    constexpr auto CentipedeMaxLead = 40.0;
    constexpr auto TentacledMaxLead = 35.0;

    struct FSpecies
    {
        const TCHAR* Name = nullptr;
        FCentipedeLayout Layout;
        float Reach = 0.0f;
        double MaxLead = 0.0;
        bool Tentacled = false;
    };
    const FSpecies Species[] =
    {
        FSpecies{TEXT("Centipede"), MakeCentipedeLayout(), LegReach, CentipedeMaxLead, false},
        FSpecies{TEXT("Tentacled"), MakeTentacledLayout(), TentacledReach, TentacledMaxLead, true},
    };

    for (const auto& Walker : Species)
    {
        for (const auto Speed : Speeds)
        {
            const auto LegCount = Walker.Layout.Hips.Num();
            auto Solver = ck::FProceduralGaitSolver{};
            if (Walker.Tentacled)
            { ApplyTentacledGait(Solver); }
            else
            { ApplyCentipedeGait(Solver); }
            Solver.Reset(Walker.Layout.Rests);
            const auto HardLimit = Solver.Get_Settings().Get_Reach().Get_HardOverstretchFraction() * Walker.Reach;
            const auto Velocity = FVector{Speed, 0.0, 0.0};
            const auto Lead = FVector{FMath::Min(Speed * Solver.Get_Settings().Get_Step().Get_Duration().Get_Seconds(), Walker.MaxLead), 0.0, 0.0};

            auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
            Inputs.SetNum(LegCount);
            auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
            Outputs.SetNum(LegCount);
            for (auto Leg = 0; Leg < LegCount; ++Leg)
            { Inputs[Leg].Set_PhaseOffset(Walker.Layout.PhaseOffsets[Leg]).Set_Reach(Walker.Reach); }

            auto Body = FVector::ZeroVector;
            auto BeyondScheduleFrames = 0;
            auto MultiGroupFrames = 0;
            auto Lifts = 0;
            auto WorstReach = 0.0;
            for (auto Frame = 0; Frame < Frames; ++Frame)
            {
                Body += Velocity * FrameDt.Get_Seconds();
                for (auto Leg = 0; Leg < LegCount; ++Leg)
                { Inputs[Leg].Set_Hip(Body + Walker.Layout.Hips[Leg]).Set_IdealTarget(Body + Walker.Layout.Rests[Leg] + Lead); }

                if (NOT Solver.Step(FrameDt, static_cast<float>(Speed), Velocity, Inputs, Outputs))
                {
                    AddError(FString::Printf(TEXT("%s at %.0f cm/s: the solver rejected the walk"), Walker.Name, Speed));
                    return false;
                }

                MultiGroupFrames += Get_SwingingGroups(Solver, Inputs) >= 2 ? 1 : 0;
                for (auto Leg = 0; Leg < LegCount; ++Leg)
                {
                    const auto& State = Solver.GetLegState(Leg);
                    BeyondScheduleFrames += State.Get_Swing().Get_Active() && State.Get_Swing().Get_BeyondSchedule() ? 1 : 0;
                    Lifts += NOT Outputs[Leg].Get_Planted() && Outputs[Leg].Get_SwingAlpha() == 0.0f ? 1 : 0;
                    if (Outputs[Leg].Get_Planted())
                    { WorstReach = FMath::Max(WorstReach, FVector::Dist(State.Get_Plant().Get_Position(), Inputs[Leg].Get_Hip())); }
                }
            }

            TestTrue(FString::Printf(TEXT("%s at %.0f cm/s: the walk steps (%d lifts)"), Walker.Name, Speed, Lifts), Lifts > LegCount);
            TestTrue(FString::Printf(TEXT("%s at %.0f cm/s: no planted foot reaches the hard-overstretch reach (worst %.1f of %.1f cm)"),
                Walker.Name, Speed, WorstReach, HardLimit), WorstReach < HardLimit);
            TestEqual(FString::Printf(TEXT("%s at %.0f cm/s: no swing begins beyond the phase schedule"), Walker.Name, Speed),
                BeyondScheduleFrames, 0);
            TestEqual(FString::Printf(TEXT("%s at %.0f cm/s: no frame has two phase groups swinging"), Walker.Name, Speed),
                MultiGroupFrames, 0);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitOccludedPlantIsAnEmergencyTest,
    "Ck.ProceduralAnimation.Gait.OccludedPlantIsAnEmergency",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitOccludedPlantIsAnEmergencyTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto SettleAtRest = false;
    constexpr auto ClosedPhaseOffset = 0.25f;
    constexpr auto Occluded = true;
    constexpr auto Clear = false;
    constexpr auto ValidTarget = true;
    constexpr auto NoTarget = false;
    constexpr auto Frames = 90;
    const auto Plant = FVector{0.0, 60.0, -40.0};
    const auto NearbyIdeal = FVector{0.0, 65.0, -40.0};

    const auto PlantedAfterOneStep = [&](bool InPlantOccluded, bool InTargetValid) -> bool
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        Solver.Reset({Plant});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_PhaseOffset(ClosedPhaseOffset).Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(NearbyIdeal)
            .Set_TargetValid(InTargetValid).Set_PlantOccluded(InPlantOccluded);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        return Outputs[0].Get_Planted();
    };

    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Reset({Plant});
        TestFalse(TEXT("Precondition: the leg's window is closed"), Solver.IsWindowOpen(ClosedPhaseOffset));
        TestTrue(TEXT("Precondition: the plant is within ForceStepFraction of the reach"),
            Plant.Size() < Solver.Get_Settings().Get_Reach().Get_ForceStepFraction() * LegReach);
        TestTrue(TEXT("Precondition: the plant is within a step threshold of its ideal target"),
            FVector::Dist(Plant, NearbyIdeal) < Solver.Get_Settings().Get_Step().Get_Threshold());
    }
    TestTrue(TEXT("Control: an unoccluded plant holds through its closed window"), PlantedAfterOneStep(Clear, ValidTarget));
    TestFalse(TEXT("An occluded plant with a valid target steps through its closed window"), PlantedAfterOneStep(Occluded, ValidTarget));
    TestTrue(TEXT("An occluded plant without a valid target holds"), PlantedAfterOneStep(Occluded, NoTarget));

    const auto SwingingLegPlant = FVector{0.0, -60.0, -40.0};
    const auto MakeTwoGroupSolver = [&](int32 InMaxSimultaneousSwings, TArray<ck::FProceduralGaitLegInput>& OutInputs)
        -> ck::FProceduralGaitSolver
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(InMaxSimultaneousSwings);
        Solver.Reset({SwingingLegPlant, Plant});

        OutInputs.SetNum(2);
        OutInputs[0].Set_PhaseOffset(0.0f).Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(FVector{30.0, -60.0, -40.0});
        OutInputs[1].Set_PhaseOffset(0.5f).Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(NearbyIdeal);
        return Solver;
    };

    // The occluded leg of the second group steps beyond the schedule while the first group's swing is in flight.
    {
        constexpr auto UnlimitedSwings = 0;
        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        auto Solver = MakeTwoGroupSolver(UnlimitedSwings, Inputs);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(2);

        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT TestTrue(TEXT("Precondition: the first group's leg lifts in its open window"), NOT Outputs[0].Get_Planted() && Outputs[1].Get_Planted()))
        { return false; }

        Inputs[1].Set_PlantOccluded(Occluded);
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        TestTrue(TEXT("Precondition: the first group's swing is still in flight"), Solver.GetLegState(0).Get_Swing().Get_Active());
        TestFalse(TEXT("The occluded leg steps while the other group swings"), Outputs[1].Get_Planted());
        TestTrue(TEXT("Its swing runs beyond the schedule"), Solver.GetLegState(1).Get_Swing().Get_BeyondSchedule());
    }

    // A take-off beyond the schedule needs the swing budget: with none left, the occluded leg waits for the first group's
    // swing, then steps.
    {
        constexpr auto OneSwing = 1;
        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        auto Solver = MakeTwoGroupSolver(OneSwing, Inputs);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(2);

        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT TestTrue(TEXT("Precondition: the first group's leg lifts in its open window"), NOT Outputs[0].Get_Planted() && Outputs[1].Get_Planted()))
        { return false; }

        Inputs[1].Set_PlantOccluded(Occluded);
        auto FirstLegLanding = int32{INDEX_NONE};
        auto OccludedLegLift = int32{INDEX_NONE};
        for (auto Frame = 0; Frame < Frames && OccludedLegLift == INDEX_NONE; ++Frame)
        {
            const auto FirstWasSwinging = Solver.GetLegState(0).Get_Swing().Get_Active();
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
            {
                AddError(FString::Printf(TEXT("Both phase groups swung at frame %d with a budget of one swing"), Frame));
                return false;
            }
            if (FirstWasSwinging && Outputs[0].Get_Planted() && FirstLegLanding == INDEX_NONE)
            { FirstLegLanding = Frame; }
            if (NOT Outputs[1].Get_Planted())
            { OccludedLegLift = Frame; }
        }

        if (NOT TestTrue(TEXT("The first group's swing lands"), FirstLegLanding != INDEX_NONE)
            || NOT TestTrue(TEXT("The occluded leg steps once that swing ends"), OccludedLegLift != INDEX_NONE))
        { return false; }

        TestTrue(FString::Printf(TEXT("The occluded leg steps at the first solve with budget free (landing frame %d, lift frame %d)"),
                FirstLegLanding, OccludedLegLift),
            OccludedLegLift > FirstLegLanding && OccludedLegLift <= FirstLegLanding + 2);
    }

    // An occluded plant counts as ratio 1, so a reach Emergency of another group, whose ratio exceeds 1, keeps priority and
    // steps on the schedule; the occluded plant steps beside it, beyond the schedule.
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        const auto OccludedLegHip = FVector{0.0, -20.0, 0.0};
        const auto OccludedLegPlant = FVector{0.0, -80.0, -40.0};
        const auto StretchedLegHip = FVector{0.0, 20.0, 0.0};
        const auto StretchedDistance = 95.0;
        const auto StretchedLegPlant = StretchedLegHip + FVector{0.0, FMath::Sqrt(FMath::Square(StretchedDistance) - FMath::Square(40.0)), -40.0};
        Solver.Reset({OccludedLegPlant, StretchedLegPlant});

        const auto ForceStepLimit = Solver.Get_Settings().Get_Reach().Get_ForceStepFraction() * LegReach;
        const auto HardLimit = Solver.Get_Settings().Get_Reach().Get_HardOverstretchFraction() * LegReach;
        TestTrue(TEXT("Precondition: the stretched plant is a reach Emergency below the hard overstretch"),
            StretchedDistance > ForceStepLimit && StretchedDistance < HardLimit);

        // The stretched leg's target lies beyond the force-step reach: geometry with no ground under it, since a trusted target
        // there would count as no target.
        constexpr auto NoValidatedGround = false;
        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(2);
        Inputs[0].Set_PhaseOffset(0.0f).Set_Hip(OccludedLegHip).Set_Reach(LegReach)
            .Set_IdealTarget(OccludedLegPlant + FVector{0.0, -2.0, 0.0}).Set_PlantOccluded(Occluded);
        Inputs[1].Set_PhaseOffset(0.5f).Set_Hip(StretchedLegHip).Set_Reach(LegReach)
            .Set_IdealTarget(StretchedLegPlant + FVector{0.0, -2.0, 0.0}).Set_TargetTrusted(NoValidatedGround);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(2);

        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        TestTrue(TEXT("The reach Emergency of the other group keeps priority and steps on the schedule"),
            NOT Outputs[1].Get_Planted() && NOT Solver.GetLegState(1).Get_Swing().Get_BeyondSchedule());
        TestTrue(TEXT("The occluded plant steps beside it, beyond the schedule"),
            NOT Outputs[0].Get_Planted() && Solver.GetLegState(0).Get_Swing().Get_BeyondSchedule());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitFootholdTargetLandsWithoutOvershootTest,
    "Ck.ProceduralAnimation.Gait.FootholdTargetLandsWithoutOvershoot",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitFootholdTargetLandsWithoutOvershootTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto SettleAtRest = false;
    constexpr auto Frames = 120;
    constexpr auto LandingTolerance = 0.01;
    constexpr auto MinControlOvershoot = 5.0;
    constexpr auto OnFoothold = true;
    constexpr auto OnIdeal = false;
    const auto Plant = FVector{0.0, 60.0, -40.0};
    const auto Target = FVector{40.0, 60.0, -40.0};
    const auto BodyVelocity = FVector{100.0, 0.0, 0.0};

    const auto LandingOf = [&](bool InTargetIsFoothold) -> TOptional<FVector>
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        Solver.Reset({Plant});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_PhaseOffset(0.0f).Set_IdealTarget(Target).Set_TargetIsFoothold(InTargetIsFoothold);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto Lifted = false;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted())
            { Lifted = true; }
            else if (Lifted)
            { return Outputs[0].Get_Position(); }
        }
        return {};
    };

    const auto ControlLanding = LandingOf(OnIdeal);
    const auto FootholdLanding = LandingOf(OnFoothold);
    if (NOT TestTrue(TEXT("Both swings land"), ControlLanding.IsSet() && FootholdLanding.IsSet()))
    { return false; }

    const auto ControlOvershoot = FVector::Dist(ControlLanding.GetValue(), Target);
    TestTrue(FString::Printf(TEXT("Control: a swing toward an ideal target lands beyond it by the overshoot and the freeze push (%.2f cm)"),
            ControlOvershoot),
        ControlOvershoot > MinControlOvershoot);

    const auto FootholdMiss = FVector::Dist(FootholdLanding.GetValue(), Target);
    TestTrue(FString::Printf(TEXT("A swing toward a foothold lands on it (%.3f cm off)"), FootholdMiss), FootholdMiss <= LandingTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_reach
{
    // A top whose far edge lies at InEdgeX: a probe under a point on it finds the top, past it nothing.
    auto
        Get_GroundBeforeEdge(
            const FVector& InPoint,
            double InEdgeX,
            double InTopZ)
        -> TPair<ck::EProceduralGaitLandingGround, float>
    {
        constexpr auto EdgeTolerance = 0.5;
        if (InPoint.X <= InEdgeX + EdgeTolerance)
        { return {ck::EProceduralGaitLandingGround::Found, static_cast<float>(InTopZ)}; }

        return {ck::EProceduralGaitLandingGround::None, 0.0f};
    }

    // One swing from a plant toward an ideal target at the far edge of a top, while the body moves on at 100 cm/s, so the
    // stroke overshoot and the freeze push carry an unreported landing past the edge.
    struct FEdgeSwing
    {
        bool Landed = false;
        FVector Plant = FVector::ZeroVector;
        bool PlantTrusted = true;
        TArray<double> DistancesAfterNoGround;
    };

    constexpr auto EdgeReportsNever = 0;
    constexpr auto EdgeReportsFromTheFirstSwingFrame = 1;
    constexpr auto EdgeReportsFromTheFreeze = 2;

    auto
        DoSwing_TowardAnEdge(
            const FVector& InPlant,
            const FVector& InTarget,
            int32 InReportFrom)
        -> FEdgeSwing
    {
        constexpr auto SettleAtRest = false;
        constexpr auto Frames = 120;
        const auto BodyVelocity = FVector{100.0, 0.0, 0.0};

        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        Solver.Reset({InPlant});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_PhaseOffset(0.0f).Set_IdealTarget(InTarget);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto Swing = FEdgeSwing{};
        auto Lifted = false;
        auto NoGroundSeen = false;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs);
            const auto& State = Solver.GetLegState(0);
            if (Outputs[0].Get_Planted())
            {
                if (Lifted)
                {
                    Swing.Landed = true;
                    Swing.Plant = Outputs[0].Get_Position();
                    Swing.PlantTrusted = State.Get_Plant().Get_Trusted();
                    return Swing;
                }
                continue;
            }
            Lifted = true;

            const auto& LandingPoint = State.Get_Swing().Get_LandingPoint();
            if (NoGroundSeen)
            { Swing.DistancesAfterNoGround.Add(FVector::Dist(LandingPoint, InTarget)); }

            const auto Reports = InReportFrom == EdgeReportsFromTheFirstSwingFrame
                || (InReportFrom == EdgeReportsFromTheFreeze && State.Get_Swing().Get_TargetFrozen());
            if (NOT Reports)
            { continue; }

            // The ECS probes under the landing point this solve exposed and tells the next solve.
            const auto Ground = Get_GroundBeforeEdge(LandingPoint, InTarget.X, InTarget.Z);
            Inputs[0].Set_LandingGround(Ground.Key).Set_LandingGroundZ(Ground.Value);
            NoGroundSeen |= Ground.Key == ck::EProceduralGaitLandingGround::None;
        }
        return Swing;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLandingWithoutGroundDropsTheOvershootTest,
    "Ck.ProceduralAnimation.Gait.LandingWithoutGroundDropsTheOvershoot",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLandingWithoutGroundDropsTheOvershootTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto LandingTolerance = 0.1;
    constexpr auto MinControlOvershoot = 5.0;
    const auto Plant = FVector{0.0, 60.0, -40.0};
    const auto Target = FVector{40.0, 60.0, -40.0};

    const auto Control = DoSwing_TowardAnEdge(Plant, Target, EdgeReportsNever);
    const auto Told = DoSwing_TowardAnEdge(Plant, Target, EdgeReportsFromTheFirstSwingFrame);
    if (NOT TestTrue(TEXT("Both swings land"), Control.Landed && Told.Landed))
    { return false; }

    const auto ControlOvershoot = FVector::Dist(Control.Plant, Target);
    TestTrue(FString::Printf(TEXT("Control: told nothing, the swing lands past the target's edge by the overshoot and the freeze push "
        "(%.2f cm)"), ControlOvershoot), ControlOvershoot > MinControlOvershoot);

    const auto Miss = FVector::Dist(Told.Plant, Target);
    TestTrue(FString::Printf(TEXT("Told before its freeze that nothing lies under its landing point, the swing lands on the validated "
        "target (%.3f cm off)"), Miss), Miss <= LandingTolerance);
    TestTrue(TEXT("The ground found under the target at touchdown makes a trusted plant"), Told.PlantTrusted);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLandingWithoutGroundAfterTheFreezePullsBackTest,
    "Ck.ProceduralAnimation.Gait.LandingWithoutGroundAfterTheFreezePullsBack",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLandingWithoutGroundAfterTheFreezePullsBackTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto LandingTolerance = 0.1;
    constexpr auto MonotonicTolerance = 1.0e-4;
    constexpr auto MinOvershootAtTheFreeze = 5.0;
    const auto Plant = FVector{0.0, 60.0, -40.0};
    const auto Target = FVector{40.0, 60.0, -40.0};

    const auto Told = DoSwing_TowardAnEdge(Plant, Target, EdgeReportsFromTheFreeze);
    if (NOT TestTrue(TEXT("The swing lands"), Told.Landed))
    { return false; }
    if (NOT TestTrue(TEXT("Precondition: after the freeze the probe found nothing under the landing point"),
            Told.DistancesAfterNoGround.Num() > 0))
    { return false; }

    TestTrue(FString::Printf(TEXT("Precondition: the frozen landing point lay past the target when nothing was found under it (%.2f cm)"),
        Told.DistancesAfterNoGround[0]), Told.DistancesAfterNoGround[0] > MinOvershootAtTheFreeze);
    for (auto Index = 1; Index < Told.DistancesAfterNoGround.Num(); ++Index)
    {
        if (NOT TestTrue(FString::Printf(TEXT("Frame %d of the pull-back: the landing point moves toward the target (%.3f cm, was %.3f)"),
                Index, Told.DistancesAfterNoGround[Index], Told.DistancesAfterNoGround[Index - 1]),
                Told.DistancesAfterNoGround[Index] <= Told.DistancesAfterNoGround[Index - 1] + MonotonicTolerance))
        { return false; }
    }

    const auto Miss = FVector::Dist(Told.Plant, Target);
    TestTrue(FString::Printf(TEXT("The swing touches down on the validated target (%.3f cm off)"), Miss), Miss <= LandingTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitFoundGroundStillLiftsTest,
    "Ck.ProceduralAnimation.Gait.FoundGroundStillLifts",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitFoundGroundStillLiftsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto LowerTreadZ = -45.0;
    constexpr auto UpperTreadZ = -25.0;
    constexpr auto Frames = 60;
    constexpr auto Tolerance = 0.01;

    // One leg steps from behind its hip to a target on the lower tread and is told, from the retarget freeze on, the upper
    // tread's height under its landing point with the given report.
    const auto PlantZOf = [&](ck::EProceduralGaitLandingGround InReport) -> TOptional<double>
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Reset({FVector{-30.0, 60.0, LowerTreadZ}});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(FVector{30.0, 60.0, LowerTreadZ});
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto Lifted = false;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (Outputs[0].Get_Planted())
            {
                if (Lifted)
                { return Outputs[0].Get_Position().Z; }
                continue;
            }
            Lifted = true;
            if (Solver.GetLegState(0).Get_Swing().Get_TargetFrozen())
            { Inputs[0].Set_LandingGround(InReport).Set_LandingGroundZ(static_cast<float>(UpperTreadZ)); }
        }
        return {};
    };

    const auto OnFoundGround = PlantZOf(ck::EProceduralGaitLandingGround::Found);
    const auto OnUnknownGround = PlantZOf(ck::EProceduralGaitLandingGround::Unknown);
    const auto OnNoGround = PlantZOf(ck::EProceduralGaitLandingGround::None);
    if (NOT TestTrue(TEXT("Every swing lands"), OnFoundGround.IsSet() && OnUnknownGround.IsSet() && OnNoGround.IsSet()))
    { return false; }

    TestEqual(TEXT("Ground Found under the landing point lifts the plant onto the upper tread"), OnFoundGround.GetValue(), UpperTreadZ,
        Tolerance);
    TestEqual(TEXT("The same height reported Unknown lifts nothing"), OnUnknownGround.GetValue(), LowerTreadZ, Tolerance);
    TestEqual(TEXT("The same height reported None lifts nothing"), OnNoGround.GetValue(), LowerTreadZ, Tolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitTrustedTargetIsNotClampedTest,
    "Ck.ProceduralAnimation.Gait.TrustedTargetIsNotClamped",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitTrustedTargetIsNotClampedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Frames = 120;
    constexpr auto Tolerance = 0.01;
    constexpr auto Trusted = true;
    constexpr auto Untrusted = false;
    // One leg on a 100 cm reach, its hip at the origin: target reach 80 cm, force-step reach 92 cm. The plant lies 78.1 cm
    // from the hip; the target 85 cm, beyond the target reach and within the force-step reach; the far target 95 cm.
    const auto Plant = FVector{-30.0, 60.0, -40.0};
    const auto Target = FVector{45.0, 60.0, -40.0};
    const auto FarTarget = FVector{61.8, 60.0, -40.0};
    const auto TargetLimit = static_cast<double>(ck::FProceduralGaitSolver{}.Get_Settings().Get_Reach().Get_TargetFraction() * LegReach);

    // A swing toward InTarget, aimed at a spot the caller validated so neither the overshoot nor the freeze push moves it; from
    // its first swing frame on, the input names InMidSwingTarget instead when one is given.
    const auto LandingOf = [&](const FVector& InTarget, bool InTrusted, TOptional<FVector> InMidSwingTarget) -> TOptional<FVector>
    {
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Reset({Plant});
        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(InTarget).Set_TargetTrusted(InTrusted)
            .Set_TargetIsFoothold(true);
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        auto Lifted = false;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            if (NOT Outputs[0].Get_Planted())
            {
                Lifted = true;
                if (InMidSwingTarget.IsSet())
                { Inputs[0].Set_IdealTarget(InMidSwingTarget.GetValue()); }
                continue;
            }
            if (Lifted)
            { return Outputs[0].Get_Position(); }
        }
        return {};
    };

    const auto TrustedLanding = LandingOf(Target, Trusted, {});
    const auto UntrustedLanding = LandingOf(Target, Untrusted, {});
    const auto FarLanding = LandingOf(Target, Trusted, FarTarget);
    if (NOT TestTrue(TEXT("Every swing lands"), TrustedLanding.IsSet() && UntrustedLanding.IsSet() && FarLanding.IsSet()))
    { return false; }

    TestTrue(FString::Printf(TEXT("A trusted target beyond the target reach and within the force-step reach is landed on (%s against %s)"),
        *TrustedLanding->ToString(), *Target.ToString()), TrustedLanding->Equals(Target, Tolerance));
    TestEqual(TEXT("An untrusted target there is clamped to the target reach"), FVector::Dist(UntrustedLanding.GetValue(), FVector::ZeroVector),
        TargetLimit, Tolerance);
    TestTrue(FString::Printf(TEXT("A trusted target beyond the force-step reach counts as no target: the swing keeps its landing (%s against %s)"),
        *FarLanding->ToString(), *Target.ToString()), FarLanding->Equals(Target, Tolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitPullBackTargetIsFrozenTest,
    "Ck.ProceduralAnimation.Gait.PullBackTargetIsFrozen",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitPullBackTargetIsFrozenTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto SettleAtRest = false;
    constexpr auto Frames = 120;
    constexpr auto Tolerance = 0.1;
    constexpr auto FramesWithTheNewIdeal = 2;
    const auto Plant = FVector{0.0, 60.0, -40.0};
    const auto Target = FVector{40.0, 60.0, -40.0};
    const auto NewIdeal = FVector{70.0, 60.0, -40.0};
    const auto BodyVelocity = FVector{100.0, 0.0, 0.0};

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
    Solver.Reset({Plant});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    Inputs.SetNum(1);
    Inputs[0].Set_PhaseOffset(0.0f).Set_IdealTarget(Target);
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);

    // Once the swing has frozen its target, the ideal moves on for two frames, then the probe under the landing point finds
    // nothing.
    auto FrozenLanding = TOptional<FVector>{};
    auto FramesAfterTheFreeze = 0;
    auto Lifted = false;
    auto Landed = TOptional<FVector>{};
    for (auto Frame = 0; Frame < Frames && NOT Landed.IsSet(); ++Frame)
    {
        Solver.Step(FrameDt, BodyVelocity.Size2D(), BodyVelocity, Inputs, Outputs);
        const auto& Swing = Solver.GetLegState(0).Get_Swing();
        if (Outputs[0].Get_Planted())
        {
            if (Lifted)
            { Landed = Outputs[0].Get_Position(); }
            continue;
        }
        Lifted = true;
        if (NOT Swing.Get_TargetFrozen())
        { continue; }

        if (NOT FrozenLanding.IsSet())
        {
            FrozenLanding = Swing.Get_LandingPoint();
            TestTrue(FString::Printf(TEXT("The freeze captures the target the input named (%s against %s)"), *Swing.Get_ValidatedTarget().ToString(),
                *Target.ToString()), Swing.Get_ValidatedTarget().Equals(Target, Tolerance));
        }
        else if (FramesAfterTheFreeze <= FramesWithTheNewIdeal)
        {
            TestTrue(FString::Printf(TEXT("After the freeze a changed ideal leaves the landing where it was (%s against %s)"),
                *Swing.Get_LandingPoint().ToString(), *FrozenLanding->ToString()), Swing.Get_LandingPoint().Equals(FrozenLanding.GetValue(), Tolerance));
        }
        TestTrue(TEXT("The captured target never follows the input"), Swing.Get_ValidatedTarget().Equals(Target, Tolerance));

        ++FramesAfterTheFreeze;
        Inputs[0].Set_IdealTarget(NewIdeal);
        if (FramesAfterTheFreeze > FramesWithTheNewIdeal)
        { Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::None); }
    }

    if (NOT TestTrue(TEXT("The swing froze its target and landed"), FrozenLanding.IsSet() && Landed.IsSet()))
    { return false; }
    TestTrue(FString::Printf(TEXT("Precondition: the frozen landing lay past the target (%.2f cm)"), FVector::Dist(FrozenLanding.GetValue(), Target)),
        FVector::Dist(FrozenLanding.GetValue(), Target) > 1.0);
    TestTrue(FString::Printf(TEXT("Told nothing lies under its landing, the swing pulls back to the frozen target, not the new ideal (%s)"),
        *Landed->ToString()), Landed->Equals(Target, Tolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_reach
{
    // What the probe under the landing point reports to a displaced swing: nothing, ground at the target's height on every
    // frame, or nothing there from the frame after the freeze on.
    enum class EDisplacedLandingReport : uint8
    {
        None,
        GroundAtTheTarget,
        NoGroundAfterTheFreeze
    };

    // One leg on a 100 cm reach, its hip at the origin (target reach 80 cm, force-step reach 92 cm), planted at InPlant and
    // stepping to a trusted InTarget with ground normal InNormal while the body moves at InVelocity; from its first swing
    // frame on, the input carries InMidSwingNormal when one is given, as a support frame that pitched after take-off would.
    // The swing's first touchdown, and the push the freeze gives it, from the phase the freeze took, before any bound.
    struct FDisplacedLanding
    {
        TOptional<FVector> Landing;
        TOptional<FVector> Push;
    };

    auto
        Get_DisplacedLanding(
            const FVector& InPlant,
            const FVector& InTarget,
            const FVector& InNormal,
            const FVector& InVelocity,
            EDisplacedLandingReport InReport = EDisplacedLandingReport::None,
            bool InOvershoot = true,
            const TOptional<FVector>& InMidSwingNormal = {})
        -> FDisplacedLanding
    {
        constexpr auto SettleAtRest = false;
        constexpr auto Frames = 120;
        auto Solver = ck::FProceduralGaitSolver{};
        Solver.Get_Settings().Get_Settle().Set_AtRest(SettleAtRest);
        if (NOT InOvershoot)
        { Solver.Get_Settings().Get_Step().Set_StrokeOvershootFraction(0.0f); }
        Solver.Reset({InPlant});
        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        Inputs.SetNum(1);
        Inputs[0].Set_Hip(FVector::ZeroVector).Set_Reach(LegReach).Set_IdealTarget(InTarget).Set_GroundNormal(InNormal)
            .Set_TargetTrusted(true);
        if (InReport == EDisplacedLandingReport::GroundAtTheTarget)
        {
            Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::Found)
                .Set_LandingGroundZ(static_cast<float>(InTarget.Z));
        }
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Outputs.SetNum(1);

        // The body speed stays 0 so the cadence does not scale the swing; the push reads the planar velocity alone.
        auto Result = FDisplacedLanding{};
        auto Lifted = false;
        for (auto Frame = 0; Frame < Frames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, InVelocity, Inputs, Outputs);
            const auto& Swing = Solver.GetLegState(0).Get_Swing();
            if (NOT Outputs[0].Get_Planted())
            {
                if (NOT Lifted && InMidSwingNormal.IsSet())
                { Inputs[0].Set_GroundNormal(InMidSwingNormal.GetValue()); }
                Lifted = true;
                if (Swing.Get_TargetFrozen() && NOT Result.Push.IsSet())
                {
                    const auto Remaining = Solver.Get_Settings().Get_Step().Get_Duration().Get_Seconds() * (1.0 - Swing.Get_Phase());
                    Result.Push = InVelocity * Remaining;
                    if (InReport == EDisplacedLandingReport::NoGroundAfterTheFreeze)
                    { Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::None); }
                }
                continue;
            }
            if (Lifted)
            {
                Result.Landing = Outputs[0].Get_Position();
                return Result;
            }
        }
        return Result;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitDisplacementIsClampedThenVerifiedTest,
    "Ck.ProceduralAnimation.Gait.DisplacementIsClampedThenVerified",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitDisplacementIsClampedThenVerifiedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Tolerance = 0.05;
    constexpr auto WithoutOvershoot = false;
    const auto TargetLimit = ck::FProceduralGaitSolver{}.Get_Settings().Get_Reach().Get_TargetFraction() * LegReach;
    // A trusted target at 0.7 of the reach, on the plant's Y and Z, so the push runs along +X; no stroke overshoot, so the
    // push is the only displacement.
    const auto Plant = FVector{-30.0, 40.0, -40.0};
    const auto Target = FVector{FMath::Sqrt(70.0 * 70.0 - 3200.0), 40.0, -40.0};
    const auto Velocity = FVector{450.0, 0.0, 0.0};

    const auto Found = Get_DisplacedLanding(Plant, Target, FVector::UpVector, Velocity, EDisplacedLandingReport::GroundAtTheTarget,
        WithoutOvershoot);
    const auto Missed = Get_DisplacedLanding(Plant, Target, FVector::UpVector, Velocity, EDisplacedLandingReport::NoGroundAfterTheFreeze,
        WithoutOvershoot);
    if (NOT TestTrue(TEXT("Both swings freeze their target and land"), Found.Landing.IsSet() && Found.Push.IsSet()
            && Missed.Landing.IsSet() && Missed.Push.IsSet()))
    { return false; }

    const auto Pushed = Target + Found.Push.GetValue();
    TestTrue(FString::Printf(TEXT("Precondition: the push carries the target to 0.9 of the reach (%.2f cm)"), Pushed.Size()),
        Pushed.Size() >= 0.9 * LegReach);
    const auto Clamped = ck::FProceduralGaitSolver::ClampToReach(FVector::ZeroVector, Pushed, TargetLimit);
    TestTrue(FString::Printf(TEXT("With ground found under the landing point the swing lands at the clamp of the pushed target (%s against %s)"),
        *Found.Landing->ToString(), *Clamped.ToString()), Found.Landing->Equals(Clamped, Tolerance));
    TestTrue(FString::Printf(TEXT("With no ground there after the freeze the swing pulls back and lands on the target (%s against %s)"),
        *Missed.Landing->ToString(), *Target.ToString()), Missed.Landing->Equals(Target, Tolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitFaceTargetGetsNoDisplacementTest,
    "Ck.ProceduralAnimation.Gait.FaceTargetGetsNoDisplacement",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitFaceTargetGetsNoDisplacementTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;

    constexpr auto Tolerance = 0.05;
    // A trusted target on a face whose normal lies across the stroke, within the target reach: level ground there would
    // take the overshoot and the push along +X.
    const auto Plant = FVector{-30.0, 40.0, -40.0};
    const auto Target = FVector{50.0, 40.0, -40.0};
    const auto FaceNormal = FVector{0.0, -1.0, 0.0};
    const auto Velocity = FVector{450.0, 0.0, 0.0};

    const auto Face = Get_DisplacedLanding(Plant, Target, FaceNormal, Velocity);
    const auto Level = Get_DisplacedLanding(Plant, Target, FVector::UpVector, Velocity);
    if (NOT TestTrue(TEXT("Both swings land"), Face.Landing.IsSet() && Level.Landing.IsSet()))
    { return false; }

    TestTrue(FString::Printf(TEXT("Precondition: on level ground the same step is displaced along +X (%s)"), *Level.Landing->ToString()),
        Level.Landing->X > Target.X + 1.0);
    TestTrue(FString::Printf(TEXT("A target on a face is landed on exactly (%s against %s)"), *Face.Landing->ToString(), *Target.ToString()),
        Face.Landing->Equals(Target, Tolerance));

    // The same face target, while the support frame pitches after take-off until the face's normal reads 40 degrees from the
    // support up: the swing classified its target at take-off and keeps it a face.
    constexpr auto PitchedDegrees = 40.0;
    const auto PitchedNormal = FVector{0.0, -FMath::Sin(FMath::DegreesToRadians(PitchedDegrees)), FMath::Cos(FMath::DegreesToRadians(PitchedDegrees))};
    constexpr auto NoReport = EDisplacedLandingReport::None;
    constexpr auto WithOvershoot = true;
    const auto Pitched = Get_DisplacedLanding(Plant, Target, FaceNormal, Velocity, NoReport, WithOvershoot, PitchedNormal);
    if (NOT TestTrue(TEXT("The pitched swing lands"), Pitched.Landing.IsSet()))
    { return false; }
    TestTrue(FString::Printf(TEXT("A face target stays a face for its swing when the frame pitches it below the face angle: landed on "
            "exactly (%s against %s)"), *Pitched.Landing->ToString(), *Target.ToString()),
        Pitched.Landing->Equals(Target, Tolerance));

    return true;
}

// Append before #endif in existing Core/Test_ProceduralGait_Reach.cpp; no production fix is part of this draft.

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitUntrustedPlantRecoversToNearbyGroundTest,
    "Ck.ProceduralAnimation.Gait.UntrustedPlantRecoversToNearbyGround",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitUntrustedPlantRecoversToNearbyGroundTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;
    const auto Initial = TArray<FVector>{{0.0, 30.0, -60.0}, {0.0, -30.0, -60.0}};
    const auto Init = [&](ck::FProceduralGaitSolver& InOutSolver, TArray<ck::FProceduralGaitLegInput>& OutInputs,
        TArray<ck::FProceduralGaitLegOutput>& OutOutputs)
    {
        InOutSolver.Get_Settings().Get_Step().Set_Threshold(50.0f).Set_StrokeOvershootFraction(0.0f);
        InOutSolver.Get_Settings().Get_Settle().Set_AtRest(false);
        InOutSolver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(1);
        InOutSolver.Reset(Initial);
        InOutSolver.SetPlantedPose(0, Initial[0], FVector::UpVector, false);
        OutInputs.SetNum(2);
        OutOutputs.SetNum(2);
        for (auto Index = 0; Index < 2; ++Index)
        {
            OutInputs[Index].Set_Hip(FVector{0.0, Index == 0 ? 20.0 : -20.0, 0.0}).Set_Reach(100.0f)
                .Set_IdealTarget(Initial[Index]).Set_PhaseOffset(Index == 0 ? 0.5f : 0.0f)
                .Set_TargetTrusted(Index != 0).Set_TargetValid(true).Set_TargetIsFoothold(true)
                .Set_LandingGround(ck::EProceduralGaitLandingGround::Found).Set_LandingGroundZ(-60.0f);
        }
        OutInputs[0].Set_IdealTarget(Initial[0] + FVector{10.0, 0.0, 0.0});
    };

    auto Solver = ck::FProceduralGaitSolver{};
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Init(Solver, Inputs, Outputs);
    // An untrusted target is not a contact recovery request, even when geometrically close to the emitted air foot.
    for (auto Frame = 0; Frame < 30; ++Frame)
    {
        TestTrue(TEXT("The guessed target input is accepted"), Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs));
        TestFalse(TEXT("A guessed target does not promote the unsupported plant"), Solver.GetLegState(0).Get_Plant().Get_Trusted());
        TestFalse(TEXT("A guessed target does not start a recovery swing"), Solver.GetLegState(0).Get_Swing().Get_Active());
    }
    Inputs[0].Set_TargetTrusted(true);
    const auto BeforeClock = Solver.GetGaitClock();
    const auto BeforePlant = Solver.GetLegState(0).Get_Plant().Get_Position();
    TestTrue(TEXT("Zero dt accepts the newly validated target without advancing"),
        Solver.Step(FCk_Time{}, 0.0f, FVector::ZeroVector, Inputs, Outputs));
    TestTrue(TEXT("Zero dt does not start recovery or mutate the unsupported plant"),
        NOT Solver.GetLegState(0).Get_Swing().Get_Active() && NOT Solver.GetLegState(0).Get_Plant().Get_Trusted()
        && Solver.GetGaitClock() == BeforeClock && Solver.GetLegState(0).Get_Plant().Get_Position() == BeforePlant);
    auto SawSwing = false;
    auto Recovered = false;
    for (auto Frame = 0; Frame < 90; ++Frame)
    {
        TestTrue(TEXT("Nearby contact recovery step is accepted"), Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs));
        SawSwing |= Solver.GetLegState(0).Get_Swing().Get_Active();
        Recovered |= SawSwing && Outputs[0].Get_Planted() && Solver.GetLegState(0).Get_Plant().Get_Trusted();
    }
    TestTrue(TEXT("A newly validated contact below the normal step threshold requests a real recovery swing"), SawSwing);
    TestTrue(TEXT("The recovery swing lands on the validated target"), Recovered);
    TestTrue(TEXT("Recovery uses the provided target without moving its geometry"),
        Recovered && Solver.GetLegState(0).Get_Plant().Get_Position().Equals(Inputs[0].Get_IdealTarget(), 0.01));

    Init(Solver, Inputs, Outputs);
    Inputs[1].Set_IdealTarget(Initial[1] + FVector{60.0, 0.0, 0.0});
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestTrue(TEXT("Precondition: the trusted neighbor occupies the one-swing budget"),
        Solver.GetLegState(1).Get_Swing().Get_Active()))
    { return false; }
    Inputs[0].Set_TargetTrusted(true);
    SawSwing = false;
    Recovered = false;
    for (auto Frame = 0; Frame < 90; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        const auto Active = static_cast<int32>(Solver.GetLegState(0).Get_Swing().Get_Active())
            + static_cast<int32>(Solver.GetLegState(1).Get_Swing().Get_Active());
        TestTrue(TEXT("Contact recovery does not bypass the authored swing budget"), Active <= 1);
        SawSwing |= Solver.GetLegState(0).Get_Swing().Get_Active();
        Recovered |= SawSwing && Outputs[0].Get_Planted() && Solver.GetLegState(0).Get_Plant().Get_Trusted();
    }
    TestTrue(TEXT("Recovery proceeds after the occupied budget becomes free"), Recovered);

    Init(Solver, Inputs, Outputs);
    Solver.Get_Settings().Get_Step().Set_Threshold(20.0f).Set_StrokeOvershootFraction(0.5f);
    Inputs[0].Set_TargetTrusted(true).Set_TargetIsFoothold(false)
        .Set_IdealTarget(Initial[0] + FVector{40.0, 0.0, 0.0}).Set_PhaseOffset(0.0f);
    const auto RecoveryTarget = Inputs[0].Get_IdealTarget();
    const auto Velocity = FVector{30.0, 0.0, 0.0};
    SawSwing = false;
    Recovered = false;
    for (auto Frame = 0; Frame < 90; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, Velocity, Inputs, Outputs);
        const auto& Swing = Solver.GetLegState(0).Get_Swing();
        if (Swing.Get_Active())
        {
            SawSwing = true;
            TestFalse(TEXT("Recovery does not apply stroke overshoot even above the ordinary threshold"), Swing.Get_Overshoot());
            if (Swing.Get_TargetFrozen())
            {
                TestTrue(TEXT("The recovery freeze does not push a non-foothold contact along velocity"),
                    Swing.Get_Target().Equals(RecoveryTarget, 0.01));
            }
        }
        if (SawSwing && Outputs[0].Get_Planted())
        {
            Recovered = Solver.GetLegState(0).Get_Plant().Get_Trusted();
            break;
        }
    }
    TestTrue(TEXT("A larger-error non-foothold recovery lands on its validated point"), Recovered
        && Solver.GetLegState(0).Get_Plant().Get_Position().Equals(RecoveryTarget, 0.01));

    Init(Solver, Inputs, Outputs);
    Inputs[0].Set_TargetTrusted(true).Set_LandingGround(ck::EProceduralGaitLandingGround::None);
    for (auto Frame = 0; Frame < 45; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        TestFalse(TEXT("Recovery never promotes trust when landing ground is withdrawn"),
            Solver.GetLegState(0).Get_Plant().Get_Trusted());
    }

    Init(Solver, Inputs, Outputs);
    Inputs[0].Set_TargetTrusted(true).Set_Enabled(false);
    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    TestFalse(TEXT("A disabled unsupported leg does not begin contact recovery"), Solver.GetLegState(0).Get_Swing().Get_Active());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitFootReservationPredicateTest,
    "Ck.ProceduralAnimation.Gait.FootReservationPredicate",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitFootReservationPredicateTest::
    RunTest(
        const FString&)
    -> bool
{
    const auto Reservations = TArray<ck::FProceduralFootReservation>{
        {FVector::ZeroVector, 10.0f, 1}, {FVector{100.0, 0.0, 0.0}, 0.0f, 2}};
    TestFalse(TEXT("Positive-radius contacts cannot penetrate a peer reservation"),
        ck::Get_IsProceduralFootContactAvailable(FVector{19.0, 0.0, 0.0}, 10.0f, 0, Reservations));
    TestTrue(TEXT("Tangent contacts are available"),
        ck::Get_IsProceduralFootContactAvailable(FVector{20.0, 0.0, 0.0}, 10.0f, 0, Reservations));
    TestTrue(TEXT("A contact does not obstruct itself"),
        ck::Get_IsProceduralFootContactAvailable(FVector::ZeroVector, 10.0f, 1, Reservations));
    TestTrue(TEXT("Zero radius preserves legacy overlapping targets"),
        ck::Get_IsProceduralFootContactAvailable(FVector::ZeroVector, 0.0f, 0, Reservations));
    TestTrue(TEXT("Zero-radius peers do not reserve"),
        ck::Get_IsProceduralFootContactAvailable(FVector{100.0, 0.0, 0.0}, 10.0f, 0, Reservations));
    TestFalse(TEXT("Negative radius is rejected"),
        ck::Get_IsProceduralFootContactAvailable(FVector::ZeroVector, -1.0f, 0, Reservations));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitFootReservationsProtectCommittedContactsTest,
    "Ck.ProceduralAnimation.Gait.FootReservationsProtectCommittedContacts",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitFootReservationsProtectCommittedContactsTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;
    const auto Initial = TArray<FVector>{{-60.0, 40.0, -60.0}, {60.0, 40.0, -60.0}};
    const auto Shared = FVector{0.0, 40.0, -60.0};
    auto Solver = ck::FProceduralGaitSolver{};
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    const auto Init = [&](float InRadius)
    {
        Solver.Get_Settings().Get_Step().Set_Threshold(10.0f).Set_StrokeOvershootFraction(0.5f);
        Solver.Get_Settings().Get_Settle().Set_AtRest(false);
        Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(2);
        Solver.Reset(Initial);
        Inputs.SetNum(2);
        Outputs.SetNum(2);
        for (auto Index = 0; Index < 2; ++Index)
        {
            Inputs[Index] = ck::FProceduralGaitLegInput{};
            Inputs[Index].Set_Hip(FVector{0.0, Index == 0 ? 20.0 : -20.0, 0.0}).Set_Reach(200.0f)
                .Set_IdealTarget(Shared).Set_PhaseOffset(0.0f).Set_TargetTrusted(true).Set_TargetValid(true)
                .Set_TargetIsFoothold(false).Set_FootContactRadius(InRadius);
        }
    };
    const auto Tick = [&]() { return Solver.Step(FrameDt, 0.0f, FVector{30.0, 0.0, 0.0}, Inputs, Outputs); };
    Init(10.0f);
    TestTrue(TEXT("Reserved contact step is accepted"), Tick());
    if (NOT TestTrue(TEXT("The first same-phase leg reserves the shared landing before its peer"),
        Solver.GetLegState(0).Get_Swing().Get_Active() && NOT Solver.GetLegState(1).Get_Swing().Get_Active()))
    { return false; }
    TestTrue(TEXT("The blocked peer's existing plant is not moved"),
        Solver.GetLegState(1).Get_Plant().Get_Position().Equals(Initial[1], 0.01));
    Inputs[0].Set_IdealTarget(Initial[1]);
    for (auto Frame = 0; Frame < 30; ++Frame)
    {
        Tick();
        const auto& State = Solver.GetLegState(0);
        if (State.Get_Swing().Get_Active())
        {
            TestTrue(TEXT("A retarget onto a trusted peer keeps the admitted landing through freeze"),
                State.Get_Swing().Get_LandingPoint().Equals(Shared, 0.01));
            TestFalse(TEXT("Reserved contacts do not stroke beyond their validated point"), State.Get_Swing().Get_Overshoot());
        }
        TestFalse(TEXT("The peer cannot start toward the occupied committed landing"), Solver.GetLegState(1).Get_Swing().Get_Active());
    }
    TestTrue(TEXT("The first contact lands on its exact admitted point"),
        Solver.GetLegState(0).Get_Plant().Get_Trusted() && Solver.GetLegState(0).Get_Plant().Get_Position().Equals(Shared, 0.01));
    Inputs[0].Set_IdealTarget(Shared);
    Inputs[1].Set_TargetTrusted(false);
    Tick();
    TestFalse(TEXT("An untrusted gather cannot enter a trusted peer reservation"), Solver.GetLegState(1).Get_Swing().Get_Active());
    Inputs[1].Set_TargetTrusted(true).Set_IdealTarget(FVector{0.0, 80.0, -60.0}).Set_PlantCrowded(true);
    auto SawClearSwing = false;
    for (auto Frame = 0; Frame < 60; ++Frame)
    {
        Tick();
        SawClearSwing |= Solver.GetLegState(1).Get_Swing().Get_Active();
        TestTrue(TEXT("Moving the crowded leg does not slide the existing trusted peer"),
            Solver.GetLegState(0).Get_Plant().Get_Position().Equals(Shared, 0.01));
    }
    TestTrue(TEXT("An available replacement permits recovery from the contested target"), SawClearSwing
        && Solver.GetLegState(1).Get_Plant().Get_Trusted()
        && Solver.GetLegState(1).Get_Plant().Get_Position().Equals(Inputs[1].Get_IdealTarget(), 0.01));

    Init(0.0f);
    Tick();
    TestTrue(TEXT("Zero radii preserve simultaneous same-target legacy takeoff"),
        Solver.GetLegState(0).Get_Swing().Get_Active() && Solver.GetLegState(1).Get_Swing().Get_Active());
    const auto Before = Solver.GetLegState(0).Get_Swing().Get_Target();
    Inputs[0].Set_FootContactRadius(-1.0f);
    TestFalse(TEXT("A malformed input radius rejects the entire step"), Tick());
    TestTrue(TEXT("Radius rejection leaves committed state unchanged"), Solver.GetLegState(0).Get_Swing().Get_Target() == Before);

    Init(10.0f);
    Solver.SetPlantedPose(1, FVector{0.0, 40.0, 0.0}, FVector::UpVector, true);
    Inputs[1].Set_IdealTarget(FVector{0.0, 40.0, 0.0});
    Tick();
    Inputs[0].Set_LandingGround(ck::EProceduralGaitLandingGround::Found).Set_LandingGroundZ(0.0f);
    for (auto Frame = 0; Frame < 30; ++Frame)
    {
        Tick();
        if (Solver.GetLegState(0).Get_Swing().Get_Active())
        {
            TestTrue(TEXT("An occupied raised landing leaves the original commitment intact"),
                Solver.GetLegState(0).Get_Swing().Get_LandingLiftStartAlpha() < 0.0f
                && Solver.GetLegState(0).Get_Swing().Get_LandingPoint().Equals(Shared, 0.01));
            TestTrue(TEXT("The shared support/reservation point never promotes the rejected lift report"),
                Solver.GetLegState(0).Get_Swing().Get_CommittedLandingPoint().Equals(Shared, 0.01));
        }
    }
    TestTrue(TEXT("An occupied lift cannot promote an overlapping trusted plant"),
        Solver.GetLegState(0).Get_Plant().Get_Position().Equals(Shared, 0.01));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCommittedLandingFollowsLiftedPullbackTest,
    "Ck.ProceduralAnimation.Gait.CommittedLandingFollowsLiftedPullback",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitCommittedLandingFollowsLiftedPullbackTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_reach;
    const auto Target = FVector{40.0, 60.0, -40.0};
    const auto Velocity = FVector{100.0, 0.0, 0.0};
    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Get_Settle().Set_AtRest(false);
    Solver.Reset({FVector{0.0, 60.0, -40.0}});
    auto Inputs = TArray<ck::FProceduralGaitLegInput>{ck::FProceduralGaitLegInput{}
        .Set_IdealTarget(Target).Set_Hip(FVector::ZeroVector).Set_Reach(200.0f)};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Outputs.SetNum(1);
    auto SawLift = false;
    auto SawPullback = false;
    auto TookOff = false;
    auto Landed = false;
    auto LastCommitted = FVector::ZeroVector;
    auto LargestLiftPlanarDifference = 0.0;
    for (auto Frame = 0; Frame < 120 && NOT Landed; ++Frame)
    {
        Solver.Step(FrameDt, Velocity.Size2D(), Velocity, Inputs, Outputs);
        const auto& Swing = Solver.GetLegState(0).Get_Swing();
        if (Outputs[0].Get_Planted())
        {
            if (TookOff)
            {
                Landed = true;
                TestTrue(TEXT("The completed pullback lands at the validated XY and the accepted lifted height"),
                    Outputs[0].Get_Position().Equals(FVector{Target.X, Target.Y, -20.0}, 0.01));
            }
            continue;
        }
        TookOff = true;
        LastCommitted = Swing.Get_CommittedLandingPoint();
        SawLift |= Swing.Get_LandingLiftStartAlpha() >= 0.0f;
        SawPullback |= Swing.Get_PullBackStartAlpha() >= 0.0f;
        TestTrue(TEXT("Committed landing retains the current landing XY throughout lift and pullback"),
            FVector2D{LastCommitted}.Equals(FVector2D{Swing.Get_LandingPoint()}, 0.01));
        if (Swing.Get_LandingLiftStartAlpha() >= 0.0f)
        {
            TestEqual(TEXT("A committed lifted landing uses only the accepted lift height"), LastCommitted.Z,
                FMath::Max(Swing.Get_LandingPoint().Z, Swing.Get_LiftedLandingPoint().Z), 0.01);
            LargestLiftPlanarDifference = FMath::Max(LargestLiftPlanarDifference,
                FVector::Dist2D(Swing.Get_LandingPoint(), Swing.Get_LiftedLandingPoint()));
        }
        Inputs[0].Set_LandingGround(Swing.Get_TargetFrozen()
            ? ck::EProceduralGaitLandingGround::None : ck::EProceduralGaitLandingGround::Found)
            .Set_LandingGroundZ(-20.0f);
    }
    TestTrue(TEXT("The real swing lifted, froze, pulled back and landed"), SawLift && SawPullback && Landed);
    TestTrue(TEXT("The lifted swing changed XY away from the retained lift point, exercising the old reservation discrepancy"),
        LargestLiftPlanarDifference > 1.0);
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
