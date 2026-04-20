// Language=angelscript

//============================================================================
// STATION 6: RESOLVER DATA BUNDLE
//============================================================================

class UCk_EntityScript_InteractionGym_DataBundle : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_ResolverSource ResolverSourceHandle;
    FCk_Handle_ResolverTarget ResolverTargetHandle;
    FCk_Handle_Timer AutoTimer;

    int32 ResolutionCount = 0;
    FString CurrentPhase = "N/A";
    float32 LastFinalValue = 0.0f;
    int32 PhasesCompleted = 0;
    bool AllPhasesComplete = false;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InteractionGym_DataBundle");

        auto Phases = TArray<FCk_Fragment_ResolverDataBundle_PhaseInfo>();
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Calculate"),
            ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata
        ));
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Apply"),
            ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata
        ));

        auto SourceParams = FCk_Fragment_ResolverSource_ParamsData(Phases);
        ResolverSourceHandle = utils_resolver_source::Add(InHandle, SourceParams);

        auto TargetParams = FCk_Fragment_ResolverTarget_ParamsData();
        ResolverTargetHandle = utils_resolver_target::Add(InHandle, TargetParams);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InteractionGym_InitiateResolution, FCk_Delegate_Messaging_OnBroadcast(this, n"OnInitiateResolution"));

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description = "ResolverSource + ResolverTarget with 2 phases.\nCalculate (base+bonus), Apply (multiplier).";
        AutoConfig.GlobalAutoCommand = "Ck_GymInteraction_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymInteraction_AutoDataBundle";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Initiate resolution", 0, 0));
        AutoConfig.ManualCommands.Add("Ck_GymInteraction_InitiateResolution");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void Request_InitiateResolution()
    {
        auto SelfEntity = ck::ToEntity(this);
        AllPhasesComplete = false;
        PhasesCompleted = 0;
        CurrentPhase = "Pending";

        auto BundleName = utils_gameplay_tag::ResolveGameplayTag(n"ResolverDataBundle.InteractionGym.Damage");

        auto InitialModifier = FCk_ResolverDataBundle_ModifierOperation(100.0f);
        InitialModifier.Set_ResolverComponent(ECk_ResolverDataBundle_ModifierComponent::BaseValue);
        InitialModifier.Set_ModifierOperation(ECk_ArithmeticOperations_Basic::Add);

        auto InitialModifierConditional = FCk_ResolverDataBundle_ModifierOperation_Conditional(FGameplayTagRequirements(), InitialModifier);

        auto Request = utils_resolver_source::Make_InitiateNewResolution(
            BundleName, ResolverTargetHandle, SelfEntity,
            FCk_ResolverDataBundle_MetadataOperation_Conditional(), InitialModifierConditional
        );

        utils_resolver_source::Request_InitiateNewResolution(
            ResolverSourceHandle, Request,
            FCk_Delegate_ResolverSource_OnNewResolverDataBundle(this, n"OnNewDataBundle")
        );

        ResolutionCount++;
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!AutoRunning) { return; }
        auto Step = AutoStep % AutoConfig.TotalSteps;
        if (Step == 0) { Request_InitiateResolution(); }
        AutoStep++;
    }

    UFUNCTION()
    private void OnInitiateResolution(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); Request_InitiateResolution(); }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    UFUNCTION()
    private void OnNewDataBundle(FCk_Handle_ResolverSource InSource, FCk_Handle InCauser, FCk_Handle_ResolverDataBundle InDataBundle)
    {
        utils_resolver_data_bundle::BindTo_OnPhaseStart(InDataBundle, FCk_Delegate_ResolverDataBundle_OnPhaseStart(this, n"OnPhaseStart"));
        utils_resolver_data_bundle::BindTo_OnPhaseComplete(InDataBundle, FCk_Delegate_ResolverDataBundle_OnPhaseComplete(this, n"OnPhaseComplete"));
        utils_resolver_data_bundle::BindTo_OnAllPhasesComplete(InDataBundle, FCk_Delegate_ResolverDataBundle_OnAllPhasesComplete(this, n"OnAllPhasesComplete"));
    }

    UFUNCTION()
    private void OnPhaseStart(FCk_Handle_ResolverDataBundle InDataBundle, FGameplayTag InPhase)
    {
        CurrentPhase = InPhase.ToString();

        auto CalculateTag = utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Calculate");
        if (InPhase == CalculateTag)
        {
            auto BonusModifier = FCk_ResolverDataBundle_ModifierOperation(25.0f);
            BonusModifier.Set_ResolverComponent(ECk_ResolverDataBundle_ModifierComponent::BonusValue);
            BonusModifier.Set_ModifierOperation(ECk_ArithmeticOperations_Basic::Add);
            auto BonusConditional = FCk_ResolverDataBundle_ModifierOperation_Conditional(FGameplayTagRequirements(), BonusModifier);
            utils_resolver_data_bundle::Request_AddOperation_Modifier(InDataBundle, ECk_ResolverDataBundle_PhaseSelection::ThisPhase, FCk_Request_ResolverDataBundle_ModifierOperation(BonusConditional));
        }

        auto ApplyTag = utils_gameplay_tag::ResolveGameplayTag(n"ResolverPhase.InteractionGym.Apply");
        if (InPhase == ApplyTag)
        {
            auto MultiplierModifier = FCk_ResolverDataBundle_ModifierOperation(1.5f);
            MultiplierModifier.Set_ResolverComponent(ECk_ResolverDataBundle_ModifierComponent::TotalMultiplier);
            MultiplierModifier.Set_ModifierOperation(ECk_ArithmeticOperations_Basic::Multiply);
            auto MultiplierConditional = FCk_ResolverDataBundle_ModifierOperation_Conditional(FGameplayTagRequirements(), MultiplierModifier);
            utils_resolver_data_bundle::Request_AddOperation_Modifier(InDataBundle, ECk_ResolverDataBundle_PhaseSelection::ThisPhase, FCk_Request_ResolverDataBundle_ModifierOperation(MultiplierConditional));
        }
    }

    UFUNCTION()
    private void OnPhaseComplete(FCk_Handle_ResolverDataBundle InDataBundle, FGameplayTag InPhase, FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        PhasesCompleted++;
        LastFinalValue = InPayload.Get_FinalValue();
    }

    UFUNCTION()
    private void OnAllPhasesComplete(FCk_Handle_ResolverDataBundle InDataBundle, FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        AllPhasesComplete = true;
        LastFinalValue = InPayload.Get_FinalValue();
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto CompleteStr = AllPhasesComplete ? "Yes" : "No";

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        DisplayText = f"{DisplayText}===== Resolution Stats =====\n";
        DisplayText = f"{DisplayText}Resolutions: {ResolutionCount}\n";
        DisplayText = f"{DisplayText}Phase: {CurrentPhase}\n";
        DisplayText = f"{DisplayText}Phases Done: {PhasesCompleted}  All Complete: {CompleteStr}\n";
        DisplayText = f"{DisplayText}Final Value: {LastFinalValue}\n\n";
        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"RESOLVER DATA BUNDLE {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }
}
