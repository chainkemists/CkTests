// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: RESULT DELTAS ON CONTINUOUS UPDATE
//============================================================================
//
// Verifies J1 — OnContinuousUpdate's payload exposes per-result _Added and
// _Removed arrays so callers don't have to diff result sets themselves.
//
// Strategy: bind a continuous-update delegate, add a single-tag requirement,
// then progressively (a) tag one entity, (b) tag a second, (c) destroy the
// first, observing the per-step delta arrays.
//
// The trackers are reset to -1 after the initial WaitOneFrame because the
// continuous signal fires every pump pass and we need to make sure the
// asserted values come from the post-mutation fire, not a stale pre-mutation
// one.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ResultDeltasOnContinuous : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private FCk_Handle                _E2;
    private int32                     _LastAddedCount   = 0;
    private int32                     _LastRemovedCount = 0;

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

        WaitOneFrame(n"AfterAddRequirement");
    }

    UFUNCTION()
    private void AfterAddRequirement(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Reset trackers — the continuous fire may have already populated them
        // during the requirement-add settle. We care only about deltas caused
        // by the subsequent entity mutations.
        _LastAddedCount   = -1;
        _LastRemovedCount = -1;

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Delta");
        WaitOneFrame(n"AfterFirstAdd");
    }

    UFUNCTION()
    private void AfterFirstAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_LastAddedCount, 1,
            "First tag-add must surface as _Added.Num()==1 in the next continuous fire");
        Assert_Equals_Int(_LastRemovedCount, 0,
            "No removals expected after a single add");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_Delta");
        WaitOneFrame(n"AfterSecondAdd");
    }

    UFUNCTION()
    private void AfterSecondAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_LastAddedCount, 1,
            "Second tag-add must surface as _Added.Num()==1 — delta is since last fire");

        utils_entity_lifetime::Request_DestroyEntity(_E1);
        WaitOneFrame(n"AfterDestroy");
    }

    UFUNCTION()
    private void AfterDestroy(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_LastRemovedCount, 1,
            "Entity destruction must surface as _Removed.Num()==1 in the next continuous fire");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnContinuous(
        FCk_Handle_EntityTagQuery InQuery,
        bool InIsSatisfied,
        const TArray<FCk_EntityTagQuery_Result>& InResults)
    {
        if (InResults.Num() == 0) { return; }

        _LastAddedCount   = InResults[0].Get_Added().Num();
        _LastRemovedCount = InResults[0].Get_Removed().Num();
    }
}
