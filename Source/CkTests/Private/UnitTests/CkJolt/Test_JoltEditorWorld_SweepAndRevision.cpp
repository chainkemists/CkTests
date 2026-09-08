#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"

#include "CkJolt/Settings/CkJolt_ProjectSettings.h"
#include "CkJolt/StaticWorld/CkJoltStaticWorld_Subsystem.h"
#include "CkJolt/Subsystem/CkJolt_Subsystem.h"

#include <Components/StaticMeshComponent.h>
#include <Engine/Level.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <Engine/World.h>
#include <Misc/ScopeExit.h>
#include <UObject/UObjectGlobals.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the LAZY sweep an Editor world gets in place of OnWorldBeginPlay, and the revision contract on top of it.
//
// Three facts, in the order they matter:
//   - Request_EnsureSwept sweeps the world's levels once. Nothing sweeps a map because it was opened, so a
//     consumer that needs geometry is the one that pays; the second call must add NOTHING, which is what the
//     _HasSwept flag exists for and what a re-entrant sweep would break by double-adding every level's bodies.
//   - Baking an actor after the sweep bumps Get_StaticSceneRevision, and removing it bumps it again. That token
//     is the whole argument for hosting a live Jolt world in the editor rather than inventing a second geometry
//     surface: an editor-world consumer fails closed on exactly the same revision PIE does.
//   - A world's subsystem collection is built once, when the world is created, so the mode is pinned BEFORE the
//     world exists (as in the SubsystemGating pin) and the project's own configuration cannot decide whether
//     the subsystems under test are reachable.
//
// The revision legs call Request_BakeActor / Request_RemoveActor DIRECTLY, on a manually baked actor AND on
// one the LEVEL SWEEP baked: the sweep files every actor it bakes in the same actor -> entity index the
// manual bake writes, so a request reaches level geometry too (it used to be a silent no-op there). That
// pair IS the surface the editor's actor add/delete/move delegates route through. The add delegate DOES
// reach this world (SpawnActor broadcasts it), so its refusal of a not-yet-bakeable spawn is pinned below;
// the move and delete orderings — and undo/redo — remain an [EDITOR-VERIFY], not reproducible headless.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_editor_world_sweep
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr auto InformEngineOfWorld = false;

    static auto Spawn_CubeActor(
        UWorld& InWorld,
        EComponentMobility::Type InMobility)
        -> AStaticMeshActor*
    {
        auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (Cube == nullptr)
        { return nullptr; }

        auto* Actor = InWorld.SpawnActor<AStaticMeshActor>();
        if (Actor == nullptr)
        { return nullptr; }

        auto* Component = Actor->GetStaticMeshComponent();
        Component->SetMobility(InMobility);
        Component->SetStaticMesh(Cube);
        Component->SetCollisionProfileName(TEXT("BlockAll"));
        Actor->RegisterAllComponents();

        return Actor;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltEditorWorld_SweepAndRevision,
    "Ck.Jolt.EditorWorld.SweepAndRevision",
    ck_test_jolt_editor_world_sweep::kTestFlags)

