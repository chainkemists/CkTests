//============================================================================
// DIALOG GYM - FILTERS STATION
// Two emitters (Townie vs NamedNpc), same ENTER event, different visible line
// subsets via tag-overlap. Plus a global (untagged) line both can see.
//============================================================================

class UCk_EntityScript_DialogGym_Filters : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	private FCk_Handle_DialogEmitter _TownieEmitter;
	private FCk_Handle_DialogEmitter _NamedEmitter;
	private FGameplayTag _EventTag;
	private int _TownieCount = 0;
	private int _NamedCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_DialogGym_Filters");

		_EventTag = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Filters.Enter");
		auto TownieTag = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Filters.Townie");
		auto NamedTag = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Filters.NamedNpc");

		auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

		{
			auto Bank = FGameplayTagContainer();
			Bank.AddTag(TownieTag);
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Filters.TownieLine", _EventTag);
			LineData.Set_Text(FText::FromString("Nice day for a walk."));
			Registry.Request_RegisterLine(LineData, Bank);
		}
		{
			auto Bank = FGameplayTagContainer();
			Bank.AddTag(NamedTag);
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Filters.NamedLine", _EventTag);
			LineData.Set_Text(FText::FromString("Ah, it is you again, hero."));
			Registry.Request_RegisterLine(LineData, Bank);
		}
		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Filters.GlobalLine", _EventTag);
			LineData.Set_Text(FText::FromString("(everyone can say this)"));
			Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
		}

		// Townie emitter (this entity).
		auto TownieTags = FGameplayTagContainer();
		TownieTags.AddTag(TownieTag);
		_TownieEmitter = UCk_Utils_DialogEmitter_UE::Add(InHandle, FCk_Fragment_DialogEmitter_ParamsData(TownieTags));
		_TownieEmitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnTownieResult"));

		// NamedNpc emitter (a child entity).
		auto NamedChild = utils_entity_lifetime::Request_CreateEntity(InHandle);
		auto NamedTags = FGameplayTagContainer();
		NamedTags.AddTag(NamedTag);
		_NamedEmitter = UCk_Utils_DialogEmitter_UE::Add(NamedChild, FCk_Fragment_DialogEmitter_ParamsData(NamedTags));
		_NamedEmitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnNamedResult"));

		auto CadenceParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0));
		CadenceParams.Set_StartingState(ECk_Timer_State::Running);
		CadenceParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto Cadence = utils_timer::Add(InHandle, CadenceParams);
		Cadence.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnQueryTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void OnQueryTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		_TownieEmitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
		_NamedEmitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
	}

	UFUNCTION()
	private void OnTownieResult(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
	{
		_TownieCount = InResult.Get_Entries().Num();
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnNamedResult(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
	{
		_NamedCount = InResult.Get_Entries().Num();
		Request_UpdateDisplay();
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Body = f"Townie emitter sees: {_TownieCount} line(s)\n";
		Body += f"NamedNpc emitter sees: {_NamedCount} line(s)\n\n";
		Body += "(each sees its own tagged line + the global line = 2)";
		CkGym_Common::Update_StationDisplay(SelfEntity, "DIALOG TAG FILTERS", Body, "Same event, different visible lines");
	}
}
