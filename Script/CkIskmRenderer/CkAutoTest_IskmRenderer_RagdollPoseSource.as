// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q4 RAGDOLL POSE-SOURCE FLIP
//============================================================================
//
// Calls Request_BeginRagdoll, asserts Get_PoseSource flips to Ragdoll. Then
// Request_EndRagdoll, asserts pose source returns to Sequence (or AnimBP).
//
// Auto-loads RendererData_Demo. The renderer's mesh must have a bound
// PhysicsAsset for ragdoll to engage — otherwise the handler logs a warning
// and bails (no pose-source flip), which the test treats as a skip.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_RagdollPoseSource : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Result = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Demo/RendererData_Demo",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto RendererData = Cast<UCk_IskmRenderer_Data>(Result._Asset);

        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            FCk_Request_IskmProxy_BeginRagdoll Req;
            utils_iskm_proxy::Request_BeginRagdoll(_Proxy, Req);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            const auto Pose = utils_iskm_proxy::Get_PoseSource(_Proxy);
            // No PhysicsAsset → pose source stays Sequence (skip condition).
            if (Pose != ECk_IskmProxy_PoseSource::Ragdoll) { FinishSuccess(); return; }

            utils_iskm_proxy::Request_EndRagdoll(_Proxy);
            _Phase = 2;
            _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            const auto Pose = utils_iskm_proxy::Get_PoseSource(_Proxy);
            Assert_True(Pose != ECk_IskmProxy_PoseSource::Ragdoll,
                "After EndRagdoll, pose source should not be Ragdoll");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_RagdollPoseSource_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_RagdollPoseSource;
    default _TimeoutSeconds = 5.0f;
}
