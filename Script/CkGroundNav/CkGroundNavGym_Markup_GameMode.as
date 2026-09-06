// --------------------------------------------------------------------------------------------------------------------
// GroundNav Markup - paint a strip impassable and watch every route bend around it
//
// Four walkers patrol west to east across one slab. Key 2 paints an impassable box across the middle
// of it, covering 80% of its width and leaving a 400uu gap at the north end - so no lane is cut off,
// and every route has to detour through the same gap. The paint is the provider-NEUTRAL request the
// crowd itself goes through, and its lifetime IS the markup handle, so key 2 again destroys it and
// the corridor reopens.
//
// A paint is answered a publish LATER, which is why the picture is re-baked and the walkers re-planned
// on the republish rather than at the keypress. The Verdict says so while it waits.
//
// T cycles what the debug picture under the walkers shows.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Markup_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Markup_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
