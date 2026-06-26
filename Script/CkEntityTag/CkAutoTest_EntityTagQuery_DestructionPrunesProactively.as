// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: DESTRUCTION PRUNES PROACTIVELY
//============================================================================
//
// Verifies improvement I1 — when a tagged entity is destroyed while it is in
// a satisfied query's result set, the dedicated destructor processor proactively
// prunes the result array (without relying on the lazy Is_NOT_Valid filter
// inside Evaluate, which was removed in I1).
//
// Count(2) of tag A:
//   1. Create + tag 2 entities → fires once, IsSatisfied=true, result Handles=2.
//   2. Destroy one of the matches → after one frame the result array's Handles
//      array drops to 1 and IsSatisfied flips back to false.
//
// The "Handles count went from 2 to 1" assertion is the proof that the
// destructor processor scrubbed the cached results — if cleanup had been
// purely lazy, reading the array before the next Evaluate pass would still
// show 2 entries (one stale invalid).
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

        WaitOneFrame(n"AfterAddRequirement");
    }

    UFUNCTION()
    private void AfterAddRequirement(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_DPP");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_DPP");

        WaitOneFrame(n"AfterTagBoth");
    }

    UFUNCTION()
    private void AfterTagBoth(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "Count(2) crossed — query must fire exactly once");
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query),
            "After 2 matches, Get_IsSatisfied must report true");

        auto Results = utils_entity_tag_query::Get_CurrentResults(_Query);
        Assert_True(Results.Num() > 0,
            "Satisfied query must expose at least one requirement result");
        Assert_Equals_Int(Results[0].Get_Handles().Num(), 2,
            "Result entry must hold both tagged handles before destruction");

        // Destroy one of the matches. The new destructor processor should
        // proactively prune the cached results — not just rely on Evaluate's
        // lazy filter.
        utils_entity_lifetime::Request_DestroyEntity(_E1);

        WaitOneFrame(n"AfterDestroyOne");
    }

    UFUNCTION()
    private void AfterDestroyOne(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Results = utils_entity_tag_query::Get_CurrentResults(_Query);
        Assert_True(Results.Num() > 0,
            "Result entry for the requirement must still exist after destroying one match");

        const auto HandleCount = Results[0].Get_Handles().Num();

        // If the destructor processor + Evaluate scheduling left us mid-flight,
        // give it one more frame to settle.
        if (HandleCount == 1)
        {
            DoCheckFinalState();
            return;
        }

        WaitOneFrame(n"AfterDestroySecondFrame");
    }

    UFUNCTION()
    private void AfterDestroySecondFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        DoCheckFinalState();
    }

    private void DoCheckFinalState()
    {
        auto Results = utils_entity_tag_query::Get_CurrentResults(_Query);
        Assert_True(Results.Num() > 0,
            "Result entry for the requirement must still exist after destruction");
        Assert_Equals_Int(Results[0].Get_Handles().Num(), 1,
            "Destruction cleanup must proactively prune the destroyed handle from the cached results");
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query) == false,
            "After dropping below the cap, IsSatisfied must report false");
        Assert_Equals_Int(_FireCount, 1,
            "A silent drop must not trigger an OnSatisfied re-fire");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
