// Language=angelscript

//============================================================================
// INTERACTION GYM - PLAYER CONTROLLER
//============================================================================

class ACk_InteractionGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Station 1: Instant Interaction
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Instant");
            Station.Title = FText::FromString("INSTANT INTERACTION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Source and target on same entity with Instant completion."));
            Description.Add(FText::FromString("Tests OnNewInteraction and OnInteractionFinished signals."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 2: Timed Interaction
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Timed");
            Station.Title = FText::FromString("TIMED INTERACTION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Source and target on separate entities with 3s timed completion."));
            Description.Add(FText::FromString("Displays elapsed time and completion tracking."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 3: Manual Interaction
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Manual");
            Station.Title = FText::FromString("MANUAL INTERACTION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("ManuallyCompleted policy - must explicitly end or cancel."));
            Description.Add(FText::FromString("Tests EndInteraction with Succeeded/Failed and CancelInteraction."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 4: Enable/Disable & Validation
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Validation");
            Station.Title = FText::FromString("ENABLE/DISABLE & VALIDATION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Target with custom CanInteractWith validation delegate."));
            Description.Add(FText::FromString("Toggle enabled state and custom validation to test rejection."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 5: Interaction Resolver
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.Resolver");
            Station.Title = FText::FromString("INTERACTION RESOLVER");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Resolver with intent-channel mapping and distance sorting."));
            Description.Add(FText::FromString("Source + 3 targets at varying distances."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 6: Resolver Data Bundle
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Interaction.DataBundle");
            Station.Title = FText::FromString("RESOLVER DATA BUNDLE");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("ResolverSource + ResolverTarget with phased resolution."));
            Description.Add(FText::FromString("Calculate phase (base+bonus) then Apply phase (multiplier)."));
            Station.Description = Description;
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
        ck::Trace("✅ Interaction Gym - All stations started");
    }

    //------------------------------------------------------------------------
    // STATION STARTUP FUNCTIONS
    //------------------------------------------------------------------------

    void Request_StartInstantStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Interaction.Instant");
        auto SpawnParams = FInteractionGymSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Instant"),
            UCk_EntityScript_InteractionGym_Instant,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Instant Interaction station started");
        }
        else
        {
            ck::Error("❌ Failed to spawn Instant Interaction entity");
        }
    }

    void Request_StartTimedStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Interaction.Timed");

        // Spawn source entity (offset slightly from station center)
        auto SourceTransform = StationTransform;
        auto SourceLocation = SourceTransform.GetLocation() + FVector(100.0f, 0.0f, 0.0f);
        SourceTransform.SetLocation(SourceLocation);
        auto SourceParams = FInteractionGymSpawnParams(SourceTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Timed"),
            UCk_EntityScript_InteractionGym_TimedSource,
            FInstancedStruct::Make(SourceParams)
        );

        // Spawn target entity (offset in other direction)
        auto TargetTransform = StationTransform;
        auto TargetLocation = TargetTransform.GetLocation() + FVector(-100.0f, 0.0f, 0.0f);
        TargetTransform.SetLocation(TargetLocation);
        auto TargetParams = FInteractionGymSpawnParams(TargetTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Timed"),
            UCk_EntityScript_InteractionGym_TimedTarget,
            FInstancedStruct::Make(TargetParams)
        );

        ck::Trace("✅ Timed Interaction station started (source + target)");
    }

    void Request_StartManualStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Interaction.Manual");
        auto SpawnParams = FInteractionGymSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Manual"),
            UCk_EntityScript_InteractionGym_Manual,
            FInstancedStruct::Make(SpawnParams)
        );
        ck::Trace("✅ Manual Interaction station started");
    }

    void Request_StartValidationStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Interaction.Validation");
        auto SpawnParams = FInteractionGymSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Validation"),
            UCk_EntityScript_InteractionGym_Validation,
            FInstancedStruct::Make(SpawnParams)
        );
        ck::Trace("✅ Validation station started");
    }

    void Request_StartResolverStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Interaction.Resolver");

        // Spawn source entity at station center
        auto SourceParams = FInteractionGymSpawnParams(StationTransform);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.Resolver"),
            UCk_EntityScript_InteractionGym_ResolverSource,
            FInstancedStruct::Make(SourceParams)
        );

        // Spawn 3 target entities at different distances from source
        auto BaseLocation = StationTransform.GetLocation();
        auto Offsets = TArray<FVector>();
        Offsets.Add(FVector(50.0f, 0.0f, 0.0f));
        Offsets.Add(FVector(150.0f, 0.0f, 0.0f));
        Offsets.Add(FVector(300.0f, 0.0f, 0.0f));

        for (int32 i = 0; i < Offsets.Num(); i++)
        {
            auto TargetTransform = StationTransform;
            TargetTransform.SetLocation(BaseLocation + Offsets[i]);
            auto TargetParams = FInteractionGymSpawnParams(TargetTransform);

            utils_entity_script::Request_SpawnEntity(
                Get_StationHandle("Gym.Interaction.Resolver"),
                UCk_EntityScript_InteractionGym_ResolverTarget,
                FInstancedStruct::Make(TargetParams)
            );
        }

        ck::Trace("✅ Resolver station started (1 source + 3 targets)");
    }

    void Request_StartDataBundleStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Interaction.DataBundle");
        auto SpawnParams = FInteractionGymSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Interaction.DataBundle"),
            UCk_EntityScript_InteractionGym_DataBundle,
            FInstancedStruct::Make(SpawnParams)
        );
        ck::Trace("✅ Data Bundle station started");
    }

    //------------------------------------------------------------------------
    // HELPER: Broadcast message to all entities with a given tag
    //------------------------------------------------------------------------

    void BroadcastToTag(FName InTag, FInstancedStruct InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    //------------------------------------------------------------------------
    // STATION 1: INSTANT INTERACTION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Trigger Instant")
    void Ck_GymInteraction_TriggerInstant()
    {
        BroadcastToTag(n"TAG_InteractionGym_Instant", FInstancedStruct::Make(FCk_Message_InteractionGym_Command()));
    }

    //------------------------------------------------------------------------
    // STATION 2: TIMED INTERACTION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Start Timed")
    void Ck_GymInteraction_StartTimed()
    {
        BroadcastToTag(n"TAG_InteractionGym_TimedTarget", FInstancedStruct::Make(FCk_Message_InteractionGym_Command()));
    }

    //------------------------------------------------------------------------
    // STATION 3: MANUAL INTERACTION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Start Manual")
    void Ck_GymInteraction_StartManual()
    {
        BroadcastToTag(n"TAG_InteractionGym_Manual", FInstancedStruct::Make(FCk_Message_InteractionGym_Command()));
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
    // STATION 4: VALIDATION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Attempt Validation")
    void Ck_GymInteraction_AttemptValidation()
    {
        BroadcastToTag(n"TAG_InteractionGym_Validation", FInstancedStruct::Make(FCk_Message_InteractionGym_Command()));
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
    // STATION 5: RESOLVER COMMANDS
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
    // STATION 6: DATA BUNDLE COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Interaction Gym - Initiate Resolution")
    void Ck_GymInteraction_InitiateResolution()
    {
        BroadcastToTag(n"TAG_InteractionGym_DataBundle", FInstancedStruct::Make(FCk_Message_InteractionGym_Command()));
    }
}
