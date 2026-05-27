// Language=angelscript
//
// CK ENTITY COLLECTION — AUTOMATION TEST: Request_RemoveSingleEntity
// Add → frame → Remove → frame. Final state: Num=0 and Contains is false.

class UCk_AutoTest_EntityCollection_RequestRemoveSingleEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_EntityCollection _Collection;
    private FCk_Handle _Member;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto CollectionTag = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.RemoveFlow");

        _Collection = utils_entity_collection::Add(
            LocalHandle,
            FCk_Fragment_EntityCollection_ParamsData(CollectionTag),
            ECk_Replication::DoesNotReplicate);
        _Member = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        utils_entity_collection::Request_AddSingleEntity(_Collection, _Member);

        WaitOneFrame(n"OnAdded");
    }

    UFUNCTION()
    private void OnAdded(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_entity_collection::Get_NumEntitiesInCollection(_Collection), 1,
            "Pre-remove: collection should contain 1 entity");

        utils_entity_collection::Request_RemoveSingleEntity(_Collection, _Member);
        WaitOneFrame(n"OnRemoved");
    }

    UFUNCTION()
    private void OnRemoved(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_entity_collection::Get_NumEntitiesInCollection(_Collection), 0,
            "Post-remove: collection should be empty");
        Assert_True(!utils_entity_collection::Get_ContainsEntityInCollection(_Collection, _Member),
            "Get_ContainsEntityInCollection should return false after Remove");

        FinishSuccess();
    }
}
