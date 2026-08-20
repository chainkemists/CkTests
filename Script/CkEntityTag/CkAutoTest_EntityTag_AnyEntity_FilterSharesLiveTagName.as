// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ANY-ENTITY FILTER SHARES A LIVE TAG NAME
//============================================================================
//
// Verifies that a subscription filter and a live entity tag can share one
// FName in one registry. Both features key per-name entt storage pools by
// name hash; before the subscription id was salted they resolved the SAME
// pool under two different storage types (EnTT's type assert compiles out of
// UE builds, so that was silent pool aliasing). Production does exactly this:
// an NPC subscribes to a station kind tag that stations carry as a live tag.
//
// Order matters and is deliberate: the tag pool is created FIRST, so the
// subscription bind is the side that would have landed in the wrong-typed
// pool. The test then round-trips both directions — a second entity gaining
// the tag must fire Added, losing it must fire Removed — while Has() on both
// subjects proves the tag-side pool stayed intact throughout.
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_FilterSharesLiveTagName : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle          _Listener;
    private FCk_Handle          _Subject1;
    private FCk_Handle          _Subject2;
    private FName               _SharedName = n"AutoTestEt_Any_SharedName";
    private FName               _LastTag;
    private FCk_Handle          _LastEntity;
    private int32               _AddedFireCount   = 0;
    private int32               _RemovedFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Listener = InHandle;

        _Subject1 = utils_entity_lifetime::Request_CreateEntity(_Listener);
        utils_entity_tag::Add(_Subject1, _SharedName);

        Add_Step_WaitUntil("the tag pool exists before the subscription binds", n"Check_Subject1Tagged");
        Add_Step(          "bind on the SAME name, tag a second entity",        n"Step_BindAndAddSecond");
        Add_Step_WaitUntil("the listener fires Added for the second entity",    n"Check_AddedFired");
        Add_Step(          "assert the add, then remove the second tag",        n"Step_AssertAddAndRemove");
        Add_Step_WaitUntil("the listener fires Removed",                        n"Check_RemovedFired");
        Add_Step(          "assert the remove and the intact tag side",         n"Step_AssertFinal");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_BindAndAddSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::BindTo_OnTagUpdated_AnyEntity(_Listener,
            _SharedName,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        _Subject2 = utils_entity_lifetime::Request_CreateEntity(_Listener);
        utils_entity_tag::Add(_Subject2, _SharedName);
    }

    UFUNCTION()
    private void Step_AssertAddAndRemove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener must fire exactly once, for the second entity's 0->1 flip");
        Assert_True(_LastTag == _SharedName,
            "Payload must carry the shared name");
        Assert_True(_LastEntity == _Subject2,
            "Payload must carry the entity that gained the tag, not the pre-tagged one");
        Assert_True(utils_entity_tag::Has(_Subject1, _SharedName),
            "The pre-existing tag must survive the subscription bind");
        Assert_True(utils_entity_tag::Has(_Subject2, _SharedName),
            "The second entity's tag must be live alongside the subscription");

        utils_entity_tag::Request_TryRemove(_Subject2, _SharedName);
    }

    UFUNCTION()
    private void Step_AssertFinal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedFireCount, 1,
            "Listener must fire Removed exactly once for the second entity");
        Assert_Equals_Int(_AddedFireCount, 1,
            "The remove must not re-fire Added");
        Assert_True(utils_entity_tag::Has(_Subject2, _SharedName) == false,
            "The second entity's tag must be gone after the remove");
        Assert_True(utils_entity_tag::Has(_Subject1, _SharedName),
            "The first entity's tag must be untouched by the second's removal");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Subject1Tagged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Subject1, _SharedName));
    }

    UFUNCTION()
    private void Check_AddedFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AddedFireCount >= 1);
    }

    UFUNCTION()
    private void Check_RemovedFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RemovedFireCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnAnyTag(FName InTag, FCk_Handle InEntity, ECk_EntityTagUpdate InUpdate)
    {
        _LastTag    = InTag;
        _LastEntity = InEntity;

        if (InUpdate == ECk_EntityTagUpdate::Added)
        {
            _AddedFireCount += 1;
        }
        else
        {
            _RemovedFireCount += 1;
        }
    }
}
