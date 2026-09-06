// --------------------------------------------------------------------------------------------------------------------
// GroundNav vs Recast - the same scene, the same walkers, the provider flipped under them
//
// A 3600x2400 slab with four pillars scattered across its middle band, and three walkers patrolling
// west to east through them. Everything is identical on both sides of the swap - the same bodies, the
// same posts, the same routes drawn - so the only thing that changes is which surface answered.
//
// Key 1 swaps the provider and respawns the walkers, so the verdict judges the backend that is
// answering NOW rather than a record earned on the other one. Key 2 turns on Recast's own navmesh
// draw beside the GroundNav picture. T cycles what that picture shows.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Parity_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Parity_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
