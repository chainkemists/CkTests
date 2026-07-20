// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: multiple POIs per owner
//============================================================================
//
// Create composes POIs as record-connected CHILD entities, so one owner can
// host several POIs (e.g. a vendor that is both a Shop and a QuestTarget). Two
// Creates with different categories return distinct valid handles and
// ForEach_Poi reports both (returned array + per-poi delegate).
//
// Isolated Y band: 52200.
//============================================================================

class UCk_AutoTest_Poi_Add_MultiplePerOwner : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private int32 _ForEachCount = 0;

    UFUNCTION()
    private void OnEachPoi(FCk_Handle InHandle, FInstancedStruct InOptionalPayload)
    {
        _ForEachCount++;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto PoiTransform = FTransform(FRotator::ZeroRotator, FVector(0.0, 52200.0, 0.0));
        auto ShopCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Shop");
        auto QuestCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");

        auto ShopPoi = utils_poi::Create(Owner, PoiTransform, FCk_Fragment_Poi_ParamsData(ShopCategory), FCk_Time());
        auto QuestPoi = utils_poi::Create(Owner, PoiTransform, FCk_Fragment_Poi_ParamsData(QuestCategory), FCk_Time());

        Assert_True(ck::IsValid(ShopPoi), "First Create should return a valid handle");
        Assert_True(ck::IsValid(QuestPoi), "Second Create on the SAME owner should return a valid handle");
        Assert_True(!(ShopPoi == QuestPoi), "The two POIs must be distinct entities");

        // Array path: an UNBOUND delegate makes ForEach_Poi return the POIs
        auto Pois = utils_poi::ForEach_Poi(Owner, FInstancedStruct(), FCk_Lambda_InHandle());
        Assert_Equals_Int(Pois.Num(), 2, "ForEach_Poi's returned array should report both POIs");

        // Delegate path: a BOUND delegate fires once per POI (and returns an empty array)
        utils_poi::ForEach_Poi(Owner, FInstancedStruct(), FCk_Lambda_InHandle(this, n"OnEachPoi"));
        Assert_Equals_Int(_ForEachCount, 2, "ForEach_Poi should invoke the delegate once per POI");

        FinishSuccess();
    }
}
