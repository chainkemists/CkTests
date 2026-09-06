// --------------------------------------------------------------------------------------------------------------------
// GroundNav Walk - bodies crossing a baked field, and the three answers the field gives them
//
// One slab carries all three. FOUR PILLARS across the middle band, so a west-east route has to weave
// rather than run straight. A RAMP of two planks side by side climbing to a small landing - the
// lower at 40 degrees and the upper at 50, either side of the profile's 45-degree slope limit - so
// the landing is reachable over the shallow plank and over nothing else. An ISLAND 300uu clear of
// the slab's south edge: real walkable ground that no seam spans and no link joins.
//
// Three walkers say so out loud: one weaves the pillars, one climbs the ramp to the landing, and one
// asks for the island and is refused - which is the contract, not a fault, so it holds where it
// stopped and the Verdict expects it to.
//
// Key 1 cycles the walker count 3 / 1 / 8; T cycles what the picture under them shows.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Walk_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Walk_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
