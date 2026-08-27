// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: DESTRUCTION PRUNES PROACTIVELY
//============================================================================
//
// Verifies improvement I1 - when a tagged entity is destroyed while it is in
// a satisfied query's result set, the dedicated destructor processor proactively
// prunes the result array (without relying on the lazy Is_NOT_Valid filter
// inside Evaluate, which was removed in I1).
//
// Count(2) of tag A:
//   1. Create + tag 2 entities -> fires once, IsSatisfied=true, result Handles=2.
//   2. Destroy one of the matches -> the result array's Handles array drops to 1
//      and IsSatisfied flips back to false.
//
// The "Handles count went from 2 to 1" assertion is the proof that the
// destructor processor scrubbed the cached results - if cleanup had been
// purely lazy, reading the array before the next Evaluate pass would still
// show 2 entries (one stale invalid).
//
// This replaces a HAND-ROLLED RETRY: the previous version read the handle
// count one frame after the destroy, branched on whether it had reached 1, and
// gave the pump exactly one more frame through a second callback before
// judging. That is the ad-hoc timing workaround the sequencer exists to
// remove - the prune is now a single wait on the count reaching 1, bounded by
// the test timeout instead of by a hardcoded second chance.
//============================================================================

class UCk_AutoTest_EntityTagQuery_DestructionPrunesProactively : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private FCk_Handle                _E2;
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

        auto Req = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_DPP", 2);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        Add_Step_WaitUntil("the requirement registers on a live query",  n"Check_RequirementRegistered");
        Add_Step(          "tag two entities",                           n"Step_TagBoth");
        Add_Step_WaitUntil("crossing Count(2) fires OnSatisfied",        n"Check_FiredOnce");
        Add_Step(          "assert the cached results, destroy one match", n"Step_AssertCachedAndDestroy");
        Add_Step_WaitUntil("the destroyed handle is pruned from results", n"Check_Pruned");
        Add_Step(          "assert the post-prune state",                n"Step_AssertPrunedState");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_TagBoth(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_DPP");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_DPP");
    }

    UFUNCTION()
    private void Step_AssertCachedAndDestroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query),
            "After 2 matches, Get_IsSatisfied must report true");

        auto Results = utils_entity_tag_query::Get_CurrentResults(_Query);
        Assert_True(Results.Num() > 0,
            "Satisfied query must expose at least one requirement result");
        Assert_Equals_Int(Results[0].Get_Handles().Num(), 2,
            "Result entry must hold both tagged handles before destruction");

        // Destroy one of the matches. The destructor processor should
        // proactively prune the cached results - not just rely on Evaluate's
        // lazy filter.
        utils_entity_lifetime::Request_DestroyEntity(_E1);
    }

    UFUNCTION()
    private void Step_AssertPrunedState(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query) == false,
            "After dropping below the cap, IsSatisfied must report false");
        Assert_Equals_Int(_FireCount, 1,
            "A silent drop must not trigger an OnSatisfied re-fire");
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
    private void Check_Pruned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Results = utils_entity_tag_query::Get_CurrentResults(_Query);

        auto Res = OutResult;
        Res.Set(Results.Num() > 0 && Results[0].Get_Handles().Num() == 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
