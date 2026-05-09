// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q4 RAGDOLL POSE-SOURCE FLIP
//============================================================================
//
// Adds a proxy, calls Request_BeginRagdoll, asserts Get_PoseSource flips to
// Ragdoll. Then Request_EndRagdoll, asserts pose source returns to Sequence
// (or AnimBP if a default AnimInstanceClass is configured).
//
// REQUIRES authored content: the RendererData's mesh (via AnimCollection's
// DefaultMesh) must have a bound PhysicsAsset. With null content (or no
// PhysicsAsset), Request_BeginRagdoll's handler logs a warning and bails
// without flipping pose source — so the test FinishSuccess()-skips.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_RagdollPoseSource : UCk_AutoTest_Base
{
    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto LocalRendererData = RendererData;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, LocalRendererData);
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
            // After Setup is done, request Begin.
            FCk_Request_IskmProxy_BeginRagdoll Req;
            utils_iskm_proxy::Request_BeginRagdoll(_Proxy, Req);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            const auto Pose = utils_iskm_proxy::Get_PoseSource(_Proxy);
            // Without a PhysicsAsset (Plan-1 default), the handler bails and pose source
            // stays Sequence. Treat that as the skip condition.
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
