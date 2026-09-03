// Language=angelscript

//============================================================================
// GYM CONTROL PANEL HUD - the default gym HUD
//============================================================================
//
// Drives the control panel for whichever gym is running: it asks the PlayerController for its
// rows, dispatches by index off its input layer, and pushes the row state to the Slate panel that
// UCkGym_Switchboard_Subsystem renders (CkStyle language, same as the switchboard). It also ARMS
// the switchboard's Tab global action (gym worlds only, by HUDClass construction). A gym that
// declares no rows gets just the Tab hint - the panel is opt-in per gym, not per HUD.
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
    private bool _LeftShiftDown = false;
    private bool _RightShiftDown = false;

    private FCk_Handle _PanelLayerOwner;
    private FCk_Handle_InputLayer _PanelLayer;
    private TArray<FKey> _SyncedKeys;
    private TArray<FKey> _ReportedReservedKeys;

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

    // No Canvas drawing left: this is the per-frame DRIVER. It arms the switchboard, keeps the
    // panel's input layer in sync, and pushes the row state across to the Slate panel (which
    // re-renders only on change). Suppression and the switchboard-open case still push - with an
    // explicit hide - so the widget can never linger showing a stale gym's rows.
    UFUNCTION(BlueprintOverride)
    void DrawHUD(int32 SizeX, int32 SizeY)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PC = Cast<ACk_Gym_Base_PlayerController>(GetOwningPlayerController());

        if (ck::Is_NOT_Valid(PC))
        { return; }

        // Reconcile after focus/menu gaps, where a higher input layer may have consumed Shift.
        _LeftShiftDown = PC.IsInputKeyDown(EKeys::LeftShift);
        _RightShiftDown = PC.IsInputKeyDown(EKeys::RightShift);

        auto Suppressed = UCk_Utils_GymRegistry_UE::Get_SuppressHUDDuringStartup();
        auto Rows = Suppressed ? TArray<FCkGym_ControlRow>() : PC.Get_ControlRows();

        auto Switchboard = UCkGym_Switchboard_Subsystem::Get(PC);
        if (ck::IsValid(Switchboard))
        {
            // Idempotent, retried until the input source exists.
            Switchboard.Request_ArmTabOpen();

            auto Style = Get_ControlPanelStyle();
            Switchboard.Request_SetControlPanel(PC.Get_ControlPanelTitle(), Rows,
                FVector2D(Style.X, Style.Y), _PanelHidden, Suppressed);
        }

        if (Suppressed)
        { return; }

        DoEnsurePanelLayer(PC);
        DoSyncCaptures(Rows);
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

    // Keys a panel row must NEVER capture: a capture CONSUMES, so a row on a movement key would
    // steal the pawn's input (the old polling panel merely observed, which is how such rows crept
    // in). Tab/H and Shift modifier observation are the framework's own.
    private bool DoIsReservedRowKey(FKey InKey)
    {
        return InKey == EKeys::W || InKey == EKeys::A || InKey == EKeys::S || InKey == EKeys::D ||
               InKey == EKeys::E || InKey == EKeys::Q || InKey == EKeys::C || InKey == EKeys::SpaceBar ||
               InKey == EKeys::H || InKey == EKeys::Tab ||
               InKey == EKeys::LeftShift || InKey == EKeys::RightShift;
    }

    // Diff-syncs H, pass-through Shift observation, and every enabled keyed row (and its alt key). Rows change
    // rarely (per gym, per scenario state), so the steady state enqueues nothing. A row binding a
    // reserved key is refused LOUDLY and never captured - the row draws but cannot fire, so the
    // authoring mistake is visible in the panel and the log instead of silently freezing the pawn.
    private void DoSyncCaptures(const TArray<FCkGym_ControlRow>&in InRows)
    {
        if (ck::Is_NOT_Valid(_PanelLayer))
        { return; }

        TArray<FKey> Desired;
        Desired.Add(EKeys::H);
        Desired.Add(EKeys::LeftShift);
        Desired.Add(EKeys::RightShift);

        for (auto Row : InRows)
        {
            if (Row.Kind == ECkGym_ControlKind::Header || Row.Kind == ECkGym_ControlKind::Status || Row.Enabled == false)
            { continue; }

            if (Row.KeyLabel.Len() == 0)
            { continue; }

            if (DoIsReservedRowKey(Row.Key))
            {
                if (_ReportedReservedKeys.Contains(Row.Key) == false)
                {
                    _ReportedReservedKeys.Add(Row.Key);
                    ck::Error(f"[GymControlPanel] row '{Row.Label}' binds RESERVED key '{Row.KeyLabel}' (pawn/menu-owned) - the row will not fire; re-key it");
                }
                continue;
            }

            Desired.AddUnique(Row.Key);

            if (Row.HasAltKey && DoIsReservedRowKey(Row.AltKey) == false)
            { Desired.AddUnique(Row.AltKey); }
        }

        for (auto Key : Desired)
        {
            if (_SyncedKeys.Contains(Key) == false)
            {
                const auto Behavior = Key == EKeys::LeftShift || Key == EKeys::RightShift
                    ? ECk_InputLayer_CaptureBehavior::PassThrough : ECk_InputLayer_CaptureBehavior::Consume;
                utils_input_layer::Request_AddCapture(_PanelLayer, FCk_Request_InputLayer_AddCapture(
                    utils_input_layer::Make_KeyCapture(Key, Behavior)));
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

    // A HUD hosting its own text-input surface (VfxExamples' cloned search menu) overrides this to
    // park the panel while that surface owns the keyboard - otherwise typing a letter the panel
    // has a row on would both filter AND dispatch. Dies when such menus become input layers.
    bool Get_PanelKeysSuspended()
    {
        return false;
    }

    UFUNCTION()
    private void OnPanelCaptured(FCk_Handle_InputLayer InLayer, FCk_InputSource_RawEvent InEvent, FCk_InputLayer_Capture InCapture)
    {
        auto Key = InEvent.Get_Key();
        // Preserve Shift/number/release ordering inside a routed event batch, even when
        // the physical modifier is already released by the time its number is delivered.
        if (Key == EKeys::LeftShift || Key == EKeys::RightShift)
        {
            if (InEvent.Get_EventType() == ECk_InputSource_EventType::Pressed
                || InEvent.Get_EventType() == ECk_InputSource_EventType::Released)
            {
                const bool Down = InEvent.Get_EventType() == ECk_InputSource_EventType::Pressed;
                if (Key == EKeys::LeftShift) { _LeftShiftDown = Down; }
                else { _RightShiftDown = Down; }
            }
            return;
        }
        if (InEvent.Get_EventType() != ECk_InputSource_EventType::Pressed)
        { return; }

        if (Get_PanelKeysSuspended())
        { return; }

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
        const bool ShiftDown = _LeftShiftDown || _RightShiftDown;
        const int32 RowIndex = CkGym_Control::Get_PressedRow(Rows, Key, ShiftDown);
        if (RowIndex >= 0)
        { PC.Request_ControlActivated(RowIndex); }
    }
}
