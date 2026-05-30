// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — GAME MODE
//============================================================================

class ACk_NetGym_TwoPlayer_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_NetGym_TwoPlayer_PlayerController;
    default DefaultPawnClass = ACk_NetGym_TwoPlayer_Pawn;
}
