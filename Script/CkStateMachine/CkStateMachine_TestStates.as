// ============================================================================
// STATE MACHINE TEST STATES
// ============================================================================

// Three simple states that cycle visually: Idle -> Patrol -> Alert -> Idle...
// The graph is built from the initial state onward. Each state declares its
// own outgoing transition in DoDefineState.

// ============================================================================

UCLASS()
class UCk_SmTest_Condition_AfterDelay : UCk_SmCondition_EntityScript
{
    default _ConditionMode = ECk_SmConditionMode::EventDriven;
    default _ResetBehavior = ECk_SmConditionResetBehavior::Manual;

    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 2.0f;

    UPROPERTY(EditAnywhere)
    float32 RetryDelayWhilePaused = 0.25f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        System::SetTimer(this, n"TryMarkSatisfied", DelaySeconds, false);
    }

    UFUNCTION()
    private void TryMarkSatisfied()
    {
        auto OwnerSm = DoGet_OwnerStateMachine();
        if (!ck::IsValid(OwnerSm))
        {
            return;
        }

        if (OwnerSm.Get_RunStatus() == ECk_SmRunStatus::Paused)
        {
            System::SetTimer(this, n"TryMarkSatisfied", RetryDelayWhilePaused, false);
            return;
        }

        MarkSatisfied();
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_State_Patrol);
        DoAddCondition(Trans, UCk_SmTest_Condition_AfterDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("SM Test: Entered IDLE", n"SmTest", 3.0f, FLinearColor::Blue);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
        ck::Trace("SM Test: Exited IDLE", n"SmTest", 1.0f);
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_State_Patrol : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_State_Alert);
        DoAddCondition(Trans, UCk_SmTest_Condition_AfterDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("SM Test: Entered PATROL", n"SmTest", 3.0f, FLinearColor::Green);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
        ck::Trace("SM Test: Exited PATROL", n"SmTest", 1.0f);
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_State_Alert : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_State_Idle);
        DoAddCondition(Trans, UCk_SmTest_Condition_AfterDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("SM Test: Entered ALERT", n"SmTest", 3.0f, FLinearColor::Red);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
        ck::Trace("SM Test: Exited ALERT", n"SmTest", 1.0f);
    }
};

// ============================================================================
