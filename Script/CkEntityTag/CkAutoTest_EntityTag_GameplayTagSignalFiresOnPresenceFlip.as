// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: GAMEPLAY TAG SIGNAL FIRES ON FLIP
//============================================================================
//
// Mirror of CkAutoTest_EntityTag_SignalFiresOnPresenceFlip, but for the
// OnGameplayTagUpdated signal. Add the same gameplay tag twice + remove
// twice — exactly one Added + one Removed event for that tag.
//
// Same shape as its FName twin: the silent 2->1 hop has no event to wait on,
// so it settles for a fixed number of frames; the two presence flips are
// condition waits on the fire counter.
//============================================================================

class UCk_AutoTest_EntityTag_GameplayTagSignalFiresOnPresenceFlip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;
    private FGameplayTag _Tag;
    private int32 _AddedCount   = 0;
    private int32 _RemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        _Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");

        auto NoFilter = FGameplayTagContainer();
        utils_entity_tag::BindTo_OnGameplayTagUpdated(_Entity,
            NoFilter,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnGameplayTagUpdated(this, n"OnGameplayTagUpdated"));

        // Add twice — only first fires Added for THIS tag.
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _Tag);
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _Tag);

        Add_Step_WaitUntil( "Added fires once for A.B.C across two Adds", n"Check_Added");
        Add_Step(           "assert one Added, then remove (2 -> 1)",     n"Step_AssertAddedAndRemoveFirst");
        Add_Step_WaitFrames("let the silent 2->1 remove drain",           2);
        Add_Step(           "assert no Removed yet, then remove (1 -> 0)", n"Step_AssertSilentAndRemoveSecond");
        Add_Step_WaitUntil( "Removed fires on the 1->0 flip",             n"Check_Removed");
        Add_Step(           "assert exactly one Added and one Removed",   n"Step_AssertFinal");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertAddedAndRemoveFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedCount, 1,
            "OnGameplayTagUpdated::Added must fire exactly once for A.B.C across two Adds");
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire before any removes");

        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _Tag);
    }

    UFUNCTION()
    private void Step_AssertSilentAndRemoveSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire on the first remove (count 2->1)");

        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _Tag);
    }

    UFUNCTION()
    private void Step_AssertFinal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedCount, 1,
            "Removed must fire exactly once (count 1->0)");
        Assert_Equals_Int(_AddedCount, 1,
            "Added count must remain 1 — no extra fires from removes");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Added(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AddedCount >= 1);
    }

    UFUNCTION()
    private void Check_Removed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RemovedCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnGameplayTagUpdated(FCk_Handle InOwner, FGameplayTag InTag, ECk_EntityTagUpdate InUpdateType)
    {
        // Only count A.B.C events; parent FName chain fires on the FName signal, not this one.
        if (InTag.GetTagName() != n"AutoTestEt.A.B.C") { return; }

        if (InUpdateType == ECk_EntityTagUpdate::Added)
        {
            _AddedCount += 1;
        }
        else
        {
            _RemovedCount += 1;
        }
    }
}
