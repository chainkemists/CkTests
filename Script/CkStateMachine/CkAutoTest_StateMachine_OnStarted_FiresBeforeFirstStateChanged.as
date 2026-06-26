// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: OnStarted FIRES BEFORE FIRST StateChanged
//============================================================================
//
// Pins the signal-ordering contract: OnStarted fires once when the SM enters
// Running, BEFORE the initial OnStateChanged (entry into the initial state).
// Consumers that set up per-run state in OnStarted rely on it preceding the
// first per-state pulse.
//
// Catches the regression where the initial state entry signals before (or
// without) the start signal.
//============================================================================

UCLASS()
class UCk_SmStartedTest_State_Only : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Sink — only the initial entry fires.
    }
};

class UCk_AutoTest_StateMachine_OnStarted_FiresBeforeFirstStateChanged : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _StartedFired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmStartedTest_State_Only));

        FCk_Delegate_Sm_OnStarted StartedDelegate;
        StartedDelegate.BindUFunction(this, n"OnStarted");
        _SmHandle.BindTo_OnStarted(StartedDelegate);

        FCk_Delegate_Sm_OnStateChanged ChangedDelegate;
        ChangedDelegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(ChangedDelegate);
    }

    UFUNCTION()
    private void OnStarted(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStarted InPayload)
    {
        _StartedFired = true;
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }

        Assert_True(_StartedFired,
            "OnStarted must fire before the first OnStateChanged (initial state entry)");
        FinishSuccess();
    }
}
