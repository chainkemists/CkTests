class ACk_TransformGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		if (HasAuthority() == false)
		{ return TArray<FCkGym_Station_SpawnParams_Payload>(); }

		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Transform.SetLocation");
			Station.Title = FText::FromString("SET LOCATION");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Teleports entity between square corner positions."));
			Description.Add(FText::FromString("Uses utils_transform::Request_SetLocation() with World space."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Transform.SetRotation");
			Station.Title = FText::FromString("SET ROTATION");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Rotates entity to absolute yaw values (0, 90, 180, 270)."));
			Description.Add(FText::FromString("Uses utils_transform::Request_SetRotation() with World space."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Transform.SetScale");
			Station.Title = FText::FromString("SET SCALE");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Pulses entity scale between 0.5 and 2.0."));
			Description.Add(FText::FromString("Uses utils_transform::Request_SetScale() with World space."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Transform.AddLocationOffset");
			Station.Title = FText::FromString("ADD LOCATION OFFSET");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Entity traces a circular path using relative offsets."));
			Description.Add(FText::FromString("Uses utils_transform::Request_AddLocationOffset() each frame."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Transform.AddRotationOffset");
			Station.Title = FText::FromString("ADD ROTATION OFFSET");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Entity spins continuously with incremental yaw offsets."));
			Description.Add(FText::FromString("Uses utils_transform::Request_AddRotationOffset() each frame."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Transform.DirectionalVectors");
			Station.Title = FText::FromString("DIRECTIONAL VECTORS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Draws Forward (red), Right (green), Up (blue) vectors."));
			Description.Add(FText::FromString("Entity rotates slowly to show vector orientation changes."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		return Stations;
	}

	void Request_StartGym() override
	{
		if (HasAuthority() == false)
		{ return; }

		Request_SpawnCube("Gym.Transform.SetLocation", ECk_TransformGym_Behavior::SetLocation);
		Request_SpawnCube("Gym.Transform.SetRotation", ECk_TransformGym_Behavior::SetRotation);
		Request_SpawnCube("Gym.Transform.SetScale", ECk_TransformGym_Behavior::SetScale);
		Request_SpawnCube("Gym.Transform.AddLocationOffset", ECk_TransformGym_Behavior::AddLocationOffset);
		Request_SpawnCube("Gym.Transform.AddRotationOffset", ECk_TransformGym_Behavior::AddRotationOffset);
		Request_SpawnCube("Gym.Transform.DirectionalVectors", ECk_TransformGym_Behavior::DirectionalVectors);

		ck::Trace("Transform Gym - All features started");
	}

	void Request_SpawnCube(FString InStationTag, ECk_TransformGym_Behavior InBehavior)
	{
		auto StationTransform = Get_StationTransform(InStationTag);

		// Spawn cube actor
		auto SpawnedActor = SpawnActor(ACk_TransformGym_Cube, StationTransform.GetLocation(), FRotator(0, 180, 0), NAME_None, true);
		SpawnedActor.Behavior = InBehavior;
		FinishSpawningActor(SpawnedActor);

		// Spawn display entity script for live station text
		auto DisplayParams = FTransformGym_DisplaySpawnParams();
		DisplayParams.InitialTransform = StationTransform;
		DisplayParams.LinkedCube = SpawnedActor;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InStationTag),
			UCk_EntityScript_TransformGym_Display,
			FInstancedStruct::Make(DisplayParams)
		);
	}

	UFUNCTION(Exec, DisplayName="Transform Gym - Restart All")
	void Ck_GymTransform_RestartAll()
	{
		Request_StartGym();
	}
}
