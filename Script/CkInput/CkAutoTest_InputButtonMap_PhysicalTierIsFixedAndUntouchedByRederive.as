// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP — AUTOMATION TEST: THE PHYSICAL TIER DOES NOT MOVE
//============================================================================
//
// Tier 2 exists so something can name a button before a binding profile does —
// prototyping, synthetic producers, debug keys. That is only worth anything if
// its association is genuinely fixed, so this pins the property a re-derive is
// most likely to break: a derivation that rebuilt the WHOLE table from the
// profile would wipe every physical row, and the map would go quietly empty for
// exactly the consumers that cannot fall back on a mapping.
//
// Both entry points are exercised, because they are separate code paths into the
// same table: F9 is DECLARED on the params at composition, F10 is REGISTERED at
// runtime through the request.
//
// F9 and F10 are chosen because no CkTests mapping is authored to them and no
// other script in this plugin names them, so neither can be a disguised mapped
// button. Nothing presses them — the association is what is under test, not
// delivery.
//
// The re-derive between the two assertion blocks is the actual experiment; the
// first block exists so the second one cannot pass vacuously against a table
// that was empty all along.
//============================================================================

class UCk_AutoTest_InputButtonMap_PhysicalTierIsFixedAndUntouchedByRederive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;

    private int32 _ReRegisterFires = 0;
    private bool  _ReRegisterSucceeded = false;
    private int32 _RederiveFires = 0;

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

        TArray<FKey> Declared;
        Declared.Add(EKeys::F9);

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Map    = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(Declared));

        Assert_True(ck::IsValid(_Map),
            "the button map must compose for this test to mean anything");

        Add_Step_WaitUntil("the declared physical button lands",        n"Check_DeclaredLanded");
        Add_Step(          "register a second physical button at runtime", n"Step_RegisterSecond");
        Add_Step_WaitUntil("the registered physical button lands",      n"Check_RegisteredLanded");
        Add_Step(          "assert both are fixed to their own keys",   n"Step_AssertFixedBeforeRederive");
        Add_Step_WaitUntil("the re-derive drains",                      n"Check_RederiveCompleted");
        Add_Step(          "assert the re-derive left both untouched",  n"Step_AssertUntouchedAfterRederive");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RegisterSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_input_button_map::Request_RegisterPhysicalButton(
            _Map, FCk_Request_InputButtonMap_RegisterPhysicalButton(EKeys::F10));
    }

    UFUNCTION()
    private void Step_AssertFixedBeforeRederive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertPhysicalRow(EKeys::F9,  "the declared physical button");
        DoAssertPhysicalRow(EKeys::F10, "the registered physical button");

        // Re-registering a key the map already carries is an accepted no-op: the
        // association IS the key, so the caller's intent already holds.
        utils_input_button_map::Request_RegisterPhysicalButton(
            _Map, FCk_Request_InputButtonMap_RegisterPhysicalButton(EKeys::F10),
            FCk_Delegate_Request_OnCompleted(this, n"OnReRegisterCompleted"));

        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive(),
            FCk_Delegate_Request_OnCompleted(this, n"OnRederiveCompleted"));
    }

    UFUNCTION()
    private void Step_AssertUntouchedAfterRederive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertPhysicalRow(EKeys::F9,  "the declared physical button survives a re-derive");
        DoAssertPhysicalRow(EKeys::F10, "the registered physical button survives a re-derive");

        Assert_Equals_Int(_ReRegisterFires, 1,
            "the redundant registration completed exactly once");
        Assert_True(_ReRegisterSucceeded,
            "re-registering a key the map already carries reports Succeeded, not Failed");

        auto F9Holders = utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F9);
        Assert_Equals_Int(F9Holders.Num(), 1,
            "a re-derive must not mint a second button for a physical key it already carries");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_DeclaredLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F9).Num() >= 1);
    }

    UFUNCTION()
    private void Check_RegisteredLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, EKeys::F10).Num() >= 1);
    }

    // The second re-derive is what the last block is testing, and the map looks
    // the same before and after it — so the wait is on the request COMPLETING,
    // the only observable that is false until it has actually run.
    UFUNCTION()
    private void Check_RederiveCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RederiveFires >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnReRegisterCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _ReRegisterFires += 1;
        _ReRegisterSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void OnRederiveCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _RederiveFires += 1;
    }

    private void DoAssertPhysicalRow(FKey InKey, const FString& InWhat)
    {
        auto Holders = utils_input_button_map::Get_ButtonIdsForKey(_Map, InKey);

        auto FoundPhysical = false;
        auto FoundId = FCk_Input_ButtonId();

        for (auto Index = 0; Index < Holders.Num(); Index++)
        {
            if (Holders[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            FoundPhysical = true;
            FoundId = Holders[Index];
            break;
        }

        Assert_True(FoundPhysical, f"{InWhat} resolves from its own key");

        if (FoundPhysical == false)
        { return; }

        auto Associated = utils_input_button_map::TryGet_KeyForButton(_Map, FoundId);
        Assert_True(Associated == InKey,
            f"{InWhat} is associated with the key it was minted from (got {Associated.GetKeyName()})");
    }
}
