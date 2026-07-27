// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Request_TryRemove happy path
// Add a tag, then TryRemove returns Succeeded; Has reports false.
//
// Add and Request_TryRemove are both deferred through the request pump
// (CkEntityTag/Claude.md § Timing), so each phase waits on the presence
// actually flipping.

class UCk_AutoTest_EntityTag_RequestTryRemoveHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;

        Add_Step(          "add the tag",              n"Step_Add");
        Add_Step_WaitUntil("the tag becomes present",  n"Check_Present");
        Add_Step(          "remove the tag",           n"Step_Remove");
        Add_Step_WaitUntil("the tag becomes absent",   n"Check_Absent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Add(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::Add(_Entity, n"RemoveMe");
    }

    UFUNCTION()
    private void Step_Remove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Result = utils_entity_tag::Request_TryRemove(_Entity, n"RemoveMe");
        Assert_True(Result == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove on a present tag should return Succeeded");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Present(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"RemoveMe"));
    }

    UFUNCTION()
    private void Check_Absent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"RemoveMe") == false);
    }
}
