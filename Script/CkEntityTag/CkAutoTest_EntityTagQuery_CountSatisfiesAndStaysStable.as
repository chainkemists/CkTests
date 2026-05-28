// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: COUNT(2) SATISFIES AND STAYS STABLE
//============================================================================
//
// Spawn a query "I need 2 entities tagged A". Tag 1 entity → no fire. Tag a 2nd
// → fires once. Tag a 3rd → no extra fire (Count is capped, no All-mode re-fire).
//============================================================================

class UCk_AutoTest_EntityTagQuery_CountSatisfiesAndStaysStable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private FCk_Handle                _E2;
    private FCk_Handle                _E3;
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

        auto Req = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_A", 2);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        WaitOneFrame(n"AfterAddRequirement");
    }

    UFUNCTION()
    private void AfterAddRequirement(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "Empty result set must not fire");

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_A");
        WaitOneFrame(n"AfterFirstTag");
    }

    UFUNCTION()
    private void AfterFirstTag(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "Only 1 of 2 — query must not have fired yet");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_A");
        WaitOneFrame(n"AfterSecondTag");
    }

    UFUNCTION()
    private void AfterSecondTag(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "Threshold (2) crossed — must fire exactly once");

        _E3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E3, n"AutoTestEtq_A");
        WaitOneFrame(n"AfterThirdTag");
    }

    UFUNCTION()
    private void AfterThirdTag(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "Count mode caps at 2; the 3rd tagged entity must not trigger a re-fire");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
