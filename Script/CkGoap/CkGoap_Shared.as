namespace Ck
{
	asset GoapGym_Tags of UCk_GameplayTags
	{
		GameplayTags.Add(n"Gym.Goap.SimplePlan");
		GameplayTags.Add(n"Gym.Goap.MultiStepPlan");
		GameplayTags.Add(n"Gym.Goap.NoPlanPossible");
		GameplayTags.Add(n"Gym.Goap.GoalAlreadySatisfied");
		GameplayTags.Add(n"Gym.Goap.CostComparison");
		GameplayTags.Add(n"Gym.Goap.DynamicCostUpdate");
	}

	asset GoapGym_WorldStateTags of UCk_GameplayTags
	{
		GameplayTags.Add(n"Goap.WS.HasWeapon");
		GameplayTags.Add(n"Goap.WS.EnemyVisible");
		GameplayTags.Add(n"Goap.WS.EnemyInRange");
		GameplayTags.Add(n"Goap.WS.EnemyAlive");
		GameplayTags.Add(n"Goap.WS.HasAmmo");
		GameplayTags.Add(n"Goap.WS.IsArmed");
		GameplayTags.Add(n"Goap.WS.InCover");
		GameplayTags.Add(n"Goap.WS.AreaSafe");
	}
}
