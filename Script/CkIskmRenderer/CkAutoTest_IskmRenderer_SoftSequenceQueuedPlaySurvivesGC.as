// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: soft sequence resolves, plays, survives GC
//============================================================================
//
// Pins the soft-ref request pipeline end-to-end (mirror of the AudioTrack
// SoftSoundResolvesPlaysAndSurvivesGC shape):
//   1. Request_PlayAnimation enqueued IMMEDIATELY after Add - it must queue
//      behind FTag_IskmProxy_NeedsSetup, carrying its soft sequence + the
//      enqueue-time loader batch through the queue.
//   2. Once Setup completes, the drain resolves the sequence from the batch
//      and plays it.
//   3. A full GC pass while playing must not tear the sequence away (the
//      single-node instance roots what it plays; the batch rooted it across
//      the queue window).
//
// Scope: in-editor the asset registry keeps real assets resident, so the
// negative half (a fragment-held pointer alone would dangle) is only
// falsifiable packaged - the C++ unit tests own the params-layer no-dangle
// contract; this test owns the resolve/queue/root pipeline.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_SoftSequenceQueuedPlaySurvivesGC : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        UAnimSequenceBase TestSequence = assets::load::MM_Idle();

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestSequence))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto TransformHandle = utils_transform::Add(LocalHandle, FTransform::Identity);

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(TransformHandle, Params);

        TSubclassOf<UAnimInstance> NullClass;
        utils_iskm_proxy::Request_SetAnimInstanceClass(_Proxy, NullClass);

        // Requested BEFORE the proxy's Setup completes - must queue behind
        // NeedsSetup and play once the drain runs.
        auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
        PlayReq.Set_Loop(true);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, PlayReq);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            auto Playing = utils_iskm_proxy::Get_PlayingAnimation(_Proxy);
            Assert_True(ck::IsValid(Playing),
                "the queued-behind-Setup PlayAnimation must have resolved its soft sequence and be playing by now");

            System::CollectGarbage();
            WaitOneFrame(n"OnGCSettled");
            _Phase = 1;
        }
    }

    UFUNCTION()
    private void OnGCSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Playing = utils_iskm_proxy::Get_PlayingAnimation(_Proxy);
        Assert_True(ck::IsValid(Playing),
            "the playing sequence must survive a full GC pass - the single-node instance roots it after the drain applied it");

        FinishSuccess();
    }
}
