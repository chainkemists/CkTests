// Subset of the Navigation gym that spawns ONLY the two single-agent stations
// (Find Path + Moving Agent). Skips the crowd-stress stations (Ring/CounterFlow/
// Cluster/Density) so logs aren't drowned by 60+ background agents — useful when
// debugging the basic CrowdSetup → CrowdUpdateTarget → CrowdStep loop in isolation.
//
// Used by ACk_NavigationGymSimple_GameMode.
class ACk_NavigationGymSimple_PlayerController : ACk_NavigationGym_PlayerController
{
	default _SimpleMode = true;
};
