// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: DIVERGENCE FIRST-BRANCH REGRESSION
//============================================================================
//
// Headless port of the DivergenceFirstBranch gym station. Spawns the
// existing gym driver actor (which sets up the SM, runs Pass A and Pass B,
// and snapshots per-pass counters), waits for the second pass to complete,
// and asserts on the snapshotted counter values.
//
// What this catches:
//   In a sub-SM, a state with multiple outgoing transitions whose first-
//   added branch happens to be the chosen one constructs the chosen
//   target-state task chain TWICE. Side-effecting tasks fire twice on a
//   single traversal. The bug tracks AddTransition order — swap the order
//   and the doubling follows the new first-added branch.
//
// Pass criteria:
//   Pass A (AddLeftFirst + ChooseLeft):
//     Each task fires exactly once per traversal:
//       Enter=1, Idle=1, Branch=1, Left=1, Right=0, Finish=1
//     Bug signal: Left=2 (first-added branch counter doubled).
//
//   Pass B (AddRightFirst + ChooseRight):
//     Each task fires exactly once:
//       Enter=1, Idle=1, Branch=1, Left=0, Right=1, Finish=1
//     Bug signal: Right=2.
//
// Pattern B (settle-timer poll). The gym driver runs both passes back-to-
// back via a 0.3s timer per pass; we wait 1.0s (~3 PIE frames + buffer)
// and then read the snapshot fields. The cube + text visuals on the gym
// actor are irrelevant to the assertion — they just briefly appear in PIE
// and get torn down with the world.
//============================================================================

class UCk_AutoTest_StateMachine_DivergenceFirstBranch : UCk_AutoTest_Base
{
    // Gym runs two passes back-to-back at 1.5s each (now measured AFTER the async
    // entity-spawn hop completes, ~0.5s per pass), plus assertion-eval buffer.
    // Total: 2 * (0.5 + 1.5) = 4.0s + buffer → outer settle 5.0s, timeout 7.0s.
    default _TimeoutSeconds = 7.0f;

    private ACk_SmTest_DivergenceFirstBranch_GymActor _GymActor;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Spawn deferred so we can null out the StationHandle (no
        // BP_DemoDisplay panel exists in this test map) before BeginPlay
        // wires it up. The gym actor's display path no-ops on an invalid
        // station handle.
        auto Deferred = true;
        _GymActor = Cast<ACk_SmTest_DivergenceFirstBranch_GymActor>(
            SpawnActor(
                ACk_SmTest_DivergenceFirstBranch_GymActor,
                FVector(0.0f, 0.0f, 0.0f),
                FRotator::ZeroRotator,
                NAME_None,
                Deferred));

        if (!ck::IsValid(_GymActor))
        {
            FinishFailure("SpawnActor returned invalid gym actor");
            return;
        }

        _GymActor.StationHandle = FCk_Handle();
        FinishSpawningActor(_GymActor);

        // Settle timer — gym uses PerPassSettleSeconds=1.5f per pass (now measured
        // after the async entity-spawn hop), so each pass takes ~2s. Two passes
        // need ~4s; 5s gives buffer for verify timer + assertion eval.
        auto LocalHandle = InHandle;
        auto SettleParams = FCk_Timer_Spec(FCk_Time(5.0f));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(LocalHandle, SettleParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!ck::IsValid(_GymActor))
        {
            FinishFailure("Gym actor was destroyed before settle");
            return;
        }

        // Pass A — AddLeftFirst + PaymentLeft -> Enter -> Idle -> Branch -> Left -> Finish.
        Assert_Equals_Int(_GymActor.Snap_A_Enter,  1, "Pass A: Enter task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Idle,   1, "Pass A: Idle task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Branch, 1, "Pass A: Branch task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Left,   1, "Pass A: Left task fires exactly once (bug doubles to 2)");
        Assert_Equals_Int(_GymActor.Snap_A_Right,  0, "Pass A: Right task does NOT fire (not chosen)");
        Assert_Equals_Int(_GymActor.Snap_A_Finish, 1, "Pass A: Finish task fires exactly once");

        // Pass B — AddRightFirst + PaymentRight -> Enter -> Idle -> Branch -> Right -> Finish.
        Assert_Equals_Int(_GymActor.Snap_B_Enter,  1, "Pass B: Enter task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Idle,   1, "Pass B: Idle task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Branch, 1, "Pass B: Branch task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Left,   0, "Pass B: Left task does NOT fire (not chosen)");
        Assert_Equals_Int(_GymActor.Snap_B_Right,  1, "Pass B: Right task fires exactly once (bug doubles to 2)");
        Assert_Equals_Int(_GymActor.Snap_B_Finish, 1, "Pass B: Finish task fires exactly once");

        FinishSuccess();
    }
}
