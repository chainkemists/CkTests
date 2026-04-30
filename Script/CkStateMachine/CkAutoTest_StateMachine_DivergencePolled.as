// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: DIVERGENCE FIRST-BRANCH (POLLED)
//============================================================================
//
// Polled mirror of CkAutoTest_StateMachine_DivergenceFirstBranchTimed.as.
// Same shape, same dual-pass assertion structure, but every linear hop is
// gated by a polled time-elapsed condition instead of an event-driven timer.
//
// Diagnostic value: lets us compare pump-budget behavior between event-driven
// and polled gating for an otherwise-identical sub-SM topology. If this
// test does NOT trigger the "High pump count this frame" warning while the
// Timed variant does, the cascade is specific to event-driven cascades; if
// both trigger, the cascade is generic to the racing pattern.
//
// Settle window: 1.5s per pass × 2 = 3s minimum. Timeout 5s gives buffer.
//============================================================================

class UCk_AutoTest_StateMachine_DivergencePolled : UCk_AutoTest_Base
{
    private ACk_SmTest_DivergencePolled_GymActor _GymActor;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Deferred = true;
        _GymActor = Cast<ACk_SmTest_DivergencePolled_GymActor>(
            SpawnActor(
                ACk_SmTest_DivergencePolled_GymActor,
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
        Assert_Equals_Int(_GymActor.Snap_A_Enter,  1, "Pass A (polled): Enter task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Idle,   1, "Pass A (polled): Idle task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Branch, 1, "Pass A (polled): Branch task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Left,   1, "Pass A (polled): Left task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_A_Right,  0, "Pass A (polled): Right task does NOT fire (not chosen)");
        Assert_Equals_Int(_GymActor.Snap_A_Finish, 1, "Pass A (polled): Finish task fires exactly once");

        // Pass B — AddRightFirst + PaymentRight -> Enter -> Idle -> Branch -> Right -> Finish.
        Assert_Equals_Int(_GymActor.Snap_B_Enter,  1, "Pass B (polled): Enter task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Idle,   1, "Pass B (polled): Idle task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Branch, 1, "Pass B (polled): Branch task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Left,   0, "Pass B (polled): Left task does NOT fire (not chosen)");
        Assert_Equals_Int(_GymActor.Snap_B_Right,  1, "Pass B (polled): Right task fires exactly once");
        Assert_Equals_Int(_GymActor.Snap_B_Finish, 1, "Pass B (polled): Finish task fires exactly once");

        FinishSuccess();
    }
}

//============================================================================
// Test actor wrapper.
//============================================================================

class ACk_AutoTest_StateMachine_DivergencePolled_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_StateMachine_DivergencePolled;
    default _TimeoutSeconds = 5.0f;
}
