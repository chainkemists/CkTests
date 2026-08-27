// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP - AUTOMATION TEST: ONE KEY, EVERY BUTTON IT PRODUCES
//============================================================================
//
// Key -> button is ONE-TO-MANY by design. Two mappings in different categories
// legitimately share a key, and duplicate bindings turn up in real profiles, so
// a reverse lookup that answered with "the" button would have to pick one - and
// whichever it picked, some consumer would silently stop receiving its input.
//
// Crouch (Movement) and Interact (Interaction) are batch-remapped onto the same
// unused key, and after the re-derive the lookup must name BOTH. The batch form
// is used because it defers the settings broadcast until the last entry, so the
// profile is never observed mid-move.
//
// The assertion is membership, never a count: the shared PIE world's profile may
// hold other suites' mappings, and any of them could legitimately be on F2 too.
//
// TEARDOWN IS UNCONDITIONAL within its step - both rows are reset whether or not
// the assertions above them held, because a leaked rebind poisons every later
// test that reads this profile.
//============================================================================

class UCk_AutoTest_InputButtonMap_SharedKeyReturnsAllHolders : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController - the mapped tier derives from the local player's profile");
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

        Add_Step_WaitUntil("the first derivation drains onto the map",       n"Check_BothDerived");
        Add_Step(          "put Crouch and Interact on one key, re-derive",  n"Step_ShareOneKey");
        Add_Step_WaitUntil("the re-derive lands both on the shared key",     n"Check_BothOnSharedKey");
        Add_Step(          "assert the lookup names both holders",           n"Step_AssertBothHolders");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ShareOneKey(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto HoldersBefore = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F2);
        Assert_False(DoContainsMapped(HoldersBefore, n"CkTests_Crouch"),
            "Crouch must not already sit on the shared key for this test to mean anything");
        Assert_False(DoContainsMapped(HoldersBefore, n"CkTests_Interact"),
            "Interact must not already sit on the shared key for this test to mean anything");

        TArray<FName> ToShare;
        ToShare.Add(n"CkTests_Crouch");
        ToShare.Add(n"CkTests_Interact");

        auto PlayerController = Gameplay::GetPlayerController(0);
        auto FailureReason = FGameplayTagContainer();
        auto Remapped = utils_key_binding::RemapKeys(
            PlayerController, ToShare, EPlayerMappableKeySlot::First, EKeys::F2, FailureReason);
        Assert_True(Remapped, "RemapKeys reports success putting both mappings on the unused key F2");

        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
    }

    UFUNCTION()
    private void Step_AssertBothHolders(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Holders = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F2);

        Assert_True(DoContainsMapped(Holders, n"CkTests_Crouch"),
            "the shared key names Crouch");
        Assert_True(DoContainsMapped(Holders, n"CkTests_Interact"),
            "the shared key names Interact too - a reverse lookup that picked one would drop the other");

        auto CrouchKey = utils_input_button_map::TryGet_KeyForButton(
            _Map, FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, n"CkTests_Crouch"));
        auto InteractKey = utils_input_button_map::TryGet_KeyForButton(
            _Map, FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, n"CkTests_Interact"));

        Assert_True(CrouchKey == EKeys::F2,
            f"the forward direction agrees for Crouch (got {CrouchKey.GetKeyName()})");
        Assert_True(InteractKey == EKeys::F2,
            f"the forward direction agrees for Interact (got {InteractKey.GetKeyName()})");

        auto PlayerController = Gameplay::GetPlayerController(0);
        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Crouch");
        utils_key_binding::ResetMappingToDefault(PlayerController, n"CkTests_Interact");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_BothDerived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Buttons = utils_input_button_map::Get_AllButtons(_Map);

        auto Res = OutResult;
        Res.Set(DoContainsMapped(Buttons, n"CkTests_Crouch") &&
                DoContainsMapped(Buttons, n"CkTests_Interact"));
    }

    UFUNCTION()
    private void Check_BothOnSharedKey(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Holders = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F2);

        auto Res = OutResult;
        Res.Set(DoContainsMapped(Holders, n"CkTests_Crouch") &&
                DoContainsMapped(Holders, n"CkTests_Interact"));
    }

    //------------------------------------------------------------------------

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
