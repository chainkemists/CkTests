// --------------------------------------------------------------------------------------------------------------------
// Crowd Bunch-Up Gym
//
// N agents (20 auto-spawn on gym start, once the navmesh probe resolves) on a ring, every one of
// them commanded to the SAME exact point. Only one can stand there; the rest have to learn the
// goal is taken and hold. Watch for the failure this gym exists to show: agents that never learn
// it, and fidget against the pile indefinitely.
//
// Console:
//   Ck_GymCrowd_BunchUp_Spawn <count>   spawn <count> agents (default 15) and send them all to the centre
//   Ck_GymCrowd_BunchUp_Reset           destroy every spawned agent
//   Ck_GymCrowd_BunchUp_Digest          emit the per-agent [CrowdDiag] digest for the live agents
//
// Visuals: ck.Crowd.Debug 1 (world overlays) / ck.Crowd.Debug.AgentBody 1 (capsule + cone) /
//          ck.CrowdDebugger 1 (data panel).
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_BunchUp_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_BunchUp_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
