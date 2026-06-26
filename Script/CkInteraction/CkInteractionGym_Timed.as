// Language=angelscript

//============================================================================
// STATION 2: TIMED INTERACTION - SOURCE ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_TimedSource : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

class UCk_EntityScript_InteractionGym_TimedTarget : UCk_GenericEntityScript_UE
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

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(4.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description = "Source + target on separate entities, Timed (3s).\nDisplays elapsed time and completion tracking.";
        AutoConfig.GlobalAutoCommand = "Ck_GymInteraction_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymInteraction_AutoTimed";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Start timed interaction (every 4s)", 0, 0));
        AutoConfig.ManualCommands.Add("Ck_GymInteraction_StartTimed");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

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
        auto Step = AutoStep % AutoConfig.TotalSteps;
        if (Step == 0) { Request_StartTimedInteraction(); }
        AutoStep++;
    }

    UFUNCTION()
    private void OnStartTimed(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_StartTimedInteraction();
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
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

        auto ElapsedStr = "0.00";
        auto DurationStr = "3.00";
        if (ck::IsValid(ActiveInteraction))
        {
            auto Elapsed = utils_interaction::Get_InteractionTimeElapsed(ActiveInteraction);
            auto Duration = utils_interaction::Get_InteractionDuration(ActiveInteraction);
            ElapsedStr = f"{Elapsed.Get_Seconds()}";
            DurationStr = f"{Duration.Get_Seconds()}";
        }

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        DisplayText = f"{DisplayText}===== Interaction Stats =====\n";
        DisplayText = f"{DisplayText}State: {CurrentState}\n";
        DisplayText = f"{DisplayText}Elapsed: {ElapsedStr}s / {DurationStr}s\n";
        DisplayText = f"{DisplayText}Completions: {CompletionCount}\n";
        DisplayText = f"{DisplayText}Last Result: {LastResult}\n\n";
        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"TIMED INTERACTION {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }
}
