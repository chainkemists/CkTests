// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: explicit hide removes a POI from BOTH projectors
//============================================================================
//
// Gate 4 semantics: a base-entity CkVisibleRange with an UNLIMITED range (so
// distance never hides it) still drives projector membership through the
// explicit show/hide override. Request_SetVisibility(Hide) sets the base
// entity's FTag_VisibleRange_Hidden, which both the compass and the minimap
// gather-exclude — the POI leaves BOTH projectors. Request_SetVisibility(Show)
// clears the vote and the projectors (which keep feeding hidden POIs by
// design) re-admit it.
//
// One observer hosts both projectors: compass Add and minimap Add are each
// direct-attach onto distinct fragment sets (CkCompass_Utils.cpp:33,
// CkMinimap_Utils.cpp:37), so they coexist on one entity.
//
// Isolated Y band: 51600.
//============================================================================

class UCk_AutoTest_Poi_ExplicitHide_RemovesFromBothProjectors : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 9.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _Poi;
    private FCk_Handle_VisibleRange _Vr;
    private FVector _Base = FVector(0.0, 51600.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Observer entity hosting BOTH projectors at the band origin.
        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto CompassParams = FCk_Fragment_Compass_ParamsData();
        CompassParams.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, CompassParams);
        _Compass.Request_SetManualHeading(0.0);

        _Minimap = utils_minimap::Add(Observer, FCk_Fragment_Minimap_ParamsData(5000.0));

        // POI 1000uu due +X (bearing 0, inside the compass arc; inside the minimap frame).
        auto PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark")));

        // Base-entity VisibleRange: unlimited range (MaxRange 0), evaluate every tick.
        auto VrParams = FCk_Fragment_VisibleRange_ParamsData(0.0);
        VrParams.Set_UpdateInterval(FCk_Time(0.0f));
        _Vr = utils_visible_range::Add(PoiOwner, VrParams);

        WaitOneFrame(n"OnSettled_Requests");
    }

    private bool DoCompassContainsPoi()
    {
        for (auto Entry : utils_compass::Get_Entries(_Compass))
        {
            if (Entry.Get_Poi() == _Poi) { return true; }
        }
        return false;
    }

    private bool DoMinimapContainsPoi()
    {
        for (auto Entry : utils_minimap::Get_Entries(_Minimap))
        {
            if (Entry.Get_Poi() == _Poi) { return true; }
        }
        return false;
    }

    // ---- Phase 1: both projectors show the POI (EntityTag category + first projection settle) ----
    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Visible");
    }

    UFUNCTION()
    private void OnSettled_Visible(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(DoCompassContainsPoi(), "Phase 1: the visible POI should be on the compass");
        Assert_True(DoMinimapContainsPoi(), "Phase 1: the visible POI should be on the minimap");

        // Phase 2: explicit hide.
        utils_visible_range::Request_SetVisibility(_Vr, ECk_VisibleRange_ShowHide::Hide);
        WaitOneFrame(n"OnHide_1");
    }

    // ---- Phase 2: hide drains (request + VR tag + projector update) then both projectors drop it ----
    UFUNCTION()
    private void OnHide_1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnHide_2");
    }

    UFUNCTION()
    private void OnHide_2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnHide_3");
    }

    UFUNCTION()
    private void OnHide_3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!DoCompassContainsPoi(), "Phase 2: an explicitly hidden POI must leave the compass");
        Assert_True(!DoMinimapContainsPoi(), "Phase 2: an explicitly hidden POI must leave the minimap");

        // Phase 3: show again — recovery must work (projectors keep feeding hidden POIs).
        utils_visible_range::Request_SetVisibility(_Vr, ECk_VisibleRange_ShowHide::Show);
        WaitOneFrame(n"OnShow_1");
    }

    // ---- Phase 3: show drains then both projectors re-admit it ----
    UFUNCTION()
    private void OnShow_1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnShow_2");
    }

    UFUNCTION()
    private void OnShow_2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnShow_3");
    }

    UFUNCTION()
    private void OnShow_3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(DoCompassContainsPoi(), "Phase 3: showing the POI again must re-admit it to the compass");
        Assert_True(DoMinimapContainsPoi(), "Phase 3: showing the POI again must re-admit it to the minimap");

        FinishSuccess();
    }
}
