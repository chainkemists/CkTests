// --------------------------------------------------------------------------------------------------------------------
// Solid Outline gym ("Solid Outline" in the cycler): one station per sample outline preset. Each station spawns an
// outlined sphere with an opaque wall partly in front, so you can immediately see the occlusion behaviour differ:
//   - INTERACTABLE (Normal)        : silhouette hidden where the wall covers the sphere.
//   - SEE-THROUGH                  : silhouette + faint fill visible through the wall.
//   - MASKED SEE-THROUGH           : see-through with a stippled fill (objective-marker style).
// Tab opens the gym cycler menu; search "Solid Outline". Console: "Ck_GymOutline_RestartAll".
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfOutlineGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<AActor> _Showcases;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.Rendering.OutlineInteractable", "OUTLINE: INTERACTABLE",
            "Solid blue silhouette (Normal type).", "Hidden where the wall occludes the sphere."));
        Stations.Add(Make_Station(n"Gym.Rendering.OutlineSeeThrough", "OUTLINE: SEE-THROUGH",
            "Green outline + faint fill.", "Stays visible through the wall."));
        Stations.Add(Make_Station(n"Gym.Rendering.OutlineMasked", "OUTLINE: MASKED SEE-THROUGH",
            "Amber outline + stippled fill.", "Objective-marker style, readable through cover."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload Make_Station(FName InTag, FString InTitle, FString InLine1, FString InLine2)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InLine1));
        Description.Add(FText::FromString(InLine2));
        Station.Description = Description;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        Request_SpawnAllOutlines();
        ck::Trace("🟦 Solid Outline Gym - stations started");
    }

    void Request_SpawnAllOutlines()
    {
        // Clear any prior showcases (supports restart).
        for (auto Existing : _Showcases)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyActor(); }
        }
        _Showcases.Empty();

        Request_SpawnOutline(n"Gym.Rendering.OutlineInteractable", CkUsf::DA_Outline_Interactable);
        Request_SpawnOutline(n"Gym.Rendering.OutlineSeeThrough",   CkUsf::DA_Outline_SeeThrough);
        Request_SpawnOutline(n"Gym.Rendering.OutlineMasked",       CkUsf::DA_Outline_MaskedObjective);
    }

    private void Request_SpawnOutline(FName InStationTag, UCkUsf_OutlinePreset InPreset)
    {
        auto StationTransform = Get_StationTransform(InStationTag.ToString());
        // Place toward the player (world -X) and raised, in front of the station billboard.
        auto Location = StationTransform.Location + FVector(-200.0, 0.0, 150.0);

        auto Showcase = Cast<ACk_UsfGym_OutlineShowcase>(
            SpawnActor(ACk_UsfGym_OutlineShowcase, Location, FRotator::ZeroRotator));
        if (Showcase != nullptr)
        {
            Showcase.Request_SetPreset(InPreset);
            _Showcases.Add(Showcase);
        }
        else
        {
            ck::Error("❌ Failed to spawn solid-outline showcase actor");
        }
    }

    UFUNCTION(Exec, DisplayName="Solid Outline Gym - Restart")
    void Ck_GymOutline_RestartAll()
    {
        Request_SpawnAllOutlines();
    }
}
