// Language=angelscript

//============================================================================
// CK POI - AUTOMATION TEST: a per-consumer VisibleRange culls ONE projector
//============================================================================
//
// Gate 4 per-consumer restriction: a POI has NO base VisibleRange, but carries
// two PoiDisplayDefinition children - one for the compass consumer, one for the
// minimap consumer. A CkVisibleRange composed on the COMPASS child only, with a
// MaxRange smaller than the POI's distance, culls the compass entry while the
// minimap (whose child has no VisibleRange) keeps showing it.
//
// Path (per gate): projector update feeds the resolved consumer child's VR
// distance -> VR evaluates on its next tick -> the next projector update
// excludes that child (Get_IsEffectivelyHidden). One projector feeds only its
// OWN consumer child, so the minimap never drives the compass child's VR.
//
// POI at 2000uu due +X; compass child VR MaxRange 1000 -> out of range -> hidden.
//
// Isolated Y band: 51800.
//
// The headline assertion is a NEGATIVE (the compass must not list the POI),
// which is already true before any projector has run - an unconditional settle
// could pass it vacuously. The sequence therefore waits on a POSITIVE witness
// first (the minimap picking the POI up, proving the projectors are live), then
// on the causal event (the compass child's VR going hidden), before asserting.
//============================================================================

class UCk_AutoTest_Poi_PerConsumerRange_CullsOneProjector : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 9.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle_Poi _Poi;
    private FCk_Handle_VisibleRange _CompassChildVr;
    private FVector _Base = FVector(0.0, 51800.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Observer entity hosting both projectors at the band origin.
        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto CompassParams = FCk_Fragment_Compass_ParamsData();
        CompassParams.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, CompassParams);
        _Compass.Request_SetManualHeading(0.0);

        _Minimap = utils_minimap::Add(Observer, FCk_Fragment_Minimap_ParamsData(5000.0));

        // POI 2000uu due +X - NO base VisibleRange.
        auto PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(2000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark")));

        // Two consumer-keyed display-definition children (native consumer tags).
        auto CompassDd = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Compass"));
        auto CompassChild = utils_poi_display_definition::Create(_Poi, CompassDd);

        auto MinimapDd = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Minimap"));
        utils_poi_display_definition::Create(_Poi, MinimapDd);

        // VisibleRange on the COMPASS child only: MaxRange 1000 < 2000 distance, evaluate every tick.
        auto VrParams = FCk_Fragment_VisibleRange_ParamsData(1000.0);
        VrParams.Set_UpdateInterval(FCk_Time(0.0f));
        _CompassChildVr = utils_visible_range::Add(CompassChild, VrParams);

        Add_Step_WaitUntil( "the minimap projector picks the POI up",        n"Check_MinimapHasPoi");
        Add_Step_WaitUntil( "the compass child's VisibleRange goes hidden",  n"Check_CompassChildHidden");
        Add_Step_WaitFrames("let the next compass update apply the cull",    3);
        Add_Step(           "assert only the compass consumer was culled",   n"Step_AssertPerConsumerCull");

        Run_Steps(InHandle);
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

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    // A POSITIVE witness, and it is load-bearing. The headline assertion is a
    // negative - the compass must NOT list the POI - which is already true
    // before any projector has run. Proving the minimap picked the POI up first
    // establishes that the projectors are live, so the negative means the
    // compass consumer was CULLED rather than never gathered.
    UFUNCTION()
    private void Check_MinimapHasPoi(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoMinimapContainsPoi());
    }

    // The causal event: the compass child's VR evaluating out-of-range is what
    // the next projector update acts on. False on entry, so this wait is decisive.
    UFUNCTION()
    private void Check_CompassChildHidden(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_visible_range::Get_IsHidden(_CompassChildVr));
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertPerConsumerCull(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(!DoCompassContainsPoi(),
            "A VisibleRange (MaxRange 1000) on the compass consumer child must cull the compass entry at distance ~2000");
        Assert_True(DoMinimapContainsPoi(),
            "The minimap consumer child has no VisibleRange, so the minimap must still show the POI");
        Assert_True(utils_visible_range::Get_IsHidden(_CompassChildVr),
            "The compass child's VisibleRange should report hidden (out of range)");
    }
}
