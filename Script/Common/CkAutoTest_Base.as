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
// The base class provides:
//   - Assertion helpers that increment counters and capture first failure
//   - FinishSuccess / FinishFailure that write the result fragment
//   - IsFinished() guard so subclasses can early-out
//
// Timeout is handled by the engine via ACk_AutoTestRunner's TimeLimit,
// which is set from the actor's _TimeoutSeconds property. AS authors
// override the timeout via:
//   class A..._Actor : ACk_AutoTestRunner { default _TimeoutSeconds = 3.0f; }
//============================================================================

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
    // single-PIE flow for every existing CkAttribute / CkAStar / CkAggro / etc. test.
    // Subclasses targeting multi-PIE override via `default _NetMode = ECk_AutoTest_NetMode::...`
    // (UCk_AutoTest_NetBase already does this for Replicated). See ECk_AutoTest_NetMode for
    // the per-value contract. Phase 3b is the declaration surface; Phase 3c (generator)
    // will wire automatic stub emission off this default.
    UPROPERTY()
    ECk_AutoTest_NetMode _NetMode = ECk_AutoTest_NetMode::Standalone;

    // ----- Internal state -----
    private FCk_Handle SelfEntity;
    private bool _Finished = false;
    private int32 _AssertionsRun = 0;
    private int32 _AssertionsFailed = 0;
    private FString _FirstFailureMessage;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        SelfEntity = InHandle;

        // Mark result as Running immediately so the C++ runner can
        // distinguish "test entity exists and is going" from "test entity
        // not yet constructed".
        UCk_Utils_AutoTest_UE::Set_Result(
            SelfEntity, ECk_AutoTest_Status::Running, "", 0, 0);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    //------------------------------------------------------------------------
    // Finish helpers
    //------------------------------------------------------------------------

    bool IsFinished() const
    {
        return _Finished;
    }

    void FinishSuccess()
    {
        if (_Finished) { return; }
        _Finished = true;
        WriteResult(_AssertionsFailed > 0 ? ECk_AutoTest_Status::Failed : ECk_AutoTest_Status::Passed,
                    _FirstFailureMessage);
    }

    void FinishFailure(const FString& InMessage)
    {
        if (_Finished) { return; }
        _Finished = true;
        if (_FirstFailureMessage == "") { _FirstFailureMessage = InMessage; }
        _AssertionsFailed++;
        WriteResult(ECk_AutoTest_Status::Failed, _FirstFailureMessage);
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
            if (_FirstFailureMessage == "") { _FirstFailureMessage = InMessage; }
            // Failures are surfaced via the result fragment; the C++ runner
            // turns them into FinishTest(Failed, ...) messages. Avoid ck::Trace
            // here — UE's automation framework treats Warning-level log output
            // during a functional test as a test failure.
        }
    }

    void Assert_Equals_Int(int32 InActual, int32 InExpected, const FString& InMessage)
    {
        Assert_True(InActual == InExpected,
            f"{InMessage} (expected {InExpected}, got {InActual})");
    }

    void Assert_Equals_String(const FString& InActual, const FString& InExpected, const FString& InMessage)
    {
        Assert_True(InActual == InExpected,
            f"{InMessage} (expected '{InExpected}', got '{InActual}')");
    }

    //------------------------------------------------------------------------
    // Deferred-framework helpers — wait for processor-scheduler side-effects
    // to settle before reading state in a result callback.
    //
    // Why: CkFoundation request handlers are deferred. A handler may complete
    // and broadcast its result signal while downstream side-effects (attribute
    // modifiers, fragment updates, etc.) are still queued — e.g.
    // Request_OverrideStackCount adds a NotRevocable modifier whose value is
    // applied by the next IntegerAttribute compute-processor tick, AFTER the
    // AddByDefinition result callback already fired. Reading the post-effect
    // state from inside the result callback observes the pre-effect value.
    //
    // WaitOneFrame schedules InCallbackName to fire on the next processor
    // pass via a 0-duration CkTimer. By the time the callback runs, every
    // processor in the scheduler has had a chance to tick at least once, so
    // all in-flight modifier and request side-effects from the prior result
    // signal have been applied.
    //
    // The callback must have the FCk_Delegate_Timer signature:
    //   UFUNCTION()
    //   private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    //
    // Use whenever a callback needs to observe state mutated through a
    // deferred pathway: attribute Request_Override / Request_Adjust, item-
    // trait stack-count writes, two-stage transfers, etc. If a single frame
    // isn't enough (multi-stage deferred chains), chain WaitOneFrame calls
    // by calling it again from the OnSettled callback.
    //------------------------------------------------------------------------

    void WaitOneFrame(FName InCallbackName)
    {
        // 0.05s rather than 0.0: a zero-duration timer can fire OnDone within
        // the same processor pass that added it, racing the very side-effect
        // processors we're trying to wait for. 0.05s = one frame at 20fps =
        // guaranteed to fall on a subsequent frame at any realistic tick rate,
        // by which point every processor has had a chance to tick.
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
