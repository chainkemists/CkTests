// Language=angelscript

//============================================================================
// CK MINIMAP - AUTOMATION TEST: SetViewExtent rescales positions immediately
//============================================================================
//
// Zoom is a projection input: a POI 1000uu East at ViewExtent 5000 sits at
// frame X = 1000/5000 = 0.2; after Request_SetViewExtent to 10000 the same POI
// must sit at 0.1 on the NEXT settle - the request bypasses any update
// throttle by design (projection-input requests force a reprojection).
//
// Isolated Y band: 53700.
//============================================================================

class UCk_AutoTest_Minimap_SetViewExtent_Rescales : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 53700.0, 0.0);

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

        auto PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(0.0, 1000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapZoom")));

        WaitUntil(n"Check_MinimapProjected", n"OnSettled_BeforeZoom");
    }

    // Names THIS test's own POI rather than counting entries: autotests share one
    // PIE world, so a neighbouring band's POIs can occupy the projection while
    // this test's are still pending (see CkCompass wave 21).
    UFUNCTION()
    private void Check_MinimapProjected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_minimap::Get_Entries(_Minimap);
        auto Found = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Poi) { Found = true; }
        }

        auto Res = OutResult;
        Res.Set(Found);
    }

    // Gates on the RESCALED POSITION, not merely on Get_ViewExtent reporting
    // 10000: the projector recomputes map positions on a later pass, so the
    // extent landing does not imply the entry has been reprojected. Waiting on
    // the extent alone would read the stale 0.2 and fail a working rescale.
    UFUNCTION()
    private void Check_ExtentRescaled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_minimap::Get_Entries(_Minimap);
        auto Rescaled = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Poi && Math::Abs(Entry.Get_MapPosition().X - 0.1) < 0.01)
            { Rescaled = true; }
        }

        auto Res = OutResult;
        Res.Set(Rescaled);
    }

    UFUNCTION()
    private void OnSettled_BeforeZoom(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 1, "The POI should project before zooming");
        if (Entries.Num() == 1)
        {
            auto Pos = Entries[0].Get_MapPosition();
            Assert_True(Math::Abs(Pos.X - 0.2) < 0.01,
                f"At extent 5000 the East-1000 POI should sit at X ~0.2 (got {Pos.X})");
        }

        _Minimap.Request_SetViewExtent(FCk_Request_Minimap_SetViewExtent(10000.0));
        WaitUntil(n"Check_ExtentRescaled", n"OnSettled_AfterZoom");
    }

    UFUNCTION()
    private void OnSettled_AfterZoom(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(Math::Abs(utils_minimap::Get_ViewExtent(_Minimap) - 10000.0) < 0.1,
            "Get_ViewExtent should report the requested zoom");

        auto Entries = utils_minimap::Get_Entries(_Minimap);
        Assert_Equals_Int(Entries.Num(), 1, "The POI should still project after zooming out");
        if (Entries.Num() == 1)
        {
            auto Pos = Entries[0].Get_MapPosition();
            Assert_True(Math::Abs(Pos.X - 0.1) < 0.01,
                f"Doubling the extent should halve the frame offset to X ~0.1 (got {Pos.X})");
        }

        FinishSuccess();
    }
}
