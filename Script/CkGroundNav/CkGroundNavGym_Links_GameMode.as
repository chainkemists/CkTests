// --------------------------------------------------------------------------------------------------------------------
// GroundNav Links - a deck joined to the ground beside it by two authored navigation links
//
// A deck stands on its own floor, and two one-way links join it to the ground around it: a DROP off
// the deck's east edge, and a LADDER back up its south face. Both are authored ON A VOLUME this gym
// mints and bakes for itself, and that is the whole reason this is not a corner of the tuning gym: a
// link is authored on a volume, and the tuning gym's R/Y bake is a debug picture that no volume holds
// and no request can be aimed at.
//
// The two links are deliberately not symmetric. The drop costs its own span and admits any agent -
// walking off a ledge is cheap and needs no room. The ladder is priced at TWICE its span and narrowed
// to 40uu of clearance, so a route with any way round prefers the way round and a body wider than the
// default 34uu agent is refused outright. A link never costs less than its own length: that is the
// property the search's Euclidean heuristic is admissible under.
//
// The VERDICT row reads both records off the published field every frame - each end's projection
// status, whether the record resolved, and whether it is live - so "the deck is joined to the floor"
// is a claim the panel makes from the field rather than from what this controller last asked for.
//
// NOTHING IN THE RETAINED DRAW REDRAWS ITSELF. ck.GroundNav.Debug.Mode selects what a bake draws and
// no sink acts on it, so plates exist only because ck.GroundNav.BakeFieldAt ran and links only because
// ck.GroundNav.LinksAt did. The gym runs both, aimed at the deck, as soon as the field publishes and
// again after every link toggle - the second run is deferred to the derive's republish, because the
// colours LinksAt draws come off the field and not off the record store.
//
// THE WALKER on key 1 is the half of this station a still picture cannot show. It ping-pongs between
// the floor west of the deck and the deck's top face, and since the deck stands 200uu clear of the
// floor on all four sides that round trip must climb the ladder and take the drop. Its route's own
// link ids come off its planner through Get_LinksOnPath, which is what lets the verdict INVERT with
// the toggle: with the links live a route naming none of them could not exist, and with them disabled
// the deck top is an island and a route to it must fail. That failure is bound and reported rather
// than left to strand the body: it holds where it stopped and is re-asked at the next link change,
// which is the only moment an impossible goal can have become possible.
//
// KEY 2 DRAWS THE WALKER'S OWN INSTALLED ROUTE - the waypoints its planner holds this frame, with the
// segments that step onto a link in a second colour - and NOT ck.GroundNav.PathAt. That is not a
// preference: PathAt searches the DEBUG field, and a debug bake's params are a region, a lattice and
// an agent profile with no link records anywhere in them, so a route drawn out of it cannot cross the
// drop or the ladder however the picture is aimed. The route drawn here can, because it is the one
// the body is walking.
//
// The per-agent VETO - a body that may not take a link by id, or may not take ladders by the link's
// user-type tag - still has no control here: the veto lives in the agent's path params, and a row that
// set it would be about one body's exclusion rather than about the records this station is for. It is
// exercised by the autotest CkAutoTest_GroundNav_Link_VetoRoutesAroundForThatAgentOnly instead.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Links_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Links_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
