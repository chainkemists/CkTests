// Language=angelscript

//============================================================================
// INTERACTION GYM - INSTANT INTERACTION
//============================================================================

class UCk_EntityScript_InteractionGym_Instant : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractTarget TargetHandle;
    FCk_Handle_Timer AutoTimer;

    int32 InteractionCount = 0;
    FString LastResult = "N/A";
    bool AutoRunning = true;
    int32 AutoStep = 0;
    int32 AUTO_TOTAL_STEPS = 1;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_Instant");

        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_source::BindTo_OnNewInteraction(SourceHandle, FCk_Delegate_InteractSource_OnNewInteraction(this, n"OnSourceNewInteraction"));
        utils_interact_source::BindTo_OnInteractionFinished(SourceHandle, FCk_Delegate_InteractSource_OnInteractionFinished(this, n"OnSourceInteractionFinished"));
        utils_interact_target::BindTo_OnNewInteraction(TargetHandle, FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnTargetNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(TargetHandle, FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnTargetInteractionFinished"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_TriggerInstant, FCk_Delegate_Messaging_OnBroadcast(this, n"OnTriggerInstant"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AutoSet, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoSet"));

        auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
        AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void StopAuto() { if (AutoRunning) { AutoRunning = false; utils_timer::Request_Pause(AutoTimer); } }

    void Request_TriggerInteraction()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SelfEntity);
        Request.Set_InteractInstigator(SelfEntity);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!AutoRunning) { return; }
        auto Step = AutoStep % AUTO_TOTAL_STEPS;
        if (Step == 0) { Request_TriggerInteraction(); }
        AutoStep++;
    }

    UFUNCTION()
    private void OnTriggerInstant(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { StopAuto(); Request_TriggerInteraction(); }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Msg = InPayload.Get(FCk_Message_InteractionGym_AutoSet);
        AutoRunning = Msg.Enabled;
        if (AutoRunning) { utils_timer::Request_Resume(AutoTimer); }
        else { utils_timer::Request_Pause(AutoTimer); }
    }

    UFUNCTION()
    private void OnSourceNewInteraction(FCk_Handle_InteractSource InSource, FCk_Handle_Interaction InInteraction) {}
    UFUNCTION()
    private void OnSourceInteractionFinished(FCk_Handle_InteractSource InSource, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed) {}

    UFUNCTION()
    private void OnTargetNewInteraction(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction) { InteractionCount++; }

    UFUNCTION()
    private void OnTargetInteractionFinished(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        LastResult = (SucceededFailed == ECk_SucceededFailed::Succeeded) ? "Succeeded" : "Failed";
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto StepMarker = AutoRunning ? (AutoStep % AUTO_TOTAL_STEPS) : -1;

        auto DisplayText = "";
        DisplayText = DisplayText + interaction_gym_helpers::AutoStatusLine(AutoRunning) + "\n";
        DisplayText = f"{DisplayText}Source + target on same entity, Instant completion.\n\n";
        DisplayText = f"{DisplayText}===== Interaction Stats =====\n";
        DisplayText = f"{DisplayText}Interactions: {InteractionCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n";
        DisplayText = f"{DisplayText}Source Valid: {ck::IsValid(SourceHandle)}\n";
        DisplayText = f"{DisplayText}Target Valid: {ck::IsValid(TargetHandle)}\n\n";
        DisplayText = f"{DisplayText}===== Auto Sequence =====\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 0) + " Trigger instant interaction\n\n";
        DisplayText = f"{DisplayText}===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_TriggerInstant\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoOn / AutoOff\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoInstant\n";

        CkGym_Common::Update_StationDisplay(SelfEntity, "INSTANT INTERACTION", DisplayText, "");
    }
}
