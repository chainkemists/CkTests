// --------------------------------------------------------------------------------------------------------------------
// GroundNav Links - a deck reachable only over two authored navigation links
//
// A 400uu deck stands 200uu clear of its own floor on all four sides, so its top is an ISLAND. Two
// one-way links join it to the ground: a LADDER up its south face, priced at twice its span and
// narrowed to 40uu of clearance, and a DROP off its east edge, priced at its span and open to anyone.
// Both are authored on a volume this gym mints and bakes for itself - a link is authored ON a volume,
// and a debug bake belongs to none.
//
// Two walkers patrol from posts on the floor west of the deck to the deck top and back, so every
// round trip has to climb the ladder and take the drop. Their routes are drawn as they go, with the
// link segments in orange.
//
// U disables both links - the deck becomes an island and the walkers hold where they stop, which is
// the contract and not a fault; U again brings them back and the walkers are re-asked on the next
// publish. T cycles what the picture under them shows.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Links_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Links_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
