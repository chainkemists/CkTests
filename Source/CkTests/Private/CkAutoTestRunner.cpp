#include "CkAutoTestRunner.h"

#include "CkAutoTest_Bridge.h"
#include "CkAutoTest_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Fragment_Data.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkCore/Settings/CkCore_Settings.h"

#include <HAL/IConsoleManager.h>
#include <Misc/AutomationTest.h>
#include <StructUtils/InstancedStruct.h>

DEFINE_LOG_CATEGORY_STATIC(LogCkAutoTest_Ensure, Log, All);
DEFINE_LOG_CATEGORY_STATIC(LogCkAutoTest_EnvDrift, Display, All);
DEFINE_LOG_CATEGORY_STATIC(LogCkAutoTest_EntityLeaks, Display, All);

// --------------------------------------------------------------------------------------------------------------------
//
// Process-wide ensure-policy override state.
//
// Goal: while ANY ACk_AutoTestRunner is active, force ECk_EnsureDisplay_Policy
// to LogOnly so dialogs don't block automated runs, and ECk_EnsureDetails_Policy
// to MessageOnly so the first ensure doesn't pay a fully-symbolicated
// StackWalkAndDump (PDB load under a global lock — I/O-bound enough to stall a
// headless run). Restore the user's original policies as soon as the LAST
// runner finishes — robust against:
//   - Overlapping actor lifecycles (Test A's BeginDestroy delayed past Test
//     B's PrepareTest): without ref-counting, B would capture A's leftover
//     LogOnly as "previous" and we'd never restore the real value.
//   - Engine shutdown with active runners: OnEnginePreExit forces a final
//     restore even if BeginDestroy never fires.
//   - Crash mid-test: nothing persists to disk anyway (Set_EnsureDisplay-
//     Policy is in-memory CDO only), so a process death always recovers
//     the user's .ini value on next launch.
//
// IMPORTANT — restore happens in EndPlay, NOT FinishTest. The per-test
// teardown path is:
//
//   FinishTest -> Destroy_RunnerEntity (Request_DestroyEntity, deferred)
//             -> next-tick ECS cleanup processors run for the just-destroyed
//                runner entity AND every child entity the AS test spawned
//             -> any of those processors may fire CK_ENSURE_IF_NOT
//
// If we restored the policy at FinishTest, that cleanup tick would see the
// real (likely ModalDialog) policy, pop a modal on the very first ensure,
// and hang the headless test process indefinitely. Holding the override
// until EndPlay means every cleanup tick within the actor's lifetime
// inherits LogOnly. Multiple runners interleave through GActiveCount, so a
// long-running cleanup chain followed by the next test's PrepareTest keeps
// the override continuously installed.
//
// The per-instance _EnsurePolicyOverridden flag still exists — it makes
// each instance's Install/Restore idempotent (EndPlay AND BeginDestroy
// both call Restore on the same actor).
//
// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::env_drift
{
    static TAutoConsoleVariable<bool> CVar_Strict(
        TEXT("ck.AutoTest.StrictEnvironmentDrift"),
        false,
        TEXT("When true, a test that leaves a console variable moved FAILS instead of merely warning. ")
        TEXT("Off by default until a full-suite run confirms the warning stream is free of engine-internal churn."),
        ECVF_Default);

    // Only variables someone actually moved at runtime. A CVar still sitting at its
    // constructor/ini/scalability priority was never touched by a test, so including it would
    // cost thousands of GetString() calls per test to observe nothing.
    static auto Capture_RuntimeSetCVars() -> TMap<FString, FString>
    {
        TMap<FString, FString> Out;

        IConsoleManager::Get().ForEachConsoleObjectThatStartsWith(
            FConsoleObjectVisitor::CreateLambda(
                [&Out](const TCHAR* InName, IConsoleObject* InObject) -> void
                {
                    if (InObject == nullptr)
                    { return; }

                    auto* CVar = InObject->AsVariable();

                    if (CVar == nullptr)
                    { return; }

                    const auto SetBy = static_cast<uint32>(CVar->GetFlags()) & static_cast<uint32>(ECVF_SetByMask);

                    if (SetBy < static_cast<uint32>(ECVF_SetByCode))
                    { return; }

                    Out.Add(FString{InName}, CVar->GetString());
                }),
            TEXT(""));

        return Out;
    }
}

