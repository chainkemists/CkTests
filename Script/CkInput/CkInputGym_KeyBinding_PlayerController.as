// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — PlayerController
//
// Owns every mutation the gym can perform. A key profile is per-local-player,
// so there is nothing station-scoped to mutate: the exec commands below call
// UCk_Utils_KeyBinding_UE directly and the stations pick the result up on their
// next display tick.
//
// Registration happens in BeginPlay BEFORE Super, so the profile is populated
// before the base flow spawns the stations and reaches Request_StartGym.
//
// TEARDOWN IS ARMED BY DEFAULT. SaveKeyBindings writes real user settings under
// Saved/ that outlive the session, so the stations that can be mutated reset and
// re-save on DoEndPlay unless the viewer explicitly suspends it. Suspending is
// what makes the persistence check possible at all — a rebind cannot be observed
// surviving a PIE restart if leaving PIE erases it — so it is offered as an exec
// rather than being impossible, and re-arming is one command away.
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
    // What the last exec command did. The remap and reset stations render this
    // so the outcome is legible on the panel the viewer is already looking at,
    // not only in the console scrollback.
    private FString _LastActionReport = "No action yet — run one of the exec commands listed on a station.";

    private bool _TeardownArmed = true;

    FString Get_LastActionReport() const
    {
        return _LastActionReport;
    }

    bool Get_IsTeardownArmed() const
    {
        return _TeardownArmed;
    }

    FString Get_TeardownStatusLine() const
    {
        if (_TeardownArmed)
        { return "Teardown ARMED — leaving the gym resets and re-saves every row."; }

        return "Teardown SUSPENDED — rebinds will survive this session. Re-arm before you finish.";
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

        Stations.Add(MakeStationPayload(n"Gym.Input.Inspection", "Binding Inspection",
            "Live view of the active key profile."));

        Stations.Add(MakeStationPayload(n"Gym.Input.RemapConflict", "Remap + Conflict",
            "Remap, conflict scopes, swap, unbind-and-remap."));

        Stations.Add(MakeStationPayload(n"Gym.Input.ResetPersistence", "Reset + Persistence",
            "Reset one row, reset all, save to disk."));

        Stations.Add(MakeStationPayload(n"Gym.Input.KeyIcon", "Key Icons",
            "Glyph brushes re-resolved every tick."));

        Stations.Add(MakeStationPayload(n"Gym.Input.ChangeSignal", "Change Signal",
            "Bound mapping-changed listeners, one per row."));

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

    void Request_StartGym() override
    {
        // Idempotent, and the gym can be restarted through Ck_Gym_Restart — a
        // second registration of an already-registered context is a no-op.
        input_gym::Request_RegisterMappingContext(this);

        SpawnStation("Gym.Input.Inspection", "BINDING INSPECTION",
            UCk_EntityScript_InputGym_Inspection,
            "Ck_GymInput_Dump");

        SpawnStation("Gym.Input.RemapConflict", "REMAP + CONFLICT",
            UCk_EntityScript_InputGym_RemapConflict,
            "Ck_GymInput_RemapFree | Ck_GymInput_RemapTakenSameCategory\nCk_GymInput_RemapTakenCrossCategory | Ck_GymInput_Swap\nCk_GymInput_UnbindAndRemap | Ck_GymInput_RemapBatch");

        SpawnStation("Gym.Input.ResetPersistence", "RESET + PERSISTENCE",
            UCk_EntityScript_InputGym_ResetPersistence,
            "Ck_GymInput_ResetJump | Ck_GymInput_ResetAll | Ck_GymInput_Save\nCk_GymInput_SuspendTeardown | Ck_GymInput_ArmTeardown\nCk_GymInput_ResetAllAndSave");

        SpawnStation("Gym.Input.KeyIcon", "KEY ICONS",
            UCk_EntityScript_InputGym_KeyIcon,
            "Ck_GymInput_RefreshGlyphs");

        SpawnStation("Gym.Input.ChangeSignal", "CHANGE SIGNAL",
            UCk_EntityScript_InputGym_ChangeSignal,
            "Drive it from the Remap + Conflict station's commands.");
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
    // Inspection
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Dump Profile")
    void Ck_GymInput_Dump()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        Set_LastAction("Dump profile",
            f"{input_gym::Format_ProfileRows(PlayerController)}{input_gym::Format_AllMappingRows(PlayerController)}");
    }

    //------------------------------------------------------------------------
    // Remap + conflict
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Remap Jump To A Free Key")
    void Ck_GymInput_RemapFree()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        Request_RemapJumpTo(PlayerController, input_gym::k_FreeKey, "Remap Jump to a free key");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Remap Jump Onto Crouch (same category)")
    void Ck_GymInput_RemapTakenSameCategory()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        Request_RemapJumpTo(PlayerController, CrouchKey,
            "Remap Jump onto Crouch's key (Movement vs Movement)");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Remap Jump Onto Interact (cross category)")
    void Ck_GymInput_RemapTakenCrossCategory()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto InteractKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Interact, EPlayerMappableKeySlot::First);

        Request_RemapJumpTo(PlayerController, InteractKey,
            "Remap Jump onto Interact's key (Movement vs Interaction)");
    }

    // The conflict report is taken BEFORE the remap on purpose: afterwards the
    // key belongs to Jump as well, so the report would describe the aftermath
    // rather than the decision the caller had to make.
    private void Request_RemapJumpTo(APlayerController InPlayerController, FKey InNewKey, FString InLabel)
    {
        if (InNewKey.IsValid() == false)
        {
            Set_LastAction(InLabel, "  target key is unbound — nothing to remap onto.\n");
            return;
        }

        auto Report = input_gym::Format_ConflictReport(
            InPlayerController, input_gym::k_Mapping_Jump, InNewKey);

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKey(
            InPlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, InNewKey, FailureReason);

        Report = f"{Report}  RemapKey succeeded={Succeeded}\n";
        Set_LastAction(InLabel, Report);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Swap Jump And Crouch")
    void Ck_GymInput_Swap()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();

        auto JumpKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First);
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        // SwapKeys leaves OldKey at Invalid when the source row holds no key and
        // then assigns that Invalid to whoever held the target key, silently
        // unbinding them. Refuse rather than demonstrate the trap by accident.
        if (JumpKey.IsValid() == false || CrouchKey.IsValid() == false)
        {
            Set_LastAction("Swap Jump and Crouch",
                f"  refused: both rows must be bound (Jump={input_gym::Format_Key(JumpKey)}, Crouch={input_gym::Format_Key(CrouchKey)}).\n  Run Ck_GymInput_ResetAll first.\n");
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::SwapKeys(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, CrouchKey, FailureReason);

        auto Report = f"  before: Jump={input_gym::Format_Key(JumpKey)}  Crouch={input_gym::Format_Key(CrouchKey)}\n";
        Report = f"{Report}  SwapKeys succeeded={Succeeded}\n";
        Report = f"{Report}{input_gym::Format_AllMappingRows(PlayerController)}";
        Set_LastAction("Swap Jump and Crouch", Report);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Unbind Conflict And Give Crouch's Key To Jump")
    void Ck_GymInput_UnbindAndRemap()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        if (CrouchKey.IsValid() == false)
        {
            Set_LastAction("Unbind conflict and remap",
                "  refused: Crouch holds no key to take. Run Ck_GymInput_ResetAll first.\n");
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::UnbindConflictAndRemap(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, CrouchKey, FailureReason);

        auto Report = f"  Jump takes {input_gym::Format_Key(CrouchKey)}, the previous holder is cleared\n";
        Report = f"{Report}  UnbindConflictAndRemap succeeded={Succeeded}\n";
        Report = f"{Report}{input_gym::Format_AllMappingRows(PlayerController)}";
        Set_LastAction("Unbind conflict and remap", Report);
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Batch Remap Both Movement Rows")
    void Ck_GymInput_RemapBatch()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();

        auto Names = TArray<FName>();
        Names.Add(input_gym::k_Mapping_Jump);
        Names.Add(input_gym::k_Mapping_Crouch);

        // RemapKeys reports success for an empty array, so an empty batch would
        // read as a passing no-op.
        if (Names.Num() == 0)
        {
            Set_LastAction("Batch remap", "  refused: empty mapping-name array.\n");
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKeys(
            PlayerController, Names, EPlayerMappableKeySlot::First, input_gym::k_BatchKey, FailureReason);

        auto Report = f"  Jump + Crouch -> {input_gym::Format_Key(input_gym::k_BatchKey)} in one call\n";
        Report = f"{Report}  RemapKeys succeeded={Succeeded}\n";
        Report = f"{Report}{input_gym::Format_AllMappingRows(PlayerController)}";
        Set_LastAction("Batch remap both movement rows", Report);
    }

    //------------------------------------------------------------------------
    // Reset + persistence
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Reset Jump To Default")
    void Ck_GymInput_ResetJump()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        utils_key_binding::ResetMappingToDefault(PlayerController, input_gym::k_Mapping_Jump);

        Set_LastAction("Reset Jump to its authored default",
            input_gym::Format_AllMappingRows(PlayerController));
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Reset All To Defaults")
    void Ck_GymInput_ResetAll()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        utils_key_binding::ResetAllToDefaults(PlayerController);

        Set_LastAction("Reset every row to its authored default",
            input_gym::Format_AllMappingRows(PlayerController));
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Save Key Bindings")
    void Ck_GymInput_Save()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        utils_key_binding::SaveKeyBindings(PlayerController);

        Set_LastAction("Save key bindings to disk",
            "  Written asynchronously under Saved/. Suspend teardown before leaving PIE\n  if you intend to check the rebind survived a restart.\n");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Suspend Teardown On Exit")
    void Ck_GymInput_SuspendTeardown()
    {
        _TeardownArmed = false;
        Set_LastAction("Suspend teardown on exit",
            "  Leaving the gym will now LEAVE your rebinds on disk. This is the only\n  way to observe persistence across a PIE restart — re-arm and run\n  Ck_GymInput_ResetAllAndSave once you have.\n");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Arm Teardown On Exit")
    void Ck_GymInput_ArmTeardown()
    {
        _TeardownArmed = true;
        Set_LastAction("Arm teardown on exit",
            "  Leaving the gym will reset every row and re-save, so nothing leaks.\n");
    }

    UFUNCTION(Exec, DisplayName = "Input Gym - Reset All And Save (teardown)")
    void Ck_GymInput_ResetAllAndSave()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        input_gym::Request_ResetAllAndSave(PlayerController);
        _TeardownArmed = true;

        Set_LastAction("Teardown: reset every row and persist the reset",
            input_gym::Format_AllMappingRows(PlayerController));
    }

    //------------------------------------------------------------------------
    // Key icons
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName = "Input Gym - Refresh Glyphs")
    void Ck_GymInput_RefreshGlyphs()
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        Set_LastAction("Re-resolve every glyph brush",
            input_gym::Format_AllGlyphRows(PlayerController));
    }

    //------------------------------------------------------------------------

    private void Set_LastAction(FString InLabel, FString InDetail)
    {
        _LastActionReport = f"{InLabel}\n{InDetail}";
        Print(f"[CkInput Gym] {InLabel}", 6.0f);
    }
};

//============================================================================
// STATION -> CONTROLLER BRIDGE
//
// The stations are display-only; these three reads are the only place they
// reach the controller, and each degrades safely when it is gone — which is the
// normal state during world teardown.
//============================================================================

namespace input_gym_pc
{
    ACk_InputGym_KeyBinding_PlayerController TryGet_GymPlayerController()
    {
        return Cast<ACk_InputGym_KeyBinding_PlayerController>(input_gym::Get_LocalPlayerController());
    }

    FString Get_LastActionReport()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return "  (gym PlayerController unavailable)\n"; }

        return GymPlayerController.Get_LastActionReport();
    }

    FString Get_TeardownStatusLine()
    {
        auto GymPlayerController = TryGet_GymPlayerController();
        if (ck::Is_NOT_Valid(GymPlayerController))
        { return "  (gym PlayerController unavailable)"; }

        return GymPlayerController.Get_TeardownStatusLine();
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
