// Language=angelscript

//============================================================================
// STATION 2: TIMED INTERACTION - SOURCE ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_TimedSource : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_TimedSource");

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = interaction_gym_helpers::DefaultChannel();
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

//============================================================================
// STATION 2: TIMED INTERACTION - TARGET ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_TimedTarget : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractTarget TargetHandle;
    FCk_Handle_Interaction ActiveInteraction;
    FCk_Handle_Timer AutoTimer;

    int32 CompletionCount = 0;
    FString CurrentState = "Idle";
    FString LastResult = "N/A";
    bool AutoRunning = true;
    int32 AutoStep = 0;
    int32 AUTO_TOTAL_STEPS = 1;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_TimedTarget");

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(
            interaction_gym_helpers::DefaultChannel()
        );
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Timed);
        TargetParams.Set_InteractionDuration(FCk_Time(3.0f));
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(TargetHandle, FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(TargetHandle, FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_StartTimed, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStartTimed"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AutoSet, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoSet"));

        // Auto timer (4s interval — enough for 3s timed interaction to complete)
        auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(4.0f));
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

    void Request_StartTimedInteraction()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto SourceEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_InteractionGym_TimedSource");
        if (SourceEntities.Num() == 0) { return; }

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SourceEntities[0]);
        Request.Set_InteractInstigator(SourceEntities[0]);
        utils_interact_target::Request_StartInteraction(TargetHandle, Request);
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!AutoRunning) { return; }
        auto Step = AutoStep % AUTO_TOTAL_STEPS;
        if (Step == 0) { Request_StartTimedInteraction(); }
        AutoStep++;
    }

    UFUNCTION()
    private void OnStartTimed(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        StopAuto();
        Request_StartTimedInteraction();
    }

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
        CurrentState = "In Progress";
    }

    UFUNCTION()
    private void OnInteractionFinished(FCk_Handle_InteractTarget InTarget, FCk_Handle_Interaction InInteraction, ECk_SucceededFailed SucceededFailed)
    {
        ActiveInteraction = utils_interaction::Get_InvalidHandle();
        CurrentState = "Idle";
        CompletionCount++;
        LastResult = (SucceededFailed == ECk_SucceededFailed::Succeeded) ? "Succeeded" : "Failed";
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto StepMarker = AutoRunning ? (AutoStep % AUTO_TOTAL_STEPS) : -1;

        auto ElapsedStr = "0.00";
        auto DurationStr = "3.00";
        if (ck::IsValid(ActiveInteraction))
        {
            auto Elapsed = utils_interaction::Get_InteractionTimeElapsed(ActiveInteraction);
            auto Duration = utils_interaction::Get_InteractionDuration(ActiveInteraction);
            ElapsedStr = f"{Elapsed.Get_Seconds()}";
            DurationStr = f"{Duration.Get_Seconds()}";
        }

        auto DisplayText = "";
        DisplayText = DisplayText + interaction_gym_helpers::AutoStatusLine(AutoRunning) + "\n";
        DisplayText = f"{DisplayText}Source + target on separate entities, Timed (3s).\n\n";
        DisplayText = f"{DisplayText}===== Interaction Stats =====\n";
        DisplayText = f"{DisplayText}State: {CurrentState}\n";
        DisplayText = f"{DisplayText}Elapsed: {ElapsedStr}s / {DurationStr}s\n";
        DisplayText = f"{DisplayText}Completions: {CompletionCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n\n";
        DisplayText = f"{DisplayText}===== Auto Sequence =====\n";
        DisplayText = DisplayText + interaction_gym_helpers::StepPrefix(StepMarker, 0) + " Start timed interaction (every 4s)\n\n";
        DisplayText = f"{DisplayText}===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_StartTimed\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoOn / AutoOff\n";
        DisplayText = f"{DisplayText}Ck_GymInteraction_AutoTimed\n";

        CkGym_Common::Update_StationDisplay(SelfEntity, "TIMED INTERACTION", DisplayText, "");
    }
}
