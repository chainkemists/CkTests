// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: OVERRIDE VIA PARAMS REPLACES BASE
//============================================================================
//
// Pins the params-based (replication-safe) override path: an SM created with
// _OverrideStates set on its PARAMS resolves its initial state to the override
// WITHOUT any runtime Request_AddOverrideState. FProcessor_Sm_Setup registers
// the symmetric override table from params on every machine, BEFORE it enqueues
// AutoStart's Start — so the table is in place before the initial-state resolves.
//
// This is the construct-time analogue of AddOverrideState_ReplacesBaseState. The
// distinguishing detail: this test uses the DEFAULT AutoStart (OnSetup). The
// request-path test needs AutoStart=Disabled + an explicit Start so the override
// REQUEST lands before the Start REQUEST; the params path lifts that ordering
// constraint (Setup registers overrides before it enqueues Start), so OnSetup is
// sufficient — and proving that is the point.
//
// PASS: the resolved current state is the override (Replacement), not Base.
//============================================================================

UCLASS()
class UCk_SmTest_OverrideParams_Base : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Terminal state (sink). No transitions needed for the override test.
    }
};

UCLASS()
class UCk_SmTest_OverrideParams_Replacement : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Terminal state (sink).
    }

    UFUNCTION(BlueprintOverride)
    TArray<FGameplayTag> DoGet_StatesToOverride() const
    {
        auto Tags = TArray<FGameplayTag>();
        Tags.Add(UCk_SmState_EntityScript::Get_StateTagForClass(UCk_SmTest_OverrideParams_Base));
        return Tags;
    }
};

class UCk_AutoTest_StateMachine_OverrideViaParams_ReplacesBaseState : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Register the override through PARAMS — no Request_AddOverrideState. Default
        // AutoStart (OnSetup): Setup builds the override table from params, THEN enqueues
        // Start, so the initial-state resolution downstream sees the override.
        auto SmParams = FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_OverrideParams_Base);

        auto OverrideStates = TArray<TSubclassOf<UCk_SmState_EntityScript>>();
        OverrideStates.Add(UCk_SmTest_OverrideParams_Replacement);
        SmParams.Set_OverrideStates(OverrideStates);

        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, SmParams);

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

        // Initial entry — the payload's NewStateClass is the REQUESTED initial class
        // (Base); the resolved (overridden) class is exposed via Get_CurrentStateClass.
        auto Resolved = InHandle.Get_CurrentStateClass();
        Assert_True(Resolved == UCk_SmTest_OverrideParams_Replacement,
            f"Params-based _OverrideStates should resolve the initial state to the override (Replacement), not Base");

        FinishSuccess();
    }
}
