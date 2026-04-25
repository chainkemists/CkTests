class ACk_NavigationGym_GameMode : ACk_Gym_Base_GameMode
{
	default PlayerControllerClass = ACk_NavigationGym_PlayerController;
	default DefaultPawnClass = ACk_Gym_Base_Pawn;

	UFUNCTION(BlueprintOverride)
	void BeginPlay()
	{
		// Floor at Z=-300 so gym stations (which spawn around Z=0 with mesh extending below)
		// have clear visual separation. Cube default mesh is 100x100x100cm. Scale (60, 60, 0.5)
		// → 6000x6000x50cm floor — wide enough for any reasonable station spread.
		const auto FloorLocation = FVector(0.0, 0.0, -300.0);
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
		//   1. Open CkGym_AllTests.umap in the editor
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
