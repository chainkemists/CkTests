// Language=angelscript

// Verifies the orphan contract: a stored value whose definition is not registered yet is retained
// SILENTLY (no warning, no expiry) and becomes the setting's initial value when the definition
// registers — the stored value wins over the definition's default. Any ensure fails this test.
class UCk_AutoTest_GameSettings_OrphanValueAppliedOnRegistration : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Provider = utils_game_settings::Get_StorageProvider();
        Provider.Request_StoreValue(ECk_GameSettings_Scope::Machine, 0, n"astest.orphan.key", "orphan-value");

        utils_game_settings::Request_ReloadFromStorage();
        Assert_False(utils_game_settings::Get_IsSettingRegistered(n"astest.orphan.key"),
            "key stays unregistered after reload");

        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.orphan.key", ECk_GameSettings_ValueType::String, "default-value")),
            "definition registers");

        Assert_Equals_String(utils_game_settings::Get_SettingValue_String(n"astest.orphan.key", ""),
            "orphan-value",
            "the retained stored value wins over the definition's default");

        FinishSuccess();
    }
}
