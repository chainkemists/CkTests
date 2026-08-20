// --------------------------------------------------------------------------------------------------------------------
// Pixel Art gym ("Pixel Art" in the cycler).
//
// The renderer is view-wide, so the stations cannot each own a subject — there is only ever one frame.
// They are MODE SELECTORS: walk up to a station and its configuration is applied to the whole view, and
// every judgement is made against the one shared judge scene, which is what makes two stations comparable.
//
// The three stations that matter most are the A/B rig for pixel creep, and they only mean anything read in
// order — CREEP first, because it is what proves the problem exists in this scene at all:
//
//   CREEP    (snap off)              -> pixels crawl along edges
//   STUTTER  (snap on, comp off)     -> motion advances in whole texels
//   SMOOTH   (snap on, comp on)      -> smooth motion, grid-aligned. The finished result.
//
// Tab opens the gym cycler menu; search "Pixel". Console:
//   Ck_GymPixelArt_RestartAll     — respawn the judge scene and re-apply the first station
//   Ck_GymPixelArt_CycleStation   — next station without walking
//   Ck_GymPixelArt_TogglePan      — start/stop the 0.2 texel/frame diagonal drift
//   Ck_GymPixelArt_ToggleLook     — the look on its own, independent of the renderer
//
// Needs the PixelArt master on disk for the LOOK stations: on a fresh checkout run
// "Ck_Usf_GenerateLooks PixelArt" once in the editor console. The RENDERER stations work regardless — and
// telling those two halves apart is exactly what the RENDERER ONLY station is for.
// --------------------------------------------------------------------------------------------------------------------

const float k_PixelArtGym_ViewingClearance = 600.0f;

