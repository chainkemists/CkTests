// Language=angelscript
// Interactive Queue gym. The PlayerController owns the scene, queue and trace because it exists on authority.
class ACk_QueueGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_QueueGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
