// Unit tests for ck::archetype_registry — named feature-amalgamations with debugger
// identity (CkGameplayDebugger docs/specs/2026-07-10 §3.3). Pure C++; no PIE required.
// Surface: Ck.Archetype.<scenario>
//
// Matching CkEcs-side = native matcher, else FeatureIds through the DebugFeatureFlags
// bit cache. Test archetypes are unregistered at the end of each test (the registry is
// process-lifetime); test flag fragments are private to this TU.

#include "Misc/AutomationTest.h"

#include "CkEcs/Archetype/CkArchetype_Data.h"
#include "CkEcs/Archetype/CkArchetype_Registry.h"
#include "CkEcs/DebugFeatureFlags/CkDebugFeatureFlags.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_archetype
{
    struct FTestArchFrag_X { int32 _Value = 0; };
    struct FTestArchFrag_Y { int32 _Value = 0; };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkArchetype_RegisterFindReplaceUnregister,
    "Ck.Archetype.RegisterFindReplaceUnregister",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkArchetype_RegisterFindReplaceUnregister::RunTest(const FString& Parameters)
{
    namespace archetypes = ck::archetype_registry;

    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.Reg.A")}.Set_Priority(5));
    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.Reg.B")}.Set_Priority(10));

    const auto FoundA = archetypes::Find(TEXT("Test.Reg.A"));
    TestTrue(TEXT("Find returns registered descriptor"), FoundA.IsSet());
    TestTrue(TEXT("Descriptor data survives"), FoundA.IsSet() && FoundA->Get_Priority() == 5);

    // Re-registration replaces (last wins).
    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.Reg.A")}.Set_Priority(7));
    const auto FoundA2 = archetypes::Find(TEXT("Test.Reg.A"));
    TestTrue(TEXT("Re-registration replaced"), FoundA2.IsSet() && FoundA2->Get_Priority() == 7);

    // Precedence order: higher priority first.
    const auto All = archetypes::Get_All();
    auto IndexA = int32{INDEX_NONE};
    auto IndexB = int32{INDEX_NONE};
    for (auto Index = 0; Index < All.Num(); ++Index)
    {
        if (All[Index].Get_Name() == TEXT("Test.Reg.A")) { IndexA = Index; }
        if (All[Index].Get_Name() == TEXT("Test.Reg.B")) { IndexB = Index; }
    }
    TestTrue(TEXT("Both present in Get_All"), IndexA != INDEX_NONE && IndexB != INDEX_NONE);
    TestTrue(TEXT("Higher priority sorts first"), IndexB < IndexA);

    archetypes::Unregister(TEXT("Test.Reg.A"));
    archetypes::Unregister(TEXT("Test.Reg.B"));
    TestTrue(TEXT("Unregistered"), NOT archetypes::Find(TEXT("Test.Reg.A")).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkArchetype_MatchingViaFlagCacheAndNativeMatcher,
    "Ck.Archetype.MatchingViaFlagCacheAndNativeMatcher",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkArchetype_MatchingViaFlagCacheAndNativeMatcher::RunTest(const FString& Parameters)
{
    using namespace ck_tests_archetype;
    namespace archetypes = ck::archetype_registry;
    namespace flags = ck::debug_feature_flags;

    flags::RegisterFlag<FTestArchFrag_X>(TEXT("TestArch.X"));
    flags::RegisterFlag<FTestArchFrag_Y>(TEXT("TestArch.Y"));

    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);
    const auto Registry = FCk_Registry{SlotHandle};

    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.XY")}
        .Set_FeatureIds({TEXT("TestArch.X"), TEXT("TestArch.Y")}));
    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.OnlyX")}
        .Set_FeatureIds({TEXT("TestArch.X")}));
    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.UnknownFeature")}
        .Set_FeatureIds({TEXT("TestArch.DoesNotExist")}));

    const auto EntityXY = Reg.create();
    const auto HandleXY = FCk_Handle{FCk_Entity{EntityXY}, SlotHandle};

    // Cache disabled → FeatureIds matching answers false (documented contract).
    Reg.emplace<FTestArchFrag_X>(EntityXY);
    Reg.emplace<FTestArchFrag_Y>(EntityXY);
    TestTrue(TEXT("Disabled cache: no match"), NOT archetypes::Get_Matches(HandleXY, TEXT("Test.XY")));

    flags::Enable(Registry);

    TestTrue(TEXT("XY entity matches Test.XY"),    archetypes::Get_Matches(HandleXY, TEXT("Test.XY")));
    TestTrue(TEXT("XY entity matches Test.OnlyX"), archetypes::Get_Matches(HandleXY, TEXT("Test.OnlyX")));
    TestTrue(TEXT("Unknown feature never matches"), NOT archetypes::Get_Matches(HandleXY, TEXT("Test.UnknownFeature")));
    TestTrue(TEXT("Unknown archetype never matches"), NOT archetypes::Get_Matches(HandleXY, TEXT("Test.NotRegistered")));

    const auto EntityX = Reg.create();
    Reg.emplace<FTestArchFrag_X>(EntityX);
    const auto HandleX = FCk_Handle{FCk_Entity{EntityX}, SlotHandle};
    TestTrue(TEXT("X-only entity fails Test.XY"),   NOT archetypes::Get_Matches(HandleX, TEXT("Test.XY")));
    TestTrue(TEXT("X-only entity matches Test.OnlyX"), archetypes::Get_Matches(HandleX, TEXT("Test.OnlyX")));

    // Best match: more required features wins at equal priority.
    TestTrue(TEXT("BestMatch prefers most features"),
        archetypes::TryGet_BestMatchName(HandleXY) == FName{TEXT("Test.XY")});

    // Priority overrides feature count.
    archetypes::Register(FCk_ArchetypeDescriptor{TEXT("Test.PrioX")}
        .Set_FeatureIds({TEXT("TestArch.X")})
        .Set_Priority(100));
    TestTrue(TEXT("BestMatch honors priority"),
        archetypes::TryGet_BestMatchName(HandleXY) == FName{TEXT("Test.PrioX")});

    // Native matcher bypasses the flag cache entirely.
    archetypes::Register(
        FCk_ArchetypeDescriptor{TEXT("Test.Native")},
        [](const FCk_Handle&) { return true; });
    TestTrue(TEXT("Native matcher matches"), archetypes::Get_Matches(HandleX, TEXT("Test.Native")));

    flags::Disable(Registry);
    TestTrue(TEXT("Native matcher still matches with cache off"),
        archetypes::Get_Matches(HandleX, TEXT("Test.Native")));

    for (const auto& Name : {TEXT("Test.XY"), TEXT("Test.OnlyX"), TEXT("Test.UnknownFeature"), TEXT("Test.PrioX"), TEXT("Test.Native")})
    { archetypes::Unregister(Name); }

    ck::registry_table::Free(SlotHandle);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
