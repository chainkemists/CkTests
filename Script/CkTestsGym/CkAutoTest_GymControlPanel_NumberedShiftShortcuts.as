// Language=angelscript

//============================================================================
// CK TESTS GYM - AUTOMATION TEST: NUMBERED CONTROL SHIFT SHORTCUTS
//============================================================================
//
// Numbered controls deliberately share their top-row digit with a second bank:
// 1..0 choose entries 0..9 and Shift+1..0 choose entries 10..19. The resolver
// owns that distinction so a disabled shifted entry cannot fall through to the
// unshifted entry with the same physical key.
//============================================================================

class UCk_AutoTest_GymControlPanel_NumberedShiftShortcuts : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        for (int32 Index = 0; Index < 20; ++Index)
        {
            Rows.Add(CkGym_Control::Numbered(Index, f"choice {Index}", false));
        }

        DoAssert_NumberedTopRowAndResolver(Rows);
        DoAssert_NumpadAndModifierBoundaries(Rows);
        DoAssert_DisabledShiftedDoesNotFallBack(Rows);
        DoAssert_InvalidIndicesAreKeyless();
        DoAssert_LegacyAndNonDispatchRows();
        DoAssert_FirstMatchingRowWins();

        FinishSuccess();
    }

    private void DoAssert_NumberedTopRowAndResolver(const TArray<FCkGym_ControlRow>&in InRows)
    {
        for (int32 Index = 0; Index < 20; ++Index)
        {
            auto Row = InRows[Index];
            auto ExpectedKey = CkGym_Control::Get_NumberRowKey(Index % 10);
            const bool Shifted = Index >= 10;
            auto ShiftName = Shifted ? "shifted" : "unshifted";

            Assert_True(Row.Key == ExpectedKey,
                f"Numbered({Index}) keeps the expected top-row digit");
            Assert_True(Row.KeyLabel == DoExpectedNumberedLabel(Index),
                f"Numbered({Index}) exposes the expected visible shortcut label");
            Assert_True(Row.ShiftRequirement == (Shifted
                ? ECkGym_ControlShift::Pressed : ECkGym_ControlShift::Released),
                f"Numbered({Index}) declares the correct Shift requirement");
            Assert_Equals_Int(CkGym_Control::Get_PressedRow(InRows, ExpectedKey, Shifted), Index,
                f"the {ShiftName} top-row digit resolves Numbered({Index})");
        }

    }

    private void DoAssert_NumpadAndModifierBoundaries(const TArray<FCkGym_ControlRow>&in InRows)
    {
        for (int32 Index = 0; Index < 10; ++Index)
        {
            auto Row = InRows[Index];
            auto NumPadKey = CkGym_Control::Get_NumPadKey(Index);
            Assert_True(Row.HasAltKey && Row.AltKey == NumPadKey,
                f"Numbered({Index}) retains its unshifted numpad twin");
            Assert_Equals_Int(CkGym_Control::Get_PressedRow(InRows, NumPadKey, false), Index,
                f"unshifted numpad resolves Numbered({Index})");
            Assert_Equals_Int(CkGym_Control::Get_PressedRow(InRows, NumPadKey, true), -1,
                f"shifted numpad never selects Numbered({Index})");
        }

        for (int32 Index = 10; Index < 20; ++Index)
        {
            Assert_False(InRows[Index].HasAltKey,
                f"shifted Numbered({Index}) has no numpad shortcut");
        }
    }

    private void DoAssert_DisabledShiftedDoesNotFallBack(TArray<FCkGym_ControlRow> InRows)
    {
        auto Rows = InRows;
        auto DisabledShifted = Rows[10];
        DisabledShifted.Enabled = false;
        Rows[10] = DisabledShifted;
        Assert_Equals_Int(CkGym_Control::Get_PressedRow(Rows, EKeys::One, true), -1,
            "a disabled Shift+1 row dispatches nothing instead of falling back to unshifted 1");
        Assert_Equals_Int(CkGym_Control::Get_PressedRow(Rows, EKeys::One, false), 0,
            "disabling Shift+1 does not disable unshifted 1");
    }

    private void DoAssert_InvalidIndicesAreKeyless()
    {
        auto Negative = CkGym_Control::Numbered(-1, "negative", false);
        auto PastLast = CkGym_Control::Numbered(20, "past last", false);
        Assert_True(Negative.KeyLabel.Len() == 0 && Negative.HasAltKey == false,
            "Numbered(-1) is keyless");
        Assert_True(PastLast.KeyLabel.Len() == 0 && PastLast.HasAltKey == false,
            "Numbered(20) is keyless");
    }

    private void DoAssert_LegacyAndNonDispatchRows()
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("section"));
        Rows.Add(CkGym_Control::Status("status"));
        Rows.Add(CkGym_Control::Numbered(20, "keyless", false));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "legacy action"));

        Assert_Equals_Int(CkGym_Control::Get_PressedRow(Rows, EKeys::P, false), 3,
            "legacy Action rows with Any Shift requirement fire unshifted");
        Assert_Equals_Int(CkGym_Control::Get_PressedRow(Rows, EKeys::P, true), 3,
            "legacy Action rows with Any Shift requirement fire shifted");
        Assert_Equals_Int(CkGym_Control::Get_PressedRow(Rows, EKeys::One, false), -1,
            "header, status, and keyless rows never dispatch");
    }

    private void DoAssert_FirstMatchingRowWins()
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "first"));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "second"));
        Assert_Equals_Int(CkGym_Control::Get_PressedRow(Rows, EKeys::P, false), 0,
            "the first enabled row matching a key and modifier wins");
    }

    private FString DoExpectedNumberedLabel(int32 InIndex)
    {
        if (InIndex == 0) { return "1"; }
        if (InIndex == 1) { return "2"; }
        if (InIndex == 2) { return "3"; }
        if (InIndex == 3) { return "4"; }
        if (InIndex == 4) { return "5"; }
        if (InIndex == 5) { return "6"; }
        if (InIndex == 6) { return "7"; }
        if (InIndex == 7) { return "8"; }
        if (InIndex == 8) { return "9"; }
        if (InIndex == 9) { return "0"; }
        if (InIndex == 10) { return "!"; }
        if (InIndex == 11) { return "@"; }
        if (InIndex == 12) { return "#"; }
        if (InIndex == 13) { return "$"; }
        if (InIndex == 14) { return "%"; }
        if (InIndex == 15) { return "^"; }
        if (InIndex == 16) { return "&"; }
        if (InIndex == 17) { return "*"; }
        if (InIndex == 18) { return "("; }
        return ")";
    }
}
