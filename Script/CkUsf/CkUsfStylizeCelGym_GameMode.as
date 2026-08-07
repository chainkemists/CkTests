// --------------------------------------------------------------------------------------------------------------------
// Cel Shade gym GameMode (minimal — all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Stylize: Cel Shade".
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfStylizeCelGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_UsfStylizeCelGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
