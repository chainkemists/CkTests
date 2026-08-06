// Language=angelscript

//============================================================================
// CK SUBSTEP — AUTOMATION TEST: IMMEDIATE MUTATOR COMPLETES SYNCHRONOUSLY
//============================================================================
//
// Request_Resume adds FTag_Substep_Update inline and enqueues nothing — there
// is no request struct and no handler. Its completion delegate must therefore
// fire with Succeeded on the CALLER'S OWN STACK, before the Request_* call
// returns: no tick, no drain, no settle frame.
//============================================================================

class UCk_AutoTest_Substep_RequestCompletion_ImmediateMutatorFiresSync : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Substep _Substep;
    private bool _Fired = false;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Params = FCk_Substep_Spec(FCk_Time(0.05f));
        Params.Set_StartingState(ECk_Substep_State::Paused);

        _Substep = utils_substep::Add(Owner, Params);

        Assert_True(_Substep.Get_CurrentState() == ECk_Substep_State::Paused,
            "Substep must start Paused for the resume to be observable");

        utils_substep::Request_Resume(_Substep, FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));

        // The assertions below run on the same stack frame that issued the request.
        // If the delegate had been deferred, _Fired would still be false here.
        Assert_True(_Fired,
            "An immediate mutator must fire its completion delegate synchronously, before returning");

        Assert_True(_Result == ECk_Request_OperationResult::Succeeded,
            f"Immediate mutator completion must report Succeeded (got {_Result})");

        Assert_True(_Substep.Get_CurrentState() == ECk_Substep_State::Running,
            "The resume must already be applied when the completion delegate fires");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Fired = true;
        _Result = InResult;
    }
}
