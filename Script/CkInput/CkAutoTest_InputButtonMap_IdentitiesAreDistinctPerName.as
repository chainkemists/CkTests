// Language=angelscript

//============================================================================
// CK INPUT BUTTON MAP - AUTOMATION TEST: ONE BUTTON PER MAPPING NAME, NO MERGES
//============================================================================
//
// Identity is (tier, name), so four distinct mapping names must produce four
// distinct buttons in the map. The failure this guards against is a map keyed on
// anything coarser - the key, the display category, the input action - which
// would silently merge two mappings into one button and leave every consumer of
// the merged button ambiguous. The mirror failure is a map that mints a fresh
// row per derivation pass, which shows up here as a duplicate.
//
// Both are read off the MAP rather than off constructed literals, because
// comparing two hand-built identities only proves that == works. Occurrences are
// counted per authored name - those four rows are this test's own, unlike
// Get_AllButtons as a whole, which in the shared PIE world also carries every
// context other suites registered.
//
// The per-name key assertion is not redundant with the distinctness one: a merge
// that kept four rows but pointed two of them at one key would satisfy
// distinctness and still be wrong.
//============================================================================

class UCk_AutoTest_InputButtonMap_IdentitiesAreDistinctPerName : UCk_AutoTest_Base
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

        Add_Step_WaitUntil("all four authored names have derived",            n"Check_AllFourDerived");
        Add_Step(          "assert four names produced four distinct buttons", n"Step_AssertDistinct");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertDistinct(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FName> Authored;
        Authored.Add(n"CkTests_Jump");
        Authored.Add(n"CkTests_Crouch");
        Authored.Add(n"CkTests_Interact");
        Authored.Add(n"CkTests_Flashlight");

        TArray<FKey> Expected;
        Expected.Add(EKeys::SpaceBar);
        Expected.Add(EKeys::C);
        Expected.Add(EKeys::E);
        Expected.Add(EKeys::F);

        auto Buttons = utils_input_button_map::Get_AllButtons(_Map);
        auto NamesFound = 0;

        for (auto Index = 0; Index < Authored.Num(); Index++)
        {
            auto MappingName = Authored[Index];
            auto Occurrences = 0;

            for (auto ButtonIndex = 0; ButtonIndex < Buttons.Num(); ButtonIndex++)
            {
                if (Buttons[ButtonIndex].Get_Tier() != ECk_Input_ButtonTier::Mapped)
                { continue; }

                if (Buttons[ButtonIndex].Get_Name() == MappingName)
                { Occurrences++; }
            }

            Assert_Equals_Int(Occurrences, 1,
                f"the map holds exactly one Mapped button for {MappingName}");

            if (Occurrences == 1)
            { NamesFound++; }

            auto ExpectedKey = Expected[Index];
            auto Associated = utils_input_button_map::TryGet_KeyForButton(
                _Map, FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, MappingName));

            Assert_True(Associated == ExpectedKey,
                f"{MappingName} resolves to its own authored key, not a neighbour's (got {Associated.GetKeyName()})");
        }

        Assert_Equals_Int(NamesFound, 4,
            "four authored mapping names produced four separate buttons");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_AllFourDerived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoHasMappedButton(n"CkTests_Jump") &&
                DoHasMappedButton(n"CkTests_Crouch") &&
                DoHasMappedButton(n"CkTests_Interact") &&
                DoHasMappedButton(n"CkTests_Flashlight"));
    }

    //------------------------------------------------------------------------

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