bool FCkTest_JoltEditorWorld_SweepAndRevision::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_editor_world_sweep;

    auto* Settings = GetMutableDefault<UCk_Jolt_ProjectSettings_UE>();

    if (NOT TestNotNull(TEXT("the Jolt project settings CDO resolves"), Settings))
    { return false; }

    const auto RestoreMode = Settings->Get_EditorStaticWorldMode();
    ON_SCOPE_EXIT { Settings->TestOnly_Set_EditorStaticWorldMode(RestoreMode); };

    Settings->TestOnly_Set_EditorStaticWorldMode(ECk_Jolt_EditorStaticWorldMode::LiveExtract);

    auto* World = UWorld::CreateWorld(EWorldType::Editor, InformEngineOfWorld, TEXT("CkJoltEditorSweep"));

    if (NOT TestNotNull(TEXT("temporary editor world is created"), World))
    { return false; }

    ON_SCOPE_EXIT { World->DestroyWorld(InformEngineOfWorld); };

    auto* JoltSubsystem = World->GetSubsystem<UCk_Jolt_Subsystem>();
    auto* StaticWorld = World->GetSubsystem<UCk_JoltStaticWorld_Subsystem_UE>();

    if (NOT TestNotNull(TEXT("the Jolt subsystem exists in an editor world"), JoltSubsystem) ||
        NOT TestNotNull(TEXT("the Jolt static-world subsystem exists in an editor world"), StaticWorld))
    { return false; }

    // Static mobility so the level sweep bakes it under every _BakeMobilityPolicy, not only the default one.
    auto* SweptCube = Spawn_CubeActor(*World, EComponentMobility::Static);

    if (NOT TestNotNull(TEXT("a static cube actor is spawned before the sweep"), SweptCube))
    { return false; }

    // ---- The sweep is lazy, and it happens exactly once ---------------------------------------------------
    TestEqual(TEXT("nothing swept the world merely because the subsystem exists"),
        StaticWorld->Get_NumStaticBodies(), 0);

    StaticWorld->Request_EnsureSwept();

    const auto NumBodiesAfterSweep = StaticWorld->Get_NumStaticBodies();

    // An Editor world always live-extracts, regardless of the project's PIE static-world mode — so the
    // sweep finding the cube is a meaningful assertion unconditionally.
    TestTrue(TEXT("the sweep baked the cube already in the world"), NumBodiesAfterSweep > 0);

    const auto RevisionAfterSweep = JoltSubsystem->Get_StaticSceneRevision();

    StaticWorld->Request_EnsureSwept();

    TestEqual(TEXT("a second Request_EnsureSwept adds no bodies"),
        StaticWorld->Get_NumStaticBodies(), NumBodiesAfterSweep);

    TestTrue(TEXT("a second Request_EnsureSwept does not touch the static scene at all"),
        JoltSubsystem->Get_StaticSceneRevision() == RevisionAfterSweep);

    // ---- Adding a static actor after the sweep bumps the revision -----------------------------------------
    auto* AddedCube = Spawn_CubeActor(*World, EComponentMobility::Static);

    if (NOT TestNotNull(TEXT("a second cube actor is spawned after the sweep"), AddedCube))
    { return false; }

    // The editor add handler saw this spawn (OnLevelActorAdded fires from SpawnActor), and at that moment
    // the actor's component had no mesh: admission must have refused it, so the count is untouched until
    // the explicit bake below.
    TestEqual(TEXT("the add handler did not bake a mesh-less spawn"),
        StaticWorld->Get_NumStaticBodies(), NumBodiesAfterSweep);

    const auto NumBodiesBaked = StaticWorld->Request_BakeActor(*AddedCube);

    if (NOT TestTrue(TEXT("baking the added actor produced bodies"), NumBodiesBaked > 0))
    { return false; }

    TestEqual(TEXT("the added actor's bodies are in the static world"),
        StaticWorld->Get_NumStaticBodies(), NumBodiesAfterSweep + NumBodiesBaked);

    const auto RevisionAfterBake = JoltSubsystem->Get_StaticSceneRevision();

    TestTrue(TEXT("baking an actor after the sweep bumps the static-scene revision"),
        RevisionAfterBake > RevisionAfterSweep);

    // ---- Removing it bumps again -------------------------------------------------------------------------
    StaticWorld->Request_RemoveActor(*AddedCube);

    TestEqual(TEXT("removing the added actor returns the body count"),
        StaticWorld->Get_NumStaticBodies(), NumBodiesAfterSweep);

    TestTrue(TEXT("removing the actor bumps the static-scene revision again"),
        JoltSubsystem->Get_StaticSceneRevision() > RevisionAfterBake);

    const auto RevisionAfterRemove = JoltSubsystem->Get_StaticSceneRevision();

    // ---- A SWEEP-baked actor answers the same two requests ------------------------------------------------
    // The whole point of the shared index: the actor below was never passed to Request_BakeActor — the
    // level sweep baked it — and removing it must still free exactly its bodies and bump the revision.
    StaticWorld->Request_RemoveActor(*SweptCube);

    const auto NumBodiesAfterSweptRemove = StaticWorld->Get_NumStaticBodies();

    TestTrue(TEXT("removing a SWEEP-baked actor frees its bodies"),
        NumBodiesAfterSweptRemove < NumBodiesAfterSweep);

    TestTrue(TEXT("removing a sweep-baked actor bumps the static-scene revision"),
        JoltSubsystem->Get_StaticSceneRevision() > RevisionAfterRemove);

    const auto RevisionAfterSweptRemove = JoltSubsystem->Get_StaticSceneRevision();

    const auto NumBodiesSweptRebaked = StaticWorld->Request_BakeActor(*SweptCube);

    TestEqual(TEXT("the removal dropped exactly the swept actor's own bodies"),
        NumBodiesAfterSweptRemove + NumBodiesSweptRebaked, NumBodiesAfterSweep);

    TestEqual(TEXT("re-baking the swept actor restores the swept body count"),
        StaticWorld->Get_NumStaticBodies(), NumBodiesAfterSweep);

    TestTrue(TEXT("re-baking the swept actor bumps the static-scene revision again"),
        JoltSubsystem->Get_StaticSceneRevision() > RevisionAfterSweptRemove);

    // ---- A REQUEST-baked actor's bodies go with its level -------------------------------------------------
    // SweptCube's live entity came from Request_BakeActor, not from the sweep. It must still be in its
    // level's teardown list, or an editor sub-level unload would free the level and leave these bodies —
    // reachable by nothing but world teardown. LevelRemovedFromWorld is the delegate the subsystem binds,
    // and this world is unregistered with the engine, so broadcasting it is deterministic here.
    FWorldDelegates::LevelRemovedFromWorld.Broadcast(World->PersistentLevel, World);

    TestEqual(TEXT("removing the level frees its request-baked bodies too"),
        StaticWorld->Get_NumStaticBodies(), 0);

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
