// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: PAUSE HALTS, RESUME CONTINUES
//============================================================================
//
// Pins the pause/resume contract: while an SM is Paused its polled-condition
// evaluator does not run, so a transition gated by an always-true polled
// condition cannot fire until the SM is Resumed.
//
// Topology: Idle -> Finish gated by an always-true polled condition.
//   - Add with Disabled auto-start, then Request_Start + Request_Pause in the
//     same frame (Pause only engages on a Running SM, so order matters: the
//     queue drains Running -> Paused).
//   - Across a 0.5s settle the polled condition is never evaluated (paused), so
//     the SM stays in Idle.
//   - On Resume the polled condition evaluates true and drives Idle -> Finish.
//
// PASS: no transition before resume; transition after resume.
//============================================================================

UCLASS()
class UCk_SmPauseTest_Cond_PolledTrue : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return true;
    }
};

UCLASS()
class UCk_SmPauseTest_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink */ }
};

UCLASS()
class UCk_SmPauseTest_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_SmPauseTest_State_Finish);
        AddCondition(Trans, UCk_SmPauseTest_Cond_PolledTrue);
    }
};

class UCk_AutoTest_StateMachine_PauseResume : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _Resumed = false;
    private bool _TransitionedEarly = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        // Disabled auto-start so we control start/pause ordering. Request_Pause only engages on a
        // Running SM (the Pause processor early-returns if not Running), so Start then Pause are
        // enqueued the same frame — the request queue drains in order Running -> Paused.
        auto SmParams = FCk_Fragment_StateMachine_ParamsData(UCk_SmPauseTest_State_Idle);
        SmParams.Set_AutoStart(ECk_SmAutoStart::Disabled);
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, SmParams);

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        _SmHandle.Request_Start();
        _SmHandle.Request_Pause();

        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(LocalHandle, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (InPayload.Get_NewStateClass() != UCk_SmPauseTest_State_Finish) { return; }

        if (!_Resumed)
        {
            _TransitionedEarly = true;
            FinishFailure("SM transitioned to Finish while still Paused — pause must halt the polled evaluator");
            return;
        }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmPauseTest_State_Finish,
            "After Resume the always-true polled condition should drive Idle -> Finish");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_TransitionedEarly == false,
            "No transition should occur while the SM is Paused (settle window elapsed paused)");
        Assert_True(_SmHandle.Get_RunStatus() == ECk_SmRunStatus::Paused,
            "SM should report Paused run-status during the settle window");
        Assert_True(_SmHandle.Get_CurrentStateClass() == UCk_SmPauseTest_State_Idle,
            "SM should still be in Idle after the paused settle window");

        _Resumed = true;
        _SmHandle.Request_Resume();
    }
}
