// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: BIND RELEVANT TAGS FILTER
//============================================================================
//
// BindTo_OnGameplayTagUpdated with a non-empty RelevantTags container must
// only fire the delegate when the tag passes the container's HasTag check.
// A matching tag fires; an unrelated tag does not.
//
// (BindTo_OnGameplayTagUpdated's `HasTag` is inclusive of parents in the
// container, so a filter {A.B} matches an event for A.B.C only if A.B.C is
// in the container — not just its parent. We test the literal filter match
// here to avoid coupling to that subtlety.)
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

        // Matching tag fires.
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagABC);

        WaitOneFrame(n"AfterMatchingAdd");
    }

    UFUNCTION()
    private void AfterMatchingAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_CallbackCount, 1,
            "Filtered binding must fire when the added tag matches the filter");

        // Non-matching tag does not fire.
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagXY);

        WaitOneFrame(n"AfterIrrelevantAdd");
    }

    UFUNCTION()
    private void AfterIrrelevantAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_CallbackCount, 1,
            "Filtered binding must NOT fire for tags outside the filter container");
        Assert_True(!_SawIrrelevant,
            "Filtered binding must NOT deliver the irrelevant tag's payload");

        FinishSuccess();
    }

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
