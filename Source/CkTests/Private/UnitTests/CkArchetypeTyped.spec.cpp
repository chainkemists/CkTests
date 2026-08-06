// Unit tests for CK_DEFINE_ARCHETYPE — the typed archetype amalgamation (CkGameplayDebugger
// docs/specs/2026-07-10 §3.3, code tier). Pure C++; no PIE required.
// Surface: Ck.Archetype.<scenario>
//
// Uses REAL feature fragments (Transform, Timer) added directly to a raw registry so the
// generated TryCast exercises the real UCk_Utils_*_UE::Has/Cast gates. The typed archetype
// self-registers at EndOfEngineInit and stays registered for the process lifetime — exactly
// like game-authored archetypes — so no Unregister at test end.

#include "Misc/AutomationTest.h"

#include "CkCore/Chrono/CkChrono.h"
#include "CkEcs/Archetype/CkArchetype_Registry.h"
#include "CkEcs/Archetype/CkArchetype_Typed.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkTimer/CkTimer_Utils.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_archetype_typed
{
    struct FCkTest_Archetype_Rig
    {
        FCk_Handle_Transform Transform;
        FCk_Handle_Timer Timer;

        CK_ARCHETYPE_BODY(FCkTest_Archetype_Rig);
    };

    CK_DEFINE_ARCHETYPE(FCkTest_Archetype_Rig, "CkTests.TypedRig", Transform, Timer);
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkArchetype_TypedTryCastAndAutoRegistration,
    "Ck.Archetype.TypedTryCastAndAutoRegistration",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkArchetype_TypedTryCastAndAutoRegistration::RunTest(const FString& Parameters)
{
    using namespace ck_tests_archetype_typed;
    namespace archetypes = ck::archetype_registry;

    // Auto-registration (EndOfEngineInit fired long before tests run).
    const auto Descriptor = archetypes::Find(TEXT("CkTests.TypedRig"));
    TestTrue(TEXT("typed archetype self-registered"), Descriptor.IsSet());
    TestTrue(TEXT("FeatureIds derive from the member list"),
        Descriptor.IsSet() && Descriptor->Get_FeatureIds().Num() == 2);

    auto Reg = ck::registry_table::EnttRegistryType{};
    const auto SlotHandle = ck::registry_table::Allocate(&Reg);

    // Invalid handle → unset, no ensure.
    TestTrue(TEXT("invalid handle fails TryCast"),
        NOT FCkTest_Archetype_Rig::TryCast(FCk_Handle{}).IsSet());

    // Transform only → all-or-nothing says no.
    const auto EntityId = Reg.create();
    const auto Handle = FCk_Handle{FCk_Entity{EntityId}, SlotHandle};
    Reg.emplace<ck::FFragment_Transform>(EntityId, FTransform{});

    TestTrue(TEXT("partial features fail TryCast"),
        NOT FCkTest_Archetype_Rig::TryCast(Handle).IsSet());

    // + Timer (FFragment_Timer is the typesafe Has anchor; Params is the retained residue) → set, members typed + valid.
    Reg.emplace<ck::FFragment_Timer_Params>(EntityId);
    Reg.emplace<ck::FFragment_Timer>(EntityId, FCk_Chrono{FCk_Time{1.0f}});

    const auto Rig = FCkTest_Archetype_Rig::TryCast(Handle);
    TestTrue(TEXT("full features pass TryCast"), Rig.IsSet());
    TestTrue(TEXT("Transform member valid"), Rig.IsSet() && ck::IsValid(Rig->Transform));
    TestTrue(TEXT("Timer member valid"), Rig.IsSet() && ck::IsValid(Rig->Timer));

    // TryCast doubles as the registry's native matcher — matching works even with the
    // feature-flag cache disabled on this registry.
    TestTrue(TEXT("native matcher matches full entity"),
        archetypes::Get_Matches(Handle, TEXT("CkTests.TypedRig")));

    const auto PartialEntityId = Reg.create();
    const auto PartialHandle = FCk_Handle{FCk_Entity{PartialEntityId}, SlotHandle};
    Reg.emplace<ck::FFragment_Transform>(PartialEntityId, FTransform{});
    TestTrue(TEXT("native matcher rejects partial entity"),
        NOT archetypes::Get_Matches(PartialHandle, TEXT("CkTests.TypedRig")));

    ck::registry_table::Free(SlotHandle);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
