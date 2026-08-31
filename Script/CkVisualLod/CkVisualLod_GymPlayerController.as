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
    private bool _LightingBuilt = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.VisualLod.Arbitration", "Budgeted LOD Arbitration",
            "40 orbiting members, near budget 5. Walk in: nearest in-view members CROSSFADE to real\nSKMC proxies. A dedicated shadow-casting sun makes the far-body bands judgeable: full lit/shadowed\nbelow 15m, reduced no-shadow after 15m, terminal no-main/depth after 30m.\nOpen Visual LOD Debugger > Tuners to change budgets and decision distances at runtime."));

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
        Build_Lighting();
        SpawnFloor();

        auto Params = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.VisualLod.Arbitration", ECk_GymStation_Anchor::PanelCenter));

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.VisualLod.Arbitration"),
            UCk_EntityScript_VisualLodGym_Arbitration,
            FInstancedStruct::Make(Params));
    }

    private void Build_Lighting()
    {
        if (_LightingBuilt)
        { return; }

        _LightingBuilt = true;

        // The shared station spotlight is aimed at its back wall and has a short local radius. This
        // sun deliberately covers the whole roaming crowd and makes the full -> reduced shadow-band
        // transition judgeable against the gym floor.
        auto KeyLight = UDirectionalLightComponent::Create(this);
        KeyLight.SetRelativeRotation(FRotator(-42.0f, 135.0f, 0.0f));
        KeyLight.SetIntensity(5.0f);
        KeyLight.SetLightColor(FLinearColor(1.0f, 0.96f, 0.88f, 1.0f));
        KeyLight.SetCastShadows(true);
        KeyLight.SetForwardShadingPriority(100);

        auto FillLight = USkyLightComponent::Create(this);
        FillLight.SetIntensity(0.75f);
        FillLight.SetLightColor(FLinearColor(0.50f, 0.58f, 0.72f, 1.0f));
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
