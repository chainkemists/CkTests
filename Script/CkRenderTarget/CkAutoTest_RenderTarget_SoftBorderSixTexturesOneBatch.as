// Language=angelscript

//============================================================================
// CK RENDER TARGET - AUTOMATION TEST: soft border draws six textures as one batch
//============================================================================
//
// DrawBorder is the widest soft-ref conversion in the module: six texture
// members riding ONE enqueue-time loader batch (with duplicate paths - the
// streamable manager must tolerate them), each resolved batch-first into the
// DrawCmd's _Asset/_ExtraAssets. This test enqueues a border whose six slots
// reuse two distinct engine textures and asserts the request normalizes into
// a single applied cmd.
//
// No pixel asserts - the batch counts as applied even on machines that
// cannot render (-nullrhi CI), same contract as the DrawSignal test.
//============================================================================

class UCk_AutoTest_RenderTarget_SoftBorderSixTexturesOneBatch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_RenderTarget _RenderTarget;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto White = Cast<UTexture>(LoadObject(this, "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"));
        auto Default = Cast<UTexture>(LoadObject(this, "/Engine/EngineResources/DefaultTexture.DefaultTexture"));

        if (ck::Is_NOT_Valid(White) || ck::Is_NOT_Valid(Default))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.SoftBorderDraw");

        auto Params = FCk_Fragment_RenderTarget_ParamsData(SyncName);
        Params.Set_Size(FIntPoint(64, 64));
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);
        Assert_True(ck::IsValid(_RenderTarget), "Add should return a valid RenderTarget handle");

        _RenderTarget.BindTo_OnInstructionsApplied(
            FCk_Delegate_RenderTarget_OnInstructionsApplied(this, n"OnInstructionsApplied"));

        _RenderTarget.Request_DrawBorder(
            FCk_Request_RenderTarget_DrawBorder(
                White, White, Default, Default, Default, Default,
                FVector2D(0.0, 0.0), FVector2D(64.0, 64.0)));
    }

    UFUNCTION()
    private void OnInstructionsApplied(FCk_Handle_RenderTarget InHandle, int32 InBatchSeq, int32 InNumCmds)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(InBatchSeq, 1, "First applied batch should carry seq 1");
        Assert_Equals_Int(InNumCmds, 1, "The six-texture border request should normalize into a single cmd");

        FinishSuccess();
    }
}
