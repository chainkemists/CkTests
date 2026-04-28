// Language=angelscript

//============================================================================
// INTERACTION GYM - PLAYER CONTROLLER
//============================================================================

class ACk_InteractionGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Instant");
            Station.Title = FText::FromString("INSTANT INTERACTION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Source and target on same entity with Instant completion."));
            Description.Add(FText::FromString("Tests OnNewInteraction and OnInteractionFinished signals."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Timed");
            Station.Title = FText::FromString("TIMED INTERACTION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Source and target on separate entities with 3s timed completion."));
            Description.Add(FText::FromString("Displays elapsed time and completion tracking."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Manual");
            Station.Title = FText::FromString("MANUAL INTERACTION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("ManuallyCompleted policy - must explicitly end or cancel."));
            Description.Add(FText::FromString("Tests EndInteraction with Succeeded/Failed and CancelInteraction."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Validation");
            Station.Title = FText::FromString("ENABLE/DISABLE & VALIDATION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Target with custom CanInteractWith validation delegate."));
            Description.Add(FText::FromString("Toggle enabled state and custom validation to test rejection."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Resolver");
            Station.Title = FText::FromString("INTERACTION RESOLVER");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Resolver with intent-channel mapping and distance sorting."));
            Description.Add(FText::FromString("Source + 3 targets at varying distances."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.DataBundle");
            Station.Title = FText::FromString("RESOLVER DATA BUNDLE");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("ResolverSource + ResolverTarget with phased resolution."));
            Description.Add(FText::FromString("Calculate phase (base+bonus) then Apply phase (multiplier)."));
            Station.Description = Description;
            Station.AutoSize = true;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartInstantStation();
        Request_StartTimedStation();
        Request_StartManualStation();
        Request_StartValidationStation();
        Request_StartResolverStation();
        Request_StartDataBundleStation();
        ck::Trace("Interaction Gym - All stations started");
    }

    //------------------------------------------------------------------------
    // STATION STARTUP FUNCTIONS
    //------------------------------------------------------------------------

    void Request_StartInstantStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Interaction.Instant", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Instant"),
            UCk_EntityScript_InteractionGym_Instant,
            FInstancedStruct::Make(FInteractionGymSpawnParams(StationTransform))
        );
        if (ck::IsValid(SpawnRequest)) { ck::Trace("✅ [Instant] started"); }
        else { ck::Error("❌ Failed to spawn [Instant]"); }
    }

    void Request_StartTimedStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Interaction.Timed", ECk_GymStation_Anchor::PanelCenter);
        auto StationHandle = Get_StationHandle("Gym.Interaction.Timed");
        auto BaseLocation = StationTransform.GetLocation();

        auto SourceTransform = StationTransform;
        SourceTransform.SetLocation(BaseLocation + FVector(100.0f, 0.0f, 0.0f));
        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(StationHandle, UCk_EntityScript_InteractionGym_TimedSource, FInstancedStruct::Make(FInteractionGymSpawnParams(SourceTransform)));

        auto TargetTransform = StationTransform;
        TargetTransform.SetLocation(BaseLocation + FVector(-100.0f, 0.0f, 0.0f));
        auto SpawnRequest2 = utils_entity_script::Request_SpawnEntity(StationHandle, UCk_EntityScript_InteractionGym_TimedTarget, FInstancedStruct::Make(FInteractionGymSpawnParams(TargetTransform)));

        if (ck::IsValid(SpawnRequest) && ck::IsValid(SpawnRequest2)) { ck::Trace("✅ [Timed] started"); }
        else { ck::Error("❌ Failed to spawn [Timed]"); }
    }

    void Request_StartManualStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Interaction.Manual", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Manual"),
            UCk_EntityScript_InteractionGym_Manual,
            FInstancedStruct::Make(FInteractionGymSpawnParams(StationTransform))
        );
        if (ck::IsValid(SpawnRequest)) { ck::Trace("✅ [Manual] started"); }
        else { ck::Error("❌ Failed to spawn [Manual]"); }
    }

    void Request_StartValidationStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Interaction.Validation", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Validation"),
            UCk_EntityScript_InteractionGym_Validation,
            FInstancedStruct::Make(FInteractionGymSpawnParams(StationTransform))
        );
        if (ck::IsValid(SpawnRequest)) { ck::Trace("✅ [Validation] started"); }
        else { ck::Error("❌ Failed to spawn [Validation]"); }
    }

    void Request_StartResolverStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Interaction.Resolver", ECk_GymStation_Anchor::PanelCenter);
        auto StationHandle = Get_StationHandle("Gym.Interaction.Resolver");
        auto BaseLocation = StationTransform.GetLocation();

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(StationHandle, UCk_EntityScript_InteractionGym_ResolverSource, FInstancedStruct::Make(FInteractionGymSpawnParams(StationTransform)));

        auto Offsets = TArray<FVector>();
        Offsets.Add(FVector(50.0f, 0.0f, 0.0f));
        Offsets.Add(FVector(150.0f, 0.0f, 0.0f));
        Offsets.Add(FVector(300.0f, 0.0f, 0.0f));

        for (int32 i = 0; i < Offsets.Num(); i++)
        {
            auto TargetTransform = StationTransform;
            TargetTransform.SetLocation(BaseLocation + Offsets[i]);
            utils_entity_script::Request_SpawnEntity(StationHandle, UCk_EntityScript_InteractionGym_ResolverTarget, FInstancedStruct::Make(FInteractionGymSpawnParams(TargetTransform)));
        }

        if (ck::IsValid(SpawnRequest)) { ck::Trace("✅ [Resolver] started"); }
        else { ck::Error("❌ Failed to spawn [Resolver]"); }
    }

    void Request_StartDataBundleStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Interaction.DataBundle", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.DataBundle"),
            UCk_EntityScript_InteractionGym_DataBundle,
            FInstancedStruct::Make(FInteractionGymSpawnParams(StationTransform))
        );
        if (ck::IsValid(SpawnRequest)) { ck::Trace("✅ [DataBundle] started"); }
        else { ck::Error("❌ Failed to spawn [DataBundle]"); }
    }

    //------------------------------------------------------------------------
    // HELPERS
    //------------------------------------------------------------------------

    void BroadcastToTag(FName InTag, FInstancedStruct InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    void BroadcastAutoToAll(bool InEnabled)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_InteractionGym_Instant");
        AllTags.Add(n"TAG_InteractionGym_TimedTarget");
        AllTags.Add(n"TAG_InteractionGym_Manual");
        AllTags.Add(n"TAG_InteractionGym_Validation");
        AllTags.Add(n"TAG_InteractionGym_ResolverSource");
        AllTags.Add(n"TAG_InteractionGym_DataBundle");

        for (auto Tag : AllTags)
        {
            BroadcastToTag(Tag, FInstancedStruct::Make(Msg));
        }
    }

    void BroadcastAutoToTag(FName InTag, bool InEnabled)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
        BroadcastToTag(InTag, FInstancedStruct::Make(Msg));
    }

    //------------------------------------------------------------------------
    // STATION 1: INSTANT
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Trigger Instant")
    void Ck_GymInteraction_TriggerInstant()
    {
        BroadcastToTag(n"TAG_InteractionGym_Instant", FInstancedStruct::Make(FCk_Message_InteractionGym_TriggerInstant()));
    }

    //------------------------------------------------------------------------
    // STATION 2: TIMED
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Start Timed")
    void Ck_GymInteraction_StartTimed()
    {
        BroadcastToTag(n"TAG_InteractionGym_TimedTarget", FInstancedStruct::Make(FCk_Message_InteractionGym_StartTimed()));
    }

    //------------------------------------------------------------------------
    // STATION 3: MANUAL
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Start Manual")
    void Ck_GymInteraction_StartManual()
    {
        BroadcastToTag(n"TAG_InteractionGym_Manual", FInstancedStruct::Make(FCk_Message_InteractionGym_StartManual()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - End Manual Success")
    void Ck_GymInteraction_EndManualSuccess()
    {
        BroadcastToTag(n"TAG_InteractionGym_Manual", FInstancedStruct::Make(FCk_Message_InteractionGym_EndManualSuccess()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - End Manual Fail")
    void Ck_GymInteraction_EndManualFail()
    {
        BroadcastToTag(n"TAG_InteractionGym_Manual", FInstancedStruct::Make(FCk_Message_InteractionGym_EndManualFail()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Cancel Manual")
    void Ck_GymInteraction_CancelManual()
    {
        BroadcastToTag(n"TAG_InteractionGym_Manual", FInstancedStruct::Make(FCk_Message_InteractionGym_CancelManual()));
    }

    //------------------------------------------------------------------------
    // STATION 4: VALIDATION
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Attempt Validation")
    void Ck_GymInteraction_AttemptValidation()
    {
        BroadcastToTag(n"TAG_InteractionGym_Validation", FInstancedStruct::Make(FCk_Message_InteractionGym_AttemptValidation()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Toggle Enabled")
    void Ck_GymInteraction_ToggleEnabled()
    {
        BroadcastToTag(n"TAG_InteractionGym_Validation", FInstancedStruct::Make(FCk_Message_InteractionGym_ToggleEnabled()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Toggle Custom Validation")
    void Ck_GymInteraction_ToggleCustomValidation()
    {
        BroadcastToTag(n"TAG_InteractionGym_Validation", FInstancedStruct::Make(FCk_Message_InteractionGym_ToggleCustomValidation()));
    }

    //------------------------------------------------------------------------
    // STATION 5: RESOLVER
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Start Intent")
    void Ck_GymInteraction_StartIntent()
    {
        BroadcastToTag(n"TAG_InteractionGym_ResolverSource", FInstancedStruct::Make(FCk_Message_InteractionGym_StartIntent()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Stop Intent")
    void Ck_GymInteraction_StopIntent()
    {
        BroadcastToTag(n"TAG_InteractionGym_ResolverSource", FInstancedStruct::Make(FCk_Message_InteractionGym_StopIntent()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Add Resolver Targets")
    void Ck_GymInteraction_AddTarget()
    {
        BroadcastToTag(n"TAG_InteractionGym_ResolverSource", FInstancedStruct::Make(FCk_Message_InteractionGym_AddTargets()));
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Remove Resolver Targets")
    void Ck_GymInteraction_RemoveTarget()
    {
        BroadcastToTag(n"TAG_InteractionGym_ResolverSource", FInstancedStruct::Make(FCk_Message_InteractionGym_RemoveTargets()));
    }

    //------------------------------------------------------------------------
    // STATION 6: DATA BUNDLE
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Initiate Resolution")
    void Ck_GymInteraction_InitiateResolution()
    {
        BroadcastToTag(n"TAG_InteractionGym_DataBundle", FInstancedStruct::Make(FCk_Message_InteractionGym_InitiateResolution()));
    }

    //------------------------------------------------------------------------
    // AUTO MODE COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto All")
    void Ck_GymInteraction_Auto(int32 InEnabled = 1)
    {
        BroadcastAutoToAll(InEnabled != 0);
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto Instant")
    void Ck_GymInteraction_AutoInstant()
    {
        BroadcastAutoToTag(n"TAG_InteractionGym_Instant", true);
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto Timed")
    void Ck_GymInteraction_AutoTimed()
    {
        BroadcastAutoToTag(n"TAG_InteractionGym_TimedTarget", true);
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto Manual")
    void Ck_GymInteraction_AutoManual()
    {
        BroadcastAutoToTag(n"TAG_InteractionGym_Manual", true);
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto Validation")
    void Ck_GymInteraction_AutoValidation()
    {
        BroadcastAutoToTag(n"TAG_InteractionGym_Validation", true);
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto Resolver")
    void Ck_GymInteraction_AutoResolver()
    {
        BroadcastAutoToTag(n"TAG_InteractionGym_ResolverSource", true);
    }

    UFUNCTION(Exec, DisplayName="Interaction Gym - Auto DataBundle")
    void Ck_GymInteraction_AutoDataBundle()
    {
        BroadcastAutoToTag(n"TAG_InteractionGym_DataBundle", true);
    }
}
