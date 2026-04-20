// Language=angelscript

//============================================================================
// GOAP AUTO-REPLAN GYM — GAME MODE
//============================================================================
// Dedicated gym for the spatially-rendered auto-replan demo. See
// CkGoapAutoReplan.as for the station implementation.
//============================================================================

class ACk_GoapAutoReplanGym_GameMode : ACk_Gym_Base_GameMode
{
	default PlayerControllerClass = ACk_GoapAutoReplanGym_PlayerController;
	default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
