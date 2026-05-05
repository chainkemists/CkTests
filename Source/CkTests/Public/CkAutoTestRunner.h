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

public:
    // Escape hatch: if a subclass needs to compute the class dynamically
    // (rather than baking it in via `default`), override this BPNE.
    // The default implementation returns the UPROPERTY value above.
    UFUNCTION(BlueprintNativeEvent, Category = "Ck|AutoTest")
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const;
    virtual TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass_Implementation() const;

public:
    virtual auto PrepareTest() -> void override;
    virtual auto Tick(float DeltaSeconds) -> void override;
    virtual auto FinishTest(EFunctionalTestResult TestResult, const FString& Message) -> void override;
    virtual auto BeginDestroy() -> void override;

private:
    UFUNCTION()
    void OnRunnerConstructed(struct FCk_Handle_EntityScript InEntityScriptHandle);

    // Forces CkEnsure's display policy to LogOnly for the duration of a test
    // run. CkFoundation's CK_ENSURE_IF_NOT path normally pops a modal dialog
    // (ECk_EnsureDisplay_Policy::ModalDialog) which blocks automated runs.
    // Under LogOnly, ensures still log a full message + callstack — so the
    // automation framework still sees the error and fails the test — but no
    // dialog appears. Saved policy is restored on FinishTest / BeginDestroy.
    void Install_EnsurePolicyOverride();
    void Restore_EnsurePolicyOverride();

private:
    FCk_Handle _RunnerEntity;
    bool _ResultReported = false;

    // Per-instance idempotency guard so FinishTest + BeginDestroy don't
    // double-decrement the process-wide override refcount. The actual
    // saved policy and refcount live in file-scope statics in the .cpp
    // (see ck::auto_test::ensure_override).
    bool _EnsurePolicyOverridden = false;
};
