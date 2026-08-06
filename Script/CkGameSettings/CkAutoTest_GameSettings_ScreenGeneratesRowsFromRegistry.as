// Language=angelscript

// Verifies the settings screen generates its rows FROM THE REGISTRY: a demo collection (one
// setting per row type) produces one visible row per setting, each resolved to the expected
// built-in row class. Widget creation works headless; rendering is not asserted.
class UCk_AutoTest_GameSettings_ScreenGeneratesRowsFromRegistry : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.screen.toggle", ECk_GameSettings_ValueType::Bool, "true")),
            "toggle setting registers");

        auto SliderDefinition = FCk_GameSettings_SettingDefinition(n"astest.screen.slider", ECk_GameSettings_ValueType::Float, "0.5");
        SliderDefinition.Set_MinValue("0");
        SliderDefinition.Set_MaxValue("1");
        Assert_True(utils_game_settings::Request_RegisterSetting(SliderDefinition), "slider setting registers");

        auto SelectDefinition = FCk_GameSettings_SettingDefinition(n"astest.screen.select", ECk_GameSettings_ValueType::String, "medium");
        TArray<FCk_GameSettings_SettingOption> Options;
        Options.Add(FCk_GameSettings_SettingOption(FText::FromString("Low"), "low"));
        Options.Add(FCk_GameSettings_SettingOption(FText::FromString("Medium"), "medium"));
        Options.Add(FCk_GameSettings_SettingOption(FText::FromString("High"), "high"));
        SelectDefinition.Set_Options(Options);
        Assert_True(utils_game_settings::Request_RegisterSetting(SelectDefinition), "select setting registers");

        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.screen.stepper", ECk_GameSettings_ValueType::Int32, "3")),
            "stepper setting registers");

        auto Screen = Cast<UCk_GameSettingsUI_ScreenWidget>(
            WidgetBlueprint::CreateWidget(UCk_GameSettingsUI_ScreenWidget, Gameplay::GetPlayerController(0)));
        if (Screen == nullptr)
        {
            FinishFailure("settings screen widget failed to create headless");
            return;
        }

        Screen.Request_RebuildRows();

        Assert_True(Screen.Get_CategoryTabCount() >= 1, "at least the General category tab exists");
        Assert_True(Screen.Request_SetActiveCategory(n"General"), "the General tab (uncategorized settings) is selectable");

        Assert_True(Screen.Get_GeneratedRowCount() >= 4, "all four demo settings produced rows");

        Assert_True(Screen.Get_HasRowForKey(n"astest.screen.toggle"), "toggle row generated");
        Assert_True(Screen.Get_HasRowForKey(n"astest.screen.slider"), "slider row generated");
        Assert_True(Screen.Get_HasRowForKey(n"astest.screen.select"), "select row generated");
        Assert_True(Screen.Get_HasRowForKey(n"astest.screen.stepper"), "stepper row generated");

        Assert_True(Screen.Get_RowClassForKey(n"astest.screen.toggle") == UCk_GameSettingsUI_RowWidget_Toggle,
            "Bool resolved to the Toggle row");
        Assert_True(Screen.Get_RowClassForKey(n"astest.screen.slider") == UCk_GameSettingsUI_RowWidget_Slider,
            "ranged Float resolved to the Slider row");
        Assert_True(Screen.Get_RowClassForKey(n"astest.screen.select") == UCk_GameSettingsUI_RowWidget_Select,
            "options-present resolved to the Select row");
        Assert_True(Screen.Get_RowClassForKey(n"astest.screen.stepper") == UCk_GameSettingsUI_RowWidget_Select,
            "rangeless Int32 resolved to the Select (stepper) row");

        FinishSuccess();
    }
}
