// --------------------------------------------------------------------------------------------------------------------
// Crowd Separation Gym — Gate 3
//
// Smoke-tests the full Gate 3 chain end-to-end:
//   FProcessor_CrowdAgent_Setup      → spawns probe child entity
//   FProcessor_CrowdAgent_NeighborSync → reads probe overlaps
//   FProcessor_CrowdAgent_Separation → quadratic-falloff push from cache
//   FProcessor_CrowdAgent_Steering   → combines path-follow + separation, clamps to MaxSpeed
//   FProcessor_CrowdAgent_DebugDraw  → optional in-world visualisation (ck.Crowd.Debug 1)
//
// Console commands (run from the `~` console):
//   Ck_GymCrowd_Sep_HeadOnNS     spawn 2 agents on a N↔S head-on collision course
//   Ck_GymCrowd_Sep_HeadOnEW     spawn 2 agents on an E↔W head-on collision course
//   Ck_GymCrowd_Sep_All4         spawn 4 agents from N/S/E/W targeting the opposite side
//   Ck_GymCrowd_Sep_Cluster5     spawn 5 agents around the centre, all targeting the centre point
//   Ck_GymCrowd_Sep_Clear        destroy all spawned agents
//
// Optional visuals: `ck.Crowd.Debug 1` draws separation radius circle, neighbor lines, and the
// per-agent force arrow. Open the data debugger with `ck.CrowdDebugger 1` for the agent list /
// neighbor cache / steering forces panels.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Separation_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Separation_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
