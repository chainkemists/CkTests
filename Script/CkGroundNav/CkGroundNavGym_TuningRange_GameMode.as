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
//   75uu catwalk off the side  LedgeSensitivity - the narrowest strip whose EDGE columns the filter
//                              reaches; it narrows the strip rather than erasing it, because the
//                              filter counts dropping sides per column and the middle has none
//   160uu gap between pillars  clearance - the only pinch in an otherwise open field
//
// Every control re-bakes, so the picture on screen always matches the values in the panel.
//
// The R and Y bakes are a DEBUG picture: no volume holds one, and nothing about one is reflected -
// FCk_GroundNav_DebugSnapshot is a plain C++ struct that no Utils class exposes. The VERDICT row at
// the top of the panel is therefore read off a VOLUME this gym mints over the same scene.
//
// THAT VOLUME TRACKS THE PANEL. A volume's params are read once, at Add, so no key can push a tunable
// into a standing one - which is why every tunable key, and R and Y with them, RE-MINT it from the
// panel's current values (DoRemintField), using the same arithmetic the cvar side applies. The
// picture and the verdict are therefore two readings of ONE profile: turning a dial moves both, and
// the verdict names the ledge sensitivity it evaluated so a reader can see that it did.
//
// Links, repairs, paints, walked routes and no-route probes are NOT here. Each is asked OF a volume
// rather than of a debug bake, and each now has a gym of its own: GroundNav Links, GroundNav Repair,
// GroundNav Routing.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_TuningRange_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_TuningRange_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
