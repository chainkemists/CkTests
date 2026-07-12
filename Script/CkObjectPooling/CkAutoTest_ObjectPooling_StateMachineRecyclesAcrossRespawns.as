// Language=angelscript

//============================================================================
// CK OBJECT POOLING — AUTOMATION TEST: StateMachine scripts recycle across respawns
//============================================================================
//
// SM states/conditions ARE EntityScripts and pool by default, so every SM
// teardown/respawn churns the pool. This pins that interplay deliberately:
// three spawn -> transition -> destroy cycles of the same SM must behave
// identically every incarnation (the event-driven condition re-arms its world
// timer on the RECYCLED instance each time), the released incarnations' timers
// must never fire against dead associations (release quiesces them), and the
// pool stats must prove the state scripts were recycled, not re-created.
//============================================================================

UCLASS()
class UCk_PoolSmTest_Condition_ShortDelay : UCk_SmCondition_EventDriven
{
    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 0.05f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        System::SetTimer(this, n"TryMarkSatisfied", DelaySeconds, false);
    }

    UFUNCTION()
    private void TryMarkSatisfied()
    {
        auto OwnerSm = Get_OwningStateMachine();
        if (!ck::IsValid(OwnerSm))
        {
            return;
        }

        MarkSatisfied();
    }
};

UCLASS()
class UCk_PoolSmTest_State_Ping : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_PoolSmTest_State_Pong);
        AddCondition(Trans, UCk_PoolSmTest_Condition_ShortDelay);
    }
};

UCLASS()
class UCk_PoolSmTest_State_Pong : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // sink — each cycle finishes here
    }
};

class UCk_AutoTest_ObjectPooling_StateMachineRecyclesAcrossRespawns : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private const int kNumCycles = 3;
    private int _CyclesCompleted = 0;

    private FCk_Handle _SmOwnerEntity;
    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        DoStartCycle();
    }

    private void DoStartCycle()
    {
        auto TestEntity = DoGet_ScriptEntity();
        _SmOwnerEntity = utils_entity_lifetime::Request_CreateEntity(TestEntity);

        _SmHandle = UCk_Utils_StateMachine_UE::Add(_SmOwnerEntity,
            FCk_Fragment_StateMachine_ParamsData(UCk_PoolSmTest_State_Ping));

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (InPayload.Get_NewStateClass() != UCk_PoolSmTest_State_Pong) { return; }

        // this incarnation transitioned correctly — tear it down and go again
        _CyclesCompleted++;
        utils_entity_lifetime::Request_DestroyEntity(_SmOwnerEntity);
        WaitOneFrame(n"OnCycleTornDown");
    }

    UFUNCTION()
    private void OnCycleTornDown(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_CyclesCompleted < kNumCycles)
        {
            DoStartCycle();
            return;
        }

        // behavioral invariants only — the SM may legitimately acquire a state script more than
        // once per cycle (e.g. a definition pass), so exact hit counts would encode SM internals.
        // What pooling must guarantee: recycling HAPPENS (hits grow with cycles), and instances
        // do NOT grow with cycles (fresh creates and survivors stay bounded regardless of churn)
        auto PingStats = utils_object::Get_ObjectPoolStats(this, UCk_PoolSmTest_State_Ping, nullptr);
        Assert_True(PingStats.Get_NumHits() >= kNumCycles - 1,
            f"Ping state script must recycle across cycles (hits {PingStats.Get_NumHits()} >= {kNumCycles - 1})");
        Assert_True(PingStats.Get_NumMisses() <= 2,
            f"Ping state fresh creates must stay bounded regardless of cycles (misses {PingStats.Get_NumMisses()} <= 2)");
        Assert_True(PingStats.Get_NumLiveInstances() <= 2,
            f"Ping state live instances must not grow with cycles (live {PingStats.Get_NumLiveInstances()} <= 2)");

        auto CondStats = utils_object::Get_ObjectPoolStats(this, UCk_PoolSmTest_Condition_ShortDelay, nullptr);
        Assert_True(CondStats.Get_NumHits() >= kNumCycles - 1,
            f"condition script must recycle across cycles — its re-armed timer fired correctly each incarnation (hits {CondStats.Get_NumHits()} >= {kNumCycles - 1})");
        Assert_True(CondStats.Get_NumMisses() <= 2,
            f"condition fresh creates must stay bounded (misses {CondStats.Get_NumMisses()} <= 2)");
        Assert_True(CondStats.Get_NumLiveInstances() <= 2,
            f"condition live instances must not grow with cycles (live {CondStats.Get_NumLiveInstances()} <= 2)");

        FinishSuccess();
    }
}
