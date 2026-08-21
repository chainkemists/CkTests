// Language=angelscript

//============================================================================
// GYM CONTROL PANEL — the shared on-screen control widget
//============================================================================
//
// Gyms are driven by console commands, which means the controls are invisible: the only way to learn
// that Ck_GymUsfDither_ToggleBanding exists is to read the PlayerController. This is the widget that
// puts them on screen — an always-on panel listing each control, the key that fires it, and its live
// value.
//
// It is DECLARATIVE. A gym never draws anything and never reads a key: it returns a list of rows from
// Get_ControlRows() and acts on an index in Request_ControlActivated(). The panel owns the rendering,
// the key polling, and the ordering rules, so every gym that adopts it looks and behaves identically
// and a gym adopts it in about thirty lines. That split is the whole point — the pixel-art gym's
// bespoke panel is what this generalizes, and it is now one caller among many rather than the only one.
//
// Rows are rebuilt every frame rather than cached, because the second column is LIVE state — a toggle
// that reports its value one frame late is worse than one that reports nothing. The cost is a handful
// of struct constructions per frame on a HUD that already formats strings per frame.
//
// Reserved keys the panel itself owns, which a gym must therefore NOT bind in a row:
//   Tab — the gym cycler menu (ACkGym_MenuHUD)
//   H   — hide/show this panel
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

//----------------------------------------------------------------------------------------------------
// What a row IS, which decides how it draws and whether it takes a key.
//----------------------------------------------------------------------------------------------------
UENUM()
enum ECkGym_ControlKind
{
    // A section label. No key, no value — it groups the rows under it.
    Header,

    // Fires once and does something. No value column.
    Action,

    // Fires once and flips a two-state value, reported as ON / off.
    Toggle,

    // One of a mutually exclusive set. Exactly one is Active, and that one is highlighted.
    Choice,

    // No key at all — a readout the gym wants on screen beside its controls.
    Status
}

//----------------------------------------------------------------------------------------------------
// One row of the panel. Build these through the CkGym_Control builders below rather than by hand: the
// builders are what keep Kind, HasAltKey and the value column consistent with how the panel draws them.
//----------------------------------------------------------------------------------------------------
USTRUCT()
struct FCkGym_ControlRow
{
    UPROPERTY()
    FString Label;

    // The right-hand column. Empty draws nothing, which is what an Action wants.
    UPROPERTY()
    FString Value;

    UPROPERTY()
    FKey Key;

    // A second key that fires the same row — the numpad twin of a number key. A laptop has no numpad
    // and a desk keyboard's number row is already under the fingers; binding one and not the other
    // makes the control depend on the hardware.
    UPROPERTY()
    FKey AltKey;

    // Whether AltKey is set. Checked instead of asking the FKey, so a default-constructed key is never
    // handed to WasInputKeyJustPressed.
    UPROPERTY()
    bool HasAltKey = false;

    // Spelled out rather than derived from the FKey: the panel wants "PgDn", not "PageDown", and a
    // display-name binding that may or may not exist is not worth the risk for a two-character string.
    UPROPERTY()
    FString KeyLabel;

    UPROPERTY()
    ECkGym_ControlKind Kind = ECkGym_ControlKind::Action;

    // Choice: this is the live one. Toggle: it is on.
    UPROPERTY()
    bool Active = false;

    // Draw hot. For the state that INVALIDATES what the viewer is looking at — a disabled snap, a
    // suppressed effect, a mode the gym cannot produce a verdict in. Not for mere emphasis.
    UPROPERTY()
    bool Warn = false;

    // Disabled rows remain visible as an explanation of the unavailable action, but never dispatch.
    // This lets a gym keep stable row indices while readiness or authority changes frame to frame.
    UPROPERTY()
    bool Enabled = true;
}

//----------------------------------------------------------------------------------------------------
// Panel geometry. Native pixels throughout: a gym that renders its scene at a reduced internal
// resolution must not drag its own controls down with it.
//----------------------------------------------------------------------------------------------------
USTRUCT()
struct FCkGym_ControlPanel_Style
{
    UPROPERTY()
    float X = 24.0f;

