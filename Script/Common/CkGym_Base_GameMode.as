class ACk_Gym_Base_GameMode : ACk_GameMode_UE
{
    // Override these in derived gym classes
    default PlayerControllerClass = ACk_Gym_Base_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
    default HUDClass = ACkGym_MenuHUD;
}