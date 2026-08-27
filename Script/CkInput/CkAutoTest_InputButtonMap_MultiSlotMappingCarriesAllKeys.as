// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP - AUTOMATION TEST: A MULTI-SLOT MAPPING CARRIES EVERY KEY
//============================================================================
//
// A Mapped button used to carry ONE key - First slot, no matter how many were
// bound. It now carries EVERY bound slot's key, primary first. This pins the
// base case for that contract: CkTests_DualBound is bound in TWO slots (F8
// registered first, so First; F12 second, so Second), and after the first
// derivation the map must answer both directions correctly
//
//   button -> keys:  Get_KeysForButton   answers [F8, F12], primary first
//   button -> key:   TryGet_KeyForButton answers F8 alone - the scalar reader
//                     a display/consumer that wants ONE key still uses
//   key -> button:    Get_ButtonIdsForKey finds the SAME button from EITHER key
//
// The third line is what a single-key implementation gets wrong first: a
// reverse lookup keyed on "the" key a button carries would answer F8 and go
// blind to F12, so the same press some other slot device made would resolve
// to nothing.
//
// No key binding is mutated here - CkTests_DualBound stays on its authored
// F8/F12 defaults for the whole test - so there is nothing to reset on
// teardown.
//============================================================================

class UCk_AutoTest_InputButtonMap_MultiSlotMappingCarriesAllKeys : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;

    private FName _MappingName = n"CkTests_DualBound";
    private FKey  _PrimaryKey;
    private FKey  _SecondaryKey;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PrimaryKey   = EKeys::F8;
        _SecondaryKey = EKeys::F12;

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

        Add_Step_WaitUntil("the first derivation lands the dual-bound button", n"Check_DualBoundDerived");
        Add_Step(          "assert both keys resolve in both directions",      n"Step_AssertBothKeys");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertBothKeys(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto ButtonId = DoMake_MappedButton();

        auto Keys = utils_input_button_map::Get_KeysForButton(_Map, ButtonId);
        Assert_Equals_Int(Keys.Num(), 2,
            f"a mapping bound in two slots carries exactly two keys (got {Keys.Num()})");

        if (Keys.Num() == 2)
        {
            Assert_True(Keys[0] == _PrimaryKey,
                f"the FIRST slot's key leads Get_KeysForButton (got {Keys[0].GetKeyName()})");
            Assert_True(Keys[1] == _SecondaryKey,
                f"the SECOND slot's key follows it (got {Keys[1].GetKeyName()})");
        }

        auto Primary = utils_input_button_map::TryGet_KeyForButton(_Map, ButtonId);
        Assert_True(Primary == _PrimaryKey,
            f"TryGet_KeyForButton answers the primary key alone (got {Primary.GetKeyName()})");

        auto HoldersOfPrimary = utils_input_button_map::Get_ButtonIdsForKey(_Map, _PrimaryKey);
        Assert_True(DoContainsMapped(HoldersOfPrimary, _MappingName),
            "the primary key resolves back to the dual-bound button");

        auto HoldersOfSecondary = utils_input_button_map::Get_ButtonIdsForKey(_Map, _SecondaryKey);
        Assert_True(DoContainsMapped(HoldersOfSecondary, _MappingName),
            "the SECONDARY key resolves to the same button too - a reverse lookup keyed on one key would go blind to it");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_DualBoundDerived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoHasMappedButton(_MappingName));
    }

    //------------------------------------------------------------------------

    private FCk_Input_ButtonId DoMake_MappedButton()
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, _MappingName);
    }

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
