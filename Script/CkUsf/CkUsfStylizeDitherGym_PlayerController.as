// --------------------------------------------------------------------------------------------------------------------
// Screen Dither gym ("Stylize: Screen Dither" in the cycler).
//
// ScreenDither is a VIEW-WIDE post-process, so the stations cannot each own a subject the way the Solid
// Outline gym's do - there is only ever one frame. They are PRESET SELECTORS instead: walk up to a
// station and its preset is applied to the whole view. Everything is judged against the single shared
// judge scene (ACk_UsfGym_StylizeDitherJudgeScene), which is what makes two presets comparable at all.
//
// Tab opens the gym cycler menu; search "Stylize". Console:
//   Ck_GymStylizeDither_RestartAll     - respawn the judge scene and re-apply Balanced
//   Ck_GymStylizeDither_CycleDebug     - next debug view of the CURRENT preset
//   Ck_GymStylizeDither_ToggleCelStack - stack CelShade underneath, for the cross-effect A/B
//
// Needs the ScreenDither master on disk: on a fresh checkout run "Ck_Usf_GenerateLooks ScreenDither"
// once in the editor console, or the subsystem warns and the view is untouched.
// --------------------------------------------------------------------------------------------------------------------

// How far in front of a station's alcove mouth the judging position sits. The alcove is 500uu deep, so
// 600 clears its front lip with standing room to spare.
const float k_DitherGym_ViewingClearance = 600.0f;

