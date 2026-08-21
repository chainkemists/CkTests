// --------------------------------------------------------------------------------------------------------------------
// Pixel Art gym GameMode (minimal — all logic lives in the PlayerController).
// Registered with the gym cycler in CkTests_GymRegistry.as as "Pixel Art".
// --------------------------------------------------------------------------------------------------------------------

class ACk_PixelArtGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_PixelArtGym_PlayerController;
    // NOT the shared gym pawn: that one is perspective, and the camera snap does not run on a perspective
    // view, so every station would render unsnapped and the A/B rig would compare three identical images.
    default DefaultPawnClass = ACk_PixelArtGym_Pawn;
}
