// ============================================================================
// SM DIVERGENCE FIRST-BRANCH (POLLED) — REGRESSION TEST STATES
// ============================================================================
//
// Polled mirror of CkStateMachine_TestStates_DivergenceFirstBranchTimed.as.
// Same topology and dual-pass structure, but every FastDelay event-driven
// condition is replaced by a "QuickDelay" polled condition whose
// DoEvaluate() returns true once N seconds have elapsed since the condition
// was entered. Lets us observe whether the pump-cost cascade we see in the
// event-driven Timed variant also reproduces under polled-only conditions.
//
// Topology:
//
//     Enter -> Idle -> Branch -+-> Left  -> Finish
//                              `-> Right -/
//
// Each linear transition: gated by QuickDelay (polled time-elapsed).
// Each divergence transition: QuickDelay AND a polled payment-method check.

UENUM()
enum ECk_SmTest_DivergencePolled_PaymentChoice
{
    Left,
    Right,
}

// ============================================================================
// REGISTRY
// ============================================================================

namespace SmDivergencePolled_Regression
{
    void Increment(FName InLabel)
    {
        auto OutActors = TArray<ACk_SmTest_DivergencePolled_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergencePolled_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Increment_Counter(InLabel); }
    }

    bool Get_AddOrderLeftFirst()
    {
        auto OutActors = TArray<ACk_SmTest_DivergencePolled_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergencePolled_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.AddOrderLeftFirst; }
        return true;
    }

    ECk_SmTest_DivergencePolled_PaymentChoice Get_PaymentChoice()
    {
        auto OutActors = TArray<ACk_SmTest_DivergencePolled_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergencePolled_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.PaymentChoice; }
        return ECk_SmTest_DivergencePolled_PaymentChoice::Left;
    }
}

// ============================================================================
// CONDITIONS
// ============================================================================

// Polled time-elapsed gate. Records start time on EnterCondition, and
// DoEvaluate returns true after DelaySeconds have elapsed. This is the
// polled mirror of UCk_SmTest_DivergenceTimed_Condition_FastDelay.
UCLASS()
class UCk_SmTest_DivergencePolled_Condition_QuickDelay : UCk_SmCondition_Polled
{
    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 0.05f;

    private float StartSeconds = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle)
    {
        StartSeconds = utils_time::Get_TimeNow(this).Get_Seconds();
    }

    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        const auto Now = utils_time::Get_TimeNow(this).Get_Seconds();
        return Now - StartSeconds >= DelaySeconds;
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Condition_PaymentIsLeft : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        return SmDivergencePolled_Regression::Get_PaymentChoice()
            == ECk_SmTest_DivergencePolled_PaymentChoice::Left;
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Condition_PaymentIsRight : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        return SmDivergencePolled_Regression::Get_PaymentChoice()
            == ECk_SmTest_DivergencePolled_PaymentChoice::Right;
    }
};

// ============================================================================
// COUNTER TASKS
// ============================================================================

UCLASS()
class UCk_SmTest_DivergencePolled_Task_Enter : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmDivergencePolled_Regression::Increment(n"Enter"); }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Task_Idle : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmDivergencePolled_Regression::Increment(n"Idle"); }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Task_Branch : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmDivergencePolled_Regression::Increment(n"Branch"); }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Task_Left : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmDivergencePolled_Regression::Increment(n"Left"); }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Task_Right : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmDivergencePolled_Regression::Increment(n"Right"); }
};

UCLASS()
class UCk_SmTest_DivergencePolled_Task_Finish : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    {
        SmDivergencePolled_Regression::Increment(n"Finish");

        auto OwningSm = Get_OwningStateMachine();
        if (ck::IsValid(OwningSm))
        { utils_state_machine::Request_Stop(OwningSm); }
    }
};

// ============================================================================
// SUB-SM STATES
// ============================================================================

UCLASS()
class UCk_SmTest_DivergencePolled_State_Enter : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_Task_Enter);

        auto ToIdle = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Idle);
        AddCondition(ToIdle, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_Task_Idle);

        auto ToBranch = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Branch);
        AddCondition(ToBranch, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_State_Branch : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_Task_Branch);

        if (SmDivergencePolled_Regression::Get_AddOrderLeftFirst())
        {
            auto ToLeft = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Left);
            AddCondition(ToLeft, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
            AddCondition(ToLeft, UCk_SmTest_DivergencePolled_Condition_PaymentIsLeft);

            auto ToRight = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Right);
            AddCondition(ToRight, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
            AddCondition(ToRight, UCk_SmTest_DivergencePolled_Condition_PaymentIsRight);
        }
        else
        {
            auto ToRight = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Right);
            AddCondition(ToRight, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
            AddCondition(ToRight, UCk_SmTest_DivergencePolled_Condition_PaymentIsRight);

            auto ToLeft = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Left);
            AddCondition(ToLeft, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
            AddCondition(ToLeft, UCk_SmTest_DivergencePolled_Condition_PaymentIsLeft);
        }
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_State_Left : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_Task_Left);

        auto ToFinish = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Finish);
        AddCondition(ToFinish, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_State_Right : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_Task_Right);

        auto ToFinish = AddTransition(InHandle, UCk_SmTest_DivergencePolled_State_Finish);
        AddCondition(ToFinish, UCk_SmTest_DivergencePolled_Condition_QuickDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergencePolled_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_Task_Finish);
    }
};

// ============================================================================
// SUB-SM WRAPPER
// ============================================================================

UCLASS()
class UCk_SmTest_DivergencePolled_SubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_DivergencePolled_State_Enter;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::SucceedOnStop;
};

UCLASS()
class UCk_SmTest_DivergencePolled_ParentState : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_DivergencePolled_SubSmTask);
    }
};

// ============================================================================
