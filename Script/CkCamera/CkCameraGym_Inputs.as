// Language=angelscript

//============================================================================
// CK CAMERA — GYM INPUT ACTIONS
//============================================================================
//
// Enhanced Input actions for the Camera gym, declared as AngelScript assets (mirrors BusterBlock's
// BB_InputAction_Assets.as) — without the input-profile-object abstraction. The gym PlayerController builds
// an Input Mapping Context over these in BeginPlay and binds handlers.
//============================================================================

namespace ck_camera_gym
{
    // Mouse / right-stick orbit (X = yaw, Y = pitch) → fed to the camera via Request_SetOrientationIntention.
    asset Asset_IA_CameraLook of UCk_Axis2d_InputAction
    {
    }

    // Cycle to the next / previous camera mode (third-person → top-down → lock-on).
    asset Asset_IA_CameraNextMode of UCk_Boolean_InputAction
    {
    }

    asset Asset_IA_CameraPrevMode of UCk_Boolean_InputAction
    {
    }
}
