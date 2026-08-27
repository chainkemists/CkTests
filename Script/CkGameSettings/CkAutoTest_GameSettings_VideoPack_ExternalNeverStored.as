// Language=angelscript

// Verifies the External-policy contract on the Video pack: video.vsync reads/writes through
// UGameUserSettings and NEVER lands in the CkGameSettings store (live provider or flushed file).
// Restores the original vsync value at the end so the dev's GameUserSettings stays untouched.
class UCk_AutoTest_GameSettings_VideoPack_ExternalNeverStored : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        utils_game_settings::Request_RegisterVideoPack();
        Assert_True(utils_game_settings::Get_IsSettingRegistered(n"video.vsync"), "video pack registered video.vsync");

        auto OriginalVSync = utils_game_settings::Get_SettingValue_Bool(n"video.vsync", false);

        Assert_True(utils_game_settings::Request_SetSettingValue_Bool(
            FCk_Request_GameSettings_SetValue_Bool(n"video.vsync", !OriginalVSync)),
            "set holds");
        Assert_True(utils_game_settings::Get_SettingValue_Bool(n"video.vsync", OriginalVSync) == !OriginalVSync,
            "read routes through GameUserSettings and sees the new value");

        utils_game_settings::Request_FlushStorage();

        auto LiveProvider = Cast<UCk_GameSettings_IniStorageProvider_UE>(utils_game_settings::Get_StorageProvider());
        if (LiveProvider == nullptr)
        {
            FinishFailure("The subsystem's storage provider is not the ini provider - this test asserts the store file");
            return;
        }

        auto FreshProvider = Cast<UCk_GameSettings_IniStorageProvider_UE>(
            NewObject(this, UCk_GameSettings_IniStorageProvider_UE));
        FreshProvider.Set_FilePathOverride(LiveProvider.Get_StorageFilePath());

        auto FoundInStore = false;
        auto MachineValues = FreshProvider.Get_StoredValues(ECk_GameSettings_Scope::Machine, 0);
        for (int32 Index = 0; Index < MachineValues.Num(); ++Index)
        {
            if (MachineValues[Index].Get_Key() == n"video.vsync")
            { FoundInStore = true; }
        }
        auto PlayerValues = FreshProvider.Get_StoredValues(ECk_GameSettings_Scope::Player, 0);
        for (int32 Index = 0; Index < PlayerValues.Num(); ++Index)
        {
            if (PlayerValues[Index].Get_Key() == n"video.vsync")
            { FoundInStore = true; }
        }

        Assert_False(FoundInStore, "External value never lands in the flushed CkGameSettings store");

        Assert_True(utils_game_settings::Request_SetSettingValue_Bool(
            FCk_Request_GameSettings_SetValue_Bool(n"video.vsync", OriginalVSync)),
            "original vsync restored");

        FinishSuccess();
    }
}
