//============================================================================
// TIMER GYM - BASICS STATION
// Tests: Timer creation, querying, chrono display, lifecycle
//============================================================================

class UCk_EntityScript_TimerGym_Basics : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Timer MainTimer;
	FCk_Handle_Timer RestartDelayTimer;

	int32 CycleCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
	    auto _CkPerfScope = ck::ScopedStat();
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_TimerGym_Basics");

		// Display timer (per-frame)
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Main demo timer: 5 seconds, PauseOnDone so it stays at the end value
		auto MainParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
		MainParams.Set_StartingState(ECk_Timer_State::Running);
		MainParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		MainTimer = utils_timer::Add(InHandle, MainParams);
		MainTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnMainTimerDone"));

		// Restart delay timer: 2 seconds, starts paused
		auto RestartParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0f));
		RestartParams.Set_StartingState(ECk_Timer_State::Paused);
		RestartParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		RestartDelayTimer = utils_timer::Add(InHandle, RestartParams);
		RestartDelayTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnRestartDelayDone"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnMainTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CycleCount++;
		// Start the restart delay
		RestartDelayTimer.Request_Reset();
		RestartDelayTimer.Request_Resume();
	}

	UFUNCTION()
	private void OnRestartDelayDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		// Reset and restart the main timer
		MainTimer.Request_Reset();
		MainTimer.Request_Resume();
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "TIMER BASICS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle: {CycleCount}\n\n";

		// Query all timer properties
		auto Chrono = MainTimer.Get_CurrentTimerValue();
		auto State = MainTimer.Get_CurrentState();
		auto Direction = MainTimer.Get_CountDirection();
		auto Behavior = MainTimer.Get_Behavior();
		auto IsDone = Chrono.Get_IsDone();

		// Break chrono into components
		auto Goal = FCk_Time();
		auto Elapsed = FCk_Time();
		auto Remaining = FCk_Time();
		Chrono.Break_Chrono(Goal, Elapsed, Remaining);

		DisplayText = f"{DisplayText}STATE: {State}\n";
		DisplayText = f"{DisplayText}DIRECTION: {Direction}\n";
		DisplayText = f"{DisplayText}BEHAVIOR: {Behavior}\n";
		DisplayText = f"{DisplayText}IS DONE: " + (IsDone ? "YES" : "NO") + "\n\n";

		DisplayText = f"{DisplayText}GOAL: {Goal.Conv_TimeToString()}\n";
		DisplayText = f"{DisplayText}ELAPSED: {Elapsed.Conv_TimeToString()}\n";
		DisplayText = f"{DisplayText}REMAINING: {Remaining.Conv_TimeToString()}\n";
		DisplayText = f"{DisplayText}CHRONO: {Chrono.Conv_ChronoToString()}\n\n";

		// Progress bar
		auto ElapsedMs = Elapsed.Get_Milliseconds();
		auto GoalMs = Goal.Get_Milliseconds();
		auto Ratio = (GoalMs > 0.0) ? float32(ElapsedMs / GoalMs) : 0.0f;
		auto ProgressBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(Ratio), 25, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
		DisplayText = f"{DisplayText}[{ProgressBar}]";

		if (IsDone)
		{
			DisplayText = f"{DisplayText}\n\nRestarting in 2s...";
		}

		auto Instructions = "Demonstrates basic timer creation and querying.\n"
			+ "A 5-second timer runs to completion, pauses 2s, then resets.\n"
			+ "Shows State, Direction, Behavior, Chrono breakdown, and IsDone flag.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
