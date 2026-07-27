// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ANY-ENTITY LISTENER FIRES ON ADD
//============================================================================
//
// Verifies J2 — UCk_Utils_EntityTag_UE::BindTo_OnTagUpdated_AnyEntity with a
// specific FName filter fires when ANY entity gains that tag, exactly once
// per 0→1 presence flip. A subsequent add of a *different* tag must NOT
// re-fire the listener (filter is honored).
//
// The second phase asserts a NON-event, so it waits on a WITNESS instead: the
// unrelated tag becoming present proves the pump drained that add. If the
// filter were broken the listener would have fired during that same drain, so
// the silence assertion is decisive rather than merely delayed.
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_FiresOnAdd : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle              _Listener;
    private FCk_Handle              _Subject;
    private FName                   _LastTag;
    private FName                   _OtherTag = n"AutoTestEt_Any_OtherTag";
    private ECk_EntityTagUpdate     _LastUpdateType = ECk_EntityTagUpdate::Added;
    private int32                   _AddedFireCount   = 0;
    private int32                   _RemovedFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Listener = InHandle;

        utils_entity_tag::BindTo_OnTagUpdated_AnyEntity(_Listener,
            n"AutoTestEt_Any_Foo",
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        _Subject = utils_entity_lifetime::Request_CreateEntity(_Listener);
        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_Foo");

        Add_Step_WaitUntil("listener fires on the 0->1 flip",            n"Check_Added");
        Add_Step(          "assert the payload, then add an off-filter tag", n"Step_AssertAndAddOther");
        Add_Step_WaitUntil("the off-filter tag lands (drain witness)",   n"Check_OtherLanded");
        Add_Step(          "assert the filtered listener stayed silent", n"Step_AssertNoRefire");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertAndAddOther(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastTag == n"AutoTestEt_Any_Foo",
            "Listener payload must carry the tag name that fired");
        Assert_True(_LastUpdateType == ECk_EntityTagUpdate::Added,
            "Update type must be Added on the 0->1 transition");
        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener must fire exactly once on the 0->1 transition");

        utils_entity_tag::Add(_Subject, _OtherTag);
    }

    UFUNCTION()
    private void Step_AssertNoRefire(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener with a specific tag filter must NOT fire for other tags");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Added(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AddedFireCount >= 1);
    }

    UFUNCTION()
    private void Check_OtherLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Subject, _OtherTag));
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnAnyTag(FName InTag, FCk_Handle InEntity, ECk_EntityTagUpdate InUpdate)
    {
        _LastTag        = InTag;
        _LastUpdateType = InUpdate;

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
