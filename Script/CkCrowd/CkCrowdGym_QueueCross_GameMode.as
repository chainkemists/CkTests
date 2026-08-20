// --------------------------------------------------------------------------------------------------------------------
// Crowd Queue-Cross Gym
//
// A standing line of 14 parked agents; 6 crossers auto-dispatch with goals VERY close on the far
// side of the line — the exact field symptom: "instead of pathing around the queue, the NPC tries
// to go through it, jitters, and never arrives."
//
// The crossers wait until the line's stationary markup is CONFIRMED on the navmesh (that is what
// makes the line visible to planning at all), then dispatch.
//
// What to watch:
//   Pre-fix  — crossers plan straight through the line (a 64x toll loses to a short crossing),
//              press into bodies they can never pass, and fidget.
//   Post-fix — strict planning treats the painted line as a WALL: every crosser routes around an
//              end of the line; the queue is undisturbed; everyone arrives.
//
// Console:
//   Ck_GymCrowd_QueueCross_Spawn     respawn the full scenario (14 line members + 6 crossers)
//   Ck_GymCrowd_QueueCross_Reset     destroy every spawned agent
//   Ck_GymCrowd_QueueCross_Digest    emit the per-agent [CrowdDiag] digest
//
// Visuals: ck.Crowd.Debug 1 | ck.Crowd.Debug.AgentBody 1 | ck.CrowdDebugger 1
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_QueueCross_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_QueueCross_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
