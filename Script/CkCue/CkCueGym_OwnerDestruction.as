//============================================================================
// CUE GYM - OWNER DESTRUCTION STATION
// Tests: Cues automatically destroyed when owning entity is destroyed
//============================================================================

class UCk_EntityScript_CueGym_OwnerDestruction : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	int32 CycleCount = 0;
	bool OwnerAlive = false;
	int32 CuesSpawned = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_OwnerDestruction");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Cycle timer: 7 seconds (5s alive + 2s pause before next cycle)
		auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(7.0f));
		CycleParams.Set_StartingState(ECk_Timer_State::Running);
		CycleParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
		CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleTick"));

		// Destroy timer: 5s after spawn, destroy the owner
		auto DestroyParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
		DestroyParams.Set_StartingState(ECk_Timer_State::Paused);
		DestroyParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		auto DestroyTimer = utils_timer::Add(InHandle, DestroyParams);
		DestroyTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDestroyOwner"));

		// Start the first cycle
		Request_SpawnOwnerAndCues();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnCycleTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CycleCount++;
		Request_SpawnOwnerAndCues();
	}

	UFUNCTION()
	private void OnDestroyOwner(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		// Destroy the owner entity - its cues will automatically be destroyed too
		auto SelfEntity = ck::ToEntity(this);
		auto Owners = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_DestructionOwner");
		for (auto Entity : Owners)
		{
			utils_entity_lifetime::Request_DestroyEntity(Entity);
		}
		OwnerAlive = false;
		ck::Trace("CueGym: Owner destroyed - all attached cues should vanish");
	}

	void Request_SpawnOwnerAndCues()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto BaseLocation = InitialTransform.GetLocation();

		// Spawn a visible owner entity
		auto OwnerTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, 0.0f, 0.0f), FVector(1.0f));
		auto SpawnParams = FCk_Gym_TransformSpawnParams(OwnerTransform);
		utils_entity_script::Request_SpawnEntity(
			SelfEntity, UCk_EntityScript_CueGym_DestructionOwner, FInstancedStruct::Make(SpawnParams));
		OwnerAlive = true;

		// Wait a frame for the owner to be constructed, then fire cues
		// Use a very short timer to defer cue execution
		auto DeferParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.1f));
		DeferParams.Set_StartingState(ECk_Timer_State::Running);
		DeferParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		auto DeferTimer = utils_timer::Add(SelfEntity, DeferParams);
		DeferTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDeferredSpawnCues"));
	}

	UFUNCTION()
	private void OnDeferredSpawnCues(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto BaseLocation = InitialTransform.GetLocation();

		// Find the owner entity
		auto Owners = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_DestructionOwner");
		if (Owners.Num() == 0)
		{
			return;
		}
		auto OwnerHandle = Owners[0];

		// Fire 3 persistent cues owned by that entity, at different positions around it
		auto CueTag = GameplayTags::ResolveGameplayTag(n"CueGym.OwnerDestruction.Attached");

		auto Cue1Transform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, -80.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue(OwnerHandle, CueTag, FCkCueGym_SpawnParams(Cue1Transform),
			ECk_Cue_ReliabilityPolicy::Unreliable, ECk_Cue_MulticastPolicy::LocalOnly);

		auto Cue2Transform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, 80.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue(OwnerHandle, CueTag, FCkCueGym_SpawnParams(Cue2Transform),
			ECk_Cue_ReliabilityPolicy::Unreliable, ECk_Cue_MulticastPolicy::LocalOnly);

		auto Cue3Transform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-200.0f, 0.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue(OwnerHandle, CueTag, FCkCueGym_SpawnParams(Cue3Transform),
			ECk_Cue_ReliabilityPolicy::Unreliable, ECk_Cue_MulticastPolicy::LocalOnly);

		CuesSpawned = 3;

		// Start the destroy timer
		// Find the destroy timer (second timer added, index-based isn't reliable, so use a separate approach)
		// Re-create a destroy timer
		auto DestroyParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
		DestroyParams.Set_StartingState(ECk_Timer_State::Running);
		DestroyParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		auto DestroyTimer = utils_timer::Add(SelfEntity, DestroyParams);
		DestroyTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDestroyOwner"));

		ck::Trace("CueGym: Spawned 3 persistent cues attached to owner");
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "CUE OWNER DESTRUCTION (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		// Count active cues
		auto AttachedCues = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_Cue_OwnerDestruction");
		auto OwnerEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_DestructionOwner");

		auto OwnerStatus = (OwnerEntities.Num() > 0) ? "ALIVE (white sphere)" : "DESTROYED";

		auto DisplayText = f"Cycle: {CycleCount}\n";
		DisplayText = f"{DisplayText}Owner: {OwnerStatus}\n";
		DisplayText = f"{DisplayText}Active Cues: {AttachedCues.Num()}\n\n";

		if (OwnerEntities.Num() > 0)
		{
			DisplayText = f"{DisplayText}Owner alive... will be destroyed soon.\n";
			DisplayText = f"{DisplayText}All 3 cue shapes will vanish with it.";
		}
		else
		{
			DisplayText = f"{DisplayText}Owner destroyed! Cues cleaned up automatically\n";
			DisplayText = f"{DisplayText}by the ECS lifetime dependents system.";
		}

		auto Instructions = "Spawns an owner entity (white box) with 3 persistent cues (blue spheres).\n"
			+ "After 5s the owner is destroyed - all shapes vanish instantly.\n"
			+ "Demonstrates automatic cleanup via lifetime dependents.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}

//============================================================================
// DESTRUCTION OWNER ENTITY (visible owner for OwnerDestruction station)
//============================================================================

class UCk_EntityScript_CueGym_DestructionOwner : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	float ElapsedTime = 0.0f;
	float LifetimeSeconds = 5.0f;
	FCk_Handle_Pmg_DebugShape ShapeHandle;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_DestructionOwner");

		// Tick timer to draw shrinking owner sphere
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DrawTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DrawTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ElapsedTime = ElapsedTime + float(InDeltaT.Get_Seconds());
		auto Progress = Math::Clamp(ElapsedTime / LifetimeSeconds, 0.0, 1.0);

		// Large white sphere that shrinks over lifetime
		auto Radius = float32(Math::Lerp(35.0, 8.0, Progress));
		auto Brightness = float32(1.0 - Progress * 0.6);

		auto Extent = FVector(Radius, Radius, Radius);
		CueGym_Pmg::DestroyShape(ShapeHandle);
		ShapeHandle = CueGym_Pmg::DrawBox(ck::ToEntity(this), FVector(0.0f, 0.0f, 150.0f),
			FLinearColor(Brightness, Brightness, Brightness, 0.3f), Extent);
	}
}
