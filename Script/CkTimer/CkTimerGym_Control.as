//============================================================================
// TIMER GYM - CONTROL STATION
// Tests: All runtime control methods (Pause, Resume, Stop, Reset,
//        Complete, Jump, ReverseDirection, ChangeCountDirection)
//============================================================================

class UCk_EntityScript_TimerGym_Control : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Timer ControlTimer;

	int32 CycleStep = 0;
	FString LastAction = "(none)";
	TArray<FString> ActionHistory;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_TimerGym_Control");

		// Display timer
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Control target timer: 10 seconds, ResetOnDone
		auto ControlParams = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
		ControlParams.Set_StartingState(ECk_Timer_State::Running);
		ControlParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		ControlTimer = utils_timer::Add(InHandle, ControlParams);

		// Automation timer: step every 2.5 seconds
		auto AutoParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.5f));
		AutoParams.Set_StartingState(ECk_Timer_State::Running);
		AutoParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnAutoStep"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	void Request_LogAction(FString InAction)
	{
		LastAction = InAction;
		ActionHistory.Add(InAction);

		// Keep only last 6 entries
		while (ActionHistory.Num() > 6)
		{
			ActionHistory.RemoveAt(0);
		}
	}

	UFUNCTION()
	private void OnAutoStep(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CycleStep++;

		switch (CycleStep)
		{
			case 1:
				Request_LogAction("Request_Pause()");
				ControlTimer.Request_Pause();
				break;
			case 2:
				Request_LogAction("Request_Resume()");
				ControlTimer.Request_Resume();
				break;
			case 3:
				Request_LogAction("Request_Jump(+3s)");
				ControlTimer.Request_Jump(FCk_Request_Timer_Jump(FCk_Time(3.0f)));
				break;
			case 4:
				Request_LogAction("Request_ReverseDirection()");
				ControlTimer.Request_ReverseDirection();
				break;
			case 5:
				Request_LogAction("ChangeCountDirection(CountUp)");
				ControlTimer.Request_ChangeCountDirection(ECk_Timer_CountDirection::CountUp);
				break;
			case 6:
				Request_LogAction("Request_Reset()");
				ControlTimer.Request_Reset();
				ControlTimer.Request_Resume();
				break;
			case 7:
				Request_LogAction("Request_Complete()");
				ControlTimer.Request_Complete();
				break;
			default:
				CycleStep = 0;
				LastAction = "(cycle restart)";
				ActionHistory.Empty();
				break;
		}
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "TIMER RUNTIME CONTROL (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto Chrono = ControlTimer.Get_CurrentTimerValue();
		auto State = ControlTimer.Get_CurrentState();
		auto Direction = ControlTimer.Get_CountDirection();

		auto Goal = FCk_Time();
		auto Elapsed = FCk_Time();
		auto Remaining = FCk_Time();
		Chrono.Break_Chrono(Goal, Elapsed, Remaining);

		auto ElapsedMs = Elapsed.Get_Milliseconds();
		auto GoalMs = Goal.Get_Milliseconds();
		auto Ratio = (GoalMs > 0.0) ? float32(ElapsedMs / GoalMs) : 0.0f;
		auto ProgressBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(Ratio), 25, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);

		auto DisplayText = f"Step {CycleStep}/7\n\n";
		DisplayText = f"{DisplayText}State: {State}\n";
		DisplayText = f"{DisplayText}Direction: {Direction}\n";
		DisplayText = f"{DisplayText}Elapsed: {Elapsed.Conv_TimeToString()} / {Goal.Conv_TimeToString()}\n";
		DisplayText = f"{DisplayText}[{ProgressBar}]\n\n";

		DisplayText = f"{DisplayText}LAST ACTION: {LastAction}\n\n";

		DisplayText = f"{DisplayText}ACTION HISTORY:\n";
		for (int32 i = 0; i < ActionHistory.Num(); i++)
		{
			DisplayText = f"{DisplayText}  {i + 1}. {ActionHistory[i]}\n";
		}

		if (ActionHistory.Num() == 0)
		{
			DisplayText = f"{DisplayText}  (running normally)";
		}

		auto Instructions = "Tests all runtime timer control methods.\n"
			+ "Cycles: Pause > Resume > Jump > Reverse > Restore > Reset > Complete.\n"
			+ "Watch the progress bar respond to each control action.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
