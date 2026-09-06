// --------------------------------------------------------------------------------------------------------------------
// GroundNav Dynamic Obstacle - a box drops into a corridor and the field repairs under it
//
// Three walkers patrol a 3600uu corridor on lanes 300uu apart. Key 3 drops a 400uu box onto the
// middle of that corridor and lifts it again; the box goes into the Jolt static world, which is the
// only world a GroundNav bake reads, so the published field is stale the instant it lands.
//
// Key 4 is what makes that visible. With auto-repair ON a local repair runs over the box footprint
// after every drop and lift, the epoch steps, and the walkers replan around the box. With it OFF the
// drop is left standing: the picture (a fresh debug bake, which reads Jolt) shows the box while the
// published field the walkers route through does not - so they walk straight through it. The
// footprint is drawn red while stale and green once repaired. T cycles what the picture shows.
// --------------------------------------------------------------------------------------------------------------------

class ACk_GroundNavGym_Obstacle_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GroundNavGym_Obstacle_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
