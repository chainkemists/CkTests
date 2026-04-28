// Language=angelscript

//============================================================================
// GOAP AUTO-REPLAN GYM — spatially-rendered auto-replan demonstration
//============================================================================
// One white "AI" capsule surrounded by 8 red (alive) / gray (dead) enemy
// capsules that drift in and out. The AI does not physically move — it only
// plans. The plan is "MoveTo(enemy) -> Attack(enemy)" with the MoveTo cost
// reflecting the distance tier to the currently-selected target (closest
// alive enemy). A line from AI to target visualizes the current plan.
//
// Every-tick re-targeting + distance-tier-gated cost updates + random
// kill/revive flips feed the new ECk_Goap_ReplanPolicy::OnEitherDirty with
// a 0.25s throttle. No explicit Request_Plan calls from the gym — the
// planner re-fires on dirty flags from Set_WorldStateValue / Set_ActionCost
// value-change detection, demonstrating the full auto-replan pipeline.
//============================================================================

namespace Ck
{
	asset GoapAutoReplan_Tags of UCk_GameplayTags
	{
		GameplayTags.Add(n"Gym.Goap.AutoReplan");
		GameplayTags.Add(n"TAG_GoapGym_AutoReplan");

		// World state keys — single-target model, per design discussion
		GameplayTags.Add(n"Goap.WS.AutoReplan.EnemyInRange");
		GameplayTags.Add(n"Goap.WS.AutoReplan.EnemyAlive");
		GameplayTags.Add(n"Goap.WS.AutoReplan.EnemyDead");
	}
}

namespace goap_auto_replan
{
	FGameplayTag T(FName InName) { return GameplayTags::ResolveGameplayTag(InName); }
}

// Per-station messages
USTRUCT() struct FCk_Message_GoapGym_AutoReplan_Replan {}
USTRUCT() struct FCk_Message_GoapGym_AutoReplan_KillRandom {}
USTRUCT() struct FCk_Message_GoapGym_AutoReplan_ReviveAll {}

//============================================================================
// ACTIONS + GOAL
//============================================================================
// MoveTo: no preconditions, effect EnemyInRange=true. Cost is dynamic (set
// by station based on distance tier — Near/Mid/Far map to 1/3/5).
// Attack:  requires EnemyInRange AND EnemyAlive, effect EnemyDead=true.
// Goal:    EnemyDead=true.
//============================================================================

class UCk_GoapAutoReplan_Action_MoveTo : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddEffect(goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyInRange"), true);
		SetCost(1.0f);
	}
};

