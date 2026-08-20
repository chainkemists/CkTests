// --------------------------------------------------------------------------------------------------------------------
// Pixel Art gym GameMode (minimal — all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Pixel Art".
// --------------------------------------------------------------------------------------------------------------------

class ACk_PixelArtGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_PixelArtGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
