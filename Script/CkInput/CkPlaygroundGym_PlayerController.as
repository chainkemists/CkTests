// Language=angelscript

//============================================================================
// CK INPUT PLAYGROUND GYM — PlayerController
//============================================================================
//
// Deliberately thin: the pawn owns movement and cursor aim (see
// ACk_PlaygroundGym_Pawn::Tick), so the PC's jobs are showing the mouse cursor —
// it IS the aim pointer — composing the player's input source, and hosting the
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

        // The cursor is the aim pointer — it stays visible for the whole session.
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

    // Skip the base gym-selector menu — the playground is drivable from the first frame (Tab still toggles the menu).
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
    // CONSOLE COMMANDS
    // ----------------------------------------------------------------------------------------------------------------

    // Scan diagnostics feed the CkIntentDebugger's near-miss ring; this is the manual switch until the combat
    // kit decides when recording should be on.
    UFUNCTION(Exec, DisplayName = "Playground Gym - Near-Miss Recording On/Off")
    void Ck_GymPlayground_Diagnostics(int32 InEnabled = 1)
    {
        if (InEnabled != 0)
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
    UFUNCTION(Exec, DisplayName = "Playground Gym - Why Is Nothing Happening")
    void Ck_GymPlayground_Status()
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
