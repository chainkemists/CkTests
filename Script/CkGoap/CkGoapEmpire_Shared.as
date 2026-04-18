// Language=angelscript

//============================================================================
// GOAP EMPIRE GYM — SHARED TAGS, LAYOUT, TIMING
//============================================================================
//
// Single-station boolean GOAP stress test: an AoE-inspired economy where
// one villager plays out a complex multi-age tech tree, with numeric
// resources driven by gameplay code and projected down to boolean flags
// the planner reads.
//
// Two flag families:
//
//   GOAP-effect flags — set by the planner executing an action's effect.
//   Examples: Age flags, building flags, research flags, training flags.
//   Gameplay may also flip these when a plan step completes (e.g. research
//   takes time, flag flips on completion).
//
//   Gameplay-read flags — set ONLY by the gameplay layer projecting
//   numeric resource thresholds (Wood, Food, Gold, Stone, Population) down
//   to booleans. The planner reads these as preconditions but never sets
//   them as effects. This preserves the invariant that numeric reality
//   lives outside the planner's closed-world belief model.
//============================================================================

namespace Ck
{
	asset GoapEmpire_Tags of UCk_GameplayTags
	{
		// Station identity
		GameplayTags.Add(n"Gym.GoapEmpire.Station");
		GameplayTags.Add(n"TAG_GoapEmpireGym_Station");

		// Ages — progressive unlocks
		GameplayTags.Add(n"Goap.WS.Empire.IsInDarkAge");
		GameplayTags.Add(n"Goap.WS.Empire.IsInFeudalAge");
		GameplayTags.Add(n"Goap.WS.Empire.IsInCastleAge");
		GameplayTags.Add(n"Goap.WS.Empire.IsInImperialAge");

		// Buildings — each set by its BuildXxx action
		GameplayTags.Add(n"Goap.WS.Empire.HasHouse");
		GameplayTags.Add(n"Goap.WS.Empire.HasLumberCamp");
		GameplayTags.Add(n"Goap.WS.Empire.HasMill");
		GameplayTags.Add(n"Goap.WS.Empire.HasMiningCamp");
		GameplayTags.Add(n"Goap.WS.Empire.HasFarm");
		GameplayTags.Add(n"Goap.WS.Empire.HasDock");
		GameplayTags.Add(n"Goap.WS.Empire.HasMarket");
		GameplayTags.Add(n"Goap.WS.Empire.HasBarracks");
		GameplayTags.Add(n"Goap.WS.Empire.HasArchery");
		GameplayTags.Add(n"Goap.WS.Empire.HasStable");
		GameplayTags.Add(n"Goap.WS.Empire.HasBlacksmith");
		GameplayTags.Add(n"Goap.WS.Empire.HasMonastery");
		GameplayTags.Add(n"Goap.WS.Empire.HasUniversity");
		GameplayTags.Add(n"Goap.WS.Empire.HasSiegeWorkshop");
		GameplayTags.Add(n"Goap.WS.Empire.HasCastle");
		GameplayTags.Add(n"Goap.WS.Empire.HasWonder");

		// Research / tech — each set by its Research action
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedLoom");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedWheelbarrow");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedHandCart");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedGoldMining");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedStoneMining");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedCrossbow");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedFletching");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedHusbandry");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedBloodlines");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedEliteSkirmisher");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedChemistry");
		GameplayTags.Add(n"Goap.WS.Empire.HasResearchedBallistics");

		// Army / military composition
		GameplayTags.Add(n"Goap.WS.Empire.HasArmyLight");
		GameplayTags.Add(n"Goap.WS.Empire.HasArmyHeavy");
		GameplayTags.Add(n"Goap.WS.Empire.HasArmyRanged");
		GameplayTags.Add(n"Goap.WS.Empire.HasArmyCavalry");
		GameplayTags.Add(n"Goap.WS.Empire.HasArmySiege");

		// Villagers (boolean — "we have enough villagers", projected from count)
		GameplayTags.Add(n"Goap.WS.Empire.HasEnoughVillagers");

		// Gameplay-driven resource flags — set ONLY by the gameplay layer
		// monitoring the underlying numeric stockpile / pop headroom.
		GameplayTags.Add(n"Goap.WS.Empire.HasEnoughWood");
		GameplayTags.Add(n"Goap.WS.Empire.HasEnoughFood");
		GameplayTags.Add(n"Goap.WS.Empire.HasEnoughGold");
		GameplayTags.Add(n"Goap.WS.Empire.HasEnoughStone");
		GameplayTags.Add(n"Goap.WS.Empire.HasFreePopulation");
	}
}

