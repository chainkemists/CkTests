// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: RESULT DELTAS ON CONTINUOUS UPDATE
//============================================================================
//
// Verifies J1 - OnContinuousUpdate payload's _Added / _Removed arrays surface
// the per-pass deltas without requiring caller-side diffing.
//
// Continuous-update fires on each pass whose result set changed (add or remove).
// Accumulate the delta counts across all fires rather than latching the latest
// value, so the assertions hold regardless of how the deltas split across fires.
//
// Every phase waits on the cumulative delta counter reaching the value that
// phase's mutation must produce, which is exactly the settling event. The
// accumulate-don't-latch design means those waits are monotonic and cannot be
// missed by a fire landing a pass earlier or later than expected.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ResultDeltasOnContinuous : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private FCk_Handle                _E2;
    private int32                     _TotalAddedSeen   = 0;
    private int32                     _TotalRemovedSeen = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;
        _Query = utils_entity_tag_query::Add(_Owner);

        utils_entity_tag_query::BindTo_OnContinuousUpdate(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnContinuousUpdate(this, n"OnContinuous"));

        auto Req = utils_entity_tag_query::Make_Requirement_All(n"AutoTestEtq_Delta");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        Add_Step_WaitUntil("the requirement registers on a live query", n"Check_RequirementRegistered");
        Add_Step(          "reset the accumulators, then tag one entity", n"Step_ResetAndTagFirst");
        Add_Step_WaitUntil("the add surfaces as an _Added delta",       n"Check_SawFirstAdd");
        Add_Step(          "assert no removals yet, then tag a second", n"Step_AssertNoRemovalsAndTagSecond");
        Add_Step_WaitUntil("the second add surfaces as another delta",  n"Check_SawSecondAdd");
        Add_Step(          "destroy the first entity",                  n"Step_DestroyFirst");
        Add_Step_WaitUntil("the destroy surfaces as a _Removed delta",  n"Check_SawRemoval");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ResetAndTagFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Reset AFTER the requirement-registration passes, so any fire from
        // building the query does not count toward the deltas under test.
        _TotalAddedSeen = 0;
        _TotalRemovedSeen = 0;

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Delta");
    }

    UFUNCTION()
    private void Step_AssertNoRemovalsAndTagSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_TotalRemovedSeen == 0,
            "No removals expected yet - _TotalRemovedSeen must be 0");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_Delta");
    }

    UFUNCTION()
    private void Step_DestroyFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_E1);
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
    private void Check_SawFirstAdd(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_TotalAddedSeen >= 1);
    }

    UFUNCTION()
    private void Check_SawSecondAdd(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_TotalAddedSeen >= 2);
    }

    UFUNCTION()
    private void Check_SawRemoval(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_TotalRemovedSeen >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnContinuous(FCk_Handle_EntityTagQuery InQuery,
                              bool InIsSatisfied,
                              const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        if (InResults.Num() == 0) { return; }

        // Accumulate - a single mutation may surface its delta across one or more change
        // fires; cumulative counts keep the assertions robust to that split.
        _TotalAddedSeen   += InResults[0].Get_Added().Num();
        _TotalRemovedSeen += InResults[0].Get_Removed().Num();
    }
}
