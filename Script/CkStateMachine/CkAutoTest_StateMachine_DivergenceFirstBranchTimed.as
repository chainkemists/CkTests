// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: DIVERGENCE FIRST-BRANCH (TIMED)
//============================================================================
//
// Headless port of the DivergenceFirstBranchTimed gym station — same shape
// as the non-timed variant but the divergence transitions are gated by
// short timer-based event conditions (~0.05s per hop) instead of vacuous
// transitions. The two together cover both fast-path (vacuous Pass on
// first evaluation) and timed-path (Pass after a delayed event) divergence
// handling.
//
// What this catches:
//   The same first-added-branch task-doubling bug as the non-timed test,
//   but exercised through the event-driven condition code path. A bug that
//   only surfaces in one of the two paths shows up as an asymmetric
//   pass/fail across this test and the non-timed variant.
//
// Pass criteria are identical to the non-timed test — every counter equals
// exactly 1 across both passes; the bug doubles whichever branch was
// first-added-and-chosen.
//
// Settle window: 1.5s per pass × 2 = 3s minimum. Timeout 5s gives buffer.
//============================================================================

class UCk_AutoTest_StateMachine_DivergenceFirstBranchTimed : UCk_AutoTest_Base
{
    private ACk_SmTest_DivergenceTimed_GymActor _GymActor;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Deferred = true;
        _GymActor = Cast<ACk_SmTest_DivergenceTimed_GymActor>(
            SpawnActor(
                ACk_SmTest_DivergenceTimed_GymActor,
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

        // Settle: PerPassSettleSeconds=1.5 × 2 passes + buffer.
        auto LocalHandle = InHandle;
        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.5f));
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
        Assert_Equals_Int(_GymActor.Snap_A_Enter,  1, "Pass A (timed): Enter task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Idle,   1, "Pass A (timed): Idle task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Branch, 1, "Pass A (timed): Branch task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Left,   1, "Pass A (timed): Left task fires exactly once (bug doubles to 2)");
        Assert_Equals_Int(_GymActor.Snap_A_Right,  0, "Pass A (timed): Right task does NOT fire (not chosen)");
        Assert_Equals_Int(_GymActor.Snap_A_Finish, 1, "Pass A (timed): Finish task fires exactly once");

        // Pass B — AddRightFirst + PaymentRight -> Enter -> Idle -> Branch -> Right -> Finish.
        Assert_Equals_Int(_GymActor.Snap_B_Enter,  1, "Pass B (timed): Enter task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Idle,   1, "Pass B (timed): Idle task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Branch, 1, "Pass B (timed): Branch task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Left,   0, "Pass B (timed): Left task does NOT fire (not chosen)");
        Assert_Equals_Int(_GymActor.Snap_B_Right,  1, "Pass B (timed): Right task fires exactly once (bug doubles to 2)");
        Assert_Equals_Int(_GymActor.Snap_B_Finish, 1, "Pass B (timed): Finish task fires exactly once");

        FinishSuccess();
    }
}
