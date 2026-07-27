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
//
// The atomicity the test exists to check is preserved: an Add_Step action runs
// to completion inside ONE tick, so the whole build still happens in a single
// frame exactly as before.
//
// This conversion also makes the test STRICTER than the version it replaces.
// The old one asserted "exactly one fire" a single frame after the build, so a
// duplicate arriving on any later pass went unseen. It now waits for the first
// fire, then deliberately settles further frames before asserting == 1, giving
// a late double-fire room to show up and be caught.
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
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;

        // Pre-stage matching entities so the query is born already satisfiable.
        _A1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A1, n"AutoTestEtq_BuildA");

        _A2 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_A2, n"AutoTestEtq_BuildA");

        _B1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_B1, n"AutoTestEtq_BuildB");

        Add_Step_WaitUntil( "all pre-staged tags land",                  n"Check_TagsApplied");
        Add_Step(           "build the whole query inside one tick",     n"Step_BuildAtomically");
        Add_Step_WaitUntil( "the first evaluation pass fires",           n"Check_Fired");
        Add_Step_WaitFrames("give a late duplicate room to appear",      3);
        Add_Step(           "assert it fired exactly once",              n"Step_AssertExactlyOnce");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_BuildAtomically(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // No wait between Add/AddRequirement/BindTo — verifies the processor's
        // batch evaluation doesn't double-fire across the in-frame deferred steps.
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
    }

    UFUNCTION()
    private void Step_AssertExactlyOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, 1,
            "Atomic in-frame build with pre-staged matches must fire exactly once on the first evaluation pass");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_TagsApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_A1, n"AutoTestEtq_BuildA")
             && utils_entity_tag::Has(_A2, n"AutoTestEtq_BuildA")
             && utils_entity_tag::Has(_B1, n"AutoTestEtq_BuildB"));
    }

    UFUNCTION()
    private void Check_Fired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
