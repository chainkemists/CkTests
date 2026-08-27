// Language=angelscript

//============================================================================
// CK STATE MACHINE - AUTOMATION TEST: DELAY TASK DESTROYS ITS TIMER
//============================================================================
//
// UCk_SmTask_Delay::EnterTask Adds a fresh timer entity per entry and ExitTask
// only unbinds the done delegate - it never destroys it. Nothing leaks anyway,
// because the timer is a child of the TASK entity and FProcessor_SmState_Exit
// destroys every task entity on state exit, so the lifetime cascade reclaims
// the timer. This test pins that cascade: it is load-bearing, and the only
// thing standing between the Delay task and an unbounded per-entry timer leak.
//
// What this catches if it regresses:
//   - a state exit that stops destroying its task entities
//   - a Delay task that starts parenting its timer somewhere longer-lived
//   - a destroy that fires so early the task's own completion breaks
//
// Shape: one delaying state whose Delay task drives AllSucceeded into a
// terminal state. The task entity is not reachable through the public SM
// Utils surface, so the timer is located by walking the test entity's
// lifetime-dependent subtree; the walk starts at the dependents, which keeps
// the harness's own per-frame step timer (a child of the test entity) out.
//============================================================================

UCLASS()
class UCk_SmDelayTimerLeak_Task : UCk_SmTask_Delay
{
    default _Duration = FCk_Time(0.2f);
};

UCLASS()
class UCk_SmDelayTimerLeak_State_Delaying : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmDelayTimerLeak_Task);
        auto Trans = AddTransition(InHandle, UCk_SmDelayTimerLeak_State_Done);
        AddCondition(Trans, UCk_SmCondition_TaskResults); // default AllSucceeded
    }
};

UCLASS()
class UCk_SmDelayTimerLeak_State_Done : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Terminal sink.
    }
};

class UCk_AutoTest_SmTask_Delay_DestroysTimerOnCompletion : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _TestEntity;
    private FCk_Handle_StateMachine _SmHandle;
    private FCk_Handle_Timer _DelayTimer;
    private bool _ReachedDone = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _TestEntity = InHandle;
        _ReachedDone = false;

        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle,
            FCk_Fragment_StateMachine_ParamsData(UCk_SmDelayTimerLeak_State_Delaying));

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        Add_Step_WaitUntil("delay task entered and armed its timer", n"Check_TimerExists", 600);
        Add_Step("capture the running delay timer", n"Step_CaptureTimer");
        Add_Step_WaitUntil("SM reaches the terminal state", n"Check_ReachedDone", 600);
        Add_Step_WaitFrames("let the deferred destroy drain", 4);
        Add_Step("the task's timer entity must be gone", n"Step_AssertTimerDestroyed");

        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (InPayload.Get_NewStateClass() != UCk_SmDelayTimerLeak_State_Done) { return; }
        _ReachedDone = true;
    }

    UFUNCTION()
    private void Check_TimerExists(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(Find_TimerBelowTestEntity()));
    }

    UFUNCTION()
    private void Step_CaptureTimer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _DelayTimer = Find_TimerBelowTestEntity();

        Assert_True(ck::IsValid(_DelayTimer),
            "sanity: the Delay task's timer entity must be valid while the task is running");
    }

    UFUNCTION()
    private void Check_ReachedDone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ReachedDone);
    }

    UFUNCTION()
    private void Step_AssertTimerDestroyed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_SmHandle.Get_CurrentStateClass() == UCk_SmDelayTimerLeak_State_Done,
            "the Delay task must still drive the SM into its terminal state");

        Assert_True(ck::Is_NOT_Valid(_DelayTimer),
            "a completed Delay task's timer entity must not outlive the task - the state-exit lifetime cascade is what keeps per-entry Delay timers from accumulating");
    }

    // Breadth-first over lifetime dependents, skipping the test entity itself so
    // the harness's own step-tick timer is never a candidate. The only timer
    // owner below the SM in this fixture is the Delay task.
    private FCk_Handle_Timer Find_TimerBelowTestEntity()
    {
        auto Frontier = TArray<FCk_Handle>();
        Frontier.Add(_TestEntity);

        for (int32 Index = 0; Index < Frontier.Num(); ++Index)
        {
            auto Current = Frontier[Index];

            for (auto Dependent : utils_entity_lifetime::Get_LifetimeDependents(Current))
            {
                if (utils_timer::Has_Any(Dependent))
                {
                    auto Timers = utils_timer::ForEach_Timer(Dependent, FInstancedStruct(), FCk_Lambda_InHandle());
                    if (Timers.Num() > 0)
                    { return Timers[0]; }
                }

                Frontier.Add(Dependent);
            }
        }

        return FCk_Handle_Timer();
    }
}
