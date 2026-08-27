// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY - AUTOMATION TEST: ON CONTINUOUS UPDATE FIRES ONLY ON CHANGE
//============================================================================
//
// NOTE ON NAME: the class/file retains its historical "FiresEveryPass" name so
// renaming it does not churn the generated autotest wrapper + the placed actor in
// AutoTests_CkTests_Level. Its CONTRACT changed: OnContinuousUpdate is now
// change-gated - it broadcasts ONLY on a pump pass whose result set actually
// changed (an entity entered or left a requirement), and stays SILENT on
// no-change passes. (Broadcasting every pass cost a per-frame payload alloc +
// broadcast + delegate call per bound query even when nothing changed; every
// consumer reacts to the _Added / _Removed deltas, so a no-change pass has nothing
// to deliver.)
//
// Strategy: bind OnContinuousUpdate to a query whose requirement nothing satisfies
// yet, prove it stays silent across idle passes, then add a matching entity and
// prove exactly that change fires it - and that it goes silent again afterwards.
//
// Most of this test asserts SILENCE, so most phases settle for a fixed number
// of frames - a non-event has nothing to wait on. The one phase that expects a
// fire waits on the counter rising above the idle baseline. The requirement
// registering IS waited on, because a query that never started would be silent
// for uninteresting reasons and the whole test would pass vacuously.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ContinuousUpdateFiresEveryPass : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private int32                     _FireCount         = 0;
    private int32                     _FireCountIdle     = 0;
    private int32                     _FireCountAfterAdd = 0;

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

        auto Req = utils_entity_tag_query::Make_Requirement_Single(n"AutoTestEtq_Cont");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        Add_Step_WaitUntil( "the requirement registers, so the query is live", n"Check_RequirementRegistered");
        Add_Step(           "assert silence on an empty result set",           n"Step_AssertSilentAndLatch");
        Add_Step_WaitFrames("let a further idle pass run",                     3);
        Add_Step(           "assert the idle pass stayed silent, then tag",    n"Step_AssertIdleSilentAndTag");
        Add_Step_WaitUntil( "the result-set change fires",                     n"Check_FiredOnChange");
        Add_Step(           "latch the post-change count",                     n"Step_LatchAfterAdd");
        Add_Step_WaitFrames("let a post-change idle pass run",                 3);
        Add_Step(           "assert it went silent again",                     n"Step_AssertSilentAgain");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertSilentAndLatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // No matching entity exists, so the evaluate produced no delta and must not fire.
        Assert_Equals_Int(_FireCount, 0,
            "OnContinuousUpdate must NOT fire while the result set is empty/unchanged");

        _FireCountIdle = _FireCount;
    }

    UFUNCTION()
    private void Step_AssertIdleSilentAndTag(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, _FireCountIdle,
            "An idle pass with no result-set change must NOT fire OnContinuousUpdate");

        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Cont");
    }

    UFUNCTION()
    private void Step_LatchAfterAdd(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FireCountAfterAdd = _FireCount;
    }

    UFUNCTION()
    private void Step_AssertSilentAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FireCount, _FireCountAfterAdd,
            "After the change settles, an idle pass must NOT re-fire OnContinuousUpdate");
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
    private void Check_FiredOnChange(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCount > _FireCountIdle);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnContinuous(
        FCk_Handle_EntityTagQuery InQuery,
        bool InIsSatisfied,
        const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
