// --------------------------------------------------------------------------------------------------------------------
// Crowd Locomotion Gym - Gate 2
//
// Smoke-tests Sub-task 2A - FProcessor_CrowdAgent_ApplyOffset.
// The chain under test:
//   FFragment_Velocity_Current -> FProcessor_EulerIntegrator_Update -> FFragment_EulerIntegrator_Current::_DistanceOffset
//   -> FProcessor_CrowdAgent_ApplyOffset -> Request_AddLocationOffset -> FProcessor_Transform_HandleRequests -> SceneNode
//
// The gym spawns one CrowdAgent with a Transform feature, a Velocity feature initialized to (100, 0, 0) cm/s
// in world space, and a zero Acceleration feature. EulerIntegrator is started so the integrator processor
// produces _DistanceOffset each tick. The new apply-offset processor consumes that offset and advances the
// agent's transform. After one second the agent's X should have advanced by ~100 cm.
//
// Console commands (run from the `~` console):
//   Ck_GymCrowd_Loco_Spawn         spawn a single agent at the station with starting velocity (100, 0, 0)
//   Ck_GymCrowd_Loco_PrintPos      print the agent's current world location
//   Ck_GymCrowd_Loco_Stop          destroy the agent
//
// Verify the debugger:  ck.CrowdDebugger 1
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Locomotion_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_CrowdGym_Locomotion_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
