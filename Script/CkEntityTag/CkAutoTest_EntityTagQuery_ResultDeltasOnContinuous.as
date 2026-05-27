// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: RESULT DELTAS ON CONTINUOUS UPDATE
//============================================================================
//
// Verifies J1 — OnContinuousUpdate payload's _Added / _Removed arrays surface
// the per-pass deltas without requiring caller-side diffing.
//
// Continuous-update fires EVERY pump pass. To survive the post-mutation pass
// (where deltas are empty again), accumulate the delta counts across all fires
// rather than latching the latest value.
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
        _Owner = InHandle;
        _Query = utils_entity_tag_query::Add(_Owner);

        utils_entity_tag_query::BindTo_OnContinuousUpdate(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnContinuousUpdate(this, n"OnContinuous"));

        auto Req = utils_entity_tag_query::Make_Requirement_All(n"AutoTestEtq_Delta");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        WaitOneFrame(n"AfterReq");
    }

    UFUNCTION()
    private void AfterReq(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Reset accumulators AFTER initial fires settled.
        _TotalAddedSeen = 0;
        _TotalRemovedSeen = 0;

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Delta");
        WaitOneFrame(n"AfterFirstAdd");
    }

    UFUNCTION()
    private void AfterFirstAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_TotalAddedSeen >= 1,
            "First tag-add must surface as _Added>=1 in at least one continuous fire");
        Assert_True(_TotalRemovedSeen == 0,
            "No removals expected yet — _TotalRemovedSeen must be 0");

        const auto AddedAfterFirst = _TotalAddedSeen;

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_Delta");
        WaitOneFrame(n"AfterSecondAdd");
    }

    UFUNCTION()
    private void AfterSecondAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_TotalAddedSeen >= 2,
            "Second tag-add must increment _TotalAddedSeen — expected cumulative >= 2");

        utils_entity_lifetime::Request_DestroyEntity(_E1);
        WaitOneFrame(n"AfterDestroy");
    }

    UFUNCTION()
    private void AfterDestroy(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_TotalRemovedSeen >= 1,
            "Entity destruction must surface as _Removed>=1 in at least one continuous fire");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnContinuous(FCk_Handle_EntityTagQuery InQuery,
                              bool InIsSatisfied,
                              const TArray<FCk_EntityTagQuery_Result>& InResults)
    {
        if (InResults.Num() == 0) { return; }

        // Accumulate — continuous-update fires every pass; we want cumulative deltas
        // so the post-mutation pass (which has empty deltas) doesn't overwrite the meaningful one.
        _TotalAddedSeen   += InResults[0].Get_Added().Num();
        _TotalRemovedSeen += InResults[0].Get_Removed().Num();
    }
}
