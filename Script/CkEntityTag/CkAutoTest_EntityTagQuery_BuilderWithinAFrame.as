// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: BUILDER WITHIN A FRAME
//============================================================================
//
// Pre-stage 2 entities tagged A and 1 tagged B. After tags settle, build the
// query in a single tick: Add → AddRequirement(Of A, 2) → AddRequirement(All B)
// → BindTo. The first evaluation pass after that frame must fire OnSatisfied
// exactly once (atomic-build evaluation, no duplicate fires across the
// in-frame request flushes).
//============================================================================

class UCk_AutoTest_EntityTagQuery_BuilderWithinAFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _A1;
    private FCk_Handle                _A2;
    private FCk_Handle                _B1;
    private int32                     _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = InHandle;

        // Pre-stage matching entities so the query is born already satisfiable.
        _A1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A1, n"AutoTestEtq_BuildA");

        _A2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A2, n"AutoTestEtq_BuildA");

        _B1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_B1, n"AutoTestEtq_BuildB");

        WaitOneFrame(n"AfterTagsApply");
    }

    UFUNCTION()
    private void AfterTagsApply(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Atomically build the query in this single tick — no WaitOneFrame
        // between Add/AddRequirement/BindTo. Verifies the processor's batch
        // evaluation doesn't double-fire across the in-frame deferred steps.
        _Query = utils_entity_tag_query::Add(_Owner);

        auto ReqA = utils_entity_tag_query::Make_Requirement_Of(n"AutoTestEtq_BuildA", 2);
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(ReqA));

        auto ReqB = utils_entity_tag_query::Make_Requirement_All(n"AutoTestEtq_BuildB");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(ReqB));

        utils_entity_tag_query::BindTo_OnSatisfied(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnSatisfied(this, n"OnSatisfied"));

        WaitOneFrame(n"AfterBuild");
    }

    UFUNCTION()
    private void AfterBuild(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "Atomic in-frame build with pre-staged matches must fire exactly once on the first evaluation pass");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
