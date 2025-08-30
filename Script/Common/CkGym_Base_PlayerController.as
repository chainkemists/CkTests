class ACk_Gym_Base_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        // Entity is now ready - validate stations and start gym
        auto ValidationResult = Request_ValidateRequiredStations();
        if (!ValidationResult)
        {
            ck::Error("❌ Gym validation failed - some required stations are missing");
            return;
        }

        ck::Trace("✅ All required stations found - starting gym");
        Request_StartGym();
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto GymName = Get_GymName();
        if (GymName.IsEmpty())
        {
            ck::Trace("Gym starting - Waiting for ECS setup...");
        }
        else
        {
            ck::Trace(GymName + " - Waiting for ECS setup...");
        }
    }

    // Override this in derived gym classes to provide gym name
    FString Get_GymName()
    {
        return "Base Gym";
    }

    // Override this in derived gym classes to provide gym description
    FString Get_GymDescription()
    {
        return "Base gym class - override Get_GymDescription() in derived class";
    }

    // Override this in derived gym classes to list required station tags
    TArray<FString> Get_RequiredStationTags()
    {
        auto RequiredTags = TArray<FString>();
        // Example: RequiredTags.Add("Gym.Audio.BackgroundMusic");
        return RequiredTags;
    }

    // Override this in derived gym classes to implement gym-specific startup logic
    void Request_StartGym()
    {
        ck::Trace("Base gym started - override Request_StartGym() in derived class");
    }

    bool Request_ValidateRequiredStations()
    {
        auto RequiredTags = Get_RequiredStationTags();
        if (RequiredTags.Num() == 0)
        {
            ck::Trace("No required stations specified - validation passed");
            return true;
        }

        auto AllValid = true;
        for (auto TagString : RequiredTags)
        {
            auto StationActor = utils_actor::Get_FirstActorWithNameContaining(TagString, ECk_ActorSearchMethod::SearchByTag);
            if (!ck::IsValid(StationActor))
            {
                ck::Error("❌ Required station not found with tag: " + TagString);
                AllValid = false;
            }
            else
            {
                ck::Trace("✅ Found required station: " + TagString + " at " + StationActor.GetActorLocation().ToString());
            }
        }

        return AllValid;
    }

    // Utility function for derived classes to find station by tag
    AActor Get_StationByTag(FString InStationTag)
    {
        auto StationActor = utils_actor::Get_FirstActorWithNameContaining(InStationTag, ECk_ActorSearchMethod::SearchByTag);
        if (!ck::IsValid(StationActor))
        {
            ck::Warning("❌ Station not found with tag: " + InStationTag);
            return nullptr;
        }

        return StationActor;
    }

    // Utility function for derived classes to get station transform
    FTransform Get_StationTransform(FString InStationTag)
    {
        auto StationActor = Get_StationByTag(InStationTag);
        if (!ck::IsValid(StationActor))
        {
            ck::Warning("❌ Cannot get transform - station not found: " + InStationTag);
            return FTransform::Identity;
        }

        return StationActor.GetActorTransform();
    }

    void Request_LogGymInfo()
    {
        ck::Trace("Gym: " + Get_GymName());
        ck::Trace("Description: " + Get_GymDescription());

        auto RequiredTags = Get_RequiredStationTags();
        if (RequiredTags.Num() > 0)
        {
            ck::Trace("Required Station Tags:");
            for (auto Tag : RequiredTags)
            {
                ck::Trace("  - " + Tag);
            }
        }
    }

    UFUNCTION(Exec, DisplayName="Gym - Show Info")
    void Ck_Gym_ShowInfo()
    {
        Request_LogGymInfo();
    }

    UFUNCTION(Exec, DisplayName="Gym - Validate Stations")
    void Ck_Gym_ValidateStations()
    {
        Request_ValidateRequiredStations();
    }

    UFUNCTION(Exec, DisplayName="Gym - Restart")
    void Ck_Gym_Restart()
    {
        Request_StartGym();
    }
}