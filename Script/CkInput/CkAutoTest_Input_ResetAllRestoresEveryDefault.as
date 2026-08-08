// Language=angelscript

//============================================================================
// CK INPUT — AUTOMATION TEST: RESET-ALL RESTORES EVERY AUTHORED DEFAULT
//============================================================================
//
// ResetAllToDefaults is the "restore defaults" button on a settings page and
// the teardown every other rebinding test leans on, so it is worth pinning
// that it reaches rows the caller never named. Two mappings are moved and all
// four are checked afterwards: the two that were changed prove the reset
// happened, the two that were not prove it did not overwrite untouched rows
// with something other than their authored keys.
//
// The reset goes through the shipped util rather than the profile directly.
// UEnhancedPlayerMappableKeyProfile::ResetToDefault bypasses the settings
// layer and broadcasts nothing, so CkInput fires OnSettingsChanged by hand
// afterwards (CkKeyBinding_Utils.cpp:356-360) — calling the profile method
// straight would leave every watcher stale.
//
// K and L are unused by this IMC's authored content, so neither remap can be
// a disguised conflict resolution, and both land on the existing slot-First
// rows rather than adding new ones — the remappable-key count is unchanged.
//
// ResetAllToDefaults IS this test's teardown. Assert_* records a failure
// without aborting, so the reset is reached on every path — a failed
// assertion cannot also leak a rebind into the shared PIE session.
//============================================================================

class UCk_AutoTest_Input_ResetAllRestoresEveryDefault : UCk_AutoTest_Base
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

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        DoAssertAuthoredDefaults(PlayerController, "before any remap");

        auto FailureReason = FGameplayTagContainer();
        Assert_True(utils_key_binding::RemapKey(
                PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::K, FailureReason),
            "RemapKey reports success rebinding CkTests_Jump to the unused key K");
        Assert_True(utils_key_binding::RemapKey(
                PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First, EKeys::L, FailureReason),
            "RemapKey reports success rebinding CkTests_Interact to the unused key L");

        auto JumpRemapped = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto InteractRemapped = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);

        Assert_True(JumpRemapped == EKeys::K,
            f"CkTests_Jump holds K before the reset (got {JumpRemapped.GetKeyName()})");
        Assert_True(InteractRemapped == EKeys::L,
            f"CkTests_Interact holds L before the reset (got {InteractRemapped.GetKeyName()})");

        utils_key_binding::ResetAllToDefaults(PlayerController);

        DoAssertAuthoredDefaults(PlayerController, "after ResetAllToDefaults");

        FinishSuccess();
    }

    private void DoAssertAuthoredDefaults(const APlayerController InPlayerController, const FString& InWhen)
    {
        auto JumpKey = utils_key_binding::Get_KeyForMapping(
            InPlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            InPlayerController, n"CkTests_Crouch", EPlayerMappableKeySlot::First);
        auto InteractKey = utils_key_binding::Get_KeyForMapping(
            InPlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);
        auto FlashlightKey = utils_key_binding::Get_KeyForMapping(
            InPlayerController, n"CkTests_Flashlight", EPlayerMappableKeySlot::First);

        Assert_True(JumpKey == EKeys::SpaceBar,
            f"CkTests_Jump holds its authored SpaceBar {InWhen} (got {JumpKey.GetKeyName()})");
        Assert_True(CrouchKey == EKeys::C,
            f"CkTests_Crouch holds its authored C {InWhen} (got {CrouchKey.GetKeyName()})");
        Assert_True(InteractKey == EKeys::E,
            f"CkTests_Interact holds its authored E {InWhen} (got {InteractKey.GetKeyName()})");
        Assert_True(FlashlightKey == EKeys::F,
            f"CkTests_Flashlight holds its authored F {InWhen} (got {FlashlightKey.GetKeyName()})");
    }
}
