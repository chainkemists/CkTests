// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP - AUTOMATION TEST: NO EDIT LANDS ON THE CALLING STACK
//============================================================================
//
// Every mutation of the button space is a deferred request, including the FIRST
// derivation that Add starts. That buys the same guarantee the rest of CkInput
// gives: whatever reads the map during a frame reads a table that cannot change
// underneath it, and a consumer resolving buttons after routing sees a settled
// answer rather than a half-applied one.
//
// The price is a visibility boundary, and it is the contract rather than a race
// - so it is asserted from both sides:
//
//   1. Immediately after Add the map is EMPTY. A first-derive that ran inline
//      would have filled it here, and would then be able to fill it in the
//      middle of somebody else's read.
//   2. Immediately after Request_RegisterPhysicalButton the new button is still
//      absent, and its completion has NOT fired - an accepted request completes
//      when it DRAINS, not when it is enqueued.
//   3. Once drained, both the button and its completion are there.
//
// Step 3 is what keeps 1 and 2 from passing vacuously: without it, a map that
// never landed anything at all would satisfy both.
//
// F11 is chosen because no CkTests mapping is authored to it and no other script
// in this plugin names it, so nothing else can put it in this map.
//============================================================================

class UCk_AutoTest_InputButtonMap_EditsFollowDeferredContract : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;

    private int32 _RegisterFires = 0;
    private bool  _RegisterSucceeded = false;

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

        // This map is entirely this test's own, so its size is a legitimate thing
        // to count - unlike the shared key profile it derives from.
        Assert_Equals_Int(utils_input_button_map::Get_AllButtons(_Map).Num(), 0,
            "the first derivation is deferred - Add must not have filled the map on the calling stack");

        Add_Step_WaitUntil("the first derivation drains",                    n"Check_FirstDeriveLanded");
        Add_Step(          "register a physical button, assert it is unseen", n"Step_RegisterAndAssertUnseen");
        Add_Step_WaitUntil("the registration drains and completes",          n"Check_RegisterCompleted");
        Add_Step(          "assert the drained edit is now visible",         n"Step_AssertVisibleAfterDrain");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RegisterAndAssertUnseen(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(DoHasMappedButton(n"CkTests_Jump"),
            "the deferred first derivation did land - the boundary is a delay, not a drop");

        Assert_Equals_Int(utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F11).Num(), 0,
            "nothing may already hold the key this step is about to register");

        utils_input_button_map::Request_RegisterPhysicalButton(
            _Map, FCk_Request_InputButtonMap_RegisterPhysicalButton(EKeys::F11),
            FCk_Delegate_Request_OnCompleted(this, n"OnRegisterCompleted"));

        Assert_Equals_Int(utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F11).Num(), 0,
            "a registration is deferred - the map must not have moved on the calling stack");
        Assert_Equals_Int(_RegisterFires, 0,
            "an accepted registration completes when it DRAINS, not when it is enqueued");
    }

    UFUNCTION()
    private void Step_AssertVisibleAfterDrain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RegisterFires, 1,
            "the drained registration completed exactly once");
        Assert_True(_RegisterSucceeded,
            "registering an unclaimed valid key completes Succeeded");

        auto Holders = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F11);
        Assert_Equals_Int(Holders.Num(), 1,
            "the drained registration is readable back through the reverse lookup");

        if (Holders.Num() != 1)
        { return; }

        Assert_True(Holders[0].Get_Tier() == ECk_Input_ButtonTier::Physical,
            "a registered raw key mints a Physical button");

        auto Associated = utils_input_button_map::TryGet_KeyForButton(_Map, Holders[0]);
        Assert_True(Associated == EKeys::F11,
            f"the forward direction agrees after the drain (got {Associated.GetKeyName()})");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_FirstDeriveLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoHasMappedButton(n"CkTests_Jump"));
    }

    UFUNCTION()
    private void Check_RegisterCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RegisterFires >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnRegisterCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _RegisterFires += 1;
        _RegisterSucceeded = InResult == ECk_Request_OperationResult::Succeeded;

        Assert_True(InRequestOwner == _Map,
            "completion must report the button map the registration was enqueued on");
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
