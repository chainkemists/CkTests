//============================================================================
// DIALOG GYM - BASICS STATION
// A runtime mini-bank on one ENTER tag; auto-cycled query lists all lines +
// their pass/fail states (one line is gated off by an always-fail condition).
//============================================================================

class UCk_EntityScript_DialogGym_Basics : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	private FCk_Handle_DialogEmitter _Emitter;
	private FGameplayTag _EventTag;
	private FCk_DialogEmitter_QueryResult _LastResult;
	private bool _HasResult = false;
	private int _QueryCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_DialogGym_Basics");

		_EventTag = utils_gameplay_tag::ResolveGameplayTag(n"DialogGym.Basics.Greeting");
		auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Basics.Hello", _EventTag);
			LineData.Set_Text(FText::FromString("Hello, traveler!"));
			Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
		}
		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Basics.Weather", _EventTag);
			LineData.Set_Text(FText::FromString("Lovely weather today."));
			Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
		}
		{
			auto LineData = FCk_DialogBank_LineData(n"DialogGym.Basics.Gated", _EventTag);
			LineData.Set_Text(FText::FromString("(gated off)"));
			Registry.Request_RegisterLine_WithCondition(
				LineData, FGameplayTagContainer(), NewObject(this, UCk_DialogTestCond_AlwaysFail));
		}

		_Emitter = UCk_Utils_DialogEmitter_UE::Add(InHandle, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));
		_Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnQueryCompleted"));

		auto CadenceParams = FCk_Timer_Spec(FCk_Time(2.0));
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
		_QueryCount++;
		_Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
	}

	UFUNCTION()
	private void OnQueryCompleted(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
	{
		_LastResult = InResult;
		_HasResult = true;
	}

	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Body = f"Queries fired: {_QueryCount}\n\n";

		if (_HasResult)
		{
			auto Entries = _LastResult.Get_Entries();
			Body += f"Last result ({Entries.Num()} lines):\n";
			for (int i = 0; i < Entries.Num(); i++)
			{
				auto StateStr = "Passed";
				auto R = Entries[i].Get_Result();
				if (R == ECk_DialogLine_QueryResult::Fail_LineCondition) { StateStr = "FAIL(line)"; }
				else if (R == ECk_DialogLine_QueryResult::Fail_EmitterCondition) { StateStr = "FAIL(cooldown)"; }
				Body += f"  [{StateStr}] {Entries[i].Get_LineID().ToString()}\n";
			}
		}
		else
		{
			Body += "(waiting for first query...)";
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, "DIALOG BASICS", Body, "Query auto-cycles every 2s");
	}
}
