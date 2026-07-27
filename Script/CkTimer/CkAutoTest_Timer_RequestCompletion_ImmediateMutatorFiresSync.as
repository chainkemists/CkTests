// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: IMMEDIATE MUTATOR COMPLETES SYNCHRONOUSLY
//============================================================================
//
// Request_ChangeCountDirection mutates the countdown tag inline and enqueues
// nothing — there is no request entity and no handler. Its completion
// delegate must therefore fire with Succeeded on the CALLER'S OWN STACK,
// before the Request_* call returns: no tick, no drain, no settle frame.
//============================================================================

class UCk_AutoTest_Timer_RequestCompletion_ImmediateMutatorFiresSync : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;
    private bool _Fired = false;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        _Timer = utils_timer::Add(LocalHandle, Params);

        Assert_True(_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountUp,
            "Timer must start counting up for the direction flip to be observable");

        utils_timer::Request_ChangeCountDirection(_Timer, ECk_Timer_CountDirection::CountDown,
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));

        // The assertions below run on the same stack frame that issued the request.
        // If the delegate had been deferred, _Fired would still be false here.
        Assert_True(_Fired,
            "An immediate mutator must fire its completion delegate synchronously, before returning");

        Assert_True(_Result == ECk_Request_OperationResult::Succeeded,
            f"Immediate mutator completion must report Succeeded (got {_Result})");

        Assert_True(_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountDown,
            "The direction flip must already be applied when the completion delegate fires");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Fired = true;
        _Result = InResult;
    }
}
