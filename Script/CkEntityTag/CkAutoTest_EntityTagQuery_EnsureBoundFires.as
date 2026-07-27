// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: ENSURE-BOUND FIRES WHEN EXCEEDED
//============================================================================
//
// Make_Requirement_Of_WithEnsure(n"X", 2, 4) — Count=2 with MaxAllowedEnsure=4.
// Tag 5 entities. The processor's CK_ENSURE_IF_NOT(GlobalCount <= MaxAllowed)
// must trip when the 5th tag is processed (global count 5 > MaxAllowed 4).
//
// The ensure does NOT halt evaluation — it merely surfaces a diagnostic.
// We assert the test reaches the end normally, while the wrapper actor
// registers the expected "exceeded MaxAllowed" log text so the automation
// framework doesn't auto-fail the test on its own deliberate diagnostic.
//
// The wait is on ALL FIVE tags being present, deliberately NOT on
// Get_IsSatisfied. Satisfaction is reached at the SECOND entity (Count is 2),
// so a wait on it could release while entities 3-5 were still pending — and
// the ensure this test exists to provoke only trips on the fifth.
//============================================================================

class UCk_AutoTest_EntityTagQuery_EnsureBoundFires : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private FCk_Handle                _E2;
    private FCk_Handle                _E3;
    private FCk_Handle                _E4;
    private FCk_Handle                _E5;
    private FName                     _Tag = n"AutoTestEtq_Ensure";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        auto Req = utils_entity_tag_query::Make_Requirement_Of_WithEnsure(
            n"AutoTestEtq_Ensure", 2, 4);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        // Tag 5 entities — strictly more than the MaxAllowed of 4.
        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, _Tag);

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, _Tag);

        _E3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E3, _Tag);

        _E4 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E4, _Tag);

        _E5 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E5, _Tag);

        Add_Step_WaitUntil("all five tags land, exceeding MaxAllowed",  n"Check_AllFiveTagged");
        Add_Step(          "assert evaluation continued past the ensure", n"Step_AssertStillSatisfied");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertStillSatisfied(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Diagnostic-only ensure — query evaluation continues, so this step is
        // reached normally. The wrapper actor declares the expected log message
        // so the framework doesn't escalate the ensure to a test failure.
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query),
            "Query with Count(2) must still report satisfied (5 >= 2); the ensure is purely diagnostic");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_AllFiveTagged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_E1, _Tag)
             && utils_entity_tag::Has(_E2, _Tag)
             && utils_entity_tag::Has(_E3, _Tag)
             && utils_entity_tag::Has(_E4, _Tag)
             && utils_entity_tag::Has(_E5, _Tag));
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR — registers the deliberate-ensure log pattern.
//============================================================================

class ACk_AutoTest_EntityTagQuery_EnsureBoundFires_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_EntityTagQuery_EnsureBoundFires;
    default _TimeoutSeconds = 8.0f;

    // The CK_ENSURE_IF_NOT in CkEntityTagQuery_Processor.cpp emits a message
    // containing "exceeded MaxAllowed" when GlobalCount > MaxAllowed. This
    // test deliberately exceeds that bound to verify the ensure fires;
    // register the substring so the automation framework doesn't auto-fail.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("exceeded MaxAllowed");
        return Out;
    }
}
