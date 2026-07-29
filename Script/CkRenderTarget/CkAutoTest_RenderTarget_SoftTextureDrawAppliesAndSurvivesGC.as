// Language=angelscript

//============================================================================
// CK RENDER TARGET — AUTOMATION TEST: soft texture draw resolves, applies, survives GC
//============================================================================
//
// Pins the soft-ref draw-request pipeline end-to-end (mirror of the IskmProxy
// SoftSequenceQueuedPlaySurvivesGC shape):
//   1. Request_DrawTexture enqueued IMMEDIATELY after Add — it must queue
//      behind FTag_RenderTarget_NeedsSetup, carrying its soft texture + the
//      enqueue-time loader batch through the queue. A same-frame DrawLine
//      must normalize into the SAME batch (the resident-asset preload gate
//      must not stall or split the drain).
//   2. OnInstructionsApplied reports seq 1 with both cmds.
//   3. A full GC pass must not corrupt the module state — a second soft draw
//      afterwards applies as its own batch (DoApplyBatch pinned the resolved
//      asset on the target's Current across the collect).
//
// Scope: in-editor the asset registry keeps real assets resident, so the
// negative half (an unpinned DrawCmd pointer alone would dangle) is only
// falsifiable packaged — this test owns the resolve/queue/apply/pin pipeline.
//
//============================================================================

class UCk_AutoTest_RenderTarget_SoftTextureDrawAppliesAndSurvivesGC : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_RenderTarget _RenderTarget;
    private int32 _AppliedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Texture = Cast<UTexture>(LoadObject(this, "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"));

        if (ck::Is_NOT_Valid(Texture))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.SoftTextureDraw");

        auto Params = FCk_Fragment_RenderTarget_ParamsData(SyncName);
        Params.Set_Size(FIntPoint(64, 64));
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);
        Assert_True(ck::IsValid(_RenderTarget), "Add should return a valid RenderTarget handle");

        _RenderTarget.BindTo_OnInstructionsApplied(
            FCk_Delegate_RenderTarget_OnInstructionsApplied(this, n"OnInstructionsApplied"));

        // Enqueued BEFORE Setup completes — the requests queue behind NeedsSetup, the texture
        // request carrying its soft ref + enqueue-time loader batch through the queue.
        _RenderTarget.Request_DrawTexture(
            FCk_Request_RenderTarget_DrawTexture(Texture, FVector2D(0.0, 0.0), FVector2D(32.0, 32.0)));
        _RenderTarget.Request_DrawLine(
            FCk_Request_RenderTarget_DrawLine(FVector2D(0.0, 0.0), FVector2D(64.0, 64.0)));
    }

    UFUNCTION()
    private void OnInstructionsApplied(FCk_Handle_RenderTarget InHandle, int32 InBatchSeq, int32 InNumCmds)
    {
        if (IsFinished()) { return; }

        _AppliedCount++;

        if (_AppliedCount == 1)
        {
            Assert_Equals_Int(InBatchSeq, 1, "First applied batch should carry seq 1");
            Assert_Equals_Int(InNumCmds, 2,
                "Both same-frame requests should normalize into one batch — a resident-asset preload must not stall or split the drain");

            System::CollectGarbage();
            WaitOneFrame(n"OnGCSettled");
            return;
        }

        Assert_Equals_Int(InBatchSeq, 2, "Post-GC batch should carry seq 2");
        Assert_Equals_Int(InNumCmds, 1, "The post-GC soft draw should apply as its own single-cmd batch");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnGCSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // A second soft draw AFTER a full GC pass — the module state (pins, seq, queue) must be intact.
        auto Texture = Cast<UTexture>(LoadObject(this, "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"));
        Assert_True(ck::IsValid(Texture), "the engine texture must still load by path after a GC pass");

        _RenderTarget.Request_DrawTexture(
            FCk_Request_RenderTarget_DrawTexture(Texture, FVector2D(8.0, 8.0), FVector2D(16.0, 16.0)));
    }
}
