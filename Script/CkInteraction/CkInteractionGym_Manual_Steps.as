// Language=angelscript

//============================================================================
// MANUAL INTERACTION GYM - STEP STATES
//============================================================================
//
// The demo sequence for the ManuallyCompleted interaction station, as a
// CkStateMachine graph. Replaces the `AutoStep % 4` + if-else dispatch that
// used to live in the station's AutoTick.
//
//   StartForSuccess -> EndSuccess -> StartForFail -> EndFail -> (cycle)
//
// The cycle needs two distinct Start states because a step's identity IS its
// state class: "start, then end successfully" and "start, then end in failure"
// are different steps even though they perform the same action.
//
// Dwell is UCk_Gym_Dwell_Short (1.0s), which is exactly the interval the
// station's gym_auto::Setup used - migrating must not retime the demo.
//
// Each state acts on the STATION ENTITY through utils_*, never on the station
// script's members. In particular the in-flight interaction is re-derived from
// the target's Get_CurrentInteractions instead of read off the station's
// ActiveInteraction field, which a separate entity script has no access to.
//============================================================================

namespace interaction_gym_manual
{
    FCk_Handle_InteractTarget Get_Target(FCk_Handle InStation)
    {
        if (ck::Is_NOT_Valid(InStation))
        { return FCk_Handle_InteractTarget(); }

        // TryGet is keyed by CHANNEL, not just owner - an entity can host targets
        // on several channels. The station composes its target on the gym's
        // default channel, so resolve against the same one.
        return utils_interact_target::TryGet(InStation, interaction_gym_helpers::DefaultChannel());
    }

    void Request_Start(FCk_Handle InStation)
    {
        auto Target = Get_Target(InStation);
        if (ck::Is_NOT_Valid(Target))
        { return; }

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(InStation);
        Request.Set_InteractInstigator(InStation);
        utils_interact_target::Request_StartInteraction(Target, Request);
    }

    // Ends whatever is currently in flight. A no-op when nothing is, which is
    // the correct behaviour for a demo the viewer may have paused mid-cycle.
    void Request_End(FCk_Handle InStation, ECk_SucceededFailed InResult)
    {
        auto Target = Get_Target(InStation);
        if (ck::Is_NOT_Valid(Target))
        { return; }

        auto InFlight = utils_interact_target::Get_CurrentInteractions(Target);
        if (InFlight.Num() == 0)
        { return; }

        utils_interaction::Request_EndInteraction(
            InFlight[0], FCk_Request_Interaction_EndInteraction(InResult));
    }
}

// ====================================================================================================================

UCLASS()
class UCk_InteractionManualGym_Step_StartForSuccess : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InteractionManualGym_Step_EndSuccess);
        AddCondition(Trans, UCk_Gym_Dwell_Short);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        interaction_gym_manual::Request_Start(Get_StationEntity());
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InteractionManualGym_Step_EndSuccess : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InteractionManualGym_Step_StartForFail);
        AddCondition(Trans, UCk_Gym_Dwell_Short);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        interaction_gym_manual::Request_End(Get_StationEntity(), ECk_SucceededFailed::Succeeded);
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InteractionManualGym_Step_StartForFail : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InteractionManualGym_Step_EndFail);
        AddCondition(Trans, UCk_Gym_Dwell_Short);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        interaction_gym_manual::Request_Start(Get_StationEntity());
    }
}

// ----------------------------------------------------------------------------

UCLASS()
class UCk_InteractionManualGym_Step_EndFail : UCk_Gym_StepState
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_InteractionManualGym_Step_StartForSuccess);
        AddCondition(Trans, UCk_Gym_Dwell_Short);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        interaction_gym_manual::Request_End(Get_StationEntity(), ECk_SucceededFailed::Failed);
    }
}
