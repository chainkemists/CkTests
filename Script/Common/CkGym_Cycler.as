//--------------------------------------------------------------------------------------------------------------------------

struct FCkGym_Entry
{
    UPROPERTY()
    FString DisplayName;

    UPROPERTY()
    TSubclassOf<AGameModeBase> GameModeClass;

    FCkGym_Entry()
    {
    }

    FCkGym_Entry(FString InDisplayName, TSubclassOf<AGameModeBase> InGameModeClass)
    {
        DisplayName = InDisplayName;
        GameModeClass = InGameModeClass;
    }
}

//--------------------------------------------------------------------------------------------------------------------------

namespace CkGym_Cycler
{
    TArray<FCkGym_Entry> Get_GymRegistry()
    {
        auto Gyms = TArray<FCkGym_Entry>();
        Gyms.Add(FCkGym_Entry("Attribute Integer",  ACk_IntegerAttributeGym_GameMode));
        Gyms.Add(FCkGym_Entry("Attribute Byte",     ACk_ByteAttributeGym_GameMode));
        Gyms.Add(FCkGym_Entry("Attribute Basic",    ACk_AttributeGym_GameMode));
        Gyms.Add(FCkGym_Entry("Audio Simple",       ACk_AudioGym_Simple_GameMode));
        Gyms.Add(FCkGym_Entry("Cue",                ACk_CueGym_GameMode));
        Gyms.Add(FCkGym_Entry("Entity Lifecycle",   ACk_EntityLifecycleGym_GameMode));
        Gyms.Add(FCkGym_Entry("Entity Script",      ACk_EntityScriptGym_Spawn_GameMode));
        Gyms.Add(FCkGym_Entry("Messaging",          ACk_MessagingGym_GameMode));
        Gyms.Add(FCkGym_Entry("PMG Shapes",         ACk_PmgShapesGym_GameMode));
        Gyms.Add(FCkGym_Entry("Scene Node",         ACk_SceneNodeGym_GameMode));
        Gyms.Add(FCkGym_Entry("State Machine",      ACk_SmTest_GymGameMode));
        Gyms.Add(FCkGym_Entry("Timer",              ACk_TimerGym_GameMode));
        Gyms.Add(FCkGym_Entry("Transform",          ACk_TransformGym_GameMode));
        Gyms.Add(FCkGym_Entry("Tween",              ACk_TweenTest_GymGameMode));
        return Gyms;
    }

    void Request_TravelToGym(int32 InIndex)
    {
        auto Registry = Get_GymRegistry();
        if (Registry.Num() == 0)
        {
            return;
        }

        // Wrap index
        auto WrappedIndex = InIndex % Registry.Num();
        if (WrappedIndex < 0)
        {
            WrappedIndex = WrappedIndex + Registry.Num();
        }

        // Persist index in GameInstance subsystem
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        Subsystem.CurrentGymIndex = WrappedIndex;

        // Resolve the actual class path from the UClass at runtime
        auto Entry = Registry[WrappedIndex];
        auto ClassPath = Entry.GameModeClass.Get().GetPathName();
        auto LevelName = Subsystem.GymLevelName;

        auto TravelURL = f"{LevelName}?game={ClassPath}";
        ck::Trace(f"[GymCycler] ServerTravel {TravelURL}");
        System::ExecuteConsoleCommand(f"ServerTravel {TravelURL}");
    }

    void Request_NextGym()
    {
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        Request_TravelToGym(Subsystem.CurrentGymIndex + 1);
    }

    void Request_PrevGym()
    {
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        Request_TravelToGym(Subsystem.CurrentGymIndex - 1);
    }

    void Print_GymList()
    {
        auto Registry = Get_GymRegistry();
        auto Subsystem = UCkGym_CyclerSubsystem::Get();

        ck::Trace("=== GYM REGISTRY ===");
        for (int32 i = 0; i < Registry.Num(); i++)
        {
            auto Marker = (i == Subsystem.CurrentGymIndex) ? " <-- CURRENT" : "";
            ck::Trace(f"  [{i}] {Registry[i].DisplayName}{Marker}");
        }
        ck::Trace("====================");
    }
}
