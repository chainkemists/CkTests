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
//
// The post-unbind phase asserts a NON-event, so it waits on a WITNESS: the
// third tag becoming present proves the pump drained that add. A listener
// that failed to unbind would have fired during that same drain.
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_WildcardAndPayForUse : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle              _Listener;
    private FCk_Handle              _Subject;
    private FName                   _TagC = n"AutoTestEt_Any_WildC";
    private int32                   _AddedFireCount   = 0;
    private int32                   _RemovedFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        Add_Step_WaitUntil("wildcard listener catches both adds",       n"Check_BothCaught");
        Add_Step(          "assert two fires, unbind, add a third tag", n"Step_AssertUnbindAndAdd");
        Add_Step_WaitUntil("the third tag lands (drain witness)",       n"Check_ThirdLanded");
        Add_Step(          "assert the unbound listener stayed silent", n"Step_AssertSilent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertUnbindAndAdd(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedFireCount, 2,
            "Wildcard listener must catch every tag add — expected 2 fires for 2 distinct tags");

        utils_entity_tag::UnbindFrom_OnTagUpdated_AnyEntity(_Listener,
            NAME_None,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        utils_entity_tag::Add(_Subject, _TagC);
    }

    UFUNCTION()
    private void Step_AssertSilent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedFireCount, 2,
            "After UnbindFrom_OnTagUpdated_AnyEntity, no further fires must be observed");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_BothCaught(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AddedFireCount >= 2);
    }

    UFUNCTION()
    private void Check_ThirdLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Subject, _TagC));
    }

    //------------------------------------------------------------------------

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
