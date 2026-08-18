// Meta-test for the FCk_Snapshot_LoadReport accounting invariant.
//
// A v3 load report is only trustworthy if it accounts for 100% of what the save contained: every saved entity is
// EITHER restored, deliberately skipped, or orphaned; every saved payload ended in exactly one TERMINAL outcome —
// applied, rejected, dropped for want of a handler or at the apply timeout, destroyed with its entity, still
// unapplied when the load finished, or never enqueued at all (skipped/orphaned/unresolved owner, or a failed
// deserialize). Get_IsAccountingClosed is the assertable form of that, and the BB gates assert it on real loads.
//
// Enqueued is deliberately NOT a term: it says a row reached the apply queue, not what became of it, so a report
// that balanced on it balanced just as happily on loads that dropped everything they enqueued.
//
// This test pins the arithmetic itself: pure struct math, no world, no load. It exists so a future field addition
// that forgets to join a sum is caught here rather than by a silently-lenient gate. Its real-load sibling is
// Ck.Snapshot.Meta.LoadReportClosesOnApply.

#include "CkCore/Macros/CkMacros.h"

#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_loadreport_sumclosure_test
{
    auto Make_ClosedReport() -> FCk_Snapshot_LoadReport
    {
        auto Report = FCk_Snapshot_LoadReport{};
        Report.Set_Result(ECk_SnapshotResult::Success);

        Report.Set_EntitiesTotal(10);
        Report.Set_EntitiesRestored(6);
        Report.Set_EntitiesSkipped(3);
        Report.Set_EntitiesOrphaned(1);

        Report.Set_PayloadsTotal(20);

        // 12 rows reached the queue and each ended somewhere; 8 never got there.
        Report.Set_PayloadsEnqueued(12);
        Report.Set_PayloadsApplied(6);
        Report.Set_PayloadsRejected(1);
        Report.Set_PayloadsDroppedNoHandler(1);
        Report.Set_PayloadsDroppedTimeout(1);
        Report.Set_PayloadsDestroyedWithEntries(2);
        Report.Set_PayloadsUnappliedAtFinish(1);

        Report.Set_PayloadsOnSkippedEntities(4);
        Report.Set_PayloadsOnOrphanedEntities(2);
        Report.Set_PayloadsOnUnresolvedOwner(1);
        Report.Set_PayloadsDropped(1);

        return Report;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadReportSumClosure_MetaTest,
    "Ck.Snapshot.Meta.LoadReportSumClosure",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_LoadReportSumClosure_MetaTest::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_loadreport_sumclosure_test;

    {
        const auto Report = Make_ClosedReport();
        TestTrue(TEXT("A fully-accounted report closes on entities"), Report.Get_IsEntityAccountingClosed());
        TestTrue(TEXT("A fully-accounted report closes on payloads"), Report.Get_IsPayloadAccountingClosed());
        TestTrue(TEXT("A fully-accounted report closes overall"), Report.Get_IsAccountingClosed());
    }

    {
        // The empty report is the degenerate closed case — a failed load (no tables read) must not look unaccounted.
        const auto Report = FCk_Snapshot_LoadReport{};
        TestTrue(TEXT("A default-constructed report closes (all buckets zero)"), Report.Get_IsAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_EntitiesSkipped(Report.Get_EntitiesSkipped() - 1);
        TestFalse(TEXT("An unaccounted saved entity breaks entity closure"), Report.Get_IsEntityAccountingClosed());
        TestTrue(TEXT("...while payload closure is unaffected"), Report.Get_IsPayloadAccountingClosed());
        TestFalse(TEXT("...and the overall query reports it"), Report.Get_IsAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_EntitiesRestored(Report.Get_EntitiesRestored() + 1);
        TestFalse(TEXT("Double-counting a saved entity breaks entity closure"), Report.Get_IsEntityAccountingClosed());
    }

    // One case per payload bucket: every bucket must participate in the sum, so dropping a unit from any of them
    // must break closure. That is exactly the failure a future field addition would introduce.
    {
        // The polarity that flipped: enqueued is a diagnostic, so moving it must NOT disturb the closure. A report
        // whose closure still keys on it would fail here.
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsEnqueued(Report.Get_PayloadsEnqueued() - 1);
        TestTrue(TEXT("PayloadsEnqueued is a diagnostic, not a closure term"),
            Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsApplied(Report.Get_PayloadsApplied() - 1);
        TestFalse(TEXT("PayloadsApplied participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsRejected(Report.Get_PayloadsRejected() - 1);
        TestFalse(TEXT("PayloadsRejected participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsDroppedNoHandler(Report.Get_PayloadsDroppedNoHandler() - 1);
        TestFalse(TEXT("PayloadsDroppedNoHandler participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsDroppedTimeout(Report.Get_PayloadsDroppedTimeout() - 1);
        TestFalse(TEXT("PayloadsDroppedTimeout participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsDestroyedWithEntries(Report.Get_PayloadsDestroyedWithEntries() - 1);
        TestFalse(TEXT("PayloadsDestroyedWithEntries participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsUnappliedAtFinish(Report.Get_PayloadsUnappliedAtFinish() - 1);
        TestFalse(TEXT("PayloadsUnappliedAtFinish participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsOnSkippedEntities(Report.Get_PayloadsOnSkippedEntities() - 1);
        TestFalse(TEXT("PayloadsOnSkippedEntities participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsOnOrphanedEntities(Report.Get_PayloadsOnOrphanedEntities() - 1);
        TestFalse(TEXT("PayloadsOnOrphanedEntities participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsOnUnresolvedOwner(Report.Get_PayloadsOnUnresolvedOwner() - 1);
        TestFalse(TEXT("PayloadsOnUnresolvedOwner participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    {
        auto Report = Make_ClosedReport();
        Report.Set_PayloadsDropped(Report.Get_PayloadsDropped() - 1);
        TestFalse(TEXT("PayloadsDropped participates in the sum"), Report.Get_IsPayloadAccountingClosed());
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
