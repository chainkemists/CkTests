// --------------------------------------------------------------------------------------------------------------------
// Cel Shade gym ("Stylize: Cel Shade" in the cycler).
//
// CelShade is a VIEW-WIDE post-process, so the stations cannot each own a subject the way the Solid
// Outline gym's do — there is only ever one frame. They are PRESET SELECTORS instead: walk up to a
// station and its preset is applied to the whole view. Everything is judged against the single shared
// judge scene (ACk_UsfGym_StylizeCelJudgeScene), which is what makes two presets comparable at all.
//
// The two per-object rows are the exception, and they are subjects rather than stations: the judge
// scene's hand-tagged STENCIL cubes and the ENTITY subjects spawned here must look identical, because
// they reach the same Custom-Stencil contract through different front doors.
//
// Tab opens the gym cycler menu; search "Stylize". Console:
//   Ck_GymStylizeCel_RestartAll      — respawn the judge scene and re-apply Balanced
//   Ck_GymStylizeCel_CyclePreset     — next preset without walking
//   Ck_GymStylizeCel_CycleDebug      — next debug view of the CURRENT preset
//   Ck_GymStylizeCel_ToggleEntity    — clear/re-apply the ENTITY row's patterns
//
// Needs the CelShade master on disk: on a fresh checkout run "Ck_Usf_GenerateLooks CelShade" once in
// the editor console, or the subsystem warns and the view is untouched.
// --------------------------------------------------------------------------------------------------------------------

