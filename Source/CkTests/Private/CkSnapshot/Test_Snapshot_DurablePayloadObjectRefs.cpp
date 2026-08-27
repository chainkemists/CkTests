// The object-reference rule for a DURABLE snapshot payload, and the two narrowings it makes.
//
// A Durable payload is walked AND serialized by the capture, and it lives in an ECS fragment that UE GC never
// visits — so a hard UObject ref there roots nothing and DANGLES rather than nulling when its target dies. The
// capture then dereferences it twice over: Audit_DurableObjectRefs reads IsAsset() on it, and Serialize_OwnedStruct
// (ArIsSaveGame=false) reads GetPathName() on it from a ParallelFor worker. QA 2026-08-26 crashed on the first.
//
// The last test here is the mechanism itself, demonstrated WITHOUT a dereference: the same object held in both
// forms, collected, then observed. It is what makes the rule an observation rather than an argument.
//
// The narrowings are pinned AGAINST the analyzer's unnarrowed defaults on purpose. ck::Analyze_UntracedStructSafety
// is also what closes this hole for AngelScript fragments and EntityScript spawn params
// (ck::dynamic::Validate_FragmentSchema), so a change that relaxed its DEFAULTS to make the snapshot fence pass
// would silently widen that guard too. Each narrowing test asserts both answers.

#include "CkCore/Macros/CkMacros.h"
#include "CkCore/Validation/CkUntracedStructSafety.h"

#include "CkEcs/Snapshot/CkSnapshot_Posture.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"

#include "UObject/Package.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_durable_payload_refs_test
{
    auto Expect_Safety(
        FAutomationTestBase& InTest,
        const UScriptStruct* InType,
        const ck::FCk_UntracedStructSafety_Policy& InPolicy,
        ck::ECk_UntracedStructSafety InExpected,
        const FString& InWhat) -> void
    {
        const auto Result = ck::Analyze_UntracedStructSafety(InType, InPolicy);

        InTest.TestEqual(
            FString::Printf(TEXT("%s — safety (path: [%s], reason: [%s])"),
                *InWhat, *Result.FailurePath, *Result.FailureReason),
            static_cast<int32>(Result.Safety),
            static_cast<int32>(InExpected));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DurablePayloadRefs_HardObjectRefIsFlagged_Test,
    "Ck.Snapshot.DurablePayloadRefs.HardObjectRefIsFlagged",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DurablePayloadRefs_HardObjectRefIsFlagged_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_durable_payload_refs_test;

    const auto Policy = ck::Get_DurablePayloadObjectRefPolicy();

    Expect_Safety(*this, FCk_Test_HydrationPayloadWithObject::StaticStruct(), Policy,
        ck::ECk_UntracedStructSafety::RequiresGcTracing, TEXT("a hard TObjectPtr leaf in a durable payload"));

    Expect_Safety(*this, FCk_Test_DurablePayload_SoftRef::StaticStruct(), Policy,
        ck::ECk_UntracedStructSafety::GcIndependent, TEXT("the soft-ref form the fence directs authors to"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DurablePayloadRefs_ClassRefNarrowingIsScoped_Test,
    "Ck.Snapshot.DurablePayloadRefs.ClassRefNarrowingIsScoped",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DurablePayloadRefs_ClassRefNarrowingIsScoped_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_durable_payload_refs_test;

    Expect_Safety(*this, FCk_Test_DurablePayload_ClassRef::StaticStruct(),
        ck::Get_DurablePayloadObjectRefPolicy(),
        ck::ECk_UntracedStructSafety::GcIndependent,
        TEXT("a class ref under the durable-payload policy (the documented narrowing)"));

    Expect_Safety(*this, FCk_Test_DurablePayload_ClassRef::StaticStruct(),
        ck::FCk_UntracedStructSafety_Policy{},
        ck::ECk_UntracedStructSafety::RequiresGcTracing,
        TEXT("the same class ref under the DEFAULT policy — the AngelScript fragment guard is unweakened"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DurablePayloadRefs_TracedCarrierNarrowingIsScoped_Test,
    "Ck.Snapshot.DurablePayloadRefs.TracedCarrierNarrowingIsScoped",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DurablePayloadRefs_TracedCarrierNarrowingIsScoped_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using namespace ck_durable_payload_refs_test;

    // FCk_SaveData_DynamicFragments is exactly this shape, and its entries are schema-validated at insertion —
    // which is why the fence stops at the carrier instead of rejecting it.
    Expect_Safety(*this, FCk_Test_InstancedStructArrayWrapper::StaticStruct(),
        ck::Get_DurablePayloadObjectRefPolicy(),
        ck::ECk_UntracedStructSafety::GcIndependent,
        TEXT("an FInstancedStruct carrier under the durable-payload policy (boundary, not rejection)"));

    Expect_Safety(*this, FCk_Test_InstancedStructArrayWrapper::StaticStruct(),
        ck::FCk_UntracedStructSafety_Policy{},
        ck::ECk_UntracedStructSafety::RequiresGcTracing,
        TEXT("the same carrier under the DEFAULT policy — untraced storage still may not hold one"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DurablePayloadRefs_HardRefDanglesWhenTargetIsCollected_Test,
    "Ck.Snapshot.DurablePayloadRefs.HardRefDanglesWhenTargetIsCollected",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DurablePayloadRefs_HardRefDanglesWhenTargetIsCollected_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto* Doomed = NewObject<UCk_Test_CollectableSubject>(GetTransientPackage());

    // The two forms a fragment can hold the same object in. Neither local is GC-traced — exactly as an EnTT
    // fragment member is not — which is what makes this a faithful stand-in for the fragment case.
    auto* AsHardRef = Doomed;
    const auto AsSoftRef = TSoftObjectPtr<UObject>{Doomed};

    TestNotNull(TEXT("PRE-CONDITION: the soft ref resolves while its target is alive (without this, the "
        "post-collection assertion below would pass for an empty path rather than for a dead object)"),
        AsSoftRef.Get());

    Doomed = nullptr;
    constexpr auto FullPurge = true;
    CollectGarbage(RF_NoFlags, FullPurge);

    // POSITIVE CONTROL: this is what proves the target actually died. If it ever fails, the test below is vacuous
    // rather than passing — a harness that cannot stage the phenomenon must not report a clean result.
    TestNull(TEXT("the soft ref resolves to null once its target is collected"), AsSoftRef.Get());

    // The hazard itself, observed WITHOUT dereferencing: comparing a pointer to null does not touch the freed
    // object. The raw form kept a non-null address into freed memory — it dangled instead of nulling, and that
    // address is what the capture reads IsAsset()/GetPathName() through.
    TestNotNull(TEXT("the hard ref still holds a non-null (freed) address — it dangled rather than nulling"),
        AsHardRef);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
