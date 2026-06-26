// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ANY-ENTITY LISTENER FIRES ON ADD
//============================================================================
//
// Verifies J2 — UCk_Utils_EntityTag_UE::BindTo_OnTagUpdated_AnyEntity with a
// specific FName filter fires when ANY entity gains that tag, exactly once
// per 0→1 presence flip. A subsequent add of a *different* tag must NOT
// re-fire the listener (filter is honored).
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_FiresOnAdd : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle              _Listener;
    private FCk_Handle              _Subject;
    private FName                   _LastTag;
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

        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_LastTag == n"AutoTestEt_Any_Foo",
            "Listener payload must carry the tag name that fired");
        Assert_True(_LastUpdateType == ECk_EntityTagUpdate::Added,
            "Update type must be Added on the 0->1 transition");
        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener must fire exactly once on the 0->1 transition");

        // Add a different tag to the same subject — listener has a specific
        // filter, so this must NOT fire.
        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_OtherTag");
        WaitOneFrame(n"AfterIrrelevantTag");
    }

    UFUNCTION()
    private void AfterIrrelevantTag(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener with a specific tag filter must NOT fire for other tags");

        FinishSuccess();
    }

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
