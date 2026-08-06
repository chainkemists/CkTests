// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: RACING EVENT-DRIVEN TRANSITIONS
//============================================================================
//
// Headless port of the SM-Racing-Event-Driven gym station. Spawns
// ACk_SmTest_RacingEventDriven_GymActor (which constructs the Idle/DestA/
// DestB SM with two racing timer-event-driven transitions) and asserts that
// the second-declared (faster) transition wins — i.e. that the state
// evaluator did NOT Break on the first Undetermined transition.
//
// See CkStateMachine_TestStates_RacingEventDriven.as for topology and the
// detailed bug description.
//
// Pattern B (settle-timer poll). Same shape as the Divergence-Timed test —
// spawn the gym actor, wait for the settle window, assert on counters.
//
// Settle window: SettleSeconds (0.8s by default) on the gym actor covers
// both the fast (~0.1s) and slow (~0.5s) paths plus replication cushion.
// _TimeoutSeconds = 2.0 gives test-runner buffer beyond settle.
//
// Acceptance:
//   Counter_DestB == 1, Counter_DestA == 0 — fix is live.
//   Counter_DestA == 1, Counter_DestB == 0 — bug is live (this is the red
//     state the test should be in before the framework fix lands).
//============================================================================

class UCk_AutoTest_StateMachine_RacingEventDrivenTransitions : UCk_AutoTest_Base
{
    // Tight 2s budget — 1.0s settle + buffer. Race-condition coverage; we
    // want regressions that slow it down to surface as failures, not pass
    // under the harness's 5s default.
    default _TimeoutSeconds = 2.0f;

    private ACk_SmTest_RacingEventDriven_GymActor _GymActor;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Deferred = true;
        _GymActor = Cast<ACk_SmTest_RacingEventDriven_GymActor>(
            SpawnActor(
                ACk_SmTest_RacingEventDriven_GymActor,
                FVector(0.0f, 0.0f, 0.0f),
                FRotator::ZeroRotator,
                NAME_None,
                Deferred));

        if (!ck::IsValid(_GymActor))
        {
            FinishFailure("SpawnActor returned invalid gym actor");
            return;
        }

        // Defaults already set on the actor: SlowDelay=0.5s, FastDelay=0.1s,
        // Settle=0.8s. No station handle — headless mode skips display push.
        _GymActor.StationHandle = FCk_Handle();
        FinishSpawningActor(_GymActor);

        // Settle: gym actor's SettleSeconds (0.8s) + replication buffer.
        auto LocalHandle = InHandle;
        auto SettleParams = FCk_Timer_Spec(FCk_Time(1.0f));
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

        // Expected (post-fix): the fast (FastDelay) transition wins despite
        // being declared second; SM lands on DestB exactly once.
        Assert_Equals_Int(_GymActor.Counter_DestB, 1,
            "DestB should be entered exactly once (fast timer should win the race)");
        Assert_Equals_Int(_GymActor.Counter_DestA, 0,
            "DestA must NOT be entered (slow timer was declared first; without fix, the evaluator Break's on its Undetermined and never sees DestB Pass)");

        FinishSuccess();
    }
}
