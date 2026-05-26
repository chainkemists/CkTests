// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Request_TryRemove on absent tag (no-op)
//
// Contract (post-A4): Request_TryRemove returns Succeeded whenever the
// handle is valid, regardless of whether the tag is present. The deferred
// DoApply_TryRemove silently no-ops when the tag isn't there. This test
// pins the end-to-end no-op behavior: Succeeded boundary result AND no
// observable state change one frame later.

class UCk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;
        // Don't add anything — pin the absent-tag no-op contract.
        auto Result = utils_entity_tag::Request_TryRemove(_Entity, n"NeverAdded");
        Assert_True(Result == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove on an absent tag should return Succeeded — the boundary only validates the handle; the deferred apply silently no-ops on a missing tag");

        WaitOneFrame(n"AfterAbsentRemove");
    }

    UFUNCTION()
    private void AfterAbsentRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_entity_tag::Has(_Entity, n"NeverAdded"),
            "After the no-op remove pumps, Has(NeverAdded) must still be false — the no-op must not poison the entity");

        FinishSuccess();
    }
}
