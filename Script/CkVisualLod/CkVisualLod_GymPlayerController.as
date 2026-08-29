// Language=angelscript

//============================================================================
// CK VISUAL LOD GYM
//============================================================================
//
// A dedicated gym for the CkVisualLod arbiter: budgeted, ranked, crossfading
// promotion between batched crowd rendering and real SKMC proxies.
//============================================================================

class ACk_VisualLodGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.VisualLod.Arbitration", "Budgeted LOD Arbitration",
            "40 orbiting members, near budget 5. Walk in: the nearest in-view members CROSSFADE to real\nSKMC proxies. Walk out past the band: they dissolve back. Strafe the edge to see ranked\npreemption (rate-limited, margin-gated). Promote 9m / demote 13m."));

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

        auto Params = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.VisualLod.Arbitration", ECk_GymStation_Anchor::PanelCenter));

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.VisualLod.Arbitration"),
            UCk_EntityScript_VisualLodGym_Arbitration,
            FInstancedStruct::Make(Params));
    }

    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(60.0, 60.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { return; }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    FString Get_ControlPanelTitle() override
    {
        return "VISUAL LOD";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Respawn the station"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_StartGym(); }
    }
}
