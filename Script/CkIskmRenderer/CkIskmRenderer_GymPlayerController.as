// Language=angelscript

class ACk_IskmRendererGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Iskm.SpawnArmy", "Spawn Army",
            "5x5 grid of skeletal-mesh proxies.\nEach plays a random looping sequence."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.OutfitSwap", "Outfit Swap",
            "Single proxy, cycles submesh attach/detach.\nDemonstrates Request_AttachSubmesh / DetachSubmesh."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.MontageBurst", "Montage Burst",
            "Single proxy, plays a montage every 3s.\nDemonstrates Request_PlayMontage."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.RagdollDemo", "Ragdoll Demo",
            "Single proxy, alternates ragdoll/get-up.\nDemonstrates Request_BeginRagdoll / EndRagdoll."));
        Stations.Add(MakeStationPayload(n"Gym.Iskm.CustomData", "Custom Data",
            "Single proxy, oscillates custom-data floats.\nDrives material tint via Request_SetCustomDataFloat."));

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
        SpawnStation("Gym.Iskm.SpawnArmy",     UCk_EntityScript_IskmRendererGym_SpawnArmy);
        SpawnStation("Gym.Iskm.OutfitSwap",    UCk_EntityScript_IskmRendererGym_OutfitSwap);
        SpawnStation("Gym.Iskm.MontageBurst",  UCk_EntityScript_IskmRendererGym_MontageBurst);
        SpawnStation("Gym.Iskm.RagdollDemo",   UCk_EntityScript_IskmRendererGym_RagdollDemo);
        SpawnStation("Gym.Iskm.CustomData",    UCk_EntityScript_IskmRendererGym_CustomData);
    }

    private void SpawnStation(FString InTag, TSubclassOf<UCk_EntityScript_UE> InScriptClass)
    {
        auto Params = FCkIskmRenderer_GymStationSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);

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
