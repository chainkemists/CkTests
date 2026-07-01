// Language=angelscript

class ACk_IskmRendererGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Iskm.SpawnArmy", "Spawn Army",
            "5x5 grid of skeletal-mesh proxies.\nEach plays a random looping sequence (idle / walk / jog) at a jittered play rate."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.OutfitSwap", "Outfit Swap",
            "Single proxy, cycles submesh attach/detach.\nDemonstrates Request_AttachSubmesh / DetachSubmesh."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.MontageBurst", "Montage Burst",
            "Single proxy, plays a montage every 3s.\nDemonstrates Request_PlayMontage."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.RagdollDemo", "Ragdoll Demo",
            "Single proxy, alternates ragdoll/get-up.\nDemonstrates Request_BeginRagdoll / EndRagdoll."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.CustomData", "Custom Data",
            "Single proxy, oscillates custom-data floats.\nDrives material tint via Request_SetCustomDataFloat."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.TransitionCycle", "Transition Cycle",
            "Single proxy, alternates a looping seq and a non-looping seq.\nDemonstrates the Replaced + Completed paths in OnAnimationFinished."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.AnimBPDemo", "AnimBP Demo",
            "Two proxies side-by-side. Left uses the Renderer PDA's default AnimBP (Asset_RendererData_Demo wires this to ABP_Unarmed).\nRight is forced to Sequence mode via Request_SetAnimInstanceClass(null) and plays MM_Idle.\nDemonstrates both pose-source modes simultaneously."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.BatchedArmy", "Batched Army (Plan-2)",
            "10x10 GPU-skinned crowd rendered through ONE GPUScene cluster proxy, animating independently.\nA/B vs the per-SKMC Spawn Army: compare draw calls (stat rhi / stat scenerendering) and frame time (stat unit)."));

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

        SpawnStation("Gym.Iskm.SpawnArmy",     UCk_EntityScript_IskmRendererGym_SpawnArmy);
        SpawnStation("Gym.Iskm.OutfitSwap",    UCk_EntityScript_IskmRendererGym_OutfitSwap);
        SpawnStation("Gym.Iskm.MontageBurst",  UCk_EntityScript_IskmRendererGym_MontageBurst);
        SpawnStation("Gym.Iskm.RagdollDemo",   UCk_EntityScript_IskmRendererGym_RagdollDemo);
        SpawnStation("Gym.Iskm.CustomData",    UCk_EntityScript_IskmRendererGym_CustomData);
        SpawnStation("Gym.Iskm.TransitionCycle", UCk_EntityScript_IskmRendererGym_TransitionCycle);
        SpawnStation("Gym.Iskm.AnimBPDemo",      UCk_EntityScript_IskmRendererGym_AnimBPDemo);
        SpawnStation("Gym.Iskm.BatchedArmy",     UCk_EntityScript_IskmRendererGym_BatchedArmy);
    }

    // Spawns a generic collidable floor under the gym so RagdollDemo characters
    // don't fall through the world. Reuses ACk_Gym_Floor (CkTests/Script/Common/
    // CkGym_Floor.as) — same pattern as the CkCrowd gyms. 4000×4000cm covers
    // all 7 station anchors and the SpawnArmy 5×5 grid (~600cm footprint).
    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(40.0, 40.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { return; }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    private void SpawnStation(FString InTag, TSubclassOf<UCk_EntityScript_UE> InScriptClass)
    {
        // Transform-only spawn params: every station spawned here exposes InitialTransform and nothing else,
        // so pass the minimal FCk_Gym_TransformSpawnParams. The 3-field FCkIskmRenderer_GymStationSpawnParams
        // (Count/Moving) is only for the Stress stations, whose StressArmy script exposes those props.
        // Injecting Count/Moving into a station that doesn't expose them ensures in
        // TryInjectEntityScriptSpawnParams ("Failed to find ExposedOnSpawn Property [Count]").
        auto Params = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter));

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            InScriptClass,
            FInstancedStruct::Make(Params));
    }

    UFUNCTION(Exec, DisplayName="IskmRenderer Gym - Restart All")
    void Ck_GymIskmRenderer_RestartAll()
    {
        Request_StartGym();
    }
}
