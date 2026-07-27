// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Add_UsingGameplayTag round-trip
// Mirror of the FName test but using FGameplayTag and the typed overloads.
//
// Both the Add and the Remove are deferred through the request pump
// (CkEntityTag/Claude.md § Timing), so each is followed by a wait on the
// presence actually flipping rather than on a fixed slice of wall-clock.

class UCk_AutoTest_EntityTag_AddGameplayTagHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FGameplayTag _Tag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        _Tag = utils_gameplay_tag::ResolveGameplayTag(n"EntityTag.AutoTest.Bar");

        Add_Step(          "add the gameplay tag",       n"Step_Add");
        Add_Step_WaitUntil("the tag becomes present",    n"Check_Present");
        Add_Step(          "remove the gameplay tag",    n"Step_Remove");
        Add_Step_WaitUntil("the tag becomes absent",     n"Check_Absent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Add(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _Tag);
    }

    UFUNCTION()
    private void Step_Remove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Removed = utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _Tag);
        Assert_True(Removed == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove_UsingGameplayTag on a present tag should succeed");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Present(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has_UsingGameplayTag(_Entity, _Tag));
    }

    UFUNCTION()
    private void Check_Absent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has_UsingGameplayTag(_Entity, _Tag) == false);
    }
}
