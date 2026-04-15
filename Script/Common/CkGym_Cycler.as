//--------------------------------------------------------------------------------------------------------------------------

struct FCkGym_Entry
{
    UPROPERTY()
    FString DisplayName;

    UPROPERTY()
    TSubclassOf<AGameModeBase> GameModeClass;

    // Optional per-gym level override. When empty, falls back to
    // UCkGym_CyclerSubsystem.GymLevelName. Set this for project gyms that live
    // in their own level (e.g. BusterBlock gyms).
    UPROPERTY()
    FString LevelName;

    FCkGym_Entry()
    {
    }

    FCkGym_Entry(FString InDisplayName, TSubclassOf<AGameModeBase> InGameModeClass, FString InLevelName = "")
    {
        DisplayName = InDisplayName;
        GameModeClass = InGameModeClass;
        LevelName = InLevelName;
    }
}

//--------------------------------------------------------------------------------------------------------------------------
// Gym Registry
//
// Built-in CkTests gyms are hardcoded in Register_BuiltInCkGyms below. Projects
// that want to add their own gyms to the Tab-menu selector should call
// CkGym_Cycler::RegisterProjectGym(displayName, gameModeClass, levelName) from
// a GameInstanceSubsystem's Initialize — they'll appear after the built-ins.
//--------------------------------------------------------------------------------------------------------------------------

namespace CkGym_Cycler
{
    void RegisterGym(TArray<FCkGym_Entry>& G, FString N, TSubclassOf<AGameModeBase> C, FString L = "") { G.Add(FCkGym_Entry(N, C, L)); }

    void Register_BuiltInCkGyms(TArray<FCkGym_Entry>& Gyms)
    {
        RegisterGym(Gyms, "Attribute Basic",    ACk_AttributeGym_GameMode);
        RegisterGym(Gyms, "Attribute Byte",     ACk_ByteAttributeGym_GameMode);
        RegisterGym(Gyms, "Attribute Float",    ACk_FloatAttributeGym_GameMode);
        RegisterGym(Gyms, "Attribute Integer",  ACk_IntegerAttributeGym_GameMode);
        RegisterGym(Gyms, "Audio Simple",       ACk_AudioGym_Simple_GameMode);
        RegisterGym(Gyms, "Cue",                ACk_CueGym_GameMode);
        RegisterGym(Gyms, "Entity Lifecycle",   ACk_EntityLifecycleGym_GameMode);
        RegisterGym(Gyms, "Entity Script",      ACk_EntityScriptGym_Spawn_GameMode);
        RegisterGym(Gyms, "Interaction",        ACk_InteractionGym_GameMode);
        RegisterGym(Gyms, "Inventory",          ACk_InventoryGym_GameMode);
        RegisterGym(Gyms, "Messaging",          ACk_MessagingGym_GameMode);
        RegisterGym(Gyms, "PMG Shapes",         ACk_PmgShapesGym_GameMode);
        RegisterGym(Gyms, "Replication",        ACk_ReplicationGym_GameMode);
        RegisterGym(Gyms, "Scene Node",         ACk_SceneNodeGym_GameMode);
        RegisterGym(Gyms, "State Machine",      ACk_SmTest_GymGameMode);
        RegisterGym(Gyms, "Timer",              ACk_TimerGym_GameMode);
        RegisterGym(Gyms, "Transform",          ACk_TransformGym_GameMode);
        RegisterGym(Gyms, "Tween",              ACk_TweenTest_GymGameMode);
    }

    // Called by external modules (e.g. BusterBlock) from a GameInstanceSubsystem
    // Initialize to add their own gyms. Dedupes by DisplayName so duplicate
    // registrations on hot-reload or module reinit are idempotent.
    void RegisterProjectGym(FString InDisplayName, TSubclassOf<AGameModeBase> InGameModeClass, FString InLevelName = "")
    {
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::Is_NOT_Valid(Subsystem))
        {
            ck::Warning(f"[GymCycler] RegisterProjectGym called but subsystem not available (DisplayName={InDisplayName})");
            return;
        }

        for (auto Existing : Subsystem.ProjectGyms)
        {
            if (Existing.DisplayName == InDisplayName)
            {
                return;
            }
        }

        Subsystem.ProjectGyms.Add(FCkGym_Entry(InDisplayName, InGameModeClass, InLevelName));
    }

    TArray<FCkGym_Entry> Get_GymRegistry()
    {
        auto Gyms = TArray<FCkGym_Entry>();
        Register_BuiltInCkGyms(Gyms);

        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::IsValid(Subsystem))
        {
            for (auto ProjectGym : Subsystem.ProjectGyms)
            {
                Gyms.Add(ProjectGym);
            }
        }

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
        auto LevelName = Entry.LevelName != "" ? Entry.LevelName : Subsystem.GymLevelName;

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