    // Below the cycler's "Press Tab for Gym Menu" hint and any gym readout drawn at the top.
    UPROPERTY()
    float Y = 90.0f;

    UPROPERTY()
    float Width = 440.0f;

    UPROPERTY()
    float RowHeight = 22.0f;

    UPROPERTY()
    float Padding = 10.0f;

    // Where the label starts, measured from the panel's left padding — the key box lives to its left.
    UPROPERTY()
    float LabelColumn = 44.0f;

    // Where the value column starts, measured from the panel's left edge.
    UPROPERTY()
    float ValueColumn = 300.0f;
}

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

    // A readout. InWarn draws it hot — use it when the state being reported makes the gym's own
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

    // Steps through a list of more than two values — a debug view, a preset ring. It is an Action with a
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

    // A toggle whose two states both deserve a name, because "off" says nothing useful — an
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
    // Indices past the tenth get no key — they still draw, and the gym can still reach them by
    // whatever means it already had.
    FCkGym_ControlRow Numbered(int32 InIndex, FString InLabel, bool InIsActive, bool InEnabled = true)
    {
        auto Row = FCkGym_ControlRow();
        Row.Kind = ECkGym_ControlKind::Choice;
        Row.Label = InLabel;
        Row.Active = InIsActive;
        Row.Enabled = InEnabled;

        if (InIndex < 0 || InIndex > 9)
        { return Row; }

        Row.Key = Get_NumberRowKey(InIndex);
        Row.AltKey = Get_NumPadKey(InIndex);
        Row.HasAltKey = true;
        auto KeyNumber = InIndex + 1;
        Row.KeyLabel = InIndex == 9 ? "0" : f"{KeyNumber}";

        return Row;
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

//============================================================================
// PANEL RENDERING AND KEY DISPATCH
//============================================================================
//
// Free functions taking the HUD rather than methods on one, so a gym that already has a bespoke HUD
// can draw the panel without reparenting to ACkGym_ControlPanelHUD.
//============================================================================

namespace CkGym_ControlPanel
{
    const FLinearColor Colour_Background = FLinearColor(0.02f, 0.02f, 0.05f, 0.82f);
    const FLinearColor Colour_Title      = FLinearColor(0.62f, 0.78f, 1.00f, 1.0f);
    const FLinearColor Colour_Header     = FLinearColor(0.62f, 0.78f, 1.00f, 0.9f);
    const FLinearColor Colour_Row        = FLinearColor(0.72f, 0.74f, 0.80f, 1.0f);
    const FLinearColor Colour_RowActive  = FLinearColor(1.00f, 1.00f, 1.00f, 1.0f);
    const FLinearColor Colour_Highlight  = FLinearColor(0.15f, 0.25f, 0.55f, 0.9f);
    const FLinearColor Colour_On         = FLinearColor(0.40f, 0.90f, 0.50f, 1.0f);
    const FLinearColor Colour_Off        = FLinearColor(0.55f, 0.60f, 0.68f, 1.0f);
    const FLinearColor Colour_Warn       = FLinearColor(1.00f, 0.55f, 0.25f, 1.0f);
    const FLinearColor Colour_Muted      = FLinearColor(0.55f, 0.60f, 0.68f, 1.0f);

    // Returns the index of the row whose key fired this frame, or -1. Header and Status rows hold no
    // key and are skipped. The first match wins, so a gym that binds one key twice gets the earlier row
    // rather than both.
    int32 Get_PressedRow(APlayerController InPC, const TArray<FCkGym_ControlRow>&in InRows)
    {
        if (ck::Is_NOT_Valid(InPC))
        { return -1; }

        for (int32 Index = 0; Index < InRows.Num(); Index++)
        {
            auto Row = InRows[Index];

            if (Row.Kind == ECkGym_ControlKind::Header || Row.Kind == ECkGym_ControlKind::Status || Row.Enabled == false)
            { continue; }

            if (Row.KeyLabel.Len() == 0)
            { continue; }

            if (InPC.WasInputKeyJustPressed(Row.Key))
            { return Index; }

            if (Row.HasAltKey && InPC.WasInputKeyJustPressed(Row.AltKey))
            { return Index; }
        }

        return -1;
    }

    float Get_PanelHeight(const TArray<FCkGym_ControlRow>&in InRows, const FCkGym_ControlPanel_Style&in InStyle)
    {
        // Title row, then one row each.
        return (InRows.Num() + 1) * InStyle.RowHeight + InStyle.Padding * 2.0f;
    }

    void Draw(AHUD InHUD, FString InTitle, const TArray<FCkGym_ControlRow>&in InRows, const FCkGym_ControlPanel_Style&in InStyle)
    {
        if (ck::Is_NOT_Valid(InHUD) || InRows.Num() == 0)
        { return; }

        InHUD.DrawRect(Colour_Background, InStyle.X, InStyle.Y, InStyle.Width, Get_PanelHeight(InRows, InStyle));

        auto RowY = InStyle.Y + InStyle.Padding;
        auto TextX = InStyle.X + InStyle.Padding;

        InHUD.DrawText(InTitle, Colour_Title, TextX, RowY, nullptr, 1.0f, false);
        RowY += InStyle.RowHeight;

        for (int32 Index = 0; Index < InRows.Num(); Index++)
        {
            Draw_Row(InHUD, InRows[Index], InStyle, TextX, RowY);
            RowY += InStyle.RowHeight;
        }
    }

    void Draw_Row(AHUD InHUD, const FCkGym_ControlRow&in InRow, const FCkGym_ControlPanel_Style&in InStyle, float InTextX, float InRowY)
    {
        if (InRow.Kind == ECkGym_ControlKind::Header)
        {
            InHUD.DrawText(InRow.Label, Colour_Header, InTextX, InRowY, nullptr, 0.85f, false);
            return;
        }

        if (InRow.Kind == ECkGym_ControlKind::Status)
        {
            FLinearColor StatusColour = InRow.Warn ? Colour_Warn : Colour_Muted;
            auto StatusText = InRow.Value.Len() > 0 ? f"{InRow.Label}: {InRow.Value}" : InRow.Label;
            InHUD.DrawText(StatusText, StatusColour, InTextX, InRowY, nullptr, 0.85f, false);
            return;
        }

        // A Choice marks the live one by highlighting the whole row; a Toggle says ON in its value
        // column and does not, or a panel of six toggles would be a wall of highlight bars.
        const bool DrawHighlight = InRow.Enabled && InRow.Kind == ECkGym_ControlKind::Choice && InRow.Active;

        if (DrawHighlight)
        {
            InHUD.DrawRect(Colour_Highlight, InStyle.X + 4.0f, InRowY - 3.0f, InStyle.Width - 8.0f, InStyle.RowHeight);
        }

        FLinearColor LabelColour = InRow.Enabled == false
            ? Colour_Muted
            : InRow.Warn ? Colour_Warn : (DrawHighlight ? Colour_RowActive : Colour_Row);

        auto KeyText = InRow.KeyLabel.Len() > 0 ? f"[{InRow.KeyLabel}]" : "   ";
        InHUD.DrawText(KeyText, LabelColour, InTextX, InRowY, nullptr, 1.0f, false);
        InHUD.DrawText(InRow.Label, LabelColour, InTextX + InStyle.LabelColumn, InRowY, nullptr, 1.0f, false);

        const auto DisplayValue = InRow.Enabled ? InRow.Value : "disabled";
        if (DisplayValue.Len() == 0)
        { return; }

        FLinearColor ValueColour = InRow.Enabled == false
            ? Colour_Muted
            : InRow.Warn ? Colour_Warn : (InRow.Active ? Colour_On : Colour_Off);

        InHUD.DrawText(DisplayValue, ValueColour, InStyle.X + InStyle.ValueColumn, InRowY, nullptr, 1.0f, false);
    }
}
