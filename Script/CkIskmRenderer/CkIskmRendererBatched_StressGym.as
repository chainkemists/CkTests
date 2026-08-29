// Language=angelscript

//============================================================================
// CK ISKM RENDERER - BATCHED STRESS GYM (Moving 600)
//============================================================================
//
// 600 batched GPU-skinned instances, ALL moving (orbiting via Set_CrowdMemberTransform every tick) - the
// worst-case production write path (per-frame in-tile pushes + a steady trickle of cross-tile migrations).
// A/B against "IskmRenderer Stress (Moving 500)" (per-SKMC Plan-1): compare `stat unit`, `stat rhi`,
// `stat scenerendering` - the batched crowd should draw in a handful of instanced calls with no per-instance
// CPU pose evaluation.
//
// Reuses UCk_EntityScript_IskmRendererBatched_MovingCrowd (CkIskmRendererBatched_GymStation.as) with
// Count=600 over a wider area.
//============================================================================

class ACk_IskmRendererBatchedGym_Stress_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_IskmRendererBatchedGym_Stress_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_IskmRendererBatchedGym_Stress_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto S = FCkGym_Station_SpawnParams_Payload();
        S.Tags.Add(n"Gym.IskmBatched.StressMoving");
        S.Title = FText::FromString("Batched Stress (Moving 600)");
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString("600 batched GPU-skinned instances, all orbiting (per-frame member transform writes + tile migrations).\nA/B vs the per-SKMC Stress (Moving 500): `stat unit` / `stat rhi` / `stat scenerendering`."));
        S.Description = Desc;
        Stations.Add(S);
        return Stations;
    }

    void Request_StartGym() override
    {
        SpawnFloor();

        auto Params = FCkIskmBatchedGym_CrowdSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform("Gym.IskmBatched.StressMoving", ECk_GymStation_Anchor::PanelCenter);
        Params.Count = 600;
        Params.AreaExtent = 6000.0f;
        Params.TileSize = 2500.0f;

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.IskmBatched.StressMoving"),
            UCk_EntityScript_IskmRendererBatched_MovingCrowd,
            FInstancedStruct::Make(Params));
    }

    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(160.0, 160.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { return; }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // One row. The crowd is spawned once at start, so re-spawning it IS the only control the gym has.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "ISKM RENDERER: BATCHED STRESS";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Respawn the 600-instance crowd"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_StartGym(); }
    }
}
