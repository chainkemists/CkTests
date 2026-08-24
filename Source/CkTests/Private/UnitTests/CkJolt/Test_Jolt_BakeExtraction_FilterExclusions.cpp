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
// Locks the settings-driven bake-filter exclusions and their two companion contracts:
//
//   - Each exclusion axis (actor class, actor tag, component tag, object channel, collision profile,
//     overlap-only) removes the component/actor from the LEVEL SWEEP and is COUNTED in the stats.
//   - ExplicitActor (Request_BakeActor) ignores the filter entirely — an excluded actor explicitly
//     baked by a caller still bakes.
//   - HASH LOCKSTEP: the source hashes cover exactly the filtered population, and the filter's own
//     fingerprint (ComputeHash) is order-insensitive — the cooked index's staleness guard depends on
//     both.
//
// Same throwaway-editor-world recipe as Ck.Jolt.BakeExtraction.MobilityPolicy.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_bake_filter
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    static auto Spawn_CubeActor(
        UWorld& InWorld,
        const FName& InProfileName = TEXT("BlockAll"))
        -> AStaticMeshActor*
    {
        auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (Cube == nullptr)
        { return nullptr; }

        auto* Actor = InWorld.SpawnActor<AStaticMeshActor>();
        if (Actor == nullptr)
        { return nullptr; }

        auto* Component = Actor->GetStaticMeshComponent();
        Component->SetMobility(EComponentMobility::Static);
        Component->SetStaticMesh(Cube);
        Component->SetCollisionProfileName(InProfileName);
        Actor->RegisterAllComponents();

        return Actor;
    }

    static auto Extract_WithFilter(
        const AActor& InActor,
        const ck::jolt::bake::FCk_Jolt_BakeFilter& InFilter,
        ck::jolt::bake::FCk_Jolt_ExtractionStats& OutStats,
        ck::jolt::bake::ECk_Jolt_ExtractionPolicy InPolicy = ck::jolt::bake::ECk_Jolt_ExtractionPolicy::LevelSweep)
        -> int32
    {
        auto Cache = ck::jolt::bake::FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<ck::jolt::bake::FCk_Jolt_ExtractedBody>{};
        return ck::jolt::bake::ExtractActor(InActor, Cache, Bodies, InFilter, InPolicy, &OutStats);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Jolt_BakeExtraction_FilterExclusions,
    "Ck.Jolt.BakeExtraction.FilterExclusions",
    ck_test_jolt_bake_filter::kTestFlags)

