// Language=angelscript

//============================================================================
// CK INPUT - AUTOMATION TEST: A REMAP FIRES THE CHANGE LISTENER EXACTLY ONCE
//============================================================================
//
// UCk_KeyBinding_Subsystem is what lets a settings row redraw itself without
// polling. This pins the whole chain for one mapping: bind, remap, and the
// delegate arrives once carrying the old and new keys, with
// Get_DidMappingKeyChange agreeing about where the row ended up.
//
// NO WAIT IS NEEDED, and that is a verified property rather than an
// assumption. RemapKey sets bDeferOnSettingsChangedBroadcast = false
// (CkKeyBinding_Utils.cpp:271), so MapPlayerKey broadcasts OnSettingsChanged
// on the caller's stack (EnhancedInputUserSettings.cpp:1172-1175) and the
// subsystem re-reads its watchers and executes the delegate inline
// (CkKeyBinding_Subsystem.cpp:154-164). The count is therefore read after the
// event, not before it, and adding a settle would only widen the window in
// which an unrelated broadcast could inflate it.
//
// The listener is bound AFTER the player controller is known to exist, because
// BindTo caches the mapping's current key only when a controller resolves at
// bind time (CkKeyBinding_Subsystem.cpp:112-120); a bind before that would
// report OldKey as Invalid instead of SpaceBar.
//
// ONE listener, on one mapping. UnbindFrom_MappingKeyChanged removes every
// watcher matching (MappingName, Slot) rather than the specific delegate
// (CkKeyBinding_Subsystem.cpp:132-135), so a second listener on this row would
// be collateral damage of this test's own teardown.
//
// TEARDOWN ORDER IS LOAD-BEARING: unbind first, then reset. ResetMappingToDefault
// broadcasts too, and a listener still attached would count that broadcast as
// well - leaving the row correct but the fire count meaningless on a re-run.
//============================================================================

class UCk_AutoTest_Input_ChangeSignalFiresOnRemap : UCk_AutoTest_Base
{
    private int32 _ChangeCount = 0;
    private FName _ObservedMappingName;
    private FKey _ObservedOldKey;
    private FKey _ObservedNewKey;

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
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        Assert_True(KeyBefore == EKeys::SpaceBar,
            f"CkTests_Jump starts on its authored default SpaceBar (got {KeyBefore.GetKeyName()})");

        auto Listener = utils_key_binding::BindTo_OnMappingKeyChanged(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First,
            FCk_OnMappingKeyChanged(this, n"OnJumpKeyChanged"));

        auto FailureReason = FGameplayTagContainer();
        auto Remapped = utils_key_binding::RemapKey(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::K, FailureReason);
        Assert_True(Remapped, "RemapKey reports success rebinding CkTests_Jump to the unused key K");

        Assert_Equals_Int(_ChangeCount, 1, "change-listener fires for the one remap of CkTests_Jump");
        Assert_True(_ObservedMappingName == n"CkTests_Jump",
            f"the delegate names the mapping that moved (got {_ObservedMappingName})");
        Assert_True(_ObservedOldKey == EKeys::SpaceBar,
            f"the delegate reports SpaceBar as the old key (got {_ObservedOldKey.GetKeyName()})");
        Assert_True(_ObservedNewKey == EKeys::K,
            f"the delegate reports K as the new key (got {_ObservedNewKey.GetKeyName()})");

        FKey CurrentKeyAgainstOld;
        auto ChangedAgainstOld = utils_key_binding::Get_DidMappingKeyChange(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::SpaceBar, CurrentKeyAgainstOld);
        Assert_True(ChangedAgainstOld,
            "Get_DidMappingKeyChange agrees the row moved when polled against the pre-remap key");
        Assert_True(CurrentKeyAgainstOld == EKeys::K,
            f"Get_DidMappingKeyChange reports K as the current key (got {CurrentKeyAgainstOld.GetKeyName()})");

        FKey CurrentKeyAgainstNew;
        auto ChangedAgainstNew = utils_key_binding::Get_DidMappingKeyChange(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::K, CurrentKeyAgainstNew);
        Assert_False(ChangedAgainstNew,
            "Get_DidMappingKeyChange reports no change when polled against the key the row now holds");

        utils_key_binding::UnbindFrom_OnMappingKeyChanged(PlayerController, Listener);
        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Jump");

        auto KeyAfterReset = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        Assert_True(KeyAfterReset == EKeys::SpaceBar,
            f"teardown returns CkTests_Jump to its authored SpaceBar (got {KeyAfterReset.GetKeyName()})");
        Assert_Equals_Int(_ChangeCount, 1, "the unbound listener does not observe the teardown reset");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnJumpKeyChanged(FName InMappingName, FKey InOldKey, FKey InNewKey)
    {
        _ChangeCount++;
        _ObservedMappingName = InMappingName;
        _ObservedOldKey = InOldKey;
        _ObservedNewKey = InNewKey;
    }
}
