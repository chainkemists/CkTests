// Lifetime-inversion characterization tests for the generational-handle
// migration. These reproduce the "UObject's handle field outlives the
// registry" failure mode at the slot-table layer.
//
// In Phase 1 the FCk_Handle dtor still uses TSharedPtr; the UObject-level
// repro for that path is deferred until FCk_Handle is migrated (Phase 2+).
// What we CAN test today (and must continue to pass after the FCk_Handle
// migration) is the underlying slot-table contract:
//
//   * A handle whose registry pointer has been Free'd resolves to nullptr,
//     never a dangling pointer or a crash.
//   * Free() called after the slot-table's static state has been "dead-
//     flipped" is a silent no-op — the phoenix-singleton invariant.
//
// Surface in Session Frontend: Ck.Registry.LifetimeInversion.<scenario>

#include "Misc/AutomationTest.h"

#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "UnitTests/CkRegistry_LifetimeInversion_Holder.h"

#include "UObject/UObjectGlobals.h"
#include "UObject/GarbageCollection.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistry_LifetimeInversion_HandleSurvivesRegistry,
    "Ck.Registry.LifetimeInversion.HandleSurvivesRegistry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_LifetimeInversion_HandleSurvivesRegistry::RunTest(const FString& Parameters)
{
    using namespace ck::registry_table;

    // 1. Allocate a registry slot — analog of UCk_EcsWorld_Subsystem_UE::Initialize.
    auto* OwnedRegistry = new EnttRegistryType{};
    auto SlotHandle = Allocate(OwnedRegistry);

    // 2. Create a UObject that holds an FCk_RegistryHandle bound to that registry.
    //    AddToRoot prevents it being GC'd before we explicitly release it.
    auto* Holder = NewObject<UCk_LifetimeInversion_Holder>();
    Holder->AddToRoot();
    Holder->_SlotHandle = SlotHandle;

    TestTrue(TEXT("Slot resolves before registry teardown"),
        Resolve(Holder->_SlotHandle) == OwnedRegistry);

    // 3. Tear down the registry — analog of UCk_EcsWorld_Subsystem_UE::Deinitialize.
    //    Slot is freed BEFORE the entt registry is deleted (matches subsystem
    //    deinit order in the production code).
    Free(SlotHandle);
    delete OwnedRegistry;
    OwnedRegistry = nullptr;

    // 4. The Holder's _SlotHandle is now dangling. Pre-migration: a TSharedPtr-
    //    based handle dtor would decrement a freed control block. Post-
    //    migration (this test): TryResolve cleanly returns nullptr — the
    //    POD bytes carry no ownership.
    TestNull(TEXT("Stale slot reports null (no crash)"),
        TryResolve(Holder->_SlotHandle));

    // 5. Force GC on the Holder. With the slot table holding a POD handle,
    //    UObject teardown is an 8-byte memcpy — a no-op. Pre-migration,
    //    ~FCk_Handle would have decremented an already-freed shared-ptr
    //    control block here.
    Holder->RemoveFromRoot();
    Holder = nullptr;
    CollectGarbage(RF_NoFlags, true);

    // If we get here without crashing, the slot-table invariant holds.
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistry_LifetimeInversion_FreeAfterTableDestruction,
    "Ck.Registry.LifetimeInversion.FreeAfterTableDestruction",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_LifetimeInversion_FreeAfterTableDestruction::RunTest(const FString& Parameters)
{
    // Smoke test for the phoenix-singleton sentinel: simulate the "Free
    // called during static destruction order" scenario by directly invoking
    // the test hook. The phoenix singleton must accept Free calls after its
    // sentinel flips and silently no-op them.
    using namespace ck::registry_table;

    auto Reg = EnttRegistryType{};
    auto H = Allocate(&Reg);
    TestTrue(TEXT("Handle resolves before sim-destruction"), Resolve(H) == &Reg);

    Debug_SimulateTableDestruction_DoNotUseInProduction();

    Free(H); // Must not crash.
    TestNull(TEXT("Resolve after sim-destruction is null"), TryResolve(H));

    // Re-arm the sentinel so subsequent tests in the same process can keep
    // allocating. The phoenix-singleton bytes were never destructed; this
    // is just flipping the flag back so production behavior (Allocate/
    // Free/Resolve all live) resumes. In the real shutdown path this is
    // never called — module shutdown is the end of life.
    Debug_ReviveTableAfterSimulatedDestruction_DoNotUseInProduction();

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
