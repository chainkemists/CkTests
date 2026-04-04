class UCkGym_CyclerSubsystem : UScriptGameInstanceSubsystem
{
    UPROPERTY()
    int32 CurrentGymIndex = 0;

    // Set this to the name of the shared gym level (e.g. "CkGym_AllTests")
    // Must match the level asset name without path or extension
    UPROPERTY()
    FString GymLevelName = "CkGym_AllTests";
}
