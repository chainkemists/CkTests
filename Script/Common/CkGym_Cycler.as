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
// Gym Registry
// To add a new gym, add one line to Get_GymRegistry():
//   CkGym_Cycler::RegisterGym(Gyms, "Display Name", AMyGym_GameMode);
//--------------------------------------------------------------------------------------------------------------------------

namespace CkGym_Cycler
{
    void RegisterGym(TArray<FCkGym_Entry>& G, FString N, TSubclassOf<AGameModeBase> C) { G.Add(FCkGym_Entry(N, C)); }

    TArray<FCkGym_Entry> Get_GymRegistry()
    {
        auto Gyms = TArray<FCkGym_Entry>();
        RegisterGym(Gyms, "Attribute Basic",    ACk_AttributeGym_GameMode);
        RegisterGym(Gyms, "Attribute Byte",     ACk_ByteAttributeGym_GameMode);
        RegisterGym(Gyms, "Attribute Integer",  ACk_IntegerAttributeGym_GameMode);
        RegisterGym(Gyms, "Audio Simple",       ACk_AudioGym_Simple_GameMode);
        RegisterGym(Gyms, "Cue",                ACk_CueGym_GameMode);
        RegisterGym(Gyms, "Entity Lifecycle",   ACk_EntityLifecycleGym_GameMode);
        RegisterGym(Gyms, "Entity Script",      ACk_EntityScriptGym_Spawn_GameMode);
        RegisterGym(Gyms, "Messaging",          ACk_MessagingGym_GameMode);
        RegisterGym(Gyms, "PMG Shapes",         ACk_PmgShapesGym_GameMode);
        RegisterGym(Gyms, "Scene Node",         ACk_SceneNodeGym_GameMode);
        RegisterGym(Gyms, "State Machine",      ACk_SmTest_GymGameMode);
        RegisterGym(Gyms, "Timer",              ACk_TimerGym_GameMode);
        RegisterGym(Gyms, "Transform",          ACk_TransformGym_GameMode);
        RegisterGym(Gyms, "Tween",              ACk_TweenTest_GymGameMode);
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
