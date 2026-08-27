// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM - DEMO STEP STATES
//============================================================================
//
// The Remap + Conflict station's demo sequence, as a CkStateMachine graph. It
// runs on its own from the moment the station constructs: a viewer who walks up
// to the panel sees the whole key-binding surface exercised and checked without
// typing a command.
//
//   ResetBaseline -> RemapFree -> RemapOntoCrouch -> RemapOntoInteract
//                 -> SwapJumpCrouch -> UnbindConflict -> BatchRemap
//                 -> ResetAndSave -> (back to ResetBaseline)
//
// EVERY STEP ASSERTS. A step reads what it expects BEFORE it mutates anything,
// performs the mutation, reads back, and publishes an EXPECT/GOT verdict the
// station renders green or red. That is the difference between a demo that
// shows key bindings changing and one that tells you they changed correctly.
//
// NOTHING HERE TOUCHES A SCRIPT'S MEMBERS. A step state is its own entity
// script; the key profile is reached through the local PlayerController (a key
// profile belongs to the local player, not to any entity) and the verdict is
// written to the station ENTITY as a fragment, found by the private tag the
// station adds to itself.
//
// EVERY WATCHED ROW MOVES ONCE PER CYCLE. Jump moves constantly, Crouch moves
// at the swap and the batch, and Interact and Flashlight both ride the batch.
// Interact rides it rather than relying on the unbind-and-remap step, which
// leaves it UNBOUND rather than on a key. That is deliberate - the Change
// Signal station asserts that every row's listener has fired, and a row the
// loop never touches would leave that panel permanently red.
//
// The cycle closes on a reset-and-save so an unattended demo cannot leave a
// customized profile on disk between laps (the CkInput docs anti-pattern 2).
//============================================================================

namespace input_gym_demo
{
    // Every step publishes to the same station.
    void Publish(FCk_Handle InAnyEntity, FString InStepLabel, TArray<FCkGym_ColoredLine>& InLines)
    {
        input_gym::Write_StepVerdict(InAnyEntity, input_gym::k_Tag_RemapConflict, InStepLabel, InLines);
    }

    FKey Get_Key(APlayerController InPlayerController, FName InMappingName)
    {
        return utils_key_binding::Get_KeyForMapping(InPlayerController, InMappingName, EPlayerMappableKeySlot::First);
    }

    FString Get_KeyText(APlayerController InPlayerController, FName InMappingName)
    {
        return input_gym::Format_Key(Get_Key(InPlayerController, InMappingName));
    }

    // A step that cannot run its mutation still has to say so on the panel,
    // otherwise the previous step's verdict sits there looking current.
    void Publish_Refusal(FCk_Handle InAnyEntity, FString InStepLabel, FString InReason)
    {
        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, f"  step could not run: {InReason}", gym_palette::Red);
        Publish(InAnyEntity, InStepLabel, Lines);
    }
}

// ====================================================================================================================

