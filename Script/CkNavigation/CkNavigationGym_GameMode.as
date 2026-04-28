class ACk_NavigationGym_GameMode : ACk_Gym_Base_GameMode
{
	default PlayerControllerClass = ACk_NavigationGym_PlayerController;
	default DefaultPawnClass = ACk_Gym_Base_Pawn;

	UFUNCTION(BlueprintOverride)
	void BeginPlay()
	{
		// Floor positioned so its TOP face lines up with Z=0 — this is what
		// the navmesh bakes onto, and what agents spawned at Z=0 stand on. The
		// cube default mesh is 100x100x100cm with a centered pivot, so at
		// scale.Z=0.5 the floor is 50cm thick (extent ±25cm). Pulling the
		// actor down by 25cm puts the top face exactly at Z=0; otherwise
		// agents sit 25cm inside the mesh and debug arrows clip through it.
		// Plan footprint stays large (6000x6000cm) for any reasonable spread.
		const auto FloorLocation = FVector(0.0, 0.0, -25.0);
		auto Floor = SpawnActor(ACk_NavigationGym_Floor, FloorLocation, FRotator());
		if (Floor != nullptr)
		{
			Floor.SetActorScale3D(FVector(60.0, 60.0, 0.5));
			Print(f"[NavigationGym] Spawned floor at {FloorLocation}");
		}
		else
		{
			Print("[NavigationGym] FAILED to spawn floor");
		}

		// NOTE: Navmesh bounds + bake are NOT spawned from script. UE's runtime nav system is
		// designed for incremental updates to a PRE-BAKED navmesh — baking from zero in a Game
		// world via a code-spawned NavMeshBoundsVolume produces a 0-sized navmesh (verified
		// empirically). The standard workflow is:
		//
		//   1. Open TestGyms_CkTests_Level.umap in the editor
		//   2. Drag a NavMeshBoundsVolume from the Place Actors panel into the level, scale
		//      it to cover ~7000x7000x1200 cm centered at origin
		//   3. Press P (or Build → Build Paths) to bake
		//   4. Save the level
		//
		// After that, this gym's path requests will succeed. Until then the gym exercises the
		// failure path (Status: FAILED) which is itself a valid test scenario.
		Print("[NavigationGym] To enable READY-status paths in this gym, place a NavMeshBoundsVolume in the level (see CkNavigationGym_GameMode.as comment)");
	}
};
