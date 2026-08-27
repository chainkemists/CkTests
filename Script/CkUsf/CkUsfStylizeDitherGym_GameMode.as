// --------------------------------------------------------------------------------------------------------------------
// Screen Dither gym GameMode (minimal - all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Stylize: Screen Dither".
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfStylizeDitherGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_UsfStylizeDitherGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
