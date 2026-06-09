// --------------------------------------------------------------------------------------------------------------------
// CkUsf gym PlayerController ("USF Materials"): one station per USF-authored look, each
// with a sphere rendering that look via a runtime MID. Showcases what text-only USF
// material authoring can do — from a simple hologram to per-pixel fractal math.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<AActor> _Showcases;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.Rendering.UsfHologram", "HOLOGRAM",
            "Emissive scanlines from sin(UV, Time).", "Lightest look — a few sines."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfPlasma", "PLASMA",
            "Animated sum-of-sines colour field.", "Two-colour blend over a sine plasma."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfVoronoi", "VORONOI",
            "Animated cellular distance field.", "3x3 neighbour search, glowing seams."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfJulia", "JULIA FRACTAL",
            "Per-pixel escape-time fractal.", "96 iterations, orbiting constant."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfFbmWarp", "FBM DOMAIN WARP",
            "Domain-warped fractal noise.", "fbm(fbm(fbm)) — 5 octaves each."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfSeascape", "SEASCAPE (TDM)",
            "Raymarched procedural ocean.", "32-step heightfield trace, ported from GLSL."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfAiekick", "DISPLACEMENT (AIEKICK)",
            "Raymarched glass sphere.", "Cubemap reflect/refract + noise displacement."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfTruchet", "TRUCHET CIRCUIT",
            "Animated Truchet arc tiling.", "Per-cell arc flip; glowing connected curves."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfStarfield", "STARFIELD",
            "Parallax twinkling starfield.", "5 jittered-grid depth layers."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfCaustics", "CAUSTICS",
            "Underwater light caustics.", "Domain-distorted sine ridges."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfRimGlow", "RIM GLOW (FRESNEL)",
            "Fresnel rim from normal vs view dir.", "Proves the new world-space surface inputs."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfDissolve", "DISSOLVE (MASKED)",
            "Animated cutout via OpacityMask.", "Masked blend + two-sided; glowing burn edge."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfLitMetal", "LIT METAL (PBR)",
            "Scene-lit metal/dielectric checker.", "DefaultLit + Metallic/Specular/Roughness."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfDisplace", "DISPLACE (WPO)",
            "Vertex-shader world-position offset.", "Sine wave along normal; coarse on a stock sphere."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfGlass", "GLASS (REFRACTION)",
            "Lit translucent glass with IOR bend.", "Refraction pin + RM_IndexOfRefraction."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfSkin", "SKIN (SUBSURFACE)",
            "Subsurface scatter shading model.", "SubsurfaceColor + opacity-driven scatter."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfCarPaint", "CAR PAINT (CLEARCOAT)",
            "Metallic base under a clear lacquer coat.", "ClearCoat + ClearCoatRoughness custom data."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfPerInstance", "PER-INSTANCE HUE (ISM)",
            "One material, N instances, distinct colours.", "Per-instance custom data slot 0 → hue."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfFeedback", "RENDER-TO-TEXTURE",
            "Multi-pass feedback buffer (ping-pong RT).", "BufferA reads itself; Image colorizes."));
        Stations.Add(Make_Station(n"Gym.Rendering.UsfPostProcess", "POST-PROCESS (EDGE OUTLINE)",
            "Screen-space depth+normal outline.", "Reads SceneDepth/WorldNormal; unbound PP volume."));

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
        Request_SpawnAllLooks();
        ck::Trace("🟦 USF Materials Gym - all looks started");
    }

    void Request_SpawnAllLooks()
    {
        // Clear any prior showcases (supports restart).
        for (auto Existing : _Showcases)
        {
            if (ck::IsValid(Existing)) { Existing.DestroyActor(); }
        }
        _Showcases.Empty();

        Request_SpawnLook(n"Gym.Rendering.UsfHologram", CkUsf::Hologram);
        Request_SpawnLook(n"Gym.Rendering.UsfPlasma",   CkUsf::Plasma);
        Request_SpawnLook(n"Gym.Rendering.UsfVoronoi",  CkUsf::Voronoi);
        Request_SpawnLook(n"Gym.Rendering.UsfJulia",    CkUsf::Julia);
        Request_SpawnLook(n"Gym.Rendering.UsfFbmWarp",  CkUsf::FbmWarp);
        Request_SpawnLook(n"Gym.Rendering.UsfSeascape", CkUsf::Seascape);
        Request_SpawnLook(n"Gym.Rendering.UsfAiekick",  CkUsf::Aiekick);
        Request_SpawnLook(n"Gym.Rendering.UsfTruchet",   CkUsf::Truchet);
        Request_SpawnLook(n"Gym.Rendering.UsfStarfield", CkUsf::Starfield);
        Request_SpawnLook(n"Gym.Rendering.UsfCaustics",  CkUsf::Caustics);
        Request_SpawnLook(n"Gym.Rendering.UsfRimGlow",   CkUsf::RimGlow);
        Request_SpawnLook(n"Gym.Rendering.UsfDissolve",  CkUsf::Dissolve);
        Request_SpawnLook(n"Gym.Rendering.UsfLitMetal",  CkUsf::LitMetal);
        Request_SpawnLook(n"Gym.Rendering.UsfDisplace",  CkUsf::Displace);
        Request_SpawnLook(n"Gym.Rendering.UsfGlass",     CkUsf::Glass);
        Request_SpawnLook(n"Gym.Rendering.UsfSkin",      CkUsf::Skin);
        Request_SpawnLook(n"Gym.Rendering.UsfCarPaint",  CkUsf::CarPaint);
        Request_SpawnPerInstance(n"Gym.Rendering.UsfPerInstance", CkUsf::PerInstanceHue);
        Request_SpawnMultiPass(n"Gym.Rendering.UsfFeedback");
        Request_SpawnPostProcess(n"Gym.Rendering.UsfPostProcess");
    }

    private void Request_SpawnMultiPass(FName InStationTag)
    {
        auto StationTransform = Get_StationTransform(InStationTag.ToString());
        auto Location = StationTransform.Location + FVector(-200.0, 0.0, 150.0);
        auto Actor = SpawnActor(ACk_UsfGym_MultiPassShowcase, Location, FRotator::ZeroRotator);
        if (Actor != nullptr)
        {
            Actor.SetActorScale3D(FVector(2.0, 2.0, 2.0));
            _Showcases.Add(Actor);
            ck::Trace("✅ Render-to-texture feedback showcase spawned");
        }
    }

    private void Request_SpawnPerInstance(FName InStationTag, UCkUsf_LookDefinition InLook)
    {
        auto StationTransform = Get_StationTransform(InStationTag.ToString());
        auto Location = StationTransform.Location + FVector(-200.0, 0.0, 150.0);
        auto Actor = Cast<ACk_UsfGym_PerInstanceShowcase>(
            SpawnActor(ACk_UsfGym_PerInstanceShowcase, Location, FRotator::ZeroRotator));
        if (Actor != nullptr)
        {
            const int InstanceCount = 8;
            Actor.Request_SetLook(InLook, InstanceCount);
            _Showcases.Add(Actor);
        }
        else
        {
            ck::Error("❌ Failed to spawn USF per-instance showcase actor");
        }
    }

    private void Request_SpawnPostProcess(FName InStationTag)
    {
        auto StationTransform = Get_StationTransform(InStationTag.ToString());
        auto Actor = SpawnActor(ACk_UsfGym_PostProcessShowcase, StationTransform.Location, FRotator::ZeroRotator);
        if (Actor != nullptr)
        {
            _Showcases.Add(Actor);
            ck::Trace("✅ Post-process edge-outline showcase spawned");
        }
    }

    private void Request_SpawnLook(FName InStationTag, UCkUsf_LookDefinition InLook)
    {
        auto StationTransform = Get_StationTransform(InStationTag.ToString());
        // Place the sphere toward the player (world -X) and raised, in front of the station.
        auto Location = StationTransform.Location + FVector(-200.0, 0.0, 150.0);

        auto Showcase = Cast<ACk_UsfGym_Showcase>(SpawnActor(ACk_UsfGym_Showcase, Location, FRotator::ZeroRotator));
        if (Showcase != nullptr)
        {
            Showcase.SetActorScale3D(FVector(2.0, 2.0, 2.0));
            Showcase.Request_SetLook(InLook);
            _Showcases.Add(Showcase);
        }
        else
        {
            ck::Error("❌ Failed to spawn USF showcase actor");
        }
    }

    UFUNCTION(Exec, DisplayName="USF Materials Gym - Restart All Looks")
    void Ck_GymUsf_RestartAll()
    {
        Request_SpawnAllLooks();
    }
}
