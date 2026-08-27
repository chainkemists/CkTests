// Language=angelscript

//============================================================================
// CK INPUT - AUTOMATION TEST: UNBIND-AND-REMAP LEAVES THE HOLDER UNBOUND
//============================================================================
//
// UnbindConflictAndRemap is the resolution that does NOT keep both actions
// bound: the requested mapping takes the contested key and whoever held it is
// left with nothing. This pins both halves, because a resolution that only
// moved the requested side would read as correct from the caller's row while
// leaving TWO mappings answering to the same key.
//
// THE HOLDER IS ON ITS AUTHORED DEFAULT ON PURPOSE. CkTests_Interact is asked
// to give up E, which is exactly the key it was authored with. Unbinding and
// reverting-to-default are indistinguishable on a holder that had been remapped
// away from its default, and they are opposites on one that never moved: a
// revert leaves the holder exactly where it was, so the contested key stays
// doubly bound and no query reports anything wrong. The opening assertion that
// Interact is on E is therefore load-bearing, not scene-setting.
//
// The key-to-name index is asserted alongside Get_KeyForMapping because they
// are separate reads of the same profile - the index is what a settings screen
// uses to render "also held by", and an unbind the index did not see would
// leave a phantom conflict on the page.
//
// Membership is asserted on the two mapping names this test owns rather than
// on a count: every autotest shares one PIE session and one key profile, so a
// foreign registration's rows can legitimately sit on E alongside ours.
//
// TEARDOWN IS UNCONDITIONAL. Assert_* records a failure without aborting, so
// the reset runs on every path. It matters more here than in the sibling tests:
// this is the only one that leaves a row UNBOUND, a state no other test in the
// session would restore on its way past.
//============================================================================

class UCk_AutoTest_Input_UnbindConflictAndRemapUnbindsHolder : UCk_AutoTest_Base
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
        utils_key_binding::ResetAllToDefaults(PlayerController);

        auto JumpBefore = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto InteractBefore = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);

        Assert_True(JumpBefore == EKeys::SpaceBar,
            f"CkTests_Jump starts on its authored default SpaceBar (got {JumpBefore.GetKeyName()})");
        Assert_True(InteractBefore == EKeys::E,
            f"CkTests_Interact starts on its authored default E - the holder has not been moved off it (got {InteractBefore.GetKeyName()})");

        auto FailureReason = FGameplayTagContainer();
        auto Succeeded = utils_key_binding::UnbindConflictAndRemap(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::E, FailureReason);
        Assert_True(Succeeded, "UnbindConflictAndRemap reports success taking E from CkTests_Interact for CkTests_Jump");

        auto JumpAfter = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto InteractAfter = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);

        Assert_True(JumpAfter == EKeys::E,
            f"CkTests_Jump holds the requested key E (got {JumpAfter.GetKeyName()})");
        Assert_False(InteractAfter.IsValid(),
            f"CkTests_Interact is left unbound rather than back on its authored default (got {InteractAfter.GetKeyName()})");

        auto NamesOnE = utils_key_binding::Get_MappingNamesForKey(PlayerController, EKeys::E);
        Assert_True(NamesOnE.Contains(n"CkTests_Jump"),
            "the key-to-name index lists CkTests_Jump under E after the resolution");
        Assert_False(NamesOnE.Contains(n"CkTests_Interact"),
            "the key-to-name index no longer lists CkTests_Interact under E - E is not doubly bound");

        utils_key_binding::ResetAllToDefaults(PlayerController);

        auto JumpRestored = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto InteractRestored = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);

        Assert_True(JumpRestored == EKeys::SpaceBar,
            f"the teardown returns CkTests_Jump to its authored SpaceBar (got {JumpRestored.GetKeyName()})");
        Assert_True(InteractRestored == EKeys::E,
            f"the teardown puts the unbound CkTests_Interact back on its authored E (got {InteractRestored.GetKeyName()})");

        FinishSuccess();
    }
}
