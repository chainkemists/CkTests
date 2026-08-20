// Language=angelscript

//============================================================================
// CK PIXEL ART — AUTOMATION TEST: SUBSYSTEM CONTRACT
//============================================================================
//
// The subsystem is the only thing game code talks to, so its contract is the whole public promise of the
// feature. Three parts of it are worth more than the rest:
//
//   - it is OFF until something says otherwise, so merely having the module linked changes nothing;
//   - settings round-trip exactly, so a preset means what it says;
//   - enabling is REFUSED, loudly and with a report, when an engine setting makes a pixel-art image impossible
//     — and refusal leaves no half-state. That last one is the interesting case: silently enabling into a
//     configuration that cannot render is how this feature would waste an afternoon of someone's debugging.
//============================================================================

class UCk_AutoTest_PixelArt_SubsystemContract : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Subsystem = UCkPixelArt_Subsystem::Get_PixelArtSubsystem();

        if (Subsystem == nullptr)
        { FinishFailure("No UCkPixelArt_Subsystem in the test world"); return; }

        if (Subsystem.Get_IsEnabled() != ECk_EnableDisable::Disable)
        { FinishFailure("The renderer was enabled before anything asked for it"); return; }

        if (!DoCheck_SettingsRoundtrip(Subsystem)) { return; }
        if (!DoCheck_EnableIsGated(Subsystem)) { return; }
        if (!DoCheck_ResetToDefaults(Subsystem)) { return; }

        FinishSuccess();
    }

    private bool DoCheck_SettingsRoundtrip(UCkPixelArt_Subsystem Subsystem)
    {
        // Deliberately every field away from its default: a roundtrip that only moves one value would pass even
        // if the setter copied a default-constructed struct.
        auto Params = FCk_PixelArt_Params();
        Params.Set_ResolutionMode(ECk_PixelArt_ResolutionMode::TexelsPerPixel);
        Params.Set_InternalHeight(540);
        Params.Set_TexelsPerPixel(5);
        Params.Set_MarginTexels(3);
        Params.Set_SnapEnabled(ECk_EnableDisable::Disable);
        Params.Set_UpscaleFilter(ECk_PixelArt_UpscaleFilter::Nearest);
        Params.Set_ApplyLook(ECk_EnableDisable::Disable);

        auto Look = Params.Get_Look();
        Look.Set_Bands(7);
        Look.Set_EdgeMode(ECk_PixelArt_EdgeMode::FlatColors);
        Look.Set_PaletteMode(ECk_PixelArt_PaletteMode::CustomPalette);
        Look.Set_PaletteCount(6);
        Params.Set_Look(Look);

        Subsystem.Request_SetSettings(Params);

        auto ReadBack = Subsystem.Get_Settings();

        if (ReadBack.Get_ResolutionMode() != ECk_PixelArt_ResolutionMode::TexelsPerPixel ||
            ReadBack.Get_InternalHeight() != 540 ||
            ReadBack.Get_TexelsPerPixel() != 5 ||
            ReadBack.Get_MarginTexels() != 3 ||
            ReadBack.Get_SnapEnabled() != ECk_EnableDisable::Disable ||
            ReadBack.Get_UpscaleFilter() != ECk_PixelArt_UpscaleFilter::Nearest ||
            ReadBack.Get_ApplyLook() != ECk_EnableDisable::Disable)
        {
            FinishFailure("Renderer half of the settings did not round-trip");
            return false;
        }

        auto ReadBackLook = ReadBack.Get_Look();

        if (ReadBackLook.Get_Bands() != 7 ||
            ReadBackLook.Get_EdgeMode() != ECk_PixelArt_EdgeMode::FlatColors ||
            ReadBackLook.Get_PaletteMode() != ECk_PixelArt_PaletteMode::CustomPalette ||
            ReadBackLook.Get_PaletteCount() != 6)
        {
            FinishFailure("Look half of the settings did not round-trip");
            return false;
        }

        Assert_True(true, "Settings round-trip through the subsystem unchanged");
        return true;
    }

    private bool DoCheck_EnableIsGated(UCkPixelArt_Subsystem Subsystem)
    {
        // A temporal anti-aliasing method takes the primary spatial upscale slot the renderer occupies, so this
        // is the precondition with real teeth. Forcing it is how the refusal path gets exercised on purpose
        // rather than only when a machine happens to be configured badly.
        System::ExecuteConsoleCommand("r.AntiAliasingMethod 4");

        auto BlockedReport = Subsystem.Get_PreconditionReport();

        if (BlockedReport.Get_Failures().Num() == 0)
        {
            System::ExecuteConsoleCommand("r.AntiAliasingMethod 0");
            FinishFailure("Temporal anti-aliasing did not register as a precondition failure");
            return false;
        }

        Subsystem.Request_SetEnabled(ECk_EnableDisable::Enable);

        if (Subsystem.Get_IsEnabled() != ECk_EnableDisable::Disable)
        {
            System::ExecuteConsoleCommand("r.AntiAliasingMethod 0");
            FinishFailure("The renderer enabled itself despite an unsatisfied precondition");
            return false;
        }

        if (Subsystem.Get_PreconditionReport().Get_Failures().Num() == 0)
        {
            System::ExecuteConsoleCommand("r.AntiAliasingMethod 0");
            FinishFailure("A refused enable left an empty precondition report");
            return false;
        }

        Assert_True(true, "Enabling is refused, and reported, when a precondition is unsatisfied");

        // The sanctioned escape: the subsystem moves the settings only when explicitly told to.
        Subsystem.Request_Apply_RecommendedCVars();

        auto ClearedReport = Subsystem.Get_PreconditionReport();

        if (ClearedReport.Get_Failures().Num() != 0)
        {
            // Name what is still in the way. A bare "preconditions unsatisfied" would send the next reader
            // guessing between three settings, which is exactly what the report type exists to prevent.
            FString Remaining;
            for (auto Failure : ClearedReport.Get_Failures())
            { Remaining += f"{Failure.Get_Name()}=[{Failure.Get_CurrentValue()}] needs [{Failure.Get_RequiredValue()}]; "; }

            FinishFailure(f"Applying the recommended CVars left preconditions unsatisfied: {Remaining}");
            return false;
        }

        Subsystem.Request_SetEnabled(ECk_EnableDisable::Enable);

        if (Subsystem.Get_IsEnabled() != ECk_EnableDisable::Enable)
        {
            FinishFailure("The renderer did not enable once every precondition was satisfied");
            return false;
        }

        Assert_True(true, "Enabling succeeds after the recommended CVars are applied");

        // Disabling restores whatever the escape moved, which is what keeps the test from leaking a forced
        // anti-aliasing method into every test that runs after it.
        Subsystem.Request_SetEnabled(ECk_EnableDisable::Disable);

        if (Subsystem.Get_IsEnabled() != ECk_EnableDisable::Disable)
        {
            FinishFailure("Disabling did not take");
            return false;
        }

        // KNOWN LIMITATION: this restores a literal 0, not the project's prior value, because UCk_Utils_CVar_UE
        // exposes no value getter to AngelScript. A deterministic last word beats leaving TSR forced on for every
        // test that follows, but a project whose default is not 0 does inherit this one.
        System::ExecuteConsoleCommand("r.AntiAliasingMethod 0");

        return true;
    }

    private bool DoCheck_ResetToDefaults(UCkPixelArt_Subsystem Subsystem)
    {
        Subsystem.Request_ResetToDefaults();

        auto Defaults = FCk_PixelArt_Params();
        auto ReadBack = Subsystem.Get_Settings();

        if (ReadBack.Get_ResolutionMode() != Defaults.Get_ResolutionMode() ||
            ReadBack.Get_InternalHeight() != Defaults.Get_InternalHeight() ||
            ReadBack.Get_TexelsPerPixel() != Defaults.Get_TexelsPerPixel() ||
            ReadBack.Get_MarginTexels() != Defaults.Get_MarginTexels() ||
            ReadBack.Get_SnapEnabled() != Defaults.Get_SnapEnabled() ||
            ReadBack.Get_UpscaleFilter() != Defaults.Get_UpscaleFilter())
        {
            FinishFailure("Reset did not return the settings to their defaults");
            return false;
        }

        Assert_True(true, "Reset returns the settings to their defaults");
        return true;
    }
}

class ACk_AutoTest_PixelArt_SubsystemContract_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_PixelArt_SubsystemContract;
    default _TimeoutSeconds = 10.0f;

    // The test forces a temporal anti-aliasing method specifically so the refusal fires. The ensure IS the
    // contract being tested, so its output is expected rather than a failure.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("Cannot enable the pixel-art renderer");
        return Out;
    }
}