class ACk_UsfStylizeCelGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FName> _StationTags;
    private TArray<FVector> _StationLocations;
    private ACk_UsfGym_StylizeCelJudgeScene _JudgeScene;
    private TArray<ACk_UsfGym_StylizeCelEntitySubject> _EntitySubjects;
    private int32 _ActiveStation = -1;
    private int32 _DebugIndex = 0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.Stylize.CelBalanced", "CEL: BALANCED",
            "Four bands anchored at mid exposure, world-space round dots across every transition.",
            "Band boundaries must run STRAIGHT ACROSS the gradient wall. Boundaries that follow the albedo ramp mean the illumination reconstruction failed."));
        Stations.Add(Make_Station(n"Gym.Stylize.CelCleanAnime", "CEL: CLEAN ANIME",
            "Three near-flat bands, the pattern mostly off, a cool shadow tint and a crisp line.",
            "Flat painted regions with ink on top. Visible dot texture here means the pattern strength is fighting the style."));
        Stations.Add(Make_Station(n"Gym.Stylize.CelComicHalftone", "CEL: COMIC HALFTONE",
            "Coarse world-space dots at full strength over three bands, heavy multiplied line.",
            "Dots must stay GLUED to static geometry as you walk. Dots swimming across a still wall means the pattern is in screen space."));
        Stations.Add(Make_Station(n"Gym.Stylize.CelInkCrosshatch", "CEL: INK CROSSHATCH",
            "Crosshatch strokes over five bands, desaturated, no specular.",
            "Hatch density should step visibly between bands. Uniform hatching everywhere means the transition is not reading the band fraction."));
        Stations.Add(Make_Station(n"Gym.Stylize.CelSoftToon", "CEL: SOFT TOON",
            "Six soft bands, pattern off, no ink line, a strong rim.",
            "Reads as simplified shading, not as posterization — and the backlit figure must show a clear rim."));
        Stations.Add(Make_Station(n"Gym.Stylize.CelOff", "CEL: OFF",
            "The A/B reference — the subsystem's blendable disabled.",
            "The frame must come back completely clean. Any residue here means disable is not actually disabling."));

        // Explicit single row, wider than the 800uu default: the judge scene sits in front of these and
        // the player has to be able to walk the row without leaving it.
        const float StationSpacing = 1200.0f;
        auto RowStartOffset = -(Stations.Num() - 1) * StationSpacing * 0.5f;
        for (int32 i = 0; i < Stations.Num(); i++)
        {
            auto Xf = FTransform::Identity;
            Xf.SetLocation(FVector(1800.0f, RowStartOffset + i * StationSpacing, 0.0f));
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
        // The per-object contract reads Custom Stencil, which the renderer only writes in stencil mode.
        // Without this the two per-object rows are silently inert and look like a shader bug.
        System::ExecuteConsoleCommand("r.CustomDepth 3");

        Request_RebuildGym();
        ck::Trace("🟪 Stylize Cel Shade Gym - walk to a station to apply its preset");
    }

    private void Request_RebuildGym()
    {
        if (ck::IsValid(_JudgeScene))
        { _JudgeScene.DestroyActor(); }

        for (auto Subject : _EntitySubjects)
        {
            if (ck::IsValid(Subject))
            { Subject.DestroyActor(); }
        }
        _EntitySubjects.Empty();

        _JudgeScene = Cast<ACk_UsfGym_StylizeCelJudgeScene>(
            SpawnActor(ACk_UsfGym_StylizeCelJudgeScene, FVector(0.0f, 0.0f, 0.0f), FRotator::ZeroRotator));
        if (_JudgeScene == nullptr)
        { ck::Error("❌ Stylize Cel Gym: failed to spawn the judge scene"); }

        // Y-ALIGNED with the judge scene's hand-tagged stencil row, whose cubes sit at
        // -300 control / 0 suppress / 300 RoundDots / 600 DiagonalLines. Each entity subject therefore
        // shares a sightline with its hand-tagged twin, which is the whole point of the row: the pair must
        // be indistinguishable. Misaligned rows make that unjudgeable.
        Spawn_EntitySubject(ECk_Usf_CelPattern::RoundDots, 300.0f);
        Spawn_EntitySubject(ECk_Usf_CelPattern::DiagonalLines, 600.0f);

        _StationTags.Empty();
        _StationLocations.Empty();
        _StationTags.Add(n"Gym.Stylize.CelBalanced");
        _StationTags.Add(n"Gym.Stylize.CelCleanAnime");
        _StationTags.Add(n"Gym.Stylize.CelComicHalftone");
        _StationTags.Add(n"Gym.Stylize.CelInkCrosshatch");
        _StationTags.Add(n"Gym.Stylize.CelSoftToon");
        _StationTags.Add(n"Gym.Stylize.CelOff");

        for (auto Tag : _StationTags)
        { _StationLocations.Add(Get_StationTransform(Tag.ToString()).Location); }

        _ActiveStation = -1;
        _DebugIndex = 0;
        Request_ApplyStation(0);
    }

    private void Spawn_EntitySubject(ECk_Usf_CelPattern InPattern, float InY)
    {
        // Directly behind the hand-tagged stencil row, so a viewer sees the two rows in one frame.
        auto Subject = Cast<ACk_UsfGym_StylizeCelEntitySubject>(SpawnActor(
            ACk_UsfGym_StylizeCelEntitySubject, FVector(-1050.0f, InY, 130.0f), FRotator::ZeroRotator));

        if (Subject == nullptr)
        { return; }

        Subject.Pattern = InPattern;

        // Re-apply explicitly rather than trusting BeginPlay's entity construction to land after this
        // assignment — the spawn already ran BeginPlay, and Request_ApplyPattern is a no-op until the
        // entity exists, so this is what actually guarantees the subject uses the pattern asked for.
        Subject.Request_ApplyPattern();

        _EntitySubjects.Add(Subject);
    }

    // The station a player is standing at is the selection: there is no per-station subject to interact
    // with, so proximity IS the input.
    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        auto Pawn = GetControlledPawn();
        if (!System::IsValid(Pawn) || _StationLocations.Num() == 0)
        { return; }

        // Checked BEFORE selecting: without the master the apply cannot succeed, and running the
        // selection anyway would re-enter Request_ApplyStation every tick (which never records
        // _ActiveStation on that path) and spam the log forever.
        if (UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem() == nullptr)
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
        // without a margin the nearest flips on floating-point noise and re-applies a preset every tick.
        // A challenger has to be meaningfully closer (20%) than the station already showing.
        if (_StationLocations.IsValidIndex(_ActiveStation))
        {
            auto ActiveDistanceSq = (_StationLocations[_ActiveStation] - PawnLocation).SizeSquared();
            if (NearestDistanceSq >= ActiveDistanceSq * 0.8)
            { return; }
        }

        Request_ApplyStation(Nearest);
    }

    private void Request_ApplyStation(int32 InIndex)
    {
        auto Subsystem = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("Stylize Cel Gym: CelShade subsystem unavailable");
            return;
        }

        auto Preset = Get_PresetAt(InIndex);
        if (Preset == nullptr)
        { return; }

        _ActiveStation = InIndex;
        _DebugIndex = 0;
        Subsystem.Apply_Preset(Preset);

        // A preset may move the stencil base, and the hand-tagged cubes hold whatever value was written
        // when they were built — re-resolving keeps the row honest instead of quietly stale.
        if (ck::IsValid(_JudgeScene))
        { _JudgeScene.Request_RefreshStencilRow(); }

        PrintToScreen("CEL SHADE preset: " + Get_PresetNameAt(InIndex), 2.0, FLinearColor::Yellow);
    }

    private UCkUsf_CelShadePreset Get_PresetAt(int32 InIndex)
    {
        if (InIndex == 0) { return CkUsf::DA_Cel_Balanced; }
        if (InIndex == 1) { return CkUsf::DA_Cel_CleanAnime; }
        if (InIndex == 2) { return CkUsf::DA_Cel_ComicHalftone; }
        if (InIndex == 3) { return CkUsf::DA_Cel_InkCrosshatch; }
        if (InIndex == 4) { return CkUsf::DA_Cel_SoftToon; }
        if (InIndex == 5) { return CkUsf::DA_Cel_Off; }
        return nullptr;
    }

    // const because PrintToScreen is a development-only call and AngelScript rejects non-const members
    // inside one — the compiler cannot prove the call is side-effect-free in a shipping build otherwise.
    private FString Get_PresetNameAt(int32 InIndex) const
    {
        if (InIndex == 0) { return "Balanced"; }
        if (InIndex == 1) { return "CleanAnime"; }
        if (InIndex == 2) { return "ComicHalftone"; }
        if (InIndex == 3) { return "InkCrosshatch"; }
        if (InIndex == 4) { return "SoftToon"; }
        if (InIndex == 5) { return "Off"; }
        return "?";
    }

    private ECk_Usf_CelShade_DebugMode Get_DebugModeAt(int32 InIndex)
    {
        if (InIndex == 1) { return ECk_Usf_CelShade_DebugMode::BandIndex; }
        if (InIndex == 2) { return ECk_Usf_CelShade_DebugMode::OutlineMask; }
        if (InIndex == 3) { return ECk_Usf_CelShade_DebugMode::Illumination; }
        if (InIndex == 4) { return ECk_Usf_CelShade_DebugMode::Albedo; }
        if (InIndex == 5) { return ECk_Usf_CelShade_DebugMode::Normals; }
        if (InIndex == 6) { return ECk_Usf_CelShade_DebugMode::PatternThreshold; }
        if (InIndex == 7) { return ECk_Usf_CelShade_DebugMode::PatternCoordinates; }
        if (InIndex == 8) { return ECk_Usf_CelShade_DebugMode::MotionOffset; }
        if (InIndex == 9) { return ECk_Usf_CelShade_DebugMode::Stencil; }
        return ECk_Usf_CelShade_DebugMode::Final;
    }

    private FString Get_DebugNameAt(int32 InIndex) const
    {
        if (InIndex == 1) { return "BandIndex"; }
        if (InIndex == 2) { return "OutlineMask"; }
        if (InIndex == 3) { return "Illumination"; }
        if (InIndex == 4) { return "Albedo"; }
        if (InIndex == 5) { return "Normals"; }
        if (InIndex == 6) { return "PatternThreshold"; }
        if (InIndex == 7) { return "PatternCoordinates"; }
        if (InIndex == 8) { return "MotionOffset (always black - stabilization is a non-goal)"; }
        if (InIndex == 9) { return "Stencil"; }
        return "Final";
    }

    UFUNCTION(Exec, DisplayName="Stylize Cel Gym - Restart")
    void Ck_GymStylizeCel_RestartAll()
    {
        Request_RebuildGym();
    }

    UFUNCTION(Exec, DisplayName="Stylize Cel Gym - Cycle Preset")
    void Ck_GymStylizeCel_CyclePreset()
    {
        Request_ApplyStation((_ActiveStation + 1) % _StationTags.Num());
    }

    // Debug views are a property of the CURRENT preset, so this edits the live settings rather than
    // re-applying a preset — walking to another station resets it, which is the intended behaviour.
    UFUNCTION(Exec, DisplayName="Stylize Cel Gym - Cycle Debug Mode")
    void Ck_GymStylizeCel_CycleDebug()
    {
        auto Subsystem = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem();
        if (Subsystem == nullptr)
        { return; }

        _DebugIndex = (_DebugIndex + 1) % 10;

        auto Settings = Subsystem.Get_Settings();
        Settings.Set_DebugMode(Get_DebugModeAt(_DebugIndex));
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("CEL SHADE debug: " + Get_DebugNameAt(_DebugIndex), 2.0, FLinearColor::Green);
    }

    // The remove half of the entity API. A pattern that only ever goes ON proves nothing about the
    // remove processor restoring the mesh.
    UFUNCTION(Exec, DisplayName="Stylize Cel Gym - Toggle Entity Patterns")
    void Ck_GymStylizeCel_ToggleEntity()
    {
        for (auto Subject : _EntitySubjects)
        {
            if (ck::IsValid(Subject))
            { Subject.Request_TogglePattern(); }
        }

        PrintToScreen("CEL SHADE entity patterns toggled", 2.0, FLinearColor::Green);
    }
}
