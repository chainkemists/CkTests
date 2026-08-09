// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP — AUTOMATION TEST: A REBIND MOVES THE KEY, NOT THE BUTTON
//============================================================================
//
// This is the whole reason the button space exists. A definition that names a
// button must survive the player rebinding it, with no edit anywhere — which is
// only true if a re-derive moves ASSOCIATIONS and leaves IDENTITIES alone.
//
// Three things are pinned, and the third is the one an "obvious" implementation
// gets wrong by rebuilding the map from scratch:
//
//   1. Jump's identity after the rebind is the SAME identity captured before it
//      — same tier, same name, still present in the map.
//   2. Its association moved to the new key.
//   3. The OLD key no longer resolves to it. A map that re-pointed the new key
//      without clearing the old one would pass 1 and 2 and still hand a
//      consumer two buttons for one press.
//
// F1 is chosen because no CkTests mapping is authored to it, so the remap cannot
// be a disguised conflict resolution.
//
// TEARDOWN IS UNCONDITIONAL within its step: all autotests share one PIE session
// and profile rows outlive the test that touched them, so the reset runs whether
// or not the assertions above it held.
//============================================================================

class UCk_AutoTest_InputButtonMap_RebindMovesAssociationNotIdentity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;

    private FCk_Input_ButtonId _CapturedJumpId;
    private bool               _CapturedJump = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController — the mapped tier derives from the local player's profile");
            return;
        }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(PlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        {
            FinishFailure("Enhanced Input user settings unavailable on the local player");
            return;
        }

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Map    = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData());

        Assert_True(ck::IsValid(_Map),
            "the button map must compose for this test to mean anything");

        Add_Step_WaitUntil("the first derivation drains onto the map",     n"Check_JumpDerived");
        Add_Step(          "capture Jump's identity, then rebind it to F1", n"Step_CaptureThenRebind");
        Add_Step_WaitUntil("the re-derive lands the new association",      n"Check_JumpMovedToF1");
        Add_Step(          "assert the identity held while the key moved", n"Step_AssertIdentityHeld");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_CaptureThenRebind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Buttons = utils_input_button_map::Get_AllButtons(_Map);

        for (auto Index = 0; Index < Buttons.Num(); Index++)
        {
            if (Buttons[Index].Get_Tier() != ECk_Input_ButtonTier::Mapped)
            { continue; }

            if (Buttons[Index].Get_Name() != n"CkTests_Jump")
            { continue; }

            _CapturedJumpId = Buttons[Index];
            _CapturedJump = true;
            break;
        }

        Assert_True(_CapturedJump,
            "Jump's identity must be readable off the map before the rebind");

        auto BeforeKey = utils_input_button_map::TryGet_KeyForButton(_Map, _CapturedJumpId);
        Assert_True(BeforeKey == EKeys::SpaceBar,
            f"Jump starts associated with its authored SpaceBar (got {BeforeKey.GetKeyName()})");

        auto HoldersOfSpaceBar = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::SpaceBar);
        Assert_True(DoContainsMapped(HoldersOfSpaceBar, n"CkTests_Jump"),
            "SpaceBar resolves to Jump before the rebind");

        auto PlayerController = Gameplay::GetPlayerController(0);
        auto FailureReason = FGameplayTagContainer();
        auto Remapped = utils_key_binding::RemapKey(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First, EKeys::F1, FailureReason);
        Assert_True(Remapped, "RemapKey reports success rebinding CkTests_Jump to the unused key F1");

        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
    }

    UFUNCTION()
    private void Step_AssertIdentityHeld(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(DoHasMappedButton(n"CkTests_Jump"),
            "the re-derive must not have dropped Jump's identity");

        auto Buttons = utils_input_button_map::Get_AllButtons(_Map);
        auto FoundSame = false;

        for (auto Index = 0; Index < Buttons.Num(); Index++)
        {
            if (Buttons[Index].Get_Tier() == _CapturedJumpId.Get_Tier() &&
                Buttons[Index].Get_Name() == _CapturedJumpId.Get_Name())
            {
                FoundSame = true;
                break;
            }
        }

        Assert_True(FoundSame,
            "the identity captured before the rebind is still the identity the map holds after it");

        auto AfterKey = utils_input_button_map::TryGet_KeyForButton(_Map, _CapturedJumpId);
        Assert_True(AfterKey == EKeys::F1,
            f"the captured identity now resolves to the rebound key F1 (got {AfterKey.GetKeyName()})");

        auto HoldersOfSpaceBar = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::SpaceBar);
        Assert_False(DoContainsMapped(HoldersOfSpaceBar, n"CkTests_Jump"),
            "the key Jump left must stop resolving to it, or one press would produce two buttons");

        auto PlayerController = Gameplay::GetPlayerController(0);
        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Jump");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_JumpDerived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoHasMappedButton(n"CkTests_Jump"));
    }

    UFUNCTION()
    private void Check_JumpMovedToF1(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoContainsMapped(
            utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F1), n"CkTests_Jump"));
    }

    //------------------------------------------------------------------------

    private bool DoHasMappedButton(FName InMappingName)
    {
        return DoContainsMapped(utils_input_button_map::Get_AllButtons(_Map), InMappingName);
    }

    private bool DoContainsMapped(const TArray<FCk_Input_ButtonId>& InButtons, FName InMappingName)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Mapped)
            { continue; }

            if (InButtons[Index].Get_Name() == InMappingName)
            { return true; }
        }

        return false;
    }
}
