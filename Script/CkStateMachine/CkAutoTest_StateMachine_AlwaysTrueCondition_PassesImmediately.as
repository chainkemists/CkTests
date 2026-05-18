// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: ALWAYS-TRUE CONDITION PASSES
//============================================================================
//
// Pins the documented Super::BeginPlay-then-MarkSatisfied ordering for
// UCk_SmCondition_AlwaysTrue (see CkStateMachine/CLAUDE.md "Event-driven
// condition resting state -> Trade-offs"). The contract is:
//
//   AlwaysTrue::BeginPlay calls Super::BeginPlay() first (so the
//   EventDriven base writes Fail as the resting state) and only then
//   MarkSatisfied() so the final result is Pass.
//
// Symptom of regressed ordering: AlwaysTrue would stick at Fail and the
// transition would never fire. We use the smallest possible graph: Idle
// has one transition to Finish guarded by AlwaysTrue. The transition
// must fire on the very next pump pass after the initial Idle entry.
//============================================================================

UCLASS()
class UCk_SmTest_AlwaysTrue_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // terminal — no transitions
    }
};

UCLASS()
class UCk_SmTest_AlwaysTrue_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_AlwaysTrue_State_Finish);
        AddCondition(Trans, UCk_SmCondition_AlwaysTrue);
    }
};

class UCk_AutoTest_StateMachine_AlwaysTrueCondition_PassesImmediately : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _FinishObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, UCk_SmTest_AlwaysTrue_State_Idle);

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

        // Filter the initial Idle entry; only treat the Finish entry as the
        // transition fire we are pinning.
        if (InPayload.Get_NewStateClass() != UCk_SmTest_AlwaysTrue_State_Finish) { return; }

        _FinishObserved = true;
        Assert_True(InPayload.Get_PreviousStateClass() == UCk_SmTest_AlwaysTrue_State_Idle,
            "AlwaysTrue-guarded transition should fire from Idle to Finish — Get_PreviousStateClass must be Idle");
        FinishSuccess();
    }
}
