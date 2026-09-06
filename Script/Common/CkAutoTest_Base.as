// Language=angelscript

//============================================================================
// CK AUTOMATION TEST - BASE CLASS
//============================================================================
//
// Headless test runner that sits on a transient entity. Authors subclass
// this and override DoBeginPlay to drive their feature.
//
// Wire-up (a C++ ACk_AutoTestRunner actor handles this):
//   1. C++ test actor spawns a subclass of UCk_AutoTest_Base on the world's
//      transient entity via UCk_Utils_EntityScript_UE::Request_SpawnEntity.
//   2. DoConstruct writes Status=Running to the result fragment.
//   3. DoBeginPlay (in the subclass) is where the test exercises the feature.
//   4. The subclass calls Assert_* helpers and FinishSuccess / FinishFailure.
//   5. On finish, the result fragment status flips to Passed/Failed.
//      The C++ actor polls each tick and reports the outcome to the engine.
//
// Timeout is handled by the engine via ACk_AutoTestRunner's TimeLimit,
// which is set from the actor's _TimeoutSeconds property. AS authors
// override the timeout via `default _TimeoutSeconds = X.Xf;` on the entity
// script; the wrapper generator propagates it to the generated wrapper CDO.
//
//----------------------------------------------------------------------------
// WRITING A TEST - the step sequencer
//----------------------------------------------------------------------------
//
// Declare the test as a list of named steps, then run them. Each step is
// either an ACTION (does something) or a WAIT (a predicate polled every frame
// until it returns true).
//
//   UFUNCTION(BlueprintOverride)
//   void DoBeginPlay(FCk_Handle InHandle)
//   {
//       Add_Step(          "arrange the observer and POI", n"Step_Arrange");
//       Add_Step_WaitUntil("POI reaches both projectors",  n"Check_InBoth");
//       Add_Step(          "explicitly hide the POI",      n"Step_Hide");
//       Add_Step_WaitUntil("POI leaves both projectors",   n"Check_InNeither");
//       Run_Steps(InHandle);
//   }
//
//   // ACTION - signature is FCk_Lambda_InHandle. InHandle is this test entity.
//   UFUNCTION()
//   private void Step_Hide(FCk_Handle InHandle, FInstancedStruct InPayload)
//   { utils_visible_range::Request_SetVisibility(_Vr, ECk_VisibleRange_ShowHide::Hide); }
//
//   // WAIT - signature is FCk_Predicate_InHandle_OutResult.
//   UFUNCTION()
//   private void Check_InNeither(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
//   {
//       auto Res = OutResult;   // NOT OutResult.Set(...) directly - see below
//       Res.Set(DoCompassHasPoi() == false && DoMinimapHasPoi() == false);
//   }
//
// When the last step completes the test finishes successfully on its own - no
// trailing FinishSuccess() is needed. Assertions inside a step are tagged with
// that step's name automatically, so a failure names where it came from.
//
// WHY WAIT ON A CONDITION RATHER THAN A FRAME COUNT. CkFoundation request
// handlers are deferred: a request enqueued this frame is drained by its
// processor on a later pass, and how many passes a given effect needs is a
// property of processor ORDERING, not of elapsed time. Waiting a fixed number
// of hops encodes a guess about that ordering into the test, so the test
// breaks when the ordering changes and silently depends on frame rate in the
// meantime. A predicate states what the test is actually waiting for,
// converges as soon as it holds, and - when it never holds - reports which
// named condition was still false instead of a bare engine timeout.
//
//============================================================================

// One entry in the step sequence. Actions and waits share the shape; _IsWait
// selects which delegate signature _FuncName is expected to satisfy.
USTRUCT()
struct FCk_AutoTest_Step
{
    UPROPERTY() FString _DisplayName;
    UPROPERTY() FName _FuncName;
    UPROPERTY() bool _IsWait = false;

    // Per-step ceiling on polls. Guards against one wedged condition burning
    // the whole test budget and reporting as though a later step were at
    // fault. Doubles as the frame count for a predicate-less settle step.
    UPROPERTY() int32 _FrameBudget = 0;

    // Optional DECLARED wall-clock ceiling for this step, in seconds. 0 means "no stated bound -
    // eventually is fine", which is the right contract for most steps. Set it when the step's whole
    // point is that something happens WITHIN a known cadence: a step named "the later truck is
    // targeted within rescan cadence" that cannot fail until the poll budget runs out is not
    // asserting the cadence, it is describing it.
    UPROPERTY() float _MaxSeconds = 0.0f;

    // For a predicate-LESS settle only: the span of wall-clock it lasts. 0 means the step is a
    // frame-counted settle instead. The two are different instruments, not two spellings of one -
    // see Add_Step_WaitFrames / Add_Step_WaitSeconds.
    UPROPERTY() float _SettleSeconds = 0.0f;

    FCk_AutoTest_Step(FString InDisplayName = "", FName InFuncName = n"", bool InIsWait = false, int32 InFrameBudget = 0, float InMaxSeconds = 0.0f, float InSettleSeconds = 0.0f)
    {
        _DisplayName = InDisplayName;
        _FuncName = InFuncName;
        _IsWait = InIsWait;
        _FrameBudget = InFrameBudget;
        _MaxSeconds = InMaxSeconds;
        _SettleSeconds = InSettleSeconds;
    }
}

// ====================================================================================================================

