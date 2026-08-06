// Language=angelscript

//============================================================================
// CK RENDER TARGET — AUTOMATION TEST: DRAW REQUESTS FIRE APPLIED SIGNAL
//============================================================================
//
// Draw calls are requests; the HandleRequests processor batches one frame's
// requests, applies them in a single canvas pass, and broadcasts
// OnInstructionsApplied. This test enqueues a Line + a Box in the same frame
// and asserts:
//   - OnInstructionsApplied fires exactly once for the pair
//   - The first batch carries seq 1 (the per-target seq starts at 1)
//   - NumCmds == 2 (both requests normalized into one batch)
//
// No pixel asserts — the batch counts as applied even on machines that
// cannot render (-nullrhi CI), which is exactly the contract the replicated
// instruction stream relies on.
//============================================================================

class UCk_AutoTest_RenderTarget_DrawRequests_FireAppliedSignal : UCk_AutoTest_Base
{
    private FCk_Handle_RenderTarget _RenderTarget;
    private int32 _SignalFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.DrawSignal");

        auto Params = FCk_RenderTarget_Spec(SyncName);
        Params.Set_Size(FIntPoint(64, 64));
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);
        Assert_True(ck::IsValid(_RenderTarget), "Add should return a valid RenderTarget handle");

        _RenderTarget.BindTo_OnInstructionsApplied(
            FCk_Delegate_RenderTarget_OnInstructionsApplied(this, n"OnInstructionsApplied"));

        // Both requests land in the same frame -> one batch. They sit in the requests fragment
        // until Setup completes (HandleRequests excludes NeedsSetup), then apply together.
        _RenderTarget.Request_DrawLine(
            FCk_Request_RenderTarget_DrawLine(FVector2D(0.0, 0.0), FVector2D(32.0, 32.0)));
        _RenderTarget.Request_DrawBox(
            FCk_Request_RenderTarget_DrawBox(FVector2D(8.0, 8.0), FVector2D(16.0, 16.0)));
    }

    UFUNCTION()
    private void OnInstructionsApplied(FCk_Handle_RenderTarget InHandle, int32 InBatchSeq, int32 InNumCmds)
    {
        if (IsFinished()) { return; }

        _SignalFireCount++;

        Assert_True(InHandle == _RenderTarget, "Signal should fire on the sync entity that was drawn to");
        Assert_Equals_Int(InBatchSeq, 1, "First applied batch should carry seq 1");
        Assert_Equals_Int(InNumCmds, 2, "Both same-frame requests should normalize into one batch");
        Assert_Equals_Int(_SignalFireCount, 1, "OnInstructionsApplied should fire once for one batch");

        FinishSuccess();
    }
}
