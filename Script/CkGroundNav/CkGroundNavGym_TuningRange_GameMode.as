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
//
// Two further groups of stations stand on VOLUMES this gym mints for them rather than on the panel's
// debug bake, because what they exercise - a link, a repair, a paint, a walked route - is asked OF a
// volume, and a debug bake belongs to none. Each sits in a Y band of its own:
//
//   links deck        (Y  +900)   an authored one-way drop and one-way ladder joining a deck to the floor beside it
//   ramp              (Y -1700)   two planks at 40 then 50 degrees, either side of the profile's 45-degree slope limit
//   moved obstacle    (Y -2300)   a body that jumps one tile, leaving ground only a repair over BOTH footprints can fix
//   painted markup    (Y -2900)   an impassable box dropped onto the crowd walkers' corridor
//   multi-tile cross  (Y -3500)   a 2800uu route over 800uu tiles - four of them under one corridor
//   no-route pocket   (Y -4400)   an island with no seam and no link, so a path to it Fails instead of returning a prefix
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_TuningRange_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_TuningRange_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
