// Lifetime-inversion characterization tests for the generational-handle
// migration. These reproduce the "UObject's handle field outlives the
// registry" failure mode at both layers of the migration:
//
//   * Slot-table layer: a handle whose registry pointer has been Free'd
//     resolves to nullptr, never a dangling pointer or a crash.
//   * FCk_Handle layer: a UObject UPROPERTY of type FCk_Handle whose registry
//     was Free'd before the holder is GC'd cleans up safely. This is the
//     load-bearing migration property — the original bug was the dtor of a
//     dangling FCk_Handle decrementing a freed TSharedPtr control block.
//   * Phoenix-singleton: Free() called after the slot-table's static state
//     has been "dead-flipped" is a silent no-op.
//
// Surface in Session Frontend: Ck.Registry.LifetimeInversion.<scenario>

#include "Misc/AutomationTest.h"

#include "CkEcs/Handle/CkHandle.h"
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
    Holder->SlotHandle = SlotHandle;

    TestTrue(TEXT("Slot resolves before registry teardown"),
        Resolve(Holder->SlotHandle) == OwnedRegistry);

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
        TryResolve(Holder->SlotHandle));

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
    FCkRegistry_LifetimeInversion_FCkHandleSurvivesRegistry,
    "Ck.Registry.LifetimeInversion.FCkHandleSurvivesRegistry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_LifetimeInversion_FCkHandleSurvivesRegistry::RunTest(const FString& Parameters)
{
    using namespace ck::registry_table;

    // The load-bearing migration test: a UObject UPROPERTY of type FCk_Handle
    // whose registry has been Free'd before the holder is GC'd MUST clean up
    // without dereferencing freed memory. Pre-migration this is exactly the
    // crash the migration was built to fix.

    // 1. Allocate a registry slot.
    auto* OwnedRegistry = new EnttRegistryType{};
    auto SlotHandle = Allocate(OwnedRegistry);

    // 2. Create a real entity in the registry so the FCk_Handle has a valid
    //    backing entity (not just a slot reference).
    const auto Entity = FCk_Entity{OwnedRegistry->create()};

    // 3. Build the FCk_Handle and store it on the UObject UPROPERTY. AddToRoot
    //    keeps the holder alive past the registry teardown so we can drive
    //    the GC ordering manually.
    auto* Holder = NewObject<UCk_LifetimeInversion_Holder>();
    Holder->AddToRoot();
    Holder->Handle = FCk_Handle{Entity, SlotHandle};

    TestTrue(TEXT("Handle's slot resolves before registry teardown"),
        Resolve(Holder->Handle.Get_RegistryView().Get_RegistryHandle()) == OwnedRegistry);

    // 4. Tear down the registry — Free first, then delete. Mirrors the
    //    UCk_EcsWorld_Subsystem_UE::Deinitialize order.
    Free(SlotHandle);
    delete OwnedRegistry;
    OwnedRegistry = nullptr;

    // 5. Force GC on the Holder. The UPROPERTY FCk_Handle dtor runs as part
    //    of UObject teardown. With the migration in place this is safe — the
    //    dtor only decrements TWeakObjectPtr's (GC-safe) and copies a 12-byte
    //    POD slot handle; the slot itself is already Free'd and the entt
    //    registry is gone. Pre-migration this would have decremented a freed
    //    TSharedPtr<entt::basic_registry> control block — the original crash.
    Holder->RemoveFromRoot();
    Holder = nullptr;
    CollectGarbage(RF_NoFlags, true);

    // If we get here without crashing, the FCk_Handle dtor is GC-safe over
    // a freed registry. That is the migration's load-bearing claim.
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
