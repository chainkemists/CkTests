// Language=angelscript

//============================================================================
// CK STATE MACHINE - AUTOMATION TEST: TASK ExitTask FIRES ON SM STOP
//============================================================================
//
// The existing TransitionOrdering test pins that an EnterExitOnly task's
// ExitTask fires on a *transition* out of its state. This pins the other exit
// path: ExitTask must also fire when the SM is *Stopped* (Request_Stop), so a
// task gets its cleanup hook even when the state is left via stop rather than a
// transition.
//
// Observability uses the same AS-struct-fragment-on-the-SM-owner pattern as
// TransitionOrdering: the task appends "Enter"/"Exit" to a log fragment, the
// test reads it.
//
// Flow: single state with one EnterExitOnly task (sink). After Enter is logged,
// Request_Stop. On OnStopped, assert "Exit" was logged.
//============================================================================

struct FCk_Fragment_SmTaskExitTest_Log
{
    TArray<FString> Events;
}

void Append_TaskExitEvent(FCk_Handle_StateMachine& InSm, const FString& InEvent)
{
    if (ck::Is_NOT_Valid(InSm))
    { return; }

    auto AsRaw = InSm.H();
    auto& Log = AsRaw.AddOrGet_Fragment(FCk_Fragment_SmTaskExitTest_Log);
    Log.Events.Add(InEvent);
}

UCLASS()
class UCk_SmTaskExitTest_Task : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sm = Get_OwningStateMachine();
        Append_TaskExitEvent(Sm, "Enter");
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sm = Get_OwningStateMachine();
        Append_TaskExitEvent(Sm, "Exit");
    }
};

UCLASS()
class UCk_SmTaskExitTest_State : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTaskExitTest_Task); // sink - left only via Stop
    }
};

class UCk_AutoTest_StateMachine_TaskExitOnStop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmTaskExitTest_State));

        FCk_Delegate_Sm_OnStopped Delegate;
        Delegate.BindUFunction(this, n"OnStopped");
        _SmHandle.BindTo_OnStopped(Delegate);

        WaitUntil(n"Check_EnterLogged", n"OnReadyToStop");
    }

    private bool LogContains(const TArray<FString>&in InEvents, const FString&in InWhat) const
    {
        for (auto Index = 0; Index < InEvents.Num(); Index++)
        {
            if (InEvents[Index] == InWhat)
            { return true; }
        }
        return false;
    }

    private bool LoggedEvent(const FString&in InWhat)
    {
        auto AsRaw = _SmHandle.H();
        auto& Log = AsRaw.AddOrGet_Fragment(FCk_Fragment_SmTaskExitTest_Log);
        return LogContains(Log.Events, InWhat);
    }

    // Both waits read exactly what the hop they gate asserts, so a regression that
    // never fires the hook reports as this predicate timing out rather than as an
    // assertion on a state we merely hoped had settled. The log starts empty, so
    // Enter is decisively false on entry.
    UFUNCTION()
    private void Check_EnterLogged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(LoggedEvent("Enter"));
    }

    UFUNCTION()
    private void Check_ExitLogged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(LoggedEvent("Exit"));
    }

    UFUNCTION()
    private void OnReadyToStop(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto AsRaw = _SmHandle.H();
        auto& Log = AsRaw.AddOrGet_Fragment(FCk_Fragment_SmTaskExitTest_Log);
        Assert_True(LogContains(Log.Events, "Enter"),
            "EnterExitOnly task should have logged Enter on initial state entry");

        utils_state_machine::Request_Stop(_SmHandle);
    }

    UFUNCTION()
    private void OnStopped(FCk_Handle_StateMachine InHandle, FCk_Sm_Payload_OnStopped InPayload)
    {
        if (IsFinished()) { return; }
        WaitUntil(n"Check_ExitLogged", n"OnAfterStop");
    }

    UFUNCTION()
    private void OnAfterStop(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto AsRaw = _SmHandle.H();
        auto& Log = AsRaw.AddOrGet_Fragment(FCk_Fragment_SmTaskExitTest_Log);
        Assert_True(LogContains(Log.Events, "Exit"),
            "EnterExitOnly task's ExitTask should fire when the SM is Stopped");
        FinishSuccess();
    }
}
