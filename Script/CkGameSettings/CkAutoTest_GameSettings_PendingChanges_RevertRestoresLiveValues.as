// Language=angelscript

// Verifies pending-changes semantics: sets during a session apply LIVE (preview), Revert restores
// every recorded prior value live, and the session bookkeeping (HasPendingChanges /
// HasUnappliedChange) tracks the staged keys.
class UCk_AutoTest_GameSettings_PendingChanges_RevertRestoresLiveValues : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.pending.flag", ECk_GameSettings_ValueType::Bool, "false")),
            "Bool setting registers");
        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.pending.count", ECk_GameSettings_ValueType::Int32, "10")),
            "Int32 setting registers");

        Assert_True(utils_game_settings::Request_BeginPendingChanges(), "session begins");
        Assert_False(utils_game_settings::Get_HasPendingChanges(), "clean session has no pending changes yet");

        Assert_True(utils_game_settings::Request_SetSettingValue_Bool(
            FCk_Request_GameSettings_SetValue_Bool(n"astest.pending.flag", true)), "preview set holds");
        Assert_True(utils_game_settings::Request_SetSettingValue_Int32(
            FCk_Request_GameSettings_SetValue_Int32(n"astest.pending.count", 25)), "preview set holds");

        Assert_True(utils_game_settings::Get_SettingValue_Bool(n"astest.pending.flag", false),
            "preview value is LIVE");
        Assert_Equals_Int(utils_game_settings::Get_SettingValue_Int32(n"astest.pending.count", 0), 25,
            "preview value is LIVE");

        Assert_True(utils_game_settings::Get_HasPendingChanges(), "session tracks pending changes");
        Assert_True(utils_game_settings::Get_HasUnappliedChange(n"astest.pending.flag"), "staged key is tracked");
        Assert_False(utils_game_settings::Get_HasUnappliedChange(n"astest.pending.count.other"), "unstaged key is not tracked");

        Assert_Equals_Int(utils_game_settings::Request_RevertPendingChanges(), 2, "both staged settings revert");

        Assert_False(utils_game_settings::Get_SettingValue_Bool(n"astest.pending.flag", true),
            "reverted value is LIVE");
        Assert_Equals_Int(utils_game_settings::Get_SettingValue_Int32(n"astest.pending.count", 0), 10,
            "reverted value is LIVE");
        Assert_False(utils_game_settings::Get_HasPendingChanges(), "session is closed after revert");

        FinishSuccess();
    }
}
