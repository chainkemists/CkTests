class ACk_Gym_Base_GameMode : ACk_GameMode_UE
{
    // Override these in derived gym classes
    default PlayerControllerClass = ACk_Gym_Base_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto GymName = Get_GymName();
        if (GymName.IsEmpty())
        {
            ck::Warning("Gym name not set - override Get_GymName() in derived class");
            return;
        }

        ck::Trace("=== " + GymName + " Gym Started ===");
        Request_LogGymInfo();
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

    UFUNCTION(Exec, DisplayName="Show Gym Info")
    void Ck_Gym_ShowInfo()
    {
        Request_LogGymInfo();
    }
}