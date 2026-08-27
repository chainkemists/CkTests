// Language=angelscript

//============================================================================
// CK STATE MACHINE - TEST STATES: TRANSITION ORDERING
//============================================================================
//
// Two-state SM (StateA -> StateB) used to verify that, on a transition,
// the OLD state's tasks run DoExitTask BEFORE the NEW state's tasks run
// DoEnterTask.
//
// Each state owns one task. On Enter/Exit, the task appends a tagged
// string to the FCk_Fragment_SmTest_TransitionOrdering fragment hosted
// on the SM owner (= the test entity). The test then inspects the
// recorded Events array.
//
// The transition fires after a short event-driven delay so the test
// only has to wait briefly before asserting.
//============================================================================

struct FCk_Fragment_SmTest_TransitionOrdering
{
    TArray<FString> Events;
}

// ----------------------------------------------------------------------------
// Helper: append an event to the ordering log on the SM owner.
// ----------------------------------------------------------------------------

void Append_OrderingEvent(FCk_Handle_StateMachine& InSm, const FString& InEvent)
{
    if (ck::Is_NOT_Valid(InSm))
    { return; }

    auto AsRaw = InSm.H();
    auto& Log = AsRaw.AddOrGet_Fragment(FCk_Fragment_SmTest_TransitionOrdering);
    Log.Events.Add(InEvent);
}

// ============================================================================
// CONDITION - short event-driven delay to fire the A->B transition
// ============================================================================

UCLASS()
class UCk_SmTest_Ordering_Condition_QuickDelay : UCk_SmCondition_EventDriven
{
    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 0.5f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        System::SetTimer(this, n"OnDelayElapsed", DelaySeconds, false);
    }

    UFUNCTION()
    private void OnDelayElapsed()
    {
        MarkSatisfied();
    }
};

// ============================================================================
// TASKS - record Enter/Exit on the ordering log
// ============================================================================

UCLASS()
class UCk_SmTest_Ordering_Task_A : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sm = Get_OwningStateMachine();
        Append_OrderingEvent(Sm, "EnterTask_A");
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sm = Get_OwningStateMachine();
        Append_OrderingEvent(Sm, "ExitTask_A");
    }
};

UCLASS()
class UCk_SmTest_Ordering_Task_B : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sm = Get_OwningStateMachine();
        Append_OrderingEvent(Sm, "EnterTask_B");
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Sm = Get_OwningStateMachine();
        Append_OrderingEvent(Sm, "ExitTask_B");
    }
};

// ============================================================================
// STATES - A transitions to B via a short event-driven delay; B is terminal
// ============================================================================

UCLASS()
class UCk_SmTest_Ordering_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Ordering_Task_A);
        auto Trans = AddTransition(InHandle, UCk_SmTest_Ordering_State_B);
        AddCondition(Trans, UCk_SmTest_Ordering_Condition_QuickDelay);
    }
};

UCLASS()
class UCk_SmTest_Ordering_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Ordering_Task_B);
    }
};
