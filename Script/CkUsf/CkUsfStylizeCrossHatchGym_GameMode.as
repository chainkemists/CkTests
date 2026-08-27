// --------------------------------------------------------------------------------------------------------------------
// Cross-Hatch gym GameMode (minimal - all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Stylize: Cross Hatch".
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfStylizeCrossHatchGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_UsfStylizeCrossHatchGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
