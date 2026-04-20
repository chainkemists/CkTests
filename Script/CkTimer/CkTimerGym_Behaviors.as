//============================================================================
// TIMER GYM - BEHAVIORS STATION
// Tests: ResetOnDone vs PauseOnDone vs StopOnDone side-by-side
//============================================================================

class UCk_EntityScript_TimerGym_Behaviors : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Timer ResetTimer;
	FCk_Handle_Timer PauseTimer;
	FCk_Handle_Timer StopTimer;

	int32 ResetDoneCount = 0;
	int32 PauseDoneCount = 0;
	int32 StopDoneCount = 0;

	// Auto-restart cycle
	FCk_Handle_Timer CycleTimer;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_TimerGym_Behaviors");

		// Display timer
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		Request_CreateDemoTimers(InHandle);

		// Cycle reset timer: every 18 seconds, reset non-looping timers
		auto CycleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(18.0f));
		CycleParams.Set_StartingState(ECk_Timer_State::Running);
		CycleParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		CycleTimer = utils_timer::Add(InHandle, CycleParams);
		CycleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleReset"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	void Request_CreateDemoTimers(FCk_Handle InHandle)
	{
		// Timer 1: ResetOnDone (loops continuously)
		auto ResetParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		ResetParams.Set_StartingState(ECk_Timer_State::Running);
		ResetParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		ResetTimer = utils_timer::Add(InHandle, ResetParams);
		ResetTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnResetDone"));

		// Timer 2: PauseOnDone (freezes at end)
		auto PauseParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		PauseParams.Set_StartingState(ECk_Timer_State::Running);
		PauseParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
		PauseTimer = utils_timer::Add(InHandle, PauseParams);
		PauseTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPauseDone"));

		// Timer 3: StopOnDone (resets and stops)
		auto StopParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		StopParams.Set_StartingState(ECk_Timer_State::Running);
		StopParams.Set_Behavior(ECk_Timer_Behavior::StopOnDone);
		StopTimer = utils_timer::Add(InHandle, StopParams);
		StopTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnStopDone"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnResetDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ResetDoneCount++;
	}

	UFUNCTION()
	private void OnPauseDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		PauseDoneCount++;
	}

	UFUNCTION()
	private void OnStopDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		StopDoneCount++;
	}

	UFUNCTION()
	private void OnCycleReset(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		// Reset PauseOnDone and StopOnDone timers so the demo restarts
		PauseDoneCount = 0;
		StopDoneCount = 0;

		PauseTimer.Request_Reset();
		PauseTimer.Request_Resume();

		StopTimer.Request_Reset();
		StopTimer.Request_Resume();
	}

	FString Get_TimerSection(FString InLabel, FCk_Handle_Timer InTimer, int32 InDoneCount)
	{
		auto Chrono = InTimer.Get_CurrentTimerValue();
		auto State = InTimer.Get_CurrentState();
		auto Elapsed = Chrono.Get_TimeElapsed();
		auto Goal = FCk_Time();
		auto ElapsedOut = FCk_Time();
		auto Remaining = FCk_Time();
		Chrono.Break_Chrono(Goal, ElapsedOut, Remaining);

		auto ElapsedMs = Elapsed.Get_Milliseconds();
		auto GoalMs = Goal.Get_Milliseconds();
		auto Ratio = (GoalMs > 0.0) ? float32(ElapsedMs / GoalMs) : 0.0f;
		auto Bar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(Ratio), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);

		auto Text = f"--- {InLabel} ---\n";
		Text = f"{Text}State: {State} | Done: {InDoneCount}\n";
		Text = f"{Text}[{Bar}] {Elapsed.Conv_TimeToString()}/{Goal.Conv_TimeToString()}\n";
		return Text;
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "TIMER BEHAVIORS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto DisplayText = Get_TimerSection("ResetOnDone (loops)", ResetTimer, ResetDoneCount);
		DisplayText = f"{DisplayText}\n";
		DisplayText = f"{DisplayText}" + Get_TimerSection("PauseOnDone (freezes)", PauseTimer, PauseDoneCount);
		DisplayText = f"{DisplayText}\n";
		DisplayText = f"{DisplayText}" + Get_TimerSection("StopOnDone (resets+stops)", StopTimer, StopDoneCount);

		auto Instructions = "Compares three timer behaviors running simultaneously.\n"
			+ "ResetOnDone loops, PauseOnDone freezes at end, StopOnDone resets and stops.\n"
			+ "Non-looping timers auto-restart every 18 seconds.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
