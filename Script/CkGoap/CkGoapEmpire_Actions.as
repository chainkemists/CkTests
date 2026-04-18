// Language=angelscript

//============================================================================
// GOAP EMPIRE — ACTIONS AND GOALS
//============================================================================
// All action/goal EntityScript classes for the Empire gym. Grouped by tech
// category for readability. Every action:
//
//   * Reads `HasEnoughX` resource flags as preconditions (NEVER as effects
//     — gameplay owns resource numerics)
//   * Sets building / research / training / age flags as effects
//   * Declares a cost the planner uses to pick the cheapest reachable path
//
// Costs are tuned so that:
//   - "Efficient" gather variants (FromCamp / FromMill / FromFarm) are
//     cheaper than their raw counterparts, giving the planner a reason
//     to invest in economy buildings before spamming raw gathers.
//   - Age advance actions sit at higher cost than the supporting buildings
//     so the plan naturally threads through tech requirements.
//============================================================================

namespace goapempire_tags
{
	FGameplayTag T(FName InName) { return GameplayTags::ResolveGameplayTag(InName); }
}

//----------------------------------------------------------------------------
// RESOURCE GATHERING — raw + efficient variants
//----------------------------------------------------------------------------

class UCk_Empire_Action_GatherWood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_GatherWoodFromCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasLumberCamp), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughWood), true);
		SetCost(1.0f);
	}
};

class UCk_Empire_Action_GatherFood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(goapempire_tags::T(empire_tags::HasEnoughFood), true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_GatherFoodFromFarm : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasFarm),        true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughFood),  true);
		SetCost(1.0f);
	}
};

class UCk_Empire_Action_GatherFoodFromMill : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMill),        true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughFood),  true);
		SetCost(2.0f);
	}
};

class UCk_Empire_Action_GatherGold : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(goapempire_tags::T(empire_tags::HasEnoughGold), true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_GatherGoldFromCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMiningCamp),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughGold),  true);
		SetCost(1.0f);
	}
};

class UCk_Empire_Action_GatherStone : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(goapempire_tags::T(empire_tags::HasEnoughStone), true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_GatherStoneFromCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMiningCamp),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughStone), true);
		SetCost(1.0f);
	}
};

//----------------------------------------------------------------------------
// POPULATION
//----------------------------------------------------------------------------

class UCk_Empire_Action_BuildHouse : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood),      true);
		AddEffect      (goapempire_tags::T(empire_tags::HasHouse),           true);
		AddEffect      (goapempire_tags::T(empire_tags::HasFreePopulation),  true);
		SetCost(2.0f);
	}
};

class UCk_Empire_Action_TrainVillager : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),      true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughVillagers), true);
		SetCost(2.0f);
	}
};

//----------------------------------------------------------------------------
// ECONOMY BUILDINGS
//----------------------------------------------------------------------------

class UCk_Empire_Action_BuildLumberCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasLumberCamp), true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_BuildMill : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasMill),       true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_BuildMiningCamp : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasMiningCamp), true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_BuildFarm : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasMill),       true);
		AddEffect      (goapempire_tags::T(empire_tags::HasFarm),       true);
		SetCost(2.0f);
	}
};

class UCk_Empire_Action_BuildDock : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasDock),       true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_BuildMarket : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasMarket),      true);
		SetCost(4.0f);
	}
};

//----------------------------------------------------------------------------
// MILITARY BUILDINGS
//----------------------------------------------------------------------------

class UCk_Empire_Action_BuildBarracks : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasBarracks),   true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_BuildArchery : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasBarracks),   true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArchery),    true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_BuildStable : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasBarracks),   true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasStable),     true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_BuildBlacksmith : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasBlacksmith),  true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_BuildMonastery : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood), true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasMonastery),  true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_BuildUniversity : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughStone), true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasUniversity),  true);
		SetCost(5.0f);
	}
};

class UCk_Empire_Action_BuildSiegeWorkshop : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood),     true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),     true);
		AddEffect      (goapempire_tags::T(empire_tags::HasSiegeWorkshop),  true);
		SetCost(5.0f);
	}
};

class UCk_Empire_Action_BuildCastle : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughStone), true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasCastle),      true);
		SetCost(6.0f);
	}
};

class UCk_Empire_Action_BuildWonder : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughWood),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughStone),   true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInImperialAge),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasWonder),        true);
		SetCost(10.0f);
	}
};

//----------------------------------------------------------------------------
// AGE ADVANCES
//----------------------------------------------------------------------------
// Pure additive flags — once advanced, lower-age flag stays true too, so
// any action conditioned on `IsInDarkAge=true` still works in Feudal.
// Prevents "regress age" conflicts that additive-set-to-false effects
// would create in the planner's constraint-set dedup.

