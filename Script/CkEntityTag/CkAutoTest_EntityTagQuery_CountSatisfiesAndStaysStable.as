// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: COUNT(2) SATISFIES AND STAYS STABLE
//============================================================================
//
// Spawn a query "I need 2 entities tagged A". Tag 1 entity -> no fire. Tag a 2nd
// -> fires once. Tag a 3rd -> no extra fire (Count is capped, no All-mode re-fire).
//
// The one phase that crosses the threshold waits on the fire counter. The
// under-threshold and over-cap phases both assert a NON-event, and their
// witness would have to prove the QUERY re-evaluated, not merely that the tag
// landed - the tag pump and the query evaluator are separate processors and
// their relative order is not something this test should encode. Those two
// phases settle for a fixed number of frames instead, which is robust to that
// ordering either way.
//============================================================================

class UCk_AutoTest_EntityTagQuery_CountSatisfiesAndStaysStable : UCk_AutoTest_Base
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

        auto Req = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_A", 2);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        Add_Step_WaitUntil( "the requirement registers on a live query",  n"Check_RequirementRegistered");
        Add_Step(           "assert idle, then tag the first entity",     n"Step_AssertIdleAndTagFirst");
        Add_Step_WaitFrames("let the query evaluate 1-of-2",              3);
        Add_Step(           "assert still idle, then tag the second",     n"Step_AssertStillIdleAndTagSecond");
        Add_Step_WaitUntil( "crossing the threshold fires OnSatisfied",   n"Check_FiredOnce");
        Add_Step(           "assert one fire, then tag a third entity",   n"Step_AssertOneAndTagThird");
        Add_Step_WaitFrames("let the query evaluate the over-cap match",  3);
        Add_Step(           "assert Count mode did not re-fire",          n"Step_AssertNoRefire");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertIdleAndTagFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Empty result set must not fire");

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_A");
    }

    UFUNCTION()
    private void Step_AssertStillIdleAndTagSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Only 1 of 2 - query must not have fired yet");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_A");
    }

    UFUNCTION()
    private void Step_AssertOneAndTagThird(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 1,
            "Threshold (2) crossed - must fire exactly once");

        _E3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E3, n"AutoTestEtq_A");
    }

    UFUNCTION()
    private void Step_AssertNoRefire(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 1,
            "Count mode caps at 2; the 3rd tagged entity must not trigger a re-fire");
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

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
