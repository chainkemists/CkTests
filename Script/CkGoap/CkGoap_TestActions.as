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
// STATION 6 — CIRCULAR DEPENDENCY (intentional — exercises the cycle detector)
//============================================================================
// Chicken-and-egg graph: charging the device requires a battery; charging the
// battery requires power. Neither can bootstrap from empty state, so the
// framework must flag the cycle and the planner must fail cleanly.

class UCk_GoapTest_Action_ChargeDevice : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Cycle.HasBattery"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Cycle.HasPower"), true);
		SetCost(1.0f);
	}
};

class UCk_GoapTest_Action_ChargeBattery : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.Cycle.HasPower"), true);
		AddEffect(goap_tags::T(n"Goap.WS.Cycle.HasBattery"), true);
		SetCost(1.0f);
	}
};

class UCk_GoapTest_Goal_HasPower : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.Cycle.HasPower"), true);
		SetPriority(1);
	}
};

//============================================================================
// STATION 7 — AGE OF EMPIRES (single-villager realistic economy)
//============================================================================
//
// Resources are CONSUMABLE — builds spend wood, research spends food + gold.
// This is an intentional production/consumption economy. The action graph
// contains loops (GatherWood produces HasWood; BuildLumberCamp consumes it;
// GatherWoodFromCamp requires HasLumberCamp and also produces HasWood),
// but those loops have an ESCAPE from the initial world state: GatherWood
// requires only HasVillager=true (plus !HasWood, which is the initial
// value), so the cycle is seedable and therefore reachable.
//
// The framework's cycle detector should recognize this and NOT flag these
// loops — an action whose preconditions are all satisfied by the initial
// world state provides the escape.
//
// Design invariants:
//   - Every GatherX carries !HasX so the planner never schedules a
//     redundant gather when the resource is already held.
//   - Every BuildX / ResearchX carries !<result> so each one-shot fires
//     at most once per world-cycle.
//   - Plain vs FromCamp variants give the planner a cost-based choice;
//     per-tick distance costs decide which variant wins right now.

// GatherWood: (HasVillager, !HasWood) -> HasWood  [slow, always available]
class UCk_GoapTest_Action_GatherWood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasWood"),     false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasWood"), true);
		SetCost(8.0f);
	}
};

// GatherWoodFromCamp: (HasVillager, HasLumberCamp, !HasWood) -> HasWood  [fast]
class UCk_GoapTest_Action_GatherWoodFromCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"),   true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasLumberCamp"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasWood"),       false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasWood"), true);
		SetCost(3.0f);
	}
};

// GatherFood: (HasVillager, !HasFood) -> HasFood  [slow, always available]
class UCk_GoapTest_Action_GatherFood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasFood"),     false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasFood"), true);
		SetCost(8.0f);
	}
};

// GatherFoodFromMill: (HasVillager, HasMill, !HasFood) -> HasFood  [fast]
class UCk_GoapTest_Action_GatherFoodFromMill : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMill"),     true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasFood"),     false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasFood"), true);
		SetCost(3.0f);
	}
};

// GatherStone: (HasVillager, HasMiningCamp, !HasStone) -> HasStone
// Stone and gold have no slow variant — they're gated behind the mining camp
// so the planner has to build it first, creating a non-trivial dependency.
class UCk_GoapTest_Action_GatherStone : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"),   true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasStone"),      false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasStone"), true);
		SetCost(5.0f);
	}
};

// GatherGold: (HasVillager, HasMiningCamp, !HasGold) -> HasGold
class UCk_GoapTest_Action_GatherGold : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"),   true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasGold"),       false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasGold"), true);
		SetCost(5.0f);
	}
};

// BuildLumberCamp: (HasVillager, HasWood, !HasLumberCamp) -> HasLumberCamp, !HasWood
class UCk_GoapTest_Action_BuildLumberCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"),   true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasWood"),       true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasLumberCamp"), false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasLumberCamp"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasWood"),       false);
		SetCost(4.0f);
	}
};

// BuildMill: (HasVillager, HasWood, !HasMill) -> HasMill, !HasWood
class UCk_GoapTest_Action_BuildMill : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasWood"),     true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMill"),     false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasMill"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasWood"), false);
		SetCost(4.0f);
	}
};

// BuildMiningCamp: (HasVillager, HasWood, !HasMiningCamp) -> HasMiningCamp, !HasWood
class UCk_GoapTest_Action_BuildMiningCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"),   true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasWood"),       true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasMiningCamp"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasWood"),       false);
		SetCost(4.0f);
	}
};

// BuildBarracks: (HasVillager, HasWood, HasStone, !HasBarracks) -> HasBarracks, !HasWood, !HasStone
class UCk_GoapTest_Action_BuildBarracks : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasVillager"), true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasWood"),     true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasStone"),    true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBarracks"), false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasBarracks"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasWood"),     false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasStone"),    false);
		SetCost(5.0f);
	}
};

// ResearchFeudalAge: (TC, HasFood, HasGold, HasBarracks, !ReachedFeudalAge)
//     -> ReachedFeudalAge, !HasFood, !HasGold  (research consumes food + gold)
class UCk_GoapTest_Action_ResearchFeudalAge : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasTownCenter"),    true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasFood"),          true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasGold"),          true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.HasBarracks"),      true);
		AddPrecondition(goap_tags::T(n"Goap.WS.AoE.ReachedFeudalAge"), false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.ReachedFeudalAge"), true);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasFood"),          false);
		AddEffect(goap_tags::T(n"Goap.WS.AoE.HasGold"),          false);
		SetCost(10.0f);
	}
};

// ================================================================================================================
// GOALS
// ================================================================================================================

// GatherResources: HasWood + HasFood (warm-up goal, priority 3)
class UCk_GoapTest_Goal_GatherResources : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.AoE.HasWood"), true);
		AddCondition(goap_tags::T(n"Goap.WS.AoE.HasFood"), true);
		SetPriority(3);
	}
};

// BuildMilitary: HasBarracks (priority 5)
class UCk_GoapTest_Goal_BuildMilitary : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.AoE.HasBarracks"), true);
		SetPriority(5);
	}
};

// ReachFeudalAge: ReachedFeudalAge (priority 10)
class UCk_GoapTest_Goal_ReachFeudalAge : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_tags::T(n"Goap.WS.AoE.ReachedFeudalAge"), true);
		SetPriority(10);
	}
};
