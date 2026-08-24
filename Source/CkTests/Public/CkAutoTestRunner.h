#pragma once

#include "CoreMinimal.h"

#include "FunctionalTest.h"

#include "CkCore/Settings/CkCore_Settings.h"
#include "CkEcs/Handle/CkHandle.h"

#include "CkAutoTestRunner.generated.h"

class UCk_EntityScript_UE;

// --------------------------------------------------------------------------------------------------------------------
//
// ACk_AutoTestRunner — generic Functional Test actor that drives an Angelscript
// test entity script and reports the result to the engine automation framework.
//
// Usage:
//   1. Subclass this in AngelScript per test:
//        class A..._Actor : ACk_AutoTestRunner
//        {
//            default _TestEntityScriptClass = UMyAutoTestBody;
//            default _TimeoutSeconds = 5.0f;
//        }
//   2. Drag the AS subclass from the Place Actors panel into a test map.
//   3. Run via Session Frontend → Automation → Project.Functional Tests.
//
// The actor:
//   - In PrepareTest: syncs engine TimeLimit to _TimeoutSeconds, spawns
//     the AS entity on the world's transient entity, binds the OnConstructed
//     promise.
//   - In Tick: polls the runner entity for an FCk_AutoTest_Result fragment,
//     calling FinishTest() once status is terminal (Passed/Failed).
//   - If the AS test never writes a terminal result, the engine TimeLimit
//     fires TimesUpResult=Failed automatically (no extra logic needed here).
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(Blueprintable)
class CKTESTS_API ACk_AutoTestRunner : public AFunctionalTest
{
    GENERATED_BODY()

public:
    ACk_AutoTestRunner();

private:
    // CK convention (private + AllowPrivateAccess + BlueprintReadOnly) —
    // this shape allows AS subclasses to set the value via `default`:
    //   default _TestEntityScriptClass = UMyTest;
    //   default _TimeoutSeconds = 3.0f;
    // and editor instances to set both via the Details panel.

    UPROPERTY(EditAnywhere, NoClear, BlueprintReadOnly,
        Category = "Ck|AutoTest",
        meta = (AllowPrivateAccess = "true"))
    TSubclassOf<UCk_EntityScript_UE> _TestEntityScriptClass;

    UPROPERTY(EditAnywhere, BlueprintReadOnly,
        Category = "Ck|AutoTest",
        meta = (AllowPrivateAccess = "true",
                ClampMin = "0.1",
                Tooltip = "Per-test timeout in seconds. Engine TimeLimit is set from this in PrepareTest."))
    float _TimeoutSeconds = 5.0f;

    // Suppresses the harness's built-in expected-log-error list (EOS RTC
    // TickTracker chatter, etc). Flip to true on a subclass that legitimately
    // wants those warnings to fail the test (e.g. a perf/hitch-detection
    // test that uses RTC scheduling as a stall signal).
    UPROPERTY(EditAnywhere, BlueprintReadOnly,
        Category = "Ck|AutoTest",
        meta = (AllowPrivateAccess = "true"))
    bool _DisableDefaultLogSuppressions = false;

    // Regex / substring patterns matching LogError/LogWarning lines this test
    // is expected to emit (e.g. a Pathfinding_Failure test deliberately
    // triggers a path projection error). Each entry is registered via
    // AddExpectedErrorPlain(Contains, Occurrences=-1) in PrepareTest so the
    // automation framework doesn't auto-fail the test on its own deliberate
    // output. Set in AS via:
    //   default _ExpectedLogErrors = { "FindPathSync.*projection FAILED" };
    // These layer ON TOP OF the harness's built-in default noise list (see
    // _DisableDefaultLogSuppressions to opt out of those defaults).
    UPROPERTY(EditAnywhere, BlueprintReadOnly,
        Category = "Ck|AutoTest",
        meta = (AllowPrivateAccess = "true"))
    TArray<FString> _ExpectedLogErrors;

public:
    // Escape hatch: if a subclass needs to compute the class dynamically
    // (rather than baking it in via `default`), override this BPNE.
    // The default implementation returns the UPROPERTY value above.
    UFUNCTION(BlueprintNativeEvent, Category = "Ck|AutoTest")
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const;
    virtual TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass_Implementation() const;

