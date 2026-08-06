// Language=angelscript

//============================================================================
// CK CROSS-CUTTING — AUTOMATION TEST: DESTROY OWNER DURING HANDLE REQUESTS
//============================================================================
//
// Destroying an entity while one of its processors has an in-flight request
// queued must not crash. This pattern is the canary for the upcoming refactor
// that turns silent-failure paths into `CK_ENSURE_IF_NOT` — destroy-mid-tick
// is the highest-traffic dead-handle code path in the codebase.
//
// Setup:
//   - Spawn a child owner entity.
//   - Add a Timer to the child (Running, StopOnDone).
//   - Enqueue Request_Pause AND Request_DestroyEntity on the owner SAME FRAME.
//   - Tick several frames.
//
// Pass: no crash; owner handle invalid on next frame; the test harness's
// own tick keeps draining (i.e. the registry is healthy).
//
// Fail: a `CK_ENSURE_IF_NOT` (or assert) fires for the dead-entity write,
// the test times out, or the registry corrupts and the harness can't tick.
//============================================================================

class UCk_AutoTest_CrossCutting_DestroyOwner_DuringHandleRequests_NoCrash : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _Owner;
    private int32 _TickCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Params = FCk_Timer_Spec(FCk_Time(1.0));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_Owner, Params);

        // Enqueue a request that the Timer processor will see, and destroy the
        // owner in the same frame. The Timer's HandleRequests processor must
        // see the queued Pause AFTER the destroy is in flight without crashing.
        utils_timer::Request_Pause(Timer);
        utils_entity_lifetime::Request_DestroyEntity(_Owner);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _TickCount++;
        if (_TickCount < 5) { return; }

        Assert_True(!utils_handle::Get_IsValid(_Owner),
            "Owner entity should be invalid after Request_DestroyEntity was issued same-frame as Request_Pause");
        FinishSuccess();
    }
}
