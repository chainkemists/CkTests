// --------------------------------------------------------------------------------------------------------------------
// GroundNav Tuning Range - one scene that exercises every GroundNav bake tunable
//
// The scene is built from runtime-spawned boxes and baked into the Jolt static world, because the
// GroundNav geometry backend reads Jolt and nothing else. An actor that is visible but not baked is
// free space as far as the bake is concerned.
//
// What is in the scene and which tunable each part answers:
//   flat floor                 plate merge on trivially mergeable ground
//   12 steps, 20uu risers      PlaneFitToleranceUu - below 20 the steps survive, above it they merge away
//   platform over the floor    layer separation - ground stays walkable underneath, so the region has 2 layers
//   75uu catwalk off the side  LedgeSensitivity - the narrowest thing the ledge filter can erase
//   160uu gap between pillars  clearance - the only pinch in an otherwise open field
//
// Every control re-bakes, so the picture on screen always matches the values in the panel.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_TuningRange_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_TuningRange_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
