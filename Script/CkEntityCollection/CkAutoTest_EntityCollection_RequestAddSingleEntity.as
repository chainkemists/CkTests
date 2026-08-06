// Language=angelscript
//
// CK ENTITY COLLECTION — AUTOMATION TEST: Request_AddSingleEntity
// Enqueues an Add request; after one frame the count is 1 and Contains is true.
// Pins the deferred-handler contract for Request_AddEntities.

class UCk_AutoTest_EntityCollection_RequestAddSingleEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_EntityCollection _Collection;
    private FCk_Handle _Member;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto CollectionTag = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.AddFlow");

        _Collection = utils_entity_collection::Add(
            LocalHandle,
            FCk_EntityCollection_Spec(CollectionTag),
            ECk_Replication::DoesNotReplicate);
        _Member = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        Assert_Equals_Int(utils_entity_collection::Get_NumEntitiesInCollection(_Collection), 0,
            "Pre-add: collection should be empty");

        utils_entity_collection::Request_AddSingleEntity(_Collection, _Member);

        WaitUntil(n"Check_EntityAdded", n"OnSettled");
    }

    UFUNCTION()
    private void Check_EntityAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_collection::Get_NumEntitiesInCollection(_Collection) >= 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_Int(utils_entity_collection::Get_NumEntitiesInCollection(_Collection), 1,
            "Post-add: collection should contain 1 entity");
        Assert_True(utils_entity_collection::Get_ContainsEntityInCollection(_Collection, _Member),
            "Get_ContainsEntityInCollection should return true for the just-added member");

        FinishSuccess();
    }
}
