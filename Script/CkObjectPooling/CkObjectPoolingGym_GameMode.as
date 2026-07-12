// Language=angelscript

//============================================================================
// OBJECT POOLING GYM - GAME MODE
//============================================================================

class ACk_ObjectPoolingGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ObjectPoolingGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
