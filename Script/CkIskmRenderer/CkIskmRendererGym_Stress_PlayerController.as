// Language=angelscript

//============================================================================
// CK ISKM RENDERER STRESS GYMS — PlayerControllers
//============================================================================
//
// Two PCs that differ only by the Moving flag they pass to the shared
// UCk_EntityScript_IskmRendererGym_StressArmy. Both register one station,
// spawn the standard 4000x4000 floor (per CkIskmRenderer_GymPlayerController's
// SpawnFloor pattern), and use the same station tag (Gym.Iskm.StressArmy).
//
//============================================================================

class ACk_IskmRendererGym_StressStatic_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto S = FCkGym_Station_SpawnParams_Payload();
        S.Tags.Add(n"Gym.Iskm.StressArmy");
        S.Title = FText::FromString("Stress Army (Static 500)");
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString("500 Iskm proxies, varied locomotion sequences, stationary.\nStresses renderer throughput. Use `stat unit` / `stat gpu`."));
        S.Description = Desc;
        Stations.Add(S);
        return Stations;
    }

    void Request_StartGym() override
    {
        SpawnFloor();
        SpawnStressStation(false);
    }

    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(40.0, 40.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { return; }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    private void SpawnStressStation(bool InMoving)
    {
        auto Params = FCkIskmRenderer_GymStationSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform("Gym.Iskm.StressArmy", ECk_GymStation_Anchor::PanelCenter);
        Params.Count  = 500;
        Params.Moving = InMoving;

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Iskm.StressArmy"),
            UCk_EntityScript_IskmRendererGym_StressArmy,
            FInstancedStruct::Make(Params));
    }

    UFUNCTION(Exec, DisplayName="IskmRenderer Stress (Static 500) - Restart")
    void Ck_GymIskmRendererStressStatic_Restart()
    {
        Request_StartGym();
    }
}

class ACk_IskmRendererGym_StressMoving_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto S = FCkGym_Station_SpawnParams_Payload();
        S.Tags.Add(n"Gym.Iskm.StressArmy");
        S.Title = FText::FromString("Stress Army (Moving 500)");
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString("500 Iskm proxies, walk/jog sequences, each orbiting its spawn cell via per-tick entity-transform updates.\nStresses renderer + proxy UpdateTransform path. Use `stat unit` / `stat gpu`."));
        S.Description = Desc;
        Stations.Add(S);
        return Stations;
    }

    void Request_StartGym() override
    {
        SpawnFloor();
        SpawnStressStation(true);
    }

    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(40.0, 40.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { return; }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    private void SpawnStressStation(bool InMoving)
    {
        auto Params = FCkIskmRenderer_GymStationSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform("Gym.Iskm.StressArmy", ECk_GymStation_Anchor::PanelCenter);
        Params.Count  = 500;
        Params.Moving = InMoving;

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Iskm.StressArmy"),
            UCk_EntityScript_IskmRendererGym_StressArmy,
            FInstancedStruct::Make(Params));
    }

    UFUNCTION(Exec, DisplayName="IskmRenderer Stress (Moving 500) - Restart")
    void Ck_GymIskmRendererStressMoving_Restart()
    {
        Request_StartGym();
    }
}
