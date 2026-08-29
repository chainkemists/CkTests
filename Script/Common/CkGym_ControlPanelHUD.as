// Language=angelscript

//============================================================================
// GYM CONTROL PANEL HUD - the default gym HUD
//============================================================================
//
// Draws the control panel for whichever gym is running: it asks the PlayerController for its rows
// and dispatches by index. It also ARMS the gym switchboard's Tab global action (gym worlds only,
// by HUDClass construction) and draws the closed-state Tab hint - the switchboard itself is the
// C++ UCkGym_Switchboard_Subsystem. A gym that declares no rows gets just the hint - the panel is
// opt-in per gym, not per HUD.
//
// This is ACk_Gym_Base_GameMode's default HUDClass, so adopting the panel never involves touching a
// GameMode: a gym overrides Get_ControlRows() on its PlayerController and the panel appears.
//
// Input arrives through a CkInput layer at CkGym_InputStack::Priority_ControlPanel, NOT by polling:
// the layer's capture set is diff-synced to the enabled, keyed rows each draw, and the switchboard's
// catch-all Consume above therefore silences the panel structurally while a menu is open. Rows keep
// firing while the panel is hidden with H - hiding is a draw concern, the captures stay.
//============================================================================

class ACkGym_ControlPanelHUD : AHUD
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

    private FCk_Handle _PanelLayerOwner;
    private FCk_Handle_InputLayer _PanelLayer;
    private TArray<FKey> _SyncedKeys;

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        // The layer must not outlive the HUD: stale captures would keep consuming row keys on the
        // shared source, and the next level's panel would find its priority slot taken.
        if (ck::IsValid(_PanelLayerOwner))
        {
            utils_entity_lifetime::Request_DestroyEntity(_PanelLayerOwner);
        }
    }

    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Mirrors the base's startup suppression. Without it the panel flashes over the launcher level
        // during an auto-travel to the startup gym.
        if (UCk_Utils_GymRegistry_UE::Get_SuppressHUDDuringStartup())
        { return; }

        auto PC = Cast<ACk_Gym_Base_PlayerController>(GetOwningPlayerController());

        if (ck::Is_NOT_Valid(PC))
        { return; }

        auto Switchboard = UCkGym_Switchboard_Subsystem::Get(PC);
        if (ck::IsValid(Switchboard))
        {
            // Idempotent, retried until the input source exists.
            Switchboard.Request_ArmTabOpen();

            // The switchboard draws over the center; skip the panel's own draw while it is open.
            // Key dispatch needs no such gate - the menu's catch-all masks the panel's layer.
            if (Switchboard.Get_IsOpen())
            { return; }
        }

        DrawText("[Tab] gym switchboard", CkGym_ControlPanel::Colour_Muted,
            float(SizeX) - 200.0f, 20.0f, nullptr, 0.85f, false);

        auto Rows = PC.Get_ControlRows();

        DoEnsurePanelLayer(PC);
        DoSyncCaptures(Rows);

        if (Rows.Num() == 0)
        { return; }

        auto Style = Get_ControlPanelStyle();

        if (_PanelHidden)
        {
            DrawText("[H] gym controls", CkGym_ControlPanel::Colour_Muted,
                Style.X, Style.Y, nullptr, 0.85f, false);
            return;
        }

        CkGym_ControlPanel::Draw(this, PC.Get_ControlPanelTitle(), Rows, Style);
    }

    //------------------------------------------------------------------------
    // Input layer
    //------------------------------------------------------------------------

    // Idempotent, retried from DrawHUD: the source is invalid until the local player has a
    // controller.
    private void DoEnsurePanelLayer(APlayerController InPC)
    {
        if (ck::IsValid(_PanelLayer))
        { return; }

        auto SourceSubsystem = UCk_InputSource_Subsystem::Get(InPC);
        if (ck::Is_NOT_Valid(SourceSubsystem))
        { return; }

        auto Source = SourceSubsystem.Get_InputSource();
        if (ck::Is_NOT_Valid(Source))
        { return; }

        if (ck::IsValid(utils_input_layer::TryGet_LayerWithPriority(Source, CkGym_InputStack::Priority_ControlPanel)))
        { return; }

        _PanelLayerOwner = utils_entity_lifetime::Request_CreateEntity_TransientOwner();
        _PanelLayer = utils_input_layer::Create(_PanelLayerOwner,
            FCk_Fragment_InputLayer_ParamsData(Source, CkGym_InputStack::Priority_ControlPanel));

        if (ck::Is_NOT_Valid(_PanelLayer))
        { return; }

        utils_input_layer::BindTo_OnCaptureTriggered(_PanelLayer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnPanelCaptured"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    // Diff-syncs the capture set to H + every enabled, keyed row (and its alt key). Rows change
    // rarely (per gym, per scenario state), so the steady state enqueues nothing.
    private void DoSyncCaptures(const TArray<FCkGym_ControlRow>&in InRows)
    {
        if (ck::Is_NOT_Valid(_PanelLayer))
        { return; }

        TArray<FKey> Desired;
        Desired.Add(EKeys::H);

        for (auto Row : InRows)
        {
            if (Row.Kind == ECkGym_ControlKind::Header || Row.Kind == ECkGym_ControlKind::Status || Row.Enabled == false)
            { continue; }

            if (Row.KeyLabel.Len() == 0)
            { continue; }

            Desired.AddUnique(Row.Key);

            if (Row.HasAltKey)
            { Desired.AddUnique(Row.AltKey); }
        }

        for (auto Key : Desired)
        {
            if (_SyncedKeys.Contains(Key) == false)
            {
                utils_input_layer::Request_AddCapture(_PanelLayer, FCk_Request_InputLayer_AddCapture(
                    utils_input_layer::Make_KeyCapture(Key, ECk_InputLayer_CaptureBehavior::Consume)));
            }
        }

        for (auto Key : _SyncedKeys)
        {
            if (Desired.Contains(Key) == false)
            {
                utils_input_layer::Request_RemoveCapture(_PanelLayer, FCk_Request_InputLayer_RemoveCapture(
                    ECk_InputLayer_CaptureMatch::Key, Key));
            }
        }

        _SyncedKeys = Desired;
    }

    UFUNCTION()
    private void OnPanelCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        if (InEvent.Get_EventType() != ECk_InputSource_EventType::Pressed)
        { return; }

        auto Key = InEvent.Get_Key();

        if (Key == EKeys::H)
        {
            _PanelHidden = !_PanelHidden;
            return;
        }

        auto PC = Cast<ACk_Gym_Base_PlayerController>(GetOwningPlayerController());
        if (ck::Is_NOT_Valid(PC))
        { return; }

        // Resolve by key at DELIVERY time against the live rows - first enabled match wins, same
        // contract the polled Get_PressedRow had.
        auto Rows = PC.Get_ControlRows();
        for (int32 Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];

            if (Row.Kind == ECkGym_ControlKind::Header || Row.Kind == ECkGym_ControlKind::Status || Row.Enabled == false)
            { continue; }

            if (Row.KeyLabel.Len() == 0)
            { continue; }

            if (Row.Key == Key || (Row.HasAltKey && Row.AltKey == Key))
            {
                PC.Request_ControlActivated(Index);
                return;
            }
        }
    }
}
