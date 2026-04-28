class ACk_UnrealComponentGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		if (HasAuthority() == false)
		{ return TArray<FCkGym_Station_SpawnParams_Payload>(); }

		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		Stations.Add(MakeStation(n"Gym.UnrealComponent.StaticMesh", "STATIC MESH",
			"Attaches a UStaticMeshComponent (engine cube) to an ECS entity.",
			"Component is registered against the ComponentHost subsystem."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.PointLight", "POINT LIGHT",
			"Attaches a UPointLightComponent that orbits around the station.",
			"Demonstrates lit-component lifecycle without an AActor owner."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.SpotLight", "SPOT LIGHT",
			"Attaches a USpotLightComponent and steers it via entity rotation.",
			"PushTransform processor drives the component's world transform."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.TextRender", "TEXT RENDER",
			"Attaches a UTextRenderComponent that orbits and rotates with the entity.",
			"Demonstrates a non-light scene component reacting to transform updates."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.Arrow", "ARROW",
			"Attaches a UArrowComponent (debug visual) following the entity.",
			"Useful for visualising entity facing without a mesh."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.Box", "BOX",
			"Attaches a UBoxComponent (collision shape) to the entity.",
			"Demonstrates a query-only collider with no actor owner."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.Sphere", "SPHERE",
			"Attaches a USphereComponent (collision shape) to the entity.",
			"Sphere radius is set in the OnAdded callback."));

		Stations.Add(MakeStation(n"Gym.UnrealComponent.Capsule", "CAPSULE",
			"Attaches a UCapsuleComponent (collision shape) to the entity.",
			"Capsule dimensions set in OnAdded; visible thanks to SetHiddenInGame(false)."));

		return Stations;
	}

	private FCkGym_Station_SpawnParams_Payload MakeStation(FName InTag, FString InTitle, FString InLine1, FString InLine2)
	{
		auto Station = FCkGym_Station_SpawnParams_Payload();
		Station.Tags.Add(InTag);
		Station.Title = FText::FromString(InTitle);
		auto Description = TArray<FText>();
		Description.Add(FText::FromString(InLine1));
		Description.Add(FText::FromString(InLine2));
		Station.Description = Description;
		return Station;
	}

	void Request_StartGym() override
	{
		if (HasAuthority() == false)
		{ return; }

		Request_SpawnDriver("Gym.UnrealComponent.StaticMesh", ECk_UnrealComponentGym_Type::StaticMesh);
		Request_SpawnDriver("Gym.UnrealComponent.PointLight", ECk_UnrealComponentGym_Type::PointLight);
		Request_SpawnDriver("Gym.UnrealComponent.SpotLight",  ECk_UnrealComponentGym_Type::SpotLight);
		Request_SpawnDriver("Gym.UnrealComponent.TextRender", ECk_UnrealComponentGym_Type::TextRender);
		Request_SpawnDriver("Gym.UnrealComponent.Arrow",      ECk_UnrealComponentGym_Type::Arrow);
		Request_SpawnDriver("Gym.UnrealComponent.Box",        ECk_UnrealComponentGym_Type::Box);
		Request_SpawnDriver("Gym.UnrealComponent.Sphere",     ECk_UnrealComponentGym_Type::Sphere);
		Request_SpawnDriver("Gym.UnrealComponent.Capsule",    ECk_UnrealComponentGym_Type::Capsule);

		ck::Trace("UnrealComponent Gym - All stations started");
	}

	void Request_SpawnDriver(FString InStationTag, ECk_UnrealComponentGym_Type InType)
	{
		auto StationTransform = Get_StationAnchorTransform(InStationTag, ECk_GymStation_Anchor::PanelCenter);

		auto SpawnedActor = SpawnActor(ACk_UnrealComponentGym_Driver, StationTransform.GetLocation(), FRotator(0, 180, 0), NAME_None, true);
		SpawnedActor.ComponentType = InType;
		FinishSpawningActor(SpawnedActor);

		auto DisplayParams = FUnrealComponentGym_DisplaySpawnParams();
		DisplayParams.InitialTransform = StationTransform;
		DisplayParams.LinkedDriver = SpawnedActor;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InStationTag),
			UCk_EntityScript_UnrealComponentGym_Display,
			FInstancedStruct::Make(DisplayParams)
		);
	}

	UFUNCTION(Exec, DisplayName="UnrealComponent Gym - Restart All")
	void Ck_GymUnrealComponent_RestartAll()
	{
		Request_StartGym();
	}
}
