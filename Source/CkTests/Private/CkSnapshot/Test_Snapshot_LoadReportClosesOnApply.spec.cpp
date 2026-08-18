// The load report closes on APPLY, not on enqueue.
//
// A report that partitions the save's payload rows by "did it reach the queue" answers a question nobody has:
// a row that was enqueued and then dropped at the apply timeout counted as accounted-for, so the arithmetic
// balanced on loads that lost state. The closure now asks what each row RESULTED IN, which means a real load has
// to produce non-zero apply buckets for the sum to balance at all.
// Surface in Session Frontend: Ck.Snapshot.Meta.LoadReportClosesOnApply

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_ApplyClosure.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadreport_closesonapply
{
    const auto ApplyClosure_SlotName = FName{TEXT("CkSnapshot_LoadReportClosesOnApply_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadReportClosesOnApply_Gate,
    "Ck.Snapshot.Meta.LoadReportClosesOnApply",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadReportClosesOnApply_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadreport_closesonapply;
    using namespace ck_autotest_snapshot_applyclosure;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = ApplyClosure_SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    // Drive both payloads off their construct defaults, so "applied" is provable by the values and not just
    // by a counter that could be incremented by anything.
    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        auto& Values = Probe.Get<ck::FFragment_AutoTest_ApplyClosure_Values>();
        Values._ValueA = MutatedValueA;
        Values._ValueB = MutatedValueB;
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

        const auto Probe = ResolveProbe(Server);
        AllGood &= TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe));

        if (ck::IsValid(Probe))
        {
            const auto& Values = Probe.Get<ck::FFragment_AutoTest_ApplyClosure_Values>();
            AllGood &= TestEqual(TEXT("payload A applied its saved value"), Values._ValueA, MutatedValueA);
            AllGood &= TestEqual(TEXT("payload B applied its saved value"), Values._ValueB, MutatedValueB);
        }

        const auto& Report = Subsystem->Get_LastLoadReport();

        // The point of the whole change: a healthy load reports what it APPLIED, and that number is what closes
        // the sum. Before the fold existed this was structurally zero on every load.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the report counts applied payloads (applied=%d)"), Report.Get_PayloadsApplied()),
            Report.Get_PayloadsApplied() >= 2);

        AllGood &= TestTrue(
            FString::Printf(TEXT("payload accounting closes on a real load (total=%d, applied=%d, rejected=%d, ")
                            TEXT("no-handler=%d, timed-out=%d, destroyed=%d, unapplied=%d, on-skipped=%d, ")
                            TEXT("on-orphaned=%d, unresolved-owner=%d, dropped=%d)"),
                Report.Get_PayloadsTotal(), Report.Get_PayloadsApplied(), Report.Get_PayloadsRejected(),
                Report.Get_PayloadsDroppedNoHandler(), Report.Get_PayloadsDroppedTimeout(),
                Report.Get_PayloadsDestroyedWithEntries(), Report.Get_PayloadsUnappliedAtFinish(),
                Report.Get_PayloadsOnSkippedEntities(), Report.Get_PayloadsOnOrphanedEntities(),
                Report.Get_PayloadsOnUnresolvedOwner(), Report.Get_PayloadsDropped()),
            Report.Get_IsPayloadAccountingClosed());

        AllGood &= TestTrue(TEXT("entity accounting closes too"), Report.Get_IsEntityAccountingClosed());

        // A clean load leaves nothing in flight. If this ever fails the sum above still closes — which is the
        // point of the bucket: the loss is NAMED rather than silently absorbed.
        AllGood &= TestEqual(TEXT("nothing was still queued when the load finished"),
            Report.Get_PayloadsUnappliedAtFinish(), 0);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
