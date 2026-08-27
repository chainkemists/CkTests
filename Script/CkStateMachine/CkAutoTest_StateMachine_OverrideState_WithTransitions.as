// Language=angelscript

//============================================================================
// CK STATE MACHINE - AUTOMATION TEST: OVERRIDE STATE'S OWN TRANSITIONS ACTIVE
//============================================================================
//
// Extends AddOverrideState_ReplacesBaseState: not only does the override state
// replace the base as the resolved current state, its OWN DefineState graph is
// active - the replacement declares a transition the base never had, and that
// transition drives the SM onward.
//
// Topology: initial=Base (a sink). Override Base with Replacement, which adds a
// vacuous transition to Final. After Start the SM resolves to Replacement and
// then immediately transitions Replacement -> Final.
//
// PASS: the SM reaches Final (proving the override's transitions are wired in).
//============================================================================

UCLASS()
class UCk_SmOvrTransTest_Base : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink - no transitions */ }
};

UCLASS()
class UCk_SmOvrTransTest_Final : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink */ }
};

UCLASS()
class UCk_SmOvrTransTest_Replacement : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // The override adds a transition the base did not have.
        AddTransition(InHandle, UCk_SmOvrTransTest_Final);
    }

    UFUNCTION(BlueprintOverride)
    TArray<FGameplayTag> DoGet_StatesToOverride() const
    {
        auto Tags = TArray<FGameplayTag>();
        Tags.Add(UCk_SmState_EntityScript::Get_StateTagForClass(UCk_SmOvrTransTest_Base));
        return Tags;
    }
};

class UCk_AutoTest_StateMachine_OverrideState_WithTransitions : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto SmParams = FCk_Fragment_StateMachine_ParamsData(UCk_SmOvrTransTest_Base);
        SmParams.Set_AutoStart(ECk_SmAutoStart::Disabled);
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, SmParams);

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        _SmHandle.Request_AddOverrideState(UCk_SmOvrTransTest_Replacement);
        _SmHandle.Request_Start();
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (InHandle.Get_CurrentStateClass() != UCk_SmOvrTransTest_Final) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmOvrTransTest_Final,
            "The override state's own transition should drive the SM to Final");
        FinishSuccess();
    }
}
