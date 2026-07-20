// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: multiple POIs per owner
//============================================================================
//
// The child-entity composition shape must allow one entity to host several
// POIs (e.g. a vendor that is both a Shop and a QuestTarget). Two Adds with
// different categories return distinct valid handles and ForEach_Poi reports
// both (returned array + per-poi delegate).
//
// Isolated Y band: 52200.
//============================================================================

class UCk_AutoTest_Poi_Add_MultiplePerOwner : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private int32 _ForEachCount = 0;

    UFUNCTION()
    private void OnEachPoi(FCk_Handle InHandle)
    {
        _ForEachCount++;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto ShopCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Shop");
        auto QuestCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");

        auto ShopPoi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(ShopCategory));
        auto QuestPoi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(QuestCategory));

        Assert_True(ck::IsValid(ShopPoi), "First Add should return a valid handle");
        Assert_True(ck::IsValid(QuestPoi), "Second Add on the SAME owner should return a valid handle");
        Assert_True(!(ShopPoi == QuestPoi), "The two POIs must be distinct entities");

        auto Pois = utils_poi::ForEach_Poi(Owner, FInstancedStruct(),
            FCk_Lambda_InHandle(this, n"OnEachPoi"));
        Assert_Equals_Int(Pois.Num(), 2, "ForEach_Poi's returned array should report both POIs");
        Assert_Equals_Int(_ForEachCount, 2, "ForEach_Poi should invoke the delegate once per POI");

        FinishSuccess();
    }
}
