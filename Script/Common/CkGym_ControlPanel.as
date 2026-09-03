// Language=angelscript

//============================================================================
// GYM CONTROL PANEL - the shared on-screen control widget
//============================================================================
//
// Gyms are driven by console commands, which means the controls are invisible: the only way to learn
// that Ck_GymUsfDither_ToggleBanding exists is to read the PlayerController. This is the widget that
// puts them on screen - an always-on panel listing each control, the key that fires it, and its live
// value.
//
// It is DECLARATIVE. A gym never draws anything and never reads a key: it returns a list of rows from
// Get_ControlRows() and acts on an index in Request_ControlActivated(). The panel owns the rendering,
// the key captures, and the ordering rules, so every gym that adopts it looks and behaves identically
// and a gym adopts it in about thirty lines.
//
// The data shapes (FCkGym_ControlRow, ECkGym_ControlKind, FCkGym_ControlPanel_Style) live in C++
// (CkGym_ControlPanelTypes.h) because rendering is a Slate widget owned by
// UCkGym_Switchboard_Subsystem - ACkGym_ControlPanelHUD pushes the rows across each frame and owns
// the input-layer dispatch. This namespace keeps the row BUILDERS: they are what keep Kind,
// HasAltKey and the value column consistent with how the panel draws them.
//
// Rows are rebuilt every frame rather than cached, because the second column is LIVE state - a toggle
// that reports its value one frame late is worse than one that reports nothing. The Slate side diffs
// and re-renders only on change.
//
// Reserved keys the panel itself owns, which a gym must therefore NOT bind in a row:
//   Tab - the gym switchboard (UCkGym_Switchboard_Subsystem)
//   H   - hide/show this panel
//   LeftShift/RightShift - modifier observation (passed through to movement)
//
// Adopting it, in full:
//
//   TArray<FCkGym_ControlRow> Get_ControlRows() override
//   {
//       auto Rows = TArray<FCkGym_ControlRow>();
//       Rows.Add(CkGym_Control::Toggle(EKeys::B, "B", "Banding", _Banding));
//       Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Restart"));
//       return Rows;
//   }
//
//   void Request_ControlActivated(int32 InRowIndex) override
//   {
//       if (InRowIndex == 0) { Request_ToggleBanding(); }
//       if (InRowIndex == 1) { Request_Restart(); }
//   }
//
//============================================================================

//============================================================================
// ROW BUILDERS
//============================================================================

