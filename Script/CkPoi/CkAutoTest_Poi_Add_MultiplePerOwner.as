// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: one POI per entity
//============================================================================
//
// Poi Add composes DIRECTLY onto the passed entity — an entity hosts at most
// ONE POI. Multiple POIs mean multiple entities: two entities each take a POI
// of a different category, the handles are distinct, and each category
// round-trips independently.
//
// NOTE: the class keeps its historical name (the AutoTests level has a placed
// runner actor referencing it by class path — renaming requires an editor
// level edit).
//
// Isolated Y band: 52200.
//============================================================================

class UCk_AutoTest_Poi_Add_MultiplePerOwner : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ShopCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Shop");
        auto QuestCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");

        auto ShopOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        ShopOwner.Request_OverrideToSelf();
        utils_transform::Add(ShopOwner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        auto ShopPoi = utils_poi::Add(ShopOwner, FCk_Fragment_Poi_ParamsData(ShopCategory));

        auto QuestOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        QuestOwner.Request_OverrideToSelf();
        utils_transform::Add(QuestOwner, FTransform(FRotator::ZeroRotator, FVector(100.0, 52200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        auto QuestPoi = utils_poi::Add(QuestOwner, FCk_Fragment_Poi_ParamsData(QuestCategory));

        Assert_True(ck::IsValid(ShopPoi), "First entity's Add should return a valid handle");
        Assert_True(ck::IsValid(QuestPoi), "Second entity's Add should return a valid handle");
        Assert_True(!(ShopPoi == QuestPoi), "The two POIs must be distinct entities");

        Assert_True(utils_poi::Get_Category(ShopPoi) == ShopCategory,
            "First POI's category should round-trip independently");
        Assert_True(utils_poi::Get_Category(QuestPoi) == QuestCategory,
            "Second POI's category should round-trip independently");

        Assert_True(utils_poi::Has(ShopOwner) && utils_poi::Has(QuestOwner),
            "Has should report true on both POI-hosting entities");

        FinishSuccess();
    }
}
