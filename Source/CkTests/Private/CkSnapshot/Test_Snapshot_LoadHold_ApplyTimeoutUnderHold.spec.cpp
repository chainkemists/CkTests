// T-C6-11 — the apply timeout still fires while the game is frozen. The counterweight to T-C6-3.
//
// T-C6-3 says nothing paced by game time advances during a load. This says the one thing that MUST advance still
// does. The two pull in opposite directions and are authored as a pair: satisfy the first by freezing everything
// and the per-payload apply watchdog dies with it — C4's whole DroppedTimeout bucket, its named ensure and its
// bound go dead, and every bad payload degrades into the UNNAMED "still queued at finish" bucket after burning the
// frame cap. A watchdog measured in the clock it is watching cannot expire inside the window it exists to bound.
//
// The probe's payload can never apply (its handler always answers NotReady), and the hydrate frame cap is raised
// well above its shipping value so the WALL-clock timeout is unambiguously what ends the stall rather than the
// frame fence racing it. What the test then asserts is that the entry landed in its OWN named bucket, that nothing
// was left unaccounted for, and that the load finished through the healthy settled path rather than through the
// quarantine's forced escape.
//
// GREEN both sides of C6 by design: pre-range the timeout accrued game time and the world was not frozen, so it
// fired for a different reason. This is a regression guard on the pair, not a differentiator.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.ApplyTimeoutStillFiresUnderTheHold

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Quarantine.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_applytimeout
{
    const auto ApplyTimeout_SlotName = FName{TEXT("CkSnapshot_LoadHoldApplyTimeout_GateSlot")};

    // Deliberately far above the shipping 600. The apply timeout is 5 s of WALL time outside Shipping, and a
    // headless -nullrhi editor can burn 600 frames in less than that — which would end the stall at the frame
    // fence and leave this test measuring the escape instead of the watchdog. Raising the fence removes the race
    // in the only direction that matters.
    constexpr auto RaisedHydrateFrameCap = 5000;

    auto Resolve_Probe(UWorld* InWorld) -> FCk_Handle
    {
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_ApplyTimeoutStillFiresUnderTheHold,
    "Ck.Snapshot.LoadHold.ApplyTimeoutStillFiresUnderTheHold",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_ApplyTimeoutStillFiresUnderTheHold::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_applytimeout;

    // The timeout is LOUD by design — that is the half of it C4 cared about — so the noise is declared rather
    // than silenced. An unmatched pattern here would mean the drop stopped naming itself.
    AddExpectedError(TEXT("was never applied: Apply kept returning NotReady"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    AddExpectedError(TEXT("the load COMPLETED WITH LOSS"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    // The loss RECORD the drop produces. Declared for the same reason as the ensure above: this test exists to
    // make the timeout fire, so the line naming what it cost is expected output, not an unexplained error.
    AddExpectedError(TEXT("LOST payload"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = ApplyTimeout_SlotName;
    Spec.NumPIEClients = 1;

    // ONE cycle: a load whose payload never applies has nothing for a second cycle's double-apply check to stack.
    Spec.NumCycles = 1;

    // The stall is a wall-clock wait of at least the apply timeout, on top of an ordinary reload.
    Spec.ReloadTimeoutSeconds = 120.0f;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        // GameInstance-scoped, so it survives the load's travel and governs the very load under test.
        if (auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(InServer))
        { Subsystem->TestOnly_Set_HydrateFrameCapOverride(RaisedHydrateFrameCap); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(Resolve_Probe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        Subsystem->TestOnly_Set_HydrateFrameCapOverride(0);

        const auto Report = Subsystem->Get_LastLoadReport();

        // Positive controls: the probe came back and a payload really was queued, so "it timed out" describes a
        // stall rather than a capture that produced nothing.
        auto AllGood = TestTrue(TEXT("the probe was restored (the load ran)"),
            ck::IsValid(Resolve_Probe(Server)));

        AllGood &= TestTrue(
            FString::Printf(TEXT("the load enqueued payloads to stall on (enqueued=%d)"),
                Report.Get_PayloadsEnqueued()),
            Report.Get_PayloadsEnqueued() >= 1);

        // The assertion. Its own bucket, with its own name, reached through a clock the freeze cannot stop.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the stalled payload landed in DroppedTimeout (found %d) — the apply watchdog is "
                                 "wall-clocked, so it still expires inside a load that has frozen game time"),
                Report.Get_PayloadsDroppedTimeout()),
            Report.Get_PayloadsDroppedTimeout() >= 1);

        // ...and NOT in the unnamed bucket, which is where it would land if the watchdog had gone dead and the
        // frame cap had had to end the phase instead.
        AllGood &= TestEqual(
            FString::Printf(TEXT("...and nothing degraded into the unnamed 'still queued at finish' bucket (found %d)"),
                Report.Get_PayloadsUnappliedAtFinish()),
            Report.Get_PayloadsUnappliedAtFinish(), 0);

        // The healthy path: with the queue emptied by the timeout, the quarantine lifts on the SETTLED route and
        // nothing has to be forced out of it.
        AllGood &= TestEqual(
            FString::Printf(TEXT("the quarantine lifted on the settled path — nothing was forced (found %d)"),
                Report.Get_QuarantineForced().Num()),
            Report.Get_QuarantineForced().Num(), 0);

        AllGood &= TestTrue(TEXT("the load still reads as completed — the world came back playable"),
            Report.Get_DidLoadComplete());

        AllGood &= TestTrue(TEXT("...and the world was handed back"), Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
