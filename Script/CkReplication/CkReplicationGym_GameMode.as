//============================================================================
// REPLICATION GYM — GAME MODE
//============================================================================

class ACk_ReplicationGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ReplicationGym_PlayerController;
    default DefaultPawnClass = ACk_ReplicationGym_Pawn;
}
