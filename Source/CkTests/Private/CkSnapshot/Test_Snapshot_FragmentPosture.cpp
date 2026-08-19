// T-C1-2/3/5/6/9 — these five tests pin ck::Get_FragmentPosture's resolution rules. They are pure resolver tests: no world, no save, no load — the resolver is a function of a
// reflected type, and keeping the coverage at that level is what makes each rule's regression name itself.
//
// The property under test is NOT "the right answer" but "no rule can silently drop durable data":
//   - a DECLARATION never overrides a DERIVATION (a derivation proves the declared posture is unachievable),
//   - a derived-Session shape that also carries value fields resolves Undeclared + "split me", never Session,
//   - a contradiction resolves Undeclared and ENSURES.
// The two named real-world instances behind the third rule are int32 SwingWhiffs
// (FBb_Fragment_WhackAGull_Requests) and int32 MaxCapacityDelta (FBb_Fragment_Occupancy_Requests): both live
// inside fragments whose name matches the request-queue shape, and a silent derive would have deleted them.
//
// T-C1-4 is the exception and drives the real handler: a resolution alone would not prove that the tag derivation
// reaches capture, which is the whole point of the rule.

#include "CkCore/Ensure/CkEnsure_Utils.h" // Get_EnsureCount — the enforceable "it ensured" assertion
#include "CkCore/Macros/CkMacros.h"

#include "CkDynamic/CkDynamic_Fragment_Data.h" // FCk_SaveData_DynamicFragments
#include "CkDynamic/CkDynamic_Utils.h"         // UCk_Utils_DynamicFragment_UE + ECk_Replication (transitive)

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/ReplicatedFragmentContainer/CkReplicatedFragmentContainer.h" // ECk_Persistence_ApplyResult
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_Posture.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_fragment_posture_test
{
    // One resolution, reported with its reason so a failure says WHY the resolver disagreed rather than only that
    // it did. Ck ensures reach two log sinks, so tests that expect one use AddExpectedError(..., Occurrences=0)
    // for suppression and the ensure COUNT for exactness (the T-C4-3 idiom).
    auto Expect_Posture(
        FAutomationTestBase& InTest,
        const UScriptStruct* InType,
        ECk_Snapshot_Posture InExpected,
        const FString& InWhat) -> ck::FCk_Snapshot_PostureResolution
    {
        const auto Resolution = ck::Resolve_FragmentPosture(InType);

        InTest.TestEqual(
            FString::Printf(TEXT("%s — resolved posture (reason: [%s])"), *InWhat, *Resolution.Reason),
            static_cast<int32>(Resolution.Posture),
            static_cast<int32>(InExpected));

        return Resolution;
    }
}

