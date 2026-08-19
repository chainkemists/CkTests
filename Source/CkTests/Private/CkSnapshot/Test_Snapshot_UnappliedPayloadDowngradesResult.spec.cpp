// A load that completed WITHOUT applying everything must not report Success.
//
// Two gates in one file, because they are the same statement about two different losses: a payload that timed out
// waiting to apply, and a payload whose type has no load path at all. Both leave a playable world missing named
// state, both must read as Succeeded_WithLoss, and both must still read as COMPLETED — a caller that treats them
// as a failed load skips its post-load work (BusterBlock's possession fixup is the live example) for a world that
// is perfectly loadable.
// Surface in Session Frontend: Ck.Snapshot.Report.UnappliedPayloadDowngradesResult
//                              Ck.Snapshot.Report.NoHandlerPayloadIsCountedAndNamed

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_NoHandlerPayload.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Quarantine.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_unapplied_downgrades
{
    const auto Timeout_SlotName   = FName{TEXT("CkSnapshot_UnappliedDowngradesResult_GateSlot")};
    const auto NoHandler_SlotName = FName{TEXT("CkSnapshot_NoHandlerPayloadNamed_GateSlot")};

    // The timeout gate has TWO terminal watchdogs racing for the same payload, and only one of them is its
    // subject. The 5 s wall-clock apply timeout empties the queue and lets the NORMAL release fire; the
    // 600-frame hydrate cap FORCES the quarantine off, which is the sibling QuarantineEscape gate's exit.
    // Whichever fires first claims the payload and decides the bucket.
    //
    // 600 frames vs 5 s wall makes the tipping point exactly 120 fps, and the drain phase runs at whatever the
    // lane allows. Measured on a leaf run of this test alone: drain started 12:35:50.504, the cap fired
    // 12:35:55.657 — 600 frames in 5.153 s, ~116 fps, the two watchdogs finishing 153 ms apart. Under 120 fps
    // the timeout wins and this gate passes; over it the cap wins and the gate reds on a path it does not own.
    // That is why it passed on every busy record lane and reds when run by itself.
    //
    // So the race is PINNED rather than tolerated: this gate lengthens the frame cap far past any frame rate a
    // PIE world load reaches, leaving the wall-clock watchdog as the only exit that can fire. It costs nothing
    // in the healthy case — the timeout still ends the load at ~5 s, and the cap is never approached. 3000
    // frames tolerates 600 fps, a 5x margin on the measured rate.
    constexpr auto LengthenedFrameCap = 3000;

    auto ResolveStallProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::StaticClass());
    }

    auto ResolveNoHandlerProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE::StaticClass());
    }

    auto Expect_LossDiagnostics(FAutomationTestBase& InTest) -> void
    {
        // A lossy load is LOUD by design — that is half of what these gates pin — so the noise is declared rather
        // than silenced. Occurrences=0 accepts any count (one Ck ensure reaches two log sinks).
        InTest.AddExpectedError(TEXT("the load COMPLETED WITH LOSS"),
            EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
        InTest.AddExpectedError(TEXT("LOST payload"),
            EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    }

    // The frame-cap escape's two lines, declared as IGNORED (-1) rather than expected (0). They must not occur —
    // LengthenedFrameCap exists to make sure of it — and they are not this gate's subject. Declaring them at 0
    // would REQUIRE them; leaving them undeclared would bury a lost race under an undeclared-error cascade that
    // says nothing about which watchdog won. Ignored, a lost race fails on the one assertion that names it: the
    // payload is counted in DroppedTimeout, and it would not be.
    auto Ignore_FrameCapEscapeDiagnostics(FAutomationTestBase& InTest) -> void
    {
        constexpr auto SilentlyIgnored = -1;
        InTest.AddExpectedError(TEXT("hydration quarantine"),
            EAutomationExpectedErrorFlags::Contains, SilentlyIgnored);
        InTest.AddExpectedError(TEXT("settle hit the"),
            EAutomationExpectedErrorFlags::Contains, SilentlyIgnored);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_UnappliedPayloadDowngradesResult_Gate,
    "Ck.Snapshot.Report.UnappliedPayloadDowngradesResult",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_UnappliedPayloadDowngradesResult_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_unapplied_downgrades;

    Expect_LossDiagnostics(*this);
    Ignore_FrameCapEscapeDiagnostics(*this);
    AddExpectedError(TEXT("was never applied"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = Timeout_SlotName;

    // ONE cycle. The probe's payload can never apply, so a second cycle proves nothing a first does not.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        // The exit under test is the 5 s apply timeout, which empties the queue and lets the NORMAL release
        // fire. The distinction from the quarantine-escape gate matters — this is a load that ended on its own
        // terms and still lost a payload, not one forced open by a cap. This gate used to set NO override and
        // relied on the timeout simply being quicker; at 600 frames vs 5 s that holds only under 120 fps. The
        // cap is LENGTHENED instead, so the watchdog under test is the only one that can claim the payload.
        // (The sibling gate SHORTENS the same cap, for the opposite reason.)
        if (auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(InServer))
        { Subsystem->TestOnly_Set_HydrateFrameCapOverride(LengthenedFrameCap); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(ResolveStallProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        AllGood &= TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(ResolveStallProbe(Server)));

        const auto& Report = Subsystem->Get_LastLoadReport();

        AllGood &= TestEqual(TEXT("the stalled payload is counted as a timeout drop"),
            Report.Get_PayloadsDroppedTimeout(), 1);

        AllGood &= TestTrue(TEXT("a load that lost a payload does NOT report Success"),
            Report.Get_Result() == ECk_SnapshotResult::Succeeded_WithLoss);

        // The half that keeps consumers working: lossy is still LOADED.
        AllGood &= TestTrue(TEXT("...and still reads as completed"), Report.Get_DidLoadComplete());

        const auto& Losses = Report.Get_PayloadLosses();
        const auto* TimedOut = Losses.FindByPredicate(
            [](const FCk_Snapshot_PayloadLossRecord& InRecord) -> bool
            { return InRecord.Get_Reason() == TEXT("timed-out"); });

        AllGood &= TestTrue(
            FString::Printf(TEXT("the lost payload is NAMED in the report (records=%d)"), Losses.Num()),
            TimedOut != nullptr);

        if (TimedOut != nullptr)
        {
            AllGood &= TestTrue(
                FString::Printf(TEXT("...with its type (%s)"), *TimedOut->Get_PayloadType()),
                TimedOut->Get_PayloadType().Contains(TEXT("QuarantineStall")));
            AllGood &= TestTrue(TEXT("...and the entity it belonged to"),
                NOT TimedOut->Get_OwnerIdentity().IsEmpty());
        }

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_NoHandlerPayloadIsCountedAndNamed_Gate,
    "Ck.Snapshot.Report.NoHandlerPayloadIsCountedAndNamed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_NoHandlerPayloadIsCountedAndNamed_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_unapplied_downgrades;

    Expect_LossDiagnostics(*this);
    AddExpectedError(TEXT("has no load path"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = NoHandler_SlotName;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(ResolveNoHandlerProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        AllGood &= TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(ResolveNoHandlerProbe(Server)));

        const auto& Report = Subsystem->Get_LastLoadReport();

        // Its own bucket, not the timeout's: nothing waited, so borrowing the timeout's name would say the
        // opposite of what happened.
        AllGood &= TestEqual(TEXT("the handler-less payload is counted in its own bucket"),
            Report.Get_PayloadsDroppedNoHandler(), 1);

        AllGood &= TestEqual(TEXT("...and NOT as a timeout"), Report.Get_PayloadsDroppedTimeout(), 0);

        AllGood &= TestTrue(TEXT("a load that dropped a payload for want of a handler reports the loss"),
            Report.Get_Result() == ECk_SnapshotResult::Succeeded_WithLoss);

        AllGood &= TestTrue(TEXT("...and still reads as completed"), Report.Get_DidLoadComplete());

        const auto& Losses = Report.Get_PayloadLosses();
        const auto* NoHandler = Losses.FindByPredicate(
            [](const FCk_Snapshot_PayloadLossRecord& InRecord) -> bool
            { return InRecord.Get_Reason() == TEXT("no-handler"); });

        AllGood &= TestTrue(
            FString::Printf(TEXT("the dropped payload is NAMED in the report (records=%d)"), Losses.Num()),
            NoHandler != nullptr);

        if (NoHandler != nullptr)
        {
            AllGood &= TestTrue(
                FString::Printf(TEXT("...by the type the save actually recorded (%s)"), *NoHandler->Get_PayloadType()),
                NoHandler->Get_PayloadType().Contains(TEXT("NoHandler_Orphan")));
            AllGood &= TestTrue(TEXT("...and the entity it belonged to"),
                NOT NoHandler->Get_OwnerIdentity().IsEmpty());
        }

        AllGood &= TestTrue(TEXT("payload accounting still closes when a payload had no load path"),
            Report.Get_IsPayloadAccountingClosed());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
