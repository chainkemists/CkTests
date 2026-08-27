// Language=angelscript
//
// CK ENTITY COLLECTION - AUTOMATION TEST: Add happy path
// Add a named collection; Has_Any reports true; TryGet returns the handle;
// a fresh collection has 0 entities.

class UCk_AutoTest_EntityCollection_AddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto CollectionTag = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.Foo");

        auto Collection = utils_entity_collection::Add(
            LocalHandle,
            FCk_Fragment_EntityCollection_ParamsData(CollectionTag),
            ECk_Replication::DoesNotReplicate);

        Assert_True(utils_entity_collection::Has_Any(LocalHandle),
            "Has_Any should return true after Add");
        Assert_True(utils_handle::Get_IsValid(Collection),
            "Add should return a valid collection handle");

        auto Found = utils_entity_collection::TryGet_EntityCollection(LocalHandle, CollectionTag);
        Assert_True(utils_handle::IsEqual(Found, Collection),
            "TryGet_EntityCollection should return the just-added collection");
        Assert_Equals_Int(utils_entity_collection::Get_NumEntitiesInCollection(Collection), 0,
            "Newly created collection should have 0 entities");

        FinishSuccess();
    }
}
