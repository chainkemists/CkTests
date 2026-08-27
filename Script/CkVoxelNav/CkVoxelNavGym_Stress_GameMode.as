// --------------------------------------------------------------------------------------------------------------------
// VoxelNav Stress Gym - a dense, flying-agent 3-D pathing and avoidance exercise.
// --------------------------------------------------------------------------------------------------------------------

class ACk_VoxelNavGym_Stress_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_VoxelNavGym_Stress_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