namespace ck::auto_test::entity_leaks
{
    // One step up the ownership chain, or an invalid handle at the root.
    //
    // Deliberately NOT UCk_Utils_EntityLifetime_UE::Get_LifetimeOwner: that opens with
    // CK_ENSURE_IF_NOT(InHandle.Has<FFragment_LifetimeOwner>()), which is right for its normal
    // callers but fires on every rootless entity - and every walk to a root ends on one. An
    // Error-level ensure during a functional test is escalated into a FAILURE of whatever test is
    // running (spec GOTCHA 13), so a detector built on it fails 78 innocent tests instead of naming
    // the culprit. Ask the question the ensure guards rather than walking into it.
    static auto Get_OwnerOrInvalid(const FCk_Handle& InHandle) -> FCk_Handle
    {
        if (NOT InHandle.Has<ck::FFragment_LifetimeOwner>())
        { return {}; }

        return InHandle.Get<ck::FFragment_LifetimeOwner, ck::IsValid_Policy_IncludePendingKill>().Get_Entity();
    }

    static TAutoConsoleVariable<bool> CVar_Strict(
        TEXT("ck.AutoTest.StrictEntityLeaks"),
        false,
        TEXT("When true, a test that leaves an entity alive outside its own lifetime subtree FAILS ")
        TEXT("instead of merely warning. Off by default until a full-suite run confirms the warning ")
        TEXT("stream is free of legitimate world-owned churn."),
        ECVF_Default);

    // Every entity that currently HAS a lifetime owner - exactly the population a leak can appear in,
    // since every creation API takes an owner and an entity without one is a root the world owns.
    static auto Capture_OwnedEntities(const FCk_Registry& InRegistry) -> TSet<FCk_Entity>
    {
        TSet<FCk_Entity> Out;

        InRegistry.View<ck::FFragment_LifetimeOwner>().ForEach(
            [&Out](FCk_Entity InEntity, const ck::FFragment_LifetimeOwner&) -> void
            {
                Out.Add(InEntity);
            });

        return Out;
    }
}

namespace ck::auto_test::ensure_override
{
    static int32 GActiveCount = 0;
    static ECk_EnsureDisplay_Policy GOriginalPolicy = ECk_EnsureDisplay_Policy::ModalDialog;
    static ECk_EnsureDetails_Policy GOriginalDetailsPolicy = ECk_EnsureDetails_Policy::MessageAndStackTrace;
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
            UCk_Utils_Core_UserSettings_UE::Set_EnsureDetailsPolicy(GOriginalDetailsPolicy);
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

TArray<FString>
    ACk_AutoTestRunner::
    Get_ExpectedLogErrors_Implementation() const
{
    return _ExpectedLogErrors;
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

    _EnvDriftChecked = false;
    Capture_EnvironmentFingerprint();

    _EntityLeaksChecked = false;
    Capture_EntityBaseline();

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
        TransientEntity, ResolvedClass, FInstancedStruct{}, {});

