// --------------------------------------------------------------------------------------------------------------------
// Crowd Pathing Gym - arrival stress test
//
// Drives a single CrowdAgent through Request_MoveTo -> arrival scenarios that stress the path-follow
// arrival logic: goals flush against obstacles, mid-flight re-targets, tight approaches. Built to
// reproduce (and then prove the fix for) the "agent orbits its target instead of stopping" bug.
//
// Console (Tab -> menu, or `~`):
//   Ck_GymPathing_Open        baseline open-floor goal (should arrive cleanly)
//   Ck_GymPathing_FlushBox    goal flush against a box face (reproduces the orbit)
//   Ck_GymPathing_Lateral     spawn + move far; then Ck_GymPathing_Kick re-targets to force a turn
//   Ck_GymPathing_Kick        re-target the live agent perpendicular to its velocity
//   Ck_GymPathing_Clear       destroy the agent + obstacles
//
// Visuals: green ring = arrival radius (30), red ring = predicted orbit radius (MaxSpeed/MaxTurnRate=60).
//          Live agent + path: ck.Crowd.Debug 1
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Pathing_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Pathing_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
