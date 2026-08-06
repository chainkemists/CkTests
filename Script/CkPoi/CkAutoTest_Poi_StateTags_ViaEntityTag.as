// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: multiple state tags coexist and remove independently
//============================================================================
//
// Renamed from Poi_SetStateTags_ReplacesAll: CkPoi v2 has no composite
// "replace-all" state verb — state tags are plain CkEntityTag gameplay tags,
// which have no replace-all mutation exposed to AS (the composite RestoreSet
// is private hydration plumbing). This test preserves the surviving intent:
// several distinct state tags coexist on one POI entity and each removes
// independently, without disturbing the others or the POI's category tag. All
// EntityTag mutations are deferred one pump, so reads follow a settle frame.
//
// Isolated Y band: 53200.
//============================================================================

class UCk_AutoTest_Poi_StateTags_ViaEntityTag : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Owner;
    private FGameplayTag _Category;
    private FGameplayTag _TagA;
    private FGameplayTag _TagB;
    private FGameplayTag _TagC;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Owner.Request_OverrideToSelf();
        utils_transform::Add(_Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 53200.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        _Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Area");
        _TagA = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Discovered");
        _TagB = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Cleared");
        _TagC = utils_gameplay_tag::ResolveGameplayTag(n"Poi.State.Locked");

        utils_poi::Add(_Owner, FCk_Poi_Spec(_Category));

        utils_entity_tag::Add_UsingGameplayTag(_Owner, _TagA);
        utils_entity_tag::Add_UsingGameplayTag(_Owner, _TagB);
        utils_entity_tag::Add_UsingGameplayTag(_Owner, _TagC);

        WaitUntil(n"Check_AllThreePresent", n"OnSettled_AfterAdds");
    }

    // Both waits cross a real transition. The removal one is decisive rather
    // than satisfied-on-arrival because the first wait guarantees TagB IS
    // present when the remove is issued.
    UFUNCTION()
    private void Check_AllThreePresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Tags = utils_entity_tag::Get_AllTagsAsContainer(_Owner);

        auto Res = OutResult;
        Res.Set(Tags.HasTagExact(_TagA) && Tags.HasTagExact(_TagB) && Tags.HasTagExact(_TagC));
    }

    UFUNCTION()
    private void Check_TagBRemoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Tags = utils_entity_tag::Get_AllTagsAsContainer(_Owner);

        auto Res = OutResult;
        Res.Set(Tags.HasTagExact(_TagB) == false);
    }

    UFUNCTION()
    private void OnSettled_AfterAdds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Tags = utils_entity_tag::Get_AllTagsAsContainer(_Owner);
        Assert_True(Tags.HasTagExact(_TagA) && Tags.HasTagExact(_TagB) && Tags.HasTagExact(_TagC),
            "All three added state tags should coexist on the POI entity");
        Assert_True(Tags.HasTagExact(_Category),
            "The POI category tag should be independent of state tags and still present");

        // Remove exactly one state tag; the others (and the category) must survive.
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Owner, _TagB);
        WaitUntil(n"Check_TagBRemoved", n"OnSettled_AfterRemove");
    }

    UFUNCTION()
    private void OnSettled_AfterRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Tags = utils_entity_tag::Get_AllTagsAsContainer(_Owner);
        Assert_True(!Tags.HasTagExact(_TagB),
            "The removed state tag should be gone");
        Assert_True(Tags.HasTagExact(_TagA) && Tags.HasTagExact(_TagC),
            "The other state tags must be unaffected by an independent remove");
        Assert_True(Tags.HasTagExact(_Category),
            "The category tag must be unaffected by a state-tag remove");

        FinishSuccess();
    }
}
