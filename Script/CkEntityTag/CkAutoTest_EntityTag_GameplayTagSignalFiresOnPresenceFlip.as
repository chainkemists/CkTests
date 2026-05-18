// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: GAMEPLAY TAG SIGNAL FIRES ON FLIP
//============================================================================
//
// Mirror of CkAutoTest_EntityTag_SignalFiresOnPresenceFlip, but for the
// OnGameplayTagUpdated signal. Add the same gameplay tag twice + remove
// twice — exactly one Added + one Removed event for that tag.
//============================================================================

class UCk_AutoTest_EntityTag_GameplayTagSignalFiresOnPresenceFlip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private int32 _AddedCount   = 0;
    private int32 _RemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");

        auto NoFilter = FGameplayTagContainer();
        utils_entity_tag::BindTo_OnGameplayTagUpdated(LocalHandle,
            NoFilter,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnGameplayTagUpdated(this, n"OnGameplayTagUpdated"));

        // Add twice — only first fires Added for THIS tag.
        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, Tag);
        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, Tag);
        Assert_Equals_Int(_AddedCount, 1,
            "OnGameplayTagUpdated::Added must fire exactly once for A.B.C across two Adds");

        // Remove twice — only second fires Removed.
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(LocalHandle, Tag);
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire on the first remove (count 2->1)");
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(LocalHandle, Tag);
        Assert_Equals_Int(_RemovedCount, 1,
            "Removed must fire exactly once (count 1->0)");

        FinishSuccess();
    }

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
