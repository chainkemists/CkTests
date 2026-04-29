class UCkGym_CyclerSubsystem : UScriptGameInstanceSubsystem
{
    UPROPERTY()
    int32 CurrentGymIndex = -1;  // -1 = no gym active (launcher level)

    // Default level used when a gym entry doesn't specify its own LevelName.
    // Must match the level asset name without path or extension.
    UPROPERTY()
    FString GymLevelName = "TestGyms_CkTests_Level";

    // Project-provided gyms, registered by external modules (e.g. BusterBlock)
    // via CkGym_Cycler::RegisterProjectGym. Appended after built-in CK gyms in
    // Get_GymRegistry() so projects can extend the Tab-menu selector without
    // modifying CkTests' hardcoded list.
    UPROPERTY()
    TArray<FCkGym_Entry> ProjectGyms;

    // Set to true by ACk_Gym_Base_GameMode::BeginPlay when it has decided to
    // auto-travel to a startup gym; cleared when the destination level loads
    // (and on no-travel code paths). The cycler HUD reads this and skips
    // drawing while it's true, so the user doesn't briefly see the menu /
    // tab-hint during the launcher → destination transition.
    UPROPERTY()
    bool SuppressHUDDuringStartup = false;
}
