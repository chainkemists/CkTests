// Language=angelscript
//
// CK ENTITY COLLECTION — AUTOMATION TEST: Request_AddEntities (batch)
// A single Request_AddEntities with N entities populates the collection with
// all N after one processor tick. Pins the batch-handler path that
// CkObjective and similar consumers rely on.

class UCk_AutoTest_EntityCollection_RequestAddEntitiesBatch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_EntityCollection _Collection;
    private FCk_Handle _M1;
    private FCk_Handle _M2;
    private FCk_Handle _M3;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto CollectionTag = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.Batch");

        _Collection = utils_entity_collection::Add(
            LocalHandle,
            FCk_EntityCollection_Spec(CollectionTag),
            ECk_Replication::DoesNotReplicate);
        _M1 = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _M2 = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _M3 = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Members = TArray<FCk_Handle>();
        Members.Add(_M1);
        Members.Add(_M2);
        Members.Add(_M3);

        utils_entity_collection::Request_AddEntities(
            _Collection,
            FCk_Request_EntityCollection_AddEntities(Members));

        WaitUntil(n"Check_BatchAdded", n"OnSettled");
    }

    UFUNCTION()
    private void Check_BatchAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_collection::Get_NumEntitiesInCollection(_Collection) >= 3);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_Int(utils_entity_collection::Get_NumEntitiesInCollection(_Collection), 3,
            "Batch Request_AddEntities should populate all 3 entities");
        Assert_True(utils_entity_collection::Get_ContainsEntityInCollection(_Collection, _M1),
            "M1 should be present in collection");
        Assert_True(utils_entity_collection::Get_ContainsEntityInCollection(_Collection, _M2),
            "M2 should be present in collection");
        Assert_True(utils_entity_collection::Get_ContainsEntityInCollection(_Collection, _M3),
            "M3 should be present in collection");

        FinishSuccess();
    }
}
