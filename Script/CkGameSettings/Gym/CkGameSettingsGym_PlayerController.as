// Language=angelscript

// The human visual surface for the CkGameSettings widget accelerant: registers a demo collection
// (one setting per built-in row type, split across two category tabs) and pushes the CodeBuilt
// settings screen. The keybinding page opens via the exec below.
class ACk_GameSettingsGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private UCk_GameSettingsUI_ScreenWidget _SettingsScreen;
    private UCk_GameSettingsUI_KeyBindingPageWidget _KeyBindingPage;

    void Request_StartGym() override
    {
        DoRegisterDemoCollection();
        DoOpenSettingsScreen();

        ck::Trace("GameSettingsGym: screen pushed (native base = plumbing only, renders unstyled; the game's WBP supplies the look) - Ck_GymGameSettings_OpenKeyBindingPage toggles the keybinding page");
    }

    private void DoRegisterDemoCollection()
    {
        if (utils_game_settings::Get_IsSettingRegistered(n"gymdemo.toggle"))
        { return; }

        auto GameplayCategory = utils_gameplay_tag::ResolveGameplayTag(n"GymGameSettings.Gameplay");
        auto DisplayCategory = utils_gameplay_tag::ResolveGameplayTag(n"GymGameSettings.Display");

        FGameplayTagContainer GameplayTags;
        GameplayTags.AddTag(GameplayCategory);

        FGameplayTagContainer DisplayTags;
        DisplayTags.AddTag(DisplayCategory);

        auto ToggleDefinition = FCk_GameSettings_SettingDefinition(n"gymdemo.toggle", ECk_GameSettings_ValueType::Bool, "true");
        ToggleDefinition.Set_DisplayName(FText::FromString("Demo Toggle"));
        ToggleDefinition.Set_Description(FText::FromString("A Bool setting - checkbox row"));
        ToggleDefinition.Set_CategoryTags(GameplayTags);

        auto VolumeDefinition = FCk_GameSettings_SettingDefinition(n"gymdemo.volume", ECk_GameSettings_ValueType::Float, "0.75");
        VolumeDefinition.Set_DisplayName(FText::FromString("Demo Volume"));
        VolumeDefinition.Set_Description(FText::FromString("A ranged Float setting - slider row with live readout"));
        VolumeDefinition.Set_MinValue("0");
        VolumeDefinition.Set_MaxValue("1");
        VolumeDefinition.Set_CategoryTags(GameplayTags);

        auto CountDefinition = FCk_GameSettings_SettingDefinition(n"gymdemo.count", ECk_GameSettings_ValueType::Int32, "3");
        CountDefinition.Set_DisplayName(FText::FromString("Demo Count"));
        CountDefinition.Set_Description(FText::FromString("A ranged Int32 setting - stepped slider row"));
        CountDefinition.Set_MinValue("0");
        CountDefinition.Set_MaxValue("10");
        CountDefinition.Set_CategoryTags(GameplayTags);

        auto QualityDefinition = FCk_GameSettings_SettingDefinition(n"gymdemo.quality", ECk_GameSettings_ValueType::String, "medium");
        QualityDefinition.Set_DisplayName(FText::FromString("Demo Quality"));
        QualityDefinition.Set_Description(FText::FromString("An options setting - prev/next select row"));
        TArray<FCk_GameSettings_SettingOption> QualityOptions;
        QualityOptions.Add(FCk_GameSettings_SettingOption(FText::FromString("Low"), "low"));
        QualityOptions.Add(FCk_GameSettings_SettingOption(FText::FromString("Medium"), "medium"));
        QualityOptions.Add(FCk_GameSettings_SettingOption(FText::FromString("High"), "high"));
        QualityDefinition.Set_Options(QualityOptions);
        QualityDefinition.Set_CategoryTags(DisplayTags);

        auto LivesDefinition = FCk_GameSettings_SettingDefinition(n"gymdemo.lives", ECk_GameSettings_ValueType::Int32, "3");
        LivesDefinition.Set_DisplayName(FText::FromString("Demo Lives"));
        LivesDefinition.Set_Description(FText::FromString("A rangeless Int32 setting - stepper select row"));
        LivesDefinition.Set_CategoryTags(DisplayTags);

        TArray<FCk_GameSettings_SettingDefinition> Definitions;
        Definitions.Add(ToggleDefinition);
        Definitions.Add(VolumeDefinition);
        Definitions.Add(CountDefinition);
        Definitions.Add(QualityDefinition);
        Definitions.Add(LivesDefinition);

        if (!utils_game_settings::Request_RegisterSettings(Definitions))
        {
            ck::Trace("GameSettingsGym: demo collection failed to register");
        }
    }

    private void DoOpenSettingsScreen()
    {
        _SettingsScreen = Cast<UCk_GameSettingsUI_ScreenWidget>(
            WidgetBlueprint::CreateWidget(UCk_GameSettingsUI_ScreenWidget, this));

        if (_SettingsScreen == nullptr)
        {
            ck::Trace("GameSettingsGym: settings screen failed to create");
            return;
        }

        _SettingsScreen.AddToViewport();
        _SettingsScreen.ActivateWidget();
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Closing the settings screen leaves an empty gym with no way back into it that is visible from
    // inside the gym. These two rows are that way back.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GAME SETTINGS";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::S, "S", "Reopen the settings screen"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Open the key-binding page"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Ck_GymGameSettings_ReopenScreen(); }
        else if (InRowIndex == 1) { Ck_GymGameSettings_OpenKeyBindingPage(); }
    }

    UFUNCTION(Exec, DisplayName = "GameSettings Gym - Reopen Settings Screen")
    void Ck_GymGameSettings_ReopenScreen()
    {
        if (_SettingsScreen != nullptr && _SettingsScreen.IsInViewport())
        { _SettingsScreen.RemoveFromParent(); }

        DoOpenSettingsScreen();
    }

    UFUNCTION(Exec, DisplayName = "GameSettings Gym - Open KeyBinding Page")
    void Ck_GymGameSettings_OpenKeyBindingPage()
    {
        if (_KeyBindingPage != nullptr && _KeyBindingPage.IsInViewport())
        {
            _KeyBindingPage.RemoveFromParent();
            _KeyBindingPage = nullptr;
            return;
        }

        _KeyBindingPage = Cast<UCk_GameSettingsUI_KeyBindingPageWidget>(
            WidgetBlueprint::CreateWidget(UCk_GameSettingsUI_KeyBindingPageWidget, this));

        if (_KeyBindingPage == nullptr)
        {
            ck::Trace("GameSettingsGym: keybinding page failed to create");
            return;
        }

        _KeyBindingPage.AddToViewport(10);
    }
}
