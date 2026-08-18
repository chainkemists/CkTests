// The hydration quarantine's bounded escape. Fail-closed is only a safe default while something eventually opens
// it: an entity held back from every processor until its payloads apply must be released even when they never do,
// or a single stuck payload leaves part of the world structurally present and functionally invisible for the whole
// session. The probe's payload can never apply, and the frame cap is shortened below the apply timeout so the
// escape is the ONLY reachable exit — the test then asserts it both HAPPENED and SAID SO.
// Surface in Session Frontend: Ck.Snapshot.Ordering.QuarantineAlwaysLiftsAtFinish

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkCore/Format/CkFormat.h"    // ck::Format_UE — the identity spelling the report records

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/Tag/CkTag_HydrationQuarantine.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Quarantine.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_quarantine_escape
{
    const auto QuarantineEscape_SlotName = FName{TEXT("CkSnapshot_QuarantineEscape_GateSlot")};

    // Comfortably past the settle frames the load needs, and far short of the apply timeout (5s, ~300 frames) that
    // would otherwise empty the queue and let the NORMAL release fire instead of the escape.
    constexpr auto ShortenedFrameCap = 30;

    auto QuarantineEscape_ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::StaticClass());
    }

    auto QuarantineEscape_AnyEntityQuarantined(UWorld* InWorld) -> bool
    {
        if (InWorld == nullptr)
        { return false; }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Transient))
        { return false; }

        return Transient.Get_RegistryView().Has_AnyLiveEntityWith<ck::FTag_Hydration_Quarantine>();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_QuarantineAlwaysLiftsAtFinish_Gate,
    "Ck.Snapshot.Ordering.QuarantineAlwaysLiftsAtFinish",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_QuarantineAlwaysLiftsAtFinish_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_quarantine_escape;

    // Reaching the escape is LOUD by design — that is half of what this test is pinning — so the noise is declared
    // rather than silenced: an unmatched pattern here would mean the escape stopped reporting. Occurrences=0 accepts
    // any count (a Ck ensure reaches two log sinks). No regex metacharacters: the description is compiled as one.
    AddExpectedError(TEXT("settle hit the"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    AddExpectedError(TEXT("was released from the hydration quarantine by the"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
    AddExpectedError(TEXT("hydration quarantine FORCED off"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = QuarantineEscape_SlotName;

    // ONE cycle. A load that applies nothing cannot exercise the double-apply stacking a second cycle exists for.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        // The snapshot subsystem is GameInstance-scoped, so an override set here survives the load's travel and
        // governs the very load this test is about.
        if (auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(InServer))
        { Subsystem->TestOnly_Set_HydrateFrameCapOverride(ShortenedFrameCap); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* /*InServer*/) -> void
    {
        // Zeroed immediately before the save, so the count below describes the LOAD's delivery rather than the
        // pre-save world's — the probe binds its promise from BeginPlay in both.
        ck_autotest_snapshot_quarantine::Get_OnHydratedFireCount() = 0;
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(QuarantineEscape_ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        // Positive control: the load ran and restored the probe, so everything below is about a quarantine that was
        // really raised and really released — not about a load that never happened.
        const auto Probe = QuarantineEscape_ResolveProbe(Server);
        AllGood &= TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe));

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        const auto& Report = Subsystem->Get_LastLoadReport();

        // Second positive control: a payload really was queued, so "it never applied" is a stall rather than a
        // capture that produced nothing.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the load enqueued payloads to stall on (enqueued=%d)"), Report.Get_PayloadsEnqueued()),
            Report.Get_PayloadsEnqueued() >= 1);

        AllGood &= TestFalse(
            TEXT("NO live entity still carries the hydration quarantine once the load has finished"),
            QuarantineEscape_AnyEntityQuarantined(Server));

        // A forced release is a loss, and a loss nobody can name is the silence this record exists to break.
        const auto& Forced = Report.Get_QuarantineForced();
        AllGood &= TestTrue(
            FString::Printf(TEXT("the load report NAMES the entities it forced out of the quarantine (found %d)"),
                Forced.Num()),
            Forced.Num() >= 1);

        const auto ProbeIdentity = ck::Format_UE(TEXT("{}"), Probe);
        const auto* ProbeRecord = Forced.FindByPredicate(
            [&ProbeIdentity](const FCk_Snapshot_QuarantineForcedRecord& InRecord) -> bool
            { return InRecord.Get_Identity() == ProbeIdentity; });

        AllGood &= TestTrue(
            FString::Printf(TEXT("the stalled probe [%s] is one of the named entries"), *ProbeIdentity),
            ProbeRecord != nullptr);

        if (ProbeRecord != nullptr)
        {
            AllGood &= TestTrue(
                FString::Printf(TEXT("the probe's record states how much was lost (outstanding=%d)"),
                    ProbeRecord->Get_PayloadsOutstanding()),
                ProbeRecord->Get_PayloadsOutstanding() >= 1);
        }

        // Releasing the entity is not enough on its own. The probe bound Promise_OnHydrated from BeginPlay, long
        // before any lift could have happened, and an escape that quietly skipped its broadcast would leave that
        // consumer waiting for an edge that is never coming — the fail-closed wedge moved from the entity to the
        // people watching it. The loss is already in the report by the time this fires, so a consumer reacting to
        // the promise reads the truth about what came back.
        AllGood &= TestEqual(
            TEXT("Promise_OnHydrated STILL fired for the forced entity, exactly once"),
            ck_autotest_snapshot_quarantine::Get_OnHydratedFireCount(), 1);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
