class ACk_Gym_Base_GameMode : ACk_GameMode_UE
{
    // Override these in derived gym classes
    default PlayerControllerClass = ACk_Gym_Base_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
    // The shared gym control panel HUD - it also arms the switchboard's Tab open, so every gym
    // world gets the Tab menu; a gym that declares no control rows just gets the Tab hint.
    default HUDClass = ACkGym_ControlPanelHUD;

    // The startup-gym redirect target, decided once in BeginPlay and executed by the deferred
    // DoStartupTravel (PIE bootstrap drops travel commands issued from BeginPlay directly).
    private int32 _StartupTravelIndex = -1;

    // Resolves the user's startup-gym preference (Editor Preferences ->
    // Ck Tests -> Gym Cycler) and ServerTravels there - ONCE per game
    // session. BeginPlay re-fires on every gym travel, so without the
    // consumed one-shot the preference would yank the user back to the
    // pinned gym whenever they pick anything else from the switchboard.
    // Subclasses that override BeginPlay must call Super::BeginPlay()
    // AFTER they finish registering their own gyms, otherwise the resolve
    // runs against an empty registry.
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();

        // The redirect already ran (or was skipped) this session - this
        // BeginPlay is a user-initiated travel landing. Just restore the HUD.
        if (UCk_Utils_GymRegistry_UE::Get_HasConsumedStartupResolve())
        {
            UCk_Utils_GymRegistry_UE::Request_Set_SuppressHUDDuringStartup(false);
            return;
        }

        UCk_Utils_GymRegistry_UE::Request_MarkStartupResolveConsumed();

        // Resolve synchronously so we can decide *before* the HUD's first
        // paint whether to suppress it. The actual ServerTravel still has
        // to be deferred, but the suppress-flag decision must land first.
        auto StartupIndex = CkGym_Cycler::Resolve_StartupGymIndex();

        if (StartupIndex < 0 || UCk_Utils_GymRegistry_UE::Get_CurrentGymIndex() == StartupIndex)
        {
            // No saved target, or we already start on it - cycler menu / HUD as usual.
            UCk_Utils_GymRegistry_UE::Request_Set_SuppressHUDDuringStartup(false);
            return;
        }

        // We're about to auto-travel: suppress the HUD so the user doesn't
        // see the cycler menu / tab-hint flash on the launcher level during
        // the brief transition. The destination's BeginPlay lifts it via the
        // consumed branch above.
        UCk_Utils_GymRegistry_UE::Request_Set_SuppressHUDDuringStartup(true);

        _StartupTravelIndex = StartupIndex;
        System::SetTimer(this, n"DoStartupTravel", 0.01, false);
    }

    UFUNCTION()
    private void DoStartupTravel()
    {
        if (_StartupTravelIndex < 0)
        {
            return;
        }

        CkGym_Cycler::Request_TravelToGym(_StartupTravelIndex);
    }
}
