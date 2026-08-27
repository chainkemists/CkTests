// Language=angelscript

//============================================================================
// CK ENTITY TAG - AUTOMATION TEST: SIGNAL FIRES ON PRESENCE FLIP
//============================================================================
//
// Pins the OnTagUpdated firing contract: the signal fires only on the
// 0->1 (Added) and 1->0 (Removed) transitions, not on intermediate count
// changes. Add twice / Remove twice produces exactly one Added + one
// Removed event.
//
// The middle hop is a FIXED-FRAME settle on purpose. Its whole point is that
// the 2->1 remove fires NOTHING, so there is no event to wait on - a
// condition wait there would either be true on entry (proving nothing) or
// never satisfied (timing out on correct behavior). The two hops that DO
// cross a presence flip are condition waits on the fire counter.
//============================================================================

class UCk_AutoTest_EntityTag_SignalFiresOnPresenceFlip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;
    private FName _Tag = n"AutoTestEt_FlipSignal";
    private int32 _AddedCount   = 0;
    private int32 _RemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;

        utils_entity_tag::BindTo_OnTagUpdated(_Entity,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated(this, n"OnTagUpdated"));

        utils_entity_tag::Add(_Entity, _Tag);
        utils_entity_tag::Add(_Entity, _Tag);

        Add_Step_WaitUntil( "Added fires on the 0->1 flip",              n"Check_Added");
        Add_Step(           "assert one Added, then remove (2 -> 1)",    n"Step_AssertAddedAndRemoveFirst");
        Add_Step_WaitFrames("let the silent 2->1 remove drain",          2);
        Add_Step(           "assert no Removed yet, then remove (1 -> 0)", n"Step_AssertSilentAndRemoveSecond");
        Add_Step_WaitUntil( "Removed fires on the 1->0 flip",            n"Check_Removed");
        Add_Step(           "assert exactly one Added and one Removed",  n"Step_AssertFinal");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertAddedAndRemoveFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedCount, 1,
            "Added must fire exactly once (count 0->1) after the pump drains both Add requests");
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire before any removes");

        utils_entity_tag::Request_TryRemove(_Entity, _Tag);
    }

    UFUNCTION()
    private void Step_AssertSilentAndRemoveSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedCount, 0,
            "Removed must not fire on the first remove (count 2->1)");

        utils_entity_tag::Request_TryRemove(_Entity, _Tag);
    }

    UFUNCTION()
    private void Step_AssertFinal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedCount, 1,
            "Removed must fire exactly once (count 1->0)");
        Assert_Equals_Int(_AddedCount, 1,
            "Added count must remain 1 - no extra fires from removes");
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