    // AS-overridable hook for the expected-log-errors list. AS can't brace-init a
    // TArray<FString> via `default`, so subclasses that need suppression patterns
    // override this BPNE and build the array imperatively. Default impl returns
    // the editor-settable _ExpectedLogErrors UPROPERTY (which IS settable from
    // the Details panel for actor instances placed in the test map).
    UFUNCTION(BlueprintNativeEvent, Category = "Ck|AutoTest")
    TArray<FString> Get_ExpectedLogErrors() const;
    virtual TArray<FString> Get_ExpectedLogErrors_Implementation() const;

public:
    virtual auto PrepareTest() -> void override;
    virtual auto Tick(float DeltaSeconds) -> void override;
    virtual auto FinishTest(EFunctionalTestResult TestResult, const FString& Message) -> void override;
    virtual auto BeginDestroy() -> void override;
    virtual auto EndPlay(const EEndPlayReason::Type EndPlayReason) -> void override;

private:
    UFUNCTION()
    void OnRunnerConstructed(struct FCk_Handle_EntityScript InEntityScriptHandle);

    // Destroys the spawned runner entity (and its entire child graph — every
    // entity the AS test created during Construct/BeginPlay). Idempotent.
    // Called from FinishTest and EndPlay so leaked agents from one test
    // cannot contaminate the dynamic-navmesh / world-state of the next.
    void Destroy_RunnerEntity();

    // Forces CkEnsure's display policy to LogOnly for the duration of a test
    // run. CkFoundation's CK_ENSURE_IF_NOT path normally pops a modal dialog
    // (ECk_EnsureDisplay_Policy::ModalDialog) which blocks automated runs.
    // Under LogOnly, ensures still log a full message + callstack — so the
    // automation framework still sees the error and fails the test — but no
    // dialog appears. Saved policy is restored on FinishTest / BeginDestroy.
    void Install_EnsurePolicyOverride();
    void Restore_EnsurePolicyOverride();

    // ----- Environment-drift detection -----
    //
    // Tests in a lane share one editor process and one map load, and this harness's teardown
    // reaches ECS state only (Destroy_RunnerEntity + the AS base's Track_ForCleanup list).
    // Anything PROCESS-global a test moves — console variables above all — survives into every
    // test that runs after it in that lane. The failure then lands on an innocent downstream
    // test, arbitrarily far away, which is why this class of bug is expensive: the signal points
    // at the victim, never the culprit.
    //
    // So: fingerprint the console variables that sit at a runtime-set priority before the test
    // body runs, diff at FinishTest, and name the test that moved them. Attribution is the whole
    // point — a test that dirties the world gets told so, by name, in its own log window.
    //
    // Deliberately ADVISORY by default (a Display line, not a failure). The noise floor of engine-
    // internal CVar churn during a test has never been measured on this corpus, and a detector
    // that mass-fails a green suite on its first run would simply be turned off. Set
    // `ck.AutoTest.StrictEnvironmentDrift 1` to promote drift to a test failure once a run
    // shows the warnings are clean. Tracked as a follow-up, not a permanent state.
    //
    // Scope, stated plainly: only ECVF_SetByCode and above (i.e. ExecuteConsoleCommand and
    // direct IConsoleVariable::Set) are watched. That covers every leak this was built for. It
    // does NOT cover other process-global state — subsystem flags, settings registries, on-disk
    // config — which still relies on the author restoring it.
    void Capture_EnvironmentFingerprint();
    auto Get_EnvironmentDrift() const -> TArray<FString>;

    // Registers expected-log-error patterns with the active automation test
    // so chatty third-party warnings (EOS RTC TickTracker, etc.) don't auto-
    // fail tests that don't care about them. Called once from PrepareTest.
    void Install_ExpectedLogErrors();

private:
    FCk_Handle _RunnerEntity;
    bool _ResultReported = false;

    // Per-instance idempotency guard so FinishTest + BeginDestroy don't
    // double-decrement the process-wide override refcount. The actual
    // saved policy and refcount live in file-scope statics in the .cpp
    // (see ck::auto_test::ensure_override).
    bool _EnsurePolicyOverridden = false;

    // name -> value, for console variables at a runtime-set priority when the test began.
    TMap<FString, FString> _EnvFingerprint;

    // FinishTest can be re-entered (engine timeout racing the tick poller); the diff runs once.
    bool _EnvDriftChecked = false;
};
