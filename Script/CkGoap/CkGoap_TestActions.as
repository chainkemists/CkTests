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
