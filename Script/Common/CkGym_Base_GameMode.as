class ACk_Gym_Base_GameMode : ACk_GameMode_UE
{
    // Override these in derived gym classes
    default PlayerControllerClass = ACk_Gym_Base_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
    default HUDClass = ACkGym_MenuHUD;

    // Resolves the user's startup-gym preference (Editor Preferences ->
    // Ck Tests -> Gym Cycler) and ServerTravels there if a target is set
    // and we're not already on it. Subclasses that override BeginPlay must
    // call Super::BeginPlay() AFTER they finish registering their own gyms,
    // otherwise the resolve runs against an empty registry.
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::Is_NOT_Valid(Subsystem))
        {
            return;
        }

        // Resolve synchronously so we can decide *before* the HUD's first
        // paint whether to suppress it. The actual ServerTravel still has
        // to be deferred (PIE bootstrap drops travel commands issued from
        // BeginPlay), but the suppress-flag decision must land first.
        auto StartupIndex = CkGym_Cycler::Resolve_StartupGymIndex();

        if (StartupIndex < 0)
        {
            // No saved target — cycler menu handles entry as usual.
            Subsystem.SuppressHUDDuringStartup = false;
            return;
        }

        // Guard against a re-travel loop on the destination level. The
        // subsystem's CurrentGymIndex survives ServerTravel, so once we
        // land on the chosen gym, BeginPlay sees the match and bails.
        if (Subsystem.CurrentGymIndex == StartupIndex)
        {
            // We've arrived at the chosen gym — restore the HUD.
            Subsystem.SuppressHUDDuringStartup = false;
            return;
        }

        // We're about to auto-travel: suppress the HUD so the user doesn't
        // see the cycler menu / tab-hint flash on the launcher level during
        // the brief transition.
        Subsystem.SuppressHUDDuringStartup = true;

        // Defer the actual ServerTravel by one tick.
        System::SetTimer(this, n"DoStartupTravel", 0.01, false);
    }

    UFUNCTION()
    private void DoStartupTravel()
    {
        auto StartupIndex = CkGym_Cycler::Resolve_StartupGymIndex();
        if (StartupIndex < 0)
        {
            return;
        }

        auto Subsystem = UCkGym_CyclerSubsystem::Get();
        if (ck::Is_NOT_Valid(Subsystem))
        {
            return;
        }

        if (Subsystem.CurrentGymIndex == StartupIndex)
        {
            return;
        }

        CkGym_Cycler::Request_TravelToGym(StartupIndex);
    }
}
