// Language=angelscript

//============================================================================
// CK AUTOMATION TEST — BASE CLASS
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
// WRITING A TEST — the step sequencer
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
//   // ACTION — signature is FCk_Lambda_InHandle. InHandle is this test entity.
//   UFUNCTION()
//   private void Step_Hide(FCk_Handle InHandle, FInstancedStruct InPayload)
//   { utils_visible_range::Request_SetVisibility(_Vr, ECk_VisibleRange_ShowHide::Hide); }
//
//   // WAIT — signature is FCk_Predicate_InHandle_OutResult.
//   UFUNCTION()
//   private void Check_InNeither(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
//   {
//       auto Res = OutResult;   // NOT OutResult.Set(...) directly — see below
//       Res.Set(DoCompassHasPoi() == false && DoMinimapHasPoi() == false);
//   }
//
// When the last step completes the test finishes successfully on its own — no
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
// converges as soon as it holds, and — when it never holds — reports which
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

    FCk_AutoTest_Step(FString InDisplayName = "", FName InFuncName = n"", bool InIsWait = false, int32 InFrameBudget = 0)
    {
        _DisplayName = InDisplayName;
        _FuncName = InFuncName;
        _IsWait = InIsWait;
        _FrameBudget = InFrameBudget;
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
    // compile-time default — leave it alone unless your test needs a tighter
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

    // ----- Internal state -----
    private FCk_Handle SelfEntity;
    private bool _Finished = false;
    private int32 _AssertionsRun = 0;
    private int32 _AssertionsFailed = 0;
    private FString _FirstFailureMessage;

    // Out-of-subtree owners registered via Track_ForCleanup — destroyed at finish
    // so heavyweight tests can't leak into the next test in the shared PIE world.
    private TArray<FCk_Handle> _CleanupOwners;
    private ECk_AutoTest_Status _PendingStatus = ECk_AutoTest_Status::Running;
    private FString _PendingMessage;

    // ----- Step sequencer -----
    private TArray<FCk_AutoTest_Step> _Steps;
    private int32 _CurrentStep = 0;
    private int32 _PollsInStep = 0;
    private bool _StepsRunning = false;
    private float _StepsElapsedSeconds = 0.0f;
    private FCk_Handle_Timer _StepTickTimer;

    // ----- Standalone WaitUntil (independent of the sequencer) -----
    private FName _WaitPredicateName;
    private FName _WaitContinuationName;
    private int32 _WaitPolls = 0;
    private int32 _WaitBudget = 0;
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

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    //------------------------------------------------------------------------
    // Step sequencer — declaration
    //------------------------------------------------------------------------

    // An action step. InFuncName must name a UFUNCTION on this class with the
    // FCk_Lambda_InHandle signature:
    //   UFUNCTION() private void Name(FCk_Handle InHandle, FInstancedStruct InPayload)
    // The action runs once and the sequence advances on the FOLLOWING tick, so
    // an action and the wait after it never share a tick — the wait's first
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
    // reference" (Script/CLAUDE.md 9.1). The copy is not a workaround that
    // loses the write: FCk_SharedBool holds a shared cell, so the copy and the
    // parameter address the same bool.
    protected void Add_Step_WaitUntil(const FString& InDisplayName, FName InPredicateName, int32 InFrameBudget = 0)
    {
        _Steps.Add(FCk_AutoTest_Step(InDisplayName, InPredicateName, true,
            InFrameBudget > 0 ? InFrameBudget : _DefaultWaitFrameBudget));
    }

    // A wait step that settles for a fixed number of frames. Prefer
    // Add_Step_WaitUntil — reach for this only when there is genuinely no
    // observable condition, e.g. asserting that something does NOT happen.
    protected void Add_Step_WaitFrames(const FString& InDisplayName, int32 InFrames)
    {
        _Steps.Add(FCk_AutoTest_Step(InDisplayName, n"", true, InFrames > 1 ? InFrames : 1));
    }

    // Starts the sequence. Call once, at the end of DoBeginPlay.
    protected void Run_Steps(FCk_Handle InHandle)
    {
        if (_StepsRunning) { return; }

        if (_Steps.IsEmpty())
        {
            FinishFailure("Run_Steps called with no steps declared — use Add_Step / Add_Step_WaitUntil first");
            return;
        }

        SelfEntity = InHandle;
        _StepsRunning = true;
        _CurrentStep = 0;
        _PollsInStep = 0;
        _StepsElapsedSeconds = 0.0f;
        _StepTickTimer = Do_MakePerFrameTimer(n"INTERNAL__AutoTest_StepTick");
    }

    // Where the test currently is, for diagnostics — the active sequencer step
    // or the active standalone wait. Empty when neither is running. Every
    // failure path routes its location through here rather than embedding it,
    // so a message is prefixed exactly once no matter who raises it.
    FString Get_CurrentContextLabel() const
    {
        if (_StepsRunning && _CurrentStep < _Steps.Num())
        {
            auto Name = _Steps[_CurrentStep]._DisplayName;
            auto Ordinal = _CurrentStep + 1;
            auto Total = _Steps.Num();
            return f"step {Ordinal}/{Total} '{Name}'";
        }

        if (_WaitRunning)
        {
            auto Pred = _WaitPredicateName;
            return f"WaitUntil('{Pred}')";
        }

        return "";
    }

    //------------------------------------------------------------------------
    // Step sequencer — execution
    //------------------------------------------------------------------------

    UFUNCTION()
    private void INTERNAL__AutoTest_StepTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_Finished || _StepsRunning == false) { return; }

        _StepsElapsedSeconds += float(InDeltaT.Get_Seconds());

        if (_CurrentStep >= _Steps.Num())
        {
            _StepsRunning = false;
            FinishSuccess();
            return;
        }

        // Beat the engine's TimeLimit so the failure names the pending step
        // instead of arriving as an anonymous TimesUp. 0.9 leaves room for the
        // result write and the C++ runner's next poll.
        if (_StepsElapsedSeconds > _TimeoutSeconds * 0.9f)
        {
            auto Elapsed = _StepsElapsedSeconds;
            FinishFailure(f"timed out after {Elapsed :.2}s — raise `default _TimeoutSeconds` if the test is merely slow");
            return;
        }

        auto Step = _Steps[_CurrentStep];

        if (Step._IsWait == false)
        {
            Do_InvokeStepAction(Step);
            Do_AdvanceStep();
            return;
        }

        // A wait with no predicate is a fixed-frame settle: the budget IS the wait.
        if (Step._FuncName == NAME_None)
        {
            _PollsInStep++;
            if (_PollsInStep >= Step._FrameBudget) { Do_AdvanceStep(); }
            return;
        }

        if (Do_EvaluatePredicate(Step._FuncName))
        {
            Do_AdvanceStep();
            return;
        }

        _PollsInStep++;
        if (_PollsInStep >= Step._FrameBudget)
        {
            auto Cond = Step._FuncName;
            auto Budget = Step._FrameBudget;
            auto Elapsed = _StepsElapsedSeconds;
            FinishFailure(f"condition '{Cond}' never became true within {Budget} polls ({Elapsed :.2}s)");
        }
    }

    private void Do_AdvanceStep()
    {
        _CurrentStep++;
        _PollsInStep = 0;
    }

    private void Do_InvokeStepAction(const FCk_AutoTest_Step& InStep)
    {
        auto Action = FCk_Lambda_InHandle(this, InStep._FuncName);
        if (Action.IsBound() == false)
        {
            auto Fn = InStep._FuncName;
            FinishFailure(f"no UFUNCTION named '{Fn}' on this test — an action step needs `UFUNCTION() private void {Fn}(FCk_Handle InHandle, FInstancedStruct InPayload)`");
            return;
        }
        Action.ExecuteIfBound(SelfEntity, FInstancedStruct());
    }

    // Shared by the sequencer and the standalone WaitUntil. Returns false and
    // fails the test when the name does not resolve — distinguishing an
    // unbound name from a forever-false condition is the difference between a
    // one-line fix and an afternoon.
    private bool Do_EvaluatePredicate(FName InPredicateName)
    {
        auto Predicate = FCk_Predicate_InHandle_OutResult(this, InPredicateName);
        if (Predicate.IsBound() == false)
        {
            FinishFailure(f"no UFUNCTION named '{InPredicateName}' on this test — a wait predicate needs `UFUNCTION() private void {InPredicateName}(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)`");
            return false;
        }

        auto Result = utils_shared_bool::Make(false);
        Predicate.ExecuteIfBound(SelfEntity, Result, FInstancedStruct());
        return Result.Get();
    }

    // A zero-duration ResetOnDone timer bound to OnUpdate is the per-frame hook
    // for an entity script. OnUpdate — not OnDone — is what fires once per
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
    // Standalone WaitUntil — for tests that drive their own callback chain
    // rather than declaring a step list. This is the drop-in replacement for a
    // chain of WaitOneFrame hops.
    //------------------------------------------------------------------------

    // Polls InPredicateName every frame until it returns true, then calls
    // InContinuationName once. On budget exhaustion the test fails naming the
    // predicate. The continuation takes the FCk_Delegate_Timer signature, the
    // same shape WaitOneFrame callbacks already use:
    //   UFUNCTION() private void Name(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    protected void WaitUntil(FName InPredicateName, FName InContinuationName, int32 InFrameBudget = 0)
    {
        if (_WaitRunning)
        {
            FinishFailure(f"WaitUntil('{InPredicateName}') called while already waiting on '{_WaitPredicateName}' — one standalone wait at a time");
            return;
        }

        _WaitPredicateName = InPredicateName;
        _WaitContinuationName = InContinuationName;
        _WaitPolls = 0;
        _WaitBudget = InFrameBudget > 0 ? InFrameBudget : _DefaultWaitFrameBudget;
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

    UFUNCTION()
    private void INTERNAL__AutoTest_WaitTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_Finished || _WaitRunning == false) { return; }

        _WaitElapsedSeconds += float(InDeltaT.Get_Seconds());

        // Same deadline the sequencer uses. Without it a generous frame budget
        // outlives the engine's TimeLimit and the run degrades right back to
        // the anonymous TimesUp this API exists to replace.
        if (_WaitElapsedSeconds > _TimeoutSeconds * 0.9f)
        {
            auto Elapsed = _WaitElapsedSeconds;
            FinishFailure(f"timed out after {Elapsed :.2}s — raise `default _TimeoutSeconds` if the test is merely slow");
            return;
        }

        if (Do_EvaluatePredicate(_WaitPredicateName))
        {
            // Resolve the continuation while _WaitRunning is still true, so an
            // unbound name is reported against this wait rather than against
            // nothing.
            auto Continuation = FCk_Delegate_Timer(this, _WaitContinuationName);
            if (Continuation.IsBound() == false)
            {
                auto Fn = _WaitContinuationName;
                FinishFailure(f"no UFUNCTION named '{Fn}' to continue to — needs `UFUNCTION() private void {Fn}(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)`");
                return;
            }

            // Stop before dispatching: the continuation commonly starts the
            // next wait, and a still-live timer would double-drive it.
            Do_StopWaitTick();
            Continuation.ExecuteIfBound(InTimer, InChrono, InDeltaT);
            return;
        }

        _WaitPolls++;
        if (_WaitPolls >= _WaitBudget)
        {
            auto Cond = _WaitPredicateName;
            auto Budget = _WaitBudget;
            FinishFailure(f"condition '{Cond}' never became true within {Budget} polls");
        }
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

    // Register an out-of-subtree entity ROOT to destroy when the test finishes: anything
    // you spawned UNDER an ActorRelay channel, anything owned by ck::TransientEntity(),
    // and the subordinates a driver spawns and exposes (e.g. Get_EmployeeManager()) —
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
    // acquire-only by design (acquisition is stateless pool selection — there is no
    // checkout to return), and for Generic groups the pool NEVER regrows. Destroying one
    // kills ActorRelay for the remainder of the PIE session — i.e. for every test after
    // yours. Register what you spawned UNDER the channel, never the channel.
    protected void Track_ForCleanup(FCk_Handle InOwner)
    {
        if (ck::Is_NOT_Valid(InOwner)) { return; }
        // Never the runner: its entity holds the FCk_AutoTest_Result fragment (and any
        // feature composed onto it — e.g. a Mark_AsGlobal DayCycle — which the harness
        // cascades anyway). Destroying it would nuke the result before it is polled.
        if (InOwner == SelfEntity) { return; }
        _CleanupOwners.AddUnique(InOwner);
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
    // Untracked tests (the overwhelming majority) write synchronously — behaviour is
    // identical to the classic path. Tracked tests queue the deferred destroys, then
    // write the result one frame later so the destroys are registered before the
    // poller next reads the result (the destroys never touch this runner, so its
    // result fragment survives to be written in the settle callback).
    private void Finalize(ECk_AutoTest_Status InStatus, const FString& InMessage)
    {
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
    // Assertions — increment counters, stash the first failure, but do NOT
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
            // here — UE's automation framework treats Warning-level log output
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
    // WaitOneFrame — legacy settle helper.
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
    // Result fragment write — single source of truth for the C++ poller.
    //------------------------------------------------------------------------

    private void WriteResult(ECk_AutoTest_Status InStatus, const FString& InMessage)
    {
        UCk_Utils_AutoTest_UE::Set_Result(
            SelfEntity, InStatus, InMessage, _AssertionsRun, _AssertionsFailed);
    }
}
