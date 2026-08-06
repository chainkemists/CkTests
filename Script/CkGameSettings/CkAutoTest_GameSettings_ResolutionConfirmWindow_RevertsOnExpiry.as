// Language=angelscript

// Verifies the resolution confirm-window primitive: the new resolution is live during the window,
// and expiry without Request_ConfirmResolution reverts to the prior resolution (which also leaves
// the dev's GameUserSettings restored — the revert path saves the ORIGINAL values).
class UCk_AutoTest_GameSettings_ResolutionConfirmWindow_RevertsOnExpiry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0;

    private FString _OriginalResolution;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        utils_game_settings::Request_RegisterVideoPack();

        _OriginalResolution = utils_game_settings::Get_SettingValue_String(n"video.resolution", "");
        Assert_True(_OriginalResolution != "", "current resolution readable through GameUserSettings");

        Assert_True(utils_game_settings::Request_SetResolutionWithConfirmWindow("1236x789", 1.0),
            "confirm-window set holds");
        Assert_Equals_String(utils_game_settings::Get_SettingValue_String(n"video.resolution", ""), "1236x789",
            "new resolution is live during the window");

        WaitUntil(n"Check_Reverted", n"OnReverted", 100000);
    }

    UFUNCTION()
    private void Check_Reverted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_game_settings::Get_SettingValue_String(n"video.resolution", "") == _OriginalResolution);
    }

    UFUNCTION()
    private void OnReverted(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_String(utils_game_settings::Get_SettingValue_String(n"video.resolution", ""), _OriginalResolution,
            "expiry reverted to the prior resolution");
        FinishSuccess();
    }
}
