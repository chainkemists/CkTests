// Language=angelscript

//============================================================================
// CK POI - AUTOMATION TEST: one POI per entity
//============================================================================
//
// Poi Add composes DIRECTLY onto the passed entity - an entity hosts at most
// ONE POI. Multiple POIs mean multiple entities: two entities each take a POI
// of a different category, the handles are distinct, and each category
// round-trips independently (via Get_CategoryTags, asserted after the
// EntityTag category materializes one pump later).
//
// NOTE: the class keeps its historical name (the AutoTests level has a placed
// runner actor referencing it by class path - renaming requires an editor
// level edit).
//
// Isolated Y band: 52200.
//============================================================================

class UCk_AutoTest_Poi_Add_MultiplePerOwner : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _ShopOwner;
    private FCk_Handle _QuestOwner;
    private FCk_Handle_Poi _ShopPoi;
    private FCk_Handle_Poi _QuestPoi;
    private FGameplayTag _ShopCategory;
    private FGameplayTag _QuestCategory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _ShopCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Shop");
        _QuestCategory = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");

        _ShopOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _ShopOwner.Request_OverrideToSelf();
        utils_transform::Add(_ShopOwner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _ShopPoi = utils_poi::Add(_ShopOwner, FCk_Fragment_Poi_ParamsData(_ShopCategory));

        _QuestOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _QuestOwner.Request_OverrideToSelf();
        utils_transform::Add(_QuestOwner, FTransform(FRotator::ZeroRotator, FVector(100.0, 52200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _QuestPoi = utils_poi::Add(_QuestOwner, FCk_Fragment_Poi_ParamsData(_QuestCategory));

        Assert_True(ck::IsValid(_ShopPoi), "First entity's Add should return a valid handle");
        Assert_True(ck::IsValid(_QuestPoi), "Second entity's Add should return a valid handle");
        Assert_True(!(_ShopPoi == _QuestPoi), "The two POIs must be distinct entities");

        Assert_True(utils_poi::Has(_ShopOwner) && utils_poi::Has(_QuestOwner),
            "Has should report true on both POI-hosting entities");

        WaitUntil(n"Check_CategoriesApplied", n"OnSettled_Categories");
    }

    UFUNCTION()
    private void Check_CategoriesApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_poi::Get_CategoryTags(_ShopPoi).Num() > 0 && utils_poi::Get_CategoryTags(_QuestPoi).Num() > 0);
    }

    UFUNCTION()
    private void OnSettled_Categories(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(utils_poi::Get_CategoryTags(_ShopPoi).HasTagExact(_ShopCategory),
            "First POI's category should round-trip independently");
        Assert_True(utils_poi::Get_CategoryTags(_QuestPoi).HasTagExact(_QuestCategory),
            "Second POI's category should round-trip independently");

        // Cross-check isolation: neither owner carries the other's category.
        Assert_True(!utils_poi::Get_CategoryTags(_ShopPoi).HasTagExact(_QuestCategory),
            "Shop POI must not carry the Quest category");
        Assert_True(!utils_poi::Get_CategoryTags(_QuestPoi).HasTagExact(_ShopCategory),
            "Quest POI must not carry the Shop category");

        FinishSuccess();
    }
}
