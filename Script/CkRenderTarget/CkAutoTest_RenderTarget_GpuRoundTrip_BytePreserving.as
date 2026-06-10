// Language=angelscript

//============================================================================
// CK RENDER TARGET — AUTOMATION TEST: GPU ROUND TRIP IS BYTE-PRESERVING
//============================================================================
//
// The Debug_InjectCapturedPixels seam ends at CPU staging, so headless tests
// cannot see GPU-side corruption in the capture->redraw loop (e.g. an
// sRGB/linear mismatch on the transient upload texture darkens the board by
// pow(2.2) every reconcile while every staging hash still matches). This test
// covers the real-RHI leg:
//
//   1. Draw known mid-tone content into a managed target via the request API
//      (mid-tones maximize gamma detectability).
//   2. Request_SyncPixels                       -> real GPU capture #1 (FullSync)
//   3. Debug_RedrawTargetFromLastSnapshot       -> the upload-texture redraw path
//   4. Request_SyncPixels                       -> real GPU capture #2
//
// PASS = capture #2 produces NO payload: the redraw wrote back exactly the
// bytes capture #1 read, so the diff job drops the pass as zero-diff. Any
// payload means the redraw altered pixels (gamma/format corruption).
//
// Needs a real RHI: under -nullrhi the Setup processor never creates the
// drawable target, which this test detects and reports as a skip-pass.
//============================================================================

class UCk_AutoTest_RenderTarget_GpuRoundTrip_BytePreserving : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _TestEntity;
    private FCk_Handle_RenderTarget _RenderTarget;
    private int32 _PayloadCount = 0;
    private int32 _Stage = 0;
    private int32 _SetupPolls = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _TestEntity = InHandle;

        auto Params = FCk_Fragment_RenderTarget_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.GpuRoundTrip"));
        Params.Set_Size(FIntPoint(32, 32));
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);
        Assert_True(ck::IsValid(_RenderTarget), "Add should return a valid RenderTarget handle");

        _RenderTarget.BindTo_OnPixelPayloadProduced(
            FCk_Delegate_RenderTarget_OnPixelPayloadProduced(this, n"OnPayloadProduced"));

        // The drawable target exists one tick after Add (Setup processor), and never on
        // machines that cannot render — poll, then either proceed or skip-pass.
        ScheduleTimer(0.1f, n"OnSetupPoll");
    }

    UFUNCTION()
    private void OnSetupPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!ck::IsValid(_RenderTarget.Get_Target()))
        {
            _SetupPolls++;
            if (_SetupPolls >= 10)
            {
                ck::Trace("[GpuRoundTrip] no drawable target after 1s — cannot render on this process (e.g. -nullrhi); skipping");
                FinishSuccess();
                return;
            }
            ScheduleTimer(0.1f, n"OnSetupPoll");
            return;
        }

        // Mid-tone content: a grey clear plus a couple of mid-tone shapes. pow(0.45, 2.2)
        // shifts the byte value by ~70 — any gamma mishandling produces a massive diff.
        auto ClearRequest = FCk_Request_RenderTarget_Clear();
        ClearRequest.Set_ClearColor(FLinearColor(0.45, 0.45, 0.5, 1.0));
        _RenderTarget.Request_Clear(ClearRequest);

        auto Box = FCk_Request_RenderTarget_DrawBox(FVector2D(4.0, 4.0), FVector2D(24.0, 24.0));
        Box.Set_Thickness(3.0);
        Box.Set_Color(FLinearColor(0.6, 0.3, 0.2, 1.0));
        _RenderTarget.Request_DrawBox(Box);

        auto Line = FCk_Request_RenderTarget_DrawLine(FVector2D(2.0, 2.0), FVector2D(30.0, 30.0));
        Line.Set_Thickness(2.0);
        Line.Set_Color(FLinearColor(0.2, 0.5, 0.35, 1.0));
        _RenderTarget.Request_DrawLine(Line);

        // Let the canvas pass land, then capture.
        _Stage = 1;
        ScheduleTimer(0.1f, n"OnDrawSettled");
    }

    UFUNCTION()
    private void OnDrawSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _RenderTarget.Request_SyncPixels(FCk_Request_RenderTarget_SyncPixels());
    }

    UFUNCTION()
    private void OnPayloadProduced(FCk_Handle_RenderTarget InHandle, ECk_RenderTarget_PixelPayloadKind InKind, int32 InPayloadSeq)
    {
        if (IsFinished()) { return; }

        _PayloadCount++;

        if (_Stage == 1)
        {
            Assert_True(InKind == ECk_RenderTarget_PixelPayloadKind::FullSync,
                "First-ever capture must produce a FullSync payload");

            // Redraw the target from the snapshot capture #1 just took, through the same
            // upload-texture path the pixel-apply processors use, then capture again.
            _RenderTarget.Debug_RedrawTargetFromLastSnapshot();

            _Stage = 2;
            ScheduleTimer(0.2f, n"OnRedrawSettled");
            return;
        }

        if (_Stage == 2)
        {
            FinishFailure(f"GPU round trip altered pixels — the redraw-then-capture pass produced a {InKind} payload instead of zero-diffing. Suspect gamma/format handling on the upload texture.");
        }
    }

    UFUNCTION()
    private void OnRedrawSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _RenderTarget.Request_SyncPixels(FCk_Request_RenderTarget_SyncPixels());

        // Real capture + diff runs across several frames — generous settle window before
        // declaring the zero-diff drop happened.
        ScheduleTimer(1.5f, n"OnRoundTripSettled");
    }

    UFUNCTION()
    private void OnRoundTripSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_PayloadCount, 1,
            "Capture after a snapshot redraw must zero-diff (no second payload) — the GPU round trip must be byte-preserving");
        FinishSuccess();
    }

    private void ScheduleTimer(float32 InSeconds, FName InCallbackName)
    {
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(InSeconds));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_TestEntity, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }
}
