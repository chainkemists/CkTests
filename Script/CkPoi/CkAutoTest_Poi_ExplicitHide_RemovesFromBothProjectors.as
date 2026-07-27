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
// Each projector is awaited separately rather than as one combined predicate,
// so a failure names WHICH projector never converged.
//
// Isolated Y band: 51600.
//============================================================================

class UCk_AutoTest_Poi_ExplicitHide_RemovesFromBothProjectors : UCk_AutoTest_Base
{
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

        Add_Step(          "arrange observer with both projectors and a visible POI", n"Step_Arrange");
        Add_Step_WaitUntil("POI is projected by the compass",                         n"Check_CompassHasPoi");
        Add_Step_WaitUntil("POI is projected by the minimap",                         n"Check_MinimapHasPoi");

        Add_Step(          "explicitly hide the POI",                                 n"Step_Hide");
        Add_Step_WaitUntil("hidden POI leaves the compass",                           n"Check_CompassLacksPoi");
        Add_Step_WaitUntil("hidden POI leaves the minimap",                           n"Check_MinimapLacksPoi");

        Add_Step(          "show the POI again",                                      n"Step_Show");
        Add_Step_WaitUntil("shown POI is re-admitted to the compass",                 n"Check_CompassHasPoi");
        Add_Step_WaitUntil("shown POI is re-admitted to the minimap",                 n"Check_MinimapHasPoi");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
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
    }

    UFUNCTION()
    private void Step_Hide(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_visible_range::Request_SetVisibility(_Vr, ECk_VisibleRange_ShowHide::Hide);
    }

    UFUNCTION()
    private void Step_Show(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_visible_range::Request_SetVisibility(_Vr, ECk_VisibleRange_ShowHide::Show);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_CompassHasPoi(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoCompassContainsPoi());
    }

    UFUNCTION()
    private void Check_CompassLacksPoi(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoCompassContainsPoi() == false);
    }

    UFUNCTION()
    private void Check_MinimapHasPoi(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoMinimapContainsPoi());
    }

    UFUNCTION()
    private void Check_MinimapLacksPoi(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoMinimapContainsPoi() == false);
    }

    //------------------------------------------------------------------------

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
}
