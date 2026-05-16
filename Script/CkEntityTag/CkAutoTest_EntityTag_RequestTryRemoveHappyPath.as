// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Request_TryRemove happy path
// Add a tag, then TryRemove returns Succeeded; Has reports false.

class UCk_AutoTest_EntityTag_RequestTryRemoveHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_entity_tag::Add(LocalHandle, n"RemoveMe");
        Assert_True(utils_entity_tag::Has(LocalHandle, n"RemoveMe"),
            "Pre-remove: Has should be true");

        auto Result = utils_entity_tag::Request_TryRemove(LocalHandle, n"RemoveMe");
        Assert_True(Result == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove on a present tag should return Succeeded");
        Assert_True(!utils_entity_tag::Has(LocalHandle, n"RemoveMe"),
            "Post-remove: Has should be false");

        FinishSuccess();
    }
}
