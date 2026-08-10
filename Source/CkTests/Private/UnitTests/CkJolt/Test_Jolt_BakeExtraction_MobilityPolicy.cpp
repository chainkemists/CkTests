#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include <Components/StaticMeshComponent.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <Engine/World.h>
#include <Tests/AutomationCommon.h>

// --------------------------------------------------------------------------------------------------------------------
// Locks the level-sweep mobility policy and its observability contract:
//
//   - LevelSweep bakes Static-mobility components and SKIPS Movable ones — and that skip is COUNTED in
//     FCk_Jolt_ExtractionStats, because it is the one a designer trips by accident (a Movable floor
//     silently vanishes from the Jolt static world while Chaos still blocks against it; this exact case
//     cost a debugging session in BusterBlock's Character_Gym).
//   - ExplicitActor (the Request_BakeActor path) bakes Movable components: the caller declared the actor
//     static-in-intent, and runtime-spawned actors are necessarily Movable.
//   - NoCollision components are NotEligible, not "movable-skipped" — the movable counter must not lie.
//
// Extraction is pure (BodySetup + component state, no Jolt world, no physics scene), so a throwaway
// editor world is enough. Editor world type is REQUIRED: SetStaticMesh on a Static-mobility component
// is rejected in game worlds.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_bake_mobility
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

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
    FCkTest_Jolt_BakeExtraction_MobilityPolicy,
    "Ck.Jolt.BakeExtraction.MobilityPolicy",
    ck_test_jolt_bake_mobility::kTestFlags)

bool FCkTest_Jolt_BakeExtraction_MobilityPolicy::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_mobility;

    // Shape building creates real JPH shapes, and this test runs in a bare editor world with no
    // Jolt subsystem — per CkJolt_Utils.h, worldless tests must ref the global Jolt init
    // themselves or JPH::Factory is null and shape creation access-violates.
    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    auto* StaticActor = Spawn_CubeActor(*World, EComponentMobility::Static);
    auto* MovableActor = Spawn_CubeActor(*World, EComponentMobility::Movable);
    if (NOT TestNotNull(TEXT("static cube actor spawned"), StaticActor) ||
        NOT TestNotNull(TEXT("movable cube actor spawned"), MovableActor))
    { return false; }

    if (NOT TestTrue(TEXT("static mesh component is registered (extraction precondition)"),
        StaticActor->GetStaticMeshComponent()->IsRegistered()))
    { return false; }

    // ---- Static + LevelSweep: baked, counted --------------------------------------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};

        const auto Num = ExtractActor(*StaticActor, Cache, Bodies, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("Static-mobility cube extracts one body under LevelSweep"), Num, 1);
        TestEqual(TEXT("stats: one component considered"), Stats._NumComponentsConsidered, 1);
        TestEqual(TEXT("stats: no movable skips"), Stats._NumComponentsSkippedMovable, 0);
        TestEqual(TEXT("stats: one body extracted"), Stats._NumBodiesExtracted, 1);
    }

    // ---- Movable + LevelSweep: skipped, and the skip is COUNTED -------------------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};

        const auto Num = ExtractActor(*MovableActor, Cache, Bodies, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("Movable-mobility cube extracts NOTHING under LevelSweep"), Num, 0);
        TestEqual(TEXT("stats: one component considered"), Stats._NumComponentsConsidered, 1);
        TestEqual(TEXT("stats: the movable skip is counted"), Stats._NumComponentsSkippedMovable, 1);
        TestEqual(TEXT("stats: no bodies extracted"), Stats._NumBodiesExtracted, 0);
    }

    // ---- Movable + ExplicitActor: baked (the Request_BakeActor contract) ----------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};

        const auto Num = ExtractActor(*MovableActor, Cache, Bodies, ECk_Jolt_ExtractionPolicy::ExplicitActor, &Stats);

        TestEqual(TEXT("Movable-mobility cube extracts one body under ExplicitActor"), Num, 1);
        TestEqual(TEXT("stats: no movable skips under ExplicitActor"), Stats._NumComponentsSkippedMovable, 0);
        TestEqual(TEXT("stats: one body extracted"), Stats._NumBodiesExtracted, 1);
    }

    // ---- NoCollision + LevelSweep: NotEligible, NOT counted as a movable skip -----------------------
    {
        StaticActor->GetStaticMeshComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);

        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};

        const auto Num = ExtractActor(*StaticActor, Cache, Bodies, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("NoCollision cube extracts nothing"), Num, 0);
        TestEqual(TEXT("stats: one component considered"), Stats._NumComponentsConsidered, 1);
        TestEqual(TEXT("stats: NoCollision is not a movable skip"), Stats._NumComponentsSkippedMovable, 0);
    }

    // ---- Stats accumulate across calls (the per-sweep aggregation path) -----------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};

        ExtractActor(*MovableActor, Cache, Bodies, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        ExtractActor(*MovableActor, Cache, Bodies, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("stats accumulate: two components considered"), Stats._NumComponentsConsidered, 2);
        TestEqual(TEXT("stats accumulate: two movable skips"), Stats._NumComponentsSkippedMovable, 2);
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