bool FCkTest_Jolt_BakeExtraction_FilterExclusions::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_filter;

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    // ---- Baseline: an unfiltered cube bakes ---------------------------------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);
        if (NOT TestNotNull(TEXT("baseline cube spawned"), Actor))
        { return false; }

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, FCk_Jolt_BakeFilter{}, Stats);

        TestEqual(TEXT("baseline: cube extracts one body under the default filter"), Num, 1);
        TestEqual(TEXT("baseline: nothing excluded"), Stats._NumComponentsExcludedByFilter, 0);
    }

    // ---- Actor CLASS exclusion (IsChildOf semantics via a base class) -------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);

        auto Filter = FCk_Jolt_BakeFilter{};
        Filter._ExcludedActorClasses.Emplace(TStrongObjectPtr{AStaticMeshActor::StaticClass()});

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, Filter, Stats);

        TestEqual(TEXT("class exclusion: cube extracts nothing"), Num, 0);
        TestEqual(TEXT("class exclusion: the actor exclusion is counted"), Stats._NumActorsExcludedByFilter, 1);
        TestEqual(TEXT("class exclusion: no components were even considered"), Stats._NumComponentsConsidered, 0);
    }

    // ---- Actor TAG exclusion ------------------------------------------------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);
        Actor->Tags.Emplace(TEXT("Ck.Jolt.NoBake"));

        auto Filter = FCk_Jolt_BakeFilter{};
        Filter._ExcludedActorTags.Emplace(TEXT("Ck.Jolt.NoBake"));

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, Filter, Stats);

        TestEqual(TEXT("actor tag exclusion: cube extracts nothing"), Num, 0);
        TestEqual(TEXT("actor tag exclusion: the actor exclusion is counted"), Stats._NumActorsExcludedByFilter, 1);
    }

    // ---- Component TAG exclusion --------------------------------------------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);
        Actor->GetStaticMeshComponent()->ComponentTags.Emplace(TEXT("Ck.Jolt.NoBake"));

        auto Filter = FCk_Jolt_BakeFilter{};
        Filter._ExcludedComponentTags.Emplace(TEXT("Ck.Jolt.NoBake"));

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, Filter, Stats);

        TestEqual(TEXT("component tag exclusion: cube extracts nothing"), Num, 0);
        TestEqual(TEXT("component tag exclusion: the component exclusion is counted"),
            Stats._NumComponentsExcludedByFilter, 1);
        TestEqual(TEXT("component tag exclusion: the actor itself was not excluded"),
            Stats._NumActorsExcludedByFilter, 0);
    }

    // ---- Object CHANNEL exclusion -------------------------------------------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);
        Actor->GetStaticMeshComponent()->SetCollisionObjectType(ECC_WorldDynamic);

        auto Filter = FCk_Jolt_BakeFilter{};
        Filter._ExcludedObjectChannels.Emplace(ECC_WorldDynamic);

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, Filter, Stats);

        TestEqual(TEXT("channel exclusion: WorldDynamic cube extracts nothing"), Num, 0);
        TestEqual(TEXT("channel exclusion: counted"), Stats._NumComponentsExcludedByFilter, 1);

        // A WorldStatic cube is untouched by the same filter.
        auto* StaticChannelActor = Spawn_CubeActor(*World);
        auto OtherStats = FCk_Jolt_ExtractionStats{};
        TestEqual(TEXT("channel exclusion: WorldStatic cube still bakes"),
            Extract_WithFilter(*StaticChannelActor, Filter, OtherStats), 1);
    }

    // ---- Collision PROFILE exclusion ----------------------------------------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);

        auto Filter = FCk_Jolt_BakeFilter{};
        Filter._ExcludedCollisionProfiles.Emplace(TEXT("BlockAll"));

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, Filter, Stats);

        TestEqual(TEXT("profile exclusion: BlockAll cube extracts nothing"), Num, 0);
        TestEqual(TEXT("profile exclusion: counted"), Stats._NumComponentsExcludedByFilter, 1);
    }

    // ---- Overlap-only exclusion (opt-in) ------------------------------------------------------------
    {
        auto* TriggerActor = Spawn_CubeActor(*World, TEXT("OverlapAll"));
        if (NOT TestNotNull(TEXT("overlap-only cube spawned"), TriggerActor))
        { return false; }

        // The stock OverlapAll profile only sets the 8 ENGINE channels to Overlap — project custom
        // channels keep their own (often Block) defaults, and a body that blocks ANY channel is not
        // overlap-only. Force the effective setup to genuinely block nothing.
        TriggerActor->GetStaticMeshComponent()->SetCollisionResponseToAllChannels(ECR_Overlap);

        auto DisabledFilter = FCk_Jolt_BakeFilter{};
        auto DisabledStats = FCk_Jolt_ExtractionStats{};
        TestEqual(TEXT("overlap-only: baked while the exclusion is Disabled (default, UE parity)"),
            Extract_WithFilter(*TriggerActor, DisabledFilter, DisabledStats), 1);

        auto EnabledFilter = FCk_Jolt_BakeFilter{};
        EnabledFilter._ExcludeOverlapOnlyComponents = ECk_EnableDisable::Enable;
        auto EnabledStats = FCk_Jolt_ExtractionStats{};
        TestEqual(TEXT("overlap-only: excluded while Enabled"),
            Extract_WithFilter(*TriggerActor, EnabledFilter, EnabledStats), 0);
        TestEqual(TEXT("overlap-only: counted"), EnabledStats._NumComponentsExcludedByFilter, 1);

        // A blocking cube is untouched by the same filter.
        auto* BlockingActor = Spawn_CubeActor(*World);
        auto BlockingStats = FCk_Jolt_ExtractionStats{};
        TestEqual(TEXT("overlap-only: a blocking cube still bakes under the Enabled filter"),
            Extract_WithFilter(*BlockingActor, EnabledFilter, BlockingStats), 1);
    }

    // ---- ExplicitActor ignores the filter -----------------------------------------------------------
    {
        auto* Actor = Spawn_CubeActor(*World);
        Actor->Tags.Emplace(TEXT("Ck.Jolt.NoBake"));

        auto Filter = FCk_Jolt_BakeFilter{};
        Filter._ExcludedActorTags.Emplace(TEXT("Ck.Jolt.NoBake"));
        Filter._ExcludedActorClasses.Emplace(TStrongObjectPtr{AStaticMeshActor::StaticClass()});
        Filter._ExcludedCollisionProfiles.Emplace(TEXT("BlockAll"));

        auto Stats = FCk_Jolt_ExtractionStats{};
        const auto Num = Extract_WithFilter(*Actor, Filter, Stats, ECk_Jolt_ExtractionPolicy::ExplicitActor);

        TestEqual(TEXT("ExplicitActor: a fully-excluded actor still bakes"), Num, 1);
        TestEqual(TEXT("ExplicitActor: nothing counted as excluded"), Stats._NumActorsExcludedByFilter, 0);
    }

    // ---- Hash lockstep: the source hashes cover exactly the filtered population ---------------------
    {
        auto* Actor = Spawn_CubeActor(*World);

        const auto NoExclusions = FCk_Jolt_BakeFilter{};

        auto ExcludingFilter = FCk_Jolt_BakeFilter{};
        ExcludingFilter._ExcludedCollisionProfiles.Emplace(TEXT("BlockAll"));

        auto IrrelevantFilter = FCk_Jolt_BakeFilter{};
        IrrelevantFilter._ExcludedCollisionProfiles.Emplace(TEXT("SomeUnusedProfile"));

        const auto BaselineHash = ComputeSourceHash(*Actor, NoExclusions);
        const auto ExcludedHash = ComputeSourceHash(*Actor, ExcludingFilter);
        const auto IrrelevantHash = ComputeSourceHash(*Actor, IrrelevantFilter);

        TestNotEqual(TEXT("hash lockstep: excluding the only component changes the source hash"),
            BaselineHash, ExcludedHash);
        TestEqual(TEXT("hash lockstep: an exclusion that matches nothing leaves the source hash alone"),
            BaselineHash, IrrelevantHash);

        const auto RuntimeBaseline = ComputeRuntimeCheckHash(*Actor, NoExclusions);
        const auto RuntimeExcluded = ComputeRuntimeCheckHash(*Actor, ExcludingFilter);
        TestNotEqual(TEXT("hash lockstep: the runtime-check hash follows the same population"),
            RuntimeBaseline, RuntimeExcluded);
    }

    // ---- Filter fingerprint: sensitive to content, insensitive to order -----------------------------
    {
        const auto Default = FCk_Jolt_BakeFilter{};

        auto Restrictive = FCk_Jolt_BakeFilter{};
        Restrictive._MobilityPolicy = ECk_Jolt_BakeMobilityPolicy::StaticOnly;

        auto TagsAB = FCk_Jolt_BakeFilter{};
        TagsAB._ExcludedActorTags.Emplace(TEXT("TagA"));
        TagsAB._ExcludedActorTags.Emplace(TEXT("TagB"));

        auto TagsBA = FCk_Jolt_BakeFilter{};
        TagsBA._ExcludedActorTags.Emplace(TEXT("TagB"));
        TagsBA._ExcludedActorTags.Emplace(TEXT("TagA"));

        TestEqual(TEXT("filter hash: identical filters agree"),
            FCk_Jolt_BakeFilter{}.ComputeHash(), Default.ComputeHash());
        TestNotEqual(TEXT("filter hash: a policy change changes the fingerprint"),
            Default.ComputeHash(), Restrictive.ComputeHash());
        TestNotEqual(TEXT("filter hash: an added tag changes the fingerprint"),
            Default.ComputeHash(), TagsAB.ComputeHash());
        TestEqual(TEXT("filter hash: entry order does not matter"),
            TagsAB.ComputeHash(), TagsBA.ComputeHash());
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
