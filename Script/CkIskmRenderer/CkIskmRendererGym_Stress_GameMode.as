// Language=angelscript

//============================================================================
// CK ISKM RENDERER STRESS GYMS - GameModes
//============================================================================
//
// Two sibling GameModes registered with the gym cycler in CkTests_GymRegistry.
// Both use ACk_Gym_Base_Pawn and a per-variant PlayerController that spawns
// the shared UCk_EntityScript_IskmRendererGym_StressArmy with the appropriate
// Moving flag.
//
//============================================================================

class ACk_IskmRendererGym_StressStatic_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IskmRendererGym_StressStatic_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_IskmRendererGym_StressMoving_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IskmRendererGym_StressMoving_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
