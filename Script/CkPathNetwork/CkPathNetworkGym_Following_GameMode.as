// --------------------------------------------------------------------------------------------------------------------
// Path Network Gym - sidewalk-following showcase
//
// Visual test bed for CkPathNetwork: crowd agents opted into the PathNetworkFollower feature route
// their MoveTos along ribbon networks (sidewalks) instead of beelining, keep to the right so
// opposing streams pass, take honest shortcuts when the multiplier says so, and replan live when
// the network is rebuilt under them.
//
// Stations (facing -X; scenarios play out in front of them):
//   SIDEWALK RUN       one agent walks a long straight sidewalk end to end
//   SHORTCUT VS CLING  two agents, same start/goal: multiplier 1.2 cuts the diagonal,
//                      multiplier 8 clings to the U-shaped sidewalk detour
//   OPPOSING STREAMS   two agents walk the same sidewalk in opposite directions and pass
//                      on opposite sides (right-hand walking)
//   L CORNER + GAP     the sidewalk ends short of the goal; the agent rounds the L and
//                      ramps off the end (emergent exit selection)
//   T JUNCTION         two agents share the stem, then split to opposite branch ends
//   LIVE REBUILD       the B row swaps the lane's ribbon for a dog-leg mid-walk; the
//                      agent's corridor invalidates and it detours
//
// Control panel:
//   R   rebuild every scenario from scratch
//   B   swap the LIVE REBUILD lane's ribbon mid-walk
//   Z   destroy all agents + networks
//
// Visuals: ck.PathNetwork.DebugDraw 1 (networks + corridors; forced on at start),
//          ck.Crowd.Debug 1 (agents), planned paths + breadcrumbs.
// --------------------------------------------------------------------------------------------------------------------

class ACk_PathNetworkGym_Following_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_PathNetworkGym_Following_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
