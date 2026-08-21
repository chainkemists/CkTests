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

        Stations.Add(Make_Station(n"Gym.Rendering.OutlineIsm", "OUTLINE: ISM ENTITIES",
            "5 cubes share ONE ISM component; entities #2 (blue) and #4 (green) outlined.",
            "Per-instance outlines via the custom-depth-only shadow ISM."));
        Stations.Add(Make_Station(n"Gym.Rendering.OutlineIskm", "OUTLINE: ISKM PLAN-1",
            "3 skeletal proxies (pooled SKMCs); the middle one outlined (amber).",
            "Custom depth set on the entity's SKMC + outfit submeshes."));
        Stations.Add(Make_Station(n"Gym.Rendering.OutlineBatched", "OUTLINE: BATCHED CROWD",
            "16 GPU-skinned crowd members; members 0-2 outlined by index (blue/blue/green).",
            "Highlight cluster mirrors the skinned pose into custom depth."));
        Stations.Add(Make_Station(n"Gym.Rendering.OutlineCascade", "OUTLINE: CASCADE",
            "A parent entity whose visuals are 3 child cube proxies.",
            "One Request_ApplyOutline(EntityAndDependents) outlines them all."));
        Stations.Add(Make_Station(n"Gym.Rendering.OutlineVat", "OUTLINE: VAT (ANIMATED)",
            "3 vertex-animated figures; outer two outlined (blue/green), middle is the control.",
            "Silhouettes must WALK with the mesh — a bind-pose outline means the shadow ISM lost the VAT material or its custom data."));

        // Explicit single-row layout, wider than the 800uu default grid — the entity stations
        // spawn free-standing content (cube rows, crowds) that needs the extra clearance to
        // read as belonging to their station.
        const float StationSpacing = 1600.0f;
        auto RowStartOffset = -(Stations.Num() - 1) * StationSpacing * 0.5f;
        for (int32 i = 0; i < Stations.Num(); i++)
        {
            auto Xf = FTransform::Identity;
            Xf.SetLocation(FVector(500.0f, RowStartOffset + i * StationSpacing, 0.0f));
            Xf.SetRotation(FRotator(0.0f, 180.0f, 0.0f).Quaternion());
            Stations[i].Transform = Xf;
        }

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

        // Entity-outline stations (ISM / ISKM / Batched / Cascade / VAT) — entity-script stations.
        Request_SpawnEntityStation("Gym.Rendering.OutlineIsm",     UCk_EntityScript_UsfOutlineGym_Ism);
        Request_SpawnEntityStation("Gym.Rendering.OutlineIskm",    UCk_EntityScript_UsfOutlineGym_Iskm);
        Request_SpawnEntityStation("Gym.Rendering.OutlineBatched", UCk_EntityScript_UsfOutlineGym_Batched);
        Request_SpawnEntityStation("Gym.Rendering.OutlineCascade", UCk_EntityScript_UsfOutlineGym_Cascade);
        Request_SpawnEntityStation("Gym.Rendering.OutlineVat",     UCk_EntityScript_UsfOutlineGym_Vat);
    }

    private void Request_SpawnEntityStation(FString InTag, TSubclassOf<UCk_EntityScript_UE> InScriptClass)
    {
        auto Params = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter));

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            InScriptClass,
            FInstancedStruct::Make(Params));
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

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // One row, and it earns its place: respawning is how you re-run every preset after regenerating the
    // masters, and until this panel existed the only way to learn the command existed was to read this file.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "SOLID OUTLINE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Respawn every outline"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_SpawnAllOutlines(); }
    }

    UFUNCTION(Exec, DisplayName="Solid Outline Gym - Restart")
    void Ck_GymOutline_RestartAll()
    {
        Request_SpawnAllOutlines();
    }
}
