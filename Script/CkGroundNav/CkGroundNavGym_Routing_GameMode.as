// --------------------------------------------------------------------------------------------------------------------
// GroundNav Routing - what a published field says about walkability and about routes
//
// One slab, and three questions asked of the volume baked over it:
//
//   the RAMP        two planks in series at 40 then 50 degrees. The volume's agent profile keeps the
//                   default 45-degree slope limit, so the lower plank is ground and the upper one is
//                   not - the ramp stops being walkable half way up rather than at its foot.
//   the CROSSING    a 2800uu route over 800uu tiles, so four tiles lie under one corridor. A tiled
//                   bake that disagreed with itself would show as a kink at a seam and nowhere else.
//   the POCKET      a 600uu island with 300uu of nothing between it and the slab. It bakes to real
//                   walkable ground, but no seam can span a gap with no ground in it and nothing
//                   authors a link across it, so nothing can reach it.
//
// Both routes are asked for with PARTIAL PATHS OFF, and for the pocket that is the whole station:
// with them on, a route that cannot reach the island answers with the closest point it COULD reach
// and reads as a success. Failed is the contract an unreachable island owes, not a disappointment.
//
// Everything the scene stands on is baked into the JOLT STATIC WORLD, because the GroundNav geometry
// backend reads Jolt and nothing else - an actor that is visible but not baked is free space as far
// as the bake is concerned.
//
// The crossing DRAW is a separate thing from the crossing PROBE, and the difference is load-bearing.
// ck.GroundNav.PathAt reads the DEBUG field, which no volume holds and no request can be aimed at, so
// the draw row bakes one over the band before it asks. The verdict reads the probe instead: a real
// request through the provider-neutral facade, answered by whichever backend the world is on - which
// is what makes the provider row worth having.
//
// Obstacles, markup, crowd walkers and authored links are NOT here. Each has a gym of its own:
// GroundNav Repair and GroundNav Links.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Routing_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Routing_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
