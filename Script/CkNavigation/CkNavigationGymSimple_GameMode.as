// Quiet variant of the Navigation gym for low-noise debugging. Reuses everything
// from ACk_NavigationGym_GameMode (floor spawn + level-side NavMeshBoundsVolume +
// bake) — only the PlayerController changes, swapping in the Simple PC that
// gates the crowd-stress stations off via _SimpleMode.
//
// To use: set the level's WorldSettings → GameMode Override to this class. The
// rest of the navigation setup (NavMeshBoundsVolume placement, bake) is unchanged.
class ACk_NavigationGymSimple_GameMode : ACk_NavigationGym_GameMode
{
	default PlayerControllerClass = ACk_NavigationGymSimple_PlayerController;
};
