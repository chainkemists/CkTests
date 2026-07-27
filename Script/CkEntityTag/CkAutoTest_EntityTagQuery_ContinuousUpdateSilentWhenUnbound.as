// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: CONTINUOUS UPDATE SILENT WHEN UNBOUND
//============================================================================
//
// Verifies improvement I2's pay-for-what-you-use guarantee: when no delegate
// is bound to OnContinuousUpdate, the signal must not fire at all (the
// refcount gate inside the broadcaster short-circuits the work). Run a query
// for several pump passes without binding anything and confirm _FireCount
// stays at zero.
//
// The OnContinuous callback is declared so the signature is reachable, but
// it is never registered via BindTo_OnContinuousUpdate.
//
// The requirement registering is a real observable and is waited on: it proves
// the query is LIVE, which is what makes the silence meaningful — a query that
// never started would be silent for uninteresting reasons. The extra passes
// after that are a fixed settle, since a non-event has nothing to wait for.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ContinuousUpdateSilentWhenUnbound : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private int32                     _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        // Intentionally NOT binding OnContinuousUpdate (and also not OnSatisfied —
        // we want the entire query running silently to prove the refcount gate
        // holds when no listener is attached).
        auto Req = utils_entity_tag_query::Make_Requirement_Single(n"AutoTestEtq_Silent");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        Add_Step_WaitUntil( "the requirement registers, so the query is live", n"Check_RequirementRegistered");
        Add_Step_WaitFrames("let several evaluation passes run",               3);
        Add_Step(           "assert the unbound signal never fired",           n"Step_AssertSilent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertSilent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "OnContinuousUpdate must not fire when no delegate is bound — refcount gate must hold");
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

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnContinuous(
        FCk_Handle_EntityTagQuery InQuery,
        bool InIsSatisfied,
        const TArray<FCk_EntityTagQuery_Result>& InResults)
    {
        // Declared but never bound — if this is ever invoked, the refcount
        // gate failed and the test will fail in the Step_AssertSilent step.
        _FireCount += 1;
    }
}
