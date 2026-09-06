// --------------------------------------------------------------------------------------------------------------------
// GroundNav Repair - one slab, one volume, and the three ways a published field goes stale
//
// A GroundNav volume publishes a field, and everything that reads ground reads THAT field. This gym
// is the three things that can make it wrong, and the one request that puts it right again.
//
// THE BODY THAT MOVED. A 400uu box jumps one 800uu tile, out of the Jolt static world and back into it
// at the new place. That round trip is the only way ground in a Ck scene goes stale: the static world
// holds its own copy of a shape at the position it was baked at, so an actor moved without it is still
// standing where it was as far as every bake is concerned. The repair then opens over the UNION of both
// footprints, never just the one the body arrived on - the half it LEFT is ground nothing else will
// ever revisit, so a repair aimed only at the new position leaves the old footprint blocked for the
// rest of the field's life.
//
// THE PAINT. A 500uu impassable box dropped across the walkers' corridor, through the provider-NEUTRAL
// request the crowd itself goes through: it names a shape and a place and nothing about which backend
// answers it. The paint's lifetime IS its markup handle, so releasing it is destroying an entity, and
// the panel reads the handle back rather than remembering that it asked.
//
// THE BACKEND. The provider is a per-WORLD choice. On Recast the volume stays baked and still answers
// its own counts, but nothing routes through it - which is why that is the FIRST thing the verdict
// checks and the only thing it says when it is wrong.
//
// The crowd walkers are here so the paint has somebody to be in the way of. They ping-pong along the
// corridor rather than parking at the far end: a corridor whose bodies all stopped after one crossing
// shows nothing about a paint dropped onto it a minute later.
//
// LOCALITY is the claim this gym exists to make, and it is made from the BUILD EPOCH: a local repair is
// exactly one publish, so the epoch read after it must be the epoch read the instant BEFORE the repair
// was asked for, plus one. That snapshot is taken at the REPAIR keypress and not at the nudge, because
// anything else this panel offers can republish the field in between - and a paint or a provider swap
// dropped between the two would otherwise be reported as a repair that was not local. How
// many TILES that repair rebuilt has no readback anywhere in utils_ground_nav_volume - the tile counts
// there describe the whole published field - so the verdict says "tile locality: no readback" rather
// than subtracting two whole-field numbers and calling the difference a measurement.
//
// The ramp, the multi-tile crossing and the no-route pocket that once shared this slab belong to the
// Routing gym; the bake tunables belong to the Tuning Range; the authored links belong to the Links
// gym. What is left here is the one volume and the three things that make it lie.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Repair_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Repair_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
