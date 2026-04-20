//============================================================================
// TIMER GYM - COUNTDOWN STATION
// Tests: CountDown direction, PauseOnDone vs ResetOnDone countdown,
//        Request_Consume, OnDepleted signal
//============================================================================

class UCk_EntityScript_TimerGym_Countdown : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Two countdown timers with different behaviors
	FCk_Handle_Timer CountdownPause;   // PauseOnDone
	FCk_Handle_Timer CountdownReset;   // ResetOnDone

	int32 PauseDoneCount = 0;
	int32 ResetDoneCount = 0;

	// Consume demo timer
	FCk_Handle_Timer ConsumeTimer;
	int32 ConsumeCount = 0;
	int32 DepletedCount = 0;
	FString ConsumeStatus = "Waiting";

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_TimerGym_Countdown");

		// Display timer
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Countdown A: 10s, CountDown, PauseOnDone
		auto PauseParams = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
		PauseParams.Set_StartingState(ECk_Timer_State::Running);
		PauseParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		PauseParams.Set_CountDirection(ECk_Timer_CountDirection::CountDown);
		CountdownPause = utils_timer::Add(InHandle, PauseParams);
		CountdownPause.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPauseDone"));

		// Countdown B: 10s, CountDown, ResetOnDone
		auto ResetParams = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
		ResetParams.Set_StartingState(ECk_Timer_State::Running);
		ResetParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		ResetParams.Set_CountDirection(ECk_Timer_CountDirection::CountDown);
		CountdownReset = utils_timer::Add(InHandle, ResetParams);
		CountdownReset.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnResetDone"));

		// Consume demo: 10s timer, consumed in chunks
		auto ConsumeParams = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
		ConsumeParams.Set_StartingState(ECk_Timer_State::Running);
		ConsumeParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		ConsumeTimer = utils_timer::Add(InHandle, ConsumeParams);
		ConsumeTimer.BindTo_OnDepleted(FCk_Delegate_Timer(this, n"OnDepleted"));

		// Automation: consume 2s every 3s
		auto AutoParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		AutoParams.Set_StartingState(ECk_Timer_State::Running);
		AutoParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnConsumeStep"));

		// Full cycle reset after 25s
		auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(25.0f));
		CycleParams.Set_StartingState(ECk_Timer_State::Running);
		CycleParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto CycleTimer = utils_timer::Add(InHandle, CycleParams);
		CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleReset"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnPauseDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		PauseDoneCount++;
	}

	UFUNCTION()
	private void OnResetDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ResetDoneCount++;
	}

	UFUNCTION()
	private void OnConsumeStep(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ConsumeTimer.Get_CurrentTimerValue().Get_IsDone())
		{
			ConsumeStatus = "Already depleted";
			return;
		}

		ConsumeCount++;
		ConsumeStatus = f"Consumed chunk #{ConsumeCount} (-2s)";
		ConsumeTimer.Request_Consume(FCk_Request_Timer_Consume(FCk_Time(2.0f)));
	}

	UFUNCTION()
	private void OnDepleted(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DepletedCount++;
		ConsumeStatus = "DEPLETED!";
	}

	UFUNCTION()
	private void OnCycleReset(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		PauseDoneCount = 0;
		ConsumeCount = 0;
		DepletedCount = 0;
		ConsumeStatus = "Waiting";

		CountdownPause.Request_Reset();
		CountdownPause.Request_Resume();

		ConsumeTimer.Request_Reset();
		ConsumeTimer.Request_Resume();
	}

	FString Get_CountdownSection(FString InLabel, FCk_Handle_Timer InTimer, int32 InDoneCount)
	{
		auto Chrono = InTimer.Get_CurrentTimerValue();
		auto State = InTimer.Get_CurrentState();
		auto Goal = FCk_Time();
		auto ElapsedOut = FCk_Time();
		auto RemainingOut = FCk_Time();
		Chrono.Break_Chrono(Goal, ElapsedOut, RemainingOut);

		auto ElapsedMs = ElapsedOut.Get_Milliseconds();
		auto GoalMs = Goal.Get_Milliseconds();
		// For countdown: elapsed goes 10→0, so bar drains naturally
		auto Ratio = (GoalMs > 0.0) ? float32(ElapsedMs / GoalMs) : 0.0f;
		auto Bar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(Ratio), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);

		auto Text = f"--- {InLabel} ---\n";
		Text = f"{Text}State: {State} | Done: {InDoneCount}\n";
		Text = f"{Text}Countdown: {ElapsedOut.Conv_TimeToString()}\n";
		Text = f"{Text}[{Bar}]\n";
		return Text;
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "TIMER COUNTDOWN (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto DisplayText = Get_CountdownSection("Countdown + PauseOnDone", CountdownPause, PauseDoneCount);
		DisplayText = f"{DisplayText}\n";
		DisplayText = f"{DisplayText}" + Get_CountdownSection("Countdown + ResetOnDone", CountdownReset, ResetDoneCount);

		// Consume section
		DisplayText = f"{DisplayText}\n--- CONSUME DEMO ---\n";
		auto ConsumeChrono = ConsumeTimer.Get_CurrentTimerValue();
		auto ConsumeGoal = FCk_Time();
		auto ConsumeElapsed = FCk_Time();
		auto ConsumeRemaining = FCk_Time();
		ConsumeChrono.Break_Chrono(ConsumeGoal, ConsumeElapsed, ConsumeRemaining);

		auto ConsumeRemainingMs = ConsumeRemaining.Get_Milliseconds();
		auto ConsumeGoalMs = ConsumeGoal.Get_Milliseconds();
		auto ConsumeRatio = (ConsumeGoalMs > 0.0) ? float32(ConsumeRemainingMs / ConsumeGoalMs) : 0.0f;
		auto ConsumeBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(ConsumeRatio), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);

		DisplayText = f"{DisplayText}Chunks consumed: {ConsumeCount} | Depleted: {DepletedCount}\n";
		DisplayText = f"{DisplayText}[{ConsumeBar}] {ConsumeRemaining.Conv_TimeToString()}\n";
		DisplayText = f"{DisplayText}Status: {ConsumeStatus}";

		auto Instructions = "Tests CountDown direction and Request_Consume.\n"
			+ "Two 10s countdowns with different behaviors (drain from full to empty).\n"
			+ "Consume demo subtracts 2s chunks every 3s until OnDepleted fires.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
