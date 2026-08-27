// --------------------------------------------------------------------------------------------------------------------
// Crowd Pathfinding Gym - Gate 1
//
// Verifies the new CkNavigation API end-to-end:
//   - utils_nav::Request_FindPath enqueues a path query on a Transform-bearing entity.
//   - The processor (FProcessor_Nav_HandleRequests) drains it next tick and runs FindPathSync.
//   - On success, the OnPathReady delegate fires with the FCk_Nav_PathResult (waypoints + status).
//   - On failure, the OnPathFailed delegate fires.
//
// Open the debugger to see Navmesh Status: ck.CrowdDebugger 1
//
// Console commands (Tab -> menu HUD -> or run direct from `~`):
//   Ck_GymCrowd_Path_IssueGood   issue a path to a reachable point
//   Ck_GymCrowd_Path_IssueBad    issue a path to (99999, 99999, 99999) - fails
//   Ck_GymCrowd_Path_Status      print last status + waypoint count + fail reason
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Pathfinding_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Pathfinding_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
