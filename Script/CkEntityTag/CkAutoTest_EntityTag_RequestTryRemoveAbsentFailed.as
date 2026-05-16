// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Request_TryRemove on absent tag
// TryRemove on a tag that was never added returns Failed.

class UCk_AutoTest_EntityTag_RequestTryRemoveAbsentFailed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        // Don't add anything — pin the absent-tag failure contract.
        auto Result = utils_entity_tag::Request_TryRemove(LocalHandle, n"NeverAdded");
        Assert_True(Result == ECk_SucceededFailed::Failed,
            "Request_TryRemove on an absent tag should return Failed");

        FinishSuccess();
    }
}
