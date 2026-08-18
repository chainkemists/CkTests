// Promise_OnLoadComplete: travel-safe, honest outside a load, and one-shot.
//
// Three gates over one contract. The promise used to be an ECS signal bound on the CALLER's world transient while
// the broadcast happened on the POST-travel world's — so a promise armed during a load (which is when consumers
// reach for it) died with the world it was armed in, silently. It is now held by the snapshot subsystem, which is
// GameInstance-scoped and survives the travel.
// Surface in Session Frontend: Ck.Snapshot.Promise.SurvivesTravel
//                              Ck.Snapshot.Promise.NoLoadInProgress
//                              Ck.Snapshot.Promise.OneShotAcrossTwoLoads

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Misc/ScopeExit.h"            // ON_SCOPE_EXIT — the rooted listener is unrooted on every path

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Signal/CkSignal_Macros.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/CkSnapshot_Utils.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Signals.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_PromiseListener.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_promise_onloadcomplete
{
    const auto SurvivesTravel_SlotName = FName{TEXT("CkSnapshot_PromiseSurvivesTravel_GateSlot")};
    const auto OneShot_SlotName        = FName{TEXT("CkSnapshot_PromiseOneShot_GateSlot")};

    // Rooted for the duration: the listener has to outlive the load's level travel, or the promise has no
    // subscriber left to deliver to and the test would pass for the wrong reason.
    auto Make_RootedListener() -> UCk_AutoTest_Snapshot_PromiseListener_UE*
    {
        auto* Listener = NewObject<UCk_AutoTest_Snapshot_PromiseListener_UE>();
        Listener->AddToRoot();
        return Listener;
    }

    auto Arm_PreLoadBind(UWorld* InWorld, UCk_AutoTest_Snapshot_PromiseListener_UE* InListener) -> void
    {
        if (InWorld == nullptr || InListener == nullptr)
        { return; }

        auto Source = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Source))
        { return; }

        // OnPreLoad fires from INSIDE Request_Load, after the load has latched and before the teardown/travel —
        // the one moment a pre-travel arm is both possible and meaningful. Under the old world-scoped bind this
        // is precisely the promise that was lost.
        auto Delegate = FCk_Delegate_Snapshot_OnPreLoad{};
        Delegate.BindUFunction(InListener, TEXT("OnPreLoad"));
        CK_SIGNAL_BIND(ck::UUtils_Signal_Snapshot_OnPreLoad, Source, Delegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_PromiseSurvivesTravel_Gate,
    "Ck.Snapshot.Promise.SurvivesTravel",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_PromiseSurvivesTravel_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_promise_onloadcomplete;

    auto* Listener = Make_RootedListener();

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SurvivesTravel_SlotName;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([Listener](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        Arm_PreLoadBind(InServer, Listener);
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Listener]() -> bool
    {
        // Unrooted on every exit — a rooted fixture left behind outlives the test in a shared PIE process.
        ON_SCOPE_EXIT { Listener->RemoveFromRoot(); };

        auto AllGood = TestEqual(TEXT("the promise was armed once, from the PRE-travel world"),
            Listener->_ArmCount, 1);

        // The whole point: armed before the travel, delivered after it.
        AllGood &= TestEqual(TEXT("a promise armed before the load's travel still fired"),
            Listener->_FireCount, 1);

        AllGood &= TestTrue(TEXT("...with the real report, not a default-constructed one"),
            Listener->_LastResult == ECk_SnapshotResult::Success ||
            Listener->_LastResult == ECk_SnapshotResult::Succeeded_WithLoss);

        AllGood &= TestTrue(TEXT("...and a valid handle from the POST-travel world"),
            Listener->_LastHandleWasValid);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_PromiseNoLoadInProgress_Gate,
    "Ck.Snapshot.Promise.NoLoadInProgress",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_PromiseNoLoadInProgress_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_promise_onloadcomplete;

    // No save, no load — just a world. The contract under test is what the promise does when there is nothing to
    // wait for, so introducing a load would be testing something else.
    constexpr auto NumClients = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;

    auto* Listener = Make_RootedListener();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(NumClients, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Listener]() -> bool
        {
            ON_SCOPE_EXIT { Listener->RemoveFromRoot(); };

            auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
            if (NOT TestTrue(TEXT("world resolves"), Server != nullptr))
            { return true; }

            auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
            if (NOT TestTrue(TEXT("snapshot subsystem present"), Subsystem != nullptr))
            { return true; }

            auto AllGood = TestFalse(TEXT("premise: no load is in progress"), Subsystem->Get_IsLoadInProgress());

            auto Source = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Server);

            auto Delegate = FCk_Delegate_Snapshot_OnLoadComplete{};
            Delegate.BindUFunction(Listener, TEXT("OnLoadComplete"));

            const auto Result = UCk_Utils_Snapshot_UE::Promise_OnLoadComplete(Source, Delegate);

            // Synchronously, inside the call — a consumer that binds "converge now or when the load lands" gets
            // the now case immediately, which is what makes the single call shape usable at all.
            AllGood &= TestEqual(TEXT("the delegate fired immediately"), Listener->_FireCount, 1);

            // The lie this replaces: a default-constructed report says Failed_IO, so every consumer that branched
            // on Result saw a FAILURE for a load that never happened.
            AllGood &= TestTrue(TEXT("...with Result = NoLoadInProgress, not a failure"),
                Listener->_LastResult == ECk_SnapshotResult::NoLoadInProgress);

            AllGood &= TestFalse(TEXT("...which does not read as a completed load"),
                FCk_Snapshot_LoadReport{}.Get_DidLoadComplete());

            AllGood &= TestTrue(TEXT("and the call REPORTS that it fired rather than queued"),
                Result == ECk_Snapshot_PromiseResult::NoLoadInProgress);

            return AllGood;
        }),
        TEXT("Promise_OnLoadComplete outside a load")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_PromiseOneShotAcrossTwoLoads_Gate,
    "Ck.Snapshot.Promise.OneShotAcrossTwoLoads",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_PromiseOneShotAcrossTwoLoads_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_promise_onloadcomplete;

    auto* Listener = Make_RootedListener();
    Listener->_ReArmInsideCallback = true;

    // Assert re-runs after EVERY cycle, so the fixture is unrooted by whichever run is the last one.
    constexpr auto NumCycles = 2;
    const auto AssertRuns = MakeShared<int32>(0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = OneShot_SlotName;

    // TWO save/load cycles, and the listener arms exactly once (its own guard), so a promise that stayed bound
    // would fire on the second load too.
    Spec.NumCycles = NumCycles;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([Listener](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        Arm_PreLoadBind(InServer, Listener);
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Listener, AssertRuns]() -> bool
    {
        ON_SCOPE_EXIT
        {
            ++(*AssertRuns);
            if (*AssertRuns >= NumCycles)
            { Listener->RemoveFromRoot(); }
        };

        auto AllGood = TestEqual(TEXT("the promise was armed exactly once"), Listener->_ArmCount, 1);

        // One-shot means one-shot: the second load must not re-deliver a promise nobody re-armed.
        AllGood &= TestEqual(TEXT("it fired exactly once across BOTH loads"), Listener->_FireCount, 1);

        // Re-arming from inside the callback is the re-entrancy case: _LoadInProgress is already cleared by the
        // time promises drain, so the re-arm takes the immediate path — and must NOT land in the array being
        // iterated, which would either drop it or deliver it twice.
        AllGood &= TestTrue(TEXT("a re-arm from inside the callback took the no-load-in-progress path"),
            Listener->_ReArmReturnedNoLoadInProgress);

        AllGood &= TestEqual(TEXT("...and fired immediately, exactly once"), Listener->_ReArmFireCount, 1);

        AllGood &= TestTrue(TEXT("...with Result = NoLoadInProgress"),
            Listener->_ReArmResult == ECk_SnapshotResult::NoLoadInProgress);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