class ACk_PixelArtGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FName> _StationTags;
    private TArray<FVector> _StationLocations;
    private AActor _JudgeScene;
    private int32 _ActiveStation = -1;
    private bool _LookOverride = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.PixelArt.Off", "OFF (NATIVE)",
            "The renderer disabled entirely — the scene at full resolution.",
            "The control. Everything else is judged against this, including the perf numbers."));
        Stations.Add(Make_Station(n"Gym.PixelArt.RendererOnly", "RENDERER ONLY — 360p",
            "360 internal texels, snap on, box filter, no stylization.",
            "Chunky but SHARP. Blurry here means the box filter is not running and the engine's upscale is."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Height180", "INTERNAL HEIGHT: 180",
            "Half the texels of the reference station.",
            "Texels twice as large, and the thin rail should now be at or under one texel wide."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Height540", "INTERNAL HEIGHT: 540",
            "Half again as many texels as the reference station.",
            "Finer grid, same framing. A framing that CHANGES with the height means the margin fold is wrong."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Creep", "A/B 1 — CREEP (SNAP OFF)",
            "Snapping disabled. Start the pan: Ck_GymPixelArt_TogglePan.",
            "Pixels must visibly CRAWL along edges. If they do not, the pan is not running and the next two verdicts are worthless."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Stutter", "A/B 2 — STUTTER (NO COMPENSATION)",
            "Snap on, sub-texel compensation off.",
            "Motion must advance in whole texels — visibly stepped. That is the proof the snap is live."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Smooth", "A/B 3 — SMOOTH (THE RESULT)",
            "Snap on, compensation on. The finished behaviour.",
            "Smooth motion AND no crawl. Smooth-but-creeping means the compensation sign is inverted: try ck.PixelArt.Debug.CompSign -1."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Crisp16", "PRESET: CRISP 16",
            "360p, 8-colour palette, band-shift edges.",
            "Outlines must be colours the palette already holds — a grey or black line means the edge is being tinted after the palette snap instead of before."));
        Stations.Add(Make_Station(n"Gym.PixelArt.SoftRamp", "PRESET: SOFT RAMP",
            "Five bands, wide transition, flat edge colours, per-channel steps.",
            "Reads as toon shading rather than pixel art. That contrast with Crisp16 is the point: the palette and the edge rule carry the style, not the low resolution."));
        Stations.Add(Make_Station(n"Gym.PixelArt.Nearest", "FILTER: NEAREST",
            "Point sampling instead of the box filter.",
            "The texel grid becomes unambiguous — use it to count texels and to check the margin. Aliasing on the diagonal ramp is expected here and is what the box filter exists to remove."));

        const float StationSpacing = 1200.0f;
        const float StationRowX = 1800.0f + k_PixelArtGym_ViewingClearance;
        auto RowStartOffset = -(Stations.Num() - 1) * StationSpacing * 0.5f;

        for (int32 i = 0; i < Stations.Num(); i++)
        {
            auto Xf = FTransform::Identity;
            Xf.SetLocation(FVector(StationRowX, RowStartOffset + i * StationSpacing, 0.0f));
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
        Request_RebuildGym();

        ck::Trace("🟪 Pixel Art Gym - walk to a station to apply its configuration");
        ck::Trace("   Ck_GymPixelArt_TogglePan starts the 0.2 texel/frame drift the creep verdicts need");

        DoWarn_IfPiePreview();
    }

    // PIE at anything but 100% DPI inserts a second, engine-owned resample after ours, so the image is
    // softer than the real thing and every sharpness verdict taken there is wrong. Said out loud rather
    // than silently tolerated, because the failure looks exactly like a broken box filter.
    //
    // Stated unconditionally and pointed at the real evidence rather than guessed at here: the condition
    // that actually matters is not "is this PIE" but "did the engine settle on a secondary view fraction
    // below 1", which only the renderer can see. It logs that value itself the frame it changes.
    private void DoWarn_IfPiePreview()
    {
        ck::Trace("⚠ IF THIS IS PIE, IT IS A PREVIEW. Above 100% OS DPI the engine adds a second upscale");
        ck::Trace("   after this renderer's, so the image is softer than standalone. Check the log for a");
        ck::Trace("   `LogCkPixelArt: Secondary view fraction is <1` line - that line IS the condition.");
        ck::Trace("   Take sharpness, creep and margin verdicts from a standalone -game run.");
    }

    private void Request_RebuildGym()
    {
        if (ck::IsValid(_JudgeScene))
        { _JudgeScene.DestroyActor(); }

        _JudgeScene = SpawnActor(ACk_PixelArtGym_JudgeScene, FVector::ZeroVector, FRotator::ZeroRotator);

        if (_JudgeScene == nullptr)
        { ck::Error("❌ Pixel Art Gym: failed to spawn the judge scene"); }

        _StationTags.Empty();
        _StationLocations.Empty();
        _StationTags.Add(n"Gym.PixelArt.Off");
        _StationTags.Add(n"Gym.PixelArt.RendererOnly");
        _StationTags.Add(n"Gym.PixelArt.Height180");
        _StationTags.Add(n"Gym.PixelArt.Height540");
        _StationTags.Add(n"Gym.PixelArt.Creep");
        _StationTags.Add(n"Gym.PixelArt.Stutter");
        _StationTags.Add(n"Gym.PixelArt.Smooth");
        _StationTags.Add(n"Gym.PixelArt.Crisp16");
        _StationTags.Add(n"Gym.PixelArt.SoftRamp");
        _StationTags.Add(n"Gym.PixelArt.Nearest");

        for (auto Tag : _StationTags)
        { _StationLocations.Add(Get_StationViewingPoint(Tag)); }

        _ActiveStation = -1;
        Request_ApplyStation(0);
    }

    private FVector Get_StationViewingPoint(FName InTag)
    {
        auto Xf = Get_StationTransform(InTag.ToString());
        return Xf.Location + Xf.Rotator().GetForwardVector() * k_PixelArtGym_ViewingClearance;
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        auto Pawn = GetControlledPawn();

        if (!System::IsValid(Pawn) || _StationLocations.Num() == 0)
        { return; }

        if (UCkPixelArt_Subsystem::Get_PixelArtSubsystem() == nullptr)
        { return; }

        auto PawnLocation = Pawn.GetActorLocation();
        auto Nearest = 0;
        auto NearestDistanceSq = (_StationLocations[0] - PawnLocation).SizeSquared();

        for (int32 i = 1; i < _StationLocations.Num(); i++)
        {
            auto DistanceSq = (_StationLocations[i] - PawnLocation).SizeSquared();

            if (DistanceSq < NearestDistanceSq)
            {
                NearestDistanceSq = DistanceSq;
                Nearest = i;
            }
        }

        if (Nearest == _ActiveStation)
        { return; }

        // Hysteresis: a pawn idling on the midpoint between two stations is very nearly equidistant, and
        // without a margin the nearest flips on floating-point noise and re-applies a configuration every
        // tick. Applied in distance-SQUARED, so the real bar is about 10% closer in linear distance.
        if (_StationLocations.IsValidIndex(_ActiveStation))
        {
            auto ActiveDistanceSq = (_StationLocations[_ActiveStation] - PawnLocation).SizeSquared();

            if (NearestDistanceSq > ActiveDistanceSq * 0.8f)
            { return; }
        }

        Request_ApplyStation(Nearest);
    }

    void Request_ApplyStation(int32 InIndex)
    {
        auto Subsystem = UCkPixelArt_Subsystem::Get_PixelArtSubsystem();

        if (Subsystem == nullptr || !_StationTags.IsValidIndex(InIndex))
        { return; }

        // The gym is the one place that MAY move the engine's rendering settings, because a gym exists to
        // be looked at. Shipping code never does this without being asked.
        Subsystem.Request_Apply_RecommendedCVars();

        // Debug knobs are per-station state, so every station resets them rather than inheriting whatever
        // the previous one left behind.
        System::ExecuteConsoleCommand("ck.PixelArt.Debug.SnapOnly 0");

        auto Params = FCk_PixelArt_Params();
        Params.Set_InternalHeight(360);
        Params.Set_MarginTexels(2);
        Params.Set_SnapEnabled(ECk_EnableDisable::Enable);
        Params.Set_UpscaleFilter(ECk_PixelArt_UpscaleFilter::BoxFilter);
        Params.Set_ApplyLook(ECk_EnableDisable::Disable);

        auto Enabled = ECk_EnableDisable::Enable;
        auto Tag = _StationTags[InIndex];

        if (Tag == n"Gym.PixelArt.Off")
        {
            Enabled = ECk_EnableDisable::Disable;
        }
        else if (Tag == n"Gym.PixelArt.Height180")
        {
            Params.Set_InternalHeight(180);
        }
        else if (Tag == n"Gym.PixelArt.Height540")
        {
            Params.Set_InternalHeight(540);
        }
        else if (Tag == n"Gym.PixelArt.Creep")
        {
            Params.Set_SnapEnabled(ECk_EnableDisable::Disable);
        }
        else if (Tag == n"Gym.PixelArt.Stutter")
        {
            System::ExecuteConsoleCommand("ck.PixelArt.Debug.SnapOnly 1");
        }
        else if (Tag == n"Gym.PixelArt.Crisp16")
        {
            Params = CkPixelArt::DA_PixelArt_Crisp16.Get_AsParams();
        }
        else if (Tag == n"Gym.PixelArt.SoftRamp")
        {
            Params = CkPixelArt::DA_PixelArt_SoftRamp.Get_AsParams();
        }
        else if (Tag == n"Gym.PixelArt.Nearest")
        {
            Params.Set_UpscaleFilter(ECk_PixelArt_UpscaleFilter::Nearest);
        }

        if (_LookOverride)
        { Params.Set_ApplyLook(ECk_EnableDisable::Enable); }

        Subsystem.Request_SetSettings(Params);
        Subsystem.Request_SetEnabled(Enabled);

        // Recorded only after the subsystem accepted it: an enable refused on preconditions must not leave
        // the gym believing the station is showing.
        if (Subsystem.Get_IsEnabled() != Enabled)
        {
            ck::Error(f"❌ Pixel Art Gym: the subsystem refused station [{Tag}] — see the precondition report");
            return;
        }

        _ActiveStation = InIndex;
    }

    void Request_CycleStation()
    {
        if (_StationTags.Num() == 0)
        { return; }

        Request_ApplyStation((_ActiveStation + 1) % _StationTags.Num());
    }

    void Request_ToggleLook()
    {
        _LookOverride = !_LookOverride;

        auto State = _LookOverride ? "ON" : "OFF";
        ck::Trace(f"🟪 Pixel Art Gym: look override {State}");

        if (_StationTags.IsValidIndex(_ActiveStation))
        {
            auto Index = _ActiveStation;
            _ActiveStation = -1;
            Request_ApplyStation(Index);
        }
    }

    UFUNCTION(Exec, DisplayName="Pixel Art Gym - Restart")
    void Ck_GymPixelArt_RestartAll()
    {
        Request_RebuildGym();
    }

    UFUNCTION(Exec, DisplayName="Pixel Art Gym - Cycle Station")
    void Ck_GymPixelArt_CycleStation()
    {
        Request_CycleStation();
    }

    // Delegates to the renderer's own pan rather than moving the camera here: the drift has to be measured
    // in TEXELS, and only the renderer knows how big one is at the current resolution and ortho width.
    UFUNCTION(Exec, DisplayName="Pixel Art Gym - Toggle Camera Pan")
    void Ck_GymPixelArt_TogglePan()
    {
        System::ExecuteConsoleCommand("Ck_PixelArt_DebugPan 0.2");
    }

    UFUNCTION(Exec, DisplayName="Pixel Art Gym - Toggle Look")
    void Ck_GymPixelArt_ToggleLook()
    {
        Request_ToggleLook();
    }
}
