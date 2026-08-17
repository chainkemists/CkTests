// T-C4-3 — a hydration payload whose type has no load path must be reported as its OWN outcome and must ENSURE.
//
// ck::persistence_apply::ApplyOne resolves a payload's handler and calls HydrationApply. When there is no handler,
// or the resolved handler never declared a HydrationApply, the entry is data loss: the save recorded state that
// this build cannot apply. That branch used to return DroppedTimeout — borrowing the timeout's name for a case
// that never waited — with no log, no ensure and no counter, which made it the one outcome in the whole apply
// path a consumer could not distinguish or even observe.
//
// This is a pure-arithmetic-level test: no world, no load. ApplyOne's no-handler check runs before it touches the
// entity, so an invalid handle is a legitimate argument here and keeps the test world-free.

#include "CkCore/Ensure/CkEnsure_Utils.h" // Get_EnsureCount — the enforceable "it ensured" assertion
#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Persistence/CkPersistenceHydration_Processor.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_MissingHandlerIsCountedAndEnsured_Test,
    "Ck.Snapshot.Report.MissingHandlerIsCountedAndEnsured",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_MissingHandlerIsCountedAndEnsured_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto* PayloadType = FCk_Test_DynFrag_PureData::StaticStruct();

    // Premise. This test is only meaningful while nothing gives this type a load path: no per-type handler, and
    // whatever the fallback resolves to must not carry a HydrationApply either (CkDynamic's fallback is NetApply-only).
    // If a future change registers one, this assert fails LOUDLY rather than the test passing vacuously.
    TestNull(TEXT("the fixture payload type has no per-type handler"),
        FCk_PersistenceHandlerRegistry::Find(PayloadType));

    const auto* Resolved = FCk_PersistenceHandlerRegistry::Resolve(PayloadType);
    TestTrue(TEXT("...and nothing it resolves to declares a HydrationApply"),
        Resolved == nullptr || NOT static_cast<bool>(Resolved->HydrationApply));

    // Suppresses the ensure's Error so the harness does not escalate it to a failure. Occurrences = 0 means "at
    // least once", which is deliberate: ONE Ck ensure firing emits its message through two log sinks (measured —
    // an exact expectation of 1 fails with "found 2 time(s)"). The exact-once guarantee comes from the ensure
    // COUNT below, which is the count of ensures rather than of log lines.
    AddExpectedError(TEXT("has no load path"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    const auto EnsureCountBefore = UCk_Utils_Ensure_UE::Get_EnsureCount();

    auto NoEntity = FCk_Handle{};
    auto PendingForSeconds = 0.0f;
    const auto Outcome = ck::persistence_apply::ApplyOne(
        NoEntity,
        FInstancedStruct::Make(FCk_Test_DynFrag_PureData{}),
        TOptional<FInstancedStruct>{},
        PendingForSeconds,
        FCk_Time{});

    TestTrue(TEXT("a payload with no load path reports DroppedNoHandler, not DroppedTimeout"),
        Outcome == ck::persistence_apply::EApplyOutcome::DroppedNoHandler);

    TestEqual(TEXT("...and it ensured exactly once — this outcome is data loss, never silent"),
        UCk_Utils_Ensure_UE::Get_EnsureCount(), EnsureCountBefore + 1);

    // Terminal on the first call: nothing waited, so nothing may accumulate toward the retry timeout either.
    TestEqual(TEXT("the no-handler drop accumulates no pending time"), PendingForSeconds, 0.0f);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
