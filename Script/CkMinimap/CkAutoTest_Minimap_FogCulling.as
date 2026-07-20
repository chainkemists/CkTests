// Language=angelscript

//============================================================================
// CK MINIMAP — AUTOMATION TEST: fog-linked minimap culls unexplored POIs
//============================================================================
//
// A minimap linked to a fog grid (Request_SetFogOfWar) must exclude a POI
// standing in unexplored cells; revealing the ground under the POI makes it
// appear on the next settle. The fog link is a projection input, so the
// requests bypass the update throttle.
//
// Isolated Y band: 54300.
//============================================================================

class UCk_AutoTest_Minimap_FogCulling : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_FogOfWar _Fog;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 54300.0, 0.0);
    private FVector _PoiPos = FVector(0.0, 55300.0, 0.0);   // base + 1000 East, inside fog bounds

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto MapEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        MapEntity.Request_OverrideToSelf();
        auto FogParams = FCk_Fragment_FogOfWar_ParamsData(FCk_Minimap_WorldBounds(
            FVector2D(0.0, 54300.0), FVector2D(2000.0, 2000.0)));
        FogParams.Set_RevealRadius(300.0);
        _Fog = utils_fog_of_war::Add(MapEntity, FogParams);

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        _Minimap = utils_minimap::Add(Observer, FCk_Fragment_Minimap_ParamsData(5000.0));
        _Minimap.Request_SetFogOfWar(_Fog);

        auto PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(PoiOwner, FTransform(FRotator::ZeroRotator, _PoiPos),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapFogCull")));

        WaitOneFrame(n"OnSettled_Requests");
    }

    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Fogged");
    }

    UFUNCTION()
    private void OnSettled_Fogged(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 0, "A POI standing in unexplored fog should be culled");

        _Fog.Request_RevealLocation(FCk_Request_FogOfWar_RevealLocation(_PoiPos));
        WaitOneFrame(n"OnSettled_Revealed");
    }

    UFUNCTION()
    private void OnSettled_Revealed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Revealed2");
    }

    UFUNCTION()
    private void OnSettled_Revealed2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 1, "Revealing the ground under the POI should un-cull it");
        if (Entries.Num() == 1)
        {
            Assert_True(Entries[0].Get_Poi() == _Poi, "The revealed entry should be the fogged POI");
        }

        FinishSuccess();
    }
}
