//============================================================================
// CUE GYM - PLAYER CONTROLLER
//============================================================================

class ACk_CueGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		// Stations are replicated - only the server should create them
		if (HasAuthority() == false)
		{
			return Stations;
		}

		// Station 1: Lifetime
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Cue.Lifetime");
			Station.Title = FText::FromString("CUE LIFETIME");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests AfterOneFrame, Persistent, Timed, and Custom lifetime behaviors."));
			Description.Add(FText::FromString("Each lifetime type controls when/how a cue entity is destroyed."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 2: Concurrency
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Cue.Concurrency");
			Station.Title = FText::FromString("CUE CONCURRENCY");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Compares AllowMultiple vs RestartExisting concurrency policies."));
			Description.Add(FText::FromString("Left side stacks instances, right side restarts the existing one."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 3: Owner Validation
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Cue.OwnerValidation");
			Station.Title = FText::FromString("CUE OWNER VALIDATION");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests SkipIfInvalid vs RequireValid with valid and invalid owners."));
			Description.Add(FText::FromString("Alternates between valid owner (Phase 1) and invalid owner (Phase 2)."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 4: Restart
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Cue.Restart");
			Station.Title = FText::FromString("CUE RESTART");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests the Restart() method via RestartExisting concurrency policy."));
			Description.Add(FText::FromString("Re-fires every 3s - watch sphere color shift with each restart."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 5: Transient
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Cue.Transient");
			Station.Title = FText::FromString("CUE TRANSIENT");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests cues executed without a persistent owner entity."));
			Description.Add(FText::FromString("Fires cues with FCk_Handle() (invalid) as owner."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 6: Owner Destruction
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Cue.OwnerDestruction");
			Station.Title = FText::FromString("CUE OWNER DESTRUCTION");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests automatic cue cleanup when owning entity is destroyed."));
			Description.Add(FText::FromString("Owner sphere + 3 cue spheres vanish together on owner destruction."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		return Stations;
	}

	void Request_StartGym() override
	{
		// Entity scripts are replicated - only the server should spawn them
		if (HasAuthority() == false)
		{
			return;
		}

		Request_StartLifetime();
		Request_StartConcurrency();
		Request_StartOwnerValidation();
		Request_StartRestart();
		Request_StartTransient();
		Request_StartOwnerDestruction();
		ck::Trace("Cue Gym - All stations started");
	}

	//------------------------------------------------------------------------
	// STATION STARTUP
	//------------------------------------------------------------------------

	void Request_StartLifetime()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Cue.Lifetime", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Cue.Lifetime"),
			UCk_EntityScript_CueGym_Lifetime,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartConcurrency()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Cue.Concurrency", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Cue.Concurrency"),
			UCk_EntityScript_CueGym_Concurrency,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartOwnerValidation()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Cue.OwnerValidation", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Cue.OwnerValidation"),
			UCk_EntityScript_CueGym_OwnerValidation,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartRestart()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Cue.Restart", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Cue.Restart"),
			UCk_EntityScript_CueGym_Restart,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartTransient()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Cue.Transient", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Cue.Transient"),
			UCk_EntityScript_CueGym_Transient,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartOwnerDestruction()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Cue.OwnerDestruction", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Cue.OwnerDestruction"),
			UCk_EntityScript_CueGym_OwnerDestruction,
			FInstancedStruct::Make(SpawnParams));
	}

	//--------------------------------------------------------------------------------------------------------------------------
	// CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
	//
	// Every station in this gym is a one-shot that has to be RE-FIRED to be watched. Restarting was
	// console-only, which made the gym look inert to anyone who arrived after the first pass had run.
	//--------------------------------------------------------------------------------------------------------------------------

	FString Get_ControlPanelTitle() override
	{
		return "CUE";
	}

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();

		Rows.Add(CkGym_Control::Header("RE-FIRE A STATION"));
		Rows.Add(CkGym_Control::Numbered(0, "Lifetime", false));
		Rows.Add(CkGym_Control::Numbered(1, "Concurrency", false));
		Rows.Add(CkGym_Control::Numbered(2, "Owner validation", false));
		Rows.Add(CkGym_Control::Numbered(3, "Restart", false));
		Rows.Add(CkGym_Control::Numbered(4, "Transient", false));
		Rows.Add(CkGym_Control::Numbered(5, "Owner destruction", false));
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-fire every station"));

		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		// Row 0 is the header, which holds no key and never arrives here.
		if (InRowIndex == 1)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_Lifetime");
			Request_StartLifetime();
		}
		else if (InRowIndex == 2)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_Concurrency");
			Request_StartConcurrency();
		}
		else if (InRowIndex == 3)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_OwnerValidation");
			Request_StartOwnerValidation();
		}
		else if (InRowIndex == 4)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_Restart");
			Request_StartRestart();
		}
		else if (InRowIndex == 5)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_Transient");
			Request_StartTransient();
		}
		else if (InRowIndex == 6)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_OwnerDestruction");
			Request_StartOwnerDestruction();
		}
		else if (InRowIndex == 7)
		{
			Request_DestroyStationEntities(n"TAG_CueGym_Lifetime");
			Request_DestroyStationEntities(n"TAG_CueGym_Concurrency");
			Request_DestroyStationEntities(n"TAG_CueGym_OwnerValidation");
			Request_DestroyStationEntities(n"TAG_CueGym_Restart");
			Request_DestroyStationEntities(n"TAG_CueGym_Transient");
			Request_DestroyStationEntities(n"TAG_CueGym_OwnerDestruction");

			Request_StartGym();
		}
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
