// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Request_TryRemove happy path
// Add a tag, then TryRemove returns Succeeded; Has reports false.

class UCk_AutoTest_EntityTag_RequestTryRemoveHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;
        utils_entity_tag::Add(_Entity, n"RemoveMe");

        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, n"RemoveMe"),
            "Pre-remove: Has should be true");

        auto Result = utils_entity_tag::Request_TryRemove(_Entity, n"RemoveMe");
        Assert_True(Result == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove on a present tag should return Succeeded");

        WaitOneFrame(n"AfterRemove");
    }

    UFUNCTION()
    private void AfterRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_entity_tag::Has(_Entity, n"RemoveMe"),
            "Post-remove: Has should be false");

        FinishSuccess();
    }
}
