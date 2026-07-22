// Unit tests for ck::registry_table — the process-lifetime slot allocator
// behind the generational-handle migration. Pure C++ tests; no PIE / world
// required. Surface in Session Frontend: Ck.Registry.SlotTable.<scenario>

#include "Misc/AutomationTest.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_registry_view
{
    struct FTestFragment
    {
        int32 Value = 0;
    };

    struct FExcludedFragment
    {
        int32 Value = 0;
    };
}

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
    FCkRegistryView_InvalidFailsClosed,
    "Ck.Registry.View.InvalidFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryView_InvalidFailsClosed::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view;
    using namespace ck::registry_table;

    // The pointer-backed view itself must remain safe independently of ensure
    // configuration. This directly pins the unconditional ForEach bailout.
    auto NullViewCallbackCount = int32{0};
    FCk_Registry::RegistryViewType<FTestFragment>{nullptr}.ForEach(
        [&NullViewCallbackCount](FCk_Entity, FTestFragment&)
        {
            ++NullViewCallbackCount;
        });
    TestEqual(TEXT("Explicit null view invokes no callbacks"), NullViewCallbackCount, int32{0});

    AddExpectedError(
        TEXT("registry_table::Resolve called with an unset handle"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto MutableUnsetCallbackCount = int32{0};
    auto MutableUnsetRegistry = FCk_Registry{};
    MutableUnsetRegistry.View<FTestFragment>().ForEach(
        [&MutableUnsetCallbackCount](FCk_Entity, FTestFragment&)
        {
            ++MutableUnsetCallbackCount;
        });

    auto ConstUnsetCallbackCount = int32{0};
    const auto ConstUnsetRegistry = FCk_Registry{};
    ConstUnsetRegistry.View<FTestFragment>().ForEach(
        [&ConstUnsetCallbackCount](FCk_Entity, const FTestFragment&)
        {
            ++ConstUnsetCallbackCount;
        });

    TestEqual(TEXT("Mutable unset registry view invokes no callbacks"), MutableUnsetCallbackCount, int32{0});
    TestEqual(TEXT("Const unset registry view invokes no callbacks"), ConstUnsetCallbackCount, int32{0});

    auto StaleBackingRegistry = EnttRegistryType{};
    const auto StaleHandle = Allocate(&StaleBackingRegistry);
    auto StaleRegistry = FCk_Registry{StaleHandle};
    Free(StaleHandle);

    AddExpectedError(
        TEXT("Stale FCk_RegistryHandle"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto StaleCallbackCount = int32{0};
    StaleRegistry.View<FTestFragment>().ForEach(
        [&StaleCallbackCount](FCk_Entity, FTestFragment&)
        {
            ++StaleCallbackCount;
        });
    TestEqual(TEXT("Stale registry view invokes no callbacks"), StaleCallbackCount, int32{0});

    AddExpectedError(
        TEXT("Unable to prepare a View"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto InvalidHandleCallbackCount = int32{0};
    auto InvalidHandle = FCk_Handle{};
    InvalidHandle.View<FTestFragment>().ForEach(
        [&InvalidHandleCallbackCount](FCk_Entity, FTestFragment&)
        {
            ++InvalidHandleCallbackCount;
        });
    TestEqual(TEXT("Invalid entity handle view invokes no callbacks"), InvalidHandleCallbackCount, int32{0});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryView_ValidParity,
    "Ck.Registry.View.ValidParity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryView_ValidParity::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view;
    using namespace ck::registry_table;

    auto BackingRegistry = EnttRegistryType{};
    const auto RegistryHandle = Allocate(&BackingRegistry);
    auto Registry = FCk_Registry{RegistryHandle};

    const auto IncludedEntity = BackingRegistry.create();
    BackingRegistry.emplace<FTestFragment>(IncludedEntity, FTestFragment{41});

    const auto ExcludedEntity = BackingRegistry.create();
    BackingRegistry.emplace<FTestFragment>(ExcludedEntity, FTestFragment{99});
    BackingRegistry.emplace<FExcludedFragment>(ExcludedEntity, FExcludedFragment{});

    auto MutableCallbackCount = int32{0};
    Registry.View<FTestFragment, ck::TExclude<FExcludedFragment>>().ForEach(
        [&MutableCallbackCount](FCk_Entity, FTestFragment& InFragment)
        {
            ++MutableCallbackCount;
            ++InFragment.Value;
        });

    TestEqual(TEXT("Mutable view preserves exclude filtering"), MutableCallbackCount, int32{1});
    TestEqual(TEXT("Mutable view preserves fragment access"), BackingRegistry.get<FTestFragment>(IncludedEntity).Value, int32{42});
    TestEqual(TEXT("Excluded entity is not visited"), BackingRegistry.get<FTestFragment>(ExcludedEntity).Value, int32{99});

    const auto& ConstRegistry = Registry;
    auto ConstCallbackCount = int32{0};
    auto ConstValueSum = int32{0};
    ConstRegistry.View<FTestFragment, ck::TExclude<FExcludedFragment>>().ForEach(
        [&ConstCallbackCount, &ConstValueSum](FCk_Entity, const FTestFragment& InFragment)
        {
            ++ConstCallbackCount;
            ConstValueSum += InFragment.Value;
        });

    TestEqual(TEXT("Const view preserves exclude filtering"), ConstCallbackCount, int32{1});
    TestEqual(TEXT("Const view preserves fragment access"), ConstValueSum, int32{42});

    Free(RegistryHandle);
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
