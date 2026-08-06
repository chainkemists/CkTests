// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: entry appear/disappear membership signals
//============================================================================
//
// Membership deltas are the push contract: creating an in-range POI fires
// OnEntryAppeared exactly once; destroying its owner fires
// OnEntryDisappeared exactly once (no repeats while it stays).
//
// Isolated Y band: 59200.
//============================================================================

class UCk_AutoTest_Compass_AppearDisappear_Signals : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle _PoiOwner;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 59200.0, 0.0);

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

        auto Params = FCk_Compass_Spec();
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        _Compass.BindTo_OnEntryAppeared(
            FCk_Delegate_Compass_EntryAppeared(this, n"OnEntryAppeared"));
        _Compass.BindTo_OnEntryDisappeared(
            FCk_Delegate_Compass_EntryDisappeared(this, n"OnEntryDisappeared"));

        // Let the empty compass settle a couple of frames first.
        // Frame-settle, not a condition: this phase asserts that NOTHING has
        // fired yet, so there is no observable to converge on — a predicate
        // would be true immediately and prove nothing.
        Add_Step_WaitFrames("let any spurious pre-POI signal land",      2);
        Add_Step(          "assert no signals yet, then create the POI", n"Step_AssertEmpty_CreatePoi");
        Add_Step_WaitUntil("the POI's entry appears on the compass",     n"Check_Appeared");
        Add_Step(          "assert appeared once, then destroy the owner", n"Step_AssertAppeared_Destroy");
        Add_Step_WaitUntil("the entry disappears from the compass",      n"Check_Disappeared");
        Add_Step(          "assert exactly one appear and one disappear", n"Step_AssertFinal");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertEmpty_CreatePoi(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AppearedCount, 0, "No signals before any POI exists");

        _PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(_PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(_PoiOwner, FCk_Poi_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestMembership")));
    }

    UFUNCTION()
    private void Step_AssertAppeared_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
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
    // Conditions — >= so an over-fire is caught by the "exactly once"
    // assertions above rather than never converging.
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

    UFUNCTION()
    private void OnEntryAppeared(FCk_Handle_Compass InCompass, FCk_Compass_Entry InEntry)
    {
        _AppearedCount++;
    }

    UFUNCTION()
    private void OnEntryDisappeared(FCk_Handle_Compass InCompass, FCk_Handle_Poi InPoi)
    {
        _DisappearedCount++;
    }

}
