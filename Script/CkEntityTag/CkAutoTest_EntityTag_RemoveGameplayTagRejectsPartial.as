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
//   2. NOT remove anything: one frame later, A.B.C is still present
//      (explicit), and A.B is still present (parent of A.B.C).
//
// This pins end-to-end no-op behavior on partial-match removes.
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

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Entity = InHandle;
        _LeafTag   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        _ParentTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B");

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _LeafTag);

        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Result = utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _ParentTag);
        Assert_True(Result == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove_UsingGameplayTag must Succeed at the boundary whenever the handle/tag are valid — partial-match enforcement is handled inside the deferred apply as a silent no-op");

        WaitOneFrame(n"AfterPartialRemove");
    }

    UFUNCTION()
    private void AfterPartialRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Leaf must still be intact — the partial-match remove no-ops.
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B.C"),
            "Leaf A.B.C must still be present after the no-op parent remove");
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B"),
            "Parent FName A.B must still be present after the no-op parent remove (held by A.B.C)");

        FinishSuccess();
    }
}
