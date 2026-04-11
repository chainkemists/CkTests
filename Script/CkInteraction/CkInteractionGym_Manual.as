// Language=angelscript

//============================================================================
// STATION 3: MANUAL INTERACTION
//============================================================================

class UCk_EntityScript_InteractionGym_Manual : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractTarget TargetHandle;
    FCk_Handle_Interaction ActiveInteraction;
    FCk_Handle_Timer AutoTimer;

    int32 SuccessCount = 0;
    int32 FailCount = 0;
    int32 CancelCount = 0;
    FString CurrentState = "Idle";
    FString LastResult = "N/A";
    bool AutoRunning = true;
    int32 AutoStep = 0;
    int32 AUTO_TOTAL_STEPS = 4;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_Manual");

        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::ManuallyCompleted);
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(TargetHandle, FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(TargetHandle, FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_StartManual, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStartManual"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_EndManualSuccess, FCk_Delegate_Messaging_OnBroadcast(this, n"OnEndManualSuccess"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_EndManualFail, FCk_Delegate_Messaging_OnBroadcast(this, n"OnEndManualFail"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_CancelManual, FCk_Delegate_Messaging_OnBroadcast(this, n"OnCancelManual"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AutoSet, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoSet"));

        // Auto timer
        auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.0f));
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

    void Request_StartManual()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SelfEntity);
        Request.Set_InteractInstigator(SelfEntity);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
    }

    void Request_EndSuccess()
    {
        if (!ck::IsValid(ActiveInteraction)) { return; }
        utils_interaction::Request_EndInteraction(ActiveInteraction, FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Succeeded));
    }

    void Request_EndFail()
    {
        if (!ck::IsValid(ActiveInteraction)) { return; }
        utils_interaction::Request_EndInteraction(ActiveInteraction, FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Failed));
    }

    void Request_Cancel()
    {
        if (!ck::IsValid(ActiveInteraction)) { return; }
        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Request_InteractTarget_CancelInteraction();
        Request.Set_InteractSource(SelfEntity);
        utils_interact_target::Request_CancelInteraction(TargetHandle, Request);
        CancelCount++;
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!AutoRunning) { return; }
        auto Step = AutoStep % AUTO_TOTAL_STEPS;
        if (Step == 0) { Request_StartManual(); }
        else if (Step == 1) { Request_EndSuccess(); }
        else if (Step == 2) { Request_StartManual(); }
        else if (Step == 3) { Request_EndFail(); }
        AutoStep++;
    }

    UFUNCTION()
    private void OnStartManual(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_StartManual(); }
    UFUNCTION()
    private void OnEndManualSuccess(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_EndSuccess(); }
    UFUNCTION()
    private void OnEndManualFail(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_EndFail(); }
    UFUNCTION()
    private void OnCancelManual(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_Cancel(); }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Msg = InPayload.Get(FCk_Message_InteractionGym_AutoSet);
        AutoRunning = Msg.Enabled;
        if (AutoRunning) { utils_timer::Request_Resume(AutoTimer); }
        else { utils_timer::Request_Pause(AutoTimer); }
    }

    UFUNCTION()
    private void OnNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction)
    {
        ActiveInteraction = InInteraction;
        CurrentState = "Active";
    }

    UFUNCTION()
    private void OnInteractionFinished(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        ActiveInteraction = utils_interaction::Get_InvalidHandle();
        CurrentState = "Idle";
        if (SucceededFailed == ECk_SucceededFailed::Succeeded) { SuccessCount++; LastResult = "Succeeded"; }
        else { FailCount++; LastResult = "Failed"; }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto ActiveCount = utils_interact_target::Get_CurrentInteractions(TargetHandle).Num();
        auto StepMarker = AutoRunning ? (AutoStep % AUTO_TOTAL_STEPS) : -1;

        auto DisplayText = "";
        DisplayText = DisplayText + interaction_gym_helpers::AutoStatusLine(AutoRunning) + "\n";
        DisplayText = f"{DisplayText}ManuallyCompleted policy - explicit end/cancel required.\n\n";
        DisplayText = f"{DisplayText}===== Interaction Stats =====\n";
        DisplayText = f"{DisplayText}State: {CurrentState}  Active: {ActiveCount}\n";
        DisplayText = f"{DisplayText}Successes: {SuccessCount}  Failures: {FailCount}  Cancels: {CancelCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n\n";
        DisplayText = f"{DisplayText}===== Auto Sequence =====\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 0) + " Start manual interaction\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 1) + " End with success\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 2) + " Start manual interaction\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 3) + " End with failure\n\n";
        DisplayText = f"{DisplayText}===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_StartManual\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_EndManualSuccess\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_EndManualFail\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_CancelManual\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoOn / AutoOff\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoManual\n";

        CkGym_Common::Update_StationDisplay(SelfEntity, "MANUAL INTERACTION", DisplayText, "");
    }
}
