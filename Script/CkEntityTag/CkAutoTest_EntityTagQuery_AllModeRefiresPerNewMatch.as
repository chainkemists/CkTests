// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: ALL-MODE RE-FIRES PER NEW MATCH
//============================================================================
//
// All-mode requirement on tag B. Each new entity tagged B should re-fire
// OnSatisfied. Three additions -> three fires.
//
// Every match phase waits on the fire counter reaching that match's expected
// value, so a slow-but-correct evaluation pass no longer reads as a failure.
// The counters wait on >= N and assert == N, so an EXTRA fire is reported by
// the assertion rather than hanging until the deadline.
//
// The opening phase asserts a non-event (nothing matches yet), so it waits on
// the requirement itself being registered - proof the query is live and has
// evaluated at least once with an empty result set.
//============================================================================

class UCk_AutoTest_EntityTagQuery_AllModeRefiresPerNewMatch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private FCk_Handle                _E2;
    private FCk_Handle                _E3;
    private int32                     _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;
        _Query = utils_entity_tag_query::Add(_Owner);

        utils_entity_tag_query::BindTo_OnSatisfied(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnSatisfied(this, n"OnSatisfied"));

        auto Req = utils_entity_tag_query::Make_Requirement_All(n"AutoTestEtq_B");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        Add_Step_WaitUntil("the requirement registers on a live query", n"Check_RequirementRegistered");
        Add_Step(          "assert no fire on an empty result set",     n"Step_AssertIdleAndTagFirst");
        Add_Step_WaitUntil("the first match fires OnSatisfied",         n"Check_FiredOnce");
        Add_Step(          "assert one fire, then tag a second entity", n"Step_AssertOneAndTagSecond");
        Add_Step_WaitUntil("the second match re-fires",                 n"Check_FiredTwice");
        Add_Step(          "assert two fires, then tag a third entity", n"Step_AssertTwoAndTagThird");
        Add_Step_WaitUntil("the third match re-fires",                  n"Check_FiredThrice");
        Add_Step(          "assert three fires total",                  n"Step_AssertThree");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertIdleAndTagFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Empty result - must not have fired yet");

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_B");
    }

    UFUNCTION()
    private void Step_AssertOneAndTagSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 1,
            "All-mode: first match crosses threshold (>=1), must fire once");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_B");
    }

    UFUNCTION()
    private void Step_AssertTwoAndTagThird(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 2,
            "All-mode: each new match while satisfied re-fires; expected 2 fires after 2 matches");

        _E3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E3, n"AutoTestEtq_B");
    }

    UFUNCTION()
    private void Step_AssertThree(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 3,
            "All-mode: third match must re-fire, expected 3 fires total");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_RequirementRegistered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag_query::Get_AllRequirements(_Query).Num() >= 1);
    }

    UFUNCTION()
    private void Check_FiredOnce(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCount >= 1);
    }

    UFUNCTION()
    private void Check_FiredTwice(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCount >= 2);
    }

    UFUNCTION()
    private void Check_FiredThrice(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCount >= 3);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
