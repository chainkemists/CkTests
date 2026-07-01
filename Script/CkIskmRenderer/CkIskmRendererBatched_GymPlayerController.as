// Language=angelscript

//============================================================================
// CK ISKM RENDERER — BATCHED GYM (Plan-2 dedicated)
//============================================================================
//
// A dedicated, uncluttered gym for the batched GPU-skinned crowd renderer, so it
// can be exercised in isolation — occlusion, per-instance culling, A/B perf, and
// the GPU<->per-SKMC distance-LOD flip — without the 8-station IskmRenderer gym
// crowding the view.
//
// Stations:
//   - Crowd: a large batched GPU-skinned crowd (GPUScene cluster proxies, per-instance
//            looping animation + per-instance occlusion culling).
//   - Flip:  the instances closest to the player flip from batched-GPU rendering to a
//            real per-SKMC proxy (Plan-1) for ragdoll/montage, then back — distance-LOD
//            routing (Phase 5).
//============================================================================

class ACk_IskmRendererBatchedGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.IskmBatched.Crowd", "Batched Crowd",
            "A large GPU-skinned crowd rendered through GPUScene cluster proxies: per-instance looping\nanimation + per-instance occlusion culling. Use `stat rhi` / `stat scenerendering` for draw calls, `stat unit` for frame time."));

        Stations.Add(MakeStationPayload(n"Gym.IskmBatched.Flip", "GPU <-> SKMC Flip",
            "A batched crowd where the instances nearest the player flip to real per-SKMC proxies (Plan-1)\nso they can ragdoll and play montages, then flip back to batched when you walk away. Distance-LOD routing."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        return Station;
    }

    void Request_StartGym() override
    {
        SpawnFloor();

        SpawnStation("Gym.IskmBatched.Crowd", UCk_EntityScript_IskmRendererBatched_Crowd);
        SpawnStation("Gym.IskmBatched.Flip",  UCk_EntityScript_IskmRendererBatched_Flip);
    }

    // Larger floor than the multi-station gym: the crowd + flip stations spread wide.
    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(60.0, 60.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { return; }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    private void SpawnStation(FString InTag, TSubclassOf<UCk_EntityScript_UE> InScriptClass)
    {
        auto Params = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter));

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            InScriptClass,
            FInstancedStruct::Make(Params));
    }

    UFUNCTION(Exec, DisplayName="IskmRenderer Batched Gym - Restart All")
    void Ck_GymIskmRendererBatched_RestartAll()
    {
        Request_StartGym();
    }
}
