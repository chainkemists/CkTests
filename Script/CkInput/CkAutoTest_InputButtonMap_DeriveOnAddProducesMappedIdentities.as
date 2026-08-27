// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP - AUTOMATION TEST: COMPOSING A MAP DERIVES THE PROFILE
//============================================================================
//
// The mapped tier is not declared anywhere - it is READ off the player's
// resolved mappings - so "does the map know about my buttons" is entirely a
// question of whether the derivation ran and what it read.
//
// This pins the base case: register the four authored CkTests mappings, compose
// a map on a synthetic source, and after the first derivation each of the four
// names owns a Mapped identity whose association is that mapping's authored
// default key.
//
// The wait is on ONE of the four names existing rather than on a count. Every
// autotest shares one PIE world and the key profile is global to it - other
// suites register their own contexts, so a count would be measuring them too.
// The assertions that follow name only the four this test authored.
//
// The keys are asserted against the authored defaults rather than against
// Get_KeyForMapping, deliberately: reading the answer out of the same store the
// derivation read would pass even if the derivation copied garbage.
//============================================================================

class UCk_AutoTest_InputButtonMap_DeriveOnAddProducesMappedIdentities : UCk_AutoTest_Base
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

        Add_Step_WaitUntil("the first derivation drains onto the map", n"Check_JumpDerived");
        Add_Step(          "assert every authored name owns its default key", n"Step_AssertAuthoredRows");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertAuthoredRows(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertMappedRow(n"CkTests_Jump",       EKeys::SpaceBar);
        DoAssertMappedRow(n"CkTests_Crouch",     EKeys::C);
        DoAssertMappedRow(n"CkTests_Interact",   EKeys::E);
        DoAssertMappedRow(n"CkTests_Flashlight", EKeys::F);
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

    //------------------------------------------------------------------------

    private void DoAssertMappedRow(FName InMappingName, FKey InExpectedKey)
    {
        Assert_True(DoHasMappedButton(InMappingName),
            f"deriving mints a Mapped identity for the authored mapping name {InMappingName}");

        auto Associated = utils_input_button_map::TryGet_KeyForButton(
            _Map, FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, InMappingName));

        Assert_True(Associated == InExpectedKey,
            f"{InMappingName} associates with its authored default key (got {Associated.GetKeyName()})");
    }

    private bool DoHasMappedButton(FName InMappingName)
    {
        auto Buttons = utils_input_button_map::Get_AllButtons(_Map);

        for (auto Index = 0; Index < Buttons.Num(); Index++)
        {
            if (Buttons[Index].Get_Tier() != ECk_Input_ButtonTier::Mapped)
            { continue; }

            if (Buttons[Index].Get_Name() == InMappingName)
            { return true; }
        }

        return false;
    }
}
