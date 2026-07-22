// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: enable/disable via the Poi.Disabled EntityTag
//============================================================================
//
// CkPoi v2: enable/disable is a CkEntityTag convention, not a Poi request.
// A disabled POI carries the Poi.Disabled gameplay tag; projectors skip it.
// Disabling (Add_UsingGameplayTag) fires OnGameplayTagUpdated::Added once;
// re-enabling (Request_TryRemove_UsingGameplayTag) fires ::Removed once. The
// bind is filtered to Poi.Disabled so category-tag noise never counts. All
// EntityTag mutations are deferred one pump, so each is followed by a settle.
//
// Isolated Y band: 52800.
//============================================================================

class UCk_AutoTest_Poi_EnableDisable_FiresSignal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Owner;
    private FGameplayTag _DisabledTag;
    private int32 _SignalCount = 0;
    private ECk_EntityTagUpdate _LastUpdate = ECk_EntityTagUpdate::Removed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Owner.Request_OverrideToSelf();
        utils_transform::Add(_Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52800.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Door");
        utils_poi::Add(_Owner, FCk_Fragment_Poi_ParamsData(Category));

        _DisabledTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Disabled");

        auto RelevantTags = FGameplayTagContainer();
        RelevantTags.AddTag(_DisabledTag);
        utils_entity_tag::BindTo_OnGameplayTagUpdated(_Owner,
            RelevantTags,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnGameplayTagUpdated(this, n"OnDisabledTagUpdated"));

        // Disable: add the Poi.Disabled tag (0 -> 1 flip fires Added).
        utils_entity_tag::Add_UsingGameplayTag(_Owner, _DisabledTag);
        WaitOneFrame(n"OnSettled_AfterDisable");
    }

    UFUNCTION()
    private void OnDisabledTagUpdated(FCk_Handle InOwner, FGameplayTag InTag, ECk_EntityTagUpdate InUpdateType)
    {
        if ((InTag == _DisabledTag) == false) { return; }
        _SignalCount++;
        _LastUpdate = InUpdateType;
    }

    UFUNCTION()
    private void OnSettled_AfterDisable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 1, "Disable should fire OnGameplayTagUpdated once");
        Assert_True(_LastUpdate == ECk_EntityTagUpdate::Added,
            "The disable event should carry Added");
        Assert_True(utils_entity_tag::Has_UsingGameplayTag(_Owner, _DisabledTag),
            "The POI should carry Poi.Disabled (be disabled) after the add settles");

        // Enable: remove the tag (1 -> 0 flip fires Removed).
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Owner, _DisabledTag);
        WaitOneFrame(n"OnSettled_AfterEnable");
    }

    UFUNCTION()
    private void OnSettled_AfterEnable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 2, "Re-enable should fire OnGameplayTagUpdated again");
        Assert_True(_LastUpdate == ECk_EntityTagUpdate::Removed,
            "The enable event should carry Removed");
        Assert_True(!utils_entity_tag::Has_UsingGameplayTag(_Owner, _DisabledTag),
            "The POI should no longer carry Poi.Disabled (be enabled) after the remove settles");

        FinishSuccess();
    }
}
