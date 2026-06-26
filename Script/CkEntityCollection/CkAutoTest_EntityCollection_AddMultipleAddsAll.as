// Language=angelscript
//
// CK ENTITY COLLECTION — AUTOMATION TEST: AddMultiple registers every entry
// AddMultiple(N) returns N handles and each name resolves via TryGet.

class UCk_AutoTest_EntityCollection_AddMultipleAddsAll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto NameA = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.MultiA");
        auto NameB = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.MultiB");

        auto ParamsList = TArray<FCk_Fragment_EntityCollection_ParamsData>();
        ParamsList.Add(FCk_Fragment_EntityCollection_ParamsData(NameA));
        ParamsList.Add(FCk_Fragment_EntityCollection_ParamsData(NameB));

        auto Added = utils_entity_collection::AddMultiple(
            LocalHandle,
            FCk_Fragment_MultipleEntityCollection_ParamsData(ParamsList),
            ECk_Replication::DoesNotReplicate);

        Assert_Equals_Int(Added.Num(), 2,
            "AddMultiple should return one handle per ParamsData entry");

        auto FoundA = utils_entity_collection::TryGet_EntityCollection(LocalHandle, NameA);
        Assert_True(utils_handle::Get_IsValid(FoundA),
            "TryGet(NameA) should resolve after AddMultiple");
        auto FoundB = utils_entity_collection::TryGet_EntityCollection(LocalHandle, NameB);
        Assert_True(utils_handle::Get_IsValid(FoundB),
            "TryGet(NameB) should resolve after AddMultiple");

        FinishSuccess();
    }
}
