// T-C6-4 — ready-to-resume IS the promise, it fires once, and everything it claims is already true when it does.
//
// C6 moves the firing point of the existing triple (signal, promise list, pending delegate) from "the payloads
// drained" to "the world is coherent". Moving a firing point is exactly the change that turns one delivery into
// two — an extra broadcast at the old point, a re-entrant fire from the new one — so the count is asserted first.
// The rest is what the new point is FOR: at the instant a consumer is woken, the load has let go of the world,
// the world is the player's again, and the report it is handed is already closed, so a callback that branches on
// the result is not reading a number still being written.
//
// Two loads with a listener that arms exactly once: a promise that stayed bound would fire on the second.
//
// RED before C6: Get_IsReadyToResume does not exist, and the promise fired from a point where physics and probe
// overlaps had not converged — the claim this test makes about the fire instant was not a claim the code made.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.ReadyToResumeFiresOnceAfterClosure

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Misc/ScopeExit.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Signal/CkSignal_Macros.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Signals.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_PromiseListener.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_readytoresume
{
    const auto ReadyToResume_SlotName = FName{TEXT("CkSnapshot_LoadHoldReadyToResume_GateSlot")};

    constexpr auto NumCycles = 2;

    auto Arm_PreLoadBind(UWorld* InWorld, UCk_AutoTest_Snapshot_PromiseListener_UE* InListener) -> void
    {
        if (InWorld == nullptr || InListener == nullptr)
        { return; }

        auto Source = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Source))
        { return; }

        auto Delegate = FCk_Delegate_Snapshot_OnPreLoad{};
        Delegate.BindUFunction(InListener, TEXT("OnPreLoad"));
        CK_SIGNAL_BIND(ck::UUtils_Signal_Snapshot_OnPreLoad, Source, Delegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_ReadyToResumeFiresOnceAfterClosure,
    "Ck.Snapshot.LoadHold.ReadyToResumeFiresOnceAfterClosure",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_ReadyToResumeFiresOnceAfterClosure::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_readytoresume;

    auto* Listener = NewObject<UCk_AutoTest_Snapshot_PromiseListener_UE>();
    Listener->AddToRoot();

    const auto AssertRuns = MakeShared<int32>(0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = ReadyToResume_SlotName;
    Spec.NumPIEClients = 1;
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

        // One-shot across BOTH loads: moving the firing point must not leave a second broadcast at the old one.
        AllGood &= TestEqual(TEXT("it fired exactly once across both loads"), Listener->_FireCount, 1);

        if (Listener->_FireCount == 0)
        { return false; }

        AllGood &= TestTrue(TEXT("at the fire instant the world was READY TO RESUME"),
            Listener->_ReadyToResumeAtFire);

        // Deliberately NOT the inverse of the above — between them sits every phase in which the world exists
        // but is not yet the player's. At the fire instant both must have resolved.
        AllGood &= TestFalse(TEXT("...and the load had already let go of it"),
            Listener->_LoadInProgressAtFire);

        AllGood &= TestTrue(TEXT("...and the report handed to the callback was already CLOSED — a consumer "
                                 "branching on the result is not reading a number still being written"),
            Listener->_AccountingClosedAtFire);

        // A healthy load gives up on nothing. Recorded rather than merely implied: Succeeded_WithLoss with a
        // named convergence row is the shape the bounded escape produces, and this is not that load.
        AllGood &= TestEqual(TEXT("...and it names no unmet convergence facts"),
            Listener->_ConvergenceUnmetAtFire, 0);

        AllGood &= TestTrue(TEXT("...with a real report, not a default-constructed one"),
            Listener->_LastResult == ECk_SnapshotResult::Success ||
            Listener->_LastResult == ECk_SnapshotResult::Succeeded_WithLoss);

        // The pull channel agrees with the push channel: a consumer that was not party to the Request_Load call
        // reads the same verdict.
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        AllGood &= TestTrue(TEXT("the subsystem still reports ready-to-resume once the world is running"),
            Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
