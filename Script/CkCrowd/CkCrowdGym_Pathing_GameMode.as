// --------------------------------------------------------------------------------------------------------------------
// Crowd Pathing Gym - arrival stress test
//
// Drives a single CrowdAgent through Request_MoveTo -> arrival scenarios that stress the path-follow
// arrival logic: goals flush against obstacles, mid-flight re-targets, tight approaches. Built to
// reproduce (and then prove the fix for) the "agent orbits its target instead of stopping" bug.
//
// Control panel:
//   R   rebuild every scenario from scratch
//   Z   destroy the agents + obstacles
//   K   flip the close-goal strafe parameter and rebuild
//
// Visuals: green ring = arrival radius (30), red ring = predicted orbit radius (MaxSpeed/MaxTurnRate=60).
//          Live agent + path: ck.Crowd.Debug 1
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Pathing_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Pathing_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
