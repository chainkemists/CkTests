// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM - RESET + PERSISTENCE STATION
//
// Display half of ResetMappingToDefault / ResetAllToDefaults / SaveKeyBindings.
// The profile view shows current AND default per row, so a reset is verifiable
// on the panel: after it, the two agree on every row.
//
// PERSISTENCE SPANS TWO PIE SESSIONS, SO THE PANEL PROVES IT WITH A MARKER.
// Ck_GymInput_StartPersistenceCheck moves Jump onto a key nothing else in this
// gym ever assigns, saves, and suspends teardown so leaving PIE does not erase
// the very thing being tested. On the next session this station probes ONCE at
// construct - before the demo on the Remap + Conflict station can touch
// anything - and a Jump still sitting on the marker key can only have come off
// disk. That is what makes the verdict a detection rather than a checklist item
// the viewer has to grade themselves.
//
// The probe result is stored on the station entity at construct rather than
// re-read on the display tick, because by tick time the demo has already been
// running and the answer would no longer mean anything.
//
// TEARDOWN. This station can leave the profile saved-customized, so DoEndPlay
// resets and re-saves unless the viewer suspended teardown.
//============================================================================

class UCk_EntityScript_InputGym_ResetPersistence : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, input_gym::k_Tag_ResetPersistence);

        Record_PersistenceProbe(InHandle);

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        input_gym_pc::Request_TeardownIfArmed();
    }

    // Runs once, at construct. The marker key is assigned by exactly one exec
    // command and by no demo step, so finding it on Jump here means the profile
    // was loaded with it.
    private void Record_PersistenceProbe(FCk_Handle& InHandle)
    {
        auto& Probe = InHandle.AddOrGet_Fragment(FCkInputGym_PersistenceProbe);

        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto JumpKey = utils_key_binding::Get_KeyForMapping(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First);

        Probe.Checked = true;
        Probe.ObservedJumpKey = input_gym::Format_Key(JumpKey);
        Probe.Passed = Probe.ObservedJumpKey == input_gym::Format_Key(input_gym::k_PersistMarkerKey);
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto Lines = TArray<FCkGym_ColoredLine>();

        Add_TeardownStatus(Lines);
        Add_PersistenceBlock(Lines, SelfEntity, PlayerController);
        Add_Rows(Lines, PlayerController);
        Add_LastCommand(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_TeardownStatus(TArray<FCkGym_ColoredLine>& OutLines)
    {
        if (input_gym_pc::Get_IsTeardownArmed())
        {
            input_gym::Add_Line(OutLines, "  Leaving this gym puts every key back and saves. Nothing leaks.", gym_palette::White);
            return;
        }

        input_gym::Add_Line(OutLines, "  Leaving this gym will LEAVE your key changes on disk.", gym_palette::Amber);
        input_gym::Add_Line(OutLines, "  Run Ck_GymInput_ResetAllAndSave when you are done.", gym_palette::Amber);
    }

    private void Add_PersistenceBlock(TArray<FCkGym_ColoredLine>& OutLines, FCk_Handle& InSelfEntity, APlayerController InPlayerController)
    {
        auto& Probe = InSelfEntity.AddOrGet_Fragment(FCkInputGym_PersistenceProbe);
        auto MarkerText = input_gym::Format_Key(input_gym::k_PersistMarkerKey);

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "DOES A KEY CHANGE SURVIVE A RESTART?", gym_palette::White);

        if (Probe.Passed)
        {
            input_gym::Add_Line(OutLines, f"  PERSISTENCE: PASS - Jump returned as {MarkerText} from disk", gym_palette::Green);
            input_gym::Add_Line(OutLines, "  Run Ck_GymInput_ResetAllAndSave to finish and leave nothing behind.", gym_palette::Cyan);
            return;
        }

        // Started this session: the marker is on Jump now, but it was not there
        // when this station constructed, so it has not been through a restart.
        auto JumpNow = utils_key_binding::Get_KeyForMapping(
            InPlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First);

        if (input_gym::Format_Key(JumpNow) == MarkerText)
        {
            input_gym::Add_Line(OutLines, f"  Jump is on the marker key {MarkerText} and has been saved.", gym_palette::White);
            input_gym::Add_Line(OutLines, "  Now stop PIE, PIE again, re-enter this gym.", gym_palette::Cyan);
            return;
        }

        input_gym::Add_Line(OutLines, "  1. Run Ck_GymInput_StartPersistenceCheck", gym_palette::Grey);
        input_gym::Add_Line(OutLines, f"  2. Jump moves to {MarkerText}, is saved, and teardown is suspended", gym_palette::Grey);
        input_gym::Add_Line(OutLines, "  3. Stop PIE, PIE again, come back to this gym", gym_palette::Grey);
        input_gym::Add_Line(OutLines, "  4. This panel turns green on its own if the key came back", gym_palette::Grey);
        input_gym::Add_Line(OutLines, "  5. Run Ck_GymInput_ResetAllAndSave to leave nothing behind", gym_palette::Grey);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_StartPersistenceCheck    start the check now", gym_palette::Cyan);
    }

    private void Add_Rows(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "KEYS RIGHT NOW", gym_palette::White);
        input_gym::Add_MappingRows(OutLines, InPlayerController);

        auto Expected = f"{input_assets::k_MappableRowCount}";
        auto Observed = f"{input_gym::Get_RowsAtDefaultCount(InPlayerController)}";

        input_gym::Add_Verdict_AmberOnMismatch(OutLines, "rows on their default key", Expected, Observed);

        if (Expected == Observed)
        { return; }

        input_gym::Add_Line(OutLines, "  (the remap demo next door changes keys while it runs - this count follows it)", gym_palette::Amber);
    }

    private void Add_LastCommand(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, f"LAST COMMAND - {input_gym_pc::Get_ResetReportLabel()}", gym_palette::White);

        auto Report = input_gym_pc::Get_ResetReportLines();
        input_gym::Add_Lines(OutLines, Report);

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "TRY IT YOURSELF", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_ResetJump          put one row back", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_ResetAll           put every row back", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_Save               write the current keys to disk", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_SuspendTeardown    keep changes when you leave", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_ArmTeardown        clean up when you leave", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_ResetAllAndSave    put everything back and save", gym_palette::Cyan);
    }
}
