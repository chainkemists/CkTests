// Language=angelscript

//============================================================================
// CK CAMERA — EXAMPLE LAYER: TOP-DOWN / FIXED FRAMING
//============================================================================
//
// Fixed (no player orbit) camera: a long boom held at a steep fixed angle looking down at the pawn; orientation
// control + collision disabled. Typically pushed OneOnly to take over from third-person (store / minigame mode).
//============================================================================

class UCk_CameraLayer_TopDown : UCk_CameraLayer_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoEnter(FCk_Handle_CameraLayer InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        const auto Override = ECk_AttributeModifier_Operation::Override;

        auto Handle = InHandle;
        Handle.Acquire_CameraModifier_BoomArmLength(Override, 1400.0f);
        // Fixed boom angle: pitch -65 lifts the camera up-and-behind the pawn and looks down at it.
        Handle.Acquire_CameraModifier_FixedBoomRotation(Override, FRotator(-65.0f, 0.0f, 0.0f)); // (Pitch, Yaw, Roll)
        Handle.Acquire_CameraModifier_FOV(Override, 70.0f);

        // Fixed framing — hold the absolute boom rotation, no manual orbit, no collision push-in.
        auto Cam = Get_OwningCamera();
        Cam.Request_Set_UseFixedBoomRotation(true);
        Cam.Request_Set_HasOrientationControl(false);
        Cam.Request_Set_HasAutoReorient(false);
        Cam.Request_Set_HasCollision(false);
    }
}
