// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: REQUEST COMPLETION SUCCEEDS ON DRAIN
//============================================================================
//
// The Succeeded-on-drain contract in a VARIANT-list feature other than CkTimer:
// FFragment_EntityTag_Requests holds a TArray<std::variant<...>> of five request
// types, and FProcessor_EntityTag_HandleRequests completes each entry through
// ck::MakeCompletionGuard.
//   1. Add a tag and let it drain, so the removal has something to remove.
//   2. Request_TryRemove with a completion delegate.
//   3. On completion assert Succeeded, owner match, and that the tag is
//      observably gone (proving the fire is post-processing, not pre-enqueue).
//   4. Settle one more frame and assert the delegate fired exactly once.
//============================================================================

class UCk_AutoTest_EntityTag_RequestCompletion_SucceedsOnDrain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _Entity;
    private int _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;

        utils_entity_tag::Add(_Entity, n"CompletionDrainMe");

        WaitOneFrame(n"OnTagAdded");
    }

    UFUNCTION()
    private void OnTagAdded(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, n"CompletionDrainMe"),
            "The tag must be present before the removal for the drain to be observable");

        utils_entity_tag::Request_TryRemove(_Entity, n"CompletionDrainMe",
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _FireCount += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"A drained request must complete with Succeeded (got {InResult})");

        Assert_True(InRequestOwner == _Entity,
            "Completion must report the request's owner entity");

        Assert_True(!utils_entity_tag::Has(_Entity, n"CompletionDrainMe"),
            "Completion must fire after the request was processed (tag observably removed)");

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1, "Completion delegate must fire exactly once");

        FinishSuccess();
    }
}
