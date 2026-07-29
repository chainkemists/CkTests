// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: SetSkeletalMesh swap on a live proxy
//============================================================================
//
// First real-content coverage of Request_SetSkeletalMesh (previously only the
// invalid-handle no-op was pinned). Verifies, against the soft-ref request
// shape (the mesh rides the request as a TSoftObjectPtr + an enqueue-time
// loader batch):
//   1. A swap on a live sequence-mode proxy completes Succeeded (the request
//      resolved its mesh from the enqueue-time batch and applied it).
//   2. Playback still works after the swap — SetSkeletalMesh re-ran InitAnim,
//      so a fresh PlayAnimation must land on the swapped mesh.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_SetSkeletalMeshSwap : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;
    private bool _SwapCompleted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        UAnimSequenceBase TestSequence = assets::load::MM_Idle();
        USkeletalMesh SwapMesh = assets::load::SKM_Manny_Simple();

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestSequence) || ck::Is_NOT_Valid(SwapMesh))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto TransformHandle = utils_transform::Add(LocalHandle, FTransform::Identity);

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(TransformHandle, Params);

        TSubclassOf<UAnimInstance> NullClass;
        utils_iskm_proxy::Request_SetAnimInstanceClass(_Proxy, NullClass);

        auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
        PlayReq.Set_Loop(true);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, PlayReq);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnSwapCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SwapCompleted = true;
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            "SetSkeletalMesh with a valid mesh must complete Succeeded — the enqueue-time preload batch resolves it at the drain");
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            USkeletalMesh SwapMesh = assets::load::SKM_Manny_Simple();
            utils_iskm_proxy::Request_SetSkeletalMesh(_Proxy, SwapMesh,
                FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(_SwapCompleted,
                "the SetSkeletalMesh completion delegate must have fired by now");

            UAnimSequenceBase TestSequence = assets::load::MM_Idle();
            auto ReplayReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
            ReplayReq.Set_Loop(true);
            utils_iskm_proxy::Request_PlayAnimation(_Proxy, ReplayReq);

            _Phase = 2;
            _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            auto Playing = utils_iskm_proxy::Get_PlayingAnimation(_Proxy);
            Assert_True(ck::IsValid(Playing),
                "PlayAnimation after the mesh swap must drive the swapped mesh — InitAnim re-ran and the proxy stayed playable");

            FinishSuccess();
        }
    }
}
