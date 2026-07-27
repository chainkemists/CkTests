// Language=angelscript

//============================================================================
// AGGRO — AUTOMATION TEST: losing the LAST target broadcasts the calm edge
//============================================================================
//
// Regression pin. OnAggroActiveTargetChanged used to fire for every switch but
// NOT when the final target was forgotten: the forget path cleared _ActiveTarget
// itself, so Selection then compared an already-empty Incumbent against an empty
// Best, concluded nothing had changed, and stayed silent. A consumer that drives
// its combat state off this signal could learn about every acquisition and every
// switch, yet never learn the encounter had ended — leaving it latched onto a
// target that no longer exists.
//
// Two phases, because the bug was specific to the table EMPTYING:
//   1. Two targets, forget the active one -> broadcast carries the survivor
//      (proves the fix did not turn a clean switch into calm-then-re-engage).
//   2. Forget the survivor -> broadcast carries an INVALID new target.
//============================================================================

class UCk_AutoTest_Aggro_LastTargetForgotten_BroadcastsInvalidActive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle       _Context;
    private FCk_Handle_Aggro _Aggro;
    private FCk_Handle       _TargetA;
    private FCk_Handle       _TargetB;

    private int32      _BroadcastCount = 0;
    private bool       _LastNewWasValid = false;
    private FCk_Handle _LastNewTracked;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Context = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Equal distance so neither wins on falloff; MinimumTargetScore 0 (the default)
        // keeps both eligible so selection is decided purely by threat.
        _TargetA = Make_Target(FVector(500.0f, 0.0f, 0.0f));
        _TargetB = Make_Target(FVector(-500.0f, 0.0f, 0.0f));

        _Aggro = utils_aggro::Add(Owner, FCk_Fragment_Aggro_ParamsData());
        Assert_True(ck::IsValid(_Aggro), "Aggro composed on an entity with a Transform");
        if (IsFinished()) { return; }

        _Aggro.BindTo_OnActiveTargetChanged(
            FCk_Delegate_Aggro_OnActiveTargetChanged(this, n"OnActiveTargetChanged"));

        // A is the clear leader, so it becomes active first.
        _Aggro.Request_AddThreat(FCk_Request_Aggro_AddThreat(_TargetA, 100.0f));
        _Aggro.Request_AddThreat(FCk_Request_Aggro_AddThreat(_TargetB, 10.0f));

        ScheduleSettle(1.0f, n"OnEngaged");
    }

    private FCk_Handle Make_Target(FVector InLocation)
    {
        auto Target = utils_entity_lifetime::Request_CreateEntity(_Context);
        utils_transform::Add(Target, FTransform(InLocation), ECk_Replication::DoesNotReplicate);
        return Target;
    }

    UFUNCTION()
    private void OnActiveTargetChanged(
        FCk_Handle_Aggro       InAggro,
        FCk_Handle_AggroTarget InOldTarget,
        FCk_Handle_AggroTarget InNewTarget)
    {
        _BroadcastCount  += 1;
        _LastNewWasValid  = ck::IsValid(InNewTarget);
        _LastNewTracked   = _LastNewWasValid ? InNewTarget.Get_TrackedEntity() : FCk_Handle();
    }

    UFUNCTION()
    private void OnEngaged(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_LastNewWasValid && _LastNewTracked == _TargetA,
            "highest-threat target became active");
        if (IsFinished()) { return; }

        _BroadcastCount = 0;

        auto ActiveTarget = _Aggro.Get_ActiveTarget();
        Assert_True(ck::IsValid(ActiveTarget), "active target handle resolvable before forget");
        if (IsFinished()) { return; }
        ActiveTarget.Request_Forget();

        ScheduleSettle(1.0f, n"OnActiveForgotten");
    }

    UFUNCTION()
    private void OnActiveForgotten(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Phase 1: a survivor remains, so this must read as ONE clean switch onto B —
        // not a calm followed by a re-engage.
        Assert_True(_BroadcastCount == 1,
            "forgetting the active target with a survivor broadcasts exactly once");
        if (IsFinished()) { return; }
        Assert_True(_LastNewWasValid && _LastNewTracked == _TargetB,
            "the surviving target became active");
        if (IsFinished()) { return; }

        _BroadcastCount = 0;

        auto ActiveTarget = _Aggro.Get_ActiveTarget();
        Assert_True(ck::IsValid(ActiveTarget), "survivor is the active target");
        if (IsFinished()) { return; }
        ActiveTarget.Request_Forget();

        ScheduleSettle(1.0f, n"OnLastForgotten");
    }

    UFUNCTION()
    private void OnLastForgotten(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Phase 2: the regression this test exists for.
        Assert_True(_BroadcastCount == 1,
            "forgetting the LAST target still broadcasts the active-target change");
        if (IsFinished()) { return; }
        Assert_True(_LastNewWasValid == false,
            "the broadcast carries an INVALID new target (the calm edge)");
        if (IsFinished()) { return; }
        Assert_True(ck::Is_NOT_Valid(_Aggro.Get_ActiveTarget()),
            "no active target remains");
        if (IsFinished()) { return; }
        Assert_True(utils_aggro::Get_NumTrackedTargets(_Aggro) == 0,
            "threat table is empty");

        FinishSuccess();
    }

    private void ScheduleSettle(float InSeconds, FName InHandlerName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(InSeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_Context, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InHandlerName));
    }
}
