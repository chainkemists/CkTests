// Language=angelscript

//============================================================================
// STATION 4: ENABLE/DISABLE & VALIDATION
//============================================================================

class UCk_EntityScript_InteractionGym_Validation : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractTarget TargetHandle;
    FCk_Handle_Timer AutoTimer;

    bool IsTargetEnabled = true;
    bool CustomValidationAllowed = true;
    FString LastCanInteractResult = "N/A";
    int32 AttemptCount = 0;
    int32 SuccessCount = 0;
    int32 RejectedCount = 0;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    int32 AUTO_TOTAL_STEPS = 6;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_Validation");

        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        TargetParams.Set_CustomCanInteractWithDynamic(FCk_Delegate_InteractTarget_CanInteractWith(this, n"OnCanInteractWith"));
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(TargetHandle, FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AttemptValidation, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAttemptValidation"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_ToggleEnabled, FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleEnabled"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_ToggleCustomValidation, FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleCustomValidation"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AutoSet, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoSet"));

        // Auto timer
        auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.8f));
        AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
        AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void StopAuto() { if (AutoRunning) { AutoRunning = false; utils_timer::Request_Pause(AutoTimer); } }

    void Request_AttemptInteraction()
    {
        AttemptCount++;
        auto SelfEntity = ck::ToEntity(this);
        auto CanInteractResult = utils_interact_target::Get_CanInteractWith(TargetHandle, SelfEntity);

        if (CanInteractResult == ECk_CanInteractWithResult::CanInteractWith) { LastCanInteractResult = "CanInteractWith"; }
        else if (CanInteractResult == ECk_CanInteractWithResult::TargetDisabled) { LastCanInteractResult = "TargetDisabled"; RejectedCount++; }
        else if (CanInteractResult == ECk_CanInteractWithResult::CustomValidationFailed) { LastCanInteractResult = "CustomValidationFailed"; RejectedCount++; }
        else { LastCanInteractResult = "Other Rejection"; RejectedCount++; }

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SelfEntity);
        Request.Set_InteractInstigator(SelfEntity);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
    }

    void Request_ToggleEnabled()
    {
        IsTargetEnabled = !IsTargetEnabled;
        utils_interact_target::Set_Enabled(TargetHandle, IsTargetEnabled ? ECk_EnableDisable::Enable : ECk_EnableDisable::Disable);
    }

    void Request_ToggleCustomValidation()
    {
        CustomValidationAllowed = !CustomValidationAllowed;
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!AutoRunning) { return; }
        auto Step = AutoStep % AUTO_TOTAL_STEPS;
        if (Step == 0) { Request_AttemptInteraction(); }        // attempt (should succeed)
        else if (Step == 1) { Request_ToggleEnabled(); }        // disable target
        else if (Step == 2) { Request_AttemptInteraction(); }   // attempt (should be rejected: TargetDisabled)
        else if (Step == 3) { Request_ToggleEnabled(); }        // re-enable target
        else if (Step == 4) { Request_ToggleCustomValidation(); Request_AttemptInteraction(); } // block + attempt
        else if (Step == 5) { Request_ToggleCustomValidation(); }                               // unblock
        AutoStep++;
    }

    UFUNCTION()
    private void OnCanInteractWith(FCk_Handle_InteractTarget InTarget, FCk_Handle InInteractSource, FCk_Handle InInteractInstigator, bool& OutResult)
    {
        OutResult = CustomValidationAllowed;
    }

    UFUNCTION()
    private void OnNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction) { SuccessCount++; }

    UFUNCTION()
    private void OnAttemptValidation(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_AttemptInteraction(); }
    UFUNCTION()
    private void OnToggleEnabled(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_ToggleEnabled(); }
    UFUNCTION()
    private void OnToggleCustomValidation(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_ToggleCustomValidation(); }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Msg = InPayload.Get(FCk_Message_InteractionGym_AutoSet);
        AutoRunning = Msg.Enabled;
        if (AutoRunning) { utils_timer::Request_Resume(AutoTimer); }
        else { utils_timer::Request_Pause(AutoTimer); }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto EnabledStr = IsTargetEnabled ? "Enabled" : "Disabled";
        auto ValidationStr = CustomValidationAllowed ? "Allowed" : "Blocked";
        auto StepMarker = AutoRunning ? (AutoStep % AUTO_TOTAL_STEPS) : -1;

        auto DisplayText = "";
        DisplayText = DisplayText + interaction_gym_helpers::AutoStatusLine(AutoRunning) + "\n";
        DisplayText = f"{DisplayText}Custom CanInteractWith validation + enable/disable.\n\n";
        DisplayText = f"{DisplayText}===== Validation Stats =====\n";
        DisplayText = f"{DisplayText}Target: {EnabledStr}  Validation: {ValidationStr}\n";
        DisplayText = f"{DisplayText}Last CanInteract: {LastCanInteractResult}\n";
        DisplayText = f"{DisplayText}Attempts: {AttemptCount}  OK: {SuccessCount}  Rejected: {RejectedCount}\n\n";
        DisplayText = f"{DisplayText}===== Auto Sequence =====\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 0) + " Attempt interaction (expect OK)\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 1) + " Disable target\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 2) + " Attempt interaction (expect Disabled)\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 3) + " Re-enable target\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 4) + " Block validation + attempt\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 5) + " Unblock validation\n\n";
        DisplayText = f"{DisplayText}===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AttemptValidation\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_ToggleEnabled\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_ToggleCustomValidation\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoOn / AutoOff\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoValidation\n";

        CkGym_Common::Update_StationDisplay(SelfEntity, "ENABLE/DISABLE & VALIDATION", DisplayText, "");
    }
}
