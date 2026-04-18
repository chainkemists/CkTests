// Language=angelscript

//============================================================================
// GOAP EMPIRE GYM — GAME MODE
//============================================================================
// Dedicated game mode for the single-station Empire visual demo. The
// coverage stations (Door / Tea / Combat / etc.) live in the CkGoap gym.
//============================================================================

class ACk_GoapEmpireGym_GameMode : ACk_Gym_Base_GameMode
{
	default PlayerControllerClass = ACk_GoapEmpireGym_PlayerController;
	default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