class UCk_AutoTest_Base : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    // Per-test timeout override. Authors override this on their entity-script
    // subclass via `default _TimeoutSeconds = X.Xf;` and the wrapper generator
    // reads the CDO at emit time, propagating it to the generated wrapper's
    // own _TimeoutSeconds (which the C++ runner applies to the engine
    // TimeLimit in PrepareTest). Default 5.0f matches ACk_AutoTestRunner's
    // compile-time default - leave it alone unless your test needs a tighter
    // or looser bound.
    UPROPERTY()
    float _TimeoutSeconds = 5.0f;

    // Multi-world shape this test expects. Default Standalone preserves the classic
    // single-PIE flow. Subclasses targeting multi-PIE override via
    // `default _NetMode = ECk_AutoTest_NetMode::...` (UCk_AutoTest_NetBase already
    // does this for Replicated). See ECk_AutoTest_NetMode for the per-value contract.
    UPROPERTY()
    ECk_AutoTest_NetMode _NetMode = ECk_AutoTest_NetMode::Standalone;

    // Polls a wait is allowed before it is declared stuck. Deliberately
    // generous: an over-large budget is bounded by the global deadline below,
    // while an under-sized one fails a merely-slow test.
    UPROPERTY()
    int32 _DefaultWaitFrameBudget = 240;

    // Wall-clock floor a predicate wait cannot fail faster than, however many polls it burned.
    //
    // The budget above is a FRAME count, and much of what tests wait on is a WALL-CLOCK cadence - a
    // once-a-second rescan, a settle timer, a day-cycle pulse. The two only agree at a known frame
    // rate. This project pins one - Config/DefaultEngine.ini [SystemSettings] t.MaxFPS=60 - and at 60
    // fps 240 polls IS the 4 seconds the field above intends; editor logs confirm it, e.g. a
    // CapacityFallbackAndTenQueueDeterminism step-1 wait reporting "240 polls (4.00s)".
    //
    // The budget breaks wherever that pin does not hold, and the pin is easy to lift by accident: any
    // harness passing `t.MaxFPS 0` un-caps the frame rate, and then 240 polls is well under a second.
    // Measured there: Bb_AutoTest_EmployeeOrders_UnloadLifecycle_ManagerReadopts step 6 waits on
    // BB_NpcAI_Processor_TaskStationArrival's 1.0s TruckRescanElapsed and reports "240 polls (0.45s)",
    // i.e. declared stuck before the thing it waits for can fire even once. A CVar a prior test failed
    // to restore does the same thing to whatever runs next.
    //
    // So the floor is not chasing faster machines - it makes the budget mean the same thing whether or
    // not the frame cap is in force. At the pinned 60 fps it is inert.
    //
    // It only ever makes a wait MORE patient, never less: it ANDs into the FAILURE branch only, so a
    // test that passes is unaffected, and it cannot lengthen a predicate-less WaitFrames settle. It
    // stays bounded above by the global _TimeoutSeconds deadline, so the worst case is a wedged
    // condition being reported by that deadline instead - which still names the pending step through
    // Get_CurrentContextLabel, though its "raise _TimeoutSeconds" advice is then the wrong advice.
    //
    // WHY 2.0 AND NOT THE 4.0 THE BUDGET INTENDS: at 4.0 the floor is unreachable for the 259 tests
    // declaring `_TimeoutSeconds = 3.0f`, because their deadline fires at 0.9*3.0 = 2.7s first. 2.0
    // clears every cadence measured in the corpus (the longest is a 1.0s rescan) while staying
    // reachable for those. The waits it does NOT reach are the ones waiting out multi-second PRODUCT
    // durations - PhoneBooth_AnswerFlow waits out BB_PhoneBooth_Hfsm's AnsweringDuration - and those
    // want a per-test override, which is what this being a UPROPERTY is for.
    UPROPERTY()
    float _DefaultWaitMinSeconds = 2.0f;


    // ----- Internal state -----
    private FCk_Handle SelfEntity;
    private bool _Finished = false;
    private int32 _AssertionsRun = 0;
    private int32 _AssertionsFailed = 0;
    private FString _FirstFailureMessage;

    // Out-of-subtree owners registered via Track_ForCleanup - destroyed at finish
    // so heavyweight tests can't leak into the next test in the shared PIE world.
    private TArray<FCk_Handle> _CleanupOwners;

    // Console variables this test moved. The prior value AND priority of each live in C++
    // (UCk_Utils_AutoTest_UE), because restoring a CVar means restoring both.
    private TArray<FName> _CVarOverrideNames;

    // The test's ONE deadline. Armed in DoConstruct, so its origin is the test itself -
    // see Arm_TestDeadline.
    private FCk_Handle_Timer _TestDeadlineTimer;
    private ECk_AutoTest_Status _PendingStatus = ECk_AutoTest_Status::Running;
    private FString _PendingMessage;

    // ----- Step sequencer -----
    private TArray<FCk_AutoTest_Step> _Steps;
    private int32 _CurrentStep = 0;
    private int32 _PollsInStep = 0;
    // Per-STEP elapsed, reset by Do_AdvanceStep. Drives the wait floor and any declared
    // per-step ceiling. There is deliberately no cumulative sequence timer beside it any more:
    // the whole-test clock is Arm_TestDeadline's timer, and a second accumulator claiming to
    // measure the same thing from a later origin is what 8l was.
    private float _SecondsInStep = 0.0f;
    private bool _StepsRunning = false;
    private FCk_Handle_Timer _StepTickTimer;

    // ----- Standalone WaitUntil (independent of the sequencer) -----
    private FName _WaitPredicateName;
    private FName _WaitContinuationName;
    private int32 _WaitPolls = 0;
    private int32 _WaitBudget = 0;
    private float _WaitMaxSeconds = 0.0f;
    private float _WaitSettleSeconds = 0.0f;
    private bool _WaitRunning = false;
    private float _WaitElapsedSeconds = 0.0f;
    private FCk_Handle_Timer _WaitTickTimer;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        SelfEntity = InHandle;

        // Mark result as Running immediately so the C++ runner can
        // distinguish "test entity exists and is going" from "test entity
        // not yet constructed".
        UCk_Utils_AutoTest_UE::Set_Result(
            SelfEntity, ECk_AutoTest_Status::Running, "", 0, 0);

        Arm_TestDeadline();

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    //------------------------------------------------------------------------
    // Step sequencer - declaration
    //------------------------------------------------------------------------

    // An action step. InFuncName must name a UFUNCTION on this class with the
    // FCk_Lambda_InHandle signature:
    //   UFUNCTION() private void Name(FCk_Handle InHandle, FInstancedStruct InPayload)
    // The action runs once and the sequence advances on the FOLLOWING tick, so
    // an action and the wait after it never share a tick - the wait's first
    // poll always observes at least one processor pass.
    protected void Add_Step(const FString& InDisplayName, FName InFuncName)
    {
        _Steps.Add(FCk_AutoTest_Step(InDisplayName, InFuncName, false, 0));
    }

    // A wait step. InPredicateName must name a UFUNCTION on this class with the
    // FCk_Predicate_InHandle_OutResult signature:
    //   UFUNCTION() private void Name(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    //
    // Answer through a LOCAL COPY, never the parameter directly:
    //   auto Res = OutResult;
    //   Res.Set(...);
    // AngelScript treats a by-value struct parameter as read-only and rejects
    // `OutResult.Set(...)` with "Non-const method call on read-only object
    // reference" (Script/ARCHITECTURE.md 9.1). The copy is not a workaround that
    // loses the write: FCk_SharedBool holds a shared cell, so the copy and the
    // parameter address the same bool.
    // InFrameBudget is a floor on POLLS, not a ceiling on time: a wait is not declared stuck until BOTH
    // it and _DefaultWaitMinSeconds are exhausted, so the effective budget is max(frames, floor). No
    // call site in the corpus passes fewer than 120 frames, so this changes nothing today.
    //
    // InMaxSeconds is the opposite knob and the one to reach for when the step's NAME makes a claim
    // about timing. It is a DECLARED wall-clock ceiling, and because it is declared it beats both
    // defaults above: a step that must converge inside a 1.0s rescan cadence fails at that bound
    // even though the generous poll budget and the 2.0s floor would both still be patient. Leave it
    // 0 - the default - for the ordinary "eventually" step, which is most of them.
    protected void Add_Step_WaitUntil(const FString& InDisplayName, FName InPredicateName, int32 InFrameBudget = 0, float InMaxSeconds = 0.0f)
    {
        _Steps.Add(FCk_AutoTest_Step(InDisplayName, InPredicateName, true,
            InFrameBudget > 0 ? InFrameBudget : _DefaultWaitFrameBudget, InMaxSeconds));
    }

    // A wait step that settles for a fixed number of PROCESSOR PASSES. Exactly N, at any frame
    // rate - that is the contract, and some tests depend on it (see the spec's WaitOneFrame /
    // WaitFrames section). Prefer Add_Step_WaitUntil over both.
    //
    // If what you actually need is a WINDOW OF TIME rather than a count of passes - and that is
    // what you need whenever the settle backs a NEGATIVE assertion - use Add_Step_WaitSeconds
    // instead. A frame count is only a duration at the frame rate it was written against.
    protected void Add_Step_WaitFrames(const FString& InDisplayName, int32 InFrames)
    {
        _Steps.Add(FCk_AutoTest_Step(InDisplayName, n"", true, InFrames > 1 ? InFrames : 1));
    }

    // A wait step that settles for a fixed SPAN OF WALL-CLOCK.
    //
    // THIS IS THE ONE FOR A NEGATIVE ASSERTION - "nothing happened in this window". The thing you
    // are proving absent is driven by a wall-clock cadence (a once-a-second rescan, a settle timer,
    // a day-cycle pulse), so the window has to be measured in the same units or it is not a window
    // at all. A 30-frame settle is 0.5s at the pinned 60 fps (Config/DefaultEngine.ini
    // [SystemSettings] t.MaxFPS=60) but 0.06s with the cap lifted - and at 0.06s "the count did not
    // move" is not an assertion that CAN fail. A test whose entire purpose is to prove an absence
    // then passes vacuously, and passes LOUDER the faster the machine.
    //
    // The frame budget underneath is still enforced, so the settle is max(the declared seconds, one
    // poll) - it can never return before a single processor pass has run.
    protected void Add_Step_WaitSeconds(const FString& InDisplayName, float InSeconds)
    {
        _Steps.Add(FCk_AutoTest_Step(InDisplayName, n"", true, 1, 0.0f, InSeconds));
    }

    // Starts the sequence. Call once, at the end of DoBeginPlay.
    protected void Run_Steps(FCk_Handle InHandle)
    {
        if (_StepsRunning) { return; }

        if (_Steps.IsEmpty())
        {
            FinishFailure("Run_Steps called with no steps declared - use Add_Step / Add_Step_WaitUntil first");
            return;
        }

        SelfEntity = InHandle;
        _StepsRunning = true;
        _CurrentStep = 0;
        _PollsInStep = 0;
        _SecondsInStep = 0.0f;
        _StepTickTimer = Do_MakePerFrameTimer(n"INTERNAL__AutoTest_StepTick");
    }

    // Where the test currently is, for diagnostics - the active sequencer step
    // or the active standalone wait. Empty when neither is running. Every
    // failure path routes its location through here rather than embedding it,
    // so a message is prefixed exactly once no matter who raises it.
    FString Get_CurrentContextLabel() const
    {
        if (_StepsRunning && _CurrentStep < _Steps.Num())
        {
            auto StepName = _Steps[_CurrentStep]._DisplayName;
            auto Ordinal = _CurrentStep + 1;
            auto Total = _Steps.Num();
            return f"step {Ordinal}/{Total} '{StepName}'";
        }

        if (_WaitRunning)
        {
            if (_WaitPredicateName == NAME_None)
            {
                auto Frames = _WaitBudget;
                return f"WaitFrames({Frames})";
            }
            auto Pred = _WaitPredicateName;
            return f"WaitUntil('{Pred}')";
        }

        return "";
    }

    //------------------------------------------------------------------------
    // Step sequencer - execution
    //------------------------------------------------------------------------

    UFUNCTION()
    private void INTERNAL__AutoTest_StepTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_Finished || _StepsRunning == false) { return; }

        _SecondsInStep += float(InDeltaT.Get_Seconds());

        if (_CurrentStep >= _Steps.Num())
        {
            _StepsRunning = false;
            FinishSuccess();
            return;
        }

        // No deadline check here. The test's one deadline is Arm_TestDeadline's timer, whose
        // origin is DoConstruct - always at or before Run_Steps, so a sequence-local check could
        // only ever fire second. The accumulator it used to need is gone with it.

        auto Step = _Steps[_CurrentStep];

        if (Step._IsWait == false)
        {
            Do_InvokeStepAction(Step);
            Do_AdvanceStep();
            return;
        }

        // A wait with no predicate is a settle: the budget IS the wait. Which budget depends on
        // which instrument the author reached for - passes (Add_Step_WaitFrames) or wall-clock
        // (Add_Step_WaitSeconds). Both are enforced, so a seconds-settle still runs at least one
        // poll and a frames-settle is unaffected by either.
        if (Step._FuncName == NAME_None)
        {
            _PollsInStep++;
            if (_PollsInStep < Step._FrameBudget) { return; }
            if (_SecondsInStep < Step._SettleSeconds) { return; }
            Do_AdvanceStep();
            return;
        }

        if (Do_EvaluatePredicate(Step._FuncName))
        {
            Do_AdvanceStep();
            return;
        }

        // A DECLARED ceiling is the step's stated contract, so it beats both defaults - the poll
        // budget is a generous guard and the floor exists to stop a wait being declared stuck too
        // early, and neither should keep waiting past a bound the author wrote down.
        if (Step._MaxSeconds > 0.0f && _SecondsInStep >= Step._MaxSeconds)
        {
            auto Cond = Step._FuncName;
            auto Bound = Step._MaxSeconds;
            auto Elapsed = _SecondsInStep;
            FinishFailure(f"condition '{Cond}' did not hold within the declared {Bound :.2}s bound ({Elapsed :.2}s elapsed) - the step asserts a cadence, so this is a real timing regression, not a slow machine");
            return;
        }

        _PollsInStep++;
        if (Step._MaxSeconds <= 0.0f && _PollsInStep >= Step._FrameBudget && _SecondsInStep >= _DefaultWaitMinSeconds)
        {
            auto Cond = Step._FuncName;
            auto Budget = Step._FrameBudget;
            auto Elapsed = _SecondsInStep;
            auto Floor = _DefaultWaitMinSeconds;
            FinishFailure(f"condition '{Cond}' never became true within {Budget} polls / {Elapsed :.2}s (floor {Floor :.2}s)");
        }
    }

    private void Do_AdvanceStep()
    {
        _CurrentStep++;
        _PollsInStep = 0;
        _SecondsInStep = 0.0f;
    }

    private void Do_InvokeStepAction(const FCk_AutoTest_Step& InStep)
    {
        auto Action = FCk_Lambda_InHandle(this, InStep._FuncName);
        if (Action.IsBound() == false)
        {
            auto Fn = InStep._FuncName;
            FinishFailure(f"no UFUNCTION named '{Fn}' on this test - an action step needs `UFUNCTION() private void {Fn}(FCk_Handle InHandle, FInstancedStruct InPayload)`");
            return;
        }
        Action.ExecuteIfBound(SelfEntity, FInstancedStruct());
    }

    // Shared by the sequencer and the standalone WaitUntil. Returns false and
    // fails the test when the name does not resolve - distinguishing an
    // unbound name from a forever-false condition is the difference between a
    // one-line fix and an afternoon.
    private bool Do_EvaluatePredicate(FName InPredicateName)
    {
        auto Predicate = FCk_Predicate_InHandle_OutResult(this, InPredicateName);
        if (Predicate.IsBound() == false)
        {
            FinishFailure(f"no UFUNCTION named '{InPredicateName}' on this test - a wait predicate needs `UFUNCTION() private void {InPredicateName}(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)`");
            return false;
        }

        auto Result = utils_shared_bool::Make(false);
        Predicate.ExecuteIfBound(SelfEntity, Result, FInstancedStruct());
        return Result.Get();
    }

    // A zero-duration ResetOnDone timer bound to OnUpdate is the per-frame hook
    // for an entity script. OnUpdate - not OnDone - is what fires once per
    // processor pass; a zero-duration OnDone can re-fire within the pass that
    // added it.
    private FCk_Handle_Timer Do_MakePerFrameTimer(FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(SelfEntity, Params);
        Timer.BindTo_OnUpdate(FCk_Delegate_Timer(this, InCallbackName));
        return Timer;
    }

    //------------------------------------------------------------------------
    // Standalone WaitUntil - for tests that drive their own callback chain
    // rather than declaring a step list. This is the drop-in replacement for a
    // chain of WaitOneFrame hops.
    //------------------------------------------------------------------------

    // Polls InPredicateName every frame until it returns true, then calls
    // InContinuationName once. On budget exhaustion the test fails naming the
    // predicate. The continuation takes the FCk_Delegate_Timer signature, the
    // same shape WaitOneFrame callbacks already use:
    //   UFUNCTION() private void Name(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    //
    // InMaxSeconds is the declared wall-clock ceiling, exactly as on Add_Step_WaitUntil: set it when
    // the wait is asserting a cadence rather than merely awaiting one, and it beats both the poll
    // budget and _DefaultWaitMinSeconds.
    protected void WaitUntil(FName InPredicateName, FName InContinuationName, int32 InFrameBudget = 0, float InMaxSeconds = 0.0f)
    {
        if (_WaitRunning)
        {
            FinishFailure(f"WaitUntil('{InPredicateName}') called while already waiting on '{_WaitPredicateName}' - one standalone wait at a time");
            return;
        }

        _WaitPredicateName = InPredicateName;
        _WaitContinuationName = InContinuationName;
        _WaitPolls = 0;
        _WaitBudget = InFrameBudget > 0 ? InFrameBudget : _DefaultWaitFrameBudget;
        _WaitMaxSeconds = InMaxSeconds;
        _WaitSettleSeconds = 0.0f;
        _WaitElapsedSeconds = 0.0f;
        _WaitRunning = true;

        // One timer for the whole test, reused. Creating a fresh one per wait
        // would overlap with the previous one: Request_DestroyEntity is
        // deferred, so the old timer stays bound for several ticks and would
        // drive the NEXT wait alongside its own.
        if (ck::Is_NOT_Valid(_WaitTickTimer))
        { _WaitTickTimer = Do_MakePerFrameTimer(n"INTERNAL__AutoTest_WaitTick"); }
        else
        { utils_timer::Request_Resume(_WaitTickTimer); }
    }

    // Yields a fixed number of frames, then calls InContinuationName. Reach for
    // this ONLY when there is no observable condition to wait on - the canonical
    // case is asserting that something does NOT happen, where the whole point is
    // that no state changes. Everywhere else use WaitUntil: a frame count cannot
    // state what it is waiting for, and cannot report anything useful when the
    // thing never arrives.
    protected void WaitFrames(int32 InFrames, FName InContinuationName)
    {
        if (_WaitRunning)
        {
            FinishFailure(f"WaitFrames called while already waiting on '{_WaitPredicateName}' - one standalone wait at a time");
            return;
        }

        _WaitPredicateName = NAME_None;
        _WaitContinuationName = InContinuationName;
        _WaitPolls = 0;
        _WaitBudget = InFrames > 1 ? InFrames : 1;
        _WaitMaxSeconds = 0.0f;
        _WaitSettleSeconds = 0.0f;
        _WaitElapsedSeconds = 0.0f;
        _WaitRunning = true;

        if (ck::Is_NOT_Valid(_WaitTickTimer))
        { _WaitTickTimer = Do_MakePerFrameTimer(n"INTERNAL__AutoTest_WaitTick"); }
        else
        { utils_timer::Request_Resume(_WaitTickTimer); }
    }

    // Yields a fixed SPAN OF WALL-CLOCK, then calls InContinuationName. The standalone twin of
    // Add_Step_WaitSeconds - reach for it for the same reason: a settle backing a NEGATIVE
    // assertion has to be a real window, and a frame count is only a window at the frame rate it
    // was written against. See Add_Step_WaitSeconds for the full argument.
    protected void WaitSeconds(float InSeconds, FName InContinuationName)
    {
        if (_WaitRunning)
        {
            FinishFailure(f"WaitSeconds called while already waiting on '{_WaitPredicateName}' - one standalone wait at a time");
            return;
        }

        _WaitPredicateName = NAME_None;
        _WaitContinuationName = InContinuationName;
        _WaitPolls = 0;
        _WaitBudget = 1;
        _WaitMaxSeconds = 0.0f;
        _WaitSettleSeconds = InSeconds;
        _WaitElapsedSeconds = 0.0f;
        _WaitRunning = true;

        if (ck::Is_NOT_Valid(_WaitTickTimer))
        { _WaitTickTimer = Do_MakePerFrameTimer(n"INTERNAL__AutoTest_WaitTick"); }
        else
        { utils_timer::Request_Resume(_WaitTickTimer); }
    }

    UFUNCTION()
    private void INTERNAL__AutoTest_WaitTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_Finished || _WaitRunning == false) { return; }

        _WaitElapsedSeconds += float(InDeltaT.Get_Seconds());

        // No deadline check here either, and this is the one that mattered: _WaitElapsedSeconds
        // is reset by EVERY WaitUntil/WaitFrames call, so a callback-chain test with N sequential
        // waits used to get N * 0.9 * _TimeoutSeconds of runway against the engine's single
        // _TimeoutSeconds - it lost that race unconditionally, not just when it was slow.
        // Arm_TestDeadline's timer is the bound now. _WaitElapsedSeconds stays as the per-wait
        // floor accumulator below, which is what it is actually good for.

        // A nameless wait is a settle: the budget IS the wait, in whichever unit the author asked
        // for - passes (WaitFrames) or wall-clock (WaitSeconds). Both are enforced.
        if (_WaitPredicateName == NAME_None)
        {
            _WaitPolls++;
            if (_WaitPolls < _WaitBudget) { return; }
            if (_WaitElapsedSeconds < _WaitSettleSeconds) { return; }
            Do_DispatchWaitContinuation(InTimer, InChrono, InDeltaT);
            return;
        }

        if (Do_EvaluatePredicate(_WaitPredicateName))
        {
            // Resolve the continuation while _WaitRunning is still true, so an
            // unbound name is reported against this wait rather than against
            // nothing.
            Do_DispatchWaitContinuation(InTimer, InChrono, InDeltaT);
            return;
        }

        // A declared ceiling beats both defaults - see Add_Step_WaitUntil.
        if (_WaitMaxSeconds > 0.0f && _WaitElapsedSeconds >= _WaitMaxSeconds)
        {
            auto Cond = _WaitPredicateName;
            auto Bound = _WaitMaxSeconds;
            auto Elapsed = _WaitElapsedSeconds;
            FinishFailure(f"condition '{Cond}' did not hold within the declared {Bound :.2}s bound ({Elapsed :.2}s elapsed) - the wait asserts a cadence, so this is a real timing regression, not a slow machine");
            return;
        }

        _WaitPolls++;
        if (_WaitMaxSeconds <= 0.0f && _WaitPolls >= _WaitBudget && _WaitElapsedSeconds >= _DefaultWaitMinSeconds)
        {
            auto Cond = _WaitPredicateName;
            auto Budget = _WaitBudget;
            auto Elapsed = _WaitElapsedSeconds;
            auto Floor = _DefaultWaitMinSeconds;
            FinishFailure(f"condition '{Cond}' never became true within {Budget} polls / {Elapsed :.2}s (floor {Floor :.2}s)");
        }
    }

    private void Do_DispatchWaitContinuation(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // Resolve the continuation while _WaitRunning is still true, so an
        // unbound name is reported against this wait rather than against nothing.
        auto Continuation = FCk_Delegate_Timer(this, _WaitContinuationName);
        if (Continuation.IsBound() == false)
        {
            auto Fn = _WaitContinuationName;
            FinishFailure(f"no UFUNCTION named '{Fn}' to continue to - needs `UFUNCTION() private void {Fn}(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)`");
            return;
        }

        // Stop before dispatching: the continuation commonly starts the next
        // wait, and a still-live timer would double-drive it.
        Do_StopWaitTick();
        Continuation.ExecuteIfBound(InTimer, InChrono, InDeltaT);
    }

    private void Do_StopWaitTick()
    {
        _WaitRunning = false;
        if (ck::IsValid(_WaitTickTimer))
        { utils_timer::Request_Pause(_WaitTickTimer); }
    }

    //------------------------------------------------------------------------
    // Finish helpers
    //------------------------------------------------------------------------

    bool IsFinished() const
    {
        return _Finished;
    }

    // Move a console variable for the duration of THIS test. The value it held before is
    // captured on the first override and put back at finish, on the success AND failure paths.
    //
    // Use this instead of System::ExecuteConsoleCommand. A lane is ONE editor process running its
    // tests back to back, so a CVar left moved is inherited by every test after this one - and
    // timing CVars (t.MaxFPS, r.VSync) change the frame budget of all of them, which surfaces as
    // unrelated wait predicates running out of polls. "Restoring" by executing a second console
    // command with a hardcoded literal is not restoring: it imposes the test author's guess of the
    // default on the rest of the lane, which on any project whose default differs is
    // indistinguishable from not restoring at all.
    protected void Set_CVarForTest(FName InName, const FString& InValue)
    {
        if (Do_TrackCVarForRestore(InName) == false)
        { return; }

        UCk_Utils_AutoTest_UE::Request_PushCVarOverride(InName, InValue);
    }

    // For a variable this test does not set itself but that something it INVOKES will move on its
    // behalf - HighResShot rewrites r.SceneColorFormat, r.PostProcessingColorFormat and r.ForceLOD,
    // for instance. Captures the current value now so the base can put it back at finish.
    protected void Snapshot_CVarForTest(FName InName)
    {
        if (Do_TrackCVarForRestore(InName) == false)
        { return; }

        UCk_Utils_AutoTest_UE::Request_PushCVarSnapshot(InName);
    }

    private bool Do_TrackCVarForRestore(FName InName)
    {
        if (UCk_Utils_AutoTest_UE::Get_CVarExists(InName) == false)
        {
            FinishFailure(f"no console variable named '{InName}' - check the spelling, or whether the module that registers it is loaded in a test boot");
            return false;
        }

        _CVarOverrideNames.AddUnique(InName);
        return true;
    }

    private void Restore_CVarOverrides()
    {
        for (auto CVarName : _CVarOverrideNames)
        { UCk_Utils_AutoTest_UE::Request_PopCVarOverride(CVarName); }

        _CVarOverrideNames.Empty();
    }

    // Register an out-of-subtree entity ROOT to destroy when the test finishes: anything
    // you spawned UNDER an ActorRelay channel, anything owned by ck::TransientEntity(),
    // and the subordinates a driver spawns and exposes (e.g. Get_EmployeeManager())
    // in short, anything NOT parented to this runner entity. The harness's own per-test
    // teardown (ACk_AutoTestRunner::Destroy_RunnerEntity) cascades ONLY the runner's
    // lifetime subtree, so these escape it and leak into every later test in the shared
    // PIE world. That is not a local problem: drivers discover their subjects by
    // WORLD-scoped tag-scan, so one leaked entity silently breaks unrelated tests far
    // away from the one that leaked it. Registering here makes the base destroy them at
    // finish, correctly sequenced (destroy -> settle -> result-write across frames) so a
    // tracked destroy can never race the result the C++ runner polls.
    //
    // NEVER register the ActorRelay CHANNEL entity itself (InResult.Get_ChannelEntity()).
    // Channels are POOLED and SHARED with live production subsystems, the API is
    // acquire-only by design (acquisition is stateless pool selection - there is no
    // checkout to return), and for Generic groups the pool NEVER regrows. Destroying one
    // kills ActorRelay for the remainder of the PIE session - i.e. for every test after
    // yours. Register what you spawned UNDER the channel, never the channel.
    protected void Track_ForCleanup(FCk_Handle InOwner)
    {
        if (ck::Is_NOT_Valid(InOwner)) { return; }
        // Never the runner: its entity holds the FCk_AutoTest_Result fragment (and any
        // feature composed onto it - e.g. a Mark_AsGlobal DayCycle - which the harness
        // cascades anyway). Destroying it would nuke the result before it is polled.
        if (InOwner == SelfEntity) { return; }
        _CleanupOwners.AddUnique(InOwner);
    }

    // THE test deadline. One clock, one origin, and the origin is the test.
    //
    // The engine's TimeLimit reports a timeout WITHOUT running this class's finish path:
    // AFunctionalTest::Tick calls OnTimeout -> FinishTest, and ACk_AutoTestRunner::FinishTest
    // goes straight to Destroy_RunnerEntity. Finalize never runs there, so a test the engine
    // times out drains NOTHING - not _CleanupOwners (every out-of-subtree entity it built
    // survives into the rest of the lane) and not _CVarOverrideNames (every console variable it
    // moved stays moved for every test after it). Both are silent, and both land on some later,
    // innocent test.
    //
    // So this fires just inside the engine's deadline and routes the failure through
    // FinishFailure -> Finalize, which cleans up and names the test that wedged.
    //
    // ARMED IN DoConstruct, UNCONDITIONALLY. That is the whole point, and it is what three
    // earlier versions of this got wrong:
    //   - arming on the first Track_ForCleanup only won the race if that first claim landed
    //     inside 0.1 * _TimeoutSeconds of test start, which a test claiming an ASYNCHRONOUSLY
    //     spawned thing cannot do by construction;
    //   - the sequencer's own check was anchored at Run_Steps;
    //   - the standalone wait's was anchored at each individual WaitUntil, so it reset N times
    //     over a test the engine only gives one budget to.
    // Every one of those origins is later than the engine's, so every one of them could lose.
    // DoConstruct cannot: ACk_AutoTestRunner::IsReady gates StartTest - and therefore the
    // engine's TotalTime - on the runner entity existing, i.e. on this very construct.
    //
    // COST: one one-shot timer per test, where the lazy arming meant most tests carried none.
    // Bought with a NAMED timeout for every test instead of the engine's anonymous TimesUp, plus
    // the two drains above actually happening. If this timer itself never fires - a wedged ECS,
    // a stalled timer processor - the engine's TimeLimit is still underneath as the net, which is
    // exactly the failure mode worth leaving it for.
    private void Arm_TestDeadline()
    {
        if (ck::IsValid(_TestDeadlineTimer)) { return; }

        // 0.9 leaves room for the result write and the C++ runner's next poll.
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(_TimeoutSeconds * 0.9f));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);

        _TestDeadlineTimer = utils_timer::Add(SelfEntity, Params);
        _TestDeadlineTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"INTERNAL__AutoTest_TestDeadline"));
    }

    UFUNCTION()
    private void INTERNAL__AutoTest_TestDeadline(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_Finished) { return; }

        auto Deadline = _TimeoutSeconds * 0.9f;
        auto Tracked = _CleanupOwners.Num();

        // A test driving its own callback chain (its own timers, no Run_Steps and no WaitUntil in
        // flight) has no context to name, and the label is empty. Say nothing rather than "at: .".
        auto Where = Get_CurrentContextLabel();
        FString At = "";
        if (Where != "")
        { At = f" at: {Where}"; }

        FString Leaked = "";
        if (Tracked > 0)
        { Leaked = f" Destroying {Tracked} tracked out-of-subtree owner(s) rather than leaking them into the rest of the lane."; }

        FinishFailure(f"timed out after {Deadline :.2}s (90% of _TimeoutSeconds){At}. Raise `default _TimeoutSeconds` if the test is merely slow.{Leaked}");
    }

    void FinishSuccess()
    {
        if (_Finished) { return; }
        _Finished = true;
        Do_StopAllTicks();
        Finalize(_AssertionsFailed > 0 ? ECk_AutoTest_Status::Failed : ECk_AutoTest_Status::Passed,
                 _FirstFailureMessage);
    }

    void FinishFailure(const FString& InMessage)
    {
        if (_Finished) { return; }
        _Finished = true;
        // Capture the label BEFORE the tick teardown clears the running flags,
        // otherwise a failure raised from inside a step loses its location.
        auto Where = Get_CurrentContextLabel();
        Do_StopAllTicks();
        if (_FirstFailureMessage == "")
        {
            _FirstFailureMessage = Where == "" ? InMessage : f"{Where}: {InMessage}";
        }
        _AssertionsFailed++;
        Finalize(ECk_AutoTest_Status::Failed, _FirstFailureMessage);
    }

    // The per-frame drivers must stop before the result is written: they live
    // on the runner entity, and a tick landing between the destroy queue and
    // the settle-frame result write would poll a half-torn-down test.
    private void Do_StopAllTicks()
    {
        _StepsRunning = false;
        if (ck::IsValid(_StepTickTimer))
        { utils_timer::Request_Pause(_StepTickTimer); }
        Do_StopWaitTick();
    }

    // Writes the terminal result, releasing any tracked out-of-subtree owners first.
    // Untracked tests (the overwhelming majority) write synchronously - behaviour is
    // identical to the classic path. Tracked tests queue the deferred destroys, then
    // write the result one frame later so the destroys are registered before the
    // poller next reads the result (the destroys never touch this runner, so its
    // result fragment survives to be written in the settle callback).
    private void Finalize(ECk_AutoTest_Status InStatus, const FString& InMessage)
    {
        // Both FinishSuccess and FinishFailure land here, so an early-out failure cannot skip
        // the restore. Synchronous: a CVar write needs no settle frame.
        Restore_CVarOverrides();

        if (ck::IsValid(_TestDeadlineTimer))
        { utils_timer::Request_Pause(_TestDeadlineTimer); }

        if (_CleanupOwners.IsEmpty())
        {
            WriteResult(InStatus, InMessage);
            return;
        }

        _PendingStatus = InStatus;
        _PendingMessage = InMessage;
        for (auto Owner : _CleanupOwners)
        {
            if (ck::IsValid(Owner))
            { utils_entity_lifetime::Request_DestroyEntity(Owner); }
        }
        _CleanupOwners.Empty();
        WaitOneFrame(n"INTERNAL__AutoTest_OnCleanupSettled");
    }

    UFUNCTION()
    private void INTERNAL__AutoTest_OnCleanupSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        WriteResult(_PendingStatus, _PendingMessage);
    }

    //------------------------------------------------------------------------
    // Assertions - increment counters, stash the first failure, but do NOT
    // auto-finish the test. Subclasses decide when to call FinishSuccess.
    //------------------------------------------------------------------------

    void Assert_True(bool InCondition, const FString& InMessage)
    {
        _AssertionsRun++;
        if (!InCondition)
        {
            _AssertionsFailed++;
            if (_FirstFailureMessage == "")
            {
                // Tagging with the active step turns "expected 3, got 0" into a
                // located failure without the author threading context by hand.
                auto Where = Get_CurrentContextLabel();
                _FirstFailureMessage = Where == "" ? InMessage : f"{Where}: {InMessage}";
            }
            // Failures are surfaced via the result fragment; the C++ runner
            // turns them into FinishTest(Failed, ...) messages. Avoid ck::Trace
            // here - UE's automation framework treats Warning-level log output
            // during a functional test as a test failure.
        }
    }

    void Assert_False(bool InCondition, const FString& InMessage)
    {
        Assert_True(InCondition == false, InMessage);
    }

    void Assert_Equals_Int(int32 InActual, int32 InExpected, const FString& InMessage)
    {
        Assert_True(InActual == InExpected,
            f"{InMessage} (expected {InExpected}, got {InActual})");
    }

    void Assert_Equals_Float(float InActual, float InExpected, float InTolerance, const FString& InMessage)
    {
        Assert_True(Math::Abs(InActual - InExpected) <= InTolerance,
            f"{InMessage} (expected {InExpected :.4} +/- {InTolerance :.4}, got {InActual :.4})");
    }

    void Assert_Equals_String(const FString& InActual, const FString& InExpected, const FString& InMessage)
    {
        Assert_True(InActual == InExpected,
            f"{InMessage} (expected '{InExpected}', got '{InActual}')");
    }

    void Assert_Valid(const FCk_Handle& InHandle, const FString& InMessage)
    {
        Assert_True(ck::IsValid(InHandle), f"{InMessage} (handle is invalid)");
    }

    void Assert_Invalid(const FCk_Handle& InHandle, const FString& InMessage)
    {
        Assert_True(ck::Is_NOT_Valid(InHandle), f"{InMessage} (handle is unexpectedly valid)");
    }

    //------------------------------------------------------------------------
    // WaitOneFrame - legacy settle helper.
    //
    // Schedules InCallbackName via a 0.05s CkTimer. Note what that does and
    // does not guarantee: it yields AT LEAST one frame, but the number of
    // frames it yields scales with frame rate (one frame at 20fps, roughly six
    // at 120fps). It is therefore a poor way to wait for a specific number of
    // processor passes, and chaining N of them encodes a guess about processor
    // ordering into the test.
    //
    // Prefer Add_Step_WaitUntil / WaitUntil, which poll a named condition and
    // report that condition by name when it never comes true. WaitOneFrame is
    // retained unchanged for tests that have not been migrated.
    //
    // The callback must have the FCk_Delegate_Timer signature:
    //   UFUNCTION()
    //   private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    //------------------------------------------------------------------------

    void WaitOneFrame(FName InCallbackName)
    {
        // 0.05s rather than 0.0: a zero-duration timer can fire OnDone within
        // the same processor pass that added it, racing the very side-effect
        // processors we're trying to wait for.
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(SelfEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    //------------------------------------------------------------------------
    // Result fragment write - single source of truth for the C++ poller.
    //------------------------------------------------------------------------

    private void WriteResult(ECk_AutoTest_Status InStatus, const FString& InMessage)
    {
        UCk_Utils_AutoTest_UE::Set_Result(
            SelfEntity, InStatus, InMessage, _AssertionsRun, _AssertionsFailed);
    }
}
