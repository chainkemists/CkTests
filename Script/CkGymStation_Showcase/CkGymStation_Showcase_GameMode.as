//============================================================================
// Station Showcase Gym - GameMode
//
// Sandbox gym for iterating on UCk_EntityScript_GymStation. Spawns no nav
// infrastructure, no test agents - just a row of GymStation instances with
// varied tuners (see ACk_StationShowcaseGym_PlayerController::Request_StartGym).
//============================================================================

class ACk_StationShowcaseGym_GameMode : ACk_Gym_Base_GameMode
{
	default PlayerControllerClass = ACk_StationShowcaseGym_PlayerController;
	default DefaultPawnClass = ACk_Gym_Base_Pawn;
};