class UCk_Empire_Action_AdvanceToFeudalAge : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::IsInDarkAge),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasBarracks),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),  true);
		AddEffect      (goapempire_tags::T(empire_tags::IsInFeudalAge),  true);
		SetCost(6.0f);
	}
};

class UCk_Empire_Action_AdvanceToCastleAge : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasBlacksmith),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),  true);
		AddEffect      (goapempire_tags::T(empire_tags::IsInCastleAge),  true);
		SetCost(8.0f);
	}
};

class UCk_Empire_Action_AdvanceToImperialAge : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasUniversity),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),    true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),    true);
		AddEffect      (goapempire_tags::T(empire_tags::IsInImperialAge),  true);
		SetCost(10.0f);
	}
};

//----------------------------------------------------------------------------
// RESEARCH
//----------------------------------------------------------------------------

class UCk_Empire_Action_ResearchLoom : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),       true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedLoom),   true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_ResearchWheelbarrow : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMill),                    true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),              true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),              true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),              true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedWheelbarrow),   true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_ResearchHandCart : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasResearchedWheelbarrow),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),             true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),             true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),             true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedHandCart),     true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_ResearchGoldMining : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMiningCamp),             true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),             true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),             true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedGoldMining),   true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_ResearchStoneMining : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMiningCamp),              true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),              true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),              true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedStoneMining),   true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_ResearchCrossbow : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasArchery),             true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),          true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),          true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),          true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedCrossbow),  true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_ResearchFletching : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasBlacksmith),           true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),           true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),           true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),           true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedFletching),  true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_ResearchHusbandry : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasStable),               true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),           true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),           true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedHusbandry),  true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_ResearchBloodlines : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasStable),                true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),            true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedBloodlines),  true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_ResearchEliteSkirmisher : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasResearchedCrossbow),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),                true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),                true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),                true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedEliteSkirmisher), true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_ResearchChemistry : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasUniversity),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInImperialAge),          true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),            true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedChemistry),   true);
		SetCost(5.0f);
	}
};

class UCk_Empire_Action_ResearchBallistics : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasUniversity),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),            true);
		AddEffect      (goapempire_tags::T(empire_tags::HasResearchedBallistics),  true);
		SetCost(4.0f);
	}
};

//----------------------------------------------------------------------------
// TRADE (market-enabled shortcut to convert gold → food)
//----------------------------------------------------------------------------

class UCk_Empire_Action_TradeForFood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMarket),      true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),  true);
		AddEffect      (goapempire_tags::T(empire_tags::HasEnoughFood),  true);
		SetCost(2.0f);
	}
};

//----------------------------------------------------------------------------
// UNIT TRAINING — army composition
//----------------------------------------------------------------------------

class UCk_Empire_Action_TrainMilitia : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasBarracks),          true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),    true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmyLight),         true);
		SetCost(2.0f);
	}
};

class UCk_Empire_Action_TrainSpearman : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasBarracks),       true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),     true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),     true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation), true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmyLight),      true);
		SetCost(2.0f);
	}
};

class UCk_Empire_Action_TrainArcher : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasArchery),           true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInFeudalAge),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),    true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmyRanged),        true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_TrainKnight : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasStable),                true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasResearchedBloodlines),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),        true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmyCavalry),           true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmyHeavy),             true);
		SetCost(4.0f);
	}
};

class UCk_Empire_Action_TrainMonk : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasMonastery),         true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),    true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmyHeavy),         true);
		SetCost(3.0f);
	}
};

class UCk_Empire_Action_TrainSiegeRam : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasSiegeWorkshop),     true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInCastleAge),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),        true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),    true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmySiege),         true);
		SetCost(5.0f);
	}
};

class UCk_Empire_Action_TrainTrebuchet : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(goapempire_tags::T(empire_tags::HasCastle),                true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasResearchedBallistics),  true);
		AddPrecondition(goapempire_tags::T(empire_tags::IsInImperialAge),          true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughFood),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasEnoughGold),            true);
		AddPrecondition(goapempire_tags::T(empire_tags::HasFreePopulation),        true);
		AddEffect      (goapempire_tags::T(empire_tags::HasArmySiege),             true);
		SetCost(6.0f);
	}
};

//============================================================================
// GOALS (progressive — planner picks highest-priority unsatisfied)
//============================================================================

class UCk_Empire_Goal_ReachFeudalAge : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(goapempire_tags::T(empire_tags::IsInFeudalAge), true);
		SetPriority(10);
	}
};

class UCk_Empire_Goal_ReachCastleAge : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(goapempire_tags::T(empire_tags::IsInCastleAge), true);
		SetPriority(8);
	}
};

class UCk_Empire_Goal_ReachImperialAge : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(goapempire_tags::T(empire_tags::IsInImperialAge), true);
		SetPriority(6);
	}
};

class UCk_Empire_Goal_BuildWonder : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(goapempire_tags::T(empire_tags::HasWonder), true);
		SetPriority(4);
	}
};
