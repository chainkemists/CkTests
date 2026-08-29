// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM - PlayerController
//============================================================================
//
// Deliberately thin: the pawn owns movement and cursor aim (see
// ACk_PlaygroundGym_Pawn::Tick), so the PC's jobs are showing the mouse cursor
// it IS the aim pointer - composing the player's input source, and hosting the
// diagnostics execs.
//
// PER-FRAME WORK RUNS OFF A TIMER TICK ON THE PC's OWN ENTITY
// (utils_timer::Create_Tick) rather than an actor Tick this class would have to
// enable and the base never asked for.
//============================================================================

class ACk_PlaygroundGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PlaygroundEntity;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        Super::BeginPlay();

        // The cursor is the aim pointer - it stays visible for the whole session.
        bShowMouseCursor = true;
    }

    // The base spawns the PC's own WithActor entity and starts the gym from here;
    // the playground additionally keeps the handle, because the source-composition
    // tick needs an entity to hang off.
    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle) override
    {
        Super::OnEntityConstructed(InEntityScriptHandle);

        _PlaygroundEntity = FCk_Handle(InEntityScriptHandle);
        utils_timer::Create_Tick(_PlaygroundEntity, FCk_Delegate_Timer(this, n"OnPlaygroundTick"));
    }

    // Skip the base gym-selector menu - the playground is drivable from the first frame (Tab still toggles the menu).
    void Request_StartGym() override
    {
        Print("Input Playground | WASD: move, SHIFT: sprint | mouse: aim | LMB: light chain x3 (hold = light special) | RMB: heavy chain x3 (hold = heavy special) | LMB then RMB: combo L-H | RMB then LMB: combo H-L | sprint (W+SHIFT) + LMB/RMB: sprint AoE attack | Q: block (hold; press just before the hit = PARRY, which returns the shot) | the dummy shoots every 3s inside 1600cm - walk out of it, block it, or parry it back | Tab: gym menu", 12.0f);
    }

    UFUNCTION()
    private void OnPlaygroundTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Idempotent, and from a tick rather than a construct because the player's
        // input source does not exist until the local player has a controller and
        // the subsystem gives up quietly until it does.
        playground_gym::Request_EnsureSourceComposed();
    }

    // ----------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Neither row may take a key the combat kit reads: LMB, RMB, W, LeftShift and Q are the matcher's
    // subject keys (playground_gym::k_Key_*) and WASD is the pawn's own locomotion poll.
    // ----------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "INPUT PLAYGROUND";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        // The CVar itself is the state, and it reads back - so the row reports it rather than a mirror
        // that anything typing the console command behind the panel's back would falsify.
        Rows.Add(CkGym_Control::Toggle(EKeys::N, "N", "Near-miss recording",
            utils_intent_matcher::Get_ScanDiagnosticsEnabled()));
        Rows.Add(CkGym_Control::Action(EKeys::I, "I", "Why is nothing happening"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_SetScanDiagnostics(utils_intent_matcher::Get_ScanDiagnosticsEnabled() == false); }
        else if (InRowIndex == 1) { Request_ReportStatus(); }
    }

    // Scan diagnostics feed the CkIntentDebugger's near-miss ring; this is the manual switch until the combat
    // kit decides when recording should be on.
    private void Request_SetScanDiagnostics(bool InEnabled)
    {
        if (InEnabled)
        {
            System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 1");
            Print("[Playground] near-miss recording ON", 6.0f);
            return;
        }

        System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 0");
        Print("[Playground] near-miss recording OFF", 6.0f);
    }

    // When nothing arms, this says which of the three things the combat kit depends on
    // has not arrived: the player's source, the button space derived from it, or
    // the first sampled row.
    private void Request_ReportStatus()
    {
        auto Source = playground_gym::TryGet_PlayerSource();

        if (ck::Is_NOT_Valid(Source))
        {
            Print("[Playground] no input source for local player 0 yet", 8.0f);
            return;
        }

        auto ButtonMap = playground_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        {
            Print("[Playground] source is up, button map not composed yet", 8.0f);
            return;
        }

        auto Sampler = playground_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler))
        {
            Print("[Playground] source and map are up, sampler not composed yet", 8.0f);
            return;
        }

        auto Buttons = utils_input_button_map::Get_AllButtons(ButtonMap).Num();
        auto Frames = utils_intent_sampler::Get_FrameCount(Sampler);

        Print(f"[Playground] buttons {Buttons}, rows recorded {Frames}", 8.0f);
    }
}
