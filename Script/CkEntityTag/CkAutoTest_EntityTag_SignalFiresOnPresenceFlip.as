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
    default _TimeoutSeconds = 3.0f;

    private int32 _AddedCount   = 0;
    private int32 _RemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        const FName Tag = n"AutoTestEt_FlipSignal";

        utils_entity_tag::BindTo_OnTagUpdated(LocalHandle,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated(this, n"OnTagUpdated"));

        // Add twice — only the first should fire Added.
        utils_entity_tag::Add(LocalHandle, Tag);
        utils_entity_tag::Add(LocalHandle, Tag);
        Assert_Equals_Int(_AddedCount, 1,
            "Added must fire exactly once (count 0->1), not on the second Add (1->2)");
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire before any removes");

        // Remove twice — only the second should fire Removed.
        utils_entity_tag::Request_TryRemove(LocalHandle, Tag);
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire on the first remove (count 2->1)");
        utils_entity_tag::Request_TryRemove(LocalHandle, Tag);
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
