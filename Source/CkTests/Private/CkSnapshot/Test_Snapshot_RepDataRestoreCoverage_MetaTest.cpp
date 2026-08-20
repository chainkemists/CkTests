// Ratchet meta-test for CkSnapshot restore-replication COVERAGE.
//
// A replicated feature only restores its client-visible values after a server snapshot load +
// seamless travel if it has a per-feature "ReplicateOnRestore" handler (recreate the per-owner
// container entry + re-arm the value trigger). That contract is opt-in and easy to forget: at the
// time this test was written, 3 of ~23 FCk_RepData_* types were covered.
//
// This test enumerates every FCk_RepData_* reflected struct at runtime and asserts each is EITHER:
//   - in the COVERED set (has a ReplicateOnRestore handler), or
//   - in the DEFERRED allowlist (documented reason why it is intentionally not yet covered), or
//   - registered SAVE-ONLY in FCk_PersistenceHandlerRegistry (probed live, not hand-listed): such a type
//     "never rides a replicated container" (the Register_SaveOnly contract), so there are no client-visible
//     replicated values to restore — restore-replication is N/A by construction, and the registration itself
//     IS the documented decision. The exemption self-revokes: if the registration ever gains net participation
//     (e.g. FogOfWar's staged co-op upgrade), the probe stops matching and this ratchet re-arms for that type, or
//   - registered NET-ONLY (Register_NetOnly): the symmetric case, and it needs its own arm rather than falling
//     through to the save-only one. Such a type never ENTERS a snapshot at all — nothing is captured, so nothing
//     can fail to reach a client afterwards. The exemption self-revokes the same way: the moment the registration
//     gains a Produce/HydrationApply pair it stops matching and the ratchet re-arms.
//
// A NEW FCk_RepData_* type that matches none of these fails this test — forcing an explicit decision
// (cover it, or document why it is exempt) instead of silently shipping a feature whose replicated
// values vanish on the client after an MP reload. The registration shapes this test probes
// (Register_SaveOnly / Register_NetOnly and their net-and-save siblings) are documented in
// CkFoundation/Source/CkSnapshot/Claude.md, "Authoring a persistence handler".
//
// When you add restore coverage for a feature, MOVE its suffix from Get_Deferred() to Get_Covered().

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

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
            TEXT("Inventory_DataOnly_Items"),
            TEXT("StateMachine_NoHistory"),
            TEXT("StateMachine_WithHistory"),
            TEXT("Inventory_Spatial_Items"),
            TEXT("2dGridPlacements"),
            TEXT("RenderTarget"),
            TEXT("EntityCollections"),
        };
        return Covered;
    }

    // suffix -> reason. Every uncovered FCk_RepData_* MUST appear here with a documented reason.
    //
    // Rows are drift-guarded below: a suffix here must still resolve to a live reflected type. The
    // first thing that guard caught was a "Container" row whose own reason hedged "N/A if it
    // reflects at all" — it never did. TFragment_ContainerEntryRef<T> is a fragment template alias,
    // not a RepData payload, so there was never an FCk_RepData_Container to defer. It sat here
    // documenting a decision about nothing, and the covered-only guard could not see it.
    static auto Get_Deferred() -> const TMap<FString, FString>&
    {
        static const TMap<FString, FString> Deferred = {
            { TEXT("MontagePlayer"),            TEXT("registry Produce/HydrationApply round-trip is covered by Ck.Snapshot.V3.MontagePlayer.HandlerRoundTrip, but no MP playback parity gate exists yet — it needs a skeletal-mesh probe + montage asset; live mesh re-bind remains an explicit post-restore integration responsibility") },
            { TEXT("Velocity"),                 TEXT("snapshot + ReplicateOnRestore wiring present (mirrors Acceleration) but no parity gate yet — a strict-value gate needs a movement-driven probe (PredictedVelocity re-derives the value on stationary actors)") },
            { TEXT("Location"),                 TEXT("audit complete 2026-06-10: transform fragment IS snapshotted; actor-backed entities re-derive client position from the respawned replicated actor (asserted by Ck.Snapshot.M2b2b gate); only pure-ECS SceneNode replication (no actor) lacks a restore re-push — defer until that configuration has a real use") },
            { TEXT("Rotation"),                 TEXT("audit complete 2026-06-10: same as Location — actor-backed re-derives (M2b2b gate); pure-ECS SceneNode rep deferred until a real use") },
            { TEXT("Scale"),                    TEXT("audit complete 2026-06-10: same as Location — actor-backed re-derives (M2b2b gate); pure-ECS SceneNode rep deferred until a real use") },
            { TEXT("GeometryCollectionOwner"),  TEXT("Lead decision 2026-06-10: ephemeral destruction state, does NOT persist — permanently deferred") },
            { TEXT("VoiceChat_ChannelEntry"),   TEXT("not a container — the element type of FCk_RepData_VoiceChat::_Channels, name-matched only because it inherits its owner's RepData_ prefix. The owning container is Register_NetOnly (CkVoiceChat_Replication.cpp), so there is no snapshot to restore from; and it never sits on an entity, so a NetApply registration to silence this would be fiction") },
            { TEXT("VoiceChat_Member"),         TEXT("not a container — a value type nested in a ChannelEntry's _Members array; same case as VoiceChat_ChannelEntry. Voice is runtime net state and is never saved (CkVoiceChat_RepData.h)") },
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
    auto SaveOnlyCount = 0;
    auto NetOnlyCount  = 0;

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

        // Registry-verified save-only participation. Only a WELL-FORMED save-only handler qualifies
        // (Produce + HydrationApply present, NetApply absent) — a degenerate registration (e.g. the
        // Produce-without-HydrationApply misconfig, which registers anyway behind a loud ensure) falls
        // through to the ratchet error below. Find() is per-type only: the runtime-typed fallback
        // handler never masks an unregistered type here.
        const auto* Handler = FCk_PersistenceHandlerRegistry::Find(*It);
        const auto IsRegisteredSaveOnly = Handler != nullptr &&
            NOT static_cast<bool>(Handler->NetApply) &&
            static_cast<bool>(Handler->Produce) &&
            static_cast<bool>(Handler->HydrationApply);

        if (IsRegisteredSaveOnly)
        {
            ++SaveOnlyCount;
            AddInfo(FString::Printf(
                TEXT("SAVE-ONLY RepData [%s]: never rides a replicated container (registry-verified) — ")
                TEXT("restore-replication N/A; ratchet re-arms if it gains net participation"),
                *Suffix));
            continue;
        }

        // The symmetric arm. Restore-replication is a question about values a load PUT BACK, and a net-only type
        // never enters a snapshot in the first place — nothing is captured, so nothing can fail to reach a client
        // afterwards. Registry-verified for the same reason as above: the registration IS the decision, and the
        // exemption self-revokes the instant the type gains save participation.
        const auto IsRegisteredNetOnly = Handler != nullptr &&
            static_cast<bool>(Handler->NetApply) &&
            NOT static_cast<bool>(Handler->Produce) &&
            NOT static_cast<bool>(Handler->HydrationApply);

        if (IsRegisteredNetOnly)
        {
            ++NetOnlyCount;
            AddInfo(FString::Printf(
                TEXT("NET-ONLY RepData [%s]: never enters a snapshot (registry-verified) — ")
                TEXT("restore-replication N/A; ratchet re-arms if it gains save participation"),
                *Suffix));
            continue;
        }

        // The ratchet: a new replicated container with NO coverage decision.
        AddError(FString::Printf(
            TEXT("Replicated container [%s] (reflected [%s]) has NO restore-replication coverage decision. ")
            TEXT("After a server snapshot load + seamless travel its replicated VALUES will silently fail to reach ")
            TEXT("clients. Either add a ReplicateOnRestore handler (then add its suffix to Get_Covered() in this ")
            TEXT("test), or document why it is exempt (add it to Get_Deferred() with a reason). If the type ")
            TEXT("genuinely never replicates, register it via Register_SaveOnly; if it genuinely never enters a ")
            TEXT("snapshot, register it via Register_NetOnly — this test detects either from the registry. The ")
            TEXT("registration shapes are documented in CkFoundation/Source/CkSnapshot/Claude.md, \"Authoring a ")
            TEXT("persistence handler\"."),
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

    // The same guard on the DEFERRED half, which it was missing. Walking only Get_Covered() left the debt
    // list unpoliced: a deferred type that is renamed or deleted stops matching, its row is never consulted
    // again, and the map keeps a documented "reason" for a type that no longer exists — a ratchet that
    // silently accumulates fiction is worse than no ratchet, because the reason text still reads as a live
    // decision. Mirrors the FragmentPostureCoverage ratchet's allow-list guard.
    for (const auto& DeferredEntry : Deferred)
    {
        TestTrue(
            FString::Printf(TEXT("Deferred RepData [%s] still exists (not renamed/removed) — drop the row and its ")
                TEXT("reason if the type is gone, or repoint it at the new name"), *DeferredEntry.Key),
            Discovered.Contains(DeferredEntry.Key));
    }

    // The two row sets must stay disjoint. A suffix in BOTH resolves as Covered (the Covered arm returns
    // first), so its Deferred row — and the reason a reader would act on — rots unreachable: exactly the
    // "debt already paid, list never updated" state the drift guards exist to prevent.
    for (const auto& DeferredEntry : Deferred)
    {
        TestFalse(
            FString::Printf(TEXT("Deferred RepData [%s] is not ALSO in Get_Covered() — a covered type's deferral ")
                TEXT("reason is unreachable and stale; delete the Get_Deferred() row"), *DeferredEntry.Key),
            Covered.Contains(DeferredEntry.Key));
    }

    AddInfo(FString::Printf(
        TEXT("RepData restore-coverage: discovered=[%d] covered=[%d] deferred=[%d] saveonly=[%d] netonly=[%d]"),
        Discovered.Num(), CoveredCount, DeferredCount, SaveOnlyCount, NetOnlyCount));

    // T-C1-7 — every registration's DECLARED posture must agree with what its lambda set actually does. The two
    // are independent statements about the same registration: the declaration is what an author claims, the lambda
    // set is what the runtime will do, and a reader is entitled to trust either one. The named registration shapes
    // enforce this at compile/registration time; asserting it here is what catches a registration that went in
    // through the raw primitives, which take a plain aggregate and cannot be compile-enforced.
    for (const auto* Registered : FCk_PersistenceHandlerRegistry::Get_RegisteredTypes())
    {
        const auto* Handler = FCk_PersistenceHandlerRegistry::Find(Registered);
        if (Handler == nullptr)
        { continue; }

        const auto ParticipatesInSave = static_cast<bool>(Handler->Produce) && static_cast<bool>(Handler->HydrationApply);
        const auto Expected = ParticipatesInSave ? ECk_Snapshot_Posture::Durable : ECk_Snapshot_Posture::Session;

        TestEqual(
            FString::Printf(TEXT("registered payload [%s] declares the posture its lambda set implies (Produce=[%d] ")
                TEXT("HydrationApply=[%d] NetApply=[%d])"),
                *Registered->GetName(), static_cast<bool>(Handler->Produce) ? 1 : 0,
                static_cast<bool>(Handler->HydrationApply) ? 1 : 0, static_cast<bool>(Handler->NetApply) ? 1 : 0),
            static_cast<int32>(Handler->Posture), static_cast<int32>(Expected));
    }

    // Sanity: we expect a non-trivial number of replicated containers to exist; 0 means the match/enumeration broke.
    TestTrue(TEXT("Discovered at least the 3 covered attribute containers"), Discovered.Num() >= 3);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
