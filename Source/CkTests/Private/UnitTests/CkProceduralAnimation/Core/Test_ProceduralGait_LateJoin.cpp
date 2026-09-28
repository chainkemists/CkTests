#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_late_join
{
    struct FCase
    {
        ck::FProceduralGaitSolver Solver;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;
        int32 Peer = 1;
        int32 Join = 2;

        explicit
            FCase(
                bool InJoinBeforePeer = false,
                float InDuration = 0.3f)
        {
            Peer = InJoinBeforePeer ? 2 : 1;
            Join = InJoinBeforePeer ? 1 : 2;
            Solver.Get_Settings().Get_Step().Set_Duration(FCk_Time{InDuration}).Set_Threshold(50.0f);
            Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(2).Set_CadenceSpeedRef(100.0f);
            Solver.Get_Settings().Get_Schedule().Set_AdvanceFraction(0.0f);
            Solver.Get_Settings().Get_Settle().Set_AtRest(false);
            Solver.Reset({FVector::ZeroVector, FVector::ZeroVector, FVector::ZeroVector});
            Inputs.SetNum(3);
            Outputs.SetNum(3);
            Inputs[Peer].Set_PhaseOffset(0.5f).Set_IdealTarget(FVector{120.0, 0.0, 0.0});
            Inputs[Join].Set_PhaseOffset(0.5f);
            for (auto& Input : Inputs)
            { Input.Set_TargetIsFoothold(true); }
        }

        auto
            Tick(
                float InSeconds,
                float InCadenceSpeed = 0.0f)
            -> bool
        {
            return Solver.Step(FCk_Time{InSeconds}, 0.0f, FVector::ZeroVector, Inputs, Outputs, false,
                TOptional<float>{InCadenceSpeed});
        }

        auto
            ReserveWaitingGroup()
            -> void
        {
            Inputs[0].Set_IdealTarget(FVector{200.0, 0.0, 0.0});
            Inputs[Join].Set_IdealTarget(FVector{100.0, 0.0, 0.0});
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLateJoinDeadlineTest,
    "Ck.ProceduralAnimation.Gait.LateJoin.DoesNotDelayReservedGroup",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLateJoinDeadlineTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_late_join;
    for (const auto JoinBeforePeer : {false, true})
    {
        for (const auto VaryCadence : {false, true})
        {
            auto Joined = FCase{JoinBeforePeer};
            auto Control = FCase{JoinBeforePeer};
            for (auto* Case : {&Joined, &Control})
            {
                TestTrue(TEXT("The original phase .5 peer takes off"), Case->Tick(0.01f)
                    && Case->Solver.GetLegState(Case->Peer).Get_Swing().Get_Active());
                TestTrue(TEXT("The peer reaches phase .4"), Case->Tick(0.12f)
                    && FMath::IsNearlyEqual(Case->Solver.GetLegState(Case->Peer).Get_Swing().Get_Phase(), 0.4f, 1.0e-4f));
                Case->ReserveWaitingGroup();
            }
            Control.Inputs[Control.Join].Set_TargetValid(false);
            TestTrue(TEXT("The reserved group remains inhibited"), Joined.Tick(0.01f) && Control.Tick(0.01f)
                && Joined.Outputs[0].Get_Planted() && Control.Outputs[0].Get_Planted());
            if (NOT TestTrue(TEXT("The late emergency joins its active scheduled group despite the other group's reservation"),
                Joined.Solver.GetLegState(Joined.Join).Get_Swing().Get_Active()))
            { return false; }

            const auto& Peer = Joined.Solver.GetLegState(Joined.Peer).Get_Swing();
            const auto& Join = Joined.Solver.GetLegState(Joined.Join).Get_Swing();
            TestFalse(TEXT("The join remains scheduled"), Join.Get_BeyondSchedule());
            TestTrue(TEXT("The join uses the peer's post-update remaining duration"),
                FMath::IsNearlyEqual(Join.Get_DurationScale(), Peer.Get_DurationScale() * (1.0f - Peer.Get_Phase()), 1.0e-4f));

            auto PeerLanded = int32{INDEX_NONE};
            auto JoinLanded = int32{INDEX_NONE};
            auto WaiterStarted = int32{INDEX_NONE};
            auto ControlWaiterStarted = int32{INDEX_NONE};
            for (auto Frame = 0; Frame < 80; ++Frame)
            {
                const auto CadenceSpeed = VaryCadence && Frame % 2 == 0 ? 300.0f : 0.0f;
                TestTrue(TEXT("Both schedules accept the elapsed time"), Joined.Tick(0.005f, CadenceSpeed)
                    && Control.Tick(0.005f, CadenceSpeed));
                if (PeerLanded == INDEX_NONE && Joined.Outputs[Joined.Peer].Get_Planted())
                { PeerLanded = Frame; }
                if (JoinLanded == INDEX_NONE && Joined.Outputs[Joined.Join].Get_Planted())
                { JoinLanded = Frame; }
                if (WaiterStarted == INDEX_NONE && NOT Joined.Outputs[0].Get_Planted())
                { WaiterStarted = Frame; }
                if (ControlWaiterStarted == INDEX_NONE && NOT Control.Outputs[0].Get_Planted())
                { ControlWaiterStarted = Frame; }
            }
            TestTrue(TEXT("The joined leg lands no later than its original peer"),
                PeerLanded != INDEX_NONE && JoinLanded != INDEX_NONE && JoinLanded <= PeerLanded);
            TestTrue(TEXT("The reserved group starts after the active group drains"), WaiterStarted > PeerLanded);
            TestTrue(TEXT("Joining does not delay the reserved group against the control"),
                ControlWaiterStarted != INDEX_NONE && WaiterStarted <= ControlWaiterStarted);
        }
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLateJoinAdmissionTest,
    "Ck.ProceduralAnimation.Gait.LateJoin.PreservesLateBudgetAndZeroTimeGuards",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitLateJoinAdmissionTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_late_join;
    auto Late = FCase{};
    Late.Tick(0.01f);
    Late.Tick(0.18f);
    Late.ReserveWaitingGroup();
    TestTrue(TEXT("A join after half of the ordinary swing still yields"), Late.Tick(0.01f)
        && Late.Outputs[Late.Join].Get_Planted());

    auto FullBudget = FCase{};
    FullBudget.Solver.Get_Settings().Get_Cadence().Set_MaxSimultaneousSwings(1);
    FullBudget.Tick(0.01f);
    FullBudget.Tick(0.12f);
    FullBudget.ReserveWaitingGroup();
    TestTrue(TEXT("A reserved emergency join does not bypass the swing budget"), FullBudget.Tick(0.01f)
        && FullBudget.Outputs[FullBudget.Join].Get_Planted());

    auto Paused = FCase{};
    Paused.Tick(0.01f);
    Paused.Tick(0.12f);
    Paused.ReserveWaitingGroup();
    const auto PeerPhase = Paused.Solver.GetLegState(Paused.Peer).Get_Swing().Get_Phase();
    const auto Clock = Paused.Solver.GetGaitClock();
    TestTrue(TEXT("Zero elapsed time starts no join and advances neither peer nor clock"), Paused.Tick(0.0f)
        && Paused.Outputs[Paused.Join].Get_Planted()
        && Paused.Solver.GetLegState(Paused.Peer).Get_Swing().Get_Phase() == PeerPhase
        && Paused.Solver.GetGaitClock() == Clock);

    auto TinyDuration = FCase{false, 0.00001f};
    TinyDuration.Tick(0.000001f);
    TinyDuration.Tick(0.00001f);
    TinyDuration.ReserveWaitingGroup();
    TestTrue(TEXT("The minimum effective swing duration cannot extend a peer's shorter remaining time"),
        TinyDuration.Tick(0.000001f) && TinyDuration.Outputs[TinyDuration.Join].Get_Planted());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
