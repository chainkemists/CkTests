// Language=angelscript

// Verifies the subsystem -> provider -> ini round trip: a set value reaches the store, survives
// a flush, and a FRESH provider instance pointed at the same file reads it back verbatim.
class UCk_AutoTest_GameSettings_PersistRoundTrip : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Assert_True(utils_game_settings::Request_RegisterSetting(
            FCk_GameSettings_SettingDefinition(n"astest.persist.key", ECk_GameSettings_ValueType::String, "unset")),
            "String setting registers");

        Assert_True(utils_game_settings::Request_SetSettingValue_String(
            FCk_Request_GameSettings_SetValue_String(n"astest.persist.key", "persisted-value")),
            "set holds");

        utils_game_settings::Request_FlushStorage();

        auto LiveProvider = Cast<UCk_GameSettings_IniStorageProvider_UE>(utils_game_settings::Get_StorageProvider());
        if (LiveProvider == nullptr)
        {
            FinishFailure("The subsystem's storage provider is not the ini provider - this test asserts the ini file round trip");
            return;
        }

        auto FreshProvider = Cast<UCk_GameSettings_IniStorageProvider_UE>(
            NewObject(this, UCk_GameSettings_IniStorageProvider_UE));
        FreshProvider.Set_FilePathOverride(LiveProvider.Get_StorageFilePath());

        auto StoredValues = FreshProvider.Get_StoredValues(ECk_GameSettings_Scope::Machine, 0);

        auto FoundValue = FString();
        auto Found = false;
        for (int32 Index = 0; Index < StoredValues.Num(); ++Index)
        {
            if (StoredValues[Index].Get_Key() == n"astest.persist.key")
            {
                Found = true;
                FoundValue = StoredValues[Index].Get_Value();
                break;
            }
        }

        Assert_True(Found, "set value reached the flushed ini file");
        Assert_Equals_String(FoundValue, "persisted-value", "flushed value round-trips verbatim");
        FinishSuccess();
    }
}
