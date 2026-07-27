// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: category filter excludes and re-includes
//============================================================================
//
// A minimap whose params carry a Quest-only tag query must project only the
// Quest POI; clearing the filter via Request_SetCategoryFilter (empty query
// accepts everything) must re-include the Shop POI on the next update — the
// request also bypasses the update throttle by design.
//
// Isolated Y band: 53200.
//============================================================================

class UCk_AutoTest_Minimap_CategoryFilter : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _QuestPoi;
    private FCk_Handle_Poi _ShopPoi;
    private FVector _Base = FVector(0.0, 53200.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto QuestOnly = FGameplayTagContainer();
        QuestOnly.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapFilterQuest"));

        auto Params = FCk_Fragment_Minimap_ParamsData(5000.0);
        Params.Set_CategoryFilter(FGameplayTagQuery::MakeQuery_MatchAnyTags(QuestOnly));
        _Minimap = utils_minimap::Add(Observer, Params);

        _QuestPoi = DoSpawnPoi(FVector(0.0, 500.0, 0.0), n"Poi.Category.MinimapFilterQuest");
        _ShopPoi = DoSpawnPoi(FVector(0.0, -500.0, 0.0), n"Poi.Category.MinimapFilterShop");

        WaitUntil(n"Check_MinimapProjected", n"OnSettled_Requests");
    }

    UFUNCTION()
    private void Check_MinimapProjected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_minimap::Get_Entries(_Minimap).Num() >= 1);
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FName InCategoryName)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);
        return utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));
    }

    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Filtered");
    }

    UFUNCTION()
    private void OnSettled_Filtered(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 1, "Quest-only filter should project exactly one entry");
        if (Entries.Num() == 1)
        {
            Assert_True(Entries[0].Get_Poi() == _QuestPoi,
                "The filtered entry should be the Quest POI");
        }

        _Minimap.Request_SetCategoryFilter(FCk_Request_Minimap_SetCategoryFilter(FGameplayTagQuery()));
        WaitOneFrame(n"OnSettled_Unfiltered");
    }

    UFUNCTION()
    private void OnSettled_Unfiltered(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 2, "Clearing the filter (empty query) should re-include both POIs");

        FinishSuccess();
    }
}
