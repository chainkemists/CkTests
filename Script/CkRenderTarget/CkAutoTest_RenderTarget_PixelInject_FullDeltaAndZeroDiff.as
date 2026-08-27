// Language=angelscript

//============================================================================
// CK RENDER TARGET - AUTOMATION TEST: PIXEL INJECT FULL / ZERO-DIFF / DELTA
//============================================================================
//
// Exercises the capture-side pixel pipeline through the Debug_InjectCapturedPixels
// test seam - works under -nullrhi because everything downstream of
// the GPU readback (diff, compress, payload production) is CPU-side:
//
//   1. Inject image A with no prior snapshot  -> FullSync payload, seq 1
//   2. Inject the SAME image A again          -> zero diff, payload DROPPED
//   3. Inject a modified image A'             -> Delta payload, seq 2
//
// Step 2's "nothing happened" is asserted by waiting a generous settle window
// after the second inject and checking the payload count is still 1 before
// injecting step 3.
//============================================================================

class UCk_AutoTest_RenderTarget_PixelInject_FullDeltaAndZeroDiff : UCk_AutoTest_Base
{
    private FCk_Handle _TestEntity;
    private FCk_Handle_RenderTarget _RenderTarget;
    private int32 _PayloadCount = 0;
    private int32 _Stage = 0;

    private int32 Get_ImageSide() const { return 32; }

    private TArray<uint8> MakeFlatImage(uint8 InValue) const
    {
        TArray<uint8> Pixels;
        auto NumBytes = Get_ImageSide() * Get_ImageSide() * 4;
        for (auto Index = 0; Index < NumBytes; ++Index)
        {
            Pixels.Add(InValue);
        }
        return Pixels;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _TestEntity = InHandle;
        auto SyncName = utils_gameplay_tag::ResolveGameplayTag(n"RenderTarget.AutoTest.PixelInject");

        auto Params = FCk_Fragment_RenderTarget_ParamsData(SyncName);
        Params.Set_Size(FIntPoint(Get_ImageSide(), Get_ImageSide()));
        Params.Set_Replication(ECk_Replication::DoesNotReplicate);

        _RenderTarget = utils_render_target::Add(LocalHandle, Params);
        Assert_True(ck::IsValid(_RenderTarget), "Add should return a valid RenderTarget handle");

        _RenderTarget.BindTo_OnPixelPayloadProduced(
            FCk_Delegate_RenderTarget_OnPixelPayloadProduced(this, n"OnPayloadProduced"));

        _Stage = 1;
        _RenderTarget.Debug_InjectCapturedPixels(MakeFlatImage(50), FIntPoint(Get_ImageSide(), Get_ImageSide()));
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
            Assert_Equals_Int(InPayloadSeq, 1, "First payload should carry seq 1");

            // Same content again -> the diff job must drop the pass (no payload event).
            _Stage = 2;
            _RenderTarget.Debug_InjectCapturedPixels(MakeFlatImage(50), FIntPoint(Get_ImageSide(), Get_ImageSide()));
            ScheduleSettle();
            return;
        }

        if (_Stage == 2)
        {
            FinishFailure("Zero-diff inject produced a payload - it must be dropped");
            return;
        }

        if (_Stage == 3)
        {
            Assert_True(InKind == ECk_RenderTarget_PixelPayloadKind::Delta,
                "A changed capture against an established snapshot must produce a Delta payload");
            Assert_Equals_Int(InPayloadSeq, 2, "Dropped zero-diff pass must NOT consume a payload seq");
            Assert_Equals_Int(_PayloadCount, 2, "Exactly two payloads expected across the three injects");

            FinishSuccess();
        }
    }

    // The zero-diff pass runs on a background task - give it a generous settle window before
    // declaring "nothing was produced" and moving to the delta stage.
    private void ScheduleSettle()
    {
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_TestEntity, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnZeroDiffSettled"));
    }

    UFUNCTION()
    private void OnZeroDiffSettled(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_PayloadCount, 1, "Zero-diff inject must not have produced a payload");

        _Stage = 3;
        auto Modified = MakeFlatImage(50);
        Modified[0] = 200;   // one changed pixel -> one changed block
        _RenderTarget.Debug_InjectCapturedPixels(Modified, FIntPoint(Get_ImageSide(), Get_ImageSide()));
    }
}
