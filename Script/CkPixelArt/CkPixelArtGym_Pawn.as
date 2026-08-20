// Language=angelscript

//============================================================================
// PIXEL ART GYM — PAWN AND ITS FIXED ORTHOGRAPHIC CAMERA
//============================================================================
//
// The gym needs its own pawn for exactly one reason: the technique is ORTHOGRAPHIC-ONLY and the shared gym
// pawn is perspective.
//
// The camera snap is what stops texels crawling, and it is skipped outright on a perspective view
// (CkPixelArtRenderer_ViewExtension.cpp, SetupViewProjectionMatrix). That is by construction, not by omission:
// one world-space snap displaces near and far geometry by different screen amounts, so there is no snap that
// corrects all depths at once.
//
// Run this gym on the shared pawn and the result is a low-resolution UNSNAPPED image on every station — which
// looks exactly like the CREEP station and makes all three A/B verdicts meaningless while still appearing to
// work. That is too quiet a failure to leave to an operator remembering to type
// r.Ortho.Debug.ForceAllCamerasToOrtho, so the gym composes the camera it needs.
//
// [P] flips the projection at runtime, and that is part of the exercise rather than a debug affordance:
// perspective IS what the defect looks like, and flipping back and forth is the fastest way to learn to
// recognise it in a real project.
//
// Movement is polled rather than bound, for the same reason the camera gym polls it: ADefaultPawn's built-in
// bindings move along the control rotation, which mouse-look turns underneath a camera whose framing is
// fixed — so "forward" would drift away from "into the screen" the first time the mouse moved.
//============================================================================

// 2200uu across 640 displayed texels at 16:9/360p is ~3.4uu per texel — small enough that the judge scene's
// thin rail lands at roughly one texel (which is what the 180 station exists to push under one) and large
// enough that two 1200uu-spaced stations are never both fully framed, so a station change is unambiguous.
const float32 k_PixelArtGym_OrthoWidth = 2200.0f;

// Explicit planes, never auto-calculated: the engine derives those from the view rect, which would make the
// gym's depth range a function of the internal resolution — so the 180/360/540 stations would silently be
// judging three different scenes.
const float32 k_PixelArtGym_NearClip = 10.0f;
const float32 k_PixelArtGym_FarClip = 50000.0f;

const float32 k_PixelArtGym_BoomLength = 2500.0f;
const float32 k_PixelArtGym_BoomPitch = -35.0f;
const float32 k_PixelArtGym_BoomYaw = 0.0f;
const float32 k_PixelArtGym_MoveSpeedScale = 1.0f;

// Fixed framing: no orbit, no auto-reorient, no collision push-in. Every one of those moves the camera for
// reasons unrelated to the pan, and the creep verdicts are read off camera motion.
class UCk_PixelArtGym_CameraLayer_Fixed : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        const auto Override = ECk_AttributeModifier_Operation::Override;

        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_BoomArmLength(Override, k_PixelArtGym_BoomLength);
        Handle.Acquire_CameraModifier_FixedBoomRotation(Override, FRotator(k_PixelArtGym_BoomPitch, k_PixelArtGym_BoomYaw, 0.0f));

        auto Cam = Get_OwningCamera();
        Cam.Request_Set_UseFixedBoomRotation(true);
        Cam.Request_Set_HasOrientationControl(false);
        Cam.Request_Set_HasAutoReorient(false);
        Cam.Request_Set_HasCollision(false);
    }
}

class ACk_PixelArtGym_Pawn : ACk_Gym_Base_Pawn
{
    default bAddDefaultMovementBindings = false;

    // The camera director does NOT create this: _OutputComponent is the single essential constructor
    // parameter of FCk_Fragment_Camera_ParamsData and is get-only, so it has to exist on the actor first.
    UPROPERTY(DefaultComponent)
    UCk_CameraComponent CameraComponent;

