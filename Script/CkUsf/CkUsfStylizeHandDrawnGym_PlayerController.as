// --------------------------------------------------------------------------------------------------------------------
// Hand-Drawn gym ("Stylize: Hand-Drawn" in the cycler).
//
// HandDrawn is a VIEW-WIDE post-process, so the stations cannot each own a subject the way the Solid
// Outline gym's do — there is only ever one frame. They are PRESET SELECTORS instead: walk up to a
// station and its preset is applied to the whole view. Everything is judged against the single shared
// judge scene (ACk_UsfGym_StylizeHandDrawnJudgeScene), which is what makes two presets comparable at all.
//
// Two rows, each centred on its own count:
//   front row (6) — the authored presets
//   back row  (3) — StorybookInk with one debug mask forced on, because a mask is the only way to tell
//                   "the detector found nothing" from "the detector found everything and the opacity is
//                   low". Walking back to the front row restores the ordinary image.
//
// Tab opens the gym cycler menu; search "Stylize". Console:
//   Ck_GymStylizeHandDrawn_RestartAll        — respawn the judge scene and re-apply StorybookInk
//   Ck_GymStylizeHandDrawn_CyclePreset       — next preset without walking
//   Ck_GymStylizeHandDrawn_CycleDebug        — next debug view of the CURRENT settings
//   Ck_GymStylizeHandDrawn_ToggleDitherStack — stack ScreenDither on top, for the cross-effect A/B
//   Ck_GymStylizeHandDrawn_ToggleStrokeSpace — flip ScreenStable <-> WorldAttached, changing NOTHING
//                                              else. This is the A/B for the world-attached
//                                              verdict: orbit the architecture and only one of the two
//                                              may stay glued to it.
//
// Needs the HandDrawn master on disk: on a fresh checkout run "Ck_Usf_GenerateLooks HandDrawn" once in
// the editor console, or the subsystem warns and the view is untouched.
// --------------------------------------------------------------------------------------------------------------------

const int32 k_HandDrawnGym_PresetStationCount = 6;
const int32 k_HandDrawnGym_DebugStationCount = 3;

// How far in front of a station's alcove mouth the judging position sits. The alcove is 500uu deep, so
// 600 clears its front lip with standing room to spare.
const float k_HandDrawnGym_ViewingClearance = 600.0f;

class ACk_UsfStylizeHandDrawnGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FName> _StationTags;
    private TArray<FVector> _StationLocations;
    private AActor _JudgeScene;
    private int32 _ActiveStation = -1;
    private int32 _DebugIndex = 0;
    private bool _StackedOther = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnStorybookInk", "HAND-DRAWN: STORYBOOK INK",
            "Five colour regions, a wandering contour, screen-stable pencil hatching, warm grainy paper.",
            "Contours + hatching + grain all readable at once. The hatching must hold still on the MOVER — this is the screen-stable control."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnSoftPainted", "HAND-DRAWN: SOFT PAINTED",
            "Eight soft-edged regions, ink almost off, no hatching, heavy paper.",
            "Should read as watercolour: region EDGES, not drawn lines. Any hard contour left means the ink opacity is not reaching the shader."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnBoldAnimation", "HAND-DRAWN: BOLD ANIMATION",
            "Three hard regions, a thick line with zero wander, no hatching, no paper.",
            "Flat cel. The line must be perfectly steady — visible wobble here means LineVariation is not actually 0."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnDarkGothic", "HAND-DRAWN: DARK GOTHIC",
            "Two regions, heavy ragged line, dense WORLD-ATTACHED crosshatch reaching into the midtones.",
            "Orbit the architecture: the crosshatch must stay glued to the walls. On the mover it will slide — that is documented, not a defect."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnPencilWash", "HAND-DRAWN: PENCIL WASH",
            "Near-monochrome, light line, loose WORLD-ATTACHED scribble, strong paper.",
            "Graphite on a sheet. The scribble must follow the pillars' faces around their corners without smearing across the edge."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnOff", "HAND-DRAWN: OFF",
            "The A/B reference — the subsystem's blendable disabled.",
            "The frame must come back completely clean. Any residue here means disable is not actually disabling.",
            "STACKING: Ck_GymStylizeHandDrawn_ToggleDitherStack puts ScreenDither on top — legal, and the paper grain must survive quantization. Hand-drawn + cel is unsupported but harmless: both restyle the whole frame at the same chain location, so the ink ends up drawn over already-banded light."));

        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnDebugInk", "DEBUG: INK MASK",
            "StorybookInk with the ink mask forced on (white = inked).",
            "Contours only, on the spiked silhouette and the architecture corners. A solid white frame means a threshold is far too low."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnDebugStrokes", "DEBUG: SHADOW STROKE MASK",
            "StorybookInk with the shadow-stroke mask forced on.",
            "Hatching only, and only below the luminance threshold. The boundary must follow the SHADING on the ramp spheres, not their albedo."));
        Stations.Add(Make_Station(n"Gym.Stylize.HandDrawnDebugPaper", "DEBUG: PAPER PATTERN",
            "StorybookInk with the paper pattern forced on (mid grey = no deviation).",
            "Uniform speckle plus a directional fibre, ignoring the scene entirely. Anything scene-shaped here means paper is sampling the wrong space."));

        // Two explicit rows, each centred on its OWN count — a single global index would leave the short
        // back row hanging off one end of the long front one.
        //
        // Both rows sit BEHIND their judging line, alcoves opening toward the judge scene. Selection is
        // measured at Get_StationViewingPoint — one clearance in front of each mouth — so the player
        // judges from outside the alcove with the whole scene ahead of them, and only turns around to
        // read a panel. The judging lines land back at X=1800 / X=3000, the framing the presets were
        // tuned at.
        const float StationSpacing = 1200.0f;

        auto PresetRowStart = -(k_HandDrawnGym_PresetStationCount - 1) * StationSpacing * 0.5f;
        auto DebugRowStart = -(k_HandDrawnGym_DebugStationCount - 1) * StationSpacing * 0.5f;

        for (int32 i = 0; i < Stations.Num(); i++)
        {
            auto IsDebugRow = i >= k_HandDrawnGym_PresetStationCount;
            auto RowIndex = IsDebugRow ? i - k_HandDrawnGym_PresetStationCount : i;
            auto RowStart = IsDebugRow ? DebugRowStart : PresetRowStart;
            auto RowX = (IsDebugRow ? 3000.0f : 1800.0f) + k_HandDrawnGym_ViewingClearance;

            auto Xf = FTransform::Identity;
            Xf.SetLocation(FVector(RowX, RowStart + RowIndex * StationSpacing, 0.0f));
            Xf.SetRotation(FRotator(0.0f, 180.0f, 0.0f).Quaternion());
            Stations[i].Transform = Xf;
        }

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload Make_Station(FName InTag, FString InTitle, FString InLine1, FString InLine2, FString InLine3 = "")
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InLine1));
        Description.Add(FText::FromString(InLine2));
        if (InLine3 != "")
        { Description.Add(FText::FromString(InLine3)); }
        Station.Description = Description;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        Request_RebuildGym();
        ck::Trace("🟫 Stylize Hand-Drawn Gym - walk to a station to apply its preset");
    }

    private void Request_RebuildGym()
    {
        if (ck::IsValid(_JudgeScene))
        { _JudgeScene.DestroyActor(); }

        _JudgeScene = SpawnActor(ACk_UsfGym_StylizeHandDrawnJudgeScene, FVector(0.0f, 0.0f, 0.0f), FRotator::ZeroRotator);
        if (_JudgeScene == nullptr)
        { ck::Error("❌ Stylize Hand-Drawn Gym: failed to spawn the judge scene"); }

        _StationTags.Empty();
        _StationLocations.Empty();
        _StationTags.Add(n"Gym.Stylize.HandDrawnStorybookInk");
        _StationTags.Add(n"Gym.Stylize.HandDrawnSoftPainted");
        _StationTags.Add(n"Gym.Stylize.HandDrawnBoldAnimation");
        _StationTags.Add(n"Gym.Stylize.HandDrawnDarkGothic");
        _StationTags.Add(n"Gym.Stylize.HandDrawnPencilWash");
        _StationTags.Add(n"Gym.Stylize.HandDrawnOff");
        _StationTags.Add(n"Gym.Stylize.HandDrawnDebugInk");
        _StationTags.Add(n"Gym.Stylize.HandDrawnDebugStrokes");
        _StationTags.Add(n"Gym.Stylize.HandDrawnDebugPaper");

        for (auto Tag : _StationTags)
        { _StationLocations.Add(Get_StationViewingPoint(Tag)); }

        _ActiveStation = -1;
        _DebugIndex = 0;
        Request_ApplyStation(0);
    }

    // Where a player stands to judge from: one clearance out of the alcove mouth, on the judge-scene
    // side. The mouth is along the station's own forward axis, so this follows the row's rotation
    // instead of assuming an axis. Selecting on the station's OWN location would put the player inside
    // the alcove facing its back wall, with the judge scene behind them — you cannot look at the
    // content while choosing the preset that restyles it.
    private FVector Get_StationViewingPoint(FName InTag)
    {
        auto Xf = Get_StationTransform(InTag.ToString());
        return Xf.Location + Xf.Rotator().GetForwardVector() * k_HandDrawnGym_ViewingClearance;
    }

    // The station a player is standing at is the selection: there is no per-station subject to interact
    // with, so proximity IS the input.
    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        auto Pawn = GetControlledPawn();
        if (!System::IsValid(Pawn) || _StationLocations.Num() == 0)
        { return; }

        // Checked BEFORE selecting: without the subsystem the apply cannot succeed, and running the
        // selection anyway would re-enter Request_ApplyStation every tick (which never records
        // _ActiveStation on that path) and spam the log forever.
        if (UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem() == nullptr)
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
        // A challenger has to be meaningfully closer than the station already showing: the 0.8 factor is
        // applied in distance-SQUARED, so the real bar is ~10% closer in linear distance, not 20%.
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
        auto Subsystem = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("Stylize Hand-Drawn Gym: HandDrawn subsystem unavailable");
            return;
        }

        auto Preset = Get_PresetAt(InIndex);
        if (Preset == nullptr)
        { return; }

        _ActiveStation = InIndex;
        Subsystem.Apply_Preset(Preset);

        // A debug station is StorybookInk plus one forced mask, applied as a second write so the preset
        // stays the authored value and the mask is visibly a view ON it.
        _DebugIndex = Get_DebugIndexForStation(InIndex);
        if (_DebugIndex != 0)
        {
            auto Settings = Subsystem.Get_Settings();
            Settings.Set_DebugMode(Get_DebugModeAt(_DebugIndex));
            Subsystem.Request_SetSettings(Settings);
        }

        PrintToScreen("HAND-DRAWN: " + Get_StationNameAt(InIndex), 2.0, FLinearColor::Yellow);
    }

    private UCkUsf_HandDrawnPreset Get_PresetAt(int32 InIndex)
    {
        if (InIndex == 0) { return CkUsf::DA_HandDrawn_StorybookInk; }
        if (InIndex == 1) { return CkUsf::DA_HandDrawn_SoftPainted; }
        if (InIndex == 2) { return CkUsf::DA_HandDrawn_BoldAnimation; }
        if (InIndex == 3) { return CkUsf::DA_HandDrawn_DarkGothic; }
        if (InIndex == 4) { return CkUsf::DA_HandDrawn_PencilWash; }
        if (InIndex == 5) { return CkUsf::DA_HandDrawn_Off; }

        // The three debug stations all sit on the reference style, so the mask being viewed is the mask
        // the StorybookInk verdict is actually about.
        if (InIndex >= k_HandDrawnGym_PresetStationCount)
        { return CkUsf::DA_HandDrawn_StorybookInk; }

        return nullptr;
    }

    // 0 for every preset station; the debug stations map onto the ECk_Usf_HandDrawn_DebugMode indices
    // they are named for.
    private int32 Get_DebugIndexForStation(int32 InIndex) const
    {
        if (InIndex == 6) { return 1; }   // InkMask
        if (InIndex == 7) { return 2; }   // ShadowStrokeMask
        if (InIndex == 8) { return 3; }   // PaperPattern
        return 0;
    }

    // const because PrintToScreen is a development-only call and AngelScript rejects non-const members
    // inside one — the compiler cannot prove the call is side-effect-free in a shipping build otherwise.
    private FString Get_StationNameAt(int32 InIndex) const
    {
        if (InIndex == 0) { return "StorybookInk"; }
        if (InIndex == 1) { return "SoftPainted"; }
        if (InIndex == 2) { return "BoldAnimation"; }
        if (InIndex == 3) { return "DarkGothic"; }
        if (InIndex == 4) { return "PencilWash"; }
        if (InIndex == 5) { return "Off"; }
        if (InIndex == 6) { return "StorybookInk + debug InkMask"; }
        if (InIndex == 7) { return "StorybookInk + debug ShadowStrokeMask"; }
        if (InIndex == 8) { return "StorybookInk + debug PaperPattern"; }
        return "?";
    }

    private ECk_Usf_HandDrawn_DebugMode Get_DebugModeAt(int32 InIndex)
    {
        if (InIndex == 1) { return ECk_Usf_HandDrawn_DebugMode::InkMask; }
        if (InIndex == 2) { return ECk_Usf_HandDrawn_DebugMode::ShadowStrokeMask; }
        if (InIndex == 3) { return ECk_Usf_HandDrawn_DebugMode::PaperPattern; }
        if (InIndex == 4) { return ECk_Usf_HandDrawn_DebugMode::WorldNormals; }
        if (InIndex == 5) { return ECk_Usf_HandDrawn_DebugMode::SceneDepth; }
        return ECk_Usf_HandDrawn_DebugMode::FinalImage;
    }

    private FString Get_DebugNameAt(int32 InIndex) const
    {
        if (InIndex == 1) { return "InkMask"; }
        if (InIndex == 2) { return "ShadowStrokeMask"; }
        if (InIndex == 3) { return "PaperPattern"; }
        if (InIndex == 4) { return "WorldNormals"; }
        if (InIndex == 5) { return "SceneDepth"; }
        return "FinalImage";
    }

    UFUNCTION(Exec, DisplayName="Stylize Hand-Drawn Gym - Restart")
    void Ck_GymStylizeHandDrawn_RestartAll()
    {
        Request_RebuildGym();
    }

    // Cycles the PRESET row only: the debug stations are a view onto StorybookInk, not styles to walk.
    UFUNCTION(Exec, DisplayName="Stylize Hand-Drawn Gym - Cycle Preset")
    void Ck_GymStylizeHandDrawn_CyclePreset()
    {
        auto Next = (_ActiveStation + 1) % k_HandDrawnGym_PresetStationCount;
        Request_ApplyStation(Next);
    }

    // Debug views are a property of the CURRENT settings, so this edits them in place rather than
    // re-applying a preset — walking to another station resets it, which is the intended behaviour.
    UFUNCTION(Exec, DisplayName="Stylize Hand-Drawn Gym - Cycle Debug Mode")
    void Ck_GymStylizeHandDrawn_CycleDebug()
    {
        auto Subsystem = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem();
        if (Subsystem == nullptr)
        { return; }

        _DebugIndex = (_DebugIndex + 1) % 6;

        auto Settings = Subsystem.Get_Settings();
        Settings.Set_DebugMode(Get_DebugModeAt(_DebugIndex));
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("HAND-DRAWN debug: " + Get_DebugNameAt(_DebugIndex), 2.0, FLinearColor::Green);
    }

    // The world-attached verdict in one keypress: everything else is held, so any difference in
    // how the strokes behave under camera orbit is the stroke SPACE and nothing else.
    UFUNCTION(Exec, DisplayName="Stylize Hand-Drawn Gym - Toggle Stroke Space")
    void Ck_GymStylizeHandDrawn_ToggleStrokeSpace()
    {
        auto Subsystem = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem();
        if (Subsystem == nullptr)
        { return; }

        auto Settings = Subsystem.Get_Settings();
        auto WasWorldAttached = Settings.Get_StrokeSpace() == ECk_Usf_HandDrawnStrokeSpace::WorldAttached;

        Settings.Set_StrokeSpace(WasWorldAttached
            ? ECk_Usf_HandDrawnStrokeSpace::ScreenStable
            : ECk_Usf_HandDrawnStrokeSpace::WorldAttached);
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("HAND-DRAWN stroke space: " + (WasWorldAttached ? "ScreenStable" : "WorldAttached"),
            2.0, FLinearColor::Green);
    }

    // Cross-effect stacking A/B. ScreenDither is the legal partner: hand-drawn restyles before
    // tonemapping and dither reduces the palette after it, so the paper grain reaches the quantizer
    // rather than being replaced by it. The toggle owns its own flag rather than reading Get_IsEnabled(),
    // because a subsystem nothing has touched yet reports Enabled while rendering nothing — reading it
    // would make the first press a silent no-op.
    UFUNCTION(Exec, DisplayName="Stylize Hand-Drawn Gym - Toggle ScreenDither Stack")
    void Ck_GymStylizeHandDrawn_ToggleDitherStack()
    {
        auto Dither = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem();
        if (Dither == nullptr)
        { return; }

        _StackedOther = !_StackedOther;

        if (_StackedOther)
        { Dither.Apply_Preset(CkUsf::DA_Dither_Balanced); }
        else
        { Dither.Request_SetEnabled(ECk_EnableDisable::Disable); }

        PrintToScreen("HAND-DRAWN + ScreenDither stack: " + (_StackedOther ? "ON" : "OFF"), 2.0, FLinearColor::Green);
    }

}
