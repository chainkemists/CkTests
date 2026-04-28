//--------------------------------------------------------------------------------------------------------------------------
// CkTests Gym Base Game Mode
//
// All CkTests gym game modes should inherit from this instead of
// ACk_Gym_Base_GameMode directly. It registers CkTests gyms with the cycler
// during BeginPlay so the Tab menu shows them.
//
// Set this class as the World Settings default game mode in the
// TestGyms_CkTests_Level level. Individual gyms override via ServerTravel's
// ?game= parameter, and their specific game modes also inherit from here.
//--------------------------------------------------------------------------------------------------------------------------

class ACkTests_Gym_Base_GameMode : ACk_Gym_Base_GameMode
{
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        CkTests_Gyms::RegisterAll();
    }
}
