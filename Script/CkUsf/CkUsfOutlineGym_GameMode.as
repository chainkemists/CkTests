// --------------------------------------------------------------------------------------------------------------------
// Solid Outline gym GameMode (minimal - all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Solid Outline".
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfOutlineGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_UsfOutlineGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
