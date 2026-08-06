// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: ADD-OVERRIDE-STATE REPLACES BASE
//============================================================================
//
// Pins the runtime state-override contract: an SM created with state
// class A as its initial state, but with Request_AddOverrideState(B)
// queued BEFORE Request_Start, will enter B instead of A — B's
// Get_StatesToOverride includes the state tag of A.
//
// The OnStateChanged payload's NewStateClass reports the REQUESTED
// class (A) rather than the resolved class (B); the resolved class is
// available via UCk_Utils_StateMachine_UE::Get_CurrentStateClass after
// the transition lands.
//
// Setup uses ECk_SmAutoStart::Disabled so the Add and AddOverrideState
// requests both land before the Start request — without that ordering
// the override wouldn't apply to the initial state.
//============================================================================

UCLASS()
class UCk_SmTest_Override_Base : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Terminal state (sink). No transitions needed for the override test.
    }
};

UCLASS()
class UCk_SmTest_Override_Replacement : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Terminal state (sink).
    }

    UFUNCTION(BlueprintOverride)
    TArray<FGameplayTag> DoGet_StatesToOverride() const
    {
        auto Tags = TArray<FGameplayTag>();
        Tags.Add(UCk_SmState_EntityScript::Get_StateTagForClass(UCk_SmTest_Override_Base));
        return Tags;
    }
};

class UCk_AutoTest_StateMachine_AddOverrideState_ReplacesBaseState : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Disable AutoStart so Request_AddOverrideState gets processed before
        // the explicit Request_Start that follows.
        auto SmParams = FCk_StateMachine_Spec(UCk_SmTest_Override_Base);
        SmParams.Set_AutoStart(ECk_SmAutoStart::Disabled);
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, SmParams);

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        _SmHandle.Request_AddOverrideState(UCk_SmTest_Override_Replacement);
        _SmHandle.Request_Start();
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }

        // Initial entry — PreviousStateClass is null. The payload's
        // NewStateClass is the REQUESTED initial class (Base); the
        // resolved (overridden) class is exposed via Get_CurrentStateClass.
        auto Resolved = InHandle.Get_CurrentStateClass();
        Assert_True(Resolved == UCk_SmTest_Override_Replacement,
            f"After Request_AddOverrideState + Request_Start, the SM's current state class should be the override (Replacement), not the requested Base");

        FinishSuccess();
    }
}
