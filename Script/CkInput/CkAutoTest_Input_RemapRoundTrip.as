// Language=angelscript

//============================================================================
// CK INPUT — AUTOMATION TEST: REMAP THEN RESET RETURNS THE AUTHORED KEY
//============================================================================
//
// The smallest complete rebinding cycle on the shipped surface: read the
// authored default, RemapKey to an unused key, read it back through both
// query directions (Get_KeyForMapping and the profile's key->name index), then
// ResetMappingToDefault and confirm the authored key is back.
//
// K is chosen because no CkTests mapping is authored to it, so the remap
// cannot be a disguised conflict resolution. The remap lands on the EXISTING
// slot-First row rather than creating a second one — every mapping this IMC
// registers gets slot First (EnhancedInputUserSettings.cpp:1708 does
// FindOrAdd on a per-name slot counter, and EPlayerMappableKeySlot::First is
// 0), and MapPlayerKey's FindKeyMapping matches on slot (:1150, :630-633). The
// remappable-key COUNT is therefore unchanged by this test, which is what
// keeps the sibling count assertion in RemappableKeysRegistered honest.
//
// TEARDOWN IS UNCONDITIONAL. All autotests share one PIE session and profile
// rows outlive the test that touched them, so the reset runs whether or not
// the assertions above held — a failed assertion must not also leak a rebind
// into every later test and into the next baseline capture.
//============================================================================

class UCk_AutoTest_Input_RemapRoundTrip : UCk_AutoTest_Base
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

        auto KeyBefore = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        Assert_True(KeyBefore == EKeys::SpaceBar,
            f"CkTests_Jump starts on its authored default SpaceBar (got {KeyBefore.GetKeyName()})");

        auto FailureReason = FGameplayTagContainer();
        auto Remapped = utils_key_binding::RemapKey(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::K, FailureReason);
        Assert_True(Remapped, "RemapKey reports success rebinding CkTests_Jump to the unused key K");

        auto KeyAfterRemap = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        Assert_True(KeyAfterRemap == EKeys::K,
            f"Get_KeyForMapping reports K for CkTests_Jump after the remap (got {KeyAfterRemap.GetKeyName()})");

        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::K).Contains(n"CkTests_Jump"),
            "the profile's key-to-name index lists CkTests_Jump under K after the remap");
        Assert_False(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::SpaceBar).Contains(n"CkTests_Jump"),
            "CkTests_Jump no longer answers to its former key SpaceBar");

        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Jump");

        auto KeyAfterReset = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        Assert_True(KeyAfterReset == EKeys::SpaceBar,
            f"ResetMappingToDefault restores the authored SpaceBar (got {KeyAfterReset.GetKeyName()})");
        Assert_True(utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::SpaceBar).Contains(n"CkTests_Jump"),
            "the key-to-name index has CkTests_Jump back under SpaceBar after the reset");

        FinishSuccess();
    }
}
