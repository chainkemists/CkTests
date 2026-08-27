// --------------------------------------------------------------------------------------------------------------------
// Crowd Narrow-Gap Gym
//
// A 170cm physical gap between two nav-carving walls - ~100cm of navmesh after Recast erodes the
// agent radius off both wall faces: walkable for a 42cm agent, too tight to also keep an avoidance
// margin from both sides. 20 walkers auto-spawn on one side (once the navmesh probe resolves) with
// mirrored goals on the other, so the whole crowd funnels through the pinch.
//
// What to watch:
//   Solo mode      - pre-fix: agents jitter/oscillate inside the gap; post-fix (corridor
//                    stand-down): clean single-file traversal.
//   Blocked mode   - one agent parked IN the gap. Post-fix (strict planning): walkers detour
//                    around the wall ends instead of pressing into the blocker.
//   Flank closed   - cap walls remove the detour. The only honest outcomes are a calm hold or a
//                    clean OnGoalFailed with NoCrowdFreeRouteExisted=true; perpetual pressing is
//                    the no-progress-ladder defect this layout exists to reproduce.
//
// Console:
//   Ck_GymCrowd_NarrowGap_Spawn <count>          walkers only (default 20)
//   Ck_GymCrowd_NarrowGap_SpawnBlocked <count>   1 parked blocker in the gap + walkers (default 20 total)
//   Ck_GymCrowd_NarrowGap_Flank <0|1>            open/close the detour around the wall ends
//   Ck_GymCrowd_NarrowGap_Reset                  destroy every spawned agent
//   Ck_GymCrowd_NarrowGap_Digest                 emit the per-agent [CrowdDiag] digest
//
// Visuals: ck.Crowd.Debug 1 | ck.Crowd.Debug.AgentBody 1 | ck.CrowdDebugger 1
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_NarrowGap_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_NarrowGap_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
