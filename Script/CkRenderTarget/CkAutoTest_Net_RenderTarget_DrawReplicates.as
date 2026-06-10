// Language=angelscript

//============================================================================
// CK RENDER TARGET — NET AUTOMATION TEST: SERVER DRAW REPLICATES
//============================================================================
//
// Multi-world test on the RenderTarget net subject (Replicates / InstructionsOnly,
// sync name "RenderTarget.AutoTest.Net" — composed symmetrically by
// UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE).
//
//   Server world: waits for its sync child, draws a 2-cmd batch, finishes when
//                 its local applied seq reaches 1.
//   Client world: waits for the replayed batch — OnInstructionsApplied fires
//                 with the wire seq and the watermark advances to 1.
//
// Both worlds poll via a tick timer because subject composition order vs the
// test entity's DoBeginPlay is not deterministic across worlds.
//============================================================================

class UCk_AutoTest_Net_RenderTarget_DrawReplicates : UCk_AutoTest_NetBase
{
    default _NetSubjectClass = ACk_AutoTest_NetSubject_RenderTarget_UE;
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_RenderTarget _RenderTarget;
    private bool _HasDrawn = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (ck::Is_NOT_Valid(_RenderTarget))
        {
            auto Subject = Get_SubjectEntity();
            if (ck::Is_NOT_Valid(Subject)) { return; }

            auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.Net");
            _RenderTarget = utils_render_target::TryGet_RenderTarget(Subject, SyncName);
            if (ck::Is_NOT_Valid(_RenderTarget)) { return; }
        }

        auto Subject = Get_SubjectEntity();

        if (utils_net::Get_HasAuthority(Subject))
        {
            if (_HasDrawn == false)
            {
                _HasDrawn = true;
                _RenderTarget.Request_DrawLine(
                    FCk_Request_RenderTarget_DrawLine(FVector2D(0.0, 0.0), FVector2D(32.0, 32.0)));
                _RenderTarget.Request_DrawBox(
                    FCk_Request_RenderTarget_DrawBox(FVector2D(8.0, 8.0), FVector2D(16.0, 16.0)));
                return;
            }

            if (_RenderTarget.Get_LatestAppliedBatchSeq() >= 1)
            {
                FinishSuccess();
            }
            return;
        }

        // Client world: success once the replayed batch lands.
        if (_RenderTarget.Get_LatestAppliedBatchSeq() >= 1)
        {
            FinishSuccess();
        }
    }
}