//============================================================================
// SHARED CONSTANT NAMESPACES (referenced by actions + gameplay)
//============================================================================

namespace empire_tags
{
	// Ages
	const FName IsInDarkAge     = n"Goap.WS.Empire.IsInDarkAge";
	const FName IsInFeudalAge   = n"Goap.WS.Empire.IsInFeudalAge";
	const FName IsInCastleAge   = n"Goap.WS.Empire.IsInCastleAge";
	const FName IsInImperialAge = n"Goap.WS.Empire.IsInImperialAge";

	// Buildings
	const FName HasHouse         = n"Goap.WS.Empire.HasHouse";
	const FName HasLumberCamp    = n"Goap.WS.Empire.HasLumberCamp";
	const FName HasMill          = n"Goap.WS.Empire.HasMill";
	const FName HasMiningCamp    = n"Goap.WS.Empire.HasMiningCamp";
	const FName HasFarm          = n"Goap.WS.Empire.HasFarm";
	const FName HasDock          = n"Goap.WS.Empire.HasDock";
	const FName HasMarket        = n"Goap.WS.Empire.HasMarket";
	const FName HasBarracks      = n"Goap.WS.Empire.HasBarracks";
	const FName HasArchery       = n"Goap.WS.Empire.HasArchery";
	const FName HasStable        = n"Goap.WS.Empire.HasStable";
	const FName HasBlacksmith    = n"Goap.WS.Empire.HasBlacksmith";
	const FName HasMonastery     = n"Goap.WS.Empire.HasMonastery";
	const FName HasUniversity    = n"Goap.WS.Empire.HasUniversity";
	const FName HasSiegeWorkshop = n"Goap.WS.Empire.HasSiegeWorkshop";
	const FName HasCastle        = n"Goap.WS.Empire.HasCastle";
	const FName HasWonder        = n"Goap.WS.Empire.HasWonder";

	// Research
	const FName HasResearchedLoom             = n"Goap.WS.Empire.HasResearchedLoom";
	const FName HasResearchedWheelbarrow      = n"Goap.WS.Empire.HasResearchedWheelbarrow";
	const FName HasResearchedHandCart         = n"Goap.WS.Empire.HasResearchedHandCart";
	const FName HasResearchedGoldMining       = n"Goap.WS.Empire.HasResearchedGoldMining";
	const FName HasResearchedStoneMining      = n"Goap.WS.Empire.HasResearchedStoneMining";
	const FName HasResearchedCrossbow         = n"Goap.WS.Empire.HasResearchedCrossbow";
	const FName HasResearchedFletching        = n"Goap.WS.Empire.HasResearchedFletching";
	const FName HasResearchedHusbandry        = n"Goap.WS.Empire.HasResearchedHusbandry";
	const FName HasResearchedBloodlines       = n"Goap.WS.Empire.HasResearchedBloodlines";
	const FName HasResearchedEliteSkirmisher  = n"Goap.WS.Empire.HasResearchedEliteSkirmisher";
	const FName HasResearchedChemistry        = n"Goap.WS.Empire.HasResearchedChemistry";
	const FName HasResearchedBallistics       = n"Goap.WS.Empire.HasResearchedBallistics";

	// Army / military
	const FName HasArmyLight    = n"Goap.WS.Empire.HasArmyLight";
	const FName HasArmyHeavy    = n"Goap.WS.Empire.HasArmyHeavy";
	const FName HasArmyRanged   = n"Goap.WS.Empire.HasArmyRanged";
	const FName HasArmyCavalry  = n"Goap.WS.Empire.HasArmyCavalry";
	const FName HasArmySiege    = n"Goap.WS.Empire.HasArmySiege";

	// Population
	const FName HasEnoughVillagers  = n"Goap.WS.Empire.HasEnoughVillagers";
	const FName HasFreePopulation   = n"Goap.WS.Empire.HasFreePopulation";

	// Gameplay-read resource flags
	const FName HasEnoughWood  = n"Goap.WS.Empire.HasEnoughWood";
	const FName HasEnoughFood  = n"Goap.WS.Empire.HasEnoughFood";
	const FName HasEnoughGold  = n"Goap.WS.Empire.HasEnoughGold";
	const FName HasEnoughStone = n"Goap.WS.Empire.HasEnoughStone";
}

//============================================================================
// LAYOUT CONSTANTS — hardcoded per-location world positions
//============================================================================
// Centered on origin. The villager moves between these; buildings appear
// in an arc around the town center as their BuildXxx action fires.

