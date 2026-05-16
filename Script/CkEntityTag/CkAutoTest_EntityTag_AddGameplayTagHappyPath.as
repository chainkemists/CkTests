// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Add_UsingGameplayTag round-trip
// Mirror of the FName test but using FGameplayTag and the typed overloads.

class UCk_AutoTest_EntityTag_AddGameplayTagHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"EntityTag.AutoTest.Bar");

        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, Tag);
        Assert_True(utils_entity_tag::Has_UsingGameplayTag(LocalHandle, Tag),
            "Has_UsingGameplayTag should return true after Add_UsingGameplayTag");

        auto Removed = utils_entity_tag::Request_TryRemove_UsingGameplayTag(LocalHandle, Tag);
        Assert_True(Removed == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove_UsingGameplayTag on a present tag should succeed");
        Assert_True(!utils_entity_tag::Has_UsingGameplayTag(LocalHandle, Tag),
            "After remove, Has_UsingGameplayTag should be false");

        FinishSuccess();
    }
}
