// Language=angelscript

//============================================================================
// GOAP GYM — SHARED TAGS + AUTO MESSAGES
//============================================================================
// Declares station/world-state tags used across the gym, plus the message
// structs that PlayerController execs broadcast to each station.
//
// Tags are grouped by station so they read top-to-bottom in increasing
// complexity: Door -> Tea -> Combat -> Priorities -> NoPlan -> Empire.
//============================================================================

namespace Ck
{
	asset GoapGym_Tags of UCk_GameplayTags
	{
		// Station tags (used as station identifiers)
		GameplayTags.Add(n"Gym.Goap.Door");
		GameplayTags.Add(n"Gym.Goap.Tea");
		GameplayTags.Add(n"Gym.Goap.Combat");
		GameplayTags.Add(n"Gym.Goap.Priorities");
		GameplayTags.Add(n"Gym.Goap.NoPlan");
		GameplayTags.Add(n"Gym.Goap.Empire");

		// Station 1: OpenDoor
		GameplayTags.Add(n"Goap.WS.Door.HasKey");
		GameplayTags.Add(n"Goap.WS.Door.Unlocked");

		// Station 2: MakeTea
		GameplayTags.Add(n"Goap.WS.Tea.HasWater");
		GameplayTags.Add(n"Goap.WS.Tea.WaterHot");
		GameplayTags.Add(n"Goap.WS.Tea.TeaSteeped");
		GameplayTags.Add(n"Goap.WS.Tea.TeaReady");

		// Station 3 & 5: Combat / NoPlan (shared)
		GameplayTags.Add(n"Goap.WS.Combat.HasWeapon");
		GameplayTags.Add(n"Goap.WS.Combat.HasAmmo");
		GameplayTags.Add(n"Goap.WS.Combat.EnemyInRange");
		GameplayTags.Add(n"Goap.WS.Combat.EnemyAlive");

		// Station 4: Priorities
		GameplayTags.Add(n"Goap.WS.Pri.UnderFire");
		GameplayTags.Add(n"Goap.WS.Pri.InCover");
		GameplayTags.Add(n"Goap.WS.Pri.IsHungry");
		GameplayTags.Add(n"Goap.WS.Pri.HasFood");
		GameplayTags.Add(n"Goap.WS.Pri.EnemySpotted");
		GameplayTags.Add(n"Goap.WS.Pri.EnemyDown");

		// Station 6: Age of Empires
		GameplayTags.Add(n"Goap.WS.AoE.HasTownCenter");
		GameplayTags.Add(n"Goap.WS.AoE.HasIdleVillager");
		GameplayTags.Add(n"Goap.WS.AoE.HasLumberCamp");
		GameplayTags.Add(n"Goap.WS.AoE.HasMill");
		GameplayTags.Add(n"Goap.WS.AoE.HasMiningCamp");
		GameplayTags.Add(n"Goap.WS.AoE.HasBarracks");
		GameplayTags.Add(n"Goap.WS.AoE.HasBuilder");
		GameplayTags.Add(n"Goap.WS.AoE.BuildSiteSelected");
		GameplayTags.Add(n"Goap.WS.AoE.VillagerNearForest");
		GameplayTags.Add(n"Goap.WS.AoE.VillagerNearBerries");
		GameplayTags.Add(n"Goap.WS.AoE.VillagerNearGold");
		GameplayTags.Add(n"Goap.WS.AoE.VillagerNearStone");
		GameplayTags.Add(n"Goap.WS.AoE.WoodSufficient");
		GameplayTags.Add(n"Goap.WS.AoE.FoodSufficient");
		GameplayTags.Add(n"Goap.WS.AoE.GoldSufficient");
		GameplayTags.Add(n"Goap.WS.AoE.StoneSufficient");
		GameplayTags.Add(n"Goap.WS.AoE.AgeAdvancing");
		GameplayTags.Add(n"Goap.WS.AoE.ReachedFeudalAge");

		// Entity tags used by PlayerController to broadcast per-station commands
		GameplayTags.Add(n"TAG_GoapGym_Door");
		GameplayTags.Add(n"TAG_GoapGym_Tea");
		GameplayTags.Add(n"TAG_GoapGym_Combat");
		GameplayTags.Add(n"TAG_GoapGym_Priorities");
		GameplayTags.Add(n"TAG_GoapGym_NoPlan");
		GameplayTags.Add(n"TAG_GoapGym_Empire");
	}
}

//============================================================================
// PER-STATION MESSAGES (parameterless triggers from PlayerController execs)
//============================================================================
// One empty USTRUCT per exec command. Following the CkInteractionGym pattern
// from CkGym_CreationSpecification.txt §12.
//============================================================================

// Station 1: OpenDoor
USTRUCT() struct FCk_Message_GoapGym_Door_Replan {}
USTRUCT() struct FCk_Message_GoapGym_Door_GiveKey {}
USTRUCT() struct FCk_Message_GoapGym_Door_LoseKey {}
USTRUCT() struct FCk_Message_GoapGym_Door_PreUnlock {}

// Station 2: MakeTea
USTRUCT() struct FCk_Message_GoapGym_Tea_Replan {}
USTRUCT() struct FCk_Message_GoapGym_Tea_FillWater {}
USTRUCT() struct FCk_Message_GoapGym_Tea_BoilWater {}
USTRUCT() struct FCk_Message_GoapGym_Tea_SteepTea {}
USTRUCT() struct FCk_Message_GoapGym_Tea_ResetAll {}

// Station 3: Combat (ranged vs melee w/ dynamic cost)
USTRUCT() struct FCk_Message_GoapGym_Combat_Replan {}
USTRUCT() struct FCk_Message_GoapGym_Combat_MakeMeleeCheap {}
USTRUCT() struct FCk_Message_GoapGym_Combat_MakeMeleeExpensive {}
USTRUCT() struct FCk_Message_GoapGym_Combat_RemoveWeapon {}
USTRUCT() struct FCk_Message_GoapGym_Combat_GiveWeapon {}

// Station 4: Priorities
USTRUCT() struct FCk_Message_GoapGym_Priorities_Replan {}
USTRUCT() struct FCk_Message_GoapGym_Priorities_TakeFire {}
USTRUCT() struct FCk_Message_GoapGym_Priorities_GetHungry {}
USTRUCT() struct FCk_Message_GoapGym_Priorities_SpotEnemy {}
USTRUCT() struct FCk_Message_GoapGym_Priorities_ResetAll {}

// Station 5: NoPlanPossible
USTRUCT() struct FCk_Message_GoapGym_NoPlan_Replan {}

// Station 6: AgeOfEmpires
USTRUCT() struct FCk_Message_GoapGym_Empire_PlanGatherResources {}
USTRUCT() struct FCk_Message_GoapGym_Empire_PlanBuildMilitary {}
USTRUCT() struct FCk_Message_GoapGym_Empire_PlanFeudalAge {}
USTRUCT() struct FCk_Message_GoapGym_Empire_ApplyPlan {}
USTRUCT() struct FCk_Message_GoapGym_Empire_ResetWorld {}
