//============================================================================
// ENTITY LIFECYCLE GYM - PLAYER CONTROLLER
//============================================================================

class ACk_EntityLifecycleGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		// Station 1: Handle & Entity Basics
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.HandleAndEntity");
			Station.Title = FText::FromString("HANDLE & ENTITY BASICS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests handle validity, debug names, entity decomposition,"));
			Description.Add(FText::FromString("comparison, and string conversion."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 2: Ownership Tree
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.OwnershipTree");
			Station.Title = FText::FromString("OWNERSHIP TREE");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Creates parent-child entity hierarchy and queries"));
			Description.Add(FText::FromString("ownership relationships, dependents, and transient state."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 3: Destroy & Callbacks
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.DestroyCallbacks");
			Station.Title = FText::FromString("DESTROY & CALLBACKS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests entity destruction, batch destruction,"));
			Description.Add(FText::FromString("and OnBeginDestroy callbacks in automated cycles."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 4: Actor Bridge
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.ActorBridge");
			Station.Title = FText::FromString("ACTOR BRIDGE");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests actor-to-entity handle roundtrip, recursive actor lookup,"));
			Description.Add(FText::FromString("ECS readiness, and replication status."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 5: Entity Tags
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.TagSystem");
			Station.Title = FText::FromString("ENTITY TAGS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests adding, querying, removing, and searching"));
			Description.Add(FText::FromString("by entity tags in automated cycles."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 6: Deferred Entity
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.DeferredSetup");
			Station.Title = FText::FromString("DEFERRED ENTITY");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests deferred entity creation, pending state queries,"));
			Description.Add(FText::FromString("setup completion, and completion callbacks."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 7: Script Spawn & Cast
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.EntityLifecycle.ScriptSpawnCast");
			Station.Title = FText::FromString("SCRIPT SPAWN & CAST");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Tests entity script spawning, construction callbacks,"));
			Description.Add(FText::FromString("type queries, and handle casting."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		return Stations;
	}

	void Request_StartGym() override
	{
		Request_StartHandleAndEntity();
		Request_StartOwnershipTree();
		Request_StartDestroyCallbacks();
		Request_StartActorBridge();
		Request_StartTagSystem();
		Request_StartDeferredSetup();
		Request_StartScriptSpawnCast();
		ck::Trace("Entity Lifecycle Gym - All stations started");
	}

	//------------------------------------------------------------------------
	// STATION STARTUP
	//------------------------------------------------------------------------

	void Request_StartHandleAndEntity()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.HandleAndEntity", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.HandleAndEntity"),
			UCk_EntityScript_EntityLifecycleGym_HandleAndEntity,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartOwnershipTree()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.OwnershipTree", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.OwnershipTree"),
			UCk_EntityScript_EntityLifecycleGym_OwnershipTree,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartDestroyCallbacks()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.DestroyCallbacks", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.DestroyCallbacks"),
			UCk_EntityScript_EntityLifecycleGym_DestroyCallbacks,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartActorBridge()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.ActorBridge", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.ActorBridge"),
			UCk_EntityScript_EntityLifecycleGym_ActorBridge,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartTagSystem()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.TagSystem", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.TagSystem"),
			UCk_EntityScript_EntityLifecycleGym_TagSystem,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartDeferredSetup()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.DeferredSetup", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.DeferredSetup"),
			UCk_EntityScript_EntityLifecycleGym_DeferredSetup,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartScriptSpawnCast()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.EntityLifecycle.ScriptSpawnCast", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.EntityLifecycle.ScriptSpawnCast"),
			UCk_EntityScript_EntityLifecycleGym_ScriptSpawnCast,
			FInstancedStruct::Make(SpawnParams));
	}

	//------------------------------------------------------------------------
	// CONSOLE COMMANDS
	//------------------------------------------------------------------------

	//--------------------------------------------------------------------------------------------------------------------------
	// CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
	//
	// Every station here demonstrates something that HAPPENS and is then over — a destroy callback, a
	// deferred setup, a bridge teardown. Re-running one was console-only, which made the gym look inert to
	// anyone who arrived after the first pass.
	//--------------------------------------------------------------------------------------------------------------------------

	FString Get_ControlPanelTitle() override
	{
		return "ENTITY LIFECYCLE";
	}

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();

		Rows.Add(CkGym_Control::Header("RE-RUN A STATION"));
		Rows.Add(CkGym_Control::Numbered(0, "Handle & entity", false));
		Rows.Add(CkGym_Control::Numbered(1, "Ownership tree", false));
		Rows.Add(CkGym_Control::Numbered(2, "Destroy callbacks", false));
		Rows.Add(CkGym_Control::Numbered(3, "Actor bridge", false));
		Rows.Add(CkGym_Control::Numbered(4, "Tag system", false));
		Rows.Add(CkGym_Control::Numbered(5, "Deferred setup", false));
		Rows.Add(CkGym_Control::Numbered(6, "Script spawn cast", false));
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-run every station"));

		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		// Row 0 is the header, which holds no key and never arrives here.
		if (InRowIndex == 1) { Ck_GymEntityLifecycle_RestartHandleAndEntity(); }
		else if (InRowIndex == 2) { Ck_GymEntityLifecycle_RestartOwnershipTree(); }
		else if (InRowIndex == 3) { Ck_GymEntityLifecycle_RestartDestroyCallbacks(); }
		else if (InRowIndex == 4) { Ck_GymEntityLifecycle_RestartActorBridge(); }
		else if (InRowIndex == 5) { Ck_GymEntityLifecycle_RestartTagSystem(); }
		else if (InRowIndex == 6) { Ck_GymEntityLifecycle_RestartDeferredSetup(); }
		else if (InRowIndex == 7) { Ck_GymEntityLifecycle_RestartScriptSpawnCast(); }
		else if (InRowIndex == 8) { Ck_GymEntityLifecycle_ResetAll(); }
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Handle & Entity")
	void Ck_GymEntityLifecycle_RestartHandleAndEntity()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_HandleAndEntity");
		Request_StartHandleAndEntity();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Ownership Tree")
	void Ck_GymEntityLifecycle_RestartOwnershipTree()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_OwnershipTree");
		Request_StartOwnershipTree();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Destroy Callbacks")
	void Ck_GymEntityLifecycle_RestartDestroyCallbacks()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_DestroyCallbacks");
		Request_StartDestroyCallbacks();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Actor Bridge")
	void Ck_GymEntityLifecycle_RestartActorBridge()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_ActorBridge");
		Request_StartActorBridge();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Tag System")
	void Ck_GymEntityLifecycle_RestartTagSystem()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_TagSystem");
		Request_StartTagSystem();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Deferred Setup")
	void Ck_GymEntityLifecycle_RestartDeferredSetup()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_DeferredSetup");
		Request_StartDeferredSetup();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Restart Script Spawn Cast")
	void Ck_GymEntityLifecycle_RestartScriptSpawnCast()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_ScriptSpawnCast");
		Request_StartScriptSpawnCast();
	}

	UFUNCTION(Exec, DisplayName="EntityLifecycle Gym - Reset All")
	void Ck_GymEntityLifecycle_ResetAll()
	{
		Request_DestroyStationEntities(n"TAG_LifecycleGym_HandleAndEntity");
		Request_DestroyStationEntities(n"TAG_LifecycleGym_OwnershipTree");
		Request_DestroyStationEntities(n"TAG_LifecycleGym_DestroyCallbacks");
		Request_DestroyStationEntities(n"TAG_LifecycleGym_ActorBridge");
		Request_DestroyStationEntities(n"TAG_LifecycleGym_TagSystem");
		Request_DestroyStationEntities(n"TAG_LifecycleGym_DeferredSetup");
		Request_DestroyStationEntities(n"TAG_LifecycleGym_ScriptSpawnCast");

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
