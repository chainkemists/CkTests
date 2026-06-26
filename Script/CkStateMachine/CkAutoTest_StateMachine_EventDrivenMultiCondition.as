// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: EVENT-DRIVEN MULTI-CONDITION
//============================================================================
//
// Locks in the framework contract that event-driven condition Pass results
// are preserved across transition Reset cycles.
//
// A single transition Idle->Finish carries TWO event-driven conditions:
//   FastEvent: MarkSatisfied at ~0.1s.
//   SlowEvent: MarkSatisfied at ~0.4s.
//
// Between t=0.1s and t=0.4s, the transition is in Fail (one cond Pass, one
// Fail). state.Evaluate cycles through Reset for that duration. FastEvent's
// Pass result must survive all those Reset cycles — when SlowEvent finally
// fires at 0.4s, the transition must see BOTH Pass and resolve to fire.
//
// This test passes today (auto-Fail-on-enter via direct fragment write,
// shortcut version) and must continue passing under any future change to
// Request_ResetTransition's fully-event-driven path. The contract being
// verified: "Reset preserves event-driven cond results."
//
// Settle window: 0.6s on the gym actor (enough for both events to resolve
// + replication cushion). Outer timer: 0.8s to give the autotest framework
// breathing room beyond settle.
//============================================================================

class UCk_AutoTest_StateMachine_EventDrivenMultiCondition : UCk_AutoTest_Base
{
    // 0.8s settle + buffer; tighter than the harness 5s default so a
    // regression that slows event-driven Reset preservation surfaces
    // as a timeout instead of silently passing.
    default _TimeoutSeconds = 2.0f;

    private ACk_SmTest_EventDrivenMultiCondition_GymActor _GymActor;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Deferred = true;
        _GymActor = Cast<ACk_SmTest_EventDrivenMultiCondition_GymActor>(
            SpawnActor(
                ACk_SmTest_EventDrivenMultiCondition_GymActor,
                FVector(0.0f, 0.0f, 0.0f),
                FRotator::ZeroRotator,
                NAME_None,
                Deferred));

        if (!ck::IsValid(_GymActor))
        {
            FinishFailure("SpawnActor returned invalid gym actor");
            return;
        }

        // Defaults already set on the actor: FastDelay=0.1s, SlowDelay=0.4s,
        // Settle=0.6s. No station handle — headless mode skips display push.
        _GymActor.StationHandle = FCk_Handle();
        FinishSpawningActor(_GymActor);

        // Settle: gym actor's SettleSeconds (0.6s) + buffer.
        auto LocalHandle = InHandle;
        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.8f));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(LocalHandle, SettleParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!ck::IsValid(_GymActor))
        {
            FinishFailure("Gym actor was destroyed before settle");
            return;
        }

        // The single observable invariant: SM transitioned exactly once,
        // which means BOTH event-driven conditions resolved Pass and the
        // transition fired. If FastEvent's Pass had been clobbered during
        // the Reset cycle, the transition would still see Fail when
        // SlowEvent fired and Counter_Finish would be 0.
        Assert_Equals_Int(_GymActor.Counter_Finish, 1,
            "SM should transition to Finish exactly once after both event-driven conditions resolve. Counter == 0 means FastEvent's Pass was lost across Reset cycles between FastEvent firing (~0.1s) and SlowEvent firing (~0.4s).");

        FinishSuccess();
    }
}
