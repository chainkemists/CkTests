// Low-level C++ automation test for the snapshot classification audit (the runtime half of the holder/record
// forced-choice mechanism).
//
// The compile-time half makes an UNCLASSIFIED holder/record a compile error. This audit covers the residual: a type
// classified ck::FSnapshotPolicy_RoundTrip whose CK_REGISTER_SNAPSHOTABLE was forgotten — which would silently drop
// it from every save/load. ck::snapshot_audit::Audit_Compare returns the announced-but-unregistered offenders.
//
// This test exercises the pure comparator with a synthetic expected-set (one registered control + one definitely-
// unregistered hash) so it does NOT pollute the process-wide announce set. The POSITIVE path (every real RoundTrip
// type announced AND registered -> capture-time audit silent) is exercised end-to-end by every other snapshot test:
// they capture a world, which runs Audit_ExpectedAreRegistered once, and they would fail on a spurious ensure.

#include "CkEcs/Snapshot/CkSnapshot_Audit.h"
#include "CkEcs/Snapshot/CkSnapshot_FragmentRegistry.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Audit_UnregisteredRoundTrip_Test,
    "Ck.Snapshot.Audit.UnregisteredRoundTripFlagged",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Audit_UnregisteredRoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto& Registry = ck::FCk_Snapshot_FragmentRegistry::Get();

    // The registry is populated with the project's real registered fragments at static-init. Use the first as a
    // "registered control" — the audit must NOT flag it.
    const auto& AllRegistered = Registry.Get_All();
    if (NOT TestTrue(TEXT("Fragment registry is non-empty (static-init registrations ran)"), AllRegistered.Num() > 0))
    { return false; }

    const auto RegisteredHash = AllRegistered[0]._EnttTypeHash;

    // Find a hash that is definitely NOT registered (walk until Find_ByEnttHash misses), so the test can't be
    // defeated by an unlucky collision with a real registered type.
    auto UnregisteredHash = uint32{0xDEADBEEF};
    while (Registry.Find_ByEnttHash(UnregisteredHash) != nullptr)
    { ++UnregisteredHash; }

    // Synthetic expected set: one registered, one not. The audit must flag ONLY the unregistered one.
    auto Expected = TMap<uint32, FString>{};
    Expected.Add(RegisteredHash,   TEXT("RegisteredControlType"));
    Expected.Add(UnregisteredHash, TEXT("FakeUnregisteredRoundTripType"));

    const auto Offenders = ck::snapshot_audit::Audit_Compare(Expected, Registry);

    TestTrue(TEXT("An announced-but-unregistered RoundTrip type IS flagged"),
        Offenders.Contains(TEXT("FakeUnregisteredRoundTripType")));
    TestFalse(TEXT("A registered type is NOT flagged"),
        Offenders.Contains(TEXT("RegisteredControlType")));
    TestEqual(TEXT("Exactly one offender"), Offenders.Num(), 1);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
