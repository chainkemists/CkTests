// --------------------------------------------------------------------------------------------------------------------
// Cross-Hatch gym ("Stylize: Cross Hatch" in the cycler).
//
// CrossHatch is a VIEW-WIDE post-process, so the stations cannot each own a subject the way the Solid
// Outline gym's do - there is only ever one frame. They are PRESET SELECTORS instead: walk up to a
// station and its preset is applied to the whole view. Everything is judged against the single shared
// judge scene (ACk_UsfGym_StylizeCrossHatchJudgeScene), which is what makes two presets comparable.
//
// Three rows, each centred on its own count:
//   front row (4) - the authored presets
//   mid row   (2) - the effect MASK, Include and Exclude, over one preset. The mask row is the only one
//                   with per-object subjects: the judge scene's hand-tagged cubes and the entity-API
//                   subjects spawned here must look identical to each other under both modes.
//   back row  (3) - Sketch with one debug view forced on, because a mask is the only way to tell "the
//                   detector found nothing" from "the detector found everything at low opacity".
//
// Tab opens the gym cycler menu; search "Stylize". Console:
//   Ck_GymStylizeCrossHatch_RestartAll        - respawn the judge scene and re-apply Sketch
//   Ck_GymStylizeCrossHatch_CyclePreset       - next preset without walking
//   Ck_GymStylizeCrossHatch_CycleDebug        - next debug view of the CURRENT settings
//   Ck_GymStylizeCrossHatch_ToggleNormalSpace - flip view-space <-> world-space normals, changing NOTHING
//                                               else. THE headline A/B: orbit the sphere row and only the
//                                               view-space mode may keep its strokes wrapping the form.
//   Ck_GymStylizeCrossHatch_ToggleAlignment   - flip NormalAlignment 1 <-> 0. At 0 the hatch is a fixed
//                                               screen angle, which is the control that proves the
//                                               alignment does anything at all.
//   Ck_GymStylizeCrossHatch_ToggleEntityMask  - add/remove the entity subjects from the mask, so the
//                                               REMOVE path is exercised and not just the apply.
//   Ck_GymStylizeCrossHatch_ToggleHandDrawnStack / _ToggleDitherStack - the stacking claim on the Off
//                                               station's panel, made testable rather than asserted.
//
// Needs the CrossHatch master on disk: on a fresh checkout run "Ck_Usf_GenerateLooks CrossHatch" once in
// the editor console, or the subsystem warns and the view is untouched. The mask row additionally needs
// r.CustomDepth 3 (Custom Depth-Stencil WITH stencil).
// --------------------------------------------------------------------------------------------------------------------

const int32 k_CrossHatchGym_PresetStationCount = 4;
const int32 k_CrossHatchGym_MaskStationCount = 2;
const int32 k_CrossHatchGym_DebugStationCount = 3;

// How far in front of a station's alcove mouth the judging position sits. The alcove is 500uu deep, so
// 600 clears its front lip with standing room to spare.
const float k_CrossHatchGym_ViewingClearance = 600.0f;

class ACk_UsfStylizeCrossHatchGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FName> _StationTags;
    private TArray<FVector> _StationLocations;
    private AActor _JudgeScene;
    private TArray<ACk_UsfGym_StylizeCrossHatchMaskSubject> _MaskSubjects;
    // Tracked locally rather than read back from the subsystems: their settings default to Enabled while
    // the effect itself is created lazily, so an untouched subsystem reports Enabled and renders nothing.
    private bool _HandDrawnStacked = false;
    private bool _DitherStacked = false;
    private int32 _ActiveStation = -1;
    private int32 _DebugIndex = 0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchSketch", "CROSS-HATCH: SKETCH",
            "Three loose pencil layers on a warm sheet, direction following the form.",
            "Walk around the sphere row: the strokes must WRAP each form and sweep continuously across it. Strokes that hold one screen angle mean the normal is not reaching the direction."));
        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchEngraving", "CROSS-HATCH: ENGRAVING",
            "Four fine, near-perfectly-regular crosshatch layers on a cool bright sheet.",
            "Copperplate. Lines must be crisp and even - visible wobble here means StrokeIrregularity is not actually near zero."));
        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchBlueprint", "CROSS-HATCH: BLUEPRINT",
            "White ink on blue, ONE layer, and NormalAlignment at 0.",
            "The control: hatching must run at ONE fixed screen angle everywhere, ignoring the forms completely. If it still curves around the sphere, NormalAlignment is not reaching the shader."));
        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchOff", "CROSS-HATCH: OFF",
            "The A/B reference - the subsystem's blendable disabled.",
            "The frame must come back completely clean. Any residue here means disable is not actually disabling.",
            "STACKING: cross-hatch and hand-drawn both restyle the whole frame at the same chain location, so the second simply paints over the first. Cross-hatch + screen dither composes, like the other pre-TAA looks."));

        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchMaskInclude", "MASK: INCLUDE RANGE",
            "Sketch, confined to the mask stencil range - ONLY the tagged cubes are hatched.",
            "Both cubes in the judge scene's mask row AND the two entity-API subjects here must be hatched, and NOTHING else. The two pairs must be indistinguishable - same byte, different front doors."));
        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchMaskExclude", "MASK: EXCLUDE RANGE",
            "Sketch everywhere EXCEPT the mask stencil range - the tagged cubes stay untouched.",
            "The exact inverse of the previous station. A cube that changes between the two modes in any way other than hatched/not-hatched means the mask is lerping toward something that is not the original frame."));

        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchDebugMask", "DEBUG: HATCH MASK",
            "Sketch with the hatch mask forced on (white = inked).",
            "Stroke coverage only. Solid white means the darkness ramp is saturated - check DarknessBias."));
        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchDebugDirection", "DEBUG: HATCH DIRECTION",
            "RG = the hatch direction remapped to 0..1, B = the projected normal's length.",
            "A smoothly turning surface must show a SMOOTH sweep. Hard patches are pixels whose normal projects to nothing and fell back to AngleOffset - expected at the centre of a sphere facing the camera, wrong anywhere else."));
        Stations.Add(Make_Station(n"Gym.Stylize.CrossHatchDebugLayers", "DEBUG: LAYER COVERAGE",
            "How many stroke layers this pixel's darkness has reached.",
            "Must be a stepped ramp following the SHADING on the sphere row, not their albedo - the layers step with darkness, and darkness is normalized luminance."));

        // Three explicit rows, each centred on its OWN count - a single global index would leave the
        // short rows hanging off one end of the long one.
        //
        // Every row sits BEHIND its judging line, alcoves opening toward the judge scene. Selection is
        // measured at Get_StationViewingPoint - one clearance in front of each mouth - so the player
        // judges from outside the alcove with the whole scene ahead of them, and only turns around to
        // read a panel.
        const float StationSpacing = 1200.0f;

        auto PresetRowStart = -(k_CrossHatchGym_PresetStationCount - 1) * StationSpacing * 0.5f;
        auto MaskRowStart = -(k_CrossHatchGym_MaskStationCount - 1) * StationSpacing * 0.5f;
        auto DebugRowStart = -(k_CrossHatchGym_DebugStationCount - 1) * StationSpacing * 0.5f;

        for (int32 i = 0; i < Stations.Num(); i++)
        {
            auto RowIndex = i;
            auto RowStart = PresetRowStart;
            auto RowX = 1800.0f;

            if (i >= k_CrossHatchGym_PresetStationCount + k_CrossHatchGym_MaskStationCount)
            {
                RowIndex = i - k_CrossHatchGym_PresetStationCount - k_CrossHatchGym_MaskStationCount;
                RowStart = DebugRowStart;
                RowX = 4200.0f;
            }
            else if (i >= k_CrossHatchGym_PresetStationCount)
            {
                RowIndex = i - k_CrossHatchGym_PresetStationCount;
                RowStart = MaskRowStart;
                RowX = 3000.0f;
            }

            auto Xf = FTransform::Identity;
            Xf.SetLocation(FVector(RowX + k_CrossHatchGym_ViewingClearance,
                RowStart + RowIndex * StationSpacing, 0.0f));
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
        ck::Trace("* Stylize Cross-Hatch Gym - walk to a station to apply its preset");
    }

    private void Request_RebuildGym()
    {
        if (ck::IsValid(_JudgeScene))
        { _JudgeScene.DestroyActor(); }

        for (auto Subject : _MaskSubjects)
        {
            if (ck::IsValid(Subject))
            { Subject.DestroyActor(); }
        }
        _MaskSubjects.Empty();

        _JudgeScene = SpawnActor(ACk_UsfGym_StylizeCrossHatchJudgeScene, FVector(0.0f, 0.0f, 0.0f), FRotator::ZeroRotator);
        if (_JudgeScene == nullptr)
        { ck::Error("[FAIL] Stylize Cross-Hatch Gym: failed to spawn the judge scene"); }

        // Same X, same scale, same albedo as the judge scene's hand-tagged mask cubes, offset one step in
        // Y so each hand-tagged cube sits immediately beside its entity twin. The verdict on this row is
        // "indistinguishable", and that is only cheap to make if the pair is in one glance - the Cel
        // gym's contract for its own stencil row.
        for (int32 i = 0; i < 2; i++)
        {
            auto Subject = Cast<ACk_UsfGym_StylizeCrossHatchMaskSubject>(SpawnActor(
                ACk_UsfGym_StylizeCrossHatchMaskSubject,
                FVector(-900.0f, 570.0f + float(i) * 640.0f, 150.0f), FRotator::ZeroRotator));

            if (Subject != nullptr)
            { _MaskSubjects.Add(Subject); }
        }

        _StationTags.Empty();
        _StationLocations.Empty();
        _StationTags.Add(n"Gym.Stylize.CrossHatchSketch");
        _StationTags.Add(n"Gym.Stylize.CrossHatchEngraving");
        _StationTags.Add(n"Gym.Stylize.CrossHatchBlueprint");
        _StationTags.Add(n"Gym.Stylize.CrossHatchOff");
        _StationTags.Add(n"Gym.Stylize.CrossHatchMaskInclude");
        _StationTags.Add(n"Gym.Stylize.CrossHatchMaskExclude");
        _StationTags.Add(n"Gym.Stylize.CrossHatchDebugMask");
        _StationTags.Add(n"Gym.Stylize.CrossHatchDebugDirection");
        _StationTags.Add(n"Gym.Stylize.CrossHatchDebugLayers");

        for (auto Tag : _StationTags)
        { _StationLocations.Add(Get_StationViewingPoint(Tag)); }

        _ActiveStation = -1;
        _DebugIndex = 0;
        Request_ApplyStation(0);
    }

    // Where a player stands to judge from: one clearance out of the alcove mouth, on the judge-scene
    // side. The mouth is along the station's own forward axis, so this follows the row's rotation
    // instead of assuming an axis. Selecting on the station's OWN location would put the player inside
    // the alcove facing its back wall, with the judge scene behind them - you cannot look at the
    // content while choosing the preset that restyles it.
    private FVector Get_StationViewingPoint(FName InTag)
    {
        auto Xf = Get_StationTransform(InTag.ToString());
        return Xf.Location + Xf.Rotator().GetForwardVector() * k_CrossHatchGym_ViewingClearance;
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
        if (UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem() == nullptr)
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
        auto Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("Stylize Cross-Hatch Gym: CrossHatch subsystem unavailable");
            return;
        }

        auto Preset = Get_PresetAt(InIndex);
        if (Preset == nullptr)
        { return; }

        _ActiveStation = InIndex;
        Subsystem.Apply_Preset(Preset);

        // The mask and debug stations are Sketch plus one field, applied as a second write so the preset
        // stays the authored value and the override is visibly a view ON it.
        auto MaskMode = Get_MaskModeForStation(InIndex);
        _DebugIndex = Get_DebugIndexForStation(InIndex);

        if (MaskMode != ECk_Usf_StylizeMaskMode::Off || _DebugIndex != 0)
        {
            auto Settings = Subsystem.Get_Settings();

            if (MaskMode != ECk_Usf_StylizeMaskMode::Off)
            {
                // Both bounds from the project setting: a project that moves the reservation must move
                // this station with it, or the mask silently stops selecting anything.
                auto MaskStencil = UCk_Utils_Usf_Stylize_Settings_UE::Get_MaskStencilValue();
                auto Mask = FCk_Usf_StylizeMask_Params();
                Mask.Set_Mode(MaskMode);
                Mask.Set_StencilMin(MaskStencil);
                Mask.Set_StencilMax(MaskStencil);
                Settings.Set_Mask(Mask);
            }

            if (_DebugIndex != 0)
            { Settings.Set_DebugMode(Get_DebugModeAt(_DebugIndex)); }

            Subsystem.Request_SetSettings(Settings);
        }

        PrintToScreen("CROSS-HATCH: " + Get_StationNameAt(InIndex), 2.0, FLinearColor::Yellow);
    }

    private UCkUsf_CrossHatchPreset Get_PresetAt(int32 InIndex)
    {
        if (InIndex == 0) { return CkUsf::DA_CrossHatch_Sketch; }
        if (InIndex == 1) { return CkUsf::DA_CrossHatch_Engraving; }
        if (InIndex == 2) { return CkUsf::DA_CrossHatch_Blueprint; }
        if (InIndex == 3) { return CkUsf::DA_CrossHatch_Off; }

        // The mask and debug stations all sit on the reference style, so what is being viewed is a
        // property OF the Sketch verdict rather than of some other preset.
        if (InIndex >= k_CrossHatchGym_PresetStationCount)
        { return CkUsf::DA_CrossHatch_Sketch; }

        return nullptr;
    }

    private ECk_Usf_StylizeMaskMode Get_MaskModeForStation(int32 InIndex) const
    {
        if (InIndex == 4) { return ECk_Usf_StylizeMaskMode::IncludeStencilRange; }
        if (InIndex == 5) { return ECk_Usf_StylizeMaskMode::ExcludeStencilRange; }
        return ECk_Usf_StylizeMaskMode::Off;
    }

    // 0 for every non-debug station; the debug stations map onto the ECk_Usf_CrossHatch_DebugMode
    // indices they are named for.
    private int32 Get_DebugIndexForStation(int32 InIndex) const
    {
        if (InIndex == 6) { return 1; }   // HatchMask
        if (InIndex == 7) { return 2; }   // HatchDirection
        if (InIndex == 8) { return 4; }   // LayerCoverage
        return 0;
    }

    // const because PrintToScreen is a development-only call and AngelScript rejects non-const members
    // inside one - the compiler cannot prove the call is side-effect-free in a shipping build otherwise.
    private FString Get_StationNameAt(int32 InIndex) const
    {
        if (InIndex == 0) { return "Sketch"; }
        if (InIndex == 1) { return "Engraving"; }
        if (InIndex == 2) { return "Blueprint"; }
        if (InIndex == 3) { return "Off"; }
        if (InIndex == 4) { return "Sketch + mask INCLUDE"; }
        if (InIndex == 5) { return "Sketch + mask EXCLUDE"; }
        if (InIndex == 6) { return "Sketch + debug HatchMask"; }
        if (InIndex == 7) { return "Sketch + debug HatchDirection"; }
        if (InIndex == 8) { return "Sketch + debug LayerCoverage"; }
        return "?";
    }

    private ECk_Usf_CrossHatch_DebugMode Get_DebugModeAt(int32 InIndex)
    {
        if (InIndex == 1) { return ECk_Usf_CrossHatch_DebugMode::HatchMask; }
        if (InIndex == 2) { return ECk_Usf_CrossHatch_DebugMode::HatchDirection; }
        if (InIndex == 3) { return ECk_Usf_CrossHatch_DebugMode::Darkness; }
        if (InIndex == 4) { return ECk_Usf_CrossHatch_DebugMode::LayerCoverage; }
        if (InIndex == 5) { return ECk_Usf_CrossHatch_DebugMode::WorldNormals; }
        if (InIndex == 6) { return ECk_Usf_CrossHatch_DebugMode::StylizeMask; }
        return ECk_Usf_CrossHatch_DebugMode::Final;
    }

    private FString Get_DebugNameAt(int32 InIndex) const
    {
        if (InIndex == 1) { return "HatchMask"; }
        if (InIndex == 2) { return "HatchDirection"; }
        if (InIndex == 3) { return "Darkness"; }
        if (InIndex == 4) { return "LayerCoverage"; }
        if (InIndex == 5) { return "WorldNormals"; }
        if (InIndex == 6) { return "StylizeMask"; }
        return "Final";
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Normal space and alignment are read back off the subsystem rather than mirrored in a flag here: they
    // are settings the subsystem genuinely owns, and a mirror would be a second source of truth for the
    // exact value this gym exists to A/B. The two STACK flags are mirrored, and cannot be read back
    // an untouched subsystem reports Enabled while rendering nothing.
    //
    // Conditional rows go LAST so a row that appears in only one state cannot shift the index of a keyed
    // row above it.
    //--------------------------------------------------------------------------------------------------------------------------

    // Row 0 is the stations header; the stations follow it.
    private const int32 FirstStationRow = 1;

    private int32 Get_FirstControlRow() const
    {
        return FirstStationRow + _StationTags.Num();
    }

    private bool Get_UsesWorldSpaceNormals()
    {
        auto Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem();

        if (Subsystem == nullptr)
        { return false; }

        auto Settings = Subsystem.Get_Settings();
        return Settings.Get_UseWorldSpaceNormals() == ECk_EnableDisable::Enable;
    }

    private bool Get_NormalsFollowForm()
    {
        auto Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem();

        if (Subsystem == nullptr)
        { return false; }

        auto Settings = Subsystem.Get_Settings();
        return Settings.Get_NormalAlignment() > 0.5f;
    }

    FString Get_ControlPanelTitle() override
    {
        return "CROSS-HATCH";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("STATIONS  -  press a number, or walk to one"));

        for (int32 Index = 0; Index < _StationTags.Num(); Index++)
        { Rows.Add(CkGym_Control::Numbered(Index, Get_StationNameAt(Index), Index == _ActiveStation)); }

        Rows.Add(CkGym_Control::Header("THE A/B"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::N, "N", "Normal space", Get_UsesWorldSpaceNormals(), "WORLD", "VIEW"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::A, "A", "Alignment", Get_NormalsFollowForm(), "follows form", "fixed angle"));

        Rows.Add(CkGym_Control::Header("VIEW"));
        Rows.Add(CkGym_Control::Cycle(EKeys::D, "D", "Debug view", Get_DebugNameAt(_DebugIndex), _DebugIndex != 0));

        // An Action rather than a Toggle: each subject owns its own mask state, so there is no single
        // value to report and a two-state row here would be guessing at one.
        Rows.Add(CkGym_Control::Action(EKeys::E, "E", "Flip entity masks"));
        Rows.Add(CkGym_Control::Toggle(EKeys::X, "X", "Stack Hand-Drawn over", _HandDrawnStacked));
        Rows.Add(CkGym_Control::Toggle(EKeys::C, "C", "Stack ScreenDither over", _DitherStacked));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Rebuild judge scene"));

        // A debug view is not the effect. Someone who left one on and walked away would otherwise judge
        // an intermediate buffer as though it were the finished frame.
        if (_DebugIndex != 0)
        { Rows.Add(CkGym_Control::Status("Showing a DEBUG buffer, not the final image", "", true)); }

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex >= FirstStationRow && InRowIndex < Get_FirstControlRow())
        {
            Request_ApplyStation(InRowIndex - FirstStationRow);
            return;
        }

        // Offsets 0 and 3 are the two headers, which hold no key and never arrive here.
        auto Control = InRowIndex - Get_FirstControlRow();

        if (Control == 1) { Ck_GymStylizeCrossHatch_ToggleNormalSpace(); }
        else if (Control == 2) { Ck_GymStylizeCrossHatch_ToggleAlignment(); }
        else if (Control == 4) { Ck_GymStylizeCrossHatch_CycleDebug(); }
        else if (Control == 5) { Ck_GymStylizeCrossHatch_ToggleEntityMask(); }
        else if (Control == 6) { Ck_GymStylizeCrossHatch_ToggleHandDrawnStack(); }
        else if (Control == 7) { Ck_GymStylizeCrossHatch_ToggleDitherStack(); }
        else if (Control == 8) { Request_RebuildGym(); }
    }

    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Restart")
    void Ck_GymStylizeCrossHatch_RestartAll()
    {
        Request_RebuildGym();
    }

    // Cycles the PRESET row only: the mask and debug stations are views onto Sketch, not styles to walk.
    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Cycle Preset")
    void Ck_GymStylizeCrossHatch_CyclePreset()
    {
        // Clamped into the preset row first: _ActiveStation can be -1 (nothing selected yet) or point at
        // a mask/debug station, and while (-1 + 1) % 4 == 0 works by luck, (8 + 1) % 4 == 1 silently
        // skips Sketch. Clamping makes the Exec mean "walk the preset row" from wherever the player is.
        auto Current = _ActiveStation;
        if (Current < 0 || Current >= k_CrossHatchGym_PresetStationCount)
        { Current = -1; }

        auto Next = (Current + 1) % k_CrossHatchGym_PresetStationCount;
        Request_ApplyStation(Next);
    }

    // The stacking claim the Off station's panel makes, made testable. Cross-hatch and hand-drawn both
    // restyle the whole frame at the same chain location, so whichever blendable renders second wins.
    // Screen dither sits post-tonemap and genuinely composes - that contrast is what makes the first
    // result mean something rather than looking like a bug.
    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Toggle Hand-Drawn Stack")
    void Ck_GymStylizeCrossHatch_ToggleHandDrawnStack()
    {
        auto Subsystem = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("Stylize Cross-Hatch Gym: HandDrawn subsystem unavailable");
            return;
        }

        _HandDrawnStacked = !_HandDrawnStacked;
        Subsystem.Request_SetEnabled(_HandDrawnStacked ? ECk_EnableDisable::Enable : ECk_EnableDisable::Disable);

        PrintToScreen("CROSS-HATCH + hand-drawn stack: " + (_HandDrawnStacked ? "ON" : "OFF"),
            2.0, FLinearColor::Green);
    }

    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Toggle Screen Dither Stack")
    void Ck_GymStylizeCrossHatch_ToggleDitherStack()
    {
        auto Subsystem = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("Stylize Cross-Hatch Gym: ScreenDither subsystem unavailable");
            return;
        }

        _DitherStacked = !_DitherStacked;
        Subsystem.Request_SetEnabled(_DitherStacked ? ECk_EnableDisable::Enable : ECk_EnableDisable::Disable);

        PrintToScreen("CROSS-HATCH + screen dither stack: " + (_DitherStacked ? "ON" : "OFF"),
            2.0, FLinearColor::Green);
    }

    // Debug views are a property of the CURRENT settings, so this edits them in place rather than
    // re-applying a preset - walking to another station resets it, which is the intended behaviour.
    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Cycle Debug Mode")
    void Ck_GymStylizeCrossHatch_CycleDebug()
    {
        auto Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem();
        if (Subsystem == nullptr)
        { return; }

        _DebugIndex = (_DebugIndex + 1) % 7;

        auto Settings = Subsystem.Get_Settings();
        Settings.Set_DebugMode(Get_DebugModeAt(_DebugIndex));
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("CROSS-HATCH debug: " + Get_DebugNameAt(_DebugIndex), 2.0, FLinearColor::Green);
    }

    // THE headline A/B. Everything else is held, so any difference in how the strokes behave under
    // camera orbit is the normal SPACE and nothing else: view-space keeps them wrapping each form,
    // world-space re-orients them as the camera moves around a static object.
    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Toggle Normal Space")
    void Ck_GymStylizeCrossHatch_ToggleNormalSpace()
    {
        auto Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem();
        if (Subsystem == nullptr)
        { return; }

        auto Settings = Subsystem.Get_Settings();
        auto WasWorld = Settings.Get_UseWorldSpaceNormals() == ECk_EnableDisable::Enable;

        Settings.Set_UseWorldSpaceNormals(WasWorld ? ECk_EnableDisable::Disable : ECk_EnableDisable::Enable);
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("CROSS-HATCH normals: " + (WasWorld ? "View space" : "World space"),
            2.0, FLinearColor::Green);
    }

    // The control for the above: at 0 the hatch is a fixed screen angle. If the picture does not change
    // when this is toggled, the projected normal is not reaching the direction at all.
    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Toggle Normal Alignment")
    void Ck_GymStylizeCrossHatch_ToggleAlignment()
    {
        auto Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem();
        if (Subsystem == nullptr)
        { return; }

        auto Settings = Subsystem.Get_Settings();
        auto WasAligned = Settings.Get_NormalAlignment() > 0.5f;

        Settings.Set_NormalAlignment(WasAligned ? 0.0f : 1.0f);
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("CROSS-HATCH alignment: " + (WasAligned ? "0 (fixed screen angle)" : "1 (follows form)"),
            2.0, FLinearColor::Green);
    }

    // Exercises the REMOVE half of the entity API. An apply that is never undone proves only that
    // something was written once, not that the removal processor gives the mesh back.
    UFUNCTION(Exec, DisplayName="Stylize Cross-Hatch Gym - Toggle Entity Mask")
    void Ck_GymStylizeCrossHatch_ToggleEntityMask()
    {
        for (auto Subject : _MaskSubjects)
        {
            if (ck::IsValid(Subject))
            { Subject.Request_ToggleMask(); }
        }

        PrintToScreen("CROSS-HATCH entity mask toggled", 2.0, FLinearColor::Green);
    }
}
