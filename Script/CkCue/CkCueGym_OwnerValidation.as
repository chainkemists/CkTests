//============================================================================
// CUE GYM - OWNER VALIDATION STATION
// Tests: SkipIfInvalid vs RequireValid with valid and invalid owners
//============================================================================

class UCk_EntityScript_CueGym_OwnerValidation : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Phase tracking
	int32 CurrentPhase = 0;
	FCk_Handle TempOwnerHandle;

	// Results
	bool Phase1_SkipExecuted = false;
	bool Phase1_RequireExecuted = false;
	bool Phase2_SkipExecuted = false;
	bool Phase2_RequireExecuted = false;
	int32 CycleCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_OwnerValidation");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Phase timer: 5 seconds per phase
		auto PhaseParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
		PhaseParams.Set_StartingState(ECk_Timer_State::Running);
		PhaseParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto PhaseTimer = utils_timer::Add(InHandle, PhaseParams);
		PhaseTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPhaseTick"));

		// Start Phase 1: create temp owner and fire cues
		Request_StartPhase1();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnPhaseTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (CurrentPhase == 1)
		{
			Request_StartPhase2();
		}
		else
		{
			// Reset and start over
			CycleCount++;
			Request_StartPhase1();
		}
	}

	void Request_StartPhase1()
	{
		CurrentPhase = 1;
		Phase1_SkipExecuted = false;
		Phase1_RequireExecuted = false;

		auto SelfEntity = ck::ToEntity(this);

		// Create a temporary owner entity
		auto SpawnParams = FCk_Gym_TransformSpawnParams(InitialTransform);
		auto PendingHandle = utils_entity_script::Request_SpawnEntity(
			SelfEntity, UCk_EntityScript_CueGym_TempOwner, FInstancedStruct::Make(SpawnParams));

		// Fire cues with self as owner (valid owner)
		auto BaseLocation = InitialTransform.GetLocation();

		// SkipIfInvalid cue at left
		auto SkipTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, -100.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue_Local(SelfEntity,
			GameplayTags::ResolveGameplayTag(n"CueGym.Owner.SkipInvalid"),
			FCkCueGym_SpawnParams(SkipTransform));
		Phase1_SkipExecuted = true;

		// RequireValid cue at right
		auto RequireTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, 100.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue_Local(SelfEntity,
			GameplayTags::ResolveGameplayTag(n"CueGym.Owner.RequireValid"),
			FCkCueGym_SpawnParams(RequireTransform));
		Phase1_RequireExecuted = true;

		ck::Trace("CueGym: OwnerValidation Phase 1 - fired cues with valid owner");
	}

	void Request_StartPhase2()
	{
		CurrentPhase = 2;
		Phase2_SkipExecuted = false;
		Phase2_RequireExecuted = false;

		// Destroy the temp owner
		auto SelfEntity = ck::ToEntity(this);
		auto TempOwners = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_TempOwner");
		for (auto Entity : TempOwners)
		{
			utils_entity_lifetime::Request_DestroyEntity(Entity);
		}

		// Fire cues with an invalid handle as owner
		auto InvalidHandle = FCk_Handle();
		auto BaseLocation = InitialTransform.GetLocation();

		// SkipIfInvalid cue at left - should still spawn (policy skips validation)
		auto SkipTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, -100.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue_Local(InvalidHandle,
			GameplayTags::ResolveGameplayTag(n"CueGym.Owner.SkipInvalid"),
			FCkCueGym_SpawnParams(SkipTransform));
		Phase2_SkipExecuted = true;

		// RequireValid cue at right - should NOT spawn (policy requires valid owner)
		auto RequireTransform = FTransform(InitialTransform.GetRotation(),
			BaseLocation + FVector(-100.0f, 100.0f, 0.0f), FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue_Local(InvalidHandle,
			GameplayTags::ResolveGameplayTag(n"CueGym.Owner.RequireValid"),
			FCkCueGym_SpawnParams(RequireTransform));
		Phase2_RequireExecuted = true;

		ck::Trace("CueGym: OwnerValidation Phase 2 - fired cues with invalid owner");
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "CUE OWNER VALIDATION (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto PhaseText = (CurrentPhase == 1) ? "Phase 1: Valid Owner" : "Phase 2: Invalid Owner";
		auto DisplayText = f"Cycle: {CycleCount}\n";
		DisplayText = f"{DisplayText}Current: {PhaseText}\n\n";

		DisplayText = f"{DisplayText}=== Phase 1 (Valid Owner) ===\n";
		auto P1Skip = Phase1_SkipExecuted ? "EXECUTED" : "---";
		auto P1Require = Phase1_RequireExecuted ? "EXECUTED" : "---";
		DisplayText = f"{DisplayText}SkipIfInvalid: {P1Skip}\n";
		DisplayText = f"{DisplayText}RequireValid:  {P1Require}\n\n";

		DisplayText = f"{DisplayText}=== Phase 2 (Invalid Owner) ===\n";
		auto P2Skip = Phase2_SkipExecuted ? "FIRED (should skip)" : "---";
		auto P2Require = Phase2_RequireExecuted ? "FIRED (should fail)" : "---";
		DisplayText = f"{DisplayText}SkipIfInvalid: {P2Skip}\n";
		DisplayText = f"{DisplayText}RequireValid:  {P2Require}\n";

		auto Instructions = "Alternates between valid and invalid owners:\n"
			+ "  Phase 1: Both cues fire with valid owner (both execute)\n"
			+ "  Phase 2: Both cues fire with invalid owner\n"
			+ "    Left (cyan): SkipIfInvalid - skips silently\n"
			+ "    Right (yellow): RequireValid - should not execute";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}

//============================================================================
// TEMPORARY OWNER ENTITY (used by OwnerValidation station)
//============================================================================

class UCk_EntityScript_CueGym_TempOwner : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_TempOwner");
		return ECk_EntityScript_ConstructionFlow::Finished;
	}
}
