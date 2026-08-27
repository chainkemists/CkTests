// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PHASE Q5 CUSTOM-DATA SUCCESS PATH
//============================================================================
//
// Requests SetCustomDataFloat_Late(slot=0, value=0.5), asserts that the
// DeferredApply lane completes in the submission frame and Get_CustomDataFloat(0)
// reads back 0.5.
//
// Pulls iskm_assets::RendererData_Demo() (AS-authored). Its _NumCustomDataFloat must
// be >= 1 for slot 0 to be allocated at Setup. A missing slot is a fixture failure,
// never a success-skip, because that would let a non-draining late lane pass.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_CustomDataSuccess : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;
    private int64 _SubmissionFrame = 0;
    private int32 _CompletionFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();

        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto TransformHandle = utils_transform::Add(LocalHandle, FTransform::Identity);

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(TransformHandle, Params);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            _SubmissionFrame = utils_time::Get_FrameCounter();
            utils_iskm_proxy::Request_SetCustomDataFloat_Late(_Proxy,
                FCk_Request_IskmProxy_SetCustomDataFloat(int32(0), 0.5f),
                FCk_Delegate_Request_OnCompleted(this, n"OnLateWriteCompleted"));
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            const auto Value = utils_iskm_proxy::Get_CustomDataFloat(_Proxy, int32(0));
            Assert_True(Value == 0.5f,
                "Get_CustomDataFloat(0) should read back the value written via the late request lane");
            Assert_Equals_Int(_CompletionFireCount, 1,
                "the late custom-data request completion must fire exactly once");
            FinishSuccess();
        }
    }

    UFUNCTION()
    private void OnLateWriteCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _CompletionFireCount++;
        Assert_True(InRequestOwner == _Proxy,
            "late custom-data completion must report the IskmProxy request owner");
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            "late custom-data completion must report Succeeded after application");
        Assert_True(utils_time::Get_FrameCounter() == _SubmissionFrame,
            "DeferredApply must consume a late custom-data request in its submission frame");
        Assert_True(utils_iskm_proxy::Get_CustomDataFloat(_Proxy, int32(0)) == 0.5f,
            "late completion must fire after the CPU-authoritative custom-data cache is updated");
    }
}

class ACk_AutoTest_IskmRenderer_CustomDataSuccess_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_CustomDataSuccess;
    default _TimeoutSeconds = 5.0f;
}
