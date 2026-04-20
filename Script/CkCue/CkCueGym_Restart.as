//============================================================================
// CUE GYM - RESTART STATION
// Tests: Restart() method via RestartExisting concurrency policy
//============================================================================

class UCk_EntityScript_CueGym_Restart : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	int32 TriggerCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Restart");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Fire the restartable cue immediately
		Request_FireCue();

		// Re-fire timer: every 3 seconds (triggers restart via RestartExisting)
		auto RefireParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		RefireParams.Set_StartingState(ECk_Timer_State::Running);
		RefireParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto RefireTimer = utils_timer::Add(InHandle, RefireParams);
		RefireTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnRefireTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnRefireTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_FireCue();
	}

	void Request_FireCue()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto BaseLocation = InitialTransform.GetLocation();
		auto CueTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, 0.0f, 0.0f), FVector(1.0f));

		utils_cue_generic::Request_ExecuteCue_Local(SelfEntity,
			GameplayTags::ResolveGameplayTag(n"CueGym.Restart.Restartable"),
			FCkCueGym_SpawnParams(CueTransform));

		TriggerCount++;
		ck::Trace(f"CueGym: Restart station fired cue (trigger #{TriggerCount})");
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "CUE RESTART (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		// Count active restartable cues
		auto RestartableEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_Cue_Restartable");

		auto DisplayText = f"Trigger Count: {TriggerCount}\n";
		DisplayText = f"{DisplayText}Active Instances: {RestartableEntities.Num()}\n\n";
		DisplayText = f"{DisplayText}Cue has RestartExisting policy.\n";
		DisplayText = f"{DisplayText}Re-firing every 3s triggers DoRestart()\n";
		DisplayText = f"{DisplayText}instead of spawning a new instance.\n\n";
		DisplayText = f"{DisplayText}Sphere color cycles continuously\n";
		DisplayText = f"{DisplayText}through the spectrum with each restart.";

		auto Instructions = "Fires an 8s Timed cue, then re-fires every 3s.\n"
			+ "RestartExisting policy restarts the existing cue\n"
			+ "instead of creating a new one. Watch the sphere cycle colors.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