UCLASS()
class UCk_InputGym_Step_ResetBaseline : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_RemapFree);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto ExpectedJump = input_gym::Format_Key(
            input_gym::Get_DefaultKeyForMapping(PlayerController, input_gym::k_Mapping_Jump));

        utils_key_binding::ResetAllToDefaults(PlayerController);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Every row put back to the key it was authored with.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "rows on their default key",
            f"{input_assets::k_MappableRowCount}",
            f"{input_gym::Get_RowsAtDefaultCount(PlayerController)}");
        input_gym::Add_Verdict(Lines, "Jump", ExpectedJump,
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));

        input_gym_demo::Publish(Station, "Start clean", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_RemapFree : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_RemapOntoCrouch);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        // Read the collision BEFORE the remap: afterwards Jump holds the key
        // too, so the report would describe the aftermath instead of the
        // decision the caller had to make.
        auto Holders = input_gym::Format_ConflictHolders(input_gym::Get_ConflictsFor(
            PlayerController, input_gym::k_Mapping_Jump, input_gym::k_FreeKey, ECk_KeyConflictScope::All));

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKey(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First,
            input_gym::k_FreeKey, FailureReason);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, f"  Jump moved to {input_gym::Format_Key(input_gym::k_FreeKey)}, which nobody else holds.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "anyone already on that key", "(none)", Holders);
        input_gym::Add_Verdict(Lines, "remap accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(input_gym::k_FreeKey),
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));

        input_gym_demo::Publish(Station, "Move to a free key", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_RemapOntoCrouch : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_RemapOntoInteract);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto CrouchKey = input_gym_demo::Get_Key(PlayerController, input_gym::k_Mapping_Crouch);
        if (CrouchKey.IsValid() == false)
        {
            input_gym_demo::Publish_Refusal(Station, "Collide inside one category", "Crouch holds no key to collide with.");
            return;
        }

        auto SameCategory = input_gym::Format_ConflictHolders(input_gym::Get_ConflictsFor(
            PlayerController, input_gym::k_Mapping_Jump, CrouchKey, ECk_KeyConflictScope::SameCategory));

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKey(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, CrouchKey, FailureReason);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Jump took Crouch's key. Both are Movement, so this collides", gym_palette::White);
        input_gym::Add_Line(Lines, "  even when only same-category collisions are asked about.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "same-category holder",
            input_gym::Format_MappingIdentity(input_assets::IA_CkTests_Crouch), SameCategory);
        input_gym::Add_Verdict(Lines, "remap accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(CrouchKey),
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));

        input_gym_demo::Publish(Station, "Collide inside one category", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_RemapOntoInteract : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_SwapJumpCrouch);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto InteractKey = input_gym_demo::Get_Key(PlayerController, input_gym::k_Mapping_Interact);
        if (InteractKey.IsValid() == false)
        {
            input_gym_demo::Publish_Refusal(Station, "Collide across categories", "Interact holds no key to collide with.");
            return;
        }

        auto AnyCategory = input_gym::Format_ConflictHolders(input_gym::Get_ConflictsFor(
            PlayerController, input_gym::k_Mapping_Jump, InteractKey, ECk_KeyConflictScope::All));
        auto SameCategory = input_gym::Format_ConflictHolders(input_gym::Get_ConflictsFor(
            PlayerController, input_gym::k_Mapping_Jump, InteractKey, ECk_KeyConflictScope::SameCategory));

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKey(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, InteractKey, FailureReason);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Jump took Interact's key. Movement against Interaction, so this", gym_palette::White);
        input_gym::Add_Line(Lines, "  only shows up when collisions across categories are asked about.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "any-category holder",
            input_gym::Format_MappingIdentity(input_assets::IA_CkTests_Interact), AnyCategory);
        input_gym::Add_Verdict(Lines, "same-category holder", "(none)", SameCategory);
        input_gym::Add_Verdict(Lines, "remap accepted", "yes", input_gym::Format_Bool(Succeeded));

        input_gym_demo::Publish(Station, "Collide across categories", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_SwapJumpCrouch : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_UnbindConflict);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto JumpBefore = input_gym_demo::Get_Key(PlayerController, input_gym::k_Mapping_Jump);
        auto CrouchBefore = input_gym_demo::Get_Key(PlayerController, input_gym::k_Mapping_Crouch);

        // SwapKeys leaves OldKey at Invalid when the source row holds no key and
        // then assigns that Invalid to whoever held the target key, silently
        // unbinding them. Refuse rather than demonstrate the trap by accident.
        if (JumpBefore.IsValid() == false || CrouchBefore.IsValid() == false)
        {
            input_gym_demo::Publish_Refusal(Station, "Trade keys", "both rows have to be bound before they can trade.");
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::SwapKeys(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, CrouchBefore, FailureReason);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Jump and Crouch trade keys in one call - neither is left unbound.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "swap accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(CrouchBefore),
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));
        input_gym::Add_Verdict(Lines, "Crouch", input_gym::Format_Key(JumpBefore),
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Crouch));

        input_gym_demo::Publish(Station, "Trade keys", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_UnbindConflict : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_BatchRemap);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto InteractKey = input_gym_demo::Get_Key(PlayerController, input_gym::k_Mapping_Interact);
        if (InteractKey.IsValid() == false)
        {
            input_gym_demo::Publish_Refusal(Station, "Take a key by force", "Interact holds no key to take.");
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::UnbindConflictAndRemap(
            PlayerController, input_gym::k_Mapping_Jump, EPlayerMappableKeySlot::First, InteractKey, FailureReason);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Jump takes Interact's key outright. The previous holder keeps", gym_palette::White);
        input_gym::Add_Line(Lines, "  nothing - this is the resolution that unbinds instead of trading.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "take accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", input_gym::Format_Key(InteractKey),
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));
        input_gym::Add_Verdict(Lines, "Interact (previous holder)", "<unbound>",
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Interact));

        input_gym_demo::Publish(Station, "Take a key by force", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_BatchRemap : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_ResetAndSave);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto Names = TArray<FName>();
        Names.Add(input_gym::k_Mapping_Jump);
        Names.Add(input_gym::k_Mapping_Crouch);
        Names.Add(input_gym::k_Mapping_Interact);
        Names.Add(input_gym::k_Mapping_Flashlight);

        // RemapKeys reports success for an EMPTY name array, so an empty batch
        // would read as a passing no-op.
        if (Names.Num() == 0)
        {
            input_gym_demo::Publish_Refusal(Station, "Move several rows at once", "nothing was named in the batch.");
            return;
        }

        FGameplayTagContainer FailureReason;
        auto Succeeded = utils_key_binding::RemapKeys(
            PlayerController, Names, EPlayerMappableKeySlot::First, input_gym::k_BatchKey, FailureReason);

        auto BatchKeyText = input_gym::Format_Key(input_gym::k_BatchKey);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, f"  Four rows land on {BatchKeyText} in a single call.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "batch accepted", "yes", input_gym::Format_Bool(Succeeded));
        input_gym::Add_Verdict(Lines, "Jump", BatchKeyText,
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));
        input_gym::Add_Verdict(Lines, "Crouch", BatchKeyText,
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Crouch));
        input_gym::Add_Verdict(Lines, "Interact", BatchKeyText,
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Interact));
        input_gym::Add_Verdict(Lines, "Flashlight", BatchKeyText,
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Flashlight));

        input_gym_demo::Publish(Station, "Move several rows at once", Lines);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InputGym_Step_ResetAndSave : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InputGym_Step_ResetBaseline);
        AddCondition(Trans, UCk_Gym_Dwell);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Station = Get_StationEntity();
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto ExpectedJump = input_gym::Format_Key(
            input_gym::Get_DefaultKeyForMapping(PlayerController, input_gym::k_Mapping_Jump));

        input_gym::Request_ResetAllAndSave(PlayerController);

        auto Lines = TArray<FCkGym_ColoredLine>();
        input_gym::Add_Line(Lines, "  Everything back to its authored key, and the saved copy on disk", gym_palette::White);
        input_gym::Add_Line(Lines, "  overwritten to match, so no lap of the demo leaves residue.", gym_palette::White);
        input_gym::Add_Verdict(Lines, "rows on their default key",
            f"{input_assets::k_MappableRowCount}",
            f"{input_gym::Get_RowsAtDefaultCount(PlayerController)}");
        input_gym::Add_Verdict(Lines, "Jump", ExpectedJump,
            input_gym_demo::Get_KeyText(PlayerController, input_gym::k_Mapping_Jump));

        input_gym_demo::Publish(Station, "Clean up and save", Lines);
    }
}
