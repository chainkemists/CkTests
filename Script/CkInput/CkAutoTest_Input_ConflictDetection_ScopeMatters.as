// Language=angelscript

//============================================================================
// CK INPUT — AUTOMATION TEST: CONFLICT SCOPE FILTERS BY DISPLAY CATEGORY
//============================================================================
//
// Get_HasKeyConflicts answers "who else already holds this key", and its
// ECk_KeyConflictScope argument is the only thing separating a settings page
// that blocks every collision from one that blocks only same-category ones.
// This pins that difference against the two authored categories.
//
// Asking on behalf of CkTests_Jump (category Movement):
//   key C — held by CkTests_Crouch, also Movement  -> conflict under BOTH scopes
//   key E — held by CkTests_Interact, Interaction  -> conflict under All only
//
// The scope filter compares the holder's DisplayCategory against the category
// of the FIRST excluded mapping name (CkKeyBinding_Utils.cpp:407-418, :437-439),
// which is why the exclude list is the source mapping and why authoring the
// four actions across two categories is load-bearing rather than cosmetic.
//
// Assertions name the mappings this test owns instead of counting conflicts:
// every autotest shares one PIE session and one key profile, so another
// registration's rows can legitimately appear alongside ours. For the same
// reason the SameCategory/E case asserts the ABSENCE of CkTests_Interact
// rather than a false return value — a foreign Movement mapping parked on E
// would make the bool true without saying anything about the filter.
//
// This test performs no remap, so the profile it leaves behind is the profile
// it found; the opening default assertions are what prove it read a populated
// profile rather than an empty one.
//============================================================================

class UCk_AutoTest_Input_ConflictDetection_ScopeMatters : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController — the key profile lives on the local player");
            return;
        }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(PlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        {
            FinishFailure("Enhanced Input user settings unavailable on the local player");
            return;
        }

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        auto JumpKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Jump", EPlayerMappableKeySlot::First);
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Crouch", EPlayerMappableKeySlot::First);
        auto InteractKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, n"CkTests_Interact", EPlayerMappableKeySlot::First);

        Assert_True(JumpKey == EKeys::SpaceBar,
            f"CkTests_Jump starts on its authored default SpaceBar (got {JumpKey.GetKeyName()})");
        Assert_True(CrouchKey == EKeys::C,
            f"CkTests_Crouch starts on its authored default C (got {CrouchKey.GetKeyName()})");
        Assert_True(InteractKey == EKeys::E,
            f"CkTests_Interact starts on its authored default E (got {InteractKey.GetKeyName()})");

        TArray<FName> ExcludeJump;
        ExcludeJump.Add(n"CkTests_Jump");

        // --- Same category (Movement vs Movement): a conflict under either scope ---

        TArray<FCk_KeyBinding_ConflictInfo> ConflictsOnC_All;
        auto HasConflictsOnC_All = utils_key_binding::Get_HasKeyConflicts(
            PlayerController, EKeys::C, ExcludeJump, ConflictsOnC_All, ECk_KeyConflictScope::All);

        auto ConflictsOnC_AllDump = DoDescribeConflicts(ConflictsOnC_All);
        Assert_True(HasConflictsOnC_All,
            "giving CkTests_Jump the key C reports a conflict under scope All");
        Assert_True(DoConflictsContain(ConflictsOnC_All, n"CkTests_Crouch"),
            f"scope All names CkTests_Crouch as the holder of C — conflicts:{ConflictsOnC_AllDump}");
        Assert_True(DoConflictKeyMatches(ConflictsOnC_All, n"CkTests_Crouch", EKeys::C),
            "the reported CkTests_Crouch conflict carries C as its current key");

        TArray<FCk_KeyBinding_ConflictInfo> ConflictsOnC_SameCategory;
        auto HasConflictsOnC_SameCategory = utils_key_binding::Get_HasKeyConflicts(
            PlayerController, EKeys::C, ExcludeJump, ConflictsOnC_SameCategory, ECk_KeyConflictScope::SameCategory);

        auto ConflictsOnC_SameCategoryDump = DoDescribeConflicts(ConflictsOnC_SameCategory);
        Assert_True(HasConflictsOnC_SameCategory,
            "giving CkTests_Jump the key C reports a conflict under scope SameCategory — both are Movement");
        Assert_True(DoConflictsContain(ConflictsOnC_SameCategory, n"CkTests_Crouch"),
            f"scope SameCategory names CkTests_Crouch as the holder of C — conflicts:{ConflictsOnC_SameCategoryDump}");

        // --- Different category (Movement vs Interaction): a conflict under All only ---

        TArray<FCk_KeyBinding_ConflictInfo> ConflictsOnE_All;
        auto HasConflictsOnE_All = utils_key_binding::Get_HasKeyConflicts(
            PlayerController, EKeys::E, ExcludeJump, ConflictsOnE_All, ECk_KeyConflictScope::All);

        auto ConflictsOnE_AllDump = DoDescribeConflicts(ConflictsOnE_All);
        Assert_True(HasConflictsOnE_All,
            "giving CkTests_Jump the key E reports a conflict under scope All");
        Assert_True(DoConflictsContain(ConflictsOnE_All, n"CkTests_Interact"),
            f"scope All names CkTests_Interact as the holder of E — conflicts:{ConflictsOnE_AllDump}");

        // The return value is deliberately unread here: it is merely "the list is
        // non-empty", which a foreign Movement mapping parked on E would make true
        // without touching the filter behaviour under test. The list itself answers.
        TArray<FCk_KeyBinding_ConflictInfo> ConflictsOnE_SameCategory;
        utils_key_binding::Get_HasKeyConflicts(
            PlayerController, EKeys::E, ExcludeJump, ConflictsOnE_SameCategory, ECk_KeyConflictScope::SameCategory);

        auto ConflictsOnE_SameCategoryDump = DoDescribeConflicts(ConflictsOnE_SameCategory);
        Assert_False(DoConflictsContain(ConflictsOnE_SameCategory, n"CkTests_Interact"),
            f"scope SameCategory filters out CkTests_Interact — Interaction does not match Jump's Movement — conflicts:{ConflictsOnE_SameCategoryDump}");

        FinishSuccess();
    }

    private bool DoConflictsContain(const TArray<FCk_KeyBinding_ConflictInfo>& InConflicts, FName InMappingName) const
    {
        for (auto Index = 0; Index < InConflicts.Num(); Index++)
        {
            if (InConflicts[Index].Get_MappingName() == InMappingName)
            { return true; }
        }

        return false;
    }

    private bool DoConflictKeyMatches(const TArray<FCk_KeyBinding_ConflictInfo>& InConflicts, FName InMappingName, FKey InKey) const
    {
        for (auto Index = 0; Index < InConflicts.Num(); Index++)
        {
            if (InConflicts[Index].Get_MappingName() == InMappingName)
            { return InConflicts[Index].Get_CurrentKey() == InKey; }
        }

        return false;
    }

    private FString DoDescribeConflicts(const TArray<FCk_KeyBinding_ConflictInfo>& InConflicts) const
    {
        auto Description = FString();
        for (auto Index = 0; Index < InConflicts.Num(); Index++)
        {
            Description += f" [{InConflicts[Index].Get_MappingName()}|{InConflicts[Index].Get_CurrentKey().GetKeyName()}]";
        }

        return Description;
    }
}
