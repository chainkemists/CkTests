//============================================================================
// DIALOG GYM - EXIT CHAINS STATION
// A 3-line EXIT->ENTER chain (A->B->C) auto-walked via Request_QueryFollowUp.
// The chain restarts from A every few seconds.
//============================================================================

class UCk_EntityScript_DialogGym_Chains : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	private FCk_Handle_DialogEmitter _Emitter;
	private FGameplayTag _EnterA;
	private FName _CurrentLineID;
	private FText _CurrentText;
	private bool _HasCurrent = false;
	private int _Step = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_DialogGym_Chains");

		_EnterA = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Chains.A");
		auto EnterB = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Chains.B");
		auto EnterC = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Chains.C");

		auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Chains.A", _EnterA);
			LineData.Set_Text(FText::FromString("So, you've come a long way."));
			LineData.Set_LinkedEventTag(EnterB);
			Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
		}
		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Chains.B", EnterB);
			LineData.Set_Text(FText::FromString("The road ahead is dangerous."));
			LineData.Set_LinkedEventTag(EnterC);
			Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
		}
		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Chains.C", EnterC);
			LineData.Set_Text(FText::FromString("Good luck, traveler."));
			Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
		}

		_Emitter = UCk_Utils_DialogEmitter_UE::Add(InHandle, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));
		_Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnResult"));

		// Restart the chain from A every 4s.
		auto CadenceParams = FCk_Fragment_Timer_ParamsData(FCk_Time(4.0));
		CadenceParams.Set_StartingState(ECk_Timer_State::Running);
		CadenceParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto Cadence = utils_timer::Add(InHandle, CadenceParams);
		Cadence.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnRestartTick"));

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void OnRestartTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		_Step = 0;
		_Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EnterA));
	}

	UFUNCTION()
	private void OnResult(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
	{
		auto Entries = InResult.Get_Entries();
		if (Entries.Num() == 0) { return; }

		_CurrentLineID = Entries[0].Get_LineID();
		_CurrentText = Entries[0].Get_Text();
		_HasCurrent = true;
		_Step++;

		// Advance to the next link (no-op at the chain's tail — line C has no exit).
		auto PlayedLine = Entries[0].Get_Line();
		_Emitter.Request_QueryFollowUp(PlayedLine);
	}

	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Body = f"Step {_Step} of 3\n\n";
		if (_HasCurrent)
		{
			Body += f"[{_CurrentLineID.ToString()}]\n";
			Body += f"\"{_CurrentText.ToString()}\"";
		}
		else
		{
			Body += "(chain starting...)";
		}
		CkGym_Common::Update_StationDisplay(SelfEntity, "DIALOG EXIT CHAINS", Body, "A -> B -> C, restarts every 4s");
	}
}
