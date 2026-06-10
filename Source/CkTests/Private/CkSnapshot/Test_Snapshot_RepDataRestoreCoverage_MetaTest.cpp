// Ratchet meta-test for CkSnapshot restore-replication COVERAGE.
//
// A replicated feature only restores its client-visible values after a server snapshot load +
// seamless travel if it has a per-feature "ReplicateOnRestore" handler (recreate the per-owner
// container entry + re-arm the value trigger). That contract is opt-in and easy to forget: at the
// time this test was written, 3 of ~23 FCk_RepData_* types were covered.
//
// This test enumerates every FCk_RepData_* reflected struct at runtime and asserts each is EITHER:
//   - in the COVERED set (has a ReplicateOnRestore handler), or
//   - in the DEFERRED allowlist (documented reason why it is intentionally not yet covered).
//
// A NEW FCk_RepData_* type that is in neither set fails this test — forcing an explicit decision
// (cover it, or document why it is exempt) instead of silently shipping a feature whose replicated
// values vanish on the client after an MP reload. See HARDENING_RepDataRestoreCoverage.md.
//
// When you add restore coverage for a feature, MOVE its suffix from kDeferred to kCovered here.

#include "CkCore/Macros/CkMacros.h"

#include "Misc/AutomationTest.h"

#include "UObject/Class.h"
#include "UObject/UObjectIterator.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_repdata_coverage_test
{
    // Keyed by the suffix AFTER "RepData_" so the test is agnostic to the F / Ck_ reflected-name prefix
    // (UHT strips the leading F; e.g. FCk_RepData_FloatAttributes -> reflected "Ck_RepData_FloatAttributes").
    static auto Get_Covered() -> const TSet<FString>&
    {
        static const TSet<FString> Covered = {
            TEXT("FloatAttributes"),
            TEXT("ByteAttributes"),
            TEXT("IntegerAttributes"),
            TEXT("RotatorAttributes"),
            TEXT("VectorAttributes"),
            TEXT("TagSet"),
            TEXT("Acceleration"),
            TEXT("AnimPlans"),
            TEXT("Team"),
            TEXT("Player"),
        };
        return Covered;
    }

    // suffix -> reason. Every uncovered FCk_RepData_* MUST appear here with a documented reason.
    static auto Get_Deferred() -> const TMap<FString, FString>&
    {
        static const TMap<FString, FString> Deferred = {
            { TEXT("MontagePlayer"),            TEXT("clean self-container+tag fit, but feature not currently snapshotted (design call)") },
            { TEXT("Velocity"),                 TEXT("snapshot + ReplicateOnRestore wiring present (mirrors Acceleration) but no parity gate yet — a strict-value gate needs a movement-driven probe (PredictedVelocity re-derives the value on stationary actors)") },
            { TEXT("Location"),                 TEXT("SceneNode transform; restored via custom FFragment_Transform SerializeSnapshot — may re-derive, unclear (design call)") },
            { TEXT("Rotation"),                 TEXT("SceneNode transform; restored via custom FFragment_Transform SerializeSnapshot — may re-derive, unclear (design call)") },
            { TEXT("Scale"),                    TEXT("SceneNode transform; restored via custom FFragment_Transform SerializeSnapshot — may re-derive, unclear (design call)") },
            { TEXT("Inventory_Spatial_Items"),  TEXT("snapshotted, but transient SyncReplication fragment + child-item relink — complex; needs dedicated restore design") },
            { TEXT("Inventory_DataOnly_Items"), TEXT("snapshotted, but transient SyncReplication fragment + child-item relink — complex; needs dedicated restore design") },
            { TEXT("EntityCollections"),        TEXT("name-tag-keyed collection of child entities — identity hazard on restore; needs dedicated design") },
            { TEXT("2dGridPlacements"),         TEXT("CkGrid placement rep architecture unconfirmed (audit incomplete) — inspect before deciding") },
            { TEXT("GeometryCollectionOwner"),  TEXT("ephemeral destruction state (event-style); likely not meant to persist — semantics question") },
            { TEXT("StateMachine_NoHistory"),   TEXT("event-driven history replay, not value rep — INCOMPATIBLE with the value-restore pattern") },
            { TEXT("StateMachine_WithHistory"), TEXT("event-driven history replay ring, not value rep — INCOMPATIBLE with the value-restore pattern") },
            { TEXT("Container"),                TEXT("generic template base (TFragment_ContainerEntryRef<>), not a concrete replicated feature — N/A if it reflects at all") },
        };
        return Deferred;
    }

    static auto Suffix_Of(const FString& InReflectedName) -> FString
    {
        // InReflectedName like "Ck_RepData_FloatAttributes" -> "FloatAttributes"
        const auto Token = FString{TEXT("RepData_")};
        auto Index = InReflectedName.Find(Token);
        if (Index == INDEX_NONE)
        { return InReflectedName; }
        return InReflectedName.RightChop(Index + Token.Len());
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_RepDataRestoreCoverage_MetaTest,
    "Ck.Snapshot.Meta.RepDataRestoreCoverage",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_RepDataRestoreCoverage_MetaTest::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_repdata_coverage_test;

    const auto& Covered  = Get_Covered();
    const auto& Deferred = Get_Deferred();

    auto Discovered = TSet<FString>{}; // suffixes
    auto CoveredCount  = 0;
    auto DeferredCount = 0;

    for (TObjectIterator<UScriptStruct> It; It; ++It)
    {
        const auto Name = It->GetName();
        if (NOT Name.Contains(TEXT("RepData_")))
        { continue; }

        const auto Suffix = Suffix_Of(Name);
        Discovered.Add(Suffix);

        if (Covered.Contains(Suffix))
        {
            ++CoveredCount;
            continue;
        }

        if (const auto* Reason = Deferred.Find(Suffix))
        {
            ++DeferredCount;
            AddInfo(FString::Printf(TEXT("DEFERRED RepData [%s]: %s"), *Suffix, **Reason));
            continue;
        }

        // The ratchet: a new replicated container with NO coverage decision.
        AddError(FString::Printf(
            TEXT("Replicated container [%s] (reflected [%s]) has NO restore-replication coverage decision. ")
            TEXT("After a server snapshot load + seamless travel its replicated VALUES will silently fail to reach ")
            TEXT("clients. Either add a ReplicateOnRestore handler (then add its suffix to kCovered in this test), ")
            TEXT("or document why it is exempt (add it to kDeferred with a reason). See ")
            TEXT("HARDENING_RepDataRestoreCoverage.md."),
            *Suffix, *Name));
    }

    // Drift guard: every COVERED entry must actually exist (catches a rename/removal that would otherwise
    // make the covered set silently meaningless).
    for (const auto& CoveredSuffix : Covered)
    {
        TestTrue(
            FString::Printf(TEXT("Covered RepData [%s] still exists (not renamed/removed)"), *CoveredSuffix),
            Discovered.Contains(CoveredSuffix));
    }

    AddInfo(FString::Printf(
        TEXT("RepData restore-coverage: discovered=[%d] covered=[%d] deferred=[%d]"),
        Discovered.Num(), CoveredCount, DeferredCount));

    // Sanity: we expect a non-trivial number of replicated containers to exist; 0 means the match/enumeration broke.
    TestTrue(TEXT("Discovered at least the 3 covered attribute containers"), Discovered.Num() >= 3);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
