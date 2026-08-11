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
// Locks the level-sweep mobility POLICY and its observability contract:
//
//   - The default policy is All: Static, Stationary, AND Movable components all bake under LevelSweep.
//     A baked Movable is a snapshot at sweep time — parity with what Chaos blocks against at level load.
//   - StaticAndStationary skips Movable ones — and that skip is COUNTED in FCk_Jolt_ExtractionStats,
//     because it is the one a designer trips by accident under a restrictive policy (a Movable floor
//     silently vanishes from the Jolt static world while Chaos still blocks against it; this exact case
//     cost a debugging session in BusterBlock's Character_Gym).
//   - StaticOnly additionally skips Stationary.
//   - ExplicitActor (the Request_BakeActor path) ignores the filter entirely: the caller declared the
//     actor static-in-intent, and runtime-spawned actors are necessarily Movable.
//   - NoCollision components are NotEligible, not "mobility-excluded" — the mobility counter must not lie.
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

    static auto Make_FilterWithPolicy(
        ECk_Jolt_BakeMobilityPolicy InPolicy)
        -> ck::jolt::bake::FCk_Jolt_BakeFilter
    {
        auto Filter = ck::jolt::bake::FCk_Jolt_BakeFilter{};
        Filter._MobilityPolicy = InPolicy;
        return Filter;
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
    auto* StationaryActor = Spawn_CubeActor(*World, EComponentMobility::Stationary);
    auto* MovableActor = Spawn_CubeActor(*World, EComponentMobility::Movable);
    if (NOT TestNotNull(TEXT("static cube actor spawned"), StaticActor) ||
        NOT TestNotNull(TEXT("stationary cube actor spawned"), StationaryActor) ||
        NOT TestNotNull(TEXT("movable cube actor spawned"), MovableActor))
    { return false; }

    if (NOT TestTrue(TEXT("static mesh component is registered (extraction precondition)"),
        StaticActor->GetStaticMeshComponent()->IsRegistered()))
    { return false; }

    // ---- Default filter (policy All): every mobility bakes under LevelSweep -------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Filter = FCk_Jolt_BakeFilter{};

        const auto NumStatic = ExtractActor(*StaticActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        const auto NumStationary = ExtractActor(*StationaryActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        const auto NumMovable = ExtractActor(*MovableActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("All: Static cube extracts one body"), NumStatic, 1);
        TestEqual(TEXT("All: Stationary cube extracts one body"), NumStationary, 1);
        TestEqual(TEXT("All: Movable cube extracts one body"), NumMovable, 1);
        TestEqual(TEXT("All: three components considered"), Stats._NumComponentsConsidered, 3);
        TestEqual(TEXT("All: no mobility exclusions"), Stats._NumComponentsExcludedByMobility, 0);
        TestEqual(TEXT("All: three bodies extracted"), Stats._NumBodiesExtracted, 3);
    }

    // ---- StaticAndStationary: Movable is skipped, and the skip is COUNTED ---------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Filter = Make_FilterWithPolicy(ECk_Jolt_BakeMobilityPolicy::StaticAndStationary);

        const auto NumStationary = ExtractActor(*StationaryActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        const auto NumMovable = ExtractActor(*MovableActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("StaticAndStationary: Stationary cube extracts one body"), NumStationary, 1);
        TestEqual(TEXT("StaticAndStationary: Movable cube extracts NOTHING"), NumMovable, 0);
        TestEqual(TEXT("StaticAndStationary: the mobility exclusion is counted"),
            Stats._NumComponentsExcludedByMobility, 1);
        TestEqual(TEXT("StaticAndStationary: no filter exclusions"), Stats._NumComponentsExcludedByFilter, 0);
    }

    // ---- StaticOnly: Stationary AND Movable are skipped ---------------------------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Filter = Make_FilterWithPolicy(ECk_Jolt_BakeMobilityPolicy::StaticOnly);

        const auto NumStatic = ExtractActor(*StaticActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        const auto NumStationary = ExtractActor(*StationaryActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        const auto NumMovable = ExtractActor(*MovableActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("StaticOnly: Static cube extracts one body"), NumStatic, 1);
        TestEqual(TEXT("StaticOnly: Stationary cube extracts NOTHING"), NumStationary, 0);
        TestEqual(TEXT("StaticOnly: Movable cube extracts NOTHING"), NumMovable, 0);
        TestEqual(TEXT("StaticOnly: both mobility exclusions are counted"),
            Stats._NumComponentsExcludedByMobility, 2);
    }

    // ---- Movable + ExplicitActor: baked even under a restrictive filter -----------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Filter = Make_FilterWithPolicy(ECk_Jolt_BakeMobilityPolicy::StaticOnly);

        const auto Num = ExtractActor(*MovableActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::ExplicitActor, &Stats);

        TestEqual(TEXT("Movable cube extracts one body under ExplicitActor"), Num, 1);
        TestEqual(TEXT("stats: no mobility exclusions under ExplicitActor"),
            Stats._NumComponentsExcludedByMobility, 0);
        TestEqual(TEXT("stats: one body extracted"), Stats._NumBodiesExtracted, 1);
    }

    // ---- NoCollision + LevelSweep: NotEligible, NOT counted as a mobility exclusion -----------------
    {
        StaticActor->GetStaticMeshComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);

        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Filter = Make_FilterWithPolicy(ECk_Jolt_BakeMobilityPolicy::StaticOnly);

        const auto Num = ExtractActor(*StaticActor, Cache, Bodies, Filter,
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("NoCollision cube extracts nothing"), Num, 0);
        TestEqual(TEXT("stats: one component considered"), Stats._NumComponentsConsidered, 1);
        TestEqual(TEXT("stats: NoCollision is not a mobility exclusion"),
            Stats._NumComponentsExcludedByMobility, 0);
    }

    // ---- Stats accumulate across calls (the per-sweep aggregation path) -----------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Filter = Make_FilterWithPolicy(ECk_Jolt_BakeMobilityPolicy::StaticAndStationary);

        ExtractActor(*MovableActor, Cache, Bodies, Filter, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);
        ExtractActor(*MovableActor, Cache, Bodies, Filter, ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("stats accumulate: two components considered"), Stats._NumComponentsConsidered, 2);
        TestEqual(TEXT("stats accumulate: two mobility exclusions"), Stats._NumComponentsExcludedByMobility, 2);
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
