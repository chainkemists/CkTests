// ====================================================================================================================
// TEST ACTIONS — Concrete GOAP action definitions for gym scenarios
// ====================================================================================================================

// --- PickUpWeapon: () -> HasWeapon=true ---
class UCk_GoapTest_Action_PickUpWeapon : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasWeapon"), true);
		SetCost(2.0f);
	}
};

// --- LoadAmmo: (HasWeapon=true) -> HasAmmo=true ---
class UCk_GoapTest_Action_LoadAmmo : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasWeapon"), true);
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasAmmo"), true);
		SetCost(1.0f);
	}
};

// --- Scout: () -> EnemyVisible=true ---
class UCk_GoapTest_Action_Scout : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyVisible"), true);
		SetCost(3.0f);
	}
};

// --- Approach: (EnemyVisible=true) -> EnemyInRange=true ---
class UCk_GoapTest_Action_Approach : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyVisible"), true);
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyInRange"), true);
		SetCost(2.0f);
	}
};

// --- Attack: (HasWeapon=true, HasAmmo=true, EnemyInRange=true) -> EnemyAlive=false ---
class UCk_GoapTest_Action_Attack : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasWeapon"), true);
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasAmmo"), true);
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyInRange"), true);
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyAlive"), false);
		SetCost(4.0f);
	}
};

// --- MeleeAttack: (HasWeapon=true, EnemyInRange=true) -> EnemyAlive=false ---
// Cheaper alternative to Attack when ammo isn't needed
class UCk_GoapTest_Action_MeleeAttack : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasWeapon"), true);
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyInRange"), true);
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyAlive"), false);
		SetCost(6.0f);
	}
};

// --- TakeCover: () -> InCover=true ---
class UCk_GoapTest_Action_TakeCover : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.InCover"), true);
		SetCost(1.0f);
	}
};

// --- SecureArea: (EnemyAlive=false, InCover=true) -> AreaSafe=true ---
class UCk_GoapTest_Action_SecureArea : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyAlive"), false);
		AddPrecondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.InCover"), true);
		AddEffect(GameplayTags::ResolveGameplayTag(n"Goap.WS.AreaSafe"), true);
		SetCost(2.0f);
	}
};

// ====================================================================================================================
// TEST GOALS
// ====================================================================================================================

// --- Kill Enemy: EnemyAlive=false ---
class UCk_GoapTest_Goal_KillEnemy : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.EnemyAlive"), false);
		SetPriority(10);
	}
};

// --- Secure Area: AreaSafe=true ---
class UCk_GoapTest_Goal_SecureArea : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.AreaSafe"), true);
		SetPriority(5);
	}
};

// --- Arm Up: HasWeapon=true, HasAmmo=true ---
class UCk_GoapTest_Goal_ArmUp : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasWeapon"), true);
		AddCondition(GameplayTags::ResolveGameplayTag(n"Goap.WS.HasAmmo"), true);
		SetPriority(3);
	}
};
