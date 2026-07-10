// Unit tests for ck::debug_feature_flags — the sink-maintained per-registry feature-bit
// cache behind the ECS debugger redesign (CkGameplayDebugger docs/specs/2026-07-10 §5).
// Pure C++ tests; no PIE / world required. Surface: Ck.DebugFeatureFlags.<scenario>
//
// NOTE: flag registration is process-lifetime by design (like inspector/processor
// registries). Test flags use fragment types private to this TU, so their sinks never
// fire outside these tests.

#include "Misc/AutomationTest.h"

#include "CkEcs/DebugFeatureFlags/CkDebugFeatureFlags.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_debug_feature_flags
{
    struct FTestFlagFrag_A { int32 _Value = 0; };
    struct FTestFlagFrag_B { int32 _Value = 0; };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkDebugFeatureFlags_RegisterEnableSeedAndLiveBits,
    "Ck.DebugFeatureFlags.RegisterEnableSeedAndLiveBits",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkDebugFeatureFlags_RegisterEnableSeedAndLiveBits::RunTest(const FString& Parameters)
{
    using namespace ck_tests_debug_feature_flags;
    namespace flags = ck::debug_feature_flags;

    const auto BitA = flags::RegisterFlag<FTestFlagFrag_A>(TEXT("Test.FlagA"));
    const auto BitB = flags::RegisterFlag<FTestFlagFrag_B>(TEXT("Test.FlagB"));
    TestTrue(TEXT("FlagA registered"), BitA != INDEX_NONE);
    TestTrue(TEXT("FlagB registered"), BitB != INDEX_NONE);
    TestTrue(TEXT("Distinct bits"),    BitA != BitB);

    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    const auto MaskA = uint64{1} << BitA;
    const auto MaskB = uint64{1} << BitB;

    // Entity that exists BEFORE Enable — covered by the seed scan.
    const auto PreEntity = Reg.create();
    Reg.emplace<FTestFlagFrag_A>(PreEntity);

    TestTrue(TEXT("Disabled: no flags"), flags::Get_Flags(Registry, FCk_Entity{PreEntity}) == 0);

    flags::Enable(Registry);
    TestTrue(TEXT("Enabled"), flags::Get_IsEnabled(Registry));
    TestTrue(TEXT("Seed scan set pre-existing A bit"),
        (flags::Get_Flags(Registry, FCk_Entity{PreEntity}) & MaskA) != 0);

    // Entity created AFTER Enable — covered by live sinks.
    const auto LiveEntity = Reg.create();
    Reg.emplace<FTestFlagFrag_A>(LiveEntity);
    Reg.emplace<FTestFlagFrag_B>(LiveEntity);
    TestTrue(TEXT("Live add set both bits"),
        flags::Get_Flags(Registry, FCk_Entity{LiveEntity}) == (MaskA | MaskB));

    // Fragment removal clears its bit only.
    Reg.erase<FTestFlagFrag_A>(LiveEntity);
    TestTrue(TEXT("Erase A cleared A, kept B"),
        flags::Get_Flags(Registry, FCk_Entity{LiveEntity}) == MaskB);

    // Entity destruction clears the row via on_destroy.
    Reg.destroy(LiveEntity);
    TestTrue(TEXT("Destroyed entity has no flags"),
        flags::Get_Flags(Registry, FCk_Entity{LiveEntity}) == 0);

    flags::Disable(Registry);
    TestTrue(TEXT("Disabled again"), NOT flags::Get_IsEnabled(Registry));
    TestTrue(TEXT("Flags gone after Disable"),
        flags::Get_Flags(Registry, FCk_Entity{PreEntity}) == 0);

    // Mutations while disabled must be safe (sinks disconnected).
    Reg.emplace<FTestFlagFrag_B>(PreEntity);
    TestTrue(TEXT("Disabled mutation tracked nothing"),
        flags::Get_Flags(Registry, FCk_Entity{PreEntity}) == 0);

    ck::registry_table::Free(SlotHandle);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkDebugFeatureFlags_IdempotentRegisterAndUnknownQueries,
    "Ck.DebugFeatureFlags.IdempotentRegisterAndUnknownQueries",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkDebugFeatureFlags_IdempotentRegisterAndUnknownQueries::RunTest(const FString& Parameters)
{
    using namespace ck_tests_debug_feature_flags;
    namespace flags = ck::debug_feature_flags;

    const auto First = flags::RegisterFlag<FTestFlagFrag_A>(TEXT("Test.FlagA"));
    const auto Again = flags::RegisterFlag<FTestFlagFrag_A>(TEXT("Test.FlagA"));
    TestTrue(TEXT("Re-registration is idempotent"), First == Again);
    TestTrue(TEXT("Get_BitIndex agrees"), flags::Get_BitIndex(TEXT("Test.FlagA")) == First);

    TestTrue(TEXT("Unknown feature id"), flags::Get_BitIndex(TEXT("Test.DoesNotExist")) == INDEX_NONE);

    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    // Double-Enable and double-Disable are no-ops, not errors.
    flags::Enable(Registry);
    flags::Enable(Registry);
    TestTrue(TEXT("Still enabled after double Enable"), flags::Get_IsEnabled(Registry));

    flags::Disable(Registry);
    flags::Disable(Registry);
    TestTrue(TEXT("Still disabled after double Disable"), NOT flags::Get_IsEnabled(Registry));

    ck::registry_table::Free(SlotHandle);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
