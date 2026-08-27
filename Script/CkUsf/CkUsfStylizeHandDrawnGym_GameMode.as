// --------------------------------------------------------------------------------------------------------------------
// Hand-Drawn gym GameMode (minimal - all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Stylize: Hand-Drawn".
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfStylizeHandDrawnGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_UsfStylizeHandDrawnGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
