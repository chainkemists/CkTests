// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — PlayerController
//
// Owns every mutation a VIEWER can perform. A key profile is per-local-player,
// so there is nothing station-scoped to mutate: the exec commands below call
// UCk_Utils_KeyBinding_UE directly and the stations pick the result up on their
// next display tick. The unattended demo does the same thing from its own state
// machine on the Remap + Conflict station.
//
// REPORTS GO WHERE THE COMMAND IS ADVERTISED. Four report slots, not one: a
// remap-family command reports on the Remap + Conflict panel, a reset-family one
// on Reset + Persistence, the dump on Binding Inspection, and the glyph refresh
// on Key Icons. A viewer reading a command off a panel sees its outcome on that
// same panel instead of hunting for it.
//
// EVERY COMMAND HOLDS THE DEMO FIRST. Typing a command means wanting to watch
// what it did, which is impossible while the demo keeps moving keys underneath
// it. Ck_GymInput_Auto 1 lets it continue.
//
// Registration happens in BeginPlay BEFORE Super, so the profile is populated
// before the base flow spawns the stations and reaches Request_StartGym.
//
// TEARDOWN IS ARMED BY DEFAULT. SaveKeyBindings writes real user settings under
// Saved/ that outlive the session, and the demo runs unattended, so the stations
// that can be mutated reset and re-save on DoEndPlay unless the viewer
// explicitly suspends it. Suspending is what makes the persistence check
// possible at all — a rebind cannot be observed surviving a PIE restart if
// leaving PIE erases it — so it is offered as an exec rather than being
// impossible, and re-arming is one command away.
//
// Two shipped-code traps this file deliberately steers around:
//   - SwapKeys assigns Invalid to the other side when the SOURCE mapping is
//     unbound, so Ck_GymInput_Swap refuses unless both rows currently hold a
//     key (CkInput/CLAUDE.md anti-pattern 6).
//   - RemapKeys reports success for an EMPTY name array, so the batch command
//     checks the array before calling.
//============================================================================

class ACk_InputGym_KeyBinding_PlayerController : ACk_Gym_Base_PlayerController
{
    private FString _RemapReportLabel = "nothing yet";
    private FString _ResetReportLabel = "nothing yet";
    private FString _DumpReportLabel  = "nothing yet";
    private FString _GlyphReportLabel = "nothing yet";

    private TArray<FCkGym_ColoredLine> _RemapReportLines;
    private TArray<FCkGym_ColoredLine> _ResetReportLines;
    private TArray<FCkGym_ColoredLine> _DumpReportLines;
    private TArray<FCkGym_ColoredLine> _GlyphReportLines;

    private bool _TeardownArmed = true;

    FString Get_RemapReportLabel() const { return _RemapReportLabel; }
    FString Get_ResetReportLabel() const { return _ResetReportLabel; }
    FString Get_DumpReportLabel()  const { return _DumpReportLabel; }
    FString Get_GlyphReportLabel() const { return _GlyphReportLabel; }

    TArray<FCkGym_ColoredLine> Get_RemapReportLines() const { return _RemapReportLines; }
    TArray<FCkGym_ColoredLine> Get_ResetReportLines() const { return _ResetReportLines; }
    TArray<FCkGym_ColoredLine> Get_DumpReportLines()  const { return _DumpReportLines; }
    TArray<FCkGym_ColoredLine> Get_GlyphReportLines() const { return _GlyphReportLines; }

    bool Get_IsTeardownArmed() const
    {
        return _TeardownArmed;
    }

