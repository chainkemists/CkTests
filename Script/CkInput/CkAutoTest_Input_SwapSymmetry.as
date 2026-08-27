// Language=angelscript

//============================================================================
// CK INPUT - AUTOMATION TEST: SWAP TRADES BOTH KEYS AND IS ITS OWN INVERSE
//============================================================================
//
// SwapKeys is the conflict resolution that keeps both actions bound: the
// requested mapping takes the new key and whoever held that key inherits the
// requested mapping's old key. Both halves are asserted - a swap that only
// moved the requested side would look correct from the caller's row and
// silently unbind the other action.
//
// Swapping back is asserted as a separate act rather than assumed: it is the
// only cheap proof that the operation is symmetric, and it doubles as the
// restore this shared-session profile needs.
//
// SCOPE: both sides are bound before either swap, and the opening assertions
// enforce that. SwapKeys reads the source's old key as EKeys::Invalid when the
// source has none (CkKeyBinding_Utils.cpp:474-485), so an unbound-source swap
// assigns Invalid to the other action - a distinct behaviour that this test
// deliberately does not exercise.
//
// TEARDOWN IS UNCONDITIONAL. The trailing resets run whether or not the
// swap-back assertions held, so a failure here cannot also leak a rebind into
// every later test in the shared PIE session.
//============================================================================

class UCk_AutoTest_Input_SwapSymmetry : UCk_AutoTest_Base
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

        auto JumpBefore = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto CrouchBefore = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Crouch", EPlayerMappableKeySlot::First);

        Assert_True(JumpBefore == EKeys::SpaceBar,
            f"CkTests_Jump starts on its authored default SpaceBar (got {JumpBefore.GetKeyName()})");
        Assert_True(CrouchBefore == EKeys::C,
            f"CkTests_Crouch starts on its authored default C (got {CrouchBefore.GetKeyName()})");

        auto FailureReason = FGameplayTagContainer();
        auto Swapped = utils_key_binding::SwapKeys(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::C, FailureReason);
        Assert_True(Swapped, "SwapKeys reports success trading CkTests_Jump onto C");

        auto JumpAfterSwap = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto CrouchAfterSwap = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Crouch", EPlayerMappableKeySlot::First);

        Assert_True(JumpAfterSwap == EKeys::C,
            f"the swap gives CkTests_Jump the requested key C (got {JumpAfterSwap.GetKeyName()})");
        Assert_True(CrouchAfterSwap == EKeys::SpaceBar,
            f"the swap hands CkTests_Crouch the key CkTests_Jump gave up (got {CrouchAfterSwap.GetKeyName()})");

        auto SwappedBack = utils_key_binding::SwapKeys(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::SpaceBar, FailureReason);
        Assert_True(SwappedBack, "SwapKeys reports success trading CkTests_Jump back onto SpaceBar");

        auto JumpAfterSwapBack = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto CrouchAfterSwapBack = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Crouch", EPlayerMappableKeySlot::First);

        Assert_True(JumpAfterSwapBack == EKeys::SpaceBar,
            f"the reverse swap returns CkTests_Jump to SpaceBar (got {JumpAfterSwapBack.GetKeyName()})");
        Assert_True(CrouchAfterSwapBack == EKeys::C,
            f"the reverse swap returns CkTests_Crouch to C (got {CrouchAfterSwapBack.GetKeyName()})");

        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Jump");
        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Crouch");

        FinishSuccess();
    }
}
