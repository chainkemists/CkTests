// Unit tests pinning TView::HasAny — the single implementation of "would this view visit
// anything", used by the settle-barrier consumable dirty checks. Pure C++; no PIE / world.
// Surface in Session Frontend: Ck.Registry.ViewHasAny.<scenario>
//
// The six cases mirror the review that made HasAny the sole implementation of this
// predicate: never-created include pool, never-created exclude pool, tombstone-only pool,
// unsatisfied conjunction, duplicate include, and the single-include baseline.

#include "Misc/AutomationTest.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_registry_view_hasany
{
    // in_place_delete matches every Ck fragment pool — it is what makes tombstone residue
    // possible in the first place (see Has_AnyLiveEntityWith's doc comment).
    struct FFragA
    {
        static constexpr auto in_place_delete = true;
        int32 Value = 0;
    };

    struct FFragB
    {
        static constexpr auto in_place_delete = true;
        int32 Value = 0;
    };

    struct FFragNeverCreated
    {
        static constexpr auto in_place_delete = true;
        int32 Value = 0;
    };

    struct FScopedRegistry
    {
        ck::registry_table::EnttRegistryType Reg;
        FCk_RegistryHandle Slot = ck::registry_table::Allocate(&Reg);

        ~FScopedRegistry()
        {
            ck::registry_table::Free(Slot);
        }

        auto View() const -> const FCk_Registry
        {
            return FCk_Registry{Slot};
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryViewHasAny_SingleInclude,
    "Ck.Registry.ViewHasAny.SingleInclude",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryViewHasAny_SingleInclude::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view_hasany;

    FScopedRegistry Scoped;
    const auto Registry = Scoped.View();

    TestFalse(TEXT("Empty registry -> no match"), Registry.View<FFragA>().HasAny());

    const auto Entity = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(Entity);

    TestTrue(TEXT("One live entity -> match"), Registry.View<FFragA>().HasAny());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryViewHasAny_NeverCreatedIncludePool,
    "Ck.Registry.ViewHasAny.NeverCreatedIncludePool",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryViewHasAny_NeverCreatedIncludePool::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view_hasany;

    FScopedRegistry Scoped;
    const auto Registry = Scoped.View();

    const auto Entity = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(Entity);

    // The un-created pool must read as empty WITHOUT being assured into existence: a read-only
    // query must not allocate storage as a side effect.
    TestFalse(TEXT("Missing include pool -> no match"),
        (Registry.View<FFragA, FFragNeverCreated>().HasAny()));
    TestTrue(TEXT("Query did not create the pool"),
        std::as_const(Scoped.Reg).storage<FFragNeverCreated>() == nullptr);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryViewHasAny_NeverCreatedExcludePool,
    "Ck.Registry.ViewHasAny.NeverCreatedExcludePool",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryViewHasAny_NeverCreatedExcludePool::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view_hasany;

    FScopedRegistry Scoped;
    const auto Registry = Scoped.View();

    const auto Entity = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(Entity);

    // An exclude pool nothing ever touched excludes nothing — and must not be created either.
    TestTrue(TEXT("Missing exclude pool excludes nothing"),
        (Registry.View<FFragA, ck::TExclude<FFragNeverCreated>>().HasAny()));
    TestTrue(TEXT("Query did not create the exclude pool"),
        std::as_const(Scoped.Reg).storage<FFragNeverCreated>() == nullptr);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryViewHasAny_TombstoneOnlyPool,
    "Ck.Registry.ViewHasAny.TombstoneOnlyPool",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryViewHasAny_TombstoneOnlyPool::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view_hasany;

    FScopedRegistry Scoped;
    const auto Registry = Scoped.View();

    const auto Entity = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(Entity);
    Scoped.Reg.remove<FFragA>(Entity);

    // in_place_delete leaves the tombstone in the dense array — the pool is non-empty but holds
    // zero LIVE entities. This is the exact residue Has_AnyEntityWith mis-reports forever.
    TestTrue(TEXT("Pool exists and is non-empty (tombstone residue)"),
        std::as_const(Scoped.Reg).storage<FFragA>() != nullptr
            && NOT std::as_const(Scoped.Reg).storage<FFragA>()->empty());
    TestFalse(TEXT("Tombstone-only pool -> no match"), Registry.View<FFragA>().HasAny());

    // Same through entity destruction (every pool the entity touched gets the tombstone).
    const auto Entity2 = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(Entity2);
    Scoped.Reg.destroy(Entity2);
    TestFalse(TEXT("Destroyed-entity residue -> no match"), Registry.View<FFragA>().HasAny());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryViewHasAny_UnsatisfiedConjunction,
    "Ck.Registry.ViewHasAny.UnsatisfiedConjunction",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryViewHasAny_UnsatisfiedConjunction::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view_hasany;

    FScopedRegistry Scoped;
    const auto Registry = Scoped.View();

    // A has 2 entities, B has 1 — on a DIFFERENT entity. Both pools non-empty, conjunction empty.
    const auto EntityA1 = Scoped.Reg.create();
    const auto EntityA2 = Scoped.Reg.create();
    const auto EntityB  = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(EntityA1);
    Scoped.Reg.emplace<FFragA>(EntityA2);
    Scoped.Reg.emplace<FFragB>(EntityB);

    TestFalse(TEXT("Non-empty pools, empty conjunction -> no match"),
        (Registry.View<FFragA, FFragB>().HasAny()));

    Scoped.Reg.emplace<FFragB>(EntityA1);
    TestTrue(TEXT("Conjunction satisfied -> match"),
        (Registry.View<FFragA, FFragB>().HasAny()));

    // The exclude side of the same shape: every remaining A-holder also carries the exclude.
    Scoped.Reg.remove<FFragA>(EntityA2);
    TestFalse(TEXT("Sole A-holder carries the exclude -> no match"),
        (Registry.View<FFragA, ck::TExclude<FFragB>>().HasAny()));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistryViewHasAny_DuplicateInclude,
    "Ck.Registry.ViewHasAny.DuplicateInclude",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistryViewHasAny_DuplicateInclude::RunTest(const FString& Parameters)
{
    using namespace ck_tests_registry_view_hasany;

    FScopedRegistry Scoped;
    const auto Registry = Scoped.View();

    const auto Entity = Scoped.Reg.create();
    Scoped.Reg.emplace<FFragA>(Entity);

    // A caller naming a fragment the view already requires (the consumable checker prepends the
    // dirty marker to the processor's own fragment list) must be legal and answer identically.
    TestTrue(TEXT("Duplicate include -> same answer as single"),
        (Registry.View<FFragA, FFragA>().HasAny()));

    Scoped.Reg.remove<FFragA>(Entity);
    TestFalse(TEXT("Duplicate include over tombstones -> no match"),
        (Registry.View<FFragA, FFragA>().HasAny()));
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
