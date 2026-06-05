// Language=angelscript

//============================================================================
// CK CAMERA — EXAMPLE LAYER: LOCK-ON / AUTO-REORIENT
//============================================================================
//
// Input-free lock-on: auto-reorient drives the boom toward a look-at target (supplied via the AddLayer request's
// _CameraTarget in LookAt mode, resolved as the dominant layer's look-at and fed into the POV pipeline).
// Orientation control is off — the camera tracks the target, not the player's stick.
//============================================================================

class UCk_CameraLayer_LockOn : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        const auto Override = ECk_AttributeModifier_Operation::Override;

        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_BoomArmLength(Override, 300.0f);
        Handle.Acquire_CameraModifier_FOV(Override, 75.0f);

        Handle.Acquire_CameraModifier_AutoReorientYawSpeed(Override, 180.0f);
        Handle.Acquire_CameraModifier_AutoReorientYawLimits(Override, -180.0f, ECk_MinMaxCurrent::Min);
        Handle.Acquire_CameraModifier_AutoReorientYawLimits(Override, 180.0f, ECk_MinMaxCurrent::Max);
        Handle.Acquire_CameraModifier_AutoReorientPitchSpeed(Override, 120.0f);
        Handle.Acquire_CameraModifier_AutoReorientPitchLimits(Override, -60.0f, ECk_MinMaxCurrent::Min);
        Handle.Acquire_CameraModifier_AutoReorientPitchLimits(Override, 20.0f, ECk_MinMaxCurrent::Max);

        auto Cam = Get_OwningCamera();
        Cam.Request_Set_UseFixedBoomRotation(false);
        Cam.Request_Set_HasOrientationControl(false);
        Cam.Request_Set_HasAutoReorient(true);
        Cam.Request_Set_HasCollision(true);
    }
}
