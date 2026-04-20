//============================================================================
// ENTITY LIFECYCLE GYM - DESTROY & CALLBACKS
// Tests: utils_entity_lifetime (destroy, batch destroy, OnBeginDestroy)
//============================================================================

class UCk_EntityScript_EntityLifecycleGym_DestroyCallbacks : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Phase tracking
	int32 CurrentPhase = 0;
	int32 CycleCount = 0;

	// Counters
	int32 TotalCreated = 0;
	int32 TotalDestroyed = 0;
	int32 DestroyCallbackCount = 0;

	// Child handles for current cycle
	FCk_Handle ChildA;
	FCk_Handle ChildB;
	FCk_Handle ChildC;

	// Phase timer
	FCk_Handle_Timer PhaseTimer;

	// Self handle stored for use in callbacks
	FCk_Handle SelfHandle;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_LifecycleGym_DestroyCallbacks");

		SelfHandle = InHandle;

		// Display tick
		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"DisplayTick"));

		// Phase timer: 1.5 seconds per phase
		auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
		TimerParams.Set_StartingState(ECk_Timer_State::Running);
		TimerParams.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		PhaseTimer = utils_timer::Add(InHandle, TimerParams);
		PhaseTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPhaseTimerDone"));

		// Start first phase immediately
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
		CurrentPhase = (CurrentPhase + 1) % 4;

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
			// Phase 0: Create 3 children, bind destroy callback to first
			ChildA = utils_entity_lifetime::Request_CreateEntity(SelfHandle);
			utils_handle::Set_DebugName(ChildA, n"DestroyTest_A");
			ChildB = utils_entity_lifetime::Request_CreateEntity(SelfHandle);
			utils_handle::Set_DebugName(ChildB, n"DestroyTest_B");
			ChildC = utils_entity_lifetime::Request_CreateEntity(SelfHandle);
			utils_handle::Set_DebugName(ChildC, n"DestroyTest_C");
			TotalCreated = TotalCreated + 3;

			// Bind destroy callback to ChildA
			utils_entity_lifetime::BindTo_OnBeginDestroy(ChildA,
				FCk_Delegate_OnBeginDestroy(this, n"OnChildBeginDestroy"));
		}
		else if (CurrentPhase == 1)
		{
			// Phase 1: Single destroy - destroy ChildA (should trigger callback)
			if (utils_handle::Get_IsValid(ChildA))
			{
				utils_entity_lifetime::Request_DestroyEntity(ChildA);
				TotalDestroyed = TotalDestroyed + 1;
			}
		}
		else if (CurrentPhase == 2)
		{
			// Phase 2: Batch destroy - destroy ChildB and ChildC
			auto ToDestroy = TArray<FCk_Handle>();
			if (utils_handle::Get_IsValid(ChildB))
			{
				ToDestroy.Add(ChildB);
			}
			if (utils_handle::Get_IsValid(ChildC))
			{
				ToDestroy.Add(ChildC);
			}

			if (ToDestroy.Num() > 0)
			{
				utils_entity_lifetime::Request_DestroyEntities(ToDestroy);
				TotalDestroyed = TotalDestroyed + ToDestroy.Num();
			}
		}
		else if (CurrentPhase == 3)
		{
			// Phase 3: Reset - clear handles for next cycle
			ChildA = utils_handle::Get_InvalidHandle();
			ChildB = utils_handle::Get_InvalidHandle();
			ChildC = utils_handle::Get_InvalidHandle();
		}
	}

	UFUNCTION()
	private void OnChildBeginDestroy(FCk_Handle InHandle)
	{
		DestroyCallbackCount++;
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "DESTROY & CALLBACKS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";

		auto PhaseNames = TArray<FString>();
		PhaseNames.Add("CREATE 3 CHILDREN");
		PhaseNames.Add("SINGLE DESTROY");
		PhaseNames.Add("BATCH DESTROY");
		PhaseNames.Add("RESET");
		auto PhaseName = PhaseNames[CurrentPhase];

		auto D = "";
		D = f"{D}Cycle: {CycleCount}    Phase: {CurrentPhase} ({PhaseName})\n\n";

		D = f"{D}--- Counters ---\n";
		D = f"{D}Total Created:              {TotalCreated}\n";
		D = f"{D}Total Destroyed:            {TotalDestroyed}\n";
		D = f"{D}Destroy Callbacks Fired:    {DestroyCallbackCount}\n\n";

		D = f"{D}--- Validations ---\n";
		auto Pass_CallbacksFired = (DestroyCallbackCount >= CycleCount);
		D = f"{D}" + (Pass_CallbacksFired ? "[+] " : "[-] ") + f"Callbacks fired >= cycles ({DestroyCallbackCount} >= {CycleCount})\n";
		D = f"{D}" + ((TotalCreated >= TotalDestroyed) ? "[+] " : "[-] ") + "Created/Destroyed balanced\n";

		// Progress bar for current phase timer
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

		auto Instructions = "Tests entity destruction, batch destruction,\n"
			+ "and OnBeginDestroy callbacks in automated cycles.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, D, Instructions);
	}
}
