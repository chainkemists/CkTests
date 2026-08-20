// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: ORTHOGRAPHIC PROJECTION (profile -> ViewInfo, and the blendable ortho width)
//============================================================================
//
// Orthographic support splits across the two mechanisms the camera already has, and this test is what keeps them
// from being confused for each other:
//
//   - the ortho WIDTH is a tuner attribute, so a layer can blend it exactly like FOV;
//   - the projection MODE and its clip planes are plain fields, because there is no such thing as a
//     half-orthographic camera and no meaningful way to interpolate one.
//
// It also pins the planes as EXPLICIT. The engine can derive them from the view rect instead, which silently
// makes the scene's depth range a function of the rendering resolution — the exact failure that would only show
// up much later, in something that renders at a different internal size.
//============================================================================

// OVERRIDE OrthoWidth -> 2048. Doubling the base width is deliberately unmistakable: a modifier that silently did
// nothing would still leave the composed value at the 1024 base, so the assertion cannot pass by accident.
class UCk_AutoTest_CameraLayer_OrthoWidthOverride2048 : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_OrthoWidth(ECk_AttributeModifier_Operation::Override, 2048.0f);
    }
}

class UCk_AutoTest_Camera_OrthoProjection : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera                 _Camera;
    private int32                             _Frames = 0;
    private bool                              _LayerAdded = false;
    private bool                              _LayerRemoved = false;

    private const float32 BaseOrthoWidth = 1024.0f;
    private const float32 LayerOrthoWidth = 2048.0f;
    private const float32 NearPlane = 10.0f;
    private const float32 FarPlane = 50000.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        auto Sensor = FCk_CameraProfile_Sensor();
        Sensor.Set_ProjectionMode(ECk_Camera_ProjectionMode::Orthographic);
        Sensor.Set_OrthoWidth(BaseOrthoWidth);
        Sensor.Set_OrthoNearClipPlane(NearPlane);
        Sensor.Set_OrthoFarClipPlane(FarPlane);

        auto Profile = FCk_CameraProfile();
        Profile.Set_Sensor(Sensor);

        auto Params = FCk_Fragment_Camera_ParamsData(_Helper.CameraComponent);
        Params.Set_Profile(Profile);

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        auto OwnedTransform = OwnedEntity.As_Transform();
        _Camera = utils_camera::Add(OwnedTransform, Params);

        _Frames = 0;
        WaitOneFrame(n"OnFrame");
    }

    UFUNCTION()
    private void OnFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;

        auto ComposedSensor = _Camera.Get_ComposedProfile().Get_Sensor();
        auto ViewInfo = _Camera.Get_ViewInfo();

        if (!_LayerAdded)
        {
            if (_Frames < 2)
            { WaitOneFrame(n"OnFrame"); return; }

            if (ComposedSensor.Get_ProjectionMode() != ECk_Camera_ProjectionMode::Orthographic)
            { FinishFailure("Composed profile did not report an orthographic projection"); return; }

            if (Math::Abs(ComposedSensor.Get_OrthoWidth() - BaseOrthoWidth) > 0.5f)
            { FinishFailure(f"Composed OrthoWidth is {ComposedSensor.Get_OrthoWidth()}, expected {BaseOrthoWidth}"); return; }

            if (ViewInfo.ProjectionMode != ECameraProjectionMode::Orthographic)
            { FinishFailure("ViewInfo did not report an orthographic projection"); return; }

            if (Math::Abs(ViewInfo.OrthoWidth - BaseOrthoWidth) > 0.5f)
            { FinishFailure(f"ViewInfo OrthoWidth is {ViewInfo.OrthoWidth}, expected {BaseOrthoWidth}"); return; }

            // The whole point of D4's explicit planes: auto-calculated ones are derived from the view rect.
            if (ViewInfo.bAutoCalculateOrthoPlanes)
            { FinishFailure("ViewInfo has auto-calculated ortho planes, which makes depth range resolution-dependent"); return; }

            if (Math::Abs(ViewInfo.OrthoNearClipPlane - NearPlane) > 0.5f ||
                Math::Abs(ViewInfo.OrthoFarClipPlane - FarPlane) > 0.5f)
            {
                FinishFailure(f"ViewInfo ortho planes are {ViewInfo.OrthoNearClipPlane}/{ViewInfo.OrthoFarClipPlane}, expected {NearPlane}/{FarPlane}");
                return;
            }

            Assert_True(true, "Orthographic profile reached ViewInfo with explicit planes");

            auto AddRequest = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_OrthoWidthOverride2048);
            AddRequest.Set_BlendInTime(FCk_Time(0.02));
            _Camera.Request_AddLayer(AddRequest);

            _LayerAdded = true;
            _Frames = 0;
            WaitOneFrame(n"OnFrame");
            return;
        }

        if (!_LayerRemoved)
        {
            if (Math::Abs(ComposedSensor.Get_OrthoWidth() - LayerOrthoWidth) < 0.5f)
            {
                if (Math::Abs(ViewInfo.OrthoWidth - LayerOrthoWidth) > 0.5f)
                { FinishFailure(f"Composed OrthoWidth reached {LayerOrthoWidth} but ViewInfo still reads {ViewInfo.OrthoWidth}"); return; }

                Assert_True(true, "A layer modifier blended the composed OrthoWidth to 2048 and it reached ViewInfo");

                auto RemoveRequest = FCk_Request_Camera_RemoveLayer(UCk_AutoTest_CameraLayer_OrthoWidthOverride2048);
                RemoveRequest.Set_BlendOutTime(FCk_Time(0.02));
                _Camera.Request_RemoveLayer(RemoveRequest);

                _LayerRemoved = true;
                _Frames = 0;
                WaitOneFrame(n"OnFrame");
                return;
            }

            if (_Frames > 30)
            { FinishFailure(f"OrthoWidth never reached {LayerOrthoWidth} (got {ComposedSensor.Get_OrthoWidth()})"); return; }

            WaitOneFrame(n"OnFrame");
            return;
        }

        if (Math::Abs(ComposedSensor.Get_OrthoWidth() - BaseOrthoWidth) < 0.5f)
        {
            Assert_True(true, "Composed OrthoWidth returned to the 1024 base after the layer was removed");
            FinishSuccess();
            return;
        }

        if (_Frames > 30)
        { FinishFailure(f"OrthoWidth never returned to {BaseOrthoWidth} after removal (got {ComposedSensor.Get_OrthoWidth()})"); return; }

        WaitOneFrame(n"OnFrame");
    }
}
