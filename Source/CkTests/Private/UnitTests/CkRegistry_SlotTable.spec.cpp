// Unit tests for ck::registry_table — the process-lifetime slot allocator
// behind the generational-handle migration. Pure C++ tests; no PIE / world
// required. Surface in Session Frontend: Ck.Registry.SlotTable.<scenario>

#include "Misc/AutomationTest.h"

#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistrySlotTable_BasicAllocateFreeResolve,
    "Ck.Registry.SlotTable.BasicAllocateFreeResolve",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistrySlotTable_BasicAllocateFreeResolve::RunTest(const FString& Parameters)
{
    using namespace ck::registry_table;

    EnttRegistryType Reg1;
    EnttRegistryType Reg2;

    auto H1 = Allocate(&Reg1);
    auto H2 = Allocate(&Reg2);

    TestTrue(TEXT("H1 resolves"),  Resolve(H1) == &Reg1);
    TestTrue(TEXT("H2 resolves"),  Resolve(H2) == &Reg2);
    TestTrue(TEXT("H1 != H2"),     H1 != H2);

    Free(H1);
    TestTrue(TEXT("Freed H1 resolves to nullptr"), TryResolve(H1) == nullptr);
    TestTrue(TEXT("H2 still resolves"),            Resolve(H2) == &Reg2);

    auto H1Recycled = Allocate(&Reg1);
    TestTrue(TEXT("Recycled slot reused"),         H1Recycled.SlotIndex == H1.SlotIndex);
    TestTrue(TEXT("Recycled gen differs"),         H1Recycled.Generation != H1.Generation);
    TestTrue(TEXT("Stale handle still nullptr"),   TryResolve(H1) == nullptr);
    TestTrue(TEXT("Recycled handle resolves"),     Resolve(H1Recycled) == &Reg1);

    Free(H2);
    Free(H1Recycled);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistrySlotTable_UnsetHandleContract,
    "Ck.Registry.SlotTable.UnsetHandleContract",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistrySlotTable_UnsetHandleContract::RunTest(const FString& Parameters)
{
    // Contract: strict Resolve fires ensure on an unset handle. Default-
    // constructed FCk_Registry / FCk_Handle being used before it has been
    // bound to a slot is almost always a bug — pre-migration the default
    // ctor auto-allocated a private registry and hid these sites.
    //
    // TryResolve stays silent because callers like ck::IsValid use it to
    // ASK the question "is this bound yet?" — firing on unset there would
    // spam every validity check on a default-constructed handle.
    using namespace ck::registry_table;
    auto Unset = FCk_RegistryHandle::Unset();

    // Occurrences=-1: whitelist all matching messages without enforcing a count.
    // CK_ENSURE_IF_NOT emits both a log entry and an Error line for one fire,
    // which counts as 2 — match-suppression is the right semantics here.
    AddExpectedError(
        TEXT("registry_table::Resolve called with an unset handle"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    TestTrue(TEXT("Unset handle: strict Resolve fires ensure and returns nullptr"),
             Resolve(Unset) == nullptr);
    TestTrue(TEXT("Unset handle: silent TryResolve returns nullptr without firing"),
             TryResolve(Unset) == nullptr);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistrySlotTable_GenerationWrapDoesNotCollideWithSentinel,
    "Ck.Registry.SlotTable.GenerationWrapDoesNotCollideWithSentinel",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistrySlotTable_GenerationWrapDoesNotCollideWithSentinel::RunTest(const FString& Parameters)
{
    using namespace ck::registry_table;

    // Force a slot to wrap its 32-bit generation counter on the next Allocate.
    // The test hook fast-forwards the generation to the all-ones pattern so
    // the next increment wraps to 0 (the never-allocated sentinel) — the
    // skip-zero logic must kick in. Avoids actually allocating/freeing
    // 4 billion times.
    EnttRegistryType Reg;
    auto H1 = Allocate(&Reg);
    Free(H1); // Slot is now in the freelist; safe to mutate its generation.

    Debug_ForceSlotGenerationNearWrap_DoNotUseInProduction(H1.SlotIndex);

    auto H2 = Allocate(&Reg); // Increment wraps to 0 → skip-zero promotes to 1.
    TestNotEqual(TEXT("Wrapped generation must skip 0 (the never-allocated sentinel)"),
        H2.Generation, int32{0});
    TestTrue(TEXT("Wrapped slot reused (same SlotIndex)"),
        H2.SlotIndex == H1.SlotIndex);

    Free(H2);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
