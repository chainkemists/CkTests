//============================================================================
// CKNAVIGATION GYM — SHARED GAMEPLAY TAGS
//
// Each tag corresponds to one CkNav.Gym* scenario from gym_test_plan.md.
// Tags declared here so no Config/DefaultGameplayTags.ini editing is needed.
//
// Step 7 ships only the FindPath scenario; siblings land as the matching
// processors come online (CrowdSetup, CrowdStep, regen, etc.).
//============================================================================

namespace Ck
{
	asset NavigationGym_Tags of UCk_GameplayTags
	{
		GameplayTags.Add(n"Gym.Navigation.FindPath");
		GameplayTags.Add(n"Gym.Navigation.Move");
	}
}
