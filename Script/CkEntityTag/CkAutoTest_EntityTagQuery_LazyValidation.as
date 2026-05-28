// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: LAZY VALIDATION (DROP-AND-RECOVER)
//============================================================================
//
// Count(2) of tag A. Once satisfied (2 entities tagged), destroy one entity.
// The next evaluation pass should lazy-prune the destroyed handle so the
// query reports IsSatisfied == false. Tagging a 3rd entity re-satisfies the
// query and the OnSatisfied signal fires again.
//
// Verifies:
//   1. Two matches → fires once and Get_IsSatisfied returns true.
//   2. Destroying one match → next pump prunes; Get_IsSatisfied → false
//      WITHOUT a re-fire (drop is silent on the signal).
//   3. Adding a 3rd match → re-satisfies → fires again (drop-and-recover).
//============================================================================

class UCk_AutoTest_EntityTagQuery_LazyValidation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

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

        auto Req = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_Lazy", 2);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        WaitOneFrame(n"AfterAddRequirement");
    }

    UFUNCTION()
    private void AfterAddRequirement(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "No matches yet — query must not have fired");

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Lazy");

        _E2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E2, n"AutoTestEtq_Lazy");

        WaitOneFrame(n"AfterTagBoth");
    }

    UFUNCTION()
    private void AfterTagBoth(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "Count(2) crossed — must fire exactly once");
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query),
            "After 2 matches, Get_IsSatisfied must report true");

        // Drop one tagged entity. The query's lazy-prune on the next pass
        // should observe the invalidation and flip IsSatisfied back to false.
        utils_entity_lifetime::Request_DestroyEntity(_E1);

        WaitOneFrame(n"AfterDestroyOne");
    }

    UFUNCTION()
    private void AfterDestroyOne(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query) == false,
            "After destroying one of two matches, lazy-prune must drop IsSatisfied back to false");
        Assert_Equals_Int(_FireCount, 1,
            "Drop on its own must NOT trigger an OnSatisfied re-fire (signal fires on the rising edge only)");

        // Recovery — tag a 3rd entity so the query crosses the threshold again.
        _E3 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E3, n"AutoTestEtq_Lazy");

        WaitOneFrame(n"AfterRecover");
    }

    UFUNCTION()
    private void AfterRecover(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 2,
            "Drop-and-recover: re-satisfaction must fire OnSatisfied a second time");
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query),
            "Get_IsSatisfied must report true after recovery");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
