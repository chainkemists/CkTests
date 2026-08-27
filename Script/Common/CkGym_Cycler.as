//--------------------------------------------------------------------------------------------------------------------------

struct FCkGym_Entry
{
    UPROPERTY()
    FString DisplayName;

    UPROPERTY()
    TSubclassOf<AGameModeBase> GameModeClass;

    // Optional per-gym level override. When empty, falls back to
    // UCkGym_CyclerSubsystem.GymLevelName.
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
// Gym Registry (framework - no hardcoded gyms)
//
// The cycler is a pure registry. Consumers (CkTests, BusterBlock, etc.) register
// their own gyms via RegisterProjectGym, typically from a base GameMode's
// BeginPlay. This keeps the framework gym-agnostic.
//--------------------------------------------------------------------------------------------------------------------------

namespace CkGym_Cycler
{
    void RegisterGym(TArray<FCkGym_Entry>& G, FString N, TSubclassOf<AGameModeBase> C, FString L = "") { G.Add(FCkGym_Entry(N, C, L)); }

    // Called by consumers (e.g. CkTests_Gyms::RegisterAll, BB_Gyms::RegisterAll)
    // from a base GameMode's BeginPlay. Dedupes by DisplayName so duplicate
    // registrations on hot-reload or level re-entry are idempotent.
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
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::IsValid(Subsystem))
        {
            return Subsystem.ProjectGyms;
        }
        return TArray<FCkGym_Entry>();
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

        // Persist the chosen gym so the "Last" startup mode can resume it next launch.
        UCk_Utils_GymStartup_UE::Request_Set_LastGymName(Entry.DisplayName);

        auto TravelURL = f"{LevelName}?game={ClassPath}";
        ck::Trace(f"[GymCycler] ServerTravel {TravelURL}");
        System::ExecuteConsoleCommand(f"ServerTravel {TravelURL}");
    }

    int32 Find_GymIndexByName(FString InName)
    {
        if (InName == "")
        {
            return -1;
        }

        auto Registry = Get_GymRegistry();
        for (int32 i = 0; i < Registry.Num(); i++)
        {
            if (Registry[i].DisplayName == InName)
            {
                return i;
            }
        }
        return -1;
    }

    void Request_TravelToGymByName(FString InName)
    {
        auto Index = Find_GymIndexByName(InName);
        if (Index < 0)
        {
            ck::Warning(f"[GymCycler] Request_TravelToGymByName: no gym registered with DisplayName '{InName}'");
            return;
        }
        Request_TravelToGym(Index);
    }

    // Returns the registry index the gym GameMode should auto-travel to on
    // BeginPlay, based on the user's startup preference. Returns -1 when the
    // cycler menu should handle entry (mode = Cycler, or the saved name no
    // longer resolves to a registered gym).
    int32 Resolve_StartupGymIndex()
    {
        auto Mode = UCk_Utils_GymStartup_UE::Get_StartupMode();

        if (Mode == ECkGym_StartupMode::Default)
        {
            return Find_GymIndexByName(UCk_Utils_GymStartup_UE::Get_DefaultGymName());
        }

        if (Mode == ECkGym_StartupMode::Last)
        {
            return Find_GymIndexByName(UCk_Utils_GymStartup_UE::Get_LastGymName());
        }

        return -1;
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
