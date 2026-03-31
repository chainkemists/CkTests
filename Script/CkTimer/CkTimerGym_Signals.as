//============================================================================
// TIMER GYM - SIGNALS STATION
// Tests: All 8 timer signals (OnUpdate, OnDone, OnPause, OnResume,
//        OnReset, OnStop, OnJump, OnDepleted)
//============================================================================

class UCk_EntityScript_TimerGym_Signals : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Timer TestTimer;

	// Signal fire counters
	int32 UpdateCount = 0;
	int32 DoneCount = 0;
	int32 PauseCount = 0;
	int32 ResumeCount = 0;
	int32 ResetCount = 0;
	int32 StopCount = 0;
	int32 JumpCount = 0;
	int32 DepletedCount = 0;

	FString LastSignal = "(none)";
	int32 CycleStep = 0;
	FString CurrentPhase = "Starting";

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_TimerGym_Signals");

		// Display timer
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Test timer: 4 seconds, ResetOnDone
		auto TestParams = FCk_Fragment_Timer_ParamsData(FCk_Time(4.0f));
		TestParams.Set_StartingState(ECk_Timer_State::Running);
		TestParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		TestTimer = utils_timer::Add(InHandle, TestParams);

		// Bind all 8 signals
		TestTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"OnTimerUpdate"));
		TestTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimerDone"));
		TestTimer.BindTo_OnPause(FCk_Delegate_Timer(this, n"OnTimerPause"));
		TestTimer.BindTo_OnResume(FCk_Delegate_Timer(this, n"OnTimerResume"));
		TestTimer.BindTo_OnReset(FCk_Delegate_Timer(this, n"OnTimerReset"));
		TestTimer.BindTo_OnStop(FCk_Delegate_Timer(this, n"OnTimerStop"));
		TestTimer.BindTo_OnJump(FCk_Delegate_Timer_Jump(this, n"OnTimerJump"));
		TestTimer.BindTo_OnDepleted(FCk_Delegate_Timer(this, n"OnTimerDepleted"));

		// Automation timer: step every 2 seconds
		auto AutoParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0f));
		AutoParams.Set_StartingState(ECk_Timer_State::Running);
		AutoParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnAutoStep"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	// Signal callbacks
	UFUNCTION()
	private void OnTimerUpdate(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		UpdateCount++;
	}

	UFUNCTION()
	private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DoneCount++;
		LastSignal = "OnDone";
	}

	UFUNCTION()
	private void OnTimerPause(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		PauseCount++;
		LastSignal = "OnPause";
	}

	UFUNCTION()
	private void OnTimerResume(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ResumeCount++;
		LastSignal = "OnResume";
	}

	UFUNCTION()
	private void OnTimerReset(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		ResetCount++;
		LastSignal = "OnReset";
	}

	UFUNCTION()
	private void OnTimerStop(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		StopCount++;
		LastSignal = "OnStop";
	}

	UFUNCTION()
	private void OnTimerJump(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT, ECk_Timer_JumpDirection InJumpDirection, FCk_Time InJumpAmount)
	{
		JumpCount++;
		LastSignal = "OnJump";
	}

	UFUNCTION()
	private void OnTimerDepleted(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DepletedCount++;
		LastSignal = "OnDepleted";
	}

	// Automation
	UFUNCTION()
	private void OnAutoStep(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CycleStep++;

		switch (CycleStep)
		{
			case 1:
				CurrentPhase = "Pause";
				TestTimer.Request_Pause();
				break;
			case 2:
				CurrentPhase = "Resume";
				TestTimer.Request_Resume();
				break;
			case 3:
				CurrentPhase = "Jump +1s";
				TestTimer.Request_Jump(FCk_Request_Timer_Jump(FCk_Time(1.0f)));
				break;
			case 4:
				CurrentPhase = "Reset";
				TestTimer.Request_Reset();
				TestTimer.Request_Resume();
				break;
			case 5:
				CurrentPhase = "Stop";
				TestTimer.Request_Stop();
				break;
			case 6:
				CurrentPhase = "Resume after stop";
				TestTimer.Request_Resume();
				break;
			case 7:
				CurrentPhase = "Consume 3s";
				TestTimer.Request_Consume(FCk_Request_Timer_Consume(FCk_Time(3.0f)));
				break;
			default:
				// Reset all counters and restart cycle
				CycleStep = 0;
				CurrentPhase = "Cycle restart";
				UpdateCount = 0;
				DoneCount = 0;
				PauseCount = 0;
				ResumeCount = 0;
				ResetCount = 0;
				StopCount = 0;
				JumpCount = 0;
				DepletedCount = 0;
				LastSignal = "(reset)";
				TestTimer.Request_Reset();
				TestTimer.Request_Resume();
				break;
		}
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	FString Get_CheckMark(int32 InCount)
	{
		return (InCount > 0) ? "+" : "-";
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "TIMER SIGNALS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto DisplayText = f"Phase: {CurrentPhase} (Step {CycleStep}/7)\n";
		DisplayText = f"{DisplayText}Last Signal: {LastSignal}\n\n";

		DisplayText = f"{DisplayText}SIGNAL FIRE COUNTS:\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(UpdateCount)}] OnUpdate:   {UpdateCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(DoneCount)}] OnDone:     {DoneCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(PauseCount)}] OnPause:    {PauseCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(ResumeCount)}] OnResume:   {ResumeCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(ResetCount)}] OnReset:    {ResetCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(StopCount)}] OnStop:     {StopCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(JumpCount)}] OnJump:     {JumpCount}\n";
		DisplayText = f"{DisplayText}  [{Get_CheckMark(DepletedCount)}] OnDepleted: {DepletedCount}\n\n";

		auto Chrono = TestTimer.Get_CurrentTimerValue();
		auto State = TestTimer.Get_CurrentState();
		DisplayText = f"{DisplayText}Timer: {Chrono.Conv_ChronoToString()} | State: {State}";

		auto Instructions = "Tests all 8 timer signal bindings.\n"
			+ "Automation cycles through Pause/Resume/Jump/Reset/Stop/Consume\n"
			+ "to trigger each signal type. [+] = fired, [-] = not yet fired.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}
}
