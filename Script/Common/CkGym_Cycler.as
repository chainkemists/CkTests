//--------------------------------------------------------------------------------------------------------------------------
// Gym Registry facade (framework - no hardcoded gyms)
//
// The registry itself lives in C++ (UCkGym_Registry_Subsystem, per-GameInstance; see
// CkGym_Registry.h) together with FCkGym_Entry. This namespace is a thin AngelScript facade so
// consumers (CkTests, BusterBlock, etc.) keep their existing callsite spelling:
// CkGym_Cycler::RegisterProjectGym(...), typically from a base GameMode's BeginPlay.
//--------------------------------------------------------------------------------------------------------------------------

namespace CkGym_Cycler
{
    // Called by consumers (e.g. CkTests_Gyms::RegisterAll, BB_Gyms::RegisterAll) from a base
    // GameMode's BeginPlay. Dedupes by DisplayName so duplicate registrations on hot-reload or
    // level re-entry are idempotent. InCategory groups the gym on the switchboard (conventionally
    // the owning module's name, e.g. "CkCrowd"); empty lands in the fallback bucket.
    void RegisterProjectGym(FString InDisplayName, TSubclassOf<AGameModeBase> InGameModeClass, FString InLevelName = "", FString InCategory = "")
    {
        UCk_Utils_GymRegistry_UE::Request_RegisterGym(InDisplayName, InGameModeClass, InLevelName, InCategory);
    }

    TArray<FCkGym_Entry> Get_GymRegistry()
    {
        return UCk_Utils_GymRegistry_UE::Get_GymRegistry();
    }

    void Request_TravelToGym(int32 InIndex)
    {
        UCk_Utils_GymRegistry_UE::Request_TravelToGym(InIndex);
    }

    int32 Find_GymIndexByName(FString InName)
    {
        return UCk_Utils_GymRegistry_UE::Find_GymIndexByName(InName);
    }

    void Request_TravelToGymByName(FString InName)
    {
        UCk_Utils_GymRegistry_UE::Request_TravelToGymByName(InName);
    }

    // Returns the registry index the gym GameMode should auto-travel to on BeginPlay, based on the
    // user's startup preference. Returns -1 when the cycler menu should handle entry.
    int32 Resolve_StartupGymIndex()
    {
        return UCk_Utils_GymRegistry_UE::Resolve_StartupGymIndex();
    }

    void Request_NextGym()
    {
        UCk_Utils_GymRegistry_UE::Request_NextGym();
    }

    void Request_PrevGym()
    {
        UCk_Utils_GymRegistry_UE::Request_PrevGym();
    }

    void Print_GymList()
    {
        auto Registry = Get_GymRegistry();
        auto CurrentGymIndex = UCk_Utils_GymRegistry_UE::Get_CurrentGymIndex();

        ck::Trace("=== GYM REGISTRY ===");
        for (int32 i = 0; i < Registry.Num(); i++)
        {
            auto Marker = (i == CurrentGymIndex) ? " <-- CURRENT" : "";
            ck::Trace(f"  [{i}] {Registry[i].DisplayName}{Marker}");
        }
        ck::Trace("====================");
    }
}
