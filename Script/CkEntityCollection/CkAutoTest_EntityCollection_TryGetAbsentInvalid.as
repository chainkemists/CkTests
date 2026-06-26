// Language=angelscript
//
// CK ENTITY COLLECTION — AUTOMATION TEST: TryGet for an unregistered name
// returns an invalid handle (does not match a different collection by accident).

class UCk_AutoTest_EntityCollection_TryGetAbsentInvalid : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Present = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.Present");
        auto Missing = utils_gameplay_tag::ResolveGameplayTag(n"EntityCollection.AutoTest.Missing");

        utils_entity_collection::Add(
            LocalHandle,
            FCk_Fragment_EntityCollection_ParamsData(Present),
            ECk_Replication::DoesNotReplicate);

        auto FoundMissing = utils_entity_collection::TryGet_EntityCollection(LocalHandle, Missing);
        Assert_True(!utils_handle::Get_IsValid(FoundMissing),
            "TryGet for an unregistered collection name should return invalid handle");

        FinishSuccess();
    }
}