class UCk_GoapAutoReplan_Action_Attack : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineAction()
	{
		AddPrecondition(goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyInRange"), true);
		AddPrecondition(goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyAlive"),   true);
		AddEffect      (goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyDead"),    true);
		SetCost(2.0f);
	}
};

class UCk_GoapAutoReplan_Goal_KillTarget : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride)
	void DoDefineGoal()
	{
		AddCondition(goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyDead"), true);
		SetPriority(1);
	}
};

//============================================================================
// ENEMY — trivial: position + alive state. Drifts randomly in/out each tick.
//============================================================================

struct FAutoReplan_Enemy
{
	FVector Center;            // drift origin (AI location)
	FVector Position;          // current world position
	float   Radius = 0.0f;     // current distance from AI
	float   RadiusTarget = 0.0f;
	float   Angle = 0.0f;      // angular position around AI
	bool    IsAlive = true;
	FCk_Handle_Pmg_DebugShape Shape;
}

//============================================================================
// AUTO-REPLAN AI STATION
//============================================================================

class UCk_EntityScript_GoapGym_AutoReplan :  UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer StepTimer;
	FCk_Handle_Pmg_DebugShape AIShape;
	FCk_Handle_Pmg_DebugShape PlanLine;

	TArray<FAutoReplan_Enemy> Enemies;
	int32 CurrentTargetIdx = -1;
	int32 LastCostTier     = -1;       // -1 uninit, 0=near, 1=mid, 2=far
	bool LastTargetInRange = false;
	bool LastTargetAlive   = false;

	float TimeToKillRevive = 3.0f;     // countdown to next kill/revive flip

	int32 PlanCount = 0;

	const int32   ENEMY_COUNT           = 8;
	const float32 AI_CAPSULE_RADIUS     = 30.0f;
	const float32 AI_CAPSULE_HEIGHT     = 80.0f;
	const float32 ENEMY_CAPSULE_RADIUS  = 25.0f;
	const float32 ENEMY_CAPSULE_HEIGHT  = 60.0f;
	const float32 DRIFT_MIN             = 150.0f;
	const float32 DRIFT_MAX             = 600.0f;
	const float32 DRIFT_SPEED           = 80.0f;   // units/sec
	const float32 IN_RANGE_THRESHOLD    = 200.0f;
	const float32 TIER_MID_THRESHOLD    = 350.0f;
	const float32 KILL_REVIVE_PERIOD_MIN = 2.0f;
	const float32 KILL_REVIVE_PERIOD_MAX = 4.5f;
	// Shift the whole "stage" (AI + enemies) in -X so capsule drift at
	// DRIFT_MAX doesn't clip into the station panel behind them.
	const float32 STAGE_OFFSET_X = -500.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_AutoReplan");

		// GOAP entity — auto-replan on either dirty, 0.25s throttle, plan-on-start.
		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnEitherDirty);
		GoapParams.Set_MinReplanIntervalSeconds(0.25f);
		GoapParams.Set_PlanOnStart(true);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_auto_replan::T(n"Gym.Goap.AutoReplan"));
		GoapEntity.AddAction(UCk_GoapAutoReplan_Action_MoveTo);
		GoapEntity.AddAction(UCk_GoapAutoReplan_Action_Attack);
		GoapEntity.AddGoal  (UCk_GoapAutoReplan_Goal_KillTarget);

		GoapEntity.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));

		// Spawn the AI capsule at the station root (persistent, white).
		auto AIPos = InitialTransform.GetLocation() + FVector(STAGE_OFFSET_X, 0.0f, AI_CAPSULE_HEIGHT * 0.5f);
		AIShape = utils_pmg_basic_shapes::DrawFilledCapsule(
			AIPos, AI_CAPSULE_RADIUS, AI_CAPSULE_HEIGHT, 16, 8,
			FLinearColor(1.0f, 1.0f, 1.0f, 0.95f),
			true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

		// Spawn 8 enemies in random radial positions around the AI.
		Enemies.Reserve(ENEMY_COUNT);
		for (int32 i = 0; i < ENEMY_COUNT; i++)
		{
			auto E = FAutoReplan_Enemy();
			E.Center = AIPos;
			E.Angle = (float(i) / float(ENEMY_COUNT)) * 360.0f;
			E.Radius = Math::RandRange(DRIFT_MIN, DRIFT_MAX);
			E.RadiusTarget = Math::RandRange(DRIFT_MIN, DRIFT_MAX);
			E.IsAlive = true;
			E.Position = RadialToWorld(E.Center, E.Angle, E.Radius);
			E.Shape = SpawnEnemyShape(E.Position, E.IsAlive);
			Enemies.Add(E);
		}

		TimeToKillRevive = Math::RandRange(KILL_REVIVE_PERIOD_MIN, KILL_REVIVE_PERIOD_MAX);

		// Step timer: drives movement, target selection, WS/cost updates, redraw.
		auto StepParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		StepParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		StepTimer = utils_timer::Add(InHandle, StepParams);
		StepTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"StepTick"));

		// Manual exec commands.
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_AutoReplan_Replan,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_AutoReplan_KillRandom,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnKillRandom"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_AutoReplan_ReviveAll,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnReviveAll"));

		// Display text panel — disabled while we re-baseline the GymStation.
		// Re-enable with the timer + DisplayTick binding once the station
		// renders correctly with the static spawn-param text.

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	//------------------------------------------------------------------------
	// STEP TICK — move enemies, retarget, update WS/cost, redraw line
	//------------------------------------------------------------------------
	UFUNCTION() private void StepTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto DT = InDeltaT.Get_Seconds();

		DriftEnemies(DT);

		// Kill/revive cycle — flip one enemy every few seconds, keeping >=1 alive.
		TimeToKillRevive -= DT;
		if (TimeToKillRevive <= 0.0f)
		{
			DoRandomKillOrRevive();
			TimeToKillRevive = Math::RandRange(KILL_REVIVE_PERIOD_MIN, KILL_REVIVE_PERIOD_MAX);
		}

		// Pick the closest alive enemy as target. If none alive, clear.
		auto NewTargetIdx = Find_ClosestAliveEnemy();

		if (NewTargetIdx != CurrentTargetIdx)
		{
			CurrentTargetIdx = NewTargetIdx;
			// Force re-evaluation of WS/cost on retarget.
			LastCostTier = -1;
			LastTargetInRange = !LastTargetInRange;
			LastTargetAlive = !LastTargetAlive;
		}

		UpdateWorldState_ForTarget();
		UpdateMoveCost_ForTarget();
		DrawPlanLine();
	}

	private void DriftEnemies(float InDT)
	{
		auto AIPos = utils_transform::Get_EntityCurrentLocation(ck::ToEntity(this))
		           + FVector(STAGE_OFFSET_X, 0.0f, AI_CAPSULE_HEIGHT * 0.5f);

		for (int32 i = 0; i < Enemies.Num(); i++)
		{
			auto E = Enemies[i];
			E.Center = AIPos;

			// Drift radius toward target; when reached, pick a new target.
			auto RadiusDelta = E.RadiusTarget - E.Radius;
			auto Step = DRIFT_SPEED * InDT;
			if (Math::Abs(RadiusDelta) <= Step)
			{
				E.Radius = E.RadiusTarget;
				E.RadiusTarget = Math::RandRange(DRIFT_MIN, DRIFT_MAX);
			}
			else
			{
				E.Radius += (RadiusDelta > 0.0f) ? Step : -Step;
			}

			// Slow angular drift so they don't look static.
			E.Angle += 12.0f * InDT;
			if (E.Angle >= 360.0f) { E.Angle -= 360.0f; }

			E.Position = RadialToWorld(E.Center, E.Angle, E.Radius);
			Enemies[i] = E;

			if (ck::IsValid(E.Shape))
			{
				utils_transform::Request_SetLocation(E.Shape, E.Position, ECk_LocalWorld::World);
			}
		}
	}

	private int32 Find_ClosestAliveEnemy()
	{
		int32 BestIdx = -1;
		float BestDist = 1e9f;
		for (int32 i = 0; i < Enemies.Num(); i++)
		{
			if (!Enemies[i].IsAlive) { continue; }
			if (Enemies[i].Radius < BestDist)
			{
				BestDist = Enemies[i].Radius;
				BestIdx = i;
			}
		}
		return BestIdx;
	}

	// WS updates are value-change gated by Set_WorldStateValue semantics —
	// the SetWorldState request handler only raises the dirty tag when the
	// slot value actually changes. We can therefore Set unconditionally.
	private void UpdateWorldState_ForTarget()
	{
		bool InRange = false;
		bool Alive   = false;

		if (CurrentTargetIdx >= 0 && CurrentTargetIdx < Enemies.Num())
		{
			auto T = Enemies[CurrentTargetIdx];
			InRange = T.Radius <= IN_RANGE_THRESHOLD;
			Alive   = T.IsAlive;
		}

		GoapEntity.Set_WorldStateValue(goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyInRange"), InRange);
		GoapEntity.Set_WorldStateValue(goap_auto_replan::T(n"Goap.WS.AutoReplan.EnemyAlive"),   Alive);

		LastTargetInRange = InRange;
		LastTargetAlive   = Alive;
	}

	private void UpdateMoveCost_ForTarget()
	{
		if (CurrentTargetIdx < 0 || CurrentTargetIdx >= Enemies.Num()) { return; }
		auto T = Enemies[CurrentTargetIdx];

		int32 Tier = 0;
		if      (T.Radius <= IN_RANGE_THRESHOLD) { Tier = 0; }           // Near
		else if (T.Radius <= TIER_MID_THRESHOLD) { Tier = 1; }           // Mid
		else                                     { Tier = 2; }           // Far

		if (Tier == LastCostTier) { return; }
		LastCostTier = Tier;

		float NewCost = 1.0f;
		if      (Tier == 0) { NewCost = 1.0f; }
		else if (Tier == 1) { NewCost = 3.0f; }
		else                { NewCost = 5.0f; }

		GoapEntity.Set_ActionCost(UCk_GoapAutoReplan_Action_MoveTo, NewCost);
	}

	//------------------------------------------------------------------------
	// KILL / REVIVE
	//------------------------------------------------------------------------
	private void DoRandomKillOrRevive()
	{
		auto AliveCount = 0;
		auto DeadCount = 0;
		for (auto E : Enemies) { if (E.IsAlive) { ++AliveCount; } else { ++DeadCount; } }

		// Keep >=1 alive. If only one alive, force a revive.
		bool ShouldKill = false;
		if (AliveCount <= 1)      { ShouldKill = false; }
		else if (DeadCount == 0)  { ShouldKill = true; }
		else                      { ShouldKill = Math::RandRange(0.0f, 1.0f) < 0.65f; }

		int32 Idx = -1;
		if (ShouldKill)
		{
			auto Candidates = TArray<int32>();
			for (int32 i = 0; i < Enemies.Num(); i++) { if (Enemies[i].IsAlive) { Candidates.Add(i); } }
			if (Candidates.Num() > 0) { Idx = Candidates[Math::RandRange(0, Candidates.Num() - 1)]; }
		}
		else
		{
			auto Candidates = TArray<int32>();
			for (int32 i = 0; i < Enemies.Num(); i++) { if (!Enemies[i].IsAlive) { Candidates.Add(i); } }
			if (Candidates.Num() > 0) { Idx = Candidates[Math::RandRange(0, Candidates.Num() - 1)]; }
		}

		if (Idx < 0) { return; }

		SetEnemyAlive(Idx, !ShouldKill);
	}

	private void SetEnemyAlive(int32 InIdx, bool InAlive)
	{
		auto E = Enemies[InIdx];
		E.IsAlive = InAlive;
		if (ck::IsValid(E.Shape)) { utils_entity_lifetime::Request_DestroyEntity(E.Shape); }
		E.Shape = SpawnEnemyShape(E.Position, E.IsAlive);
		Enemies[InIdx] = E;
	}

	private FCk_Handle_Pmg_DebugShape SpawnEnemyShape(FVector InPos, bool InAlive)
	{
		auto Color = InAlive
			? FLinearColor(0.95f, 0.25f, 0.25f, 0.9f)   // red alive
			: FLinearColor(0.35f, 0.35f, 0.35f, 0.7f);  // gray dead
		return utils_pmg_basic_shapes::DrawFilledCapsule(
			InPos, ENEMY_CAPSULE_RADIUS, ENEMY_CAPSULE_HEIGHT, 16, 8,
			Color, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
	}

	//------------------------------------------------------------------------
	// PLAN LINE — short-duration dashed line from AI to current target
	//------------------------------------------------------------------------
	private void DrawPlanLine()
	{
		// Destroy last frame's line first (short-duration would also expire,
		// but explicit cleanup avoids transient flicker from overlap).
		if (ck::IsValid(PlanLine)) { utils_entity_lifetime::Request_DestroyEntity(PlanLine); }

		if (CurrentTargetIdx < 0) { return; }
		if (utils_goap::Get_PlanStatus(GoapEntity) != ECk_GoapPlanStatus::PlanFound) { return; }
		if (utils_goap::Get_Plan(GoapEntity).Num() == 0) { return; }

		auto AIPos = utils_transform::Get_EntityCurrentLocation(ck::ToEntity(this))
		           + FVector(STAGE_OFFSET_X, 0.0f, AI_CAPSULE_HEIGHT * 0.5f);
		auto TargetPos = Enemies[CurrentTargetIdx].Position;

		PlanLine = utils_pmg_directional_shapes::DrawDashedLine(
			AIPos, TargetPos,
			25.0f, 12.0f, 3.0f,
			FLinearColor(1.0f, 0.85f, 0.20f, 0.95f),
			ECk_Plane_Axis::XY, -1.0f);
	}

	//------------------------------------------------------------------------
	// SIGNAL + MESSAGE HANDLERS
	//------------------------------------------------------------------------
	UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
	{
		PlanCount++;
	}

	UFUNCTION() private void OnReplan(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		GoapEntity.Request_Plan();
	}

	UFUNCTION() private void OnKillRandom(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		DoRandomKillOrRevive();
	}

	UFUNCTION() private void OnReviveAll(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		for (int32 i = 0; i < Enemies.Num(); i++)
		{
			if (!Enemies[i].IsAlive) { SetEnemyAlive(i, true); }
		}
	}

	//------------------------------------------------------------------------
	// DISPLAY TICK — text panel
	//------------------------------------------------------------------------
	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);

		auto AliveCount = 0;
		for (auto E : Enemies) { if (E.IsAlive) { ++AliveCount; } }

		auto Status = utils_goap::Get_PlanStatus(GoapEntity);
		auto Plan   = utils_goap::Get_Plan(GoapEntity);
		auto Cost   = utils_goap::Get_PlanCost(GoapEntity);

		auto StatusText = "UNKNOWN";
		if      (Status == ECk_GoapPlanStatus::Idle)                 { StatusText = "IDLE"; }
		else if (Status == ECk_GoapPlanStatus::Planning)             { StatusText = "PLANNING"; }
		else if (Status == ECk_GoapPlanStatus::PlanFound)            { StatusText = "PLAN FOUND"; }
		else if (Status == ECk_GoapPlanStatus::PlanFailed)           { StatusText = "PLAN FAILED"; }
		else if (Status == ECk_GoapPlanStatus::CostThresholdReached) { StatusText = "COST THRESHOLD"; }

		auto TierText = "—";
		if      (LastCostTier == 0) { TierText = "NEAR (cost 1)"; }
		else if (LastCostTier == 1) { TierText = "MID  (cost 3)"; }
		else if (LastCostTier == 2) { TierText = "FAR  (cost 5)"; }

		auto Text = f"===== Auto-Replan Demo =====\n";
		Text = f"{Text}Policy: OnEitherDirty   Throttle: 0.25s\n";
		Text = f"{Text}Enemies alive: {AliveCount}/{Enemies.Num()}   Next flip: {TimeToKillRevive}s\n\n";
		Text = f"{Text}===== Target =====\n";
		if (CurrentTargetIdx < 0)
		{
			Text = f"{Text}<no alive target>\n";
		}
		else
		{
			auto T = Enemies[CurrentTargetIdx];
			Text = f"{Text}Target #{CurrentTargetIdx}   dist={T.Radius}   tier={TierText}\n";
			Text = f"{Text}EnemyInRange={LastTargetInRange}   EnemyAlive={LastTargetAlive}\n";
		}
		Text = f"{Text}\n===== Planner =====\n";
		Text = f"{Text}Status: {StatusText}   Plan #{PlanCount}   Cost: {Cost}\n";
		if (Plan.Num() == 0 && Status == ECk_GoapPlanStatus::PlanFound)
		{
			Text = f"{Text}Plan: <goal already satisfied>\n";
		}
		else
		{
			Text = f"{Text}Plan: {Plan.Num()} step(s)\n";
			for (int32 i = 0; i < Plan.Num(); i++)
			{
				auto ActionName = Plan[i].Get().GetName();
				Text = f"{Text}  {i + 1}. {ActionName}\n";
			}
		}
		Text = f"{Text}\nCommands: AutoReplan_Replan / KillRandom / ReviveAll";

		CkGym_Common::Update_StationDisplay(SelfEntity, "GOAP AUTO-REPLAN", Text, "");
	}

	//------------------------------------------------------------------------
	// HELPERS
	//------------------------------------------------------------------------
	private FVector RadialToWorld(FVector InCenter, float InAngleDeg, float InRadius)
	{
		auto Rad = Math::DegreesToRadians(InAngleDeg);
		return FVector(
			InCenter.X + Math::Cos(Rad) * InRadius,
			InCenter.Y + Math::Sin(Rad) * InRadius,
			InCenter.Z);
	}
};
