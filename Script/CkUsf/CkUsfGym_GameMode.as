// --------------------------------------------------------------------------------------------------------------------
// CkUsf gym GameMode (minimal - all logic lives in the PlayerController).
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_UsfGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