    auto OnConstructedDelegate = FCk_Delegate_EntityScript_Constructed{};
    OnConstructedDelegate.BindDynamic(this, &ACk_AutoTestRunner::OnRunnerConstructed);
    UCk_Utils_PendingEntityScript_UE::Promise_OnConstructed(Pending, OnConstructedDelegate);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    IsReady_Implementation()
    -> bool
{
    // StartTest zeroes the engine's TotalTime and fires on the first tick where this returns true.
    // The base returns true unconditionally, which is wrong here twice over:
    //
    //   1. PrepareTest only REQUESTS the AS test entity (Request_SpawnEntity is deferred, the handle
    //      arrives via OnRunnerConstructed), so starting the clock earlier charges the spawn latency
    //      to the test's declared _TimeoutSeconds.
    //   2. UCk_AutoTest_Base anchors its own deadline at 0.9 * _TimeoutSeconds from DoConstruct so it
    //      fires first (see Get_DeadlineExceeded there). A 10% margin is only a margin if both clocks
    //      start on the same event.
    //
    // A spawn that never completes is covered by PreparationTimeLimit instead, which reports as a
    // preparation timeout - a better diagnosis than the test timeout it would otherwise arrive as.
    return ck::IsValid(_RunnerEntity);
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
    // Note: do NOT Restore_EnsurePolicyOverride here. Destroy_RunnerEntity
    // queues a deferred destroy; ECS cleanup processors for the runner
    // entity and its child entities run on subsequent ticks, and any of
    // them may fire CK_ENSURE_IF_NOT. We need the LogOnly policy to remain
    // in force across that cleanup window. EndPlay owns the restore.
    auto EffectiveResult  = TestResult;
    auto EffectiveMessage = Message;

    if (NOT _EnvDriftChecked)
    {
        _EnvDriftChecked = true;

        const auto Drift = Get_EnvironmentDrift();

        if (NOT Drift.IsEmpty())
        {
            const auto Joined = FString::Join(Drift, TEXT("; "));

            // Display, deliberately NOT Warning: the automation framework escalates captured
            // Warning/Error output to a failure on the running test (spec GOTCHA 1/13), which
            // would make every drifting test fail through the opaque log-capture path instead of
            // the explicit result below — the "Failed ... (0 assertions failed)" signature that is
            // so hard to read. Failing is the strict CVar's job, and it fails with a message.
            //
            // Named on the CULPRIT's own log window. Without this the same information only ever
            // reaches a human as an unexplained failure in some later, unrelated test.
            UE_LOG(LogCkAutoTest_EnvDrift, Display,
                TEXT("[%s] left console variables at a runtime-set priority after it finished: %s. ")
                TEXT("Route them through UCk_AutoTest_Base::Set_CVarForTest (or Snapshot_CVarForTest ")
                TEXT("for ones an engine path moves on your behalf) — that restores the prior VALUE ")
                TEXT("and PRIORITY, which is what drops them back out of this report. Restoring only ")
                TEXT("the value leaves the variable pinned at console priority for the rest of the ")
                TEXT("process, so later legitimate writes at a lower priority are silently ignored."),
                *GetName(), *Joined);

            if (ck::auto_test::env_drift::CVar_Strict.GetValueOnGameThread())
            {
                EffectiveResult   = EFunctionalTestResult::Failed;
                EffectiveMessage += FString::Printf(
                    TEXT(" | environment drift: %s"), *Joined);
            }
        }
    }

    if (NOT _EntityLeaksChecked)
    {
        _EntityLeaksChecked = true;

        // BEFORE Destroy_RunnerEntity, deliberately: the ownership walk excludes the runner's subtree
        // either way, but reading the graph while it is whole keeps the answer independent of how far
        // a deferred cascade happens to have got.
        const auto Leaked = Get_EntityLeaks();

        if (NOT Leaked.IsEmpty())
        {
            const auto Joined = FString::Join(Leaked, TEXT("; "));

            // Display, not Warning, as with the drift report above: a Warning during a functional test
            // is escalated to a failure through the opaque log-capture path. Failing is the CVar's job.
            UE_LOG(LogCkAutoTest_EntityLeaks, Display,
                TEXT("[%s] finished with %d entit%s alive outside its own lifetime subtree: %s. ")
                TEXT("ACk_AutoTestRunner::Destroy_RunnerEntity cascades ONLY the runner's subtree, so ")
                TEXT("these survive into every later test in this PIE world - and because drivers ")
                TEXT("discover their subjects by WORLD-scoped tag scan, they break unrelated tests far ")
                TEXT("from here. Register each out-of-subtree ROOT you create with ")
                TEXT("UCk_AutoTest_Base::Track_ForCleanup - but NEVER the ActorRelay channel entity ")
                TEXT("itself, which is pooled and shared with live subsystems."),
                *GetName(), Leaked.Num(), Leaked.Num() == 1 ? TEXT("y") : TEXT("ies"), *Joined);

            if (ck::auto_test::entity_leaks::CVar_Strict.GetValueOnGameThread())
            {
                EffectiveResult   = EFunctionalTestResult::Failed;
                EffectiveMessage += FString::Printf(
                    TEXT(" | leaked out-of-subtree entities: %s"), *Joined);
            }
        }
    }

    Super::FinishTest(EffectiveResult, EffectiveMessage);

    Destroy_RunnerEntity();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Capture_EnvironmentFingerprint()
    -> void
{
    _EnvFingerprint = ck::auto_test::env_drift::Capture_RuntimeSetCVars();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Get_EnvironmentDrift() const
    -> TArray<FString>
{
    TArray<FString> Drift;

    const auto Now = ck::auto_test::env_drift::Capture_RuntimeSetCVars();

    for (const auto& [Name, Value] : Now)
    {
        const auto* Before = _EnvFingerprint.Find(Name);

        if (Before == nullptr)
        {
            Drift.Add(FString::Printf(TEXT("%s newly set to [%s]"), *Name, *Value));
            continue;
        }

        if (*Before != Value)
        { Drift.Add(FString::Printf(TEXT("%s [%s] -> [%s]"), *Name, **Before, *Value)); }
    }

    // A variable that was runtime-set before the test and has since fallen back to a lower
    // priority is drift too — the next test no longer sees what this one inherited.
    for (const auto& [Name, Value] : _EnvFingerprint)
    {
        if (NOT Now.Contains(Name))
        { Drift.Add(FString::Printf(TEXT("%s [%s] -> unset"), *Name, *Value)); }
    }

    Drift.Sort();

    return Drift;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Capture_EntityBaseline()
    -> void
{
    _EntityBaseline.Reset();
    _EntityBaselineCaptured = false;

    const auto* World = GetWorld();

    if (NOT IsValid(World))
    { return; }

    const auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);

    if (ck::Is_NOT_Valid(TransientEntity))
    { return; }

    // Runs before the runner entity exists - Request_SpawnEntity in PrepareTest is deferred - so
    // the runner and everything under it correctly read as created BY this test.
    _EntityBaseline = ck::auto_test::entity_leaks::Capture_OwnedEntities(TransientEntity.Get_RegistryView());
    _EntityBaselineCaptured = true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Get_EntityLeaks() const
    -> TArray<FString>
{
    TArray<FString> Leaks;

    const auto* World = GetWorld();

    // No baseline means "cannot judge", not "nothing leaked".
    if (NOT IsValid(World) || NOT _EntityBaselineCaptured)
    { return Leaks; }

    const auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);

    if (ck::Is_NOT_Valid(TransientEntity))
    { return Leaks; }

    const auto& Registry = TransientEntity.Get_RegistryView();
    const auto RunnerEntity = _RunnerEntity;

    // Pass 1 collects everything that survived outside this test's subtree; pass 2 keeps only the ROOTS.
    TSet<FCk_Entity> Candidates;

    Registry.View<ck::FFragment_LifetimeOwner>().ForEach(
        [&](FCk_Entity InEntity, const ck::FFragment_LifetimeOwner&) -> void
        {
            // Existed before this test ran. This is also what reports a leak ONCE: the next test's
            // baseline contains it, so it is not re-attributed to every test after the culprit.
            if (_EntityBaseline.Contains(InEntity))
            { return; }

            const auto Handle = ck::MakeHandle(InEntity, Registry);

            if (NOT ck::IsValid(Handle, ck::IsValid_Policy_IncludePendingKill{}))
            { return; }

            // Already on its way out - the normal shape for anything a test DID declare via
            // Track_ForCleanup, because Finalize requests those destroys before writing the result and
            // Request_DestroyEntity stamps the tag synchronously down the dependent chain. Without this
            // check every well-behaved test that tracks anything reports as leaking. It does NOT cover
            // the runner's own subtree - Destroy_RunnerEntity has not run yet - hence the walk below.
            if (UCk_Utils_EntityLifetime_UE::Get_IsPendingDestroy(
                    Handle, ECk_EntityLifetime_DestructionPhase::BeginDestroy))
            { return; }

            // Walk to the lifetime root; anything at or under the runner is cascaded by
            // Destroy_RunnerEntity and is not a leak by definition.
            //
            // Starting at the entity ITSELF rather than its owner is load-bearing: the runner entity is
            // spawned after the baseline and parented to the world's TransientEntity, so it is "new"
            // and its own owner is not the runner. Start one link up and every test reports its own
            // runner as a leak. Pending-kill links are followed too, or a chain stopping at a marked
            // link reads as rooted elsewhere and is reported as a leak.
            auto Node = Handle;

            // Bounded rather than assumed acyclic: a cycle in the ownership graph would hang the run.
            constexpr auto MaxDepth = 64;
            auto Depth = 0;
            auto RootedUnderRunner = false;

            while (ck::IsValid(Node, ck::IsValid_Policy_IncludePendingKill{}) && Depth++ < MaxDepth)
            {
                if (Node == RunnerEntity)
                {
                    RootedUnderRunner = true;
                    break;
                }

                Node = ck::auto_test::entity_leaks::Get_OwnerOrInvalid(Node);
            }

            if (RootedUnderRunner)
            { return; }

            Candidates.Add(InEntity);
        });

    // Pass 2 - report ROOTS ONLY, i.e. drop any candidate whose ownership chain reaches another.
    //
    // A leak is one entity that escaped, not one per fragment composed onto it: a leaked NPC pawn
    // drags its states, attributes, SceneNodes, channels and renderer entries along as candidates,
    // because each one's root is the pawn rather than the runner. Reporting all of them is not merely
    // verbose - it buries the finding. "276 entities" is noise where "3 leaked NPC roots" is a work
    // item, and the work is identical because destroying the root cascades the rest.
    for (const auto& Candidate : Candidates)
    {
        const auto Handle = ck::MakeHandle(Candidate, Registry);

        auto Node = ck::auto_test::entity_leaks::Get_OwnerOrInvalid(Handle);

        constexpr auto MaxDepth = 64;
        auto Depth = 0;
        auto HasLeakedAncestor = false;

        while (ck::IsValid(Node, ck::IsValid_Policy_IncludePendingKill{}) && Depth++ < MaxDepth)
        {
            if (Candidates.Contains(Node.Get_Entity()))
            {
                HasLeakedAncestor = true;
                break;
            }

            Node = ck::auto_test::entity_leaks::Get_OwnerOrInvalid(Node);
        }

        if (HasLeakedAncestor)
        { continue; }

        Leaks.Add(FString::Printf(TEXT("%s [%s]"),
            *Handle.Get_DebugName().ToString(), *Candidate.ToString()));
    }

    Leaks.Sort();

    // The children are still worth a count - it says how much came with each root. Encoded into the
    // array rather than returned separately, to keep the shape of Get_EnvironmentDrift beside it.
    if (NOT Leaks.IsEmpty() && Candidates.Num() > Leaks.Num())
    {
        Leaks.Add(FString::Printf(
            TEXT("(+%d composed child entities under those roots, which the cascade takes with them)"),
            Candidates.Num() - Leaks.Num()));
    }

    return Leaks;
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
    EndPlay(
        const EEndPlayReason::Type EndPlayReason)
    -> void
{
    // World teardown / PIE stop. Destroy the runner entity first — for any
    // test that skipped FinishTest, this is also the safety net that
    // prevents the AS test's entity graph from leaking on the world's
    // TransientEntity. THEN drop our ref on the ensure-policy override:
    // restoring before destruction would leave the destruction-driven
    // cleanup ensures exposed to the modal-dialog policy.
    Destroy_RunnerEntity();
    Restore_EnsurePolicyOverride();

    Super::EndPlay(EndPlayReason);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTestRunner::
    Destroy_RunnerEntity()
    -> void
{
    if (ck::Is_NOT_Valid(_RunnerEntity))
    { return; }

    // Destroys the EntityScript root entity and (via the standard ECS lifetime
    // cascade) every child entity the AS test spawned. ForceDestroy bypasses
    // any pending-kill guards so cleanup is immediate — the next test must see
    // a clean world.
    FCk_Handle DestroyHandle = _RunnerEntity;
    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(
        DestroyHandle,
        ECk_EntityLifetime_DestructionBehavior::ForceDestroy);

    _RunnerEntity = FCk_Handle{};
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

        GOriginalDetailsPolicy = UCk_Utils_Core_UserSettings_UE::Get_EnsureDetailsPolicy();

        if (GOriginalDetailsPolicy == ECk_EnsureDetails_Policy::MessageAndStackTrace)
        {
            UE_LOG(LogCkAutoTest_Ensure, Display,
                TEXT("Overriding ensure details policy: MessageAndStackTrace -> MessageOnly for AutoTest run"));
            UCk_Utils_Core_UserSettings_UE::Set_EnsureDetailsPolicy(
                ECk_EnsureDetails_Policy::MessageOnly);
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

        const auto CurrentDetailsPolicy = UCk_Utils_Core_UserSettings_UE::Get_EnsureDetailsPolicy();
        if (CurrentDetailsPolicy != GOriginalDetailsPolicy)
        {
            UE_LOG(LogCkAutoTest_Ensure, Display,
                TEXT("Restoring ensure details policy after last AutoTest runner finished"));
            UCk_Utils_Core_UserSettings_UE::Set_EnsureDetailsPolicy(GOriginalDetailsPolicy);
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
        // Unreal asset-indexer SQLite warning when the Saved/Search dir is locked
        // by another process (e.g. another PIE editor) or simply absent. Not actionable
        // for gameplay tests — the indexer is editor-only and unrelated to test work.
        TEXT("LogSQLiteDatabase"),
        TEXT("LogFileInfo: Failed to open database"),
        // Console-system perf warning emitted when long-running PIE keeps hitting the
        // same CVar lookup. Diagnostic, not actionable per-test.
        TEXT("FindConsoleObject() calls (consider caching"),
        // Project Config/DefaultGameplayTags.ini references the test-side
        // GameplayTags_Tests_CkDT DataTable, which isn't always present in the
        // CkTests plugin's Content folder. The engine emits a Warning when the
        // async-load flush happens to land mid-test; the test gets blamed even
        // though the missing asset is purely a host-project config issue.
        TEXT("Failed to find object 'DataTable /CkTests/GameplayTags_Tests_CkDT"),
        // CkEcs scheduler perf advisories (CkProcessorScheduler). "High pump count
        // this frame" / "Pump limit [N] reached" fire when a single frame needs many
        // pump iterations to reach quiescence — e.g. a heavy spawn burst (an NPC with
        // customizer cosmetics, a truck whose static meshes stream in mid-settle).
        // They are diagnostic, not gameplay correctness, and still log in real runs;
        // a test that passes its own assertions must not be failed by them.
        TEXT("High pump count this frame"),
        TEXT("Pump limit ["),
        TEXT("implicit write-ordering edge"),
        // ZenServer (the DDC backend) drops its HTTP service and self-recovers a few
        // seconds later — routine on a machine running several editors, and the recovery
        // is logged as successful right after. The Warning lands on whichever test happens
        // to be mid-run, so it fails a DIFFERENT, innocent test every run and reads exactly
        // like flake. Observed 2026-08-15: one run failed BOTH Crowd_Stall_RepathsAround-
        // LateObstacle and Crowd_Separation_SpatialOrbitSearch this way — neither emitted a
        // `FinishTest TestResult=Failed` line, i.e. both had passed their own assertions.
        // Nothing under test asserts on DDC availability.
        TEXT("Unable to reach Unreal Zen Storage Server"),
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

    // Route through the BPNE so AS subclasses overriding Get_ExpectedLogErrors
    // (the canonical entry point — AS can't brace-init TArray<FString> via
    // `default`) take effect here instead of being silently bypassed by a
    // direct field read.
    for (const auto& Pattern : Get_ExpectedLogErrors())
    {
        if (Pattern.IsEmpty())
        { continue; }
        CurrentTest->AddExpectedErrorPlain(Pattern,
            EAutomationExpectedErrorFlags::Contains, SuppressAll);
    }
}
