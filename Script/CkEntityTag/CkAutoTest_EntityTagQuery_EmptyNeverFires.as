// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: EMPTY QUERY NEVER FIRES
//============================================================================
//
// Add a query, bind OnSatisfied, but never add any requirements. After
// several settle frames, OnSatisfied must NOT have fired. An empty
// requirement list is not vacuously satisfied - the query stays idle.
//
// This is a pure NON-event test: nothing is ever enqueued, so there is no
// observable to wait on and no witness to reach for. The three chained
// single-frame callbacks it used to run collapse into one declared settle of
// the same length, which says what it is doing instead of spelling it out
// across three hops.
//============================================================================

class UCk_AutoTest_EntityTagQuery_EmptyNeverFires : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
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

        // No requirements added - query sits idle.
        Add_Step_WaitFrames("let several evaluation passes run",       3);
        Add_Step(           "assert the empty query stayed silent",    n"Step_AssertSilent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertSilent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 0,
            "Query with no requirements must never fire OnSatisfied");
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query) == false,
            "Empty query must report Get_IsSatisfied == false (not vacuously satisfied)");
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
