// Language=angelscript

//============================================================================
// CK INPUT - AUTOMATION TEST: SAVE ACCEPTS THE PROFILE WITHOUT MUTATING IT
//============================================================================
//
// WHAT THIS PROVES, AND WHAT IT CANNOT. SaveKeyBindings is reachable on a
// remapped profile and leaves that profile byte-identical afterwards - the
// keys the caller set are still the keys the queries report. That is the whole
// of what a headless test can see.
//
// It does NOT prove anything reached disk, and deliberately does not pretend
// to. SaveKeyBindings calls AsyncSaveSettings (CkKeyBinding_Utils.cpp:378),
// which snapshots the settings object on the game thread and hands the bytes
// to the platform save system for a background write
// (EnhancedInputUserSettings.cpp:769-782, GameplayStatics.cpp:2403-2426).
// There is no synchronous completion signal, and the only honest proof that a
// binding survives a restart is the relaunch check recorded as [EDITOR-VERIFY]
// under work item 1a-4. A test that asserted persistence from inside one
// session would be asserting its own in-memory state twice.
//
// TEARDOWN IS THE POINT, NOT AN EPILOGUE. Unlike every other test here this
// one writes real user settings under Saved/, which outlive the PIE session
// and the next baseline capture. The sanctioned end state is therefore a
// SECOND save carrying default content, issued immediately after
// ResetAllToDefaults, so whatever lands on disk is the authored bindings.
//
// KNOWN RESIDUAL RISK, recorded rather than hidden: the engine's save pipe
// serialises async saves but explicitly does not guarantee their ORDER
// (SaveGameSystem.h:101-102). Two saves to one slot in one frame can in
// principle land newest-first, leaving the remapped snapshot on disk. The
// content of each snapshot is captured synchronously at its call site, so the
// bytes are never mixed - only which of the two wins.
//============================================================================

class UCk_AutoTest_Input_SaveWritesUserSettings : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController - the key profile lives on the local player");
            return;
        }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(PlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        {
            FinishFailure("Enhanced Input user settings unavailable on the local player");
            return;
        }

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        auto KeyBefore = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Flashlight", EPlayerMappableKeySlot::First);
        Assert_True(KeyBefore == EKeys::F,
            f"CkTests_Flashlight starts on its authored default F (got {KeyBefore.GetKeyName()})");

        auto FailureReason = FGameplayTagContainer();
        auto Remapped = utils_key_binding::RemapKey(
            PlayerController, n"CkTests_Flashlight", EPlayerMappableKeySlot::First, EKeys::L, FailureReason);
        Assert_True(Remapped, "RemapKey reports success rebinding CkTests_Flashlight to the unused key L");

        utils_key_binding::SaveKeyBindings(PlayerController);

        auto KeyAfterSave = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Flashlight", EPlayerMappableKeySlot::First);
        Assert_True(KeyAfterSave == EKeys::L,
            f"the profile still reports the remapped L after SaveKeyBindings (got {KeyAfterSave.GetKeyName()})");
        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::L).Contains(n"CkTests_Flashlight"),
            "the key-to-name index is intact after SaveKeyBindings");

        utils_key_binding::ResetAllToDefaults(PlayerController);
        utils_key_binding::SaveKeyBindings(PlayerController);

        auto KeyAfterTeardown = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Flashlight", EPlayerMappableKeySlot::First);
        Assert_True(KeyAfterTeardown == EKeys::F,
            f"the saved end state is the authored F (got {KeyAfterTeardown.GetKeyName()})");

        auto JumpKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Crouch", EPlayerMappableKeySlot::First);
        auto InteractKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);

        Assert_True(JumpKey == EKeys::SpaceBar,
            f"CkTests_Jump is on its authored SpaceBar in the saved end state (got {JumpKey.GetKeyName()})");
        Assert_True(CrouchKey == EKeys::C,
            f"CkTests_Crouch is on its authored C in the saved end state (got {CrouchKey.GetKeyName()})");
        Assert_True(InteractKey == EKeys::E,
            f"CkTests_Interact is on its authored E in the saved end state (got {InteractKey.GetKeyName()})");

        FinishSuccess();
    }
}
