// --------------------------------------------------------------------------------------------------------------------
// CkUsf gym PlayerController: one station that demonstrates a USF-authored material
// (the Hologram look) rendered on a mesh via a runtime MID.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private AActor _Showcase;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Rendering.UsfHologram");
            Station.Title = FText::FromString("USF HOLOGRAM");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Material authored as text USF (no node graph)."));
            Description.Add(FText::FromString("Generated master -> MID -> rendered on the sphere."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_SpawnHologram();
        ck::Trace("🟦 CkUsf Gym - Hologram showcase started");
    }

    void Request_SpawnHologram()
    {
        // Place the sphere toward the player (world -X) and raised, in front of the station.
        auto StationTransform = Get_StationTransform("Gym.Rendering.UsfHologram");
        auto Location = StationTransform.Location + FVector(-200.0, 0.0, 150.0);

        if (_Showcase != nullptr)
        {
            _Showcase.DestroyActor();
        }

        _Showcase = SpawnActor(ACk_UsfGym_Showcase, Location, FRotator::ZeroRotator);
        if (_Showcase != nullptr)
        {
            _Showcase.SetActorScale3D(FVector(2.0, 2.0, 2.0));
            ck::Trace("✅ Hologram showcase sphere spawned at station");
        }
        else
        {
            ck::Error("❌ Failed to spawn Hologram showcase actor");
        }
    }

    UFUNCTION(Exec, DisplayName="Usf Gym - Restart Hologram")
    void Ck_GymUsf_RestartHologram()
    {
        Request_SpawnHologram();
    }
}
