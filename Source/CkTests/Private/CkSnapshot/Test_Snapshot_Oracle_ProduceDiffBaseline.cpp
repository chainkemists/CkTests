// Fidelity-oracle Tier-2 harness (spec §5, campaign Phase 1 §1.6).
//
// Proves the Produce-diff oracle sees a single-value mutation as exactly one changed payload line and an unmutated
// capture as zero. Exercises the REAL registered Velocity Produce handler (not a test-local fragment): per [P1-D2],
// the Attribute Produce is empty-seed and would never register a value change, so a value-emitting feature is
// required. Velocity's Add creates FFragment_Velocity_Current immediately and Request_OverrideVelocity is an
// immediate write, so no processor tick is needed in this bare FEcsWorld.
//
// Mirrors Test_Snapshot_Oracle_StructuralBaseline.cpp's standalone-FEcsWorld setup.

#include "CkEcs/Snapshot/CkSnapshot_FidelityOracle.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkPhysics/Velocity/CkVelocity_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS && CK_WITH_FIDELITY_ORACLE

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Oracle_ProduceDiffBaseline_Test,
    "Ck.Snapshot.Oracle.ProduceDiffBaseline",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Oracle_ProduceDiffBaseline_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto StartingVelocity = FVector{100.0, 0.0, 0.0};
    const auto MutatedVelocity  = FVector{250.0, -50.0, 0.0};

    // ---- Arrange: a private ECS world with one Velocity-carrying entity ----------------------------------------
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    auto* RawRegistry = ck::registry_table::TryResolve(RegistryHandle);
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    if (NOT TestTrue(TEXT("Entity valid"), ck::IsValid(Entity)))
    { return false; }

    // DoesNotReplicate: no net driver exists in a bare FEcsWorld, and Produce reads live Current directly.
    auto VelocityHandle = UCk_Utils_Velocity_UE::Add(
        Entity,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, StartingVelocity},
        ECk_Replication::DoesNotReplicate);

    if (NOT TestTrue(TEXT("Velocity feature added"), ck::IsValid(VelocityHandle)))
    { return false; }

    // ---- Capture BEFORE (StartingVelocity) ---------------------------------------------------------------------
    const auto Before = ck::snapshot_oracle::Capture_Payloads(*RawRegistry, RegistryHandle);

    // Sanity: the REAL Velocity Produce handler emitted a payload for our entity (proves Get_ProduceHandlerTypes
    // discovered the registered handler and the oracle ran it).
    auto FoundVelocityPayload = false;
    for (const auto& Pair : Before)
    {
        for (const auto& TypePayload : Pair.Value)
        {
            if (TypePayload.Key.Contains(TEXT("Velocity")))
            { FoundVelocityPayload = true; }
        }
    }
    TestTrue(TEXT("Before image contains a Velocity Produce payload"), FoundVelocityPayload);

    // Unmutated case: an image diffs against itself in zero lines.
    TestEqual(TEXT("Diff of an image against itself is empty"),
        ck::snapshot_oracle::Diff_Payloads(Before, Before).Num(), 0);

    // ---- Mutate one value (immediate write) + capture AFTER (MutatedVelocity) -----------------------------------
    UCk_Utils_Velocity_UE::Request_OverrideVelocity(VelocityHandle, MutatedVelocity);

    const auto After = ck::snapshot_oracle::Capture_Payloads(*RawRegistry, RegistryHandle);

    const auto Diff = ck::snapshot_oracle::Diff_Payloads(Before, After);
    for (const auto& Line : Diff)
    { AddInfo(FString::Printf(TEXT("Produce diff line: %s"), *Line)); }

    return TestEqual(TEXT("Exactly one Produce payload changed after mutating velocity"), Diff.Num(), 1);
}

#endif // WITH_DEV_AUTOMATION_TESTS && CK_WITH_FIDELITY_ORACLE

// --------------------------------------------------------------------------------------------------------------------
