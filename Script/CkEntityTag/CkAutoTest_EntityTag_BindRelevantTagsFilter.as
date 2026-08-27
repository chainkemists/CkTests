// Language=angelscript

//============================================================================
// CK ENTITY TAG - AUTOMATION TEST: BIND RELEVANT TAGS FILTER
//============================================================================
//
// BindTo_OnGameplayTagUpdated with a non-empty RelevantTags container must
// only fire the delegate when the tag passes the container's HasTag check.
// A matching tag fires; an unrelated tag does not.
//
// (BindTo_OnGameplayTagUpdated's `HasTag` is inclusive of parents in the
// container, so a filter {A.B} matches an event for A.B.C only if A.B.C is
// in the container - not just its parent. We test the literal filter match
// here to avoid coupling to that subtlety.)
//
// The suppression phase asserts a NON-event, so it waits on a WITNESS: the
// off-filter tag becoming present proves the pump drained that add, and a
// broken filter would have fired the delegate during the same drain.
//============================================================================

class UCk_AutoTest_EntityTag_BindRelevantTagsFilter : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FGameplayTag _TagABC;
    private FGameplayTag _TagXY;
    private int32 _CallbackCount  = 0;
    private bool  _SawIrrelevant  = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        _TagABC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        _TagXY  = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.X.Y");

        auto Filter = FGameplayTagContainer();
        Filter.AddTag(_TagABC);

        utils_entity_tag::BindTo_OnGameplayTagUpdated(_Entity,
            Filter,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnGameplayTagUpdated(this, n"OnGameplayTagUpdated"));

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagABC);

        Add_Step_WaitUntil("the matching tag fires the filtered binding", n"Check_Fired");
        Add_Step(          "assert one fire, then add an off-filter tag", n"Step_AssertAndAddOther");
        Add_Step_WaitUntil("the off-filter tag lands (drain witness)",    n"Check_OtherLanded");
        Add_Step(          "assert the filter suppressed it",             n"Step_AssertFiltered");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertAndAddOther(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_CallbackCount, 1,
            "Filtered binding must fire when the added tag matches the filter");

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagXY);
    }

    UFUNCTION()
    private void Step_AssertFiltered(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_CallbackCount, 1,
            "Filtered binding must NOT fire for tags outside the filter container");
        Assert_True(!_SawIrrelevant,
            "Filtered binding must NOT deliver the irrelevant tag's payload");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Fired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CallbackCount >= 1);
    }

    UFUNCTION()
    private void Check_OtherLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"AutoTestEt.X.Y"));
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnGameplayTagUpdated(FCk_Handle InOwner, FGameplayTag InTag, ECk_EntityTagUpdate InUpdateType)
    {
        _CallbackCount += 1;
        if (InTag.GetTagName() == n"AutoTestEt.X.Y")
        {
            _SawIrrelevant = true;
        }
    }
}
