// Language=angelscript

//============================================================================
// CK CAMERA - EXAMPLE LAYER: THIRD-PERSON FOLLOW + ORBIT
//============================================================================
//
// Reference CameraLayer: a third-person boom (long-ish arm, slight over-the-shoulder framing) with
// player-controlled orbit (orientation control) + collision push-in. Acquires Override modifiers on the tuner
// attributes (target is the value at full blend; the framework auto-blends them in/out by this layer's alpha) and
// toggles the non-blending bool leaves via Request_Set_*. The owning camera is derived from the layer handle.
//============================================================================

class UCk_CameraLayer_ThirdPerson : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        const auto Override = ECk_AttributeModifier_Operation::Override;

        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_BoomArmLength(Override, 350.0f);
        Handle.Acquire_CameraModifier_FramingOffset(Override, FVector(0.0f, 45.0f, 25.0f)); // slight over-the-shoulder
        Handle.Acquire_CameraModifier_FOV(Override, 80.0f);

        // Player-controlled orbit (consumes the orientation intention fed via Request_SetOrientationIntention).
        Handle.Acquire_CameraModifier_OrientationControlYawSpeed(Override, 180.0f);
        Handle.Acquire_CameraModifier_OrientationControlYawLimits(Override, -180.0f, ECk_MinMaxCurrent::Min);
        Handle.Acquire_CameraModifier_OrientationControlYawLimits(Override, 180.0f, ECk_MinMaxCurrent::Max);
        Handle.Acquire_CameraModifier_OrientationControlPitchSpeed(Override, 120.0f);
        Handle.Acquire_CameraModifier_OrientationControlPitchLimits(Override, -70.0f, ECk_MinMaxCurrent::Min);
        Handle.Acquire_CameraModifier_OrientationControlPitchLimits(Override, 70.0f, ECk_MinMaxCurrent::Max);

        // Non-blending mode flags (camera-global; the OneOnly-evicting entering layer establishes them).
        auto Cam = Get_OwningCamera();
        Cam.Request_Set_UseFixedBoomRotation(false);
        Cam.Request_Set_HasOrientationControl(true);
        Cam.Request_Set_HasAutoReorient(false);
        Cam.Request_Set_HasCollision(true);
    }
}
