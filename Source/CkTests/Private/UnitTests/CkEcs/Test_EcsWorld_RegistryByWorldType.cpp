#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry.h"
#include "CkEcs/Subsystem/CkEcsEditor_Subsystem.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include <Engine/World.h>
#include <Misc/ScopeExit.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the world-type seam over the two ECS world subsystems: which registry (and which transient entity) a
// UWorld resolves to is decided by its WorldType, because the runtime subsystem is gated to Game/PIE and the
// editor one to Editor, and no world ever hosts both.
//
// The discriminating leg is that the two worlds — held live at the same time — resolve to DIFFERENT
// registries. A seam that always returned the runtime subsystem's, or always the editor one's, would still
// answer "valid" for one world and would still agree with that world's own subsystem.
//
// Also asserts the Game path is unchanged: the seam's transient entity is the very handle the pre-existing
// Get_TransientEntity already returned for that world.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_ecsworld_registry_by_worldtype
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr auto InformEngineOfWorld = false;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_EcsWorld_RegistryByWorldType,
    "Ck.Ecs.World.RegistryByWorldType",
    ck_test_ecsworld_registry_by_worldtype::kTestFlags)

bool FCkTest_EcsWorld_RegistryByWorldType::RunTest(const FString& Parameters)
{
    using namespace ck_test_ecsworld_registry_by_worldtype;

    auto* GameWorld = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, TEXT("CkEcsSeamGame"));

    if (NOT TestNotNull(TEXT("temporary game world is created"), GameWorld))
    { return false; }

    ON_SCOPE_EXIT { GameWorld->DestroyWorld(InformEngineOfWorld); };

    auto* EditorWorld = UWorld::CreateWorld(EWorldType::Editor, InformEngineOfWorld, TEXT("CkEcsSeamEditor"));

    if (NOT TestNotNull(TEXT("temporary editor world is created"), EditorWorld))
    { return false; }

    ON_SCOPE_EXIT { EditorWorld->DestroyWorld(InformEngineOfWorld); };

    const auto* RuntimeSubsystem = GameWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
    const auto* EditorSubsystem = EditorWorld->GetSubsystem<UCk_EditorEcsWorld_Subsystem_UE>();

    if (NOT TestNotNull(TEXT("a game world hosts the runtime ECS world subsystem"), RuntimeSubsystem) ||
        NOT TestNotNull(TEXT("an editor world hosts the editor ECS world subsystem"), EditorSubsystem))
    { return false; }

    TestNull(TEXT("an editor world does NOT host the runtime ECS world subsystem"),
        EditorWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>());

    const auto GameRegistry = UCk_Utils_EcsWorld_Subsystem_UE::TryGet_RegistryForWorld(*GameWorld);
    const auto EditorRegistry = UCk_Utils_EcsWorld_Subsystem_UE::TryGet_RegistryForWorld(*EditorWorld);

    const auto GameTransientEntity =
        UCk_Utils_EcsWorld_Subsystem_UE::TryGet_TransientEntityForWorld(*GameWorld);
    const auto EditorTransientEntity =
        UCk_Utils_EcsWorld_Subsystem_UE::TryGet_TransientEntityForWorld(*EditorWorld);

    // ---- Game resolves the RUNTIME subsystem ----------------------------------------------------------
    TestTrue(TEXT("game: the seam resolves a valid registry"), ck::IsValid(GameRegistry));

    TestTrue(TEXT("game: it is the RUNTIME subsystem's registry"),
        GameRegistry.Get_RegistryHandle() == RuntimeSubsystem->Get_Registry().Get_RegistryHandle());

    TestTrue(TEXT("game: the seam's transient entity is the runtime subsystem's"),
        GameTransientEntity == RuntimeSubsystem->Get_TransientEntity());

    // The pre-existing accessor is what every current caller uses; the seam must agree with it exactly.
    TestTrue(TEXT("game: unchanged behaviour - the seam agrees with Get_TransientEntity"),
        GameTransientEntity == UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(GameWorld));

    // ---- Editor resolves the EDITOR subsystem ---------------------------------------------------------
    TestTrue(TEXT("editor: the seam resolves a valid registry"), ck::IsValid(EditorRegistry));

    TestTrue(TEXT("editor: it is the EDITOR subsystem's registry"),
        EditorRegistry.Get_RegistryHandle() == EditorSubsystem->Get_Registry().Get_RegistryHandle());

    TestTrue(TEXT("editor: the seam's transient entity is the editor subsystem's"),
        EditorTransientEntity == EditorSubsystem->Get_TransientEntity());

    // ---- The two are genuinely different worlds' registries -------------------------------------------
    TestTrue(TEXT("the two world types resolve to DIFFERENT registries"),
        EditorRegistry.Get_RegistryHandle() != GameRegistry.Get_RegistryHandle());

    TestFalse(TEXT("the two world types resolve to different transient entities"),
        EditorTransientEntity == GameTransientEntity);

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
