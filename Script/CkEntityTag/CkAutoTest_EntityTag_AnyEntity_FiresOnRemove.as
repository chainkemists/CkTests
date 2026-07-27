// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ANY-ENTITY LISTENER FIRES ON REMOVE
//============================================================================
//
// Verifies J2 — BindTo_OnTagUpdated_AnyEntity fires Removed when an entity
// transitions 1→0 on the filtered tag via Request_TryRemove.
//
// Each phase waits on the fan-out COUNT rising, which is the settling event;
// the exactly-once and last-update-type contracts stay assertions, so an
// over-fire is reported as a count mismatch rather than swallowed.
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_FiresOnRemove : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle              _Listener;
    private FCk_Handle              _Subject;
    private ECk_EntityTagUpdate     _LastUpdateType = ECk_EntityTagUpdate::Added;
    private int32                   _AddedFireCount   = 0;
    private int32                   _RemovedFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Listener = InHandle;

        utils_entity_tag::BindTo_OnTagUpdated_AnyEntity(_Listener,
            n"AutoTestEt_Any_Bar",
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        _Subject = utils_entity_lifetime::Request_CreateEntity(_Listener);
        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_Bar");

        Add_Step_WaitUntil("listener sees the 0->1 Added fan-out",  n"Check_Added");
        Add_Step(          "remove the tag from the subject",       n"Step_Remove");
        Add_Step_WaitUntil("listener sees the 1->0 Removed fan-out", n"Check_Removed");
        Add_Step(          "assert exactly-once fan-out semantics", n"Step_AssertOnce");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Remove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener must have fired Added once after the initial 0->1 transition");

        utils_entity_tag::Request_TryRemove(_Subject, n"AutoTestEt_Any_Bar");
    }

    UFUNCTION()
    private void Step_AssertOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedFireCount, 1,
            "Request_TryRemove crossing 1->0 must fire Removed exactly once");
        Assert_True(_LastUpdateType == ECk_EntityTagUpdate::Removed,
            "Last update type observed must be Removed");
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
    private void Check_Removed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RemovedFireCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnAnyTag(FName InTag, FCk_Handle InEntity, ECk_EntityTagUpdate InUpdate)
    {
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
