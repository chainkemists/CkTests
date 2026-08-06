// Language=angelscript

// Verifies the seam the Audio pack rides: a Float volume setting with a Handler binding routes
// every applied value into the registered handler — including the immediate apply at handler
// registration. The SoundMix side of the pack is asset-dependent and covered by [EDITOR-VERIFY].
class UCk_AutoTest_GameSettings_AudioPack_HandlerReceivesVolume : UCk_AutoTest_Base
{
    private float _ReceivedVolume = -1.0;
    private int32 _ReceiveCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Definition = FCk_GameSettings_SettingDefinition(n"astest.audiopack.master", ECk_GameSettings_ValueType::Float, "1");
        Definition.Set_ApplyBindingType(ECk_GameSettings_ApplyBindingType::Handler);
        Definition.Set_MinValue("0");
        Definition.Set_MaxValue("1");

        Assert_True(utils_game_settings::Request_RegisterSetting(Definition), "volume setting registers");

        Assert_True(utils_game_settings::Request_RegisterApplyHandler_Float(n"astest.audiopack.master",
            FCk_Delegate_GameSettings_ApplyHandler_Float(this, n"OnVolumeApplied")),
            "handler registers");

        Assert_Equals_Int(_ReceiveCount, 1, "registering the handler applies the current value immediately");
        Assert_Equals_Float(_ReceivedVolume, 1.0, 0.001, "immediate apply carries the current value");

        Assert_True(utils_game_settings::Request_SetSettingValue_Float(
            FCk_Request_GameSettings_SetValue_Float(n"astest.audiopack.master", 0.42)),
            "set holds");

        Assert_Equals_Int(_ReceiveCount, 2, "set routes to the handler");
        Assert_Equals_Float(_ReceivedVolume, 0.42, 0.001, "handler receives the volume");
        Assert_Equals_Float(utils_game_settings::Get_SettingValue_Float(n"astest.audiopack.master", -1.0), 0.42, 0.001,
            "typed read agrees with the handler");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnVolumeApplied(float32 InNewValue)
    {
        _ReceivedVolume = InNewValue;
        ++_ReceiveCount;
    }
}