    private FCk_Handle _PawnEntity;
    private FCk_Handle_Camera _Camera;
    private bool _IsOrthographic = true;

    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        _PawnEntity = FCk_Handle(InEntityScriptHandle);
        Request_OnPawnReady();
    }

    void Request_OnPawnReady() override
    {
        if (ck::Is_NOT_Valid(_PawnEntity))
        { return; }

        auto Sensor = FCk_CameraProfile_Sensor();
        Sensor.Set_ProjectionMode(ECk_Camera_ProjectionMode::Orthographic);
        Sensor.Set_OrthoWidth(k_PixelArtGym_OrthoWidth);
        Sensor.Set_OrthoNearClipPlane(k_PixelArtGym_NearClip);
        Sensor.Set_OrthoFarClipPlane(k_PixelArtGym_FarClip);

        auto Profile = FCk_CameraProfile();
        Profile.Set_Sensor(Sensor);

        auto Params = FCk_Fragment_Camera_ParamsData(CameraComponent);
        Params.Set_Profile(Profile);

        auto PawnTransform = _PawnEntity.As_Transform();
        _Camera = utils_camera::Add(PawnTransform, Params);

        if (ck::Is_NOT_Valid(_Camera))
        {
            ck::Error("Pixel Art Gym: failed to compose the orthographic camera - the snap will not run and every station will crawl");
            return;
        }

        auto Request = FCk_Request_Camera_AddLayer(UCk_PixelArtGym_CameraLayer_Fixed);
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::OneOnly);
        _Camera.Request_AddLayer(Request);

        SetActorTickEnabled(true);
    }

    bool Get_IsOrthographic() const
    {
        return _IsOrthographic;
    }

    // The whole reason this is reachable from the gym: seeing the SAME station in both projections is what
    // makes "the snap is orthographic-only" a thing you have watched rather than a sentence you have read.
    void Request_ToggleProjection()
    {
        if (ck::Is_NOT_Valid(_Camera))
        { return; }

        if (_IsOrthographic)
        {
            auto ToPerspective = FCk_Request_Camera_SetProjectionMode(ECk_Camera_ProjectionMode::Perspective);
            _Camera.Request_SetProjectionMode(ToPerspective);
            _IsOrthographic = false;

            Print("Projection: PERSPECTIVE - the camera snap is SKIPPED, so texels will crawl. That is the constraint, not a bug.", 5.0f);
            return;
        }

        // The planes ride WITH the mode: an orthographic view left on a perspective camera's near/far clips
        // the scene at the wrong distances, so there is no moment where one is wanted without the other.
        auto ToOrtho = FCk_Request_Camera_SetProjectionMode(ECk_Camera_ProjectionMode::Orthographic);
        ToOrtho.Set_OrthoNearClipPlane(k_PixelArtGym_NearClip);
        ToOrtho.Set_OrthoFarClipPlane(k_PixelArtGym_FarClip);
        _Camera.Request_SetProjectionMode(ToOrtho);
        _IsOrthographic = true;

        Print("Projection: ORTHOGRAPHIC - the camera snap is live.", 5.0f);
    }

    // Free-fly along the fixed boom yaw. The boom never yaws today, so this is world +X/+Y — written through
    // the boom rotation anyway so a future angle change carries the controls with it.
    UFUNCTION(BlueprintOverride)
    void Tick(float32 InDeltaSeconds)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PC = Cast<APlayerController>(GetController());

        if (PC == nullptr)
        { return; }

        const auto YawRot = FRotator(0.0f, k_PixelArtGym_BoomYaw, 0.0f);
        const auto Forward = YawRot.GetForwardVector();
        const auto Right = YawRot.GetRightVector();

        if (PC.IsInputKeyDown(EKeys::W)) { AddMovementInput(Forward, k_PixelArtGym_MoveSpeedScale); }
        if (PC.IsInputKeyDown(EKeys::S)) { AddMovementInput(Forward, -k_PixelArtGym_MoveSpeedScale); }
        if (PC.IsInputKeyDown(EKeys::D)) { AddMovementInput(Right, k_PixelArtGym_MoveSpeedScale); }
        if (PC.IsInputKeyDown(EKeys::A)) { AddMovementInput(Right, -k_PixelArtGym_MoveSpeedScale); }

        if (PC.IsInputKeyDown(EKeys::SpaceBar)) { AddMovementInput(FVector(0.0f, 0.0f, 1.0f), k_PixelArtGym_MoveSpeedScale); }
        if (PC.IsInputKeyDown(EKeys::LeftControl)) { AddMovementInput(FVector(0.0f, 0.0f, 1.0f), -k_PixelArtGym_MoveSpeedScale); }
    }
}