namespace CkGym_Control
{
    FCkGym_ControlRow Header(FString InLabel)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Header;
        Row.Label = InLabel;
        return Row;
    }

    // A readout. InWarn draws it hot - use it when the state being reported makes the gym's own
    // verdicts invalid, so the reader is told BEFORE they judge the image rather than after.
    FCkGym_ControlRow Status(FString InLabel, FString InValue = "", bool InWarn = false)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Status;
        Row.Label = InLabel;
        Row.Value = InValue;
        Row.Warn = InWarn;
        return Row;
    }

    FCkGym_ControlRow Action(FKey InKey, FString InKeyLabel, FString InLabel, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Action;
        Row.Key = InKey;
        Row.KeyLabel = InKeyLabel;
        Row.Label = InLabel;
        Row.Enabled = InEnabled;
        return Row;
    }

    // Steps through a list of more than two values - a debug view, a preset ring. It is an Action with a
    // value column, because the thing a viewer needs is not "this key cycles something" but WHICH of the
    // five views they are currently looking at.
    FCkGym_ControlRow Cycle(FKey InKey, FString InKeyLabel, FString InLabel, FString InCurrentValue, bool InWarn = false, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Action;
        Row.Key = InKey;
        Row.KeyLabel = InKeyLabel;
        Row.Label = InLabel;
        Row.Value = InCurrentValue;
        Row.Warn = InWarn;
        Row.Enabled = InEnabled;
        return Row;
    }

    FCkGym_ControlRow Toggle(FKey InKey, FString InKeyLabel, FString InLabel, bool InIsOn, bool InWarnWhenOff = false, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Toggle;
        Row.Key = InKey;
        Row.KeyLabel = InKeyLabel;
        Row.Label = InLabel;
        Row.Active = InIsOn;
        Row.Value = InIsOn ? "ON" : "off";
        Row.Warn = InWarnWhenOff && InIsOn == false;
        Row.Enabled = InEnabled;
        return Row;
    }

    // A toggle whose two states both deserve a name, because "off" says nothing useful - an
    // orthographic/perspective flip, a nearest/box filter, a walk/key selection mode.
    FCkGym_ControlRow ToggleNamed(FKey InKey, FString InKeyLabel, FString InLabel, bool InIsOn, FString InOnText, FString InOffText, bool InWarnWhenOff = false, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Toggle;
        Row.Key = InKey;
        Row.KeyLabel = InKeyLabel;
        Row.Label = InLabel;
        Row.Active = InIsOn;
        Row.Value = InIsOn ? InOnText : InOffText;
        Row.Warn = InWarnWhenOff && InIsOn == false;
        Row.Enabled = InEnabled;
        return Row;
    }

    FCkGym_ControlRow Choice(FKey InKey, FString InKeyLabel, FString InLabel, bool InIsActive, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Choice;
        Row.Key = InKey;
        Row.KeyLabel = InKeyLabel;
        Row.Label = InLabel;
        Row.Active = InIsActive;
        Row.Enabled = InEnabled;
        return Row;
    }

    // The nth entry of a keyed list: 1-9 pick the first nine and 0 picks the tenth, which is the
    // ordinary way a ten-item list is keyed. Both the number row and the numpad fire it.
    // The next ten use Shift+1 through Shift+0 on the number row. Shift+numpad is not bound:
    // some keyboards turn those combinations into navigation keys.
    FCkGym_ControlRow Numbered(int32 InIndex, FString InLabel, bool InIsActive, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Choice;
        Row.Label = InLabel;
        Row.Active = InIsActive;
        Row.Enabled = InEnabled;

        if (InIndex < 0 || InIndex > 19)
        { return Row; }

        const bool Shifted = InIndex >= 10;
        const int32 DigitIndex = InIndex % 10;
        Row.Key = Get_NumberRowKey(DigitIndex);
        Row.ShiftRequirement = Shifted ? ECkGym_ControlShift::Pressed : ECkGym_ControlShift::Released;
        Row.HasAltKey = Shifted == false;
        if (Row.HasAltKey)
        { Row.AltKey = Get_NumPadKey(DigitIndex); }
        const int32 KeyNumber = (DigitIndex + 1) % 10;
        Row.KeyLabel = Shifted
            ? Get_ShiftedNumberLabel(DigitIndex)
            : f"{KeyNumber}";

        return Row;
    }

    FString Get_ShiftedNumberLabel(int32 InIndex)
    {
        if (InIndex == 0) { return "!"; }
        if (InIndex == 1) { return "@"; }
        if (InIndex == 2) { return "#"; }
        if (InIndex == 3) { return "$"; }
        if (InIndex == 4) { return "%"; }
        if (InIndex == 5) { return "^"; }
        if (InIndex == 6) { return "&"; }
        if (InIndex == 7) { return "*"; }
        if (InIndex == 8) { return "("; }
        return ")";
    }

    int32 Get_PressedRow(const TArray<FCkGym_ControlRow>&in InRows, FKey InKey, bool InShiftDown)
    {
        for (int32 Index = 0; Index < InRows.Num(); ++Index)
        {
            const auto Row = InRows[Index];
            if (Row.Kind == ECkGym_ControlKind::Header || Row.Kind == ECkGym_ControlKind::Status
                || Row.Enabled == false || Row.KeyLabel.Len() == 0)
            { continue; }
            if (Row.ShiftRequirement == ECkGym_ControlShift::Pressed && InShiftDown == false)
            { continue; }
            if (Row.ShiftRequirement == ECkGym_ControlShift::Released && InShiftDown)
            { continue; }
            if (Row.Key == InKey || (Row.HasAltKey && Row.AltKey == InKey))
            { return Index; }
        }
        return -1;
    }

    FKey Get_NumberRowKey(int32 InIndex)
    {
        if (InIndex == 0) { return EKeys::One; }
        if (InIndex == 1) { return EKeys::Two; }
        if (InIndex == 2) { return EKeys::Three; }
        if (InIndex == 3) { return EKeys::Four; }
        if (InIndex == 4) { return EKeys::Five; }
        if (InIndex == 5) { return EKeys::Six; }
        if (InIndex == 6) { return EKeys::Seven; }
        if (InIndex == 7) { return EKeys::Eight; }
        if (InIndex == 8) { return EKeys::Nine; }
        return EKeys::Zero;
    }

    FKey Get_NumPadKey(int32 InIndex)
    {
        if (InIndex == 0) { return EKeys::NumPadOne; }
        if (InIndex == 1) { return EKeys::NumPadTwo; }
        if (InIndex == 2) { return EKeys::NumPadThree; }
        if (InIndex == 3) { return EKeys::NumPadFour; }
        if (InIndex == 4) { return EKeys::NumPadFive; }
        if (InIndex == 5) { return EKeys::NumPadSix; }
        if (InIndex == 6) { return EKeys::NumPadSeven; }
        if (InIndex == 7) { return EKeys::NumPadEight; }
        if (InIndex == 8) { return EKeys::NumPadNine; }
        return EKeys::NumPadZero;
    }
}
