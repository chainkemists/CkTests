// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: MIXED COUNT(2) A + ALL B
//============================================================================
//
// Two requirements coexist on one query:
//   - Count(2) of tag A — capped at 2 matches, fires once on crossing
//   - All       of tag B — fires once per new match while satisfied
//
// Verifies:
//   1. Before the last-needed match is added, no fires.
//   2. The fire happens exactly when the last requirement crosses its
//      threshold (here: 1st B, after both A's are present).
//   3. While satisfied, each new B re-fires (All-mode contribution).
//   4. Tagging a 3rd A does NOT re-fire (Count-mode caps at 2).
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

        WaitOneFrame(n"AfterAddRequirements");
    }

    UFUNCTION()
    private void AfterAddRequirements(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "Empty result — must not have fired before any matches exist");

        _A1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A1, n"AutoTestEtq_MixA");
        WaitOneFrame(n"AfterFirstA");
    }

    UFUNCTION()
    private void AfterFirstA(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "Only 1 of 2 A's and 0 B's — query is not satisfied yet");

        _A2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A2, n"AutoTestEtq_MixA");
        WaitOneFrame(n"AfterSecondA");
    }

    UFUNCTION()
    private void AfterSecondA(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "Both A's present but still no B — All(B) requirement keeps query unsatisfied");

        _B1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_B1, n"AutoTestEtq_MixB");
        WaitOneFrame(n"AfterFirstB");
    }

    UFUNCTION()
    private void AfterFirstB(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "Last requirement crosses threshold (1st B with both A's present) — must fire exactly once");

        _B2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_B2, n"AutoTestEtq_MixB");
        WaitOneFrame(n"AfterSecondB");
    }

    UFUNCTION()
    private void AfterSecondB(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 2,
            "All-mode B requirement re-fires on each new B match while satisfied");

        _A3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A3, n"AutoTestEtq_MixA");
        WaitOneFrame(n"AfterThirdA");
    }

    UFUNCTION()
    private void AfterThirdA(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 2,
            "Count(2) caps at 2; a 3rd A must NOT cause a re-fire");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>& InResults)
    {
        _FireCount += 1;
    }
}
