class ACk_SceneNodeGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		if (HasAuthority() == false)
		{ return TArray<FCkGym_Station_SpawnParams_Payload>(); }

		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.SceneNode.ParentChild");
			Station.Title = FText::FromString("PARENT-CHILD");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Child scene node orbits around a parent entity."));
			Description.Add(FText::FromString("Uses utils_scene_node::Create() and Request_UpdateOffset_Location()."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.SceneNode.OffsetUpdates");
			Station.Title = FText::FromString("OFFSET UPDATES");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Animates location, rotation, and scale offsets on a child node."));
			Description.Add(FText::FromString("Uses Request_UpdateOffset_Location/Rotation/Scale()."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.SceneNode.MultipleChildren");
			Station.Title = FText::FromString("MULTIPLE CHILDREN");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Parent rotates with 4 children at fixed offsets."));
			Description.Add(FText::FromString("Children follow parent automatically via hierarchy."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.SceneNode.Hierarchy");
			Station.Title = FText::FromString("HIERARCHY");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Nested chain: root -> child -> grandchild (3 levels)."));
			Description.Add(FText::FromString("Shows compounding transforms through the hierarchy."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.SceneNode.PropagateOnly");
			Station.Title = FText::FromString("PROPAGATE ONLY");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Solar system: only the root rotates."));
			Description.Add(FText::FromString("Planet + moon have fixed local offsets and no per-frame updates."));
			Description.Add(FText::FromString("Isolates whether scene-node propagation alone moves descendants."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.SceneNode.AnchorOffset");
			Station.Title = FText::FromString("ANCHOR OFFSET");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("SceneNode follows a moving Unreal mesh component at a relative offset."));
			Description.Add(FText::FromString("Uses CreateAndAttachToUnrealComponent(offset) + runtime Request_UpdateOffset."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		return Stations;
	}

	void Request_StartGym() override
	{
		if (HasAuthority() == false)
		{ return; }

		Request_SpawnCube("Gym.SceneNode.ParentChild", ECk_SceneNodeGym_Behavior::ParentChild);
		Request_SpawnCube("Gym.SceneNode.OffsetUpdates", ECk_SceneNodeGym_Behavior::OffsetUpdates);
		Request_SpawnCube("Gym.SceneNode.MultipleChildren", ECk_SceneNodeGym_Behavior::MultipleChildren);
		Request_SpawnCube("Gym.SceneNode.Hierarchy", ECk_SceneNodeGym_Behavior::Hierarchy);
		Request_SpawnCube("Gym.SceneNode.PropagateOnly", ECk_SceneNodeGym_Behavior::PropagateOnly);
		Request_SpawnCube("Gym.SceneNode.AnchorOffset", ECk_SceneNodeGym_Behavior::AnchorOffset);

		ck::Trace("Scene Node Gym - All features started");
	}

	void Request_SpawnCube(FString InStationTag, ECk_SceneNodeGym_Behavior InBehavior)
	{
		auto StationTransform = Get_StationAnchorTransform(InStationTag, ECk_GymStation_Anchor::PanelCenter);

		// Spawn cube actor
		auto SpawnedActor = SpawnActor(ACk_SceneNodeGym_Cube, StationTransform.GetLocation(), FRotator(0, 180, 0), NAME_None, true);
		SpawnedActor.Behavior = InBehavior;
		FinishSpawningActor(SpawnedActor);

		// Spawn display entity script for live station text
		auto DisplayParams = FSceneNodeGym_DisplaySpawnParams();
		DisplayParams.InitialTransform = StationTransform;
		DisplayParams.LinkedCube = SpawnedActor;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InStationTag),
			UCk_EntityScript_SceneNodeGym_Display,
			FInstancedStruct::Make(DisplayParams)
		);
	}

	//--------------------------------------------------------------------------------------------------------------------------
	// CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
	//
	// One row. Everything here plays once and is then over, so re-running it IS the gym - and the console
	// command's name was the only documentation that the control existed at all.
	//--------------------------------------------------------------------------------------------------------------------------

	FString Get_ControlPanelTitle() override
	{
		return "SCENE NODE";
	}

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-run every station"));
		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		if (InRowIndex == 0) { Ck_GymSceneNode_RestartAll(); }
	}

	UFUNCTION(Exec, DisplayName="Scene Node Gym - Restart All")
	void Ck_GymSceneNode_RestartAll()
	{
		Request_StartGym();
	}
}
