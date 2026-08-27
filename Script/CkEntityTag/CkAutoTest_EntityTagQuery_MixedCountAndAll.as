// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: MIXED COUNT(2) A + ALL B
//============================================================================
//
// Two requirements coexist on one query:
//   - Count(2) of tag A - capped at 2 matches, fires once on crossing
//   - All       of tag B - fires once per new match while satisfied
//
// Verifies:
//   1. Before the last-needed match is added, no fires.
//   2. The fire happens exactly when the last requirement crosses its
//      threshold (here: 1st B, after both A's are present).
//   3. While satisfied, each new B re-fires (All-mode contribution).
//   4. Tagging a 3rd A does NOT re-fire (Count-mode caps at 2).
//
// The two firing phases wait on the fire counter. The four phases that assert
// a NON-fire settle for a fixed number of frames: their witness would have to
// prove the QUERY re-evaluated, and a tag landing only proves the TAG pump
// ran - those are separate processors whose relative order this test should
// not encode.
//============================================================================

class UCk_AutoTest_EntityTagQuery_MixedCountAndAll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _A1;
    private FCk_Handle                _A2;
    private FCk_Handle                _A3;
    private FCk_Handle                _B1;
    private FCk_Handle                _B2;
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

        auto ReqA = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_MixA", 2);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(ReqA));

        auto ReqB = utils_entity_tag_query::Make_Requirement_All(n"AutoTestEtq_MixB");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(ReqB));

        Add_Step_WaitUntil( "both requirements register on a live query", n"Check_RequirementsRegistered");
        Add_Step(           "assert idle, then tag the first A",          n"Step_AssertIdleAndTagFirstA");
        Add_Step_WaitFrames("let the query evaluate 1-of-2 A",            3);
        Add_Step(           "assert still idle, then tag the second A",   n"Step_AssertIdleAndTagSecondA");
        Add_Step_WaitFrames("let the query evaluate 2-of-2 A, still no B", 3);
        Add_Step(           "assert All(B) still blocks, then tag a B",   n"Step_AssertIdleAndTagFirstB");
        Add_Step_WaitUntil( "the last requirement crossing fires once",   n"Check_FiredOnce");
        Add_Step(           "assert one fire, then tag a second B",       n"Step_AssertOneAndTagSecondB");
        Add_Step_WaitUntil( "All-mode re-fires on the new B",             n"Check_FiredTwice");
        Add_Step(           "assert two fires, then tag a third A",       n"Step_AssertTwoAndTagThirdA");
        Add_Step_WaitFrames("let the query evaluate the over-cap A",      3);
        Add_Step(           "assert Count(2) did not re-fire",            n"Step_AssertNoRefire");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertIdleAndTagFirstA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Empty result - must not have fired before any matches exist");

        _A1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A1, n"AutoTestEtq_MixA");
    }

    UFUNCTION()
    private void Step_AssertIdleAndTagSecondA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Only 1 of 2 A's and 0 B's - query is not satisfied yet");

        _A2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A2, n"AutoTestEtq_MixA");
    }

    UFUNCTION()
    private void Step_AssertIdleAndTagFirstB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Both A's present but still no B - All(B) requirement keeps query unsatisfied");

        _B1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_B1, n"AutoTestEtq_MixB");
    }

    UFUNCTION()
    private void Step_AssertOneAndTagSecondB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 1,
            "Last requirement crosses threshold (1st B with both A's present) - must fire exactly once");

        _B2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_B2, n"AutoTestEtq_MixB");
    }

    UFUNCTION()
    private void Step_AssertTwoAndTagThirdA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 2,
            "All-mode B requirement re-fires on each new B match while satisfied");

        _A3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A3, n"AutoTestEtq_MixA");
    }

    UFUNCTION()
    private void Step_AssertNoRefire(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 2,
            "Count(2) caps at 2; a 3rd A must NOT cause a re-fire");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_RequirementsRegistered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag_query::Get_AllRequirements(_Query).Num() >= 2);
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

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
