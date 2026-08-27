// --------------------------------------------------------------------------------------------------------------------
// VoxelNav Flying vs Grounded Gym - locomotion-mode split over one baked volume
//
// Two crowd agents spawn 1000cm in the air, both bound to the same freshly baked VoxelNav volume,
// and both are sent to a goal 2000cm away that is ALSO 1000cm up. Only their _AgentMode differs.
//
// Lanes (agents move +X, the player looks back down -X from behind the goals):
//   Y = -400  FLYING    - a 1200cm-tall wall blocks the lane; the flyer climbs over it, nose pitched.
//   Y = +400  GROUNDED  - the lane is clear; the agent drops to the navmesh within a second and
//                         walks the floor flat, parking beneath its elevated goal.
//
// Console (Tab -> menu, or `~`):
//   Ck_GymVoxelNav_Restart      destroy both agents and re-run the spawn + MoveTo (volume persists)
//   Ck_GymVoxelNav_ReturnTrip   re-issue MoveTo to the opposite end; repeated calls ping-pong
//
// Visuals: dim wireframe box = volume bounds, spheres = the live goals, per-agent label = mode,
//          pitch and movement state. Planned polylines come from ck.Crowd.DrawPlannedPaths.
// --------------------------------------------------------------------------------------------------------------------

class ACk_VoxelNavGym_FlyingVsGrounded_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_VoxelNavGym_FlyingVsGrounded_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
