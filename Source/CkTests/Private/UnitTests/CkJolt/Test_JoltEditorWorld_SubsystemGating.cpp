#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Subsystem/CkEcsEditor_Subsystem.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkJolt/Settings/CkJolt_ProjectSettings.h"
#include "CkJolt/StaticWorld/CkJoltStaticWorld_Subsystem.h"
#include "CkJolt/Subsystem/CkJolt_Subsystem.h"

#include <Engine/World.h>
#include <Misc/ScopeExit.h>
#include <UObject/UObjectGlobals.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the editor-world opt-in for the two CkJolt world subsystems. Both inherit a Game||PIE world-type gate,
// so with ECk_Jolt_EditorStaticWorldMode::Disabled an Editor world hosts NEITHER — that is what makes the
// setting's default free, and it is the leg a DoesSupportWorldType override that forgot to consult the setting
// would fail.
//
// A world's subsystem collection is built once, when the world is created, so each case creates its OWN world
// AFTER pinning the mode — the setting takes effect on the next map load and a shared world would make the ON
// case vacuous. The project's own configuration is pinned for the same reason the snapshot audit-mode tests pin
// theirs: it would otherwise decide which half of the assertion is reachable.
//
// The ON case also asserts the Jolt world was actually BUILT and published into the EDITOR registry, not merely
// constructed: a subsystem that existed but nulled out on the runtime ECS dependency it can no longer have in an
// editor world would still pass a bare "is not null" check.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_editor_world_gating
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr auto InformEngineOfWorld = false;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltEditorWorld_SubsystemGating,
    "Ck.Jolt.EditorWorld.SubsystemGating",
    ck_test_jolt_editor_world_gating::kTestFlags)

bool FCkTest_JoltEditorWorld_SubsystemGating::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_editor_world_gating;

    auto* Settings = GetMutableDefault<UCk_Jolt_ProjectSettings_UE>();

    if (NOT TestNotNull(TEXT("the Jolt project settings CDO resolves"), Settings))
    { return false; }

    const auto RestoreMode = Settings->Get_EditorStaticWorldMode();
    ON_SCOPE_EXIT { Settings->TestOnly_Set_EditorStaticWorldMode(RestoreMode); };

    // ---- OFF: an editor world hosts neither subsystem ---------------------------------------------------
    {
        Settings->TestOnly_Set_EditorStaticWorldMode(ECk_Jolt_EditorStaticWorldMode::Disabled);

        auto* World = UWorld::CreateWorld(EWorldType::Editor, InformEngineOfWorld, TEXT("CkJoltEditorGateOff"));

        if (NOT TestNotNull(TEXT("off: temporary editor world is created"), World))
        { return false; }

        ON_SCOPE_EXIT { World->DestroyWorld(InformEngineOfWorld); };

        TestNull(TEXT("off: no Jolt subsystem in an editor world"),
            World->GetSubsystem<UCk_Jolt_Subsystem>());

        TestNull(TEXT("off: no Jolt static-world subsystem in an editor world"),
            World->GetSubsystem<UCk_JoltStaticWorld_Subsystem_UE>());
    }

    // ---- ON: both exist, over the EDITOR ecs world ------------------------------------------------------
    {
        Settings->TestOnly_Set_EditorStaticWorldMode(ECk_Jolt_EditorStaticWorldMode::LiveExtract);

        auto* World = UWorld::CreateWorld(EWorldType::Editor, InformEngineOfWorld, TEXT("CkJoltEditorGateOn"));

        if (NOT TestNotNull(TEXT("on: temporary editor world is created"), World))
        { return false; }

        ON_SCOPE_EXIT { World->DestroyWorld(InformEngineOfWorld); };

        auto* JoltSubsystem = World->GetSubsystem<UCk_Jolt_Subsystem>();

        if (NOT TestNotNull(TEXT("on: the Jolt subsystem exists in an editor world"), JoltSubsystem))
        { return false; }

        TestNotNull(TEXT("on: the Jolt static-world subsystem exists in an editor world"),
            World->GetSubsystem<UCk_JoltStaticWorld_Subsystem_UE>());

        // It initialized against the EDITOR ecs world — the runtime one does not exist here at all.
        TestNull(TEXT("on: an editor world still has no runtime ECS world subsystem"),
            World->GetSubsystem<UCk_EcsWorld_Subsystem_UE>());

        auto* EditorEcsSubsystem = World->GetSubsystem<UCk_EditorEcsWorld_Subsystem_UE>();

        if (NOT TestNotNull(TEXT("on: the editor ECS world subsystem exists"), EditorEcsSubsystem))
        { return false; }

        TestTrue(TEXT("on: the Jolt world was built (its PhysicsSystem is live)"),
            JoltSubsystem->Get_PhysicsSystem().IsValid());

        const auto EditorRegistry = EditorEcsSubsystem->Get_Registry();
        const auto* PublishedJoltWorld = EditorRegistry.TryGetContext<TSharedPtr<ck::FJoltWorld>>();

        if (NOT TestNotNull(TEXT("on: the Jolt world is published into the EDITOR registry"), PublishedJoltWorld))
        { return false; }

        TestTrue(TEXT("on: the published Jolt world is the live one"), PublishedJoltWorld->IsValid());

        TestTrue(TEXT("on: the Jolt subsystem resolves the editor transient entity"),
            JoltSubsystem->Get_TransientEntity() == EditorEcsSubsystem->Get_TransientEntity());

        // The physics step lives behind the four RuntimeOnly FProcessor_JoltWorld_* processors, so an Editor
        // world's scheduler graph never builds them. Drive the editor scheduler with a delta well past the
        // default 60Hz/4-steps-per-frame clamp: if the quartet ran at all, NumStepsLastFrame would be clamped to a
        // nonzero value, never left at its untouched default - a call that "did not crash" would pass even with the
        // step wired back in, this would not.
        const auto NumStepsBeforeTicking = (*PublishedJoltWorld)->Get_NumStepsLastFrame();

        for (auto TickIndex = 0; TickIndex < 5; ++TickIndex)
        { EditorEcsSubsystem->Tick(1.0f); }

        TestEqual(TEXT("on: the editor world's Jolt world never planned a step"),
            (*PublishedJoltWorld)->Get_NumStepsLastFrame(), NumStepsBeforeTicking);

        TestEqual(TEXT("on: the editor world's Jolt world step count stayed at its untouched default"),
            (*PublishedJoltWorld)->Get_NumStepsLastFrame(), 0);
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
