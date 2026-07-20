// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: state-tag add/remove fires signals; no-ops don't
//============================================================================
//
// Request_AddStateTag / Request_RemoveStateTag must mutate Get_StateTags and
// fire OnPoiStateChanged only on ACTUAL change: adding an already-present
// tag or removing an absent tag is a no-op and must NOT fire.
//
// Isolated Y band: 53000.
//============================================================================

class UCk_AutoTest_Poi_StateTags_AddRemove_FiresSignals : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Poi _Poi;
    private FGameplayTag _LockedTag;
    private int32 _SignalCount = 0;
    private FGameplayTagContainer _LastTags;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 53000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Door");
        _LockedTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Locked");

        _Poi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(Category));
        _Poi.BindTo_OnStateChanged(
            FCk_Delegate_Poi_StateChanged(this, n"OnStateChanged"));

        _Poi.Request_AddStateTag(FCk_Request_Poi_AddStateTag(_LockedTag));
        WaitOneFrame(n"OnSettled_AfterAdd");
    }

    UFUNCTION()
    private void OnStateChanged(FCk_Handle_Poi InPoi, FGameplayTagContainer InStateTags)
    {
        _SignalCount++;
        _LastTags = InStateTags;
    }

    UFUNCTION()
    private void OnSettled_AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 1, "Adding a new state tag should fire OnPoiStateChanged once");
        Assert_True(_LastTags.HasTag(_LockedTag), "Signal payload should contain the added tag");
        Assert_True(utils_poi::Get_StateTags(_Poi).HasTag(_LockedTag),
            "Get_StateTags should contain the added tag");

        // No-op: same tag again.
        _Poi.Request_AddStateTag(FCk_Request_Poi_AddStateTag(_LockedTag));
        WaitOneFrame(n"OnSettled_AfterNoOpAdd");
    }

    UFUNCTION()
    private void OnSettled_AfterNoOpAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 1, "Re-adding an existing tag is a no-op and must NOT fire");

        _Poi.Request_RemoveStateTag(FCk_Request_Poi_RemoveStateTag(_LockedTag));
        WaitOneFrame(n"OnSettled_AfterRemove");
    }

    UFUNCTION()
    private void OnSettled_AfterRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 2, "Removing a present tag should fire OnPoiStateChanged");
        Assert_True(!utils_poi::Get_StateTags(_Poi).HasTag(_LockedTag),
            "Get_StateTags should no longer contain the removed tag");

        // No-op: remove an absent tag.
        _Poi.Request_RemoveStateTag(FCk_Request_Poi_RemoveStateTag(_LockedTag));
        WaitOneFrame(n"OnSettled_AfterNoOpRemove");
    }

    UFUNCTION()
    private void OnSettled_AfterNoOpRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 2, "Removing an absent tag is a no-op and must NOT fire");
        FinishSuccess();
    }
}
