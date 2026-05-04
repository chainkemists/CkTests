#include "CkAutoTestRunner.h"

#include "CkAutoTest_Bridge.h"
#include "CkAutoTest_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Fragment_Data.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkCore/Settings/CkCore_Settings.h"

#include <Misc/AutomationTest.h>
#include <StructUtils/InstancedStruct.h>

DEFINE_LOG_CATEGORY_STATIC(LogCkAutoTest_Ensure, Log, All);

// --------------------------------------------------------------------------------------------------------------------
//
// Process-wide ensure-policy override state.
//
// Goal: while ANY ACk_AutoTestRunner is active, force ECk_EnsureDisplay_Policy
// to LogOnly so dialogs don't block automated runs. Restore the user's
// original policy as soon as the LAST runner finishes — robust against:
//   - Overlapping actor lifecycles (Test A's BeginDestroy delayed past Test
//     B's PrepareTest): without ref-counting, B would capture A's leftover
//     LogOnly as "previous" and we'd never restore the real value.
//   - Engine shutdown with active runners: OnEnginePreExit forces a final
//     restore even if BeginDestroy never fires.
//   - Crash mid-test: nothing persists to disk anyway (Set_EnsureDisplay-
//     Policy is in-memory CDO only), so a process death always recovers
//     the user's .ini value on next launch.
//
// The per-instance _EnsurePolicyOverridden flag still exists — it makes
// each instance's Install/Restore idempotent (FinishTest AND BeginDestroy
// both call Restore on the same actor).
//
// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::ensure_override
{
    static int32 GActiveCount = 0;
    static ECk_EnsureDisplay_Policy GOriginalPolicy = ECk_EnsureDisplay_Policy::ModalDialog;
    static FDelegateHandle GPreExitHandle;

    static auto Force_Restore_OnEnginePreExit() -> void
    {
        if (GActiveCount > 0)
        {
            UE_LOG(LogCkAutoTest_Ensure, Warning,
                TEXT("Engine pre-exit with [%d] AutoTest runner(s) still active — "
                     "forcing ensure display policy restore."),
                GActiveCount);
            UCk_Utils_Core_UserSettings_UE::Set_EnsureDisplayPolicy(GOriginalPolicy);
            GActiveCount = 0;
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTestRunner::ACk_AutoTestRunner()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
    // TimeLimit is set in PrepareTest based on the AS subclass's
    // _TimeoutSeconds (so AS authors only configure one knob).
    // Default here is just an initial value used until PrepareTest runs.
    TimeLimit = 0.0f;
    TimesUpResult = EFunctionalTestResult::Failed;
    TimesUpMessage = NSLOCTEXT("CkTests", "AutoTestRunner_TimesUp",
        "AutoTestRunner: engine TimeLimit elapsed without an AS-side result. "
        "Did the AS test crash before its timer started?");
}

// --------------------------------------------------------------------------------------------------------------------

TSubclassOf<UCk_EntityScript_UE>
    ACk_AutoTestRunner::
    Get_TestEntityScriptClass_Implementation() const
{
    return _TestEntityScriptClass;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    PrepareTest()
    -> void
{
    Super::PrepareTest();

    _RunnerEntity = FCk_Handle{};
    _ResultReported = false;

    // Scope: override CkEnsure's display policy to LogOnly for the duration
    // of this test run, restored in FinishTest (and BeginDestroy as a safety
    // net). Outside test runs, ensures behave normally — devs running the
    // editor still see the modal dialog if their settings ask for it.
    Install_EnsurePolicyOverride();
    Install_ExpectedLogErrors();

    // Sync engine TimeLimit to the AS-author-configured _TimeoutSeconds.
    TimeLimit = FMath::Max(_TimeoutSeconds, 0.1f);

    const auto ResolvedClass = Get_TestEntityScriptClass();
    if (NOT IsValid(ResolvedClass))
    {
        FinishTest(EFunctionalTestResult::Failed,
            TEXT("AutoTestRunner: Get_TestEntityScriptClass returned null. "
                 "Set _TestEntityScriptClass via `default` in your AS actor "
                 "subclass, the Details panel, or override Get_TestEntityScriptClass."));
        return;
    }

    auto* World = GetWorld();
    if (NOT IsValid(World))
    {
        FinishTest(EFunctionalTestResult::Failed,
            TEXT("AutoTestRunner: GetWorld() returned null."));
        return;
    }

    auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
    if (ck::Is_NOT_Valid(TransientEntity))
    {
        FinishTest(EFunctionalTestResult::Failed,
            TEXT("AutoTestRunner: Could not resolve world transient entity."));
        return;
    }

    auto Pending = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
        TransientEntity, ResolvedClass, FInstancedStruct{});

    auto OnConstructedDelegate = FCk_Delegate_EntityScript_Constructed{};
    OnConstructedDelegate.BindDynamic(this, &ACk_AutoTestRunner::OnRunnerConstructed);
    UCk_Utils_PendingEntityScript_UE::Promise_OnConstructed(Pending, OnConstructedDelegate);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    OnRunnerConstructed(
        FCk_Handle_EntityScript InEntityScriptHandle)
    -> void
{
    _RunnerEntity = InEntityScriptHandle;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Tick(
        float DeltaSeconds)
    -> void
{
    Super::Tick(DeltaSeconds);

    if (_ResultReported)
    { return; }

    if (ck::Is_NOT_Valid(_RunnerEntity))
    { return; }

    if (NOT UCk_Utils_AutoTest_UE::Has_Result(_RunnerEntity))
    { return; }

    const auto TestResult = UCk_Utils_AutoTest_UE::Get_Result(_RunnerEntity);

    switch (TestResult.Status)
    {
        case ECk_AutoTest_Status::Pending:
        case ECk_AutoTest_Status::Running:
            return;

        case ECk_AutoTest_Status::Passed:
        {
            _ResultReported = true;
            const auto Msg = FString::Printf(TEXT("Passed (%d assertions)"), TestResult.AssertionsRun);
            FinishTest(EFunctionalTestResult::Succeeded, Msg);
            return;
        }

        case ECk_AutoTest_Status::Failed:
        {
            _ResultReported = true;
            const auto Msg = FString::Printf(
                TEXT("Failed: %s (%d/%d assertions failed)"),
                *TestResult.FailureMessage, TestResult.AssertionsFailed, TestResult.AssertionsRun);
            FinishTest(EFunctionalTestResult::Failed, Msg);
            return;
        }

        case ECk_AutoTest_Status::TimedOut:
        {
            // Currently unreachable: AS-side never writes TimedOut. Engine
            // TimeLimit handles timeouts via TimesUpResult/TimesUpMessage
            // directly. Kept for forward-compatibility if a future code
            // path wants to report a richer timeout via the result fragment.
            _ResultReported = true;
            const auto Msg = FString::Printf(
                TEXT("Timed out: %s (%d/%d assertions failed)"),
                *TestResult.FailureMessage, TestResult.AssertionsFailed, TestResult.AssertionsRun);
            FinishTest(EFunctionalTestResult::Failed, Msg);
            return;
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    FinishTest(
        EFunctionalTestResult TestResult,
        const FString& Message)
    -> void
{
    // Always restore the ensure policy before delegating to the base
    // implementation — covers both the engine-driven TimesUp path and
    // our own FinishTest calls from PrepareTest/Tick.
    Restore_EnsurePolicyOverride();

    Super::FinishTest(TestResult, Message);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    BeginDestroy()
    -> void
{
    // Safety net: if the actor is torn down without FinishTest ever firing
    // (e.g. world teardown mid-run), make sure we don't leave the policy
    // override in place — it's a process-wide setting via the CDO.
    Restore_EnsurePolicyOverride();

    Super::BeginDestroy();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Install_EnsurePolicyOverride()
    -> void
{
    using namespace ck::auto_test::ensure_override;

    if (_EnsurePolicyOverridden)
    { return; }

    if (GActiveCount == 0)
    {
        // First runner in this batch: capture the user's *real* policy now,
        // before we overwrite it. Subsequent runners in the same batch will
        // not re-capture (otherwise they'd record the temporary LogOnly).
        GOriginalPolicy = UCk_Utils_Core_UserSettings_UE::Get_EnsureDisplayPolicy();

        if (GOriginalPolicy == ECk_EnsureDisplay_Policy::ModalDialog)
        {
            UE_LOG(LogCkAutoTest_Ensure, Display,
                TEXT("Overriding ensure display policy: ModalDialog -> LogOnly for AutoTest run"));
            UCk_Utils_Core_UserSettings_UE::Set_EnsureDisplayPolicy(
                ECk_EnsureDisplay_Policy::LogOnly);
        }

        // Belt-and-suspenders: if engine shuts down with an override still
        // active (e.g. our BeginDestroy never fires), force a restore.
        if (NOT GPreExitHandle.IsValid())
        {
            GPreExitHandle = FCoreDelegates::OnEnginePreExit.AddStatic(
                &Force_Restore_OnEnginePreExit);
        }
    }

    ++GActiveCount;
    _EnsurePolicyOverridden = true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Restore_EnsurePolicyOverride()
    -> void
{
    using namespace ck::auto_test::ensure_override;

    if (NOT _EnsurePolicyOverridden)
    { return; }

    _EnsurePolicyOverridden = false;
    --GActiveCount;

    if (GActiveCount <= 0)
    {
        GActiveCount = 0;

        const auto CurrentPolicy = UCk_Utils_Core_UserSettings_UE::Get_EnsureDisplayPolicy();
        if (CurrentPolicy != GOriginalPolicy)
        {
            UE_LOG(LogCkAutoTest_Ensure, Display,
                TEXT("Restoring ensure display policy after last AutoTest runner finished"));
            UCk_Utils_Core_UserSettings_UE::Set_EnsureDisplayPolicy(GOriginalPolicy);
        }

        if (GPreExitHandle.IsValid())
        {
            FCoreDelegates::OnEnginePreExit.Remove(GPreExitHandle);
            GPreExitHandle.Reset();
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::expected_errors
{
    // Default noise list. Substrings — case-insensitive, matched against any
    // captured Warning/Error during the test window.
    //
    // EOS RTC TickTracker: the EOS SDK emits a Warning whenever its internal
    // tick loop slips past 40ms. In PIE/headless that fires constantly on
    // GC, asset loads, breakpoints, etc. — irrelevant to gameplay logic
    // tests, and registered here so the automation harness ignores it.
    static const TArray<FString> GDefaultPlainPatterns =
    {
        TEXT("TickTracker Ticks have been delayed"),
    };
}

auto
    ACk_AutoTestRunner::
    Install_ExpectedLogErrors()
    -> void
{
    auto* CurrentTest = FAutomationTestFramework::Get().GetCurrentTest();
    if (CurrentTest == nullptr)
    { return; }

    // Negative Occurrences = suppress all matches regardless of count, and
    // don't flag as "missing" if zero matches occur. See FAutomationExpected-
    // Message: "If negative, it will suppress all matching messages."
    constexpr int32 SuppressAll = -1;

    if (NOT _DisableDefaultLogSuppressions)
    {
        for (const auto& Pattern : ck::auto_test::expected_errors::GDefaultPlainPatterns)
        {
            CurrentTest->AddExpectedErrorPlain(Pattern,
                EAutomationExpectedErrorFlags::Contains, SuppressAll);
        }
    }

    for (const auto& Pattern : _ExpectedLogErrors)
    {
        if (Pattern.IsEmpty())
        { continue; }
        CurrentTest->AddExpectedErrorPlain(Pattern,
            EAutomationExpectedErrorFlags::Contains, SuppressAll);
    }
}
