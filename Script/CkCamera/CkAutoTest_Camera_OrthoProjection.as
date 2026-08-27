// Language=angelscript

//============================================================================
// CK CAMERA - AUTOMATION TEST: ORTHOGRAPHIC PROJECTION (profile -> ViewInfo, and the blendable ortho width)
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
// makes the scene's depth range a function of the rendering resolution - the exact failure that would only show
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
            DoCheck_ProjectionModeRequest();
            return;
        }

        if (_Frames > 30)
        { FinishFailure(f"OrthoWidth never returned to {BaseOrthoWidth} after removal (got {ComposedSensor.Get_OrthoWidth()})"); return; }

        WaitOneFrame(n"OnFrame");
    }

    // The runtime mode switch is a SEPARATE mechanism from the profile: everything above reaches ortho by
    // authoring it into the camera's params, which is the path a designer takes. Request_SetProjectionMode is
    // the path gameplay takes, and without this it had no coverage in any of the three environments - the
    // camera could have shipped able to start orthographic but not to become it.
    //
    // Every assertion here settles a frame first, and that is the CONTRACT rather than a workaround: the
    // request mutates the Current fragment immediately, but Get_ComposedProfile returns the snapshot the
    // lifecycle processor refreshes once per frame. Reading it on the calling stack reports the OLD mode
    // which is exactly what the first version of this test did, and what it failed on.
    private void DoCheck_ProjectionModeRequest()
    {
        auto Request = FCk_Request_Camera_SetProjectionMode(ECk_Camera_ProjectionMode::Perspective);
        _Camera.Request_SetProjectionMode(Request);

        _Frames = 0;
        WaitOneFrame(n"OnPerspectiveApplied");
    }

    UFUNCTION()
    private void OnPerspectiveApplied(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;

        if (_Camera.Get_ComposedProfile().Get_Sensor().Get_ProjectionMode() != ECk_Camera_ProjectionMode::Perspective)
        {
            if (_Frames > 5)
            { FinishFailure("Request_SetProjectionMode did not switch the composed profile to Perspective"); return; }

            WaitOneFrame(n"OnPerspectiveApplied");
            return;
        }

        Assert_True(true, "Request_SetProjectionMode switched the composed profile to Perspective");

        // Back to orthographic, this time carrying explicit planes in the same request - the reason the planes
        // ride WITH the mode is that an orthographic view with a perspective camera's near/far clips the scene
        // at the wrong distances, so there is no moment where a caller wants one without the other.
        auto BackToOrtho = FCk_Request_Camera_SetProjectionMode(ECk_Camera_ProjectionMode::Orthographic);
        BackToOrtho.Set_OrthoNearClipPlane(NearPlane * 2.0f);
        BackToOrtho.Set_OrthoFarClipPlane(FarPlane * 0.5f);
        _Camera.Request_SetProjectionMode(BackToOrtho);

        _Frames = 0;
        WaitOneFrame(n"OnOrthoRestored");
    }

    UFUNCTION()
    private void OnOrthoRestored(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;

        auto Sensor = _Camera.Get_ComposedProfile().Get_Sensor();
        auto ViewInfo = _Camera.Get_ViewInfo();

        const bool ModeIsBack = Sensor.Get_ProjectionMode() == ECk_Camera_ProjectionMode::Orthographic &&
                                ViewInfo.ProjectionMode == ECameraProjectionMode::Orthographic;

        if (!ModeIsBack)
        {
            if (_Frames > 5)
            { FinishFailure("Request_SetProjectionMode did not switch back to Orthographic"); return; }

            WaitOneFrame(n"OnOrthoRestored");
            return;
        }

        if (Math::Abs(Sensor.Get_OrthoNearClipPlane() - NearPlane * 2.0f) > 0.5f ||
            Math::Abs(Sensor.Get_OrthoFarClipPlane() - FarPlane * 0.5f) > 0.5f)
        {
            FinishFailure(f"Request-carried clip planes did not take: {Sensor.Get_OrthoNearClipPlane()}/{Sensor.Get_OrthoFarClipPlane()}");
            return;
        }

        if (Math::Abs(ViewInfo.OrthoNearClipPlane - NearPlane * 2.0f) > 0.5f)
        { FinishFailure(f"ViewInfo near plane is {ViewInfo.OrthoNearClipPlane}, expected {NearPlane * 2.0f}"); return; }

        Assert_True(true, "The requested mode and its clip planes reach both the composed profile and ViewInfo");
        FinishSuccess();
    }
}
