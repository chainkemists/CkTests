// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — STATION STEP STATES
//============================================================================
//
// Three states per station: Arm, Await, Report. Every one of them is a
// TARGET-ONLY state — no tasks, no transitions of its own — because on this gym
// the transition is the PLAYER. A dwell condition would advance the panel while
// somebody was still mid-charge, which is the one thing a human-driven station
// must never do, so the station drives the graph with
// `gym_sm::Request_GoToStep` off what it reads on its display tick. The
// two-player net gym's states are the in-tree precedent for that shape
// (`CkNetGym_TwoPlayer_States.as` — "Target-only state: no tasks, no
// transitions", driven externally by Request_Transition), and the fighting gym's
// nine states are the same shape one gym over.
//
// The states carry no behaviour of their own either. A step state is its own
// entity script and must not reach into the station script's members, and here
// there is nothing it would need to do: the panel is rendered by the station's
// display tick from the matcher and the record, so what the graph contributes is
// the one thing it is uniquely good at — saying, unambiguously and inspectably,
// which phase of the exercise is running. The HUD reads the SM's live current
// state, so the displayed sequence cannot drift from what is actually running.
//
// DefineState output is structurally hashed and must be identical across
// machines, so it stays free of conditionals — an empty body is trivially
// deterministic.
//============================================================================

//----------------------------------------------------------------------------
// Station 1 — a tap and a hold on one button
//----------------------------------------------------------------------------

UCLASS()
class UCk_IntentGym_Step_Souls_TapHold_Arm : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_IntentGym_Step_Souls_TapHold_Await : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_IntentGym_Step_Souls_TapHold_Report : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

//----------------------------------------------------------------------------
// Station 2 — the charge accumulator
//----------------------------------------------------------------------------

UCLASS()
class UCk_IntentGym_Step_Souls_Charge_Arm : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_IntentGym_Step_Souls_Charge_Await : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_IntentGym_Step_Souls_Charge_Report : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

//----------------------------------------------------------------------------
// Station 3 — the charge a menu ate
//----------------------------------------------------------------------------

UCLASS()
class UCk_IntentGym_Step_Souls_Loss_Arm : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_IntentGym_Step_Souls_Loss_Await : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}

UCLASS()
class UCk_IntentGym_Step_Souls_Loss_Report : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
}
