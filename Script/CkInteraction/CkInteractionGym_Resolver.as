// Language=angelscript

//============================================================================
// STATION 5: INTERACTION RESOLVER - SOURCE ENTITY (with resolver)
//============================================================================

class UCk_EntityScript_InteractionGym_ResolverSource : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractSource SourceHandle;
    FCk_Handle_InteractionResolver ResolverHandle;
    FCk_Handle_Timer AutoTimer;

    int32 BestTargetCount = 0;
    bool IntentActive = false;
    int32 TargetChangedCount = 0;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_ResolverSource");

        auto SourceParams = FCk_InteractSource_Spec();
        SourceParams._InteractionChannel = interaction_gym_helpers::DefaultChannel();
        SourceHandle = utils_interact_source::Add(InHandle, SourceParams);

        auto Channels = TArray<FGameplayTag>();
        Channels.Add(interaction_gym_helpers::DefaultChannel());
        Channels.Add(interaction_gym_helpers::SecondaryChannel());

        auto Mapping = FCk_InteractionResolver_IntentChannelMapping(
            interaction_gym_helpers::UseIntent(),
            Channels
        );
        Mapping.Set_DistanceSorting(ECk_InteractionResolver_DistanceSorting::Enabled);
        Mapping.Set_MaxConcurrentInteractions(1);

        auto Mappings = TArray<FCk_InteractionResolver_IntentChannelMapping>();
        Mappings.Add(Mapping);

        auto ResolverParams = FCk_InteractionResolver_Spec(Mappings);
        ResolverHandle = utils_interaction_resolver::Add(InHandle, ResolverParams);

        utils_interaction_resolver::BindTo_OnBestTargetsChanged(ResolverHandle, FCk_Delegate_InteractionResolver_OnBestTargetsChanged(this, n"OnBestTargetsChanged"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_StartIntent, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStartIntent"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_StopIntent, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStopIntent"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_AddTargets, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddTargets"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_RemoveTargets, FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveTargets"));

        auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.5f));

        AutoConfig.TotalSteps = 4;
        AutoConfig.Description = "Resolver with distance sorting, 3 targets.";
        AutoConfig.GlobalAutoCommand = "Ck_GymInteraction_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymInteraction_AutoResolver";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add 3 targets", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Start intent", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Stop intent", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Remove targets", 3, 3));
        AutoConfig.ManualCommands.Add("Ck_GymInteraction_StartIntent");
        AutoConfig.ManualCommands.Add("Ck_GymInteraction_StopIntent");
        AutoConfig.ManualCommands.Add("Ck_GymInteraction_AddTarget");
        AutoConfig.ManualCommands.Add("Ck_GymInteraction_RemoveTarget");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void Request_StartIntent()
    {
        auto Request = FCk_Request_InteractionResolver_StartIntent(interaction_gym_helpers::UseIntent());
        utils_interaction_resolver::Request_StartIntent(ResolverHandle, Request);
        IntentActive = true;
    }

    void Request_StopIntent()
    {
        auto Request = FCk_Request_InteractionResolver_StopIntent(interaction_gym_helpers::UseIntent());
        utils_interaction_resolver::Request_StopIntent(ResolverHandle, Request);
        IntentActive = false;
    }

    void Request_AddTargets()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TargetEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_InteractionGym_ResolverTarget");
        for (auto TargetEntity : TargetEntities)
        {
            auto TgtHandle = utils_interact_target::TryGet(TargetEntity, interaction_gym_helpers::DefaultChannel());
            if (ck::IsValid(TgtHandle))
            {
                utils_interaction_resolver::Request_AddInteractTarget(ResolverHandle, FCk_Request_InteractionResolver_AddInteractTarget(TgtHandle));
            }
        }
    }

    void Request_RemoveTargets()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TargetEntities = utils_entity_tag::ForEach_Entity(SelfEntity, n"TAG_InteractionGym_ResolverTarget");
        for (auto TargetEntity : TargetEntities)
        {
            auto TgtHandle = utils_interact_target::TryGet(TargetEntity, interaction_gym_helpers::DefaultChannel());
            if (ck::IsValid(TgtHandle))
            {
                utils_interaction_resolver::Request_RemoveInteractTarget(ResolverHandle, FCk_Request_InteractionResolver_RemoveInteractTarget(TgtHandle));
            }
        }
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!AutoRunning) { return; }
        auto Step = AutoStep % AutoConfig.TotalSteps;
        if (Step == 0) { Request_AddTargets(); }
        else if (Step == 1) { Request_StartIntent(); }
        else if (Step == 2) { Request_StopIntent(); }
        else if (Step == 3) { Request_RemoveTargets(); }
        AutoStep++;
    }

    UFUNCTION()
    private void OnBestTargetsChanged(FCk_Handle_InteractionResolver InResolver, FGameplayTag InIntent, const TArray<FCk_Handle_InteractTarget>&in InPreviousTargets, const TArray<FCk_Handle_InteractTarget>&in InNewTargets, const TArray<FCk_Handle_InteractTarget>&in InRemovedTargets)
    {
        BestTargetCount = InNewTargets.Num();
        TargetChangedCount++;
    }

    UFUNCTION()
    private void OnStartIntent(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); Request_StartIntent(); }
    UFUNCTION()
    private void OnStopIntent(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); Request_StopIntent(); }
    UFUNCTION()
    private void OnAddTargets(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); Request_AddTargets(); }
    UFUNCTION()
    private void OnRemoveTargets(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); Request_RemoveTargets(); }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto IntentStr = IntentActive ? "Active" : "Inactive";
        auto CurrentBestTargets = utils_interaction_resolver::Get_BestInteractTargets(ResolverHandle, interaction_gym_helpers::UseIntent());

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        DisplayText = f"{DisplayText}===== Resolver Stats =====\n";
        DisplayText = f"{DisplayText}Intent: {IntentStr}\n";
        DisplayText = f"{DisplayText}Best Targets: {CurrentBestTargets.Num()}\n";
        DisplayText = f"{DisplayText}Changed Events: {TargetChangedCount}\n\n";
        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"INTERACTION RESOLVER {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }
}

//============================================================================
// STATION 5: INTERACTION RESOLVER - TARGET ENTITY
//============================================================================

class UCk_EntityScript_InteractionGym_ResolverTarget : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_InteractTarget TargetHandle;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_ResolverTarget");

        auto TargetParams = FCk_InteractTarget_Spec(
            interaction_gym_helpers::DefaultChannel()
        );
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        TargetHandle = utils_interact_target::Add(InHandle, TargetParams);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
