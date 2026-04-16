// Language=angelscript

//============================================================================
// GOAP GYM — ACTIONS AND GOALS
//============================================================================
// All action/goal entity scripts used by the gym, grouped by station so
// each scenario reads independently.
//
// Helper: Tag(n"...") resolves a gameplay tag inline. All actions call
// AddPrecondition / AddEffect / SetCost inside DoDefineAction. All goals
// call AddCondition / SetPriority inside DoDefineGoal.
//============================================================================

namespace goap_tags
{
	FGameplayTag T(FName InName) { return GameplayTags::ResolveGameplayTag(InName); }
}

//============================================================================
// STATION 1 — OPEN DOOR
//============================================================================

// FindKey: () -> HasKey=true
class UCk_GoapTest_Action_FindKey : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_tags::T(n"Goap.WS.Door.HasKey"), true);
		SetCost(1.0f);
	}
};

// UnlockDoor: (HasKey=true) -> Unlocked=true
class UCk_GoapTest_Action_UnlockDoor : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Door.HasKey"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Door.Unlocked"), true);
		SetCost(2.0f);
	}
};

// Goal: Unlocked=true
class UCk_GoapTest_Goal_OpenDoor : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Door.Unlocked"), true);
		SetPriority(1);
	}
};

//============================================================================
// STATION 2 — MAKE TEA (strict linear chain)
//============================================================================

class UCk_GoapTest_Action_FillKettle : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_tags::T(n"Goap.WS.Tea.HasWater"), true);
		SetCost(1.0f);
	}
};

class UCk_GoapTest_Action_BoilKettle : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Tea.HasWater"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Tea.WaterHot"), true);
		SetCost(3.0f);
	}
};

class UCk_GoapTest_Action_SteepTea : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Tea.WaterHot"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Tea.TeaSteeped"), true);
		SetCost(2.0f);
	}
};

class UCk_GoapTest_Action_PourTea : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Tea.TeaSteeped"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Tea.TeaReady"), true);
		SetCost(1.0f);
	}
};

class UCk_GoapTest_Goal_ServeTea : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Tea.TeaReady"), true);
		SetPriority(1);
	}
};

//============================================================================
// STATION 3 & 5 — COMBAT (ranged vs melee + impossible-kill subset)
//============================================================================

class UCk_GoapTest_Action_PickUpWeapon : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_tags::T(n"Goap.WS.Combat.HasWeapon"), true);
		SetCost(2.0f);
	}
};

class UCk_GoapTest_Action_LoadAmmo : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Combat.HasWeapon"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Combat.HasAmmo"), true);
		SetCost(1.0f);
	}
};

// Ranged: needs weapon + ammo + enemy in range
class UCk_GoapTest_Action_RangedAttack : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Combat.HasWeapon"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.Combat.HasAmmo"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.Combat.EnemyInRange"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Combat.EnemyAlive"), false);
		SetCost(4.0f);
	}
};

// Melee: needs weapon + enemy in range (no ammo)
class UCk_GoapTest_Action_MeleeAttack : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Combat.HasWeapon"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.Combat.EnemyInRange"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Combat.EnemyAlive"), false);
		SetCost(6.0f);
	}
};

class UCk_GoapTest_Goal_KillEnemy : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Combat.EnemyAlive"), false);
		SetPriority(10);
	}
};

// Used only by NoPlan station — dead-end actions that can't reach KillEnemy.
class UCk_GoapTest_Action_Hide : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_tags::T(n"Goap.WS.Pri.InCover"), true);
		SetCost(1.0f);
	}
};

class UCk_GoapTest_Action_Scout : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_tags::T(n"Goap.WS.Pri.EnemySpotted"), true);
		SetCost(2.0f);
	}
};

//============================================================================
// STATION 4 — PRIORITIES (multi-goal selection)
//============================================================================

// Actions — mix of basic survival/feed/fight options.
// NOTE: Scout / Hide above are re-used.

class UCk_GoapTest_Action_Eat : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Pri.HasFood"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Pri.IsHungry"), false);
		SetCost(1.0f);
	}
};

class UCk_GoapTest_Action_Forage : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_tags::T(n"Goap.WS.Pri.HasFood"), true);
		SetCost(3.0f);
	}
};

class UCk_GoapTest_Action_Suppress : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Pri.InCover"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Pri.UnderFire"), false);
		SetCost(2.0f);
	}
};

class UCk_GoapTest_Action_Neutralize : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Pri.EnemySpotted"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Pri.EnemyDown"), true);
		SetCost(4.0f);
	}
};

// Goals (different priorities)
class UCk_GoapTest_Goal_SurviveFire : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Pri.UnderFire"), false);
		SetPriority(10);
	}
};

class UCk_GoapTest_Goal_Feed : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Pri.IsHungry"), false);
		SetPriority(5);
	}
};

class UCk_GoapTest_Goal_Neutralize : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Pri.EnemyDown"), true);
		SetPriority(3);
	}
};

