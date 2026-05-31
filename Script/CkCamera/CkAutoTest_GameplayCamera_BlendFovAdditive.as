// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: ADDITIVE FOV BLEND (end-to-end auto-blend math)
//============================================================================
//
// Exercises the whole attribute-backed camera pipeline: Add materializes the tuner attributes (FOV default 90);
// a layer acquires an ADDITIVE FOV modifier with target +30; the framework auto-blends it in (FProcessor_
// CameraLayer_Blend rewrites the modifier delta = target*alpha each frame, before the attribute recompute).
// At full blend the composed FOV is 90 + 30 = 120. Removing the layer blends it out and prunes it, returning
// the composed FOV to the 90 base.
//============================================================================

class UCk_AutoTest_GameplayCamera_BlendFovAdditive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera              _Camera;
    private int32                          _Frames = 0;
    private bool                           _Removed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Helper = Cast<ACkAutoTest_GameplayCamera_Helper>(SpawnActor(
            ACkAutoTest_GameplayCamera_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        { FinishFailure("Failed to spawn GameplayCamera helper"); return; }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        _Camera = utils_camera::Add(OwnedEntity, FCk_Fragment_Camera_ParamsData(_Helper.CameraComponent));

        auto Request = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_FovAdd30);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);

        _Frames = 0;
        WaitOneFrame(n"OnFrame");
    }

    UFUNCTION()
    private void OnFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;
        const float32 Fov = _Camera.Get_ComposedProfile().Get_Sensor().Get_FOV();

        if (!_Removed)
        {
            if (Math::Abs(Fov - 120.0f) < 0.5f)
            {
                Assert_True(true, "Additive FOV modifier blended composed FOV to base+30 (120)");

                auto Request = FCk_Request_Camera_RemoveLayer(UCk_AutoTest_CameraLayer_FovAdd30);
                Request.Set_BlendOutTime(FCk_Time(0.02));
                _Camera.Request_RemoveLayer(Request);
                _Removed = true;
                _Frames = 0;
                WaitOneFrame(n"OnFrame");
                return;
            }

            if (_Frames > 30)
            { FinishFailure(f"FOV never reached 120 (got {Fov})"); return; }

            WaitOneFrame(n"OnFrame");
        }
        else
        {
            if (Math::Abs(Fov - 90.0f) < 0.5f)
            {
                Assert_True(true, "Composed FOV returned to base (90) after layer removal");
                FinishSuccess();
                return;
            }

            if (_Frames > 30)
            { FinishFailure(f"FOV never returned to 90 after removal (got {Fov})"); return; }

            WaitOneFrame(n"OnFrame");
        }
    }
}
