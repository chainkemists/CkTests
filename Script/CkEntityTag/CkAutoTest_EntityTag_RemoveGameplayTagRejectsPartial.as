// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: REMOVE GAMEPLAY TAG ON PARTIAL IS NO-OP
//============================================================================
//
// Adding A.B.C registers A.B.C explicitly and A.B / A as parent FNames.
// Calling Request_TryRemove_UsingGameplayTag(A.B) — where A.B is only a
// parent FName, NOT an explicitly-added gameplay tag — must:
//
//   1. Return Succeeded at the boundary (post-A4 contract: handle/tag valid
//      → Succeeded; the deferred apply silently no-ops on a missing
//      _GameplayTagCounts entry, which is what "partial match" means).
//   2. NOT remove anything: A.B.C is still present (explicit), and A.B is
//      still present (parent of A.B.C).
//
// This pins end-to-end no-op behavior on partial-match removes.
//
// The verification phase asserts that NOTHING changed, which no condition can
// observe directly. It waits on a SENTINEL instead: an unrelated tag enqueued
// immediately after the partial remove. Every EntityTag mutation appends to
// the same per-entity FFragment_EntityTag_Requests::_Requests array
// (CkEntityTag_Utils.cpp:145,203,347,418) and the pump drains it in order
// (CkEntityTag_Processor.cpp:30), so the sentinel becoming visible proves the
// partial remove was already applied — and left the tags alone.
//
// NOTE: File name + class name retained for level-asset compatibility
//       (AutoTests_CkTests_Level.umap references the old C++ class path).
//       The contract is now "no-op on partial match" NOT "rejects partial".
//       See commit 68e828b56 (CkEntityTag fully deferred mutations) and the
//       binds-and-queries plan.
//============================================================================

class UCk_AutoTest_EntityTag_RemoveGameplayTagRejectsPartial : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;
    private FGameplayTag _LeafTag;
    private FGameplayTag _ParentTag;
    private FName _SentinelTag = n"AutoTestEt_PartialRemove_Sentinel";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        _LeafTag   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        _ParentTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B");

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _LeafTag);

        Add_Step_WaitUntil("the leaf tag and its parent chain land",       n"Check_LeafPresent");
        Add_Step(          "remove the parent-only tag, queue a sentinel", n"Step_RemoveParentAndQueueSentinel");
        Add_Step_WaitUntil("the sentinel lands, so the remove has drained", n"Check_SentinelPresent");
        Add_Step(          "assert the partial remove changed nothing",    n"Step_AssertUnchanged");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RemoveParentAndQueueSentinel(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Result = utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _ParentTag);
        Assert_True(Result == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove_UsingGameplayTag must Succeed at the boundary whenever the handle/tag are valid — partial-match enforcement is handled inside the deferred apply as a silent no-op");

        utils_entity_tag::Add(_Entity, _SentinelTag);
    }

    UFUNCTION()
    private void Step_AssertUnchanged(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B.C"),
            "Leaf A.B.C must still be present after the no-op parent remove");
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B"),
            "Parent FName A.B must still be present after the no-op parent remove (held by A.B.C)");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_LeafPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B.C"));
    }

    UFUNCTION()
    private void Check_SentinelPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, _SentinelTag));
    }
}