    // Super reaches Get_RequiredStations() and the whole station spawn flow, so
    // the mapping context has to be registered before it runs — otherwise the
    // stations construct against an empty key profile.
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        input_gym::Request_RegisterMappingContext(this);
        Super::BeginPlay();
    }

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Input.ResetPersistence", "Reset + Persistence",
            "Putting keys back, and proving a change survives a restart."));

        Stations.Add(MakeStationPayload(n"Gym.Input.Inspection", "Binding Inspection",
            "Everything the game currently knows about your key bindings."));

        Stations.Add(MakeStationPayload(n"Gym.Input.RemapConflict", "Remap + Conflict",
            "A demo that rebinds keys on a loop and checks itself as it goes."));

        Stations.Add(MakeStationPayload(n"Gym.Input.KeyIcon", "Key Icons",
            "The artwork shown for each key, re-resolved every frame."));

        Stations.Add(MakeStationPayload(n"Gym.Input.ChangeSignal", "Change Signal",
            "How the game finds out a key moved."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        Station.AutoSize = true;
        return Station;
    }

    // Reset + Persistence is spawned FIRST on purpose: its persistence probe
    // has to read the key profile before the demo state machine on the Remap +
    // Conflict station enters its first step and starts moving keys.
    void Request_StartGym() override
    {
        // Idempotent, and the gym can be restarted through Ck_Gym_Restart — a
        // second registration of an already-registered context is a no-op.
        input_gym::Request_RegisterMappingContext(this);

        SpawnStation("Gym.Input.ResetPersistence", "RESET + PERSISTENCE",
            UCk_EntityScript_InputGym_ResetPersistence,
            "Put keys back, save them, and check a change survives a restart.");

        SpawnStation("Gym.Input.Inspection", "BINDING INSPECTION",
            UCk_EntityScript_InputGym_Inspection,
            "What the game thinks your keys are, read fresh every frame.");

        SpawnStation("Gym.Input.RemapConflict", "REMAP + CONFLICT",
            UCk_EntityScript_InputGym_RemapConflict,
            "Watch it rebind keys on a loop. Green lines mean the check matched.");

        SpawnStation("Gym.Input.KeyIcon", "KEY ICONS",
            UCk_EntityScript_InputGym_KeyIcon,
            "Which picture the game would draw for each key, right now.");

        SpawnStation("Gym.Input.ChangeSignal", "CHANGE SIGNAL",
            UCk_EntityScript_InputGym_ChangeSignal,
            "Proof the game is told when a key moves, and does not have to guess.");
    }

    private void SpawnStation(
        FString InTag,
        FString InTitle,
        TSubclassOf<UCk_EntityScript_UE> InStationClass,
        FString InDescription)
    {
        auto Params = FCkInputGym_StationSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        Params.StationTitle = InTitle;
        Params.StationDescription = InDescription;

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            InStationClass,
            FInstancedStruct::Make(Params));
    }

    //------------------------------------------------------------------------
    // Demo control
    //------------------------------------------------------------------------

    // The demo's state machine lives on the Remap + Conflict station entity, so
    // the toggle travels as the shared gym auto-set message rather than the PC
    // reaching into a station script.
    private void Request_SetDemoRunning(bool InRunning)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::TransientEntity(), input_gym::k_Tag_RemapConflict);
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(InRunning));
        }
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Auto Demo On/Off")
    void Ck_GymInput_Auto(int32 InEnabled = 1)
    {
        Request_SetDemoRunning(InEnabled != 0);
    }

    //------------------------------------------------------------------------
    // Inspection
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Dump Profile")
    void Ck_GymInput_Dump()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto Lines = TArray<FCkGym_ColoredLine>();

        input_gym::Add_MappingRows(Lines, PlayerController);
        input_gym::Add_AllMappingDetails(Lines, PlayerController);

        Set_DumpReport("Dump the whole profile", Lines);
    }

    //------------------------------------------------------------------------
    // Remap + conflict
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Remap Jump To A Free Key")
    void Ck_GymInput_RemapFree()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        Request_RemapJumpTo(PlayerController, input_gym::k_FreeKey, "Move Jump to a free key");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Remap Jump Onto Crouch (same category)")
    void Ck_GymInput_RemapTakenSameCategory()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        Request_RemapJumpTo(PlayerController, CrouchKey, "Move Jump onto Crouch's key");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Remap Jump Onto Interact (cross category)")
    void Ck_GymInput_RemapTakenCrossCategory()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto InteractKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Interact, EPlayerMappableKeySlot::First);

        Request_RemapJumpTo(PlayerController, InteractKey, "Move Jump onto Interact's key");
    }

    // The collision preview is taken BEFORE the remap on purpose: afterwards the
    // key belongs to Jump as well, so it would describe the aftermath rather
    // than the decision the caller had to make.
    private void Request_RemapJumpTo(APlayerController InPlayerController, FKey InNewKey, FString InLabel)
    {
        auto Lines = TArray<FCkGym_ColoredLine>();

        if (InNewKey.IsValid() == false)
        {
            input_gym::Add_Line(Lines, "  That row holds no key, so there is nothing to move onto.", gym_palette::Red);
            Set_RemapReport(InLabel, Lines);
            return;
        }

        input_gym::Add_ConflictPreview(Lines, InPlayerController, input_gym::k_Mapping_Jump, InNewKey);

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKey(
            InPlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, InNewKey, FailureReason);

        input_gym::Add_Verdict(Lines, "remap accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(InNewKey),
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                InPlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First)));

        Set_RemapReport(InLabel, Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Swap Jump And Crouch")
    void Ck_GymInput_Swap()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto Lines = TArray<FCkGym_ColoredLine>();

        auto JumpKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First);
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        // SwapKeys leaves OldKey at Invalid when the source row holds no key and
        // then assigns that Invalid to whoever held the target key, silently
        // unbinding them. Refuse rather than demonstrate the trap by accident.
        if (JumpKey.IsValid() == false || CrouchKey.IsValid() == false)
        {
            input_gym::Add_Line(Lines, "  Refused: both rows have to be bound before they can trade.", gym_palette::Red);
            input_gym::Add_Line(Lines, "  Run Ck_GymInput_ResetAll first.", gym_palette::Cyan);
            Set_RemapReport("Trade Jump and Crouch", Lines);
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::SwapKeys(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, CrouchKey, FailureReason);

        input_gym::Add_Verdict(Lines, "swap accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(CrouchKey),
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First)));
        input_gym::Add_Verdict(Lines, "Crouch", input_gym::Format_Key(JumpKey),
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First)));

        Set_RemapReport("Trade Jump and Crouch", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Unbind Conflict And Give Crouch's Key To Jump")
    void Ck_GymInput_UnbindAndRemap()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto Lines = TArray<FCkGym_ColoredLine>();

        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        if (CrouchKey.IsValid() == false)
        {
            input_gym::Add_Line(Lines, "  Refused: Crouch holds no key to take.", gym_palette::Red);
            input_gym::Add_Line(Lines, "  Run Ck_GymInput_ResetAll first.", gym_palette::Cyan);
            Set_RemapReport("Take Crouch's key for Jump", Lines);
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::UnbindConflictAndRemap(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, CrouchKey, FailureReason);

        input_gym::Add_Verdict(Lines, "take accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(CrouchKey),
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First)));
        input_gym::Add_Verdict(Lines, "Crouch (previous holder)", "<unbound>",
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First)));

        Set_RemapReport("Take Crouch's key for Jump", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Batch Remap Both Movement Rows")
    void Ck_GymInput_RemapBatch()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto Lines = TArray<FCkGym_ColoredLine>();

        auto Names = TArray<FName>();
        Names.Add(input_gym::k_Mapping_Jump);
        Names.Add(input_gym::k_Mapping_Crouch);

        // RemapKeys reports success for an empty array, so an empty batch would
        // read as a passing no-op.
        if (Names.Num() == 0)
        {
            input_gym::Add_Line(Lines, "  Refused: nothing was named in the batch.", gym_palette::Red);
            Set_RemapReport("Move both movement rows at once", Lines);
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKeys(
            PlayerController, Names, EPlayerMappableKeySlot::First, input_gym::k_BatchKey, FailureReason);

        auto BatchKeyText = input_gym::Format_Key(input_gym::k_BatchKey);

        input_gym::Add_Verdict(Lines, "batch accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", BatchKeyText,
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First)));
        input_gym::Add_Verdict(Lines, "Crouch", BatchKeyText,
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First)));

        Set_RemapReport("Move both movement rows at once", Lines);
    }

    //------------------------------------------------------------------------
    // Reset + persistence
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Reset Jump To Default")
    void Ck_GymInput_ResetJump()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto Expected = input_gym::Format_Key(
            input_gym::Get_DefaultKeyForMapping(PlayerController, input_gym::k_Mapping_Jump));

        utils_key_binding::ResetMappingToDefault(PlayerController, input_gym::k_Mapping_Jump);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Verdict(Lines, "Jump", Expected,
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First)));

        Set_ResetReport("Put Jump back to its authored key", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Reset All To Defaults")
    void Ck_GymInput_ResetAll()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        utils_key_binding::ResetAllToDefaults(PlayerController);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Verdict(Lines, "rows on their default key",
            f"{input_assets::k_MappableRowCount}",
            f"{input_gym::Get_RowsAtDefaultCount(PlayerController)}");
        input_gym::Add_MappingRows(Lines, PlayerController);

        Set_ResetReport("Put every row back to its authored key", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Save Key Bindings")
    void Ck_GymInput_Save()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        utils_key_binding::SaveKeyBindings(PlayerController);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Written to disk in the background, under Saved/.", gym_palette::White);
        input_gym::Add_Line(Lines, "  Suspend teardown before leaving PIE if you want it to stay there.", gym_palette::Cyan);

        Set_ResetReport("Save the current keys to disk", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Start Persistence Check")
    void Ck_GymInput_StartPersistenceCheck()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto MarkerText = input_gym::Format_Key(input_gym::k_PersistMarkerKey);

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKey(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First,
            input_gym::k_PersistMarkerKey, FailureReason);

        utils_key_binding::SaveKeyBindings(PlayerController);
        _TeardownArmed = false;

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Verdict(Lines, "marker set", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", MarkerText,
            input_gym::Format_Key(utils_key_binding::Get_KeyForMapping(
                PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First)));
        input_gym::Add_Line(Lines, "  Saved, and teardown is suspended so leaving PIE keeps it.", gym_palette::White);
        input_gym::Add_Line(Lines, "  Now stop PIE, PIE again, re-enter this gym.", gym_palette::Cyan);

        Set_ResetReport("Start the persistence check", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Suspend Teardown On Exit")
    void Ck_GymInput_SuspendTeardown()
    {
        Request_SetDemoRunning(false);
        _TeardownArmed = false;

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Leaving the gym will now LEAVE your key changes on disk.", gym_palette::Amber);
        input_gym::Add_Line(Lines, "  This is the only way to watch a change survive a restart.", gym_palette::White);
        input_gym::Add_Line(Lines, "  Run Ck_GymInput_ResetAllAndSave when you are done.", gym_palette::Cyan);

        Set_ResetReport("Keep changes when leaving", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Arm Teardown On Exit")
    void Ck_GymInput_ArmTeardown()
    {
        Request_SetDemoRunning(false);
        _TeardownArmed = true;

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Leaving the gym will put every row back and re-save.", gym_palette::White);

        Set_ResetReport("Clean up when leaving", Lines);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Reset All And Save (teardown)")
    void Ck_GymInput_ResetAllAndSave()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        input_gym::Request_ResetAllAndSave(PlayerController);
        _TeardownArmed = true;

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Verdict(Lines, "rows on their default key",
            f"{input_assets::k_MappableRowCount}",
            f"{input_gym::Get_RowsAtDefaultCount(PlayerController)}");
        input_gym::Add_Line(Lines, "  Disk copy overwritten to match. Nothing left behind.", gym_palette::White);

        Set_ResetReport("Put everything back and save", Lines);
    }

    //------------------------------------------------------------------------
    // Key icons
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Refresh Glyphs")
    void Ck_GymInput_RefreshGlyphs()
    {
        Request_SetDemoRunning(false);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_AllGlyphRows(Lines, PlayerController);

        Set_GlyphReport("Resolve every glyph again", Lines);
    }

    //------------------------------------------------------------------------

    private void Set_RemapReport(FString InLabel, TArray<FCkGym_ColoredLine>& InLines)
    {
        _RemapReportLabel = InLabel;
        _RemapReportLines = InLines;
        Print(f"[CkInput Gym] {InLabel}", 6.0f);
    }

    private void Set_ResetReport(FString InLabel, TArray<FCkGym_ColoredLine>& InLines)
    {
        _ResetReportLabel = InLabel;
        _ResetReportLines = InLines;
        Print(f"[CkInput Gym] {InLabel}", 6.0f);
    }

    private void Set_DumpReport(FString InLabel, TArray<FCkGym_ColoredLine>& InLines)
    {
        _DumpReportLabel = InLabel;
        _DumpReportLines = InLines;
        Print(f"[CkInput Gym] {InLabel}", 6.0f);
    }

    private void Set_GlyphReport(FString InLabel, TArray<FCkGym_ColoredLine>& InLines)
    {
        _GlyphReportLabel = InLabel;
        _GlyphReportLines = InLines;
        Print(f"[CkInput Gym] {InLabel}", 6.0f);
    }
};

//============================================================================
// STATION -> CONTROLLER BRIDGE
//
// The stations are display-only; these reads are the only place they reach the
// controller, and each degrades safely when it is gone — which is the normal
// state during world teardown.
//============================================================================

namespace input_gym_pc
{
    ACk_InputGym_KeyBinding_PlayerController TryGet_GymPlayerController()
    {
        return Cast<ACk_InputGym_KeyBinding_PlayerController>(input_gym::Get_LocalPlayerController());
    }

    FString Get_RemapReportLabel()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return "(gym PlayerController unavailable)"; }

        return GymPlayerController.Get_RemapReportLabel();
    }

    FString Get_ResetReportLabel()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return "(gym PlayerController unavailable)"; }

        return GymPlayerController.Get_ResetReportLabel();
    }

    FString Get_DumpReportLabel()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return "(gym PlayerController unavailable)"; }

        return GymPlayerController.Get_DumpReportLabel();
    }

    FString Get_GlyphReportLabel()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return "(gym PlayerController unavailable)"; }

        return GymPlayerController.Get_GlyphReportLabel();
    }

    TArray<FCkGym_ColoredLine> Get_RemapReportLines()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return TArray<FCkGym_ColoredLine>(); }

        return GymPlayerController.Get_RemapReportLines();
    }

    TArray<FCkGym_ColoredLine> Get_ResetReportLines()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return TArray<FCkGym_ColoredLine>(); }

        return GymPlayerController.Get_ResetReportLines();
    }

    TArray<FCkGym_ColoredLine> Get_DumpReportLines()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return TArray<FCkGym_ColoredLine>(); }

        return GymPlayerController.Get_DumpReportLines();
    }

    TArray<FCkGym_ColoredLine> Get_GlyphReportLines()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return TArray<FCkGym_ColoredLine>(); }

        return GymPlayerController.Get_GlyphReportLines();
    }

    bool Get_IsTeardownArmed()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return true; }

        return GymPlayerController.Get_IsTeardownArmed();
    }

    // Called from the DoEndPlay of every station that can leave the profile
    // customized. No controller means the settings object is already
    // unreachable, so there is nothing left to reset; a failed cast is treated
    // as ARMED, because leaking a rebind is the worse of the two outcomes.
    void Request_TeardownIfArmed()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto GymPlayerController = Cast<ACk_InputGym_KeyBinding_PlayerController>(PlayerController);
        if (ck::IsValid(GymPlayerController) && GymPlayerController.Get_IsTeardownArmed() == false)
        { return; }

        input_gym::Request_ResetAllAndSave(PlayerController);
    }
}
