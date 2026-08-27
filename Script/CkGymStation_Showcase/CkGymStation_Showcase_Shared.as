//============================================================================
// STATION SHOWCASE GYM - SHARED GAMEPLAY TAGS
//
// Sandbox gym for iterating on UCk_EntityScript_GymStation in isolation.
// Each tag corresponds to one tuner-variant station spawned by the PC, so we
// can verify geometry, scaling, text, and spotlight independently of any
// other gym's noise.
//
// Tags declared here so no Config/DefaultGameplayTags.ini editing is needed.
//============================================================================

namespace Ck
{
	asset StationShowcaseGym_Tags of UCk_GameplayTags
	{
		GameplayTags.Add(n"Gym.StationShowcase.Default");
		GameplayTags.Add(n"Gym.StationShowcase.Small");
		GameplayTags.Add(n"Gym.StationShowcase.Large");
		GameplayTags.Add(n"Gym.StationShowcase.NoSpotlight");
		GameplayTags.Add(n"Gym.StationShowcase.RightAlign");
		GameplayTags.Add(n"Gym.StationShowcase.AutoSize.Wide");
		GameplayTags.Add(n"Gym.StationShowcase.AutoSize.Tall");
		GameplayTags.Add(n"Gym.StationShowcase.AutoSize.Runtime");
	}
}
