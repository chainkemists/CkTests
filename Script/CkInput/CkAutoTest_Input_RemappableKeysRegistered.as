// Language=angelscript

//============================================================================
// CK INPUT — AUTOMATION TEST: SCRIPT-LITERAL IMC POPULATES THE KEY PROFILE
//============================================================================
//
// The prerequisite every other CkInput key-binding test rests on: that
// AngelScript-authored Enhanced Input content actually reaches the local
// player's key profile. Registers IMC_CkTests_KeyBinding through
// UEnhancedInputUserSettings::RegisterInputMappingContext — the same call
// UCk_KeyBinding_Subsystem::Initialize makes for asset-registry-scanned
// contexts (CkKeyBinding_Subsystem.cpp:62) — then reads the profile back
// through the shipped Ck surface.
//
// Without this the profile is empty, Get_AllRemappableKeys returns an empty
// array, and every remap / conflict / reset test passes while exercising
// nothing. Assert the count against input_assets::k_MappableRowCount rather
// than a bare "non-empty" so adding content without adding coverage is red.
//
// TEARDOWN IS PARTIAL, AND THAT IS AN ENGINE LIMIT rather than an oversight.
// UnregisterInputMappingContext only drops the context from the registered set
// (EnhancedInputUserSettings.cpp:1789-1792); the rows it added stay in the key
// profile for the rest of the PIE session and Enhanced Input ships no API to
// remove them. Nothing reaches disk — SaveKeyBindings is never called here — and
// re-registration is idempotent (a row already in the same slot is updated, not
// duplicated), so the count is stable across repeat runs in one session.
//============================================================================

class UCk_AutoTest_Input_RemappableKeysRegistered : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController — the key profile lives on the local player");
            return;
        }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(PlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        {
            FinishFailure("Enhanced Input user settings unavailable on the local player");
            return;
        }

        // Deliberately unasserted: the call reports false for an already-registered
        // context, which is the correct outcome on a repeat run in a warm editor.
        // What matters is the profile state below, not who registered it.
        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        auto RemappableKeys = utils_key_binding::Get_AllRemappableKeys(PlayerController);

        Assert_True(RemappableKeys.Num() > 0,
            "Get_AllRemappableKeys returned an empty profile after registering IMC_CkTests_KeyBinding");

        auto ProfileDump = FString();
        for (auto Index = 0; Index < RemappableKeys.Num(); Index++)
        {
            ProfileDump += f" [{RemappableKeys[Index].MappingName}|slot={int(RemappableKeys[Index].Slot)}]";
        }
        Assert_Equals_Int(RemappableKeys.Num(), input_assets::k_MappableRowCount,
            f"player-mappable rows in the active key profile — rows:{ProfileDump}");

        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::SpaceBar).Contains(n"CkTests_Jump"),
            "SpaceBar is registered under the CkTests_Jump mapping name");
        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::C).Contains(n"CkTests_Crouch"),
            "C is registered under the CkTests_Crouch mapping name");
        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::E).Contains(n"CkTests_Interact"),
            "E is registered under the CkTests_Interact mapping name");
        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::F).Contains(n"CkTests_Flashlight"),
            "F is registered under the CkTests_Flashlight mapping name");

        UserSettings.UnregisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        FinishSuccess();
    }
}
