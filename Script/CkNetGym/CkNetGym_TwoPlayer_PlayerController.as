// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM - PLAYER CONTROLLER
//============================================================================
// The gym is a fully automatic showcase - state changes and damage run on the
// server-driven cadence (see the director). No console commands.
//============================================================================

class ACk_NetGym_TwoPlayer_PlayerController : ACk_Gym_Base_PlayerController
{
    void Request_StartGym() override
    {
        ck::Trace("[NetGym] Two-Player gym started. Auto-cadence: states + damage interleave every 5s.");
    }
}
