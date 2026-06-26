//============================================================================
// CUE GYM - TRANSIENT STATION
// Tests: Cues executed without a persistent owner entity
//============================================================================

class UCk_EntityScript_CueGym_Transient : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	int32 ExecutionCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Transient");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto-demo timer: fire transient cue every 5 seconds
		auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
		CycleParams.Set_StartingState(ECk_Timer_State::Running);
		CycleParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
		CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleTick"));

		// Fire the first cue immediately
		Request_FireTransientCue();

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
		Request_FireTransientCue();
	}

	void Request_FireTransientCue()
	{
		auto BaseLocation = InitialTransform.GetLocation();
		auto CueTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, 0.0f, 0.0f), FVector(1.0f));

		utils_cue_generic::Request_ExecuteCue_Transient(
			GameplayTags::ResolveGameplayTag(n"CueGym.Transient.NoOwner"),
			FCkCueGym_SpawnParams(CueTransform));

		ExecutionCount++;
		ck::Trace(f"CueGym: Transient cue fired (count: {ExecutionCount})");
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "CUE TRANSIENT (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		// Count active transient cues
		auto TransientEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_Cue_Transient");

		auto DisplayText = f"Executions: {ExecutionCount}\n";
		DisplayText = f"{DisplayText}Active Transient Cues: {TransientEntities.Num()}\n\n";
		DisplayText = f"{DisplayText}Uses Request_ExecuteCue_Transient()\n";
		DisplayText = f"{DisplayText}which requires no owner entity handle.\n";
		DisplayText = f"{DisplayText}The system provides a transient owner internally.";

		auto Instructions = "Fires a transient cue every 5s via\n"
			+ "Request_ExecuteCue_Transient (no owner needed).\n"
			+ "Each cue lives for 5s (purple sphere).";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
