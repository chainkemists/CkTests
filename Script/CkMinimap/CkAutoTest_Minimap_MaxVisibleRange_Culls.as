// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: per-POI MaxVisibleRange culls the projection
//============================================================================
//
// Two POIs inside the view extent (5000): one unlimited (range 0) at 800uu,
// one with MaxVisibleRange 1000 sitting 2000uu away. The ranged POI must be
// culled by its own range; the unlimited one survives.
//
// Isolated Y band: 53500.
//============================================================================

class UCk_AutoTest_Minimap_MaxVisibleRange_Culls : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _NearPoi;
    private FCk_Handle_Poi _RangedPoi;
    private FVector _Base = FVector(0.0, 53500.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        _Minimap = utils_minimap::Add(Observer, FCk_Fragment_Minimap_ParamsData(5000.0));

        auto NearOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        NearOwner.Request_OverrideToSelf();
        utils_transform::Add(NearOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(0.0, 800.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _NearPoi = utils_poi::Add(NearOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapRangeNear")));

        auto RangedOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        RangedOwner.Request_OverrideToSelf();
        utils_transform::Add(RangedOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(0.0, 2000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        auto RangedParams = FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapRangeFar"));
        RangedParams.Set_MaxVisibleRange(1000.0);
        _RangedPoi = utils_poi::Add(RangedOwner, RangedParams);

        WaitOneFrame(n"OnSettled_Requests");
    }

    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Projection");
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 1, "The POI beyond its own MaxVisibleRange should be culled");

        if (Entries.Num() == 1)
        {
            Assert_True(Entries[0].Get_Poi() == _NearPoi,
                "The surviving entry should be the unlimited-range POI");
        }

        FinishSuccess();
    }
}
