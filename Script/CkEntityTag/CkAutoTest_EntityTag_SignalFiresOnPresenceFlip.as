// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: SIGNAL FIRES ON PRESENCE FLIP
//============================================================================
//
// Pins the OnTagUpdated firing contract: the signal fires only on the
// 0->1 (Added) and 1->0 (Removed) transitions, not on intermediate count
// changes. Add twice / Remove twice produces exactly one Added + one
// Removed event.
//============================================================================

class UCk_AutoTest_EntityTag_SignalFiresOnPresenceFlip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;
    private int32 _AddedCount   = 0;
    private int32 _RemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;
        const FName Tag = n"AutoTestEt_FlipSignal";

        utils_entity_tag::BindTo_OnTagUpdated(_Entity,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated(this, n"OnTagUpdated"));

        utils_entity_tag::Add(_Entity, Tag);
        utils_entity_tag::Add(_Entity, Tag);

        WaitOneFrame(n"AfterFirstAdds");
    }

    UFUNCTION()
    private void AfterFirstAdds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AddedCount, 1,
            "Added must fire exactly once (count 0->1) after the pump drains both Add requests");
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire before any removes");

        utils_entity_tag::Request_TryRemove(_Entity, n"AutoTestEt_FlipSignal");
        WaitOneFrame(n"AfterFirstRemove");
    }

    UFUNCTION()
    private void AfterFirstRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire on the first remove (count 2->1)");

        utils_entity_tag::Request_TryRemove(_Entity, n"AutoTestEt_FlipSignal");
        WaitOneFrame(n"AfterSecondRemove");
    }

    UFUNCTION()
    private void AfterSecondRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_RemovedCount, 1,
            "Removed must fire exactly once (count 1->0)");
        Assert_Equals_Int(_AddedCount, 1,
            "Added count must remain 1 — no extra fires from removes");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnTagUpdated(FCk_Handle InOwner, FName InTagName, ECk_EntityTagUpdate InUpdateType)
    {
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
