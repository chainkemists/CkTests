// Language=angelscript

// Verifies the settings screen generates its rows FROM THE REGISTRY: a demo collection (one
// setting per row type) produces one visible row per setting, bound by key. Widget creation works
// headless; rendering is not asserted.
//
// Which CLASS each row resolves to is deliberately NOT asserted here - a host that configures
// project-settings row overrides (BusterBlock does) legitimately gets its own WBP classes. The
// resolution contract itself is covered host-independently by Ck.CkGameSettings.UI.RowClassResolution.
class UCk_AutoTest_GameSettings_ScreenGeneratesRowsFromRegistry : UCk_AutoTest_Base
{
    private UCk_GameSettingsUI_ScreenWidget _Screen;

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

        _Screen = Cast<UCk_GameSettingsUI_ScreenWidget>(
            WidgetBlueprint::CreateWidget(UCk_GameSettingsUI_ScreenWidget, Gameplay::GetPlayerController(0)));
        if (_Screen == nullptr)
        {
            FinishFailure("settings screen widget failed to create headless");
            return;
        }

        _Screen.Request_RebuildRows();

        Assert_True(_Screen.Get_CategoryTabCount() >= 1, "at least the General category tab exists");
        Assert_True(_Screen.Request_SetActiveCategory(n"General"), "the General tab (uncategorized settings) is selectable");

        // Row classes are soft references: the screen injects nothing until they finish loading.
        WaitUntil(n"Check_DemoRowsGenerated", n"OnDemoRowsGenerated");
    }

    UFUNCTION()
    private void Check_DemoRowsGenerated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Screen != nullptr && _Screen.Get_GeneratedRowCount() >= 4);
    }

    UFUNCTION()
    private void OnDemoRowsGenerated(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(_Screen.Get_HasRowForKey(n"astest.screen.toggle"), "toggle row generated");
        Assert_True(_Screen.Get_HasRowForKey(n"astest.screen.slider"), "slider row generated");
        Assert_True(_Screen.Get_HasRowForKey(n"astest.screen.select"), "select row generated");
        Assert_True(_Screen.Get_HasRowForKey(n"astest.screen.stepper"), "stepper row generated");

        FinishSuccess();
    }
}
