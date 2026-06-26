// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Add_UsingGameplayTag round-trip
// Mirror of the FName test but using FGameplayTag and the typed overloads.

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

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _Tag);
        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has_UsingGameplayTag(_Entity, _Tag),
            "Has_UsingGameplayTag should return true after Add_UsingGameplayTag");

        auto Removed = utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _Tag);
        Assert_True(Removed == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove_UsingGameplayTag on a present tag should succeed");

        WaitOneFrame(n"AfterRemove");
    }

    UFUNCTION()
    private void AfterRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_entity_tag::Has_UsingGameplayTag(_Entity, _Tag),
            "After remove, Has_UsingGameplayTag should be false");

        FinishSuccess();
    }
}
