// Language=angelscript

//============================================================================
// PIXEL ART GYM — HUD: the station panel
//============================================================================
//
// An always-on panel listing every station with the key that selects it. Two jobs, and the second one is
// the reason it is drawn rather than just useful:
//
//   1. Selection without walking. 1-9 and 0 pick a station directly; the panel says which is live.
//   2. It IS the native-resolution UI subject. The renderer upscales the SCENE and composites UI after,
//      so crisp text sitting directly on top of a chunky frame is the whole criterion — and a panel that
//      is always there judges it continuously instead of only at one station.
//
// Both the number row and the numpad are accepted. A laptop has no numpad and a desk keyboard's number
// row is under the fingers already; binding one and not the other would make the feature depend on
// hardware.
//
// The cycler menu (Tab) stays untouched underneath: Super runs first, and while that menu is open this
// panel takes no keys at all, or typing a search term would fire stations behind it.
//============================================================================

class ACk_PixelArtGym_HUD : ACkGym_MenuHUD
{
    // Row geometry. Native pixels, deliberately: this panel is the native-res reference, so it must not
    // scale with anything the renderer does to the scene.
    private const float PanelX = 24.0f;
    private const float PanelTopY = 90.0f;
    private const float RowHeight = 22.0f;
    private const float PanelWidth = 330.0f;
    private const float PanelPadding = 10.0f;

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Mirror the base's startup suppression: without it the panel flashes over the launcher level
        // during an auto-travel to the startup gym.
        auto CyclerSubsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::IsValid(CyclerSubsystem) && CyclerSubsystem.SuppressHUDDuringStartup)
        { return; }

        Super::DrawHUD(SizeX, SizeY);

        // The cycler menu owns the keyboard while it is open, and it draws over this area anyway.
        if (bMenuVisible)
        { return; }

        auto PC = Cast<ACk_PixelArtGym_PlayerController>(GetOwningPlayerController());

        if (!ck::IsValid(PC) || PC.Get_StationCount() == 0)
        { return; }

        Tick_StationKeys(PC);
        Draw_StationPanel(PC);
    }

    // 1-9 select stations 0-8 and 0 selects the tenth, which is the ordinary way a ten-item list is keyed.
    private void Tick_StationKeys(ACk_PixelArtGym_PlayerController InPC)
    {
        const int32 StationCount = InPC.Get_StationCount();

        for (int32 Index = 0; Index < StationCount; Index++)
        {
            if (!Get_StationKeyPressed(InPC, Index))
            { continue; }

            InPC.Request_SelectStation_Manual(Index);
            return;
        }
    }

    private bool Get_StationKeyPressed(ACk_PixelArtGym_PlayerController InPC, int32 InIndex)
    {
        // Index 9 is the tenth station, which is keyed 0 rather than a nonexistent "10".
        if (InIndex == 9)
        { return InPC.WasInputKeyJustPressed(EKeys::Zero) || InPC.WasInputKeyJustPressed(EKeys::NumPadZero); }

        if (InIndex == 0) { return InPC.WasInputKeyJustPressed(EKeys::One)   || InPC.WasInputKeyJustPressed(EKeys::NumPadOne); }
        if (InIndex == 1) { return InPC.WasInputKeyJustPressed(EKeys::Two)   || InPC.WasInputKeyJustPressed(EKeys::NumPadTwo); }
        if (InIndex == 2) { return InPC.WasInputKeyJustPressed(EKeys::Three) || InPC.WasInputKeyJustPressed(EKeys::NumPadThree); }
        if (InIndex == 3) { return InPC.WasInputKeyJustPressed(EKeys::Four)  || InPC.WasInputKeyJustPressed(EKeys::NumPadFour); }
        if (InIndex == 4) { return InPC.WasInputKeyJustPressed(EKeys::Five)  || InPC.WasInputKeyJustPressed(EKeys::NumPadFive); }
        if (InIndex == 5) { return InPC.WasInputKeyJustPressed(EKeys::Six)   || InPC.WasInputKeyJustPressed(EKeys::NumPadSix); }
        if (InIndex == 6) { return InPC.WasInputKeyJustPressed(EKeys::Seven) || InPC.WasInputKeyJustPressed(EKeys::NumPadSeven); }
        if (InIndex == 7) { return InPC.WasInputKeyJustPressed(EKeys::Eight) || InPC.WasInputKeyJustPressed(EKeys::NumPadEight); }
        if (InIndex == 8) { return InPC.WasInputKeyJustPressed(EKeys::Nine)  || InPC.WasInputKeyJustPressed(EKeys::NumPadNine); }

        return false;
    }

    private FString Get_StationKeyLabel(int32 InIndex)
    {
        if (InIndex == 9)
        { return "0"; }

        auto KeyNumber = InIndex + 1;
        return f"{KeyNumber}";
    }

    private void Draw_StationPanel(ACk_PixelArtGym_PlayerController InPC)
    {
        const int32 StationCount = InPC.Get_StationCount();
        const int32 Active = InPC.Get_ActiveStation();

        // Title row, station rows, then two footer rows.
        const float PanelHeight = (StationCount + 3) * RowHeight + PanelPadding * 2.0f;

        DrawRect(FLinearColor(0.02f, 0.02f, 0.05f, 0.82f),
            PanelX, PanelTopY, PanelWidth, PanelHeight);

        float RowY = PanelTopY + PanelPadding;

        DrawText("PIXEL ART  -  press a number", FLinearColor(0.62f, 0.78f, 1.0f, 1.0f),
            PanelX + PanelPadding, RowY, nullptr, 1.0f, false);
        RowY += RowHeight;

        for (int32 Index = 0; Index < StationCount; Index++)
        {
            const bool IsActive = Index == Active;

            if (IsActive)
            {
                DrawRect(FLinearColor(0.15f, 0.25f, 0.55f, 0.9f),
                    PanelX + 4.0f, RowY - 3.0f, PanelWidth - 8.0f, RowHeight);
            }

            auto RowColor = IsActive
                ? FLinearColor(1.0f, 1.0f, 1.0f, 1.0f)
                : FLinearColor(0.72f, 0.74f, 0.80f, 1.0f);

            DrawText(f"[{Get_StationKeyLabel(Index)}] {InPC.Get_StationLabel(Index)}",
                RowColor, PanelX + PanelPadding, RowY, nullptr, 1.0f, false);

            RowY += RowHeight;
        }

        // Which selection mode is live. Without this the panel looks broken when a key choice is silently
        // overridden by walking, which is exactly when someone needs to be told what is happening.
        auto ModeText = InPC.Get_SelectionIsManual()
            ? "Key-selected  (walk away to resume proximity)"
            : "Proximity  (walk to a station, or press a key)";

        DrawText(ModeText, FLinearColor(0.55f, 0.60f, 0.68f, 1.0f),
            PanelX + PanelPadding, RowY, nullptr, 0.85f, false);
        RowY += RowHeight;

        auto LookText = InPC.Get_LookOverride() ? "look FORCED ON" : "look per-station";

        DrawText(f"Ck_GymPixelArt_TogglePan for the creep test  |  {LookText}",
            FLinearColor(0.55f, 0.60f, 0.68f, 1.0f),
            PanelX + PanelPadding, RowY, nullptr, 0.85f, false);
    }
}
