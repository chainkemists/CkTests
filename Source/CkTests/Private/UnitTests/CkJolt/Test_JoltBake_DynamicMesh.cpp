#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include <Components/DynamicMeshComponent.h>
#include <Components/SphereComponent.h>
#include <DynamicMesh/DynamicMesh3.h>
#include <DynamicMeshActor.h>
#include <Engine/World.h>
#include <GameFramework/Actor.h>
#include <HAL/IConsoleManager.h>
#include <PhysicsEngine/BodySetup.h>
#include <Tests/AutomationCommon.h>

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>

// --------------------------------------------------------------------------------------------------------------------
// Locks the runtime-generated-geometry bake and the END of the extraction dispatch chain:
//
//   - A UDynamicMeshComponent derives UMeshComponent, NOT UStaticMeshComponent, so before the
//     explicit branch existed it fell off the end of ExtractComponent and produced ZERO bodies with
//     no ensure and no log. Silent absence is the defect these tests exist to prevent recurring.
//   - The down-ray probe pins the tri-mesh WINDING: Chaos and Jolt disagree, and Build_TriMeshShape
//     swaps b/c. A missed swap makes the quad face away and the down-ray hits nothing.
//   - The chain's terminal is policy-split: an ExplicitActor caller declared the geometry
//     static-in-intent, so an unsupported class must ensure; a LevelSweep legitimately visits every
//     primitive class in a map, so it stays a Verbose skip. Both halves are asserted.
//
// Extraction is pure (BodySetup + component state, no Jolt world), so a throwaway editor world is
// enough — but shape creation needs JPH::Factory, hence the global Jolt init.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_bake_dynamicmesh
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr double QuadZ = 50.0;
    constexpr double QuadExtent = 200.0;

    // A single Z-up quad (2 triangles) at height QuadZ spanning [0, QuadExtent] in X and Y.
    static auto Make_QuadMesh() -> UE::Geometry::FDynamicMesh3
    {
        auto Mesh = UE::Geometry::FDynamicMesh3{};

        const auto V0 = Mesh.AppendVertex(FVector3d{0.0, 0.0, QuadZ});
        const auto V1 = Mesh.AppendVertex(FVector3d{QuadExtent, 0.0, QuadZ});
        const auto V2 = Mesh.AppendVertex(FVector3d{QuadExtent, QuadExtent, QuadZ});
        const auto V3 = Mesh.AppendVertex(FVector3d{0.0, QuadExtent, QuadZ});

        // CCW seen from +Z, so the face normal points UP.
        Mesh.AppendTriangle(UE::Geometry::FIndex3i{V0, V1, V2});
        Mesh.AppendTriangle(UE::Geometry::FIndex3i{V0, V2, V3});

        return Mesh;
    }

    static auto Spawn_QuadDynamicMeshActor(
        UWorld& InWorld,
        bool InUseAsyncCooking)
        -> ADynamicMeshActor*
    {
        auto* Actor = InWorld.SpawnActor<ADynamicMeshActor>();
        if (Actor == nullptr)
        { return nullptr; }

        auto* Component = Actor->GetDynamicMeshComponent();
        if (Component == nullptr)
        { return nullptr; }

        Component->bUseAsyncCooking = InUseAsyncCooking;
        Component->SetCollisionProfileName(TEXT("BlockAll"));
        Component->SetMesh(Make_QuadMesh());

        constexpr auto OnlyIfPending = false;
        Component->SetComplexAsSimpleCollisionEnabled(true, OnlyIfPending);
        Component->UpdateCollision(OnlyIfPending);

        return Actor;
    }

    // Casts straight down in SHAPE space and returns the hit Z, or unset on miss. The actor sits at
    // the origin, so shape space and world space coincide here.
    static auto CastDownAt(const JPH::Shape& InShape, double InX, double InY) -> TOptional<double>
    {
        const auto RayStart = JPH::Vec3{static_cast<float>(InX), static_cast<float>(InY), 1000.0f};
        const auto RayDirection = JPH::Vec3{0.0f, 0.0f, -2000.0f};

        const auto Ray = JPH::RayCast{RayStart, RayDirection};
        auto Hit = JPH::RayCastResult{};

        if (NOT InShape.CastRay(Ray, JPH::SubShapeIDCreator{}, Hit))
        { return {}; }

        return 1000.0 - 2000.0 * Hit.mFraction;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_DynamicMesh_ComplexAsSimpleProducesBody,
    "Ck.Jolt.Bake.DynamicMesh.ComplexAsSimpleProducesBody",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_DynamicMesh_ComplexAsSimpleProducesBody::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    constexpr auto SynchronousCook = false;
    auto* Actor = Spawn_QuadDynamicMeshActor(*World, SynchronousCook);
    if (NOT TestNotNull(TEXT("dynamic mesh actor spawned"), Actor))
    { return false; }

    auto* Component = Actor->GetDynamicMeshComponent();
    if (NOT TestTrue(TEXT("dynamic mesh component is registered (extraction precondition)"),
        Component->IsRegistered()))
    { return false; }

    auto Cache = FCk_Jolt_ShapeCache{};
    auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};

    const auto NumExtracted = ExtractComponent(*Component, Cache, Bodies, {},
        ECk_Jolt_ExtractionPolicy::ExplicitActor);

    TestEqual(TEXT("dynamic mesh extracts exactly one body"), NumExtracted, 1);

    if (NOT TestEqual(TEXT("one extracted body is appended"), Bodies.Num(), 1))
    { return false; }

    if (NOT TestNotNull(TEXT("extracted body carries a shape"), Bodies[0]._Shape.GetPtr()))
    { return false; }

    // Winding + geometry: the quad's own surface must answer a down-ray at its center.
    {
        const auto HitZ = CastDownAt(*Bodies[0]._Shape, QuadExtent * 0.5, QuadExtent * 0.5);

        if (TestTrue(TEXT("down-ray at the quad center hits"), HitZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("hit height is ~{} (got {})"), QuadZ, *HitZ),
                FMath::Abs(*HitZ - QuadZ) <= 1.0);
        }
    }

    // The runtime-recooked BodySetup must NOT enter the guid-keyed shared cache: UpdateCollision
    // assigns a fresh guid per recook, so a cached entry per edit is a leak.
    TestEqual(TEXT("the dynamic mesh shape bypassed the shared shape cache"),
        Cache.Get_NumUniqueShapes(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_DynamicMesh_AsyncCookInFlightFailsLoudly,
    "Ck.Jolt.Bake.DynamicMesh.AsyncCookInFlightFailsLoudly",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_DynamicMesh_AsyncCookInFlightFailsLoudly::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // The bake cannot distinguish "cook still in flight" from "cooked and empty", so it refuses
    // LOUDLY rather than baking geometry that is silently stale or absent. A quiet retry here would
    // be a silent failure — the caller's contract is to bake after a synchronous UpdateCollision.
    // The refusal comes from the shared leaf builder, because component registration already
    // published an EMPTY setup (via the non-const accessor) that the queued cook has not replaced.
    // Match that exact wording, not a loose token: a broad pattern here also swallows this test's
    // OWN assertion failures, which turns a real failure into "failed, but no errors were logged".
    // Verified once by pinning an exact count and reading the failure: the refusal really does
    // fire here (the harness reported the message "found 2 time(s)" — ONE Ck ensure yields two
    // matching log lines). The committed expectation stays at the suite's -1 rather than 2,
    // because 2 encodes an ensure-logging internal that is invisible in the log (the harness
    // CONSUMES matched messages) and would strand the next reader. Re-prove loudness the same
    // way: set Occurrences to 1 and read the count back off the failure.
    AddExpectedError(TEXT("NO valid collision geometry"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    // bUseAsyncCooking alone is NOT enough in an editor world: RebuildPhysicsData ANDs it with
    // (IsGameWorld() || (IsEditorWorld() && this cvar)), and the cvar is off by default — so
    // without this the component silently takes the SYNCHRONOUS path and bakes fine.
    auto* AllowEditorAsyncCook = IConsoleManager::Get().FindConsoleVariable(
        TEXT("geometry.DynamicMesh.AllowAsyncCollisionBuildInEditor"));

    if (NOT TestNotNull(TEXT("editor async-collision cvar is found"), AllowEditorAsyncCook))
    { return false; }

    const auto RestoreAsyncCook = AllowEditorAsyncCook->GetBool();
    AllowEditorAsyncCook->Set(true);
    ON_SCOPE_EXIT { AllowEditorAsyncCook->Set(RestoreAsyncCook); };

    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    constexpr auto AsyncCook = true;
    auto* Actor = Spawn_QuadDynamicMeshActor(*World, AsyncCook);
    if (NOT TestNotNull(TEXT("dynamic mesh actor spawned"), Actor))
    { return false; }

    auto* Component = Actor->GetDynamicMeshComponent();

    // Pin the MECHANISM, not just the outcome. "Zero bodies" is also what an INELIGIBLE component
    // produces, so without these the assertions below would pass vacuously and this test would stop
    // guarding the refusal it exists for. Read through a CONST pointer: the non-const accessor
    // creates collision data on demand, which would destroy the very state under test.
    const auto* ConstComponent = Component;

    if (NOT TestTrue(TEXT("the component is eligible for extraction (collision is enabled)"),
        Component->GetCollisionEnabled() != ECollisionEnabled::NoCollision))
    { return false; }

    if (NOT TestTrue(TEXT("the component is registered (extraction precondition)"), Component->IsRegistered()))
    { return false; }

    const auto* PublishedCollision = ConstComponent->GetBodySetup();

    if (NOT TestNotNull(TEXT("registration published collision data the queued cook has not replaced"),
        PublishedCollision))
    { return false; }

    if (NOT TestEqual(TEXT("the published collision data carries NO cooked complex geometry — the state the bake must refuse"),
        PublishedCollision->TriMeshGeometries.Num(), 0))
    { return false; }

    auto Cache = FCk_Jolt_ShapeCache{};
    auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};

    const auto NumExtracted = ExtractComponent(*Component, Cache, Bodies, {},
        ECk_Jolt_ExtractionPolicy::ExplicitActor);

    TestEqual(TEXT("an in-flight async cook extracts NOTHING"), NumExtracted, 0);
    TestEqual(TEXT("no body is appended for an in-flight async cook"), Bodies.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_DynamicMesh_UnknownClassExtractsNothingQuietly,
    "Ck.Jolt.Bake.DynamicMesh.UnknownClassExtractsNothingQuietly",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_DynamicMesh_UnknownClassExtractsNothingQuietly::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // NO expected error is registered on purpose: extraction must stay QUIET for an unsupported class
    // under BOTH policies. Request_BakeComponent extracts under ExplicitActor even when the caller is
    // CkUnrealComponent's Automatic policy (a documented quiet skip), so ensuring here fires on ordinary
    // content — a shape component riding a baked entity — for every map that has one. Callers that
    // declared complete collision (BakeOnSetup) own the loud zero-body diagnosis instead. If this test
    // starts failing on an unexpected error, that layering has been broken again.
    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    auto* Actor = World->SpawnActor<AActor>();
    if (NOT TestNotNull(TEXT("host actor spawned"), Actor))
    { return false; }

    // A sphere component reaches the chain's terminal: it is collision-bearing (so the eligibility
    // gate admits it) but no branch claims it.
    auto* Sphere = NewObject<USphereComponent>(Actor);
    Actor->SetRootComponent(Sphere);
    Sphere->SetCollisionProfileName(TEXT("BlockAll"));
    Sphere->RegisterComponent();

    if (NOT TestTrue(TEXT("sphere component is registered (extraction precondition)"), Sphere->IsRegistered()))
    { return false; }

    // ---- ExplicitActor: extracts nothing, and does so QUIETLY ---------------------------------------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};

        const auto NumExtracted = ExtractComponent(*Sphere, Cache, Bodies, {},
            ECk_Jolt_ExtractionPolicy::ExplicitActor);

        TestEqual(TEXT("ExplicitActor: an unsupported class extracts NOTHING"), NumExtracted, 0);
        TestEqual(TEXT("ExplicitActor: no body is appended"), Bodies.Num(), 0);
    }

    // ---- LevelSweep: every primitive class in a map passes through here, so it stays quiet --------
    {
        auto Cache = FCk_Jolt_ShapeCache{};
        auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
        auto Stats = FCk_Jolt_ExtractionStats{};

        const auto NumExtracted = ExtractComponent(*Sphere, Cache, Bodies, {},
            ECk_Jolt_ExtractionPolicy::LevelSweep, &Stats);

        TestEqual(TEXT("LevelSweep: an unsupported class extracts NOTHING"), NumExtracted, 0);
        TestEqual(TEXT("LevelSweep: the component was considered, not filter-excluded"),
            Stats._NumComponentsExcludedByFilter, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
