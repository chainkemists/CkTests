// Language=angelscript

//============================================================================
// CK INPUT KEY-BINDING GYM — RESET + PERSISTENCE STATION
//
// Display half of ResetMappingToDefault / ResetAllToDefaults / SaveKeyBindings.
// The profile view shows current AND default per row, so a reset is verifiable
// on the panel: after it, the two columns match on every row.
//
// PERSISTENCE IS THE ONE THING THIS PANEL CANNOT PROVE ON ITS OWN. Surviving a
// PIE restart is only observable across two sessions, so the steps are printed
// here and the check itself is a human one. It also requires suspending
// teardown first — otherwise leaving PIE erases exactly the rebind the check is
// about — which is why the status line below is rendered first and loudly.
//
// TEARDOWN. This station can leave the profile saved-customized, so DoEndPlay
// resets and re-saves unless the viewer suspended teardown.
//============================================================================

class UCk_EntityScript_InputGym_ResetPersistence : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        input_gym_pc::Request_TeardownIfArmed();
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto PlayerController = input_gym::Get_LocalPlayerController();
        if (ck::Is_NOT_Valid(PlayerController))
        { return; }

        auto Display = f"{input_gym_pc::Get_TeardownStatusLine()}\n\n";
        Display = f"{Display}{input_gym::Format_ProfileRows(PlayerController)}";

        Display = f"{Display}\n===== Persistence check (two PIE sessions) =====\n";
        Display = f"{Display}  1. Ck_GymInput_SuspendTeardown\n";
        Display = f"{Display}  2. Ck_GymInput_RemapFree      (Jump moves to J)\n";
        Display = f"{Display}  3. Ck_GymInput_Save\n";
        Display = f"{Display}  4. Leave PIE, re-enter, come back to this gym\n";
        Display = f"{Display}  5. Jump should still read J above\n";
        Display = f"{Display}  6. Ck_GymInput_ResetAllAndSave  (re-arms teardown, leaves no residue)\n";

        Display = f"{Display}\n===== Last command =====\n";
        Display = f"{Display}{input_gym_pc::Get_LastActionReport()}\n";

        CkGym_Common::Update_StationDisplay(
            ck::ToEntity(this), StationTitle, Display, StationDescription);
    }
}
