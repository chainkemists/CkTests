// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: IDEMPOTENT NO-OP REPORTS SUCCEEDED
//============================================================================
//
// Succeeded means the request was processed AND the caller's intent now
// holds. It does not mean something changed. Removing a tag that is
// already absent is an idempotent no-op: the intent (tag absent) holds
// afterwards, so the completion must be Succeeded, never Failed. Failed is
// reserved for an intent that does not hold and that retrying will not fix.
//   1. Add one tag and let it drain, so the entity carries state a faulty
//      no-op could disturb.
//   2. Request_TryRemove a tag that was never added, with a completion
//      delegate — the boundary enqueues regardless, so a handler DOES run.
//   3. On completion assert Succeeded, that the absent tag is still absent,
//      and that the unrelated tag was left alone.
//============================================================================

class UCk_AutoTest_EntityTag_RequestCompletion_IdempotentNoOpSucceeds : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _Entity;
    private int _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;

        utils_entity_tag::Add(_Entity, n"CompletionKeepMe");

        WaitOneFrame(n"OnTagAdded");
    }

    UFUNCTION()
    private void OnTagAdded(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, n"CompletionKeepMe"),
            "The unrelated tag must be present so the no-op has neighbouring state to leave alone");

        Assert_True(!utils_entity_tag::Has(_Entity, n"CompletionNeverAdded"),
            "The target tag must be absent for the removal to be an idempotent no-op");

        utils_entity_tag::Request_TryRemove(_Entity, n"CompletionNeverAdded",
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _FireCount += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"An idempotent no-op must report Succeeded, not Failed (got {InResult})");

        Assert_True(InRequestOwner == _Entity,
            "Completion must report the request's owner entity");

        Assert_True(!utils_entity_tag::Has(_Entity, n"CompletionNeverAdded"),
            "The no-op removal must leave the already-absent tag absent");

        Assert_True(utils_entity_tag::Has(_Entity, n"CompletionKeepMe"),
            "The no-op removal must not disturb the entity's other tags");

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
