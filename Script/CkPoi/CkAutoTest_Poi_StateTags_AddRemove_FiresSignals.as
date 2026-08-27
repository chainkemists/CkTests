// Language=angelscript

//============================================================================
// CK POI - AUTOMATION TEST: state-tag add/remove fires signals on flips only
//============================================================================
//
// CkPoi v2: state tags are plain CkEntityTag gameplay tags on the POI entity.
// Add_UsingGameplayTag / Request_TryRemove_UsingGameplayTag mutate the set;
// OnGameplayTagUpdated fires ONLY on the 0<->1 presence flip (adds are
// COUNTED), never on intermediate count changes. The bind is filtered to the
// state tag so the Poi.Category.* tag never counts. Every mutation is deferred
// one pump, so each is followed by a settle frame.
//
// Isolated Y band: 53000.
//============================================================================

class UCk_AutoTest_Poi_StateTags_AddRemove_FiresSignals : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _Owner;
    private FGameplayTag _LockedTag;
    private int32 _AddedCount = 0;
    private int32 _RemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Owner.Request_OverrideToSelf();
        utils_transform::Add(_Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 53000.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Door");
        utils_poi::Add(_Owner, FCk_Fragment_Poi_ParamsData(Category));

        _LockedTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Locked");

        auto RelevantTags = FGameplayTagContainer();
        RelevantTags.AddTag(_LockedTag);
        utils_entity_tag::BindTo_OnGameplayTagUpdated(_Owner,
            RelevantTags,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnGameplayTagUpdated(this, n"OnStateTagUpdated"));

        // Add a new state tag (0 -> 1): fires Added once.
        utils_entity_tag::Add_UsingGameplayTag(_Owner, _LockedTag);
        WaitUntil(n"Check_AddedFired", n"OnSettled_AfterAdd");
    }

    // Only the two PRESENCE FLIPS (0->1, 1->0) have an event to wait on. The
    // counted middle hops (1->2, 2->1) exist precisely to prove nothing fires,
    // and no count accessor is exposed to script, so Has is true on both sides
    // of each - a condition there would be true on entry or never satisfy.
    // Those settle for frames, which is the unit the request pump advances in.
    UFUNCTION()
    private void Check_AddedFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AddedCount >= 1);
    }

    UFUNCTION()
    private void Check_RemovedFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RemovedCount >= 1);
    }

    UFUNCTION()
    private void OnStateTagUpdated(FCk_Handle InOwner, FGameplayTag InTag, ECk_EntityTagUpdate InUpdateType)
    {
        if ((InTag == _LockedTag) == false) { return; }
        if (InUpdateType == ECk_EntityTagUpdate::Added) { _AddedCount++; }
        else                                            { _RemovedCount++; }
    }

    UFUNCTION()
    private void OnSettled_AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AddedCount, 1, "Adding a new state tag should fire Added once");
        Assert_True(utils_entity_tag::Get_AllTagsAsContainer(_Owner).HasTagExact(_LockedTag),
            "The state tag set should contain the added tag");

        // Counted re-add (1 -> 2): no presence flip, must NOT fire.
        utils_entity_tag::Add_UsingGameplayTag(_Owner, _LockedTag);
        WaitFrames(2, n"OnSettled_AfterCountedAdd");
    }

    UFUNCTION()
    private void OnSettled_AfterCountedAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AddedCount, 1, "A counted re-add (1->2) is not a flip and must NOT fire");

        // First remove (2 -> 1): still present, must NOT fire.
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Owner, _LockedTag);
        WaitFrames(2, n"OnSettled_AfterFirstRemove");
    }

    UFUNCTION()
    private void OnSettled_AfterFirstRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_RemovedCount, 0, "A remove that leaves the tag present (2->1) must NOT fire");
        Assert_True(utils_entity_tag::Get_AllTagsAsContainer(_Owner).HasTagExact(_LockedTag),
            "The tag should still be present after a single counted remove");

        // Second remove (1 -> 0): presence flip, fires Removed once.
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Owner, _LockedTag);
        WaitUntil(n"Check_RemovedFired", n"OnSettled_AfterFinalRemove");
    }

    UFUNCTION()
    private void OnSettled_AfterFinalRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_RemovedCount, 1, "Removing the last count (1->0) should fire Removed once");
        Assert_True(!utils_entity_tag::Get_AllTagsAsContainer(_Owner).HasTagExact(_LockedTag),
            "The state tag set should no longer contain the removed tag");

        // Remove an absent tag (0 -> 0): no-op, must NOT fire.
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Owner, _LockedTag);
        WaitOneFrame(n"OnSettled_AfterNoOpRemove");
    }

    UFUNCTION()
    private void OnSettled_AfterNoOpRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_RemovedCount, 1, "Removing an absent tag is a no-op and must NOT fire");
        Assert_Equals_Int(_AddedCount, 1, "Added count must remain 1 - no extra fires");
        FinishSuccess();
    }
}
