// Phase 5B.0 unit tests for the HandleWalk FInstancedStruct recursion. ck::snapshot::ForEachHandle (the visit-only
// arm of the shared remap walker) must recurse INTO a TArray<FInstancedStruct> and reach handle fields nested in the
// stored struct -- the payload shape dynamic fragments ride (FCk_SaveData_DynamicFragments). Before the fix, the walk
// treated an FInstancedStruct as opaque, so those handles were neither remapped on save nor rehashed on load.

#include "CkEcs/Snapshot/CkSnapshot_HandleWalk.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Validation/CkIsValid.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_HandleWalk_InstancedStructNested_Test,
    "Ck.Snapshot.V3.HandleWalk.InstancedStructNested",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_HandleWalk_InstancedStructNested_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();

    // Two real entities so the nested handles carry distinct, non-null ids.
    auto EntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto EntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    const auto IdA = static_cast<uint32>(EntityA.Get_Entity().Get_ID());
    const auto IdB = static_cast<uint32>(EntityB.Get_Entity().Get_ID());

    // A dynamic-fragment-shaped payload: a single-handle field + a handle-array field, wrapped in an FInstancedStruct
    // inside a TArray<FInstancedStruct> -- exactly the G2 save shape.
    auto Frag = FCk_Test_DynFrag_WithHandle{};
    Frag.Marker = 11;
    Frag.TargetHandle = EntityA;
    Frag.TargetArray = { EntityB };

    auto Wrapper = FCk_Test_InstancedStructArrayWrapper{};
    Wrapper.Payloads.Add(FInstancedStruct::Make(Frag));

    auto SeenIds = TArray<uint32>{};
    ck::snapshot::ForEachHandle(FCk_Test_InstancedStructArrayWrapper::StaticStruct(), &Wrapper,
        [&](FCk_Handle& InHandle) -> void
        {
            SeenIds.Add(static_cast<uint32>(InHandle.Get_Entity().Get_ID()));
        });

    // The core assertion: BOTH nested handles (the single field and the array element) were reached THROUGH the
    // FInstancedStruct. Pre-fix this array would be empty -- the instanced struct was opaque to the walk.
    TestEqual(TEXT("Visited exactly the two nested handles"), SeenIds.Num(), 2);
    TestTrue(TEXT("Single-field handle (EntityA) was visited"), SeenIds.Contains(IdA));
    TestTrue(TEXT("Array-element handle (EntityB) was visited"), SeenIds.Contains(IdB));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_HandleWalk_TombstoneUntouched_Test,
    "Ck.Snapshot.V3.HandleWalk.TombstoneUntouched",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_HandleWalk_TombstoneUntouched_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // A tombstone (entt::null) handle nested in an FInstancedStruct: the walk must still VISIT it (so a raw id is
    // read/written positionally on both save and load, keeping the handle-id stream aligned) and must leave it
    // invalid -- a dangling ref stays dangling, never coincidentally rewritten.
    auto Frag = FCk_Test_DynFrag_WithHandle{};
    Frag.Marker = 5;
    Frag.TargetHandle = FCk_Handle{}; // default-constructed -> entt::null entity (TargetArray left empty)

    auto Wrapper = FCk_Test_InstancedStructArrayWrapper{};
    Wrapper.Payloads.Add(FInstancedStruct::Make(Frag));

    auto VisitCount = 0;
    auto AllInvalid = true;
    ck::snapshot::ForEachHandle(FCk_Test_InstancedStructArrayWrapper::StaticStruct(), &Wrapper,
        [&](FCk_Handle& InHandle) -> void
        {
            ++VisitCount;
            AllInvalid = AllInvalid && ck::Is_NOT_Valid(InHandle);
        });

    TestEqual(TEXT("The tombstone handle was visited exactly once"), VisitCount, 1);
    TestTrue(TEXT("The visited tombstone stayed invalid (untouched)"), AllInvalid);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
