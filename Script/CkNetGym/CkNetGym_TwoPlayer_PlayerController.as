// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — PLAYER CONTROLLER
//============================================================================
// Console commands run on the local player's controller (one per PIE window),
// so each targets that window's own possessed pawn.
//============================================================================

class ACk_NetGym_TwoPlayer_PlayerController : ACk_Gym_Base_PlayerController
{
    void Request_StartGym() override
    {
        ck::Trace("[NetGym] Two-Player gym started. Console: Ck_NetGym_Damage [amt], Ck_NetGym_NextState");
    }

    UFUNCTION(Exec, DisplayName="NetGym - Damage Own Pawn")
    void Ck_NetGym_Damage(float InAmount = 10.0f)
    {
        auto Pawn = Cast<ACk_NetGym_TwoPlayer_Pawn>(GetControlledPawn());
        if (ck::Is_NOT_Valid(Pawn))
        {
            ck::Warning("[NetGym] No controlled NetGym pawn to damage");
            return;
        }
        Pawn.Server_ApplyDamage(InAmount);
    }

    UFUNCTION(Exec, DisplayName="NetGym - Advance Own SM State")
    void Ck_NetGym_NextState()
    {
        auto Pawn = Cast<ACk_NetGym_TwoPlayer_Pawn>(GetControlledPawn());
        if (ck::Is_NOT_Valid(Pawn))
        {
            ck::Warning("[NetGym] No controlled NetGym pawn to advance");
            return;
        }
        Pawn.Request_AdvanceState();
    }
}
