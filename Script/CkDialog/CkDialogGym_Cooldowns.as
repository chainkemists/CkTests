//============================================================================
// DIALOG GYM - COOLDOWNS STATION
// 1s query cadence vs a 3s cooldown. When a line plays it goes on cooldown and
// reports Fail(cooldown) until it expires. A second emitter never cools it,
// proving per-emitter isolation. Doubles as the debugger live-overlay bed.
//============================================================================

class UCk_EntityScript_DialogGym_Cooldowns : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	private FCk_Handle_DialogEmitter _Emitter;
	private FCk_Handle_DialogEmitter _OtherEmitter;
	private FCk_Handle_DialogLine _Line;
	private FGameplayTag _EventTag;
	private ECk_DialogLine_QueryResult _LastState;
	private ECk_DialogLine_QueryResult _OtherState;
	private bool _HasState = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_DialogGym_Cooldowns");

		_EventTag = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Cooldowns.Enter");
		auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

		auto LineData = FCk_DialogBank_LineData(n"DialogGym.Cooldowns.Line", _EventTag);
		LineData.Set_Text(FText::FromString("Watch me go on cooldown."));
		_Line = Registry.Request_RegisterLine(LineData, FGameplayTagContainer());

		_Emitter = UCk_Utils_DialogEmitter_UE::Add(InHandle, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));
		_Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnResult"));

		auto OtherChild = utils_entity_lifetime::Request_CreateEntity(InHandle);
		_OtherEmitter = UCk_Utils_DialogEmitter_UE::Add(OtherChild, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));
		_OtherEmitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnOtherResult"));

		auto CadenceParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.0));
		CadenceParams.Set_StartingState(ECk_Timer_State::Running);
		CadenceParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto Cadence = utils_timer::Add(InHandle, CadenceParams);
		Cadence.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnQueryTick"));

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void OnQueryTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		_Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
		_OtherEmitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
	}

	private ECk_DialogLine_QueryResult DoFirstResult(FCk_DialogEmitter_QueryResult InResult)
	{
		auto Entries = InResult.Get_Entries();
		if (Entries.Num() == 0) { return ECk_DialogLine_QueryResult::Fail_EmitterCondition; }
		return Entries[0].Get_Result();
	}

	UFUNCTION()
	private void OnResult(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
	{
		_LastState = DoFirstResult(InResult);
		_HasState = true;

		// "Play" the line when it Passes: put it on a 3s cooldown.
		if (_LastState == ECk_DialogLine_QueryResult::Passed)
		{
			_Emitter.Request_StartCooldown(FCk_Request_DialogEmitter_StartCooldown(_Line, FCk_Time(3.0)));
		}
	}

	UFUNCTION()
	private void OnOtherResult(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
	{
		_OtherState = DoFirstResult(InResult);
	}

	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Remaining = _Emitter.Get_CooldownRemaining(_Line);

		auto Body = "";
		if (_HasState)
		{
			auto Mine = "Passed";
			if (_LastState == ECk_DialogLine_QueryResult::Fail_EmitterCondition) { Mine = "FAIL(cooldown)"; }
			else if (_LastState == ECk_DialogLine_QueryResult::Fail_LineCondition) { Mine = "FAIL(line)"; }

			auto Other = "Passed";
			if (_OtherState == ECk_DialogLine_QueryResult::Fail_EmitterCondition) { Other = "FAIL(cooldown)"; }

			Body += f"Emitter A: {Mine}   (cooldown {Remaining.Get_Seconds()}s)\n";
			Body += f"Emitter B: {Other}   (never cooled)\n";
		}
		else
		{
			Body += "(waiting for first query...)";
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, "DIALOG COOLDOWNS", Body, "Query 1s / cooldown 3s");
	}
}
