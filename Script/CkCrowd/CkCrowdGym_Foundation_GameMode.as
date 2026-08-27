// --------------------------------------------------------------------------------------------------------------------
// Crowd Foundation Gym - Gate 0
//
// Minimal gym proving that:
//   - The CkCrowd module loads
//   - UCk_Utils_CrowdAgent_UE::Add() spawns an agent fragment + entity
//   - The CkCrowdDebugger window (ck.CrowdDebugger 1) shows live agents in its list
//   - Removing an agent removes the row from the list within 1 frame
//
// No movement, no pathfinding - those land in Gates 1-2.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Foundation_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Foundation_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
