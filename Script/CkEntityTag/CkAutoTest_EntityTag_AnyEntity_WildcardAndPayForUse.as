// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ANY-ENTITY WILDCARD + PAY-FOR-WHAT-YOU-USE
//============================================================================
//
// Verifies J2 — two related guarantees in one test:
//   1) A wildcard listener (NAME_None filter) catches every tag added on any
//      entity, regardless of name.
//   2) After UnbindFrom_OnTagUpdated_AnyEntity, the listener is silent — the
//      fan-out cost is paid only by entities with a live subscription marker.
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_WildcardAndPayForUse : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle              _Listener;
    private FCk_Handle              _Subject;
    private int32                   _AddedFireCount   = 0;
    private int32                   _RemovedFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Listener = InHandle;

        // NAME_None is the wildcard filter — fire on any tag.
        utils_entity_tag::BindTo_OnTagUpdated_AnyEntity(_Listener,
            NAME_None,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        _Subject = utils_entity_lifetime::Request_CreateEntity(_Listener);
        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_WildA");
        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_WildB");

        WaitOneFrame(n"AfterAdds");
    }

    UFUNCTION()
    private void AfterAdds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AddedFireCount, 2,
            "Wildcard listener must catch every tag add — expected 2 fires for 2 distinct tags");

        // Unbind the wildcard listener and add another tag. The listener
        // must not fire again — pay-for-what-you-use.
        utils_entity_tag::UnbindFrom_OnTagUpdated_AnyEntity(_Listener,
            NAME_None,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_WildC");
        WaitOneFrame(n"AfterUnbindAdd");
    }

    UFUNCTION()
    private void AfterUnbindAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AddedFireCount, 2,
            "After UnbindFrom_OnTagUpdated_AnyEntity, no further fires must be observed");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnAnyTag(FName InTag, FCk_Handle InEntity, ECk_EntityTagUpdate InUpdate)
    {
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
