// Language=angelscript

//============================================================================
// GYM CONTROL PANEL HUD - the default gym HUD
//============================================================================
//
// Subclasses the cycler HUD rather than replacing it, so Tab still opens the gym menu everywhere. On
// top of that it draws the control panel for whichever gym is running: it asks the PlayerController
// for its rows, polls their keys, and dispatches by index. A gym that declares no rows gets exactly
// the cycler HUD it had before - the panel is opt-in per gym, not per HUD.
//
// This is ACk_Gym_Base_GameMode's default HUDClass, so adopting the panel never involves touching a
// GameMode: a gym overrides Get_ControlRows() on its PlayerController and the panel appears.
//
// H hides the panel WITHOUT disabling it. The reason to hide it is to see the image underneath, which
// is exactly when the controls still need to work - so keys keep firing while it is hidden, and a
// one-line hint stays on screen saying how to bring it back.
//============================================================================

class ACkGym_ControlPanelHUD : ACkGym_MenuHUD
{
    // Per-gym geometry. Editable on the HUD asset, and overridable in code through
    // Get_ControlPanelStyle() below - a gym whose own readout already occupies the top-left pushes the
    // panel down that way rather than the panel guessing at what is under it.
    UPROPERTY()
    FCkGym_ControlPanel_Style ControlPanelStyle;

    FCkGym_ControlPanel_Style Get_ControlPanelStyle()
    {
        return ControlPanelStyle;
    }

    private bool _PanelHidden = false;

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Mirrors the base's startup suppression. Without it the panel flashes over the launcher level
        // during an auto-travel to the startup gym.
        auto CyclerSubsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::IsValid(CyclerSubsystem) && CyclerSubsystem.SuppressHUDDuringStartup)
        { return; }

        Super::DrawHUD(SizeX, SizeY);

        // The cycler menu owns the keyboard while it is open, and it draws over this area anyway. Taking
        // keys here would fire gym controls behind it while a search term is being typed.
        if (bMenuVisible)
        { return; }

        auto PC = Cast<ACk_Gym_Base_PlayerController>(GetOwningPlayerController());

        if (ck::Is_NOT_Valid(PC))
        { return; }

        auto Rows = PC.Get_ControlRows();

        if (Rows.Num() == 0)
        { return; }

        if (PC.WasInputKeyJustPressed(EKeys::H))
        { _PanelHidden = !_PanelHidden; }

        auto Pressed = CkGym_ControlPanel::Get_PressedRow(PC, Rows);

        if (Pressed >= 0)
        {
            PC.Request_ControlActivated(Pressed);

            // Re-read: a toggle that still reports its old value on the frame it was pressed reads as a
            // control that did nothing.
            Rows = PC.Get_ControlRows();
        }

        auto Style = Get_ControlPanelStyle();

        if (_PanelHidden)
        {
            DrawText("[H] gym controls", CkGym_ControlPanel::Colour_Muted,
                Style.X, Style.Y, nullptr, 0.85f, false);
            return;
        }

        CkGym_ControlPanel::Draw(this, PC.Get_ControlPanelTitle(), Rows, Style);
    }
}