namespace empire_layout
{
	// Resource nodes
	FVector TownCenter()  { return FVector(   0.0,    0.0, 50.0); }
	FVector Forest()      { return FVector( 800.0,    0.0, 50.0); }
	FVector GoldMine()    { return FVector(-800.0,    0.0, 50.0); }
	FVector StoneQuarry() { return FVector(   0.0,  800.0, 50.0); }
	FVector FarmField()   { return FVector(   0.0, -800.0, 50.0); }

	// Building slots — arranged on a radius around TownCenter
	//    index 0 .. N   |  location
	//      0 (E)         — reserved for Dock
	//      1 (SE)        — Barracks
	//      2 (S)         — Archery
	//      3 (SW)        — Stable
	//      4 (W)         — Blacksmith
	//      5 (NW)        — Market
	//      6 (N)         — Mill
	//      7 (NE)        — Monastery / University / SiegeWorkshop / Castle / Wonder (reassign as ages advance)
	// Dual-uses are fine — each building is a single physical shape at one slot.
	FVector BuildingSlot(int32 InSlotIndex)
	{
		const float32 RadiansPerSlot = float32(6.283185307 / 8.0);  // 2π / 8
		const float32 Angle = float32(InSlotIndex) * RadiansPerSlot;
		const float32 Radius = 400.0f;
		return FVector(Math::Cos(Angle) * Radius, Math::Sin(Angle) * Radius, 50.0f);
	}
}

//============================================================================
// GAMEPLAY TIMING / THRESHOLDS
//============================================================================

namespace empire_tuning
{
	// Villager movement speed (units per second)
	const float32 VillagerSpeed = 600.0f;

	// Work durations (seconds at the target location)
	const float32 WorkGatherWood     = 2.5f;
	const float32 WorkGatherFood     = 2.5f;
	const float32 WorkGatherGold     = 3.0f;
	const float32 WorkGatherStone    = 3.0f;
	const float32 WorkBuild          = 3.0f;
	const float32 WorkResearch       = 3.0f;
	const float32 WorkTrainUnit      = 2.0f;
	const float32 WorkAdvanceAge     = 5.0f;

	// Per-work-cycle resource yields (added when a gather work completes)
	const int32 YieldWood  = 40;
	const int32 YieldFood  = 40;
	const int32 YieldGold  = 30;
	const int32 YieldStone = 30;

	// Resource thresholds — at or above → HasEnoughX true
	const int32 ThresholdWood  = 50;
	const int32 ThresholdFood  = 50;
	const int32 ThresholdGold  = 30;
	const int32 ThresholdStone = 30;

	// Build / research / train costs (decremented on completion)
	const int32 CostHouseWood           = 30;
	const int32 CostLumberCampWood      = 100;
	const int32 CostMillWood            = 100;
	const int32 CostMiningCampWood      = 100;
	const int32 CostFarmWood            = 60;
	const int32 CostDockWood            = 150;
	const int32 CostMarketWood          = 175;
	const int32 CostBarracksWood        = 175;
	const int32 CostArcheryWood         = 175;
	const int32 CostStableWood          = 175;
	const int32 CostBlacksmithWood      = 150;
	const int32 CostMonasteryWood       = 175;
	const int32 CostUniversityWood      = 200;
	const int32 CostUniversityStone     = 100;
	const int32 CostSiegeWorkshopWood   = 200;
	const int32 CostCastleStone         = 650;
	const int32 CostWonderWood          = 500;
	const int32 CostWonderStone         = 500;
	const int32 CostWonderGold          = 500;

	const int32 CostResearchFood = 50;
	const int32 CostResearchGold = 30;
	const int32 CostTrainUnitFood = 50;
	const int32 CostTrainUnitGold = 30;
	const int32 CostTrainVillagerFood = 50;

	const int32 CostAdvanceFeudalFood     = 500;
	const int32 CostAdvanceCastleFood     = 800;
	const int32 CostAdvanceCastleGold     = 200;
	const int32 CostAdvanceImperialFood   = 1000;
	const int32 CostAdvanceImperialGold   = 800;

	// Population
	const int32 InitialPopCap      = 5;
	const int32 InitialVillagers   = 3;
	const int32 PopPerHouse        = 5;
	const int32 EnoughVillagersThreshold = 8;   // HasEnoughVillagers flips true at this count
}

//============================================================================
// MESSAGE STRUCTS (ticks / commands from gameplay layer)
//============================================================================

USTRUCT() struct FCk_Message_GoapEmpire_ResetWorld {}
