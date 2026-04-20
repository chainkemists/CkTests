//============================================================================
// ENTITY LIFECYCLE GYM - DEFERRED ENTITY
// Tests: utils_deferred_entity
//============================================================================

class UCk_EntityScript_EntityLifecycleGym_DeferredSetup : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Phase tracking
	int32 CurrentPhase = 0;
	int32 CycleCount = 0;

	// Test results
	bool Pass_Create = false;
	bool Pass_IsDeferred = false;
	bool Pass_HasDeferred = false;
	bool Pass_PendingCount = false;
	bool Pass_CompleteSetup = false;
	bool Pass_SetupCompleteCallback = false;
	bool Pass_FullyCompleteCallback = false;
	bool Pass_DoCast = false;

	// Display values
	int32 PendingCount = 0;
	bool SetupCompleteCallbackFired = false;
	bool FullyCompleteCallbackFired = false;

	// Deferred entity handle
	FCk_Handle_DeferredEntity DeferredHandle;
	FCk_Handle SelfHandle;

	// Phase timer
	FCk_Handle_Timer PhaseTimer;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_LifecycleGym_DeferredSetup");

		SelfHandle = InHandle;

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Phase timer: 2 seconds per phase
		auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0f));
		TimerParams.Set_StartingState(ECk_Timer_State::Running);
		TimerParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		PhaseTimer = utils_timer::Add(InHandle, TimerParams);
		PhaseTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPhaseTimerDone"));

		// Start first phase
		Request_ExecutePhase();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnPhaseTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		CurrentPhase = (CurrentPhase + 1) % 3;

		if (CurrentPhase == 0)
		{
			CycleCount++;
		}

		Request_ExecutePhase();
	}

	void Request_ExecutePhase()
	{
		if (CurrentPhase == 0)
		{
			// Phase 0: Create deferred entity, query state, bind callbacks
			SetupCompleteCallbackFired = false;
			FullyCompleteCallbackFired = false;

			DeferredHandle = utils_deferred_entity::Create(SelfHandle);
			Pass_Create = DeferredHandle.IsValid();

			// Check if deferred
			Pass_IsDeferred = utils_deferred_entity::Get_IsDeferred(DeferredHandle);

			// Check Has
			auto DeferredAsHandle = FCk_Handle(DeferredHandle);
			Pass_HasDeferred = utils_deferred_entity::Has(DeferredAsHandle);

			// Query pending count
			PendingCount = utils_deferred_entity::Get_PendingCount(DeferredHandle);
			Pass_PendingCount = true;

			// Bind callbacks
			utils_deferred_entity::BindTo_OnSetupComplete(DeferredHandle,
				FCk_Delegate_DeferredEntity_OnComplete(this, n"OnSetupComplete"));
			utils_deferred_entity::BindTo_OnFullyComplete(DeferredHandle,
				FCk_Delegate_DeferredEntity_OnFullyComplete(this, n"OnFullyComplete"));

			// Test DoCast
			auto CastResult = utils_deferred_entity::DoCast(DeferredAsHandle);
			Pass_DoCast = CastResult.IsSet();
		}
		else if (CurrentPhase == 1)
		{
			// Phase 1: Complete setup
			utils_deferred_entity::Request_CompleteSetup(DeferredHandle);
			Pass_CompleteSetup = true;
		}
		else if (CurrentPhase == 2)
		{
			// Phase 2: Check callback results, cleanup
			Pass_SetupCompleteCallback = SetupCompleteCallbackFired;
			Pass_FullyCompleteCallback = FullyCompleteCallbackFired;

			// Destroy the deferred entity's underlying entity
			auto DeferredAsHandle = FCk_Handle(DeferredHandle);
			if (utils_handle::Get_IsValid(DeferredAsHandle))
			{
				utils_entity_lifetime::Request_DestroyEntity(DeferredAsHandle);
			}
		}
	}

	UFUNCTION()
	private void OnSetupComplete(FCk_Handle_DeferredEntity InDeferredEntity)
	{
		SetupCompleteCallbackFired = true;
	}

	UFUNCTION()
	private void OnFullyComplete(FCk_Handle_DeferredEntity InDeferredEntity)
	{
		FullyCompleteCallbackFired = true;
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "DEFERRED ENTITY (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto PhaseNames = TArray<FString>();
		PhaseNames.Add("CREATE & QUERY");
		PhaseNames.Add("COMPLETE SETUP");
		PhaseNames.Add("CHECK CALLBACKS");
		auto PhaseName = PhaseNames[CurrentPhase];

		auto D = "";
		D = f"{D}Cycle: {CycleCount}    Phase: {CurrentPhase} ({PhaseName})\n\n";

		D = f"{D}--- Creation ---\n";
		D = f"{D}" + (Pass_Create ? "[+] " : "[-] ") + "Create deferred entity\n";
		D = f"{D}" + (Pass_IsDeferred ? "[+] " : "[-] ") + "Get_IsDeferred = true\n";
		D = f"{D}" + (Pass_HasDeferred ? "[+] " : "[-] ") + "Has(deferred) = true\n";
		D = f"{D}" + (Pass_DoCast ? "[+] " : "[-] ") + "DoCast succeeded\n";
		D = f"{D}    Pending count: {PendingCount}\n\n";

		D = f"{D}--- Completion ---\n";
		D = f"{D}" + (Pass_CompleteSetup ? "[+] " : "[-] ") + "Request_CompleteSetup\n";
		D = f"{D}" + (Pass_SetupCompleteCallback ? "[+] " : "[-] ") + "OnSetupComplete fired\n";
		D = f"{D}" + (Pass_FullyCompleteCallback ? "[+] " : "[-] ") + "OnFullyComplete fired\n";

		// Progress bar
		auto Chrono = PhaseTimer.Get_CurrentTimerValue();
		auto Goal = FCk_Time();
		auto Elapsed = FCk_Time();
		auto Remaining = FCk_Time();
		Chrono.Break_Chrono(Goal, Elapsed, Remaining);
		auto ElapsedMs = Elapsed.Get_Milliseconds();
		auto GoalMs = Goal.Get_Milliseconds();
		auto Ratio = (GoalMs > 0.0) ? float32(ElapsedMs / GoalMs) : 0.0f;
		auto ProgressBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(Ratio), 25, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
		D = f"{D}\n[{ProgressBar}]";

		auto AllPassed = Pass_Create && Pass_IsDeferred && Pass_HasDeferred
			&& Pass_DoCast && Pass_CompleteSetup
			&& Pass_SetupCompleteCallback && Pass_FullyCompleteCallback;

		D = f"{D}\n\nRESULT: " + (AllPassed ? "ALL TESTS PASSED" : (CycleCount > 0 ? "SOME TESTS FAILED" : "RUNNING..."));

		auto Instructions = "Tests deferred entity creation, pending state queries,\n"
			+ "setup completion, and completion callbacks.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, D, Instructions);
	}
}
