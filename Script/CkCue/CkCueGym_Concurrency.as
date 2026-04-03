//============================================================================
// CUE GYM - CONCURRENCY STATION
// Tests: AllowMultiple vs RestartExisting concurrency policies
//============================================================================

class UCk_EntityScript_CueGym_Concurrency : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	int32 MultipleTriggerCount = 0;
	int32 RestartTriggerCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Concurrency");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto-demo timer: fire cues every 2 seconds
		auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0f));
		CycleParams.Set_StartingState(ECk_Timer_State::Running);
		CycleParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
		CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleTick"));

		// Fire initial cues
		Request_FireBothCues();

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
		Request_FireBothCues();
	}

	void Request_FireBothCues()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto BaseLocation = InitialTransform.GetLocation();

		// Left side: AllowMultiple - each instance gets a vertical offset so they stack
		auto MultipleOffset = FVector(-100.0f, -100.0f, float(MultipleTriggerCount % 5) * 40.0f);
		auto MultipleTransform = FTransform(InitialTransform.GetRotation(), BaseLocation + MultipleOffset, FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue_Local(SelfEntity,
			GameplayTags::ResolveGameplayTag(n"CueGym.Concurrency.Multiple"),
			FCkCueGym_SpawnParams(MultipleTransform));
		MultipleTriggerCount++;

		// Right side: RestartExisting - always same position, restarts instead of stacking
		auto RestartOffset = FVector(-100.0f, 100.0f, 0.0f);
		auto RestartTransform = FTransform(InitialTransform.GetRotation(), BaseLocation + RestartOffset, FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue_Local(SelfEntity,
			GameplayTags::ResolveGameplayTag(n"CueGym.Concurrency.Restart"),
			FCkCueGym_SpawnParams(RestartTransform));
		RestartTriggerCount++;
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "CUE CONCURRENCY (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		// Count active instances
		auto MultipleEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_Cue_Multiple");
		auto RestartEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_Cue_Restart");

		auto DisplayText = "=== AllowMultiple (Left) ===\n";
		DisplayText = f"{DisplayText}Triggers: {MultipleTriggerCount}\n";
		DisplayText = f"{DisplayText}Active Instances: {MultipleEntities.Num()}\n\n";
		DisplayText = f"{DisplayText}=== RestartExisting (Right) ===\n";
		DisplayText = f"{DisplayText}Triggers: {RestartTriggerCount}\n";
		DisplayText = f"{DisplayText}Active Instances: {RestartEntities.Num()}\n";

		auto Instructions = "Fires both cue types every 2s. Both shrink over time:\n"
			+ "  Left: AllowMultiple - multiple spheres, each shrinks\n"
			+ "    independently (green->red, large->small)\n"
			+ "  Right: RestartExisting - single sphere snaps back to\n"
			+ "    large/bright on each restart (never fully shrinks)";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