// --------------------------------------------------------------------------------------------------------------------
// T-C1-2
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Posture_DurableWithDelegate_IsRed_Test,
    "Ck.Snapshot.Posture.DurableWithDelegate_IsRed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Posture_DurableWithDelegate_IsRed_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_test;

    AddExpectedError(TEXT("declares FCk_Snapshot_Durable, but"), EAutomationExpectedErrorFlags::Contains,
        /*Occurrences=*/0);

    const auto EnsureCountBefore = UCk_Utils_Ensure_UE::Get_EnsureCount();

    Expect_Posture(*this, FCk_Test_Posture_DurableWithDelegate::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("Durable + a top-level delegate"));

    // The recursive walk is the point: a top-level-only check — which is what the deleted hydration guard was —
    // would pass this one and lose the delegate on load.
    Expect_Posture(*this, FCk_Test_Posture_DurableWithNestedDelegate::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("Durable + a delegate inside an array of carriers"));

    TestEqual(TEXT("each contradicted Durable declaration ensured exactly once"),
        UCk_Utils_Ensure_UE::Get_EnsureCount(), EnsureCountBefore + 2);

    // A Durable declaration with no session content must still resolve Durable, or this test would pass for the
    // trivial reason that nothing resolves Durable at all.
    Expect_Posture(*this, FCk_Test_Posture_PlainDurable::StaticStruct(),
        ECk_Snapshot_Posture::Durable, TEXT("Durable over plain values and a handle"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// T-C1-3
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Posture_RequestNamedDerivesSession_Test,
    "Ck.Snapshot.Posture.RequestNamedDerivesSession",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Posture_RequestNamedDerivesSession_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_test;

    // The AngelScript arm. It is what makes this test non-vacuous: an inheritance-only rule classifies NOTHING in
    // a script codebase (measured: zero AS structs inherit, zero name FCk_Request_Base), so the 59-of-78 captured
    // "*Requests" fragments would have stayed captured while the design's arithmetic counted them as fixed.
    Expect_Posture(*this, FCk_Test_Posture_ProbeRequests::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("a '...Requests' fragment of AS-named request payloads"));

    // The C++ arm: no name convention to lean on, only the type test.
    Expect_Posture(*this, FCk_Test_Posture_CppQueue::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("a queue of FCk_Request_Base-derived payloads"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// T-C1-5
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Posture_ContradictionIsRed_Test,
    "Ck.Snapshot.Posture.ContradictionIsRed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Posture_ContradictionIsRed_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_test;

    AddExpectedError(TEXT("declares BOTH"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    const auto EnsureCountBefore = UCk_Utils_Ensure_UE::Get_EnsureCount();

    // Neither marker wins — including not the Session one, which would be the tempting "safe" default and is
    // exactly how a declaration-over-derivation override would sneak back in.
    Expect_Posture(*this, FCk_Test_Posture_Contradiction::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("both posture markers on one fragment"));

    TestEqual(TEXT("the contradiction ensured exactly once"),
        UCk_Utils_Ensure_UE::Get_EnsureCount(), EnsureCountBefore + 1);

    Expect_Posture(*this, FCk_Test_Posture_PlainSession::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("a lone Session declaration"));

    // The DEPRECATED spelling, both ways it appears in production: derived (C++) and carried as a field
    // (AngelScript). ~188 script sites still use it, so a resolver that stopped recognising it would silently start
    // capturing every fragment that opted out through the old spelling.
    Expect_Posture(*this, FCk_Test_Posture_LegacyMarkerField::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("the legacy SnapshotTransient marker as a field"));

    Expect_Posture(*this, FCk_Test_DynFrag_SnapshotTransient::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("the legacy SnapshotTransient marker by derivation"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// T-C1-6
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Posture_TransientFieldOnDurable_IsRed_Test,
    "Ck.Snapshot.Posture.TransientFieldOnDurable_IsRed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Posture_TransientFieldOnDurable_IsRed_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_test;

    // No parentheses in the pattern: AddExpectedError compiles it as a REGEX, so "UPROPERTY(Transient)" would
    // match a capture group instead of the literal text and the suppression would silently miss.
    AddExpectedError(TEXT("opt-out is retired"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    const auto EnsureCountBefore = UCk_Utils_Ensure_UE::Get_EnsureCount();

    const auto Resolution = Expect_Posture(*this, FCk_Test_Posture_DurableWithTransientField::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("Durable + a UPROPERTY(Transient) game field"));

    TestEqual(TEXT("the retired field-level opt-out ensured exactly once"),
        UCk_Utils_Ensure_UE::Get_EnsureCount(), EnsureCountBefore + 1);

    TestTrue(TEXT("...and the reason names the offending field, so the split is actionable"),
        Resolution.Reason.Contains(TEXT("RuntimeMarker")));

    TestTrue(TEXT("...and the resolution is flagged as needing a split"), Resolution.RequiresSplit);

    // Rule 5 is still reachable and still resolves Undeclared rather than guessing: a fragment that declares
    // nothing and matches no derivation is captured whole, so no data is dropped while the ratchet reds it.
    Expect_Posture(*this, FCk_Test_DynFrag_WithHandle::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("a fragment declaring no posture and matching no derivation"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// T-C1-9
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Posture_DerivedMixedIsRedNotSession_Test,
    "Ck.Snapshot.Posture.DerivedMixedIsRedNotSession",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Posture_DerivedMixedIsRedNotSession_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_test;

    // Undeclared, NOT Session: Undeclared is the captured-and-guarded path, so the accumulator survives while the
    // red is open. Session would have silently stopped capturing it — the data-loss bug this rule exists to
    // prevent. No ensure here on purpose: a derived mixed shape is a work-list item the ratchet reds, and 46 BB
    // fragments match it today, so ensuring would storm every capture instead of naming the debt once.
    const auto MixedRequests = Expect_Posture(*this, FCk_Test_Posture_MixedRequests::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("a '...Requests' queue that also carries an accumulator"));

    const auto MixedDelegate = Expect_Posture(*this, FCk_Test_Posture_MixedDelegate::StaticStruct(),
        ECk_Snapshot_Posture::Undeclared, TEXT("a delegate carrier that also carries a durable counter"));

    TestTrue(TEXT("the mixed request queue is flagged for a split"), MixedRequests.RequiresSplit);
    TestTrue(TEXT("the mixed delegate carrier is flagged for a split"), MixedDelegate.RequiresSplit);

    TestTrue(TEXT("the request-queue reason says SPLIT ME and names the value field"),
        MixedRequests.Reason.Contains(TEXT("SPLIT ME")) && MixedRequests.Reason.Contains(TEXT("Accumulator")));

    TestTrue(TEXT("the delegate reason says SPLIT ME and names the value field"),
        MixedDelegate.Reason.Contains(TEXT("SPLIT ME")) && MixedDelegate.Reason.Contains(TEXT("Accumulator")));

    // The pure forms of the same two shapes stay Session — the mixed rule must be a discriminator, not a blanket.
    Expect_Posture(*this, FCk_Test_Posture_ProbeRequests::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("the same queue shape with no value field"));

    Expect_Posture(*this, FCk_Test_Posture_DelegateCarrier::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("the same delegate shape with no value field"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// T-C1-4
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Posture_TagStructDerivesSession_Test,
    "Ck.Snapshot.Posture.TagStructDerivesSession",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Posture_TagStructDerivesSession_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_fragment_posture_test;

    Expect_Posture(*this, FCk_Test_Posture_BareTag::StaticStruct(),
        ECk_Snapshot_Posture::Session, TEXT("a field-less fragment carrying no marker"));

    // The capture half runs on a SCRIPT-declared tag: a native zero-reflection struct cannot enter dynamic storage
    // at all (the schema gate fails closed on it), so a script tag is not a convenience here — it is the only shape
    // a tag ever has in a real world, and the one the rule was measured against.
    const auto* TagType = FindObject<UScriptStruct>(
        nullptr, TEXT("/Script/Angelscript.Ck_Fragment_DynamicTest_TagPayload"));

    if (NOT TestNotNull(TEXT("the script-declared tag fixture is loaded"), TagType))
    { return false; }

    Expect_Posture(*this, TagType, ECk_Snapshot_Posture::Session, TEXT("a script-declared field-less tag"));

    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);

    // A durable neighbour on the same entity, so "Produce emitted nothing at all" cannot masquerade as
    // "Produce omitted the tag".
    auto PureData = FCk_Test_DynFrag_PureData{};
    PureData.Count = 3;
    UCk_Utils_DynamicFragment_UE::Add_Fragment(
        Owner, FInstancedStruct::Make(PureData), ECk_Replication::DoesNotReplicate);

    UCk_Utils_DynamicFragment_UE::Add_Fragment(
        Owner, FInstancedStruct{TagType}, ECk_Replication::DoesNotReplicate);

    if (NOT TestTrue(TEXT("the tag is composed on the entity before the capture"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(Owner, TagType)))
    { return false; }

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_SaveData_DynamicFragments::StaticStruct());
    if (NOT TestNotNull(TEXT("the dynamic-fragments handler is registered"), Handler))
    { return false; }

    const auto Produced = Handler->Produce(Owner);
    if (NOT TestTrue(TEXT("Produce emitted a payload for the owner"), Produced.IsSet()))
    { return false; }

    const auto& SaveData = Produced.GetValue().Get<FCk_SaveData_DynamicFragments>();

    const auto Contains = [&SaveData](const UScriptStruct* InType) -> bool
    {
        return SaveData.Get_Fragments().ContainsByPredicate([InType](const FInstancedStruct& InEntry) -> bool
        { return InEntry.GetScriptStruct() == InType; });
    };

    TestFalse(TEXT("Produce omitted the derived-Session tag — a tag marks processing state, and a saved one comes "
        "back to re-drive whatever already consumed it"), Contains(TagType));

    TestTrue(TEXT("...while the durable neighbour on the same entity WAS captured"),
        Contains(FCk_Test_DynFrag_PureData::StaticStruct()));

    // Hydration must not re-add one either. The payload is hand-built with the tag entry present, because a capture
    // that correctly omits it can no longer exercise the apply-side skip.
    auto TaggedPayload = FCk_SaveData_DynamicFragments{};
    {
        auto Entries = SaveData.Get_Fragments();
        Entries.Add(FInstancedStruct{TagType});
        TaggedPayload.Set_Fragments(MoveTemp(Entries));
    }

    auto Rebuilt = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    UCk_Utils_DynamicFragment_UE::Add_Fragment(
        Rebuilt, FInstancedStruct{TagType}, ECk_Replication::DoesNotReplicate);

    auto RebuiltRef = Rebuilt;
    const auto ApplyResult = Handler->HydrationApply(RebuiltRef, FInstancedStruct::Make(TaggedPayload), {});
    TestEqual(TEXT("hydration applied"),
        static_cast<int32>(ApplyResult), static_cast<int32>(ECk_Persistence_ApplyResult::Applied));

    TestTrue(TEXT("the construct-stamped tag is still present after hydration"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(Rebuilt, TagType));

    // ...and it is not COMPOSED onto an entity whose construction did not stamp it, which is the half a
    // rebuilt-entity-already-carries-it assertion cannot see.
    auto Bare = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto BareRef = Bare;
    Handler->HydrationApply(BareRef, FInstancedStruct::Make(TaggedPayload), {});

    TestFalse(TEXT("hydration did not compose the derived-Session tag onto an entity that lacked it"),
        UCk_Utils_DynamicFragment_UE::Has_Fragment(Bare, TagType));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
