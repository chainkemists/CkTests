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

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        auto Req = utils_entity_tag_query::Make_Requirement_Of_WithEnsure(
            n"AutoTestEtq_Ensure", 2, 4);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        // Tag 5 entities — strictly more than the MaxAllowed of 4.
        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Ensure");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_Ensure");

        _E3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E3, n"AutoTestEtq_Ensure");

        _E4 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E4, n"AutoTestEtq_Ensure");

        _E5 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E5, n"AutoTestEtq_Ensure");

        WaitOneFrame(n"AfterTagAll");
    }

    UFUNCTION()
    private void AfterTagAll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Diagnostic-only ensure — query evaluation continues, so the test
        // reaches this callback normally. The wrapper actor declares the
        // expected log message so the framework doesn't escalate the ensure
        // to a test failure.
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query),
            "Query with Count(2) must still report satisfied (5 >= 2); the ensure is purely diagnostic");

        FinishSuccess();
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
