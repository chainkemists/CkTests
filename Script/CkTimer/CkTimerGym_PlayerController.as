//============================================================================
// TIMER GYM - PLAYER CONTROLLER
//============================================================================

class ACk_TimerGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		// Station 1: Basics
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Timer.Basics");
			Station.Title = FText::FromString("TIMER BASICS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Demonstrates timer creation and chrono querying."));
			Description.Add(FText::FromString("Shows state, elapsed/remaining, progress bar, and IsDone flag."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 2: Behaviors
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Timer.Behaviors");
			Station.Title = FText::FromString("TIMER BEHAVIORS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Compares ResetOnDone, PauseOnDone, and StopOnDone behaviors."));
			Description.Add(FText::FromString("Three timers run side-by-side showing different completion behavior."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 3: Signals
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Timer.Signals");
			Station.Title = FText::FromString("TIMER SIGNALS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests all 8 timer signals: OnUpdate, OnDone, OnPause, OnResume,"));
			Description.Add(FText::FromString("OnReset, OnStop, OnJump, OnDepleted."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 4: Control
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Timer.Control");
			Station.Title = FText::FromString("TIMER RUNTIME CONTROL");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests Pause, Resume, Stop, Reset, Complete, Jump, and ReverseDirection."));
			Description.Add(FText::FromString("Watch the progress bar respond to each control action."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 5: Countdown
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Timer.Countdown");
			Station.Title = FText::FromString("TIMER COUNTDOWN");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests CountDown direction with different behaviors."));
			Description.Add(FText::FromString("Includes a consume demo that subtracts time until OnDepleted fires."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		return Stations;
	}

	void Request_StartGym() override
	{
		Request_StartBasics();
		Request_StartBehaviors();
		Request_StartSignals();
		Request_StartControl();
		Request_StartCountdown();
		ck::Trace("✅ Timer Gym - All stations started");
	}

	//------------------------------------------------------------------------
	// STATION STARTUP
	//------------------------------------------------------------------------

	void Request_StartBasics()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Timer.Basics", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Timer.Basics"),
			UCk_EntityScript_TimerGym_Basics,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartBehaviors()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Timer.Behaviors", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Timer.Behaviors"),
			UCk_EntityScript_TimerGym_Behaviors,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartSignals()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Timer.Signals", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Timer.Signals"),
			UCk_EntityScript_TimerGym_Signals,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartControl()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Timer.Control", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Timer.Control"),
			UCk_EntityScript_TimerGym_Control,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartCountdown()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Timer.Countdown", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Timer.Countdown"),
			UCk_EntityScript_TimerGym_Countdown,
			FInstancedStruct::Make(SpawnParams));
	}

	//------------------------------------------------------------------------
	// CONSOLE COMMANDS
	//------------------------------------------------------------------------

	//--------------------------------------------------------------------------------------------------------------------------
	// CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
	//
	// Every station in this gym has to be RE-RUN to be watched — a timer that already finished shows
	// nothing. Restarting was console-only, which made the gym look inert to anyone who arrived after the
	// first pass had completed.
	//--------------------------------------------------------------------------------------------------------------------------

	FString Get_ControlPanelTitle() override
	{
		return "TIMER";
	}

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();

		Rows.Add(CkGym_Control::Header("RE-RUN A STATION"));
		Rows.Add(CkGym_Control::Numbered(0, "Basics", false));
		Rows.Add(CkGym_Control::Numbered(1, "Behaviors", false));
		Rows.Add(CkGym_Control::Numbered(2, "Signals", false));
		Rows.Add(CkGym_Control::Numbered(3, "Control", false));
		Rows.Add(CkGym_Control::Numbered(4, "Countdown", false));
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-run every station"));

		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		// Row 0 is the header, which holds no key and never arrives here.
		if (InRowIndex == 1) { Ck_GymTimer_RestartBasics(); }
		else if (InRowIndex == 2) { Ck_GymTimer_RestartBehaviors(); }
		else if (InRowIndex == 3) { Ck_GymTimer_RestartSignals(); }
		else if (InRowIndex == 4) { Ck_GymTimer_RestartControl(); }
		else if (InRowIndex == 5) { Ck_GymTimer_RestartCountdown(); }
		else if (InRowIndex == 6) { Ck_GymTimer_ResetAll(); }
	}

	UFUNCTION(Exec, DisplayName="Timer Gym - Restart Basics")
	void Ck_GymTimer_RestartBasics()
	{
		Request_DestroyStationEntities(n"TAG_TimerGym_Basics");
		Request_StartBasics();
	}

	UFUNCTION(Exec, DisplayName="Timer Gym - Restart Behaviors")
	void Ck_GymTimer_RestartBehaviors()
	{
		Request_DestroyStationEntities(n"TAG_TimerGym_Behaviors");
		Request_StartBehaviors();
	}

	UFUNCTION(Exec, DisplayName="Timer Gym - Restart Signals")
	void Ck_GymTimer_RestartSignals()
	{
		Request_DestroyStationEntities(n"TAG_TimerGym_Signals");
		Request_StartSignals();
	}

	UFUNCTION(Exec, DisplayName="Timer Gym - Restart Control")
	void Ck_GymTimer_RestartControl()
	{
		Request_DestroyStationEntities(n"TAG_TimerGym_Control");
		Request_StartControl();
	}

	UFUNCTION(Exec, DisplayName="Timer Gym - Restart Countdown")
	void Ck_GymTimer_RestartCountdown()
	{
		Request_DestroyStationEntities(n"TAG_TimerGym_Countdown");
		Request_StartCountdown();
	}

	UFUNCTION(Exec, DisplayName="Timer Gym - Reset All")
	void Ck_GymTimer_ResetAll()
	{
		Request_DestroyStationEntities(n"TAG_TimerGym_Basics");
		Request_DestroyStationEntities(n"TAG_TimerGym_Behaviors");
		Request_DestroyStationEntities(n"TAG_TimerGym_Signals");
		Request_DestroyStationEntities(n"TAG_TimerGym_Control");
		Request_DestroyStationEntities(n"TAG_TimerGym_Countdown");

		Request_StartGym();
	}

	//------------------------------------------------------------------------
	// UTILITY
	//------------------------------------------------------------------------

	void Request_DestroyStationEntities(FName InTag)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
		for (auto Entity : Entities)
		{
			utils_entity_lifetime::Request_DestroyEntity(Entity);
		}
	}
}
