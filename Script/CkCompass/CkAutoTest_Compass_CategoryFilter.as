// Language=angelscript

//============================================================================
// CK COMPASS - AUTOMATION TEST: category tag-query filter
//============================================================================
//
// Compass filtered to Quest-category only: a Quest POI and a Shop POI both
// in range/arc; only the Quest POI may appear. An empty query (the default)
// accepts everything - pinned by the other tests.
//
// NOTE (flagged for the build-fix pass): FGameplayTagQuery construction from
// AS via MakeQuery_MatchAnyTags is UNVERIFIED - if the static is not bound,
// swap to a data-authored query or a utils_compass convenience once the
// modules compile.
//
// Isolated Y band: 58400.
//============================================================================

class UCk_AutoTest_Compass_CategoryFilter : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _QuestPoi;
    private FCk_Handle_Poi _ShopPoi;
    private FVector _Base = FVector(0.0, 58400.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto QuestTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Quest");
        auto ShopTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Shop");

        auto QuestOnly = FGameplayTagContainer();
        QuestOnly.AddTag(QuestTag);

        auto Params = FCk_Fragment_Compass_ParamsData();
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        Params.Set_CategoryFilter(FGameplayTagQuery::MakeQuery_MatchAnyTags(QuestOnly));
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        _QuestPoi = DoSpawnPoi(FVector(1000.0, -100.0, 0.0), QuestTag);
        _ShopPoi = DoSpawnPoi(FVector(1000.0, 100.0, 0.0), ShopTag);

        WaitUntil(n"Check_Projected", n"OnSettled_Projection");
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FGameplayTag InCategory)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);
        return utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(InCategory));
    }

    // Waits on THIS test's own POIs reaching the compass, never on a bare entry
    // count: autotests share one PIE world and a neighbouring band's POIs can
    // occupy the projection while this test's are still pending.
    UFUNCTION()
    private void Check_Projected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto Found0 = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _QuestPoi) { Found0 = true; }
        }

        auto Res = OutResult;
        Res.Set(Found0);
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto FoundQuest = false;
        auto FoundShop = false;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _QuestPoi) { FoundQuest = true; }
            if (Entry.Get_Poi() == _ShopPoi) { FoundShop = true; }
        }

        Assert_True(FoundQuest, "Quest POI should pass the Quest-only category filter");
        Assert_True(!FoundShop, "Shop POI must be filtered out by the Quest-only query");
        Assert_Equals_Int(Entries.Num(), 1, "Exactly one POI should pass the filter");

        FinishSuccess();
    }
}
