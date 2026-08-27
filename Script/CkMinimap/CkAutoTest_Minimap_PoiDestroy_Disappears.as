// Language=angelscript

//============================================================================
// CK MINIMAP - AUTOMATION TEST: destroyed POI fires Disappeared exactly once
//============================================================================
//
// Membership deltas are the push contract: creating an in-range POI fires
// OnEntryAppeared exactly once; destroying its owner fires OnEntryDisappeared
// exactly once (no repeats while it stays, none after it is gone).
//
// Mixed sequence: the opening phase asserts nothing has fired before any POI
// exists - a non-event with nothing to wait on, so it settles a fixed pair of
// frames. The appear/disappear phases wait on the counters rising, and the
// exactly-once contracts stay assertions so an over-fire is reported rather
// than swallowed.
//
// Isolated Y band: 53600.
//============================================================================

class UCk_AutoTest_Minimap_PoiDestroy_Disappears : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Minimap _Minimap;
    private FCk_Handle _PoiOwner;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 53600.0, 0.0);

    private int32 _AppearedCount = 0;
    private int32 _DisappearedCount = 0;

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

        _Minimap.BindTo_OnEntryAppeared(
            FCk_Delegate_Minimap_EntryAppeared(this, n"OnEntryAppeared"));
        _Minimap.BindTo_OnEntryDisappeared(
            FCk_Delegate_Minimap_EntryDisappeared(this, n"OnEntryDisappeared"));

        Add_Step_WaitFrames("let any spurious pre-POI signal land",       2);
        Add_Step(           "assert silence, then create an in-range POI", n"Step_AssertSilentAndCreate");
        Add_Step_WaitUntil( "the new POI fires Appeared",                  n"Check_Appeared");
        Add_Step(           "assert exactly one Appeared, then destroy",   n"Step_AssertOnceAndDestroy");
        Add_Step_WaitUntil( "the destroy fires Disappeared",               n"Check_Disappeared");
        Add_Step(           "assert exactly-once on both signals",         n"Step_AssertFinal");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertSilentAndCreate(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AppearedCount, 0, "No signals before any POI exists");

        _PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(_PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(_PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.MinimapMembership")));
    }

    UFUNCTION()
    private void Step_AssertOnceAndDestroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AppearedCount, 1, "Creating one in-range POI should fire Appeared exactly once");
        Assert_Equals_Int(_DisappearedCount, 0, "Nothing has disappeared yet");

        utils_entity_lifetime::Request_DestroyEntity(_PoiOwner);
    }

    UFUNCTION()
    private void Step_AssertFinal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AppearedCount, 1, "Appeared must not re-fire for a stable entry");
        Assert_Equals_Int(_DisappearedCount, 1, "Destroying the POI owner should fire Disappeared exactly once");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Appeared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AppearedCount >= 1);
    }

    UFUNCTION()
    private void Check_Disappeared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DisappearedCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnEntryAppeared(FCk_Handle_Minimap InMinimap, FCk_Minimap_Entry InEntry)
    {
        _AppearedCount++;
    }

    UFUNCTION()
    private void OnEntryDisappeared(FCk_Handle_Minimap InMinimap, FCk_Handle_Poi InPoi)
    {
        _DisappearedCount++;
    }
}