class ACk_UsfStylizeDitherGym_PlayerController : ACk_Gym_Base_PlayerController
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

        Stations.Add(Make_Station(n"Gym.Stylize.DitherBalanced", "DITHER: BALANCED",
            "Bayer 4x4 over 8 steps per channel, full resolution.",
            "The gradient wall should gain a fine print-like texture, NOT visible bands."));
        Stations.Add(Make_Station(n"Gym.Stylize.DitherSubtleColor", "DITHER: SUBTLE COLOUR",
            "16 steps, soft threshold, half weight - banding cleanup rather than a style.",
            "Colours stay the scene's own; only the gradient wall should read as changed."));
        Stations.Add(Make_Station(n"Gym.Stylize.DitherRetroPixel", "DITHER: RETRO PIXEL",
            "4px blocks, 5 steps, box-filtered downsample.",
            "Whole frame pixelated and palette-reduced. The mover must not smear - if it does, TAA is eating the pattern."));
        Stations.Add(Make_Station(n"Gym.Stylize.DitherFourColor", "DITHER: 4-COLOUR HANDHELD",
            "Custom 4-entry green palette, 3px blocks, Bayer 2x2.",
            "EXACTLY four colours on screen, with visible ordered dither between them - banding without dither means the threshold is applied after quantization."));
        Stations.Add(Make_Station(n"Gym.Stylize.DitherScreenPrint", "DITHER: SCREEN PRINT",
            "Five steps on the LUMINANCE only - Balanced's pattern, scale and strength, quantizing tone instead of channels.",
            "Saturated surfaces must keep their hue and only jump in brightness. A hue that shifts at a band edge means the luminance path fell through to per-channel quantization."));
        Stations.Add(Make_Station(n"Gym.Stylize.DitherAnimatedGrain", "DITHER: ANIMATED GRAIN",
            "Blue-noise threshold re-rolled 20x a second, 10 steps, full resolution.",
            "Should read as film grain in motion. Blotchy clumping means the blue-noise approximation degenerated to white noise."));
        Stations.Add(Make_Station(n"Gym.Stylize.DitherOff", "DITHER: OFF",
            "The A/B reference - the subsystem's blendable disabled.",
            "The frame must come back completely clean. Any residue here means disable is not actually disabling.",
            "STACKING: Ck_GymStylizeDither_ToggleCelStack puts CelShade underneath. The two sit at different chain locations (cel pre-TAA, dither post-tonemap), so cel bands the light and dither quantizes the result - the classic combo, and neither reads the other's parameters."));

        // Explicit single row, wider than the 800uu default: the judge scene sits in front of these and
        // the player has to be able to walk the row without leaving it.
        //
        // The row sits BEHIND the judging line, alcoves opening toward the judge scene. Selection is
        // measured at Get_StationViewingPoint - one clearance in front of each mouth - so the player
        // judges from outside the alcove with the whole scene ahead of them, and only turns around to
        // read a panel. The judging line lands back at X=1800, the framing the presets were tuned at.
        const float StationSpacing = 1200.0f;
        const float StationRowX = 1800.0f + k_DitherGym_ViewingClearance;
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
        ck::Trace("* Stylize Screen Dither Gym - walk to a station to apply its preset");
    }

    private void Request_RebuildGym()
    {
        if (ck::IsValid(_JudgeScene))
        { _JudgeScene.DestroyActor(); }

        _JudgeScene = SpawnActor(ACk_UsfGym_StylizeDitherJudgeScene, FVector(0.0f, 0.0f, 0.0f), FRotator::ZeroRotator);
        if (_JudgeScene == nullptr)
        { ck::Error("[FAIL] Stylize Dither Gym: failed to spawn the judge scene"); }

        _StationTags.Empty();
        _StationLocations.Empty();
        _StationTags.Add(n"Gym.Stylize.DitherBalanced");
        _StationTags.Add(n"Gym.Stylize.DitherSubtleColor");
        _StationTags.Add(n"Gym.Stylize.DitherRetroPixel");
        _StationTags.Add(n"Gym.Stylize.DitherFourColor");
        _StationTags.Add(n"Gym.Stylize.DitherScreenPrint");
        _StationTags.Add(n"Gym.Stylize.DitherAnimatedGrain");
        _StationTags.Add(n"Gym.Stylize.DitherOff");

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
        return Xf.Location + Xf.Rotator().GetForwardVector() * k_DitherGym_ViewingClearance;
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
        if (UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem() == nullptr)
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
        auto Subsystem = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem();
        if (Subsystem == nullptr)
        {
            ck::Trace("Stylize Dither Gym: ScreenDither subsystem unavailable");
            return;
        }

        auto Preset = Get_PresetAt(InIndex);
        if (Preset == nullptr)
        { return; }

        _ActiveStation = InIndex;
        _DebugIndex = 0;
        Subsystem.Apply_Preset(Preset);
        PrintToScreen("SCREEN DITHER preset: " + Get_PresetNameAt(InIndex), 2.0, FLinearColor::Yellow);
    }

    private UCkUsf_ScreenDitherPreset Get_PresetAt(int32 InIndex)
    {
        if (InIndex == 0) { return CkUsf::DA_Dither_Balanced; }
        if (InIndex == 1) { return CkUsf::DA_Dither_SubtleColor; }
        if (InIndex == 2) { return CkUsf::DA_Dither_RetroPixel; }
        if (InIndex == 3) { return CkUsf::DA_Dither_FourColorHandheld; }
        if (InIndex == 4) { return CkUsf::DA_Dither_ScreenPrint; }
        if (InIndex == 5) { return CkUsf::DA_Dither_AnimatedGrain; }
        if (InIndex == 6) { return CkUsf::DA_Dither_Off; }
        return nullptr;
    }

    // const because PrintToScreen is a development-only call and AngelScript rejects non-const members
    // inside one - the compiler cannot prove the call is side-effect-free in a shipping build otherwise.
    private FString Get_PresetNameAt(int32 InIndex) const
    {
        if (InIndex == 0) { return "Balanced"; }
        if (InIndex == 1) { return "SubtleColor"; }
        if (InIndex == 2) { return "RetroPixel"; }
        if (InIndex == 3) { return "FourColorHandheld"; }
        if (InIndex == 4) { return "ScreenPrint"; }
        if (InIndex == 5) { return "AnimatedGrain"; }
        if (InIndex == 6) { return "Off"; }
        return "?";
    }

    private ECk_Usf_ScreenDither_DebugMode Get_DebugModeAt(int32 InIndex)
    {
        if (InIndex == 1) { return ECk_Usf_ScreenDither_DebugMode::Pattern; }
        if (InIndex == 2) { return ECk_Usf_ScreenDither_DebugMode::QuantizationError; }
        if (InIndex == 3) { return ECk_Usf_ScreenDither_DebugMode::QuantizedWithoutDither; }
        if (InIndex == 4) { return ECk_Usf_ScreenDither_DebugMode::DownsampledInput; }
        return ECk_Usf_ScreenDither_DebugMode::Final;
    }

    private FString Get_DebugNameAt(int32 InIndex) const
    {
        if (InIndex == 1) { return "Pattern"; }
        if (InIndex == 2) { return "QuantizationError"; }
        if (InIndex == 3) { return "QuantizedWithoutDither"; }
        if (InIndex == 4) { return "DownsampledInput"; }
        return "Final";
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The presets and the debug views are the whole gym, and until this panel existed both were reachable
    // only by typing a console command whose name you had to already know. Conditional rows go LAST so a
    // row that appears in only one state cannot shift the index of a keyed row above it.
    //--------------------------------------------------------------------------------------------------------------------------

    // Row 0 is the presets header; the presets follow it.
    private const int32 FirstPresetRow = 1;

    private int32 Get_FirstControlRow() const
    {
        return FirstPresetRow + _StationTags.Num();
    }

    FString Get_ControlPanelTitle() override
    {
        return "SCREEN DITHER";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("PRESETS  -  press a number, or walk to one"));

        for (int32 Index = 0; Index < _StationTags.Num(); Index++)
        { Rows.Add(CkGym_Control::Numbered(Index, Get_PresetNameAt(Index), Index == _ActiveStation)); }

        Rows.Add(CkGym_Control::Header("VIEW"));
        Rows.Add(CkGym_Control::Cycle(EKeys::J, "J", "Debug view", Get_DebugNameAt(_DebugIndex), _DebugIndex != 0));
        Rows.Add(CkGym_Control::Toggle(EKeys::M, "M", "Stack CelShade under", _StackedOther));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Rebuild judge scene"));

        // A debug view is not the effect. Someone who left one on and walked away would otherwise judge
        // the pattern buffer as though it were the finished frame.
        if (_DebugIndex != 0)
        { Rows.Add(CkGym_Control::Status("Showing a DEBUG buffer, not the final image", "", true)); }

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex >= FirstPresetRow && InRowIndex < Get_FirstControlRow())
        {
            Request_ApplyStation(InRowIndex - FirstPresetRow);
            return;
        }

        // Offset 0 is the VIEW header, which holds no key and never arrives here.
        auto Control = InRowIndex - Get_FirstControlRow();

        if (Control == 1) { Ck_GymStylizeDither_CycleDebug(); }
        else if (Control == 2) { Ck_GymStylizeDither_ToggleCelStack(); }
        else if (Control == 3) { Request_RebuildGym(); }
    }

    UFUNCTION(Exec, DisplayName="Stylize Dither Gym - Restart")
    void Ck_GymStylizeDither_RestartAll()
    {
        Request_RebuildGym();
    }

    // Debug views are a property of the CURRENT preset, so this edits the live settings rather than
    // re-applying a preset - walking to another station resets it, which is the intended behaviour.
    UFUNCTION(Exec, DisplayName="Stylize Dither Gym - Cycle Debug Mode")
    void Ck_GymStylizeDither_CycleDebug()
    {
        auto Subsystem = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem();
        if (Subsystem == nullptr)
        { return; }

        _DebugIndex = (_DebugIndex + 1) % 5;

        auto Settings = Subsystem.Get_Settings();
        Settings.Set_DebugMode(Get_DebugModeAt(_DebugIndex));
        Subsystem.Request_SetSettings(Settings);

        PrintToScreen("SCREEN DITHER debug: " + Get_DebugNameAt(_DebugIndex), 2.0, FLinearColor::Green);
    }

    // Cross-effect stacking A/B. CelShade is the classic partner: it bands the LIGHT before tonemapping
    // while dither reduces the PALETTE after it, so the two compose rather than compete. The toggle owns
    // its own flag rather than reading Get_IsEnabled(), because a subsystem nothing has touched yet
    // reports Enabled while rendering nothing - reading it would make the first press a silent no-op.
    UFUNCTION(Exec, DisplayName="Stylize Dither Gym - Toggle CelShade Stack")
    void Ck_GymStylizeDither_ToggleCelStack()
    {
        auto Cel = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem();
        if (Cel == nullptr)
        { return; }

        _StackedOther = !_StackedOther;

        if (_StackedOther)
        { Cel.Apply_Preset(CkUsf::DA_Cel_Balanced); }
        else
        { Cel.Request_SetEnabled(ECk_EnableDisable::Disable); }

        PrintToScreen("SCREEN DITHER + CelShade stack: " + (_StackedOther ? "ON" : "OFF"), 2.0, FLinearColor::Green);
    }

}
