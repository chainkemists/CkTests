// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — REMAP + CONFLICT STATION
//
// The centrepiece of the gym: a self-running demo that walks the whole
// remapping surface — RemapKey, RemapKeys, Get_HasKeyConflicts, SwapKeys,
// UnbindConflictAndRemap, ResetAllToDefaults, SaveKeyBindings — and checks
// itself at every step. The steps live in CkInputGym_RemapDemoSteps.as as a
// CkStateMachine graph; this station owns the machine and renders it.
//
// The panel shows, in order: whether the demo is running, the step list with
// the live one highlighted, the current step's EXPECT/GOT verdicts, the live
// key bindings, a collision preview that mutates nothing, and the outcome of
// the last remap-family command the viewer typed.
//
// WHY THE REPORT LIVES HERE. The PlayerController advertises its remap commands
// on this panel, so this is where their outcome belongs — a viewer reading
// about Ck_GymInput_Swap should not have to look at a different station to see
// what it did.
//
// A MANUAL COMMAND HOLDS THE DEMO. Every exec on the PlayerController pauses
// this state machine first: someone poking commands by hand wants the panel to
// stay still while they read it.
//
// TEARDOWN. The demo leaves the profile customized between steps, so DoEndPlay
// resets and re-saves unless the viewer suspended teardown on the
// PlayerController.
//============================================================================

class UCk_EntityScript_InputGym_RemapConflict : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    private FCk_Handle_StateMachine _StepMachine;
    private FCkGym_SmConfig _StepConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, input_gym::k_Tag_RemapConflict);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        // Auto-starts on setup, so the demo is already running by the time a
        // viewer reaches the panel.
        _StepMachine = gym_sm::Setup(InHandle, UCk_InputGym_Step_ResetBaseline);

        _StepConfig.Description = "Key remapping, conflicts and resolution, checked as it goes.";
        _StepConfig.GlobalAutoCommand = "Ck_GymInput_Auto [0/1]";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_ResetBaseline,      "Start clean"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_RemapFree,          "Move to a free key"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_RemapOntoCrouch,    "Collide inside one category"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_RemapOntoInteract,  "Collide across categories"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_SwapJumpCrouch,     "Trade keys"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_UnbindConflict,     "Take a key by force"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_BatchRemap,         "Move several rows at once"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_InputGym_Step_ResetAndSave,       "Clean up and save"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_Gym_AutoSet,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoSet"));
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        input_gym_pc::Request_TeardownIfArmed();
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_sm::HandleAutoSet(InPayload, _StepMachine);
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto Lines = TArray<FCkGym_ColoredLine>();

        Add_DemoStatus(Lines);
        Add_StepVerdict(Lines, SelfEntity);
        Add_CurrentBindings(Lines, PlayerController);
        Add_CollisionPreview(Lines, PlayerController);
        Add_LastCommand(Lines);
        Add_Commands(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_DemoStatus(TArray<FCkGym_ColoredLine>& OutLines)
    {
        if (gym_sm::Get_IsAutoRunning(_StepMachine))
        {
            input_gym::Add_Line(OutLines, "  Demo is running on its own.", gym_palette::Cyan);
        }
        else
        {
            input_gym::Add_Line(OutLines, "  Demo is held. Run Ck_GymInput_Auto 1 to let it continue.", gym_palette::Grey);
        }

        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "WHAT THE DEMO DOES", gym_palette::White);
        input_gym::Add_SmSteps(OutLines, _StepConfig, _StepMachine);
    }

    private void Add_StepVerdict(TArray<FCkGym_ColoredLine>& OutLines, FCk_Handle& InSelfEntity)
    {
        auto& Verdict = InSelfEntity.AddOrGet_Fragment(FCkInputGym_StepVerdict);

        input_gym::Add_Spacer(OutLines, gym_palette::White);

        if (Verdict.StepLabel == "")
        {
            input_gym::Add_Line(OutLines, "THIS STEP — waiting for the first step to run", gym_palette::Grey);
            return;
        }

        input_gym::Add_Line(OutLines, f"THIS STEP — {Verdict.StepLabel}", gym_palette::White);
        input_gym::Add_Lines(OutLines, Verdict.Lines);
    }

    private void Add_CurrentBindings(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "KEYS RIGHT NOW", gym_palette::White);
        input_gym::Add_MappingRows(OutLines, InPlayerController);
    }

    // Asking about a collision changes nothing — this block is a read, run every
    // tick against whatever key Crouch currently holds.
    private void Add_CollisionPreview(TArray<FCkGym_ColoredLine>& OutLines, APlayerController InPlayerController)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "WOULD IT COLLIDE? (nothing is changed by asking)", gym_palette::White);

        auto CrouchKey = utils_key_binding::Get_KeyForMapping(
            InPlayerController, input_gym::k_Mapping_Crouch, EPlayerMappableKeySlot::First);

        if (CrouchKey.IsValid() == false)
        {
            input_gym::Add_Line(OutLines, "  Crouch is unbound right now — nothing to test against.", gym_palette::Grey);
            return;
        }

        input_gym::Add_ConflictPreview(OutLines, InPlayerController, input_gym::k_Mapping_Jump, CrouchKey);
    }

    private void Add_LastCommand(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, f"LAST COMMAND — {input_gym_pc::Get_RemapReportLabel()}", gym_palette::White);

        auto Report = input_gym_pc::Get_RemapReportLines();
        input_gym::Add_Lines(OutLines, Report);
    }

    private void Add_Commands(TArray<FCkGym_ColoredLine>& OutLines)
    {
        input_gym::Add_Spacer(OutLines, gym_palette::White);
        input_gym::Add_Line(OutLines, "TRY IT YOURSELF (any of these holds the demo)", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_RemapFree                 move Jump somewhere free", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_RemapTakenSameCategory    move Jump onto Crouch", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_RemapTakenCrossCategory   move Jump onto Interact", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_Swap                      Jump and Crouch trade", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_UnbindAndRemap            Jump takes, holder loses", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_RemapBatch                move two rows at once", gym_palette::Cyan);
        input_gym::Add_Line(OutLines, "  Ck_GymInput_Auto 1                    let the demo continue", gym_palette::Cyan);
    }
}