//============================================================================
// STATION 6 — AGE OF EMPIRES (mirrors goap_debugger_D.html action graph)
//============================================================================

// TrainVillager: (HasTownCenter) -> HasIdleVillager
class UCk_GoapTest_Action_TrainVillager : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasTownCenter"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasIdleVillager"), true);
		SetCost(3.0f);
	}
};

// SelectBuildSite: (HasIdleVillager) -> BuildSiteSelected, HasBuilder
class UCk_GoapTest_Action_SelectBuildSite : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasIdleVillager"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.BuildSiteSelected"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasBuilder"), true);
		SetCost(1.0f);
	}
};

// SendToForest: (HasIdleVillager, HasLumberCamp) -> VillagerNearForest
class UCk_GoapTest_Action_SendToForest : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasIdleVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasLumberCamp"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.VillagerNearForest"), true);
		SetCost(1.0f);
	}
};

// SendToBerries: (HasIdleVillager, HasMill) -> VillagerNearBerries
class UCk_GoapTest_Action_SendToBerries : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasIdleVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMill"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.VillagerNearBerries"), true);
		SetCost(1.0f);
	}
};

// SendToGold: (HasIdleVillager, HasMiningCamp) -> VillagerNearGold
class UCk_GoapTest_Action_SendToGold : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasIdleVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.VillagerNearGold"), true);
		SetCost(1.0f);
	}
};

// SendToStone: (HasIdleVillager, HasMiningCamp) -> VillagerNearStone
class UCk_GoapTest_Action_SendToStone : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasIdleVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.VillagerNearStone"), true);
		SetCost(1.0f);
	}
};

// GatherWood: (VillagerNearForest) -> WoodSufficient
class UCk_GoapTest_Action_GatherWood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.VillagerNearForest"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.WoodSufficient"), true);
		SetCost(5.0f);
	}
};

// GatherFood: (VillagerNearBerries) -> FoodSufficient
class UCk_GoapTest_Action_GatherFood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.VillagerNearBerries"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.FoodSufficient"), true);
		SetCost(5.0f);
	}
};

// GatherGold: (VillagerNearGold) -> GoldSufficient
class UCk_GoapTest_Action_GatherGold : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.VillagerNearGold"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.GoldSufficient"), true);
		SetCost(5.0f);
	}
};

// GatherStone: (VillagerNearStone) -> StoneSufficient
class UCk_GoapTest_Action_GatherStone : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.VillagerNearStone"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.StoneSufficient"), true);
		SetCost(5.0f);
	}
};

// BuildLumberCamp: (HasBuilder, WoodSufficient, BuildSiteSelected) -> HasLumberCamp
class UCk_GoapTest_Action_BuildLumberCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBuilder"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.WoodSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.BuildSiteSelected"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasLumberCamp"), true);
		SetCost(4.0f);
	}
};

// BuildMill: (HasBuilder, WoodSufficient, BuildSiteSelected) -> HasMill
class UCk_GoapTest_Action_BuildMill : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBuilder"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.WoodSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.BuildSiteSelected"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasMill"), true);
		SetCost(4.0f);
	}
};

// BuildMiningCamp: (HasBuilder, WoodSufficient, BuildSiteSelected) -> HasMiningCamp
class UCk_GoapTest_Action_BuildMiningCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBuilder"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.WoodSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.BuildSiteSelected"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), true);
		SetCost(4.0f);
	}
};

// BuildBarracks: (HasBuilder, WoodSufficient, StoneSufficient, BuildSiteSelected) -> HasBarracks
class UCk_GoapTest_Action_BuildBarracks : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBuilder"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.WoodSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.StoneSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.BuildSiteSelected"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasBarracks"), true);
		SetCost(6.0f);
	}
};

// ResearchFeudalAge: (HasTownCenter, FoodSufficient, GoldSufficient, HasBarracks) -> AgeAdvancing
class UCk_GoapTest_Action_ResearchFeudalAge : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasTownCenter"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.FoodSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.GoldSufficient"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBarracks"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.AgeAdvancing"), true);
		SetCost(8.0f);
	}
};

// WaitForResearch: (AgeAdvancing) -> ReachedFeudalAge
class UCk_GoapTest_Action_WaitForResearch : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.AgeAdvancing"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.ReachedFeudalAge"), true);
		SetCost(10.0f);
	}
};

// Goals
class UCk_GoapTest_Goal_GatherResources : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.AoE.WoodSufficient"), true);
		AddCondition(goap_tags::T(n"Goap.WS.AoE.FoodSufficient"), true);
		SetPriority(3);
	}
};

class UCk_GoapTest_Goal_BuildMilitary : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.AoE.HasBarracks"), true);
		SetPriority(5);
	}
};

class UCk_GoapTest_Goal_ReachFeudalAge : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.AoE.ReachedFeudalAge"), true);
		SetPriority(10);
	}
};
