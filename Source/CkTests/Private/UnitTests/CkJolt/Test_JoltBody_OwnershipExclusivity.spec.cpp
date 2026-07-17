#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkEcsExt/PhysicsOwnership/CkPhysicsOwnership_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Utils.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the cross-engine ownership contract at the JoltBody composition site: a Chaos-simulated entity
// (OverlapBody Marker / RaySense) and a Jolt-simulated entity are mutually exclusive. Adding a JoltBody onto a
// Chaos-claimed entity must ENSURE at the composing call site and return an INVALID handle (a construction
// failure, not a silent warning); the mirror — claiming Chaos on a Jolt-claimed entity — must likewise ENSURE.
//
// Hermetic (private ck::FEcsWorld, no PIE): the ensure fires synchronously inside Add / TryClaim, so it needs
// only the entity's ownership tags + the Transform feature JoltBody::Add requires. The Chaos claim is set via
// the same ck::physics_ownership primitive an OverlapBody Marker calls internally
// (CkMarker_Utils.cpp:28 -> TryClaim_Chaos), so the entity state under test is identical without dragging in a
// UWorld + owning actor + Chaos scene. See DEVIATION note in the campaign return.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_ownership
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter;

    static auto Make_DynamicBoxParams() -> FCk_Fragment_JoltBody_ParamsData
    {
        auto Params = FCk_Fragment_JoltBody_ParamsData{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        return Params;
    }

    // Creates a bare entity with the Transform feature JoltBody::Add requires. Non-replicating so Transform::Add
    // is world-free (no net-container fragments, no owning-actor attach).
    static auto Make_TransformedEntity(ck::FEcsWorld& InWorld) -> FCk_Handle
    {
        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry());
        UCk_Utils_Transform_UE::Add(Entity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        return Entity;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_OwnershipExclusivity_ChaosClaimBlocksJoltAdd,
    "Ck.Jolt.Body.OwnershipExclusivity.ChaosClaimBlocksJoltAdd",
    ck_test_jolt_ownership::kTestFlags)

bool FCkTest_JoltBody_OwnershipExclusivity_ChaosClaimBlocksJoltAdd::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_ownership;

    auto World = ck::FEcsWorld{};
    auto Entity = Make_TransformedEntity(World);

    // Claim Chaos first (what an OverlapBody Marker / RaySense does at its own composing site).
    TestTrue(TEXT("Chaos claim succeeds on a fresh entity"), ck::physics_ownership::TryClaim_Chaos(Entity));

    // One ensure fire emits a log entry + an Error line, both carrying the message — whitelist by substring
    // without enforcing a count (mirrors Ck.Registry.SlotTable.UnsetHandleContract).
    AddExpectedError(TEXT("already CHAOS-simulated"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    const auto Body = UCk_Utils_JoltBody_UE::Add(Entity, Make_DynamicBoxParams());

    TestTrue(TEXT("JoltBody Add onto a Chaos-claimed entity returns an INVALID handle"), ck::Is_NOT_Valid(Body));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_OwnershipExclusivity_JoltClaimBlocksChaosAdd,
    "Ck.Jolt.Body.OwnershipExclusivity.JoltClaimBlocksChaosAdd",
    ck_test_jolt_ownership::kTestFlags)

bool FCkTest_JoltBody_OwnershipExclusivity_JoltClaimBlocksChaosAdd::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_ownership;

    auto World = ck::FEcsWorld{};
    auto Entity = Make_TransformedEntity(World);

    // JoltBody first — claims Jolt cleanly.
    const auto Body = UCk_Utils_JoltBody_UE::Add(Entity, Make_DynamicBoxParams());
    TestTrue(TEXT("JoltBody Add onto a fresh entity returns a valid handle"), ck::IsValid(Body));

    // Now the Chaos-side claim (the path every OverlapBody Marker / Sensor / RaySense funnels through) must be
    // refused with an ensure and must NOT set the Chaos tag.
    AddExpectedError(TEXT("already JOLT-simulated"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    TestFalse(TEXT("Chaos claim onto a Jolt-simulated entity is refused"),
        ck::physics_ownership::TryClaim_Chaos(Entity));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_OwnershipExclusivity_PlainEntityJoltAddSucceeds,
    "Ck.Jolt.Body.OwnershipExclusivity.PlainEntityJoltAddSucceeds",
    ck_test_jolt_ownership::kTestFlags)

bool FCkTest_JoltBody_OwnershipExclusivity_PlainEntityJoltAddSucceeds::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_ownership;

    // Positive control: no competing claim -> JoltBody Add succeeds and returns a valid handle.
    auto World = ck::FEcsWorld{};
    auto Entity = Make_TransformedEntity(World);

    const auto Body = UCk_Utils_JoltBody_UE::Add(Entity, Make_DynamicBoxParams());

    TestTrue(TEXT("JoltBody Add onto a plain (Transform-only) entity returns a valid handle"), ck::IsValid(Body));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
