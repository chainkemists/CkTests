class ACk_NavigationGym_Presentation_HUD : ACkGym_ControlPanelHUD
{
    ECkGym_ControlPanel_Mode Get_EffectivePanelMode(ACk_Gym_Base_PlayerController InPC) override
    {
        auto Presentation = Cast<ACk_NavigationGym_Presentation_PlayerController>(InPC);
        if (ck::IsValid(Presentation))
        {
            if (Presentation.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Hero)
            { return ECkGym_ControlPanel_Mode::Hidden; }
            if (Presentation.Get_PresentationMode() == ECkNavigationGym_PresentationMode::Diagnostic)
            { return ECkGym_ControlPanel_Mode::Full; }
        }
        return Super::Get_EffectivePanelMode(InPC);
    }

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        Super::DrawHUD(SizeX, SizeY);
        if (SizeX <= 0 || SizeY <= 0)
        { return; }
        auto PC = Cast<ACk_NavigationGym_Presentation_PlayerController>(GetOwningPlayerController());
        if (ck::Is_NOT_Valid(PC) || PC.Get_PresentationMode() != ECkNavigationGym_PresentationMode::Hero ||
            UCk_Utils_GymRegistry_UE::Get_SuppressHUDDuringStartup())
        { return; }

        const float Scale = Math::Min(float(SizeX) / 1920.0, float(SizeY) / 1080.0);
        const float Left = 48.0 * Scale;
        const float Top = float(SizeY) - 178.0 * Scale;
        const float Width = float(SizeX) - 96.0 * Scale;
        const auto Verdict = PC.Get_PresentationVerdict();
        FLinearColor Accent = PC.Get_PresentationProvider() == "GroundNav"
            ? FLinearColor(0.25, 0.85, 0.62, 1.0) : FLinearColor(0.30, 0.65, 1.0, 1.0);

        DrawRect(FLinearColor(0.015, 0.025, 0.045, 0.92), Left, Top, Width, 136.0 * Scale);
        DrawRect(Accent, Left, Top, 4.0 * Scale, 136.0 * Scale);
        DrawText(f"{PC.Get_ControlPanelTitle()}  /  {PC.Get_PresentationProvider()}", Accent,
            Left + 24.0 * Scale, Top + 15.0 * Scale, nullptr, 1.25 * Scale, false);
        DrawText(PC.Get_PresentationCaption(), FLinearColor::White,
            Left + 24.0 * Scale, Top + 43.0 * Scale, nullptr, 1.65 * Scale, false);
        FString VerdictText = Verdict.Value;
        if (VerdictText.Len() > 135)
        { VerdictText = f"{VerdictText.Left(132)}..."; }
        FLinearColor VerdictColor = Verdict.Warn ? FLinearColor(1.0, 0.45, 0.25, 1.0)
            : FLinearColor(0.78, 0.83, 0.9, 1.0);
        DrawText(f"{Verdict.Label}: {VerdictText}", VerdictColor,
            Left + 24.0 * Scale, Top + 80.0 * Scale, nullptr, 1.0 * Scale, false);
        DrawText("Home  Hero    End  Diagnostics    Backspace  Baseline    Tab  Gyms", FLinearColor(0.55, 0.63, 0.72, 1.0),
            Left + 24.0 * Scale, Top + 108.0 * Scale, nullptr, 0.9 * Scale, false);
    }
}
