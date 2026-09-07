#pragma once

#include "CoreMinimal.h"

#include "FunctionalTest.h"

#include "CkCore/Settings/CkCore_Settings.h"
#include "CkEcs/Handle/CkHandle.h"

#include "CkGroundNav/Volume/CkGroundNavVolume_Fragment_Data.h"

#include "CkAutoTestRunner.generated.h"

class AStaticMeshActor;
class UCk_EntityScript_UE;
class UWorld;

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
//   - In PrepareTest: syncs engine TimeLimit to _TimeoutSeconds, stages the
//     GroundNav harness origin field when this world runs on GroundNav and the
//     test did not opt out (see Get_ShouldStageOriginField), then spawns the AS
//     entity on the world's transient entity and binds the OnConstructed
//     promise. Under staging the spawn is DEFERRED to Tick.
//   - In Tick: drives the staging state machine to completion (deferred spawn),
//     then polls the runner entity for an FCk_AutoTest_Result fragment,
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
    // Gates the engine's StartTest - and so the TimeLimit clock - on the AS test entity existing.
    virtual auto IsReady_Implementation() -> bool override;
    virtual auto Tick(float DeltaSeconds) -> void override;
    virtual auto FinishTest(EFunctionalTestResult TestResult, const FString& Message) -> void override;
    virtual auto BeginDestroy() -> void override;
    virtual auto EndPlay(const EEndPlayReason::Type EndPlayReason) -> void override;

private:
    UFUNCTION()
    void OnRunnerConstructed(struct FCk_Handle_EntityScript InEntityScriptHandle);

    // Destroys the spawned runner entity (and its entire child graph — every
    // entity the AS test created during Construct/BeginPlay), and releases the
    // harness origin field if one was staged. Idempotent. Called from
    // FinishTest and EndPlay so leaked agents from one test cannot contaminate
    // the dynamic-navmesh / world-state of the next.
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

    // Out-of-subtree entity leak detection. Destroy_RunnerEntity cascades only the runner's own
    // lifetime subtree, so anything a test parents to the world's TransientEntity or to an ActorRelay
    // channel survives into every later test in the shared PIE world unless the test declares it via
    // UCk_AutoTest_Base::Track_ForCleanup. These name the test that leaked instead of the one that
    // then breaks. See the .cpp for what is deliberately NOT flagged.
    void Capture_EntityBaseline();
    auto Get_EntityLeaks() const -> TArray<FString>;

    // ----- GroundNav harness origin field -----
    //
    // The shared autotest level ships a Recast navmesh and NOTHING that publishes a GroundNav
    // field, so a world on ECk_NavSurface_Provider::GroundNav has no ground for a test to answer
    // over: every such test fails for the harness's reason rather than its own. The runner
    // therefore bakes one volume over the level's origin floor BEFORE the test entity exists, and
    // spawns the entity only once the field is built and the surface has settled.
    //
    // Staged here rather than from the AS base because the AS base could only ever prepend steps to
    // Run_Steps, which reaches the 191 of 1032 autotests that declare a step list. The ground is a
    // property of the WORLD the test runs in, not of the shape the test was written in.
    //
    // A test opts out with `default _AutoStageOriginField = false;` on its entity script; that
    // writes the subclass CDO, which is what Get_ShouldStageOriginField reads.
    auto Get_ShouldStageOriginField(const UClass* InTestEntityScriptClass, UWorld* InWorld) const -> bool;

    // Bakes the origin field. Returns false having already called FinishTest(Failed) with the
    // reason, so the caller only has to stop.
    auto Request_StageOriginField(UWorld* InWorld, FCk_Handle& InTransientEntity) -> bool;

    // Destroys the staged volume entity and pulls the floor back out of the Jolt static world IF
    // this runner is the one that put it there. Idempotent; safe on a runner that never staged.
    auto Release_OriginField() -> void;

    // Spawns the AS test entity on the world transient entity and binds the construction promise.
    // Both the immediate path (PrepareTest, no staging) and the deferred path (Tick, once the
    // field is up) route through here so the two cannot drift.
    auto Spawn_TestEntity() -> void;

private:
    FCk_Handle _RunnerEntity;
    bool _ResultReported = false;

    // ----- GroundNav harness origin field state -----
    // All inert for a test on Recast and for every opt-out.
    FCk_Handle _OriginFieldEntity;
    FCk_Handle_GroundNavVolume _OriginFieldVolume;

    // Weak on purpose: the floor is a level actor held across frames by a harness that must never
    // be the reason it stays alive.
    TWeakObjectPtr<AStaticMeshActor> _OriginFieldFloor;

    // True only when THIS runner put the floor into the Jolt static world. A floor the host's own
    // level sweep (or an earlier test) baked is left exactly as it was found.
    bool _OriginFieldFloorBakedByThisRunner = false;

    // The spawn is deferred while this is set. Cleared when the deferred spawn happens, when
    // staging times out, and in FinishTest so a TimesUp mid-stage cannot spawn a test entity for a
    // test that has already reported.
    bool _StagingOriginField = false;
    bool _StagingFieldBuilt = false;
    int32 _StagingBuildFrames = 0;
    int32 _StagingSettleFrames = 0;
    float _StagingSeconds = 0.0f;

    // Per-instance idempotency guard so FinishTest + BeginDestroy don't
    // double-decrement the process-wide override refcount. The actual
    // saved policy and refcount live in file-scope statics in the .cpp
    // (see ck::auto_test::ensure_override).
    bool _EnsurePolicyOverridden = false;

    // name -> value, for console variables at a runtime-set priority when the test began.
    TMap<FString, FString> _EnvFingerprint;

    // FinishTest can be re-entered (engine timeout racing the tick poller); the diff runs once.
    bool _EnvDriftChecked = false;

    // Every entity that had a lifetime owner when this test began. Anything owned that is NOT in
    // here at finish was created by this test.
    TSet<FCk_Entity> _EntityBaseline;

    // Distinguishes "captured an empty world" from "never captured" - the second must report
    // nothing rather than attributing the entire world to this test.
    bool _EntityBaselineCaptured = false;

    // Same re-entrancy guard as _EnvDriftChecked, for the same reason.
    bool _EntityLeaksChecked = false;
};
