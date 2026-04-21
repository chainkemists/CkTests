//============================================================================
// CUE GYM - LIFETIME STATION
// Tests: AfterOneFrame, Persistent, Timed, Custom lifetime behaviors
//============================================================================

class UCk_EntityScript_CueGym_Lifetime : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	int32 CycleCount = 0;
	int32 CueIndex = 0;
	FString LastFiredCue = "None";

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_CueGym_Lifetime");

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto-demo cycle timer: fire a cue every 4 seconds
		auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(4.0f));
		CycleParams.Set_StartingState(ECk_Timer_State::Running);
		CycleParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
		CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleTick"));

		// Fire the first cue immediately
		Request_FireNextCue();

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
		Request_FireNextCue();
	}

	void Request_FireNextCue()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto BaseTransform = InitialTransform;
		auto BaseLocation = BaseTransform.GetLocation();

		// Offset each cue type to a different position
		auto Offset = FVector(0.0f, 0.0f, 0.0f);
		auto CueTag = FGameplayTag();

		if (CueIndex == 0)
		{
			Offset = FVector(-100.0f, -150.0f, 0.0f);
			CueTag = GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.AfterOneFrame");
			LastFiredCue = "AfterOneFrame";
		}
		else if (CueIndex == 1)
		{
			Offset = FVector(-100.0f, -50.0f, 0.0f);
			CueTag = GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.Persistent");
			LastFiredCue = "Persistent";
		}
		else if (CueIndex == 2)
		{
			Offset = FVector(-100.0f, 50.0f, 0.0f);
			CueTag = GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.Timed");
			LastFiredCue = "Timed (5s)";
		}
		else if (CueIndex == 3)
		{
			Offset = FVector(-100.0f, 150.0f, 0.0f);
			CueTag = GameplayTags::ResolveGameplayTag(n"CueGym.Lifetime.Custom");
			LastFiredCue = "Custom (3s self-destruct)";
		}

		auto CueTransform = FTransform(BaseTransform.GetRotation(), BaseLocation + Offset, FVector(1.0f));
		utils_cue_generic::Request_ExecuteCue(SelfEntity, CueTag, FCkCueGym_SpawnParams(CueTransform),
			ECk_Cue_ReliabilityPolicy::Unreliable, ECk_Cue_MulticastPolicy::LocalOnly);

		CueIndex = (CueIndex + 1) % 4;
		if (CueIndex == 0)
		{
			CycleCount++;
		}
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "CUE LIFETIME (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto DisplayText = f"Cycle: {CycleCount}\n";
		DisplayText = f"{DisplayText}Last Fired: {LastFiredCue}\n\n";

		// Count active persistent cues
		auto PersistentEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_CueGym_Cue_Persistent");
		DisplayText = f"{DisplayText}Active Persistent Cues: {PersistentEntities.Num()}\n";

		auto Instructions = "Cycles through 4 lifetime behaviors every 4s:\n"
			+ "  AfterOneFrame - destroyed after 1 frame\n"
			+ "  Persistent - stays alive indefinitely (green sphere)\n"
			+ "  Timed (5s) - auto-destroys after 5s (blue sphere)\n"
			+ "  Custom (3s) - self-destructs via timer (orange sphere)";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
