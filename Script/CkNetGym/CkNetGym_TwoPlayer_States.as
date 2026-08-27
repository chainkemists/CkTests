// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM - STATE MACHINE STATES
//============================================================================
// Cycle: Idle -> Active -> Recovering -> Idle. Driven externally by the owning
// client via UCk_Utils_StateMachine_UE::Request_Transition(NextStateClass).
// States carry no transitions of their own - they are targets only.
//============================================================================

UCLASS()
class UCk_NetGym_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Target-only state: no tasks, no transitions.
    }
}

UCLASS()
class UCk_NetGym_State_Active : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_NetGym_State_Recovering : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}
