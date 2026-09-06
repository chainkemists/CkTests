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
// The per-agent VETO - a body that may not take a link by id, or may not take ladders by the link's
// user-type tag - has no control here: this gym owns no crowd agent to carry the params, and a veto
// with nobody to apply it to would show nothing. It is exercised by the autotest
// CkAutoTest_GroundNav_Link_VetoRoutesAroundForThatAgentOnly instead.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Links_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Links_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
