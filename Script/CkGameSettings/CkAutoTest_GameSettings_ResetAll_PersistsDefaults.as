// Language=angelscript

// Verifies that Reset All routes through persistence: the restored defaults land in the storage
// provider, not just in memory. Counts use >= because the registry is shared across the PIE
// world's tests and other registered settings may legitimately reset too.
class UCk_AutoTest_GameSettings_ResetAll_PersistsDefaults : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.reset.mode", ECk_GameSettings_ValueType::String, "dflt")),
            "String setting registers");
        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.reset.level", ECk_GameSettings_ValueType::Int32, "5")),
            "Int32 setting registers");

        Assert_True(utils_game_settings::Request_SetSettingValue_String(
            FCk_Request_GameSettings_SetValue_String(n"astest.reset.mode", "changed")), "set holds");
        Assert_True(utils_game_settings::Request_SetSettingValue_Int32(
            FCk_Request_GameSettings_SetValue_Int32(n"astest.reset.level", 9)), "set holds");

        Assert_True(utils_game_settings::Request_ResetAllToDefaults() >= 2,
            "reset-all restores at least this test's two changed settings");

        Assert_Equals_String(utils_game_settings::Get_SettingValue_String(n"astest.reset.mode", ""), "dflt",
            "default restored in memory");
        Assert_Equals_Int(utils_game_settings::Get_SettingValue_Int32(n"astest.reset.level", 0), 5,
            "default restored in memory");

        auto Provider = utils_game_settings::Get_StorageProvider();
        auto StoredValues = Provider.Get_StoredValues(ECk_GameSettings_Scope::Machine, 0);

        auto StoredMode = FString();
        auto StoredLevel = FString();
        for (int32 Index = 0; Index < StoredValues.Num(); ++Index)
        {
            if (StoredValues[Index].Get_Key() == n"astest.reset.mode")
            { StoredMode = StoredValues[Index].Get_Value(); }
            if (StoredValues[Index].Get_Key() == n"astest.reset.level")
            { StoredLevel = StoredValues[Index].Get_Value(); }
        }

        Assert_Equals_String(StoredMode, "dflt", "default PERSISTED to the store");
        Assert_Equals_String(StoredLevel, "5", "default PERSISTED to the store");

        FinishSuccess();
    }
}
