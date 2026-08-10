// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — GameMode
//============================================================================
//
// A drivable playground for the CkInput / CkIntent surface: one capsule pawn on
// a flat floor under a fixed top-down camera, aimed Diablo-style at the mouse
// cursor. Movement is polled from the raw device (WASD) rather than routed
// through an input profile, so the playground keeps working while the module
// underneath it is being rebuilt.
//
// Register: CkTests_GymRegistry.as -> "Input Playground". Runs in the shared
// TestGyms_CkTests_Level.
//============================================================================

class ACk_PlaygroundGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_PlaygroundGym_PlayerController;
    default DefaultPawnClass      = ACk_PlaygroundGym_Pawn;
};
