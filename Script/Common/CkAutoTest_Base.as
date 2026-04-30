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
    // Result fragment write — single source of truth for the C++ poller.
    //------------------------------------------------------------------------

    private void WriteResult(ECk_AutoTest_Status InStatus, const FString& InMessage)
    {
        UCk_Utils_AutoTest_UE::Set_Result(
            SelfEntity, InStatus, InMessage, _AssertionsRun, _AssertionsFailed);
    }
}
