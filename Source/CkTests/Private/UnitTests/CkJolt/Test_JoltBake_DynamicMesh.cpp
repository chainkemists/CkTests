#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include <Components/DynamicMeshComponent.h>
#include <Components/SphereComponent.h>
#include <DynamicMesh/DynamicMesh3.h>
#include <DynamicMeshActor.h>
#include <Engine/StaticMesh.h>
#include <Engine/World.h>
#include <GameFramework/Actor.h>
#include <HAL/IConsoleManager.h>
#include <PhysicsEngine/BodySetup.h>
#include <Tests/AutomationCommon.h>

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>

// --------------------------------------------------------------------------------------------------------------------
// Locks the runtime-generated-geometry bake and the END of the extraction dispatch chain:
//
//   - A UDynamicMeshComponent derives UMeshComponent, NOT UStaticMeshComponent, so before the
//     explicit branch existed it fell off the end of ExtractComponent and produced ZERO bodies with
//     no ensure and no log. Silent absence is the defect these tests exist to prevent recurring.
//   - The down-ray probes pin the tri-mesh WINDING: UE authors front faces left-handed, the Chaos
//     cook's bFlipNormals stores them right-handed (= Jolt's convention), and Build_TriMeshShape
//     copies that stored order as-is. An extra flip anywhere in the chain bakes inside-out — which
//     shipped for months because these fixtures were originally authored right-handed, cancelling
//     the bake's then-extra b/c swap. Fixtures are now authored in UE convention.
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

        // UE authors front faces LEFT-handed (VectorUtil::Normal reverses its cross product and says
        // why), so the UP-facing winding is (V0,V2,V1) — the right-handed CCW order (V0,V1,V2) is the
        // DOWN-facing back side. This fixture's original right-handed authoring was one half of the
        // cancelling-errors pair that hid the bake's winding flip.
        Mesh.AppendTriangle(UE::Geometry::FIndex3i{V0, V2, V1});
        Mesh.AppendTriangle(UE::Geometry::FIndex3i{V0, V3, V2});

        return Mesh;
    }

    constexpr double CubeExtent = 100.0;

    // Corners of an axis-aligned cube spanning [0, CubeExtent]^3, and its face table wound outward
    // under the RIGHT-handed cross (every face verified: Cross(b-a, c-a) points away from the cube
    // center). Right-handed is JOLT's front-face convention, so the raw-list metric fixtures use the
    // table as-is; UE authors front faces LEFT-handed, so Make_CubeMesh REVERSES it for its healthy
    // cube.
    static const FVector3d kCubeCorners[8] = {
        {0.0, 0.0, 0.0}, {CubeExtent, 0.0, 0.0}, {CubeExtent, CubeExtent, 0.0}, {0.0, CubeExtent, 0.0},
        {0.0, 0.0, CubeExtent}, {CubeExtent, 0.0, CubeExtent}, {CubeExtent, CubeExtent, CubeExtent}, {0.0, CubeExtent, CubeExtent}};

    static const int32 kCubeOutwardFaces[12][3] = {
        {0, 2, 1}, {0, 3, 2},   // bottom (-Z)
        {4, 5, 6}, {4, 6, 7},   // top (+Z)
        {0, 1, 5}, {0, 5, 4},   // -Y
        {3, 7, 6}, {3, 6, 2},   // +Y
        {0, 4, 7}, {0, 7, 3},   // -X
        {1, 2, 6}, {1, 6, 5}};  // +X

    // A closed cube spanning [0, CubeExtent]^3 — outward-wound in UE's LEFT-handed authoring
    // convention (the reversed right-handed table), or fully INSIDE-OUT.
    static auto Make_CubeMesh(bool InInverted) -> UE::Geometry::FDynamicMesh3
    {
        auto Mesh = UE::Geometry::FDynamicMesh3{};

        int32 VertexIds[8] = {};
        for (auto Index = 0; Index < 8; ++Index)
        { VertexIds[Index] = Mesh.AppendVertex(kCubeCorners[Index]); }

        for (const auto& Face : kCubeOutwardFaces)
        {
            if (InInverted)
            { Mesh.AppendTriangle(UE::Geometry::FIndex3i{VertexIds[Face[0]], VertexIds[Face[1]], VertexIds[Face[2]]}); }
            else
            { Mesh.AppendTriangle(UE::Geometry::FIndex3i{VertexIds[Face[0]], VertexIds[Face[2]], VertexIds[Face[1]]}); }
        }

        return Mesh;
    }

    static auto Spawn_DynamicMeshActor(
        UWorld& InWorld,
        UE::Geometry::FDynamicMesh3&& InMesh,
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
        Component->SetMesh(MoveTemp(InMesh));

        constexpr auto OnlyIfPending = false;
        Component->SetComplexAsSimpleCollisionEnabled(true, OnlyIfPending);
        Component->UpdateCollision(OnlyIfPending);

        return Actor;
    }

    static auto Spawn_QuadDynamicMeshActor(
        UWorld& InWorld,
        bool InUseAsyncCooking)
        -> ADynamicMeshActor*
    {
        return Spawn_DynamicMeshActor(InWorld, Make_QuadMesh(), InUseAsyncCooking);
    }

    // A ray that IGNORES BACK FACES — the only cast that can measure winding. Jolt's simple
    // Shape::CastRay overload is double-sided for mesh triangles (measured: an inside-out quad
    // answered it from both sides), so winding assertions must go through the RayCastSettings
    // variant with an explicit back-face mode.
    static auto CastRay_FrontFacesOnly(
        const JPH::Shape& InShape,
        JPH::Vec3 InStart,
        JPH::Vec3 InDirection) -> TOptional<float>
    {
        const auto Ray = JPH::RayCast{InStart, InDirection};

        auto Settings = JPH::RayCastSettings{};
        Settings.SetBackFaceMode(JPH::EBackFaceMode::IgnoreBackFaces);

        auto Collector = JPH::ClosestHitCollisionCollector<JPH::CastRayCollector>{};
        InShape.CastRay(Ray, Settings, JPH::SubShapeIDCreator{}, Collector);

        if (NOT Collector.HadHit())
        { return {}; }

        return Collector.mHit.mFraction;
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

    static auto HaveSameTriangleIndices(
        const JPH::IndexedTriangleList& InLeft,
        const JPH::IndexedTriangleList& InRight) -> bool
    {
        if (InLeft.size() != InRight.size())
        { return false; }

        for (size_t Index = 0; Index < InLeft.size(); ++Index)
        {
            for (int32 Corner = 0; Corner < 3; ++Corner)
            {
                if (InLeft[Index].mIdx[Corner] != InRight[Index].mIdx[Corner])
                { return false; }
            }
        }
        return true;
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

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

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
    FCkTest_JoltBake_DynamicMesh_MirroredScaleKeepsWindingOutward,
    "Ck.Jolt.Bake.DynamicMesh.MirroredScaleKeepsWindingOutward",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_DynamicMesh_MirroredScaleKeepsWindingOutward::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // A mirroring scale (negative determinant) flips the handedness of the vertices that
    // Build_TriMeshShape bakes, so the index order must flip WITH it or the mirrored instance
    // bakes INSIDE-OUT: single-sided mesh collision and the CCD LinearCast (back-face-ignoring)
    // both miss it from its visually-front side — level designers mirror wall pieces routinely,
    // and a thrown item passed straight through exactly those instances. The down-ray pins the
    // compensation; the up-ray pins that the mesh stayed SINGLE-sided (the compensation flips
    // winding, it does not double-side the mesh).
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    constexpr auto SynchronousCook = false;
    auto* Actor = Spawn_QuadDynamicMeshActor(*World, SynchronousCook);
    if (NOT TestNotNull(TEXT("dynamic mesh actor spawned"), Actor))
    { return false; }

    Actor->SetActorScale3D(FVector{-1.0, 1.0, 1.0});

    auto* Component = Actor->GetDynamicMeshComponent();
    if (NOT TestTrue(TEXT("dynamic mesh component is registered (extraction precondition)"),
        Component->IsRegistered()))
    { return false; }

    if (NOT TestTrue(TEXT("the component transform carries the mirroring scale (test precondition)"),
        Component->GetComponentTransform().GetScale3D().X < 0.0))
    { return false; }

    auto Cache = FCk_Jolt_ShapeCache{};
    auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};

    const auto NumExtracted = ExtractComponent(*Component, Cache, Bodies, {},
        ECk_Jolt_ExtractionPolicy::ExplicitActor);

    if (NOT TestEqual(TEXT("mirrored dynamic mesh extracts exactly one body"), NumExtracted, 1))
    { return false; }

    if (NOT TestNotNull(TEXT("extracted body carries a shape"), Bodies[0]._Shape.GetPtr()))
    { return false; }

    // X is negated by the baked scale, so the quad now spans [-QuadExtent, 0] in X.
    const auto MirroredCenterX = -QuadExtent * 0.5;
    const auto CenterY = QuadExtent * 0.5;

    // Both probes go through the back-face-CULLING cast — the simple CastRay overload is
    // double-sided for mesh triangles and cannot see winding at all (measured: it failed this
    // test's first authoring by answering from below too).
    //
    // Winding compensation: the +Z face must answer a culled down-ray...
    {
        const auto DownStart = JPH::Vec3{
            static_cast<float>(MirroredCenterX), static_cast<float>(CenterY), 1000.0f};
        const auto DownFraction = CastRay_FrontFacesOnly(
            *Bodies[0]._Shape, DownStart, JPH::Vec3{0.0f, 0.0f, -2000.0f});

        if (TestTrue(TEXT("culled down-ray at the mirrored quad center hits (winding compensated for the mirroring scale)"),
            DownFraction.IsSet()))
        {
            const auto HitZ = 1000.0 - 2000.0 * *DownFraction;
            TestTrue(ck::Format_UE(TEXT("hit height is ~{} (got {})"), QuadZ, HitZ),
                FMath::Abs(HitZ - QuadZ) <= 1.0);
        }
    }

    // ...and the SAME culled cast from below must miss: the fix flips winding, it does not
    // double-side the mesh.
    {
        const auto UpStart = JPH::Vec3{
            static_cast<float>(MirroredCenterX), static_cast<float>(CenterY), -1000.0f};
        const auto UpFraction = CastRay_FrontFacesOnly(
            *Bodies[0]._Shape, UpStart, JPH::Vec3{0.0f, 0.0f, 2000.0f});

        TestFalse(TEXT("culled up-ray from below misses (single-sided, facing +Z)"),
            UpFraction.IsSet());
    }

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

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

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
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

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

namespace ck_test_jolt_bake_dynamicmesh
{
    // Raw JPH lists for the shared cube — the same geometry Make_CubeMesh authors, expressed in the
    // types ComputeMeshWindingRatio consumes directly (no world, no cook).
    static auto Fill_CubeLists(
        JPH::VertexList& OutVertices,
        JPH::IndexedTriangleList& OutTriangles,
        double InOffset,
        bool InInverted)
        -> void
    {
        OutVertices.clear();
        OutTriangles.clear();

        for (const auto& Corner : kCubeCorners)
        {
            OutVertices.push_back(JPH::Float3(
                static_cast<float>(Corner.X + InOffset),
                static_cast<float>(Corner.Y + InOffset),
                static_cast<float>(Corner.Z + InOffset)));
        }

        for (const auto& Face : kCubeOutwardFaces)
        {
            if (InInverted)
            { OutTriangles.push_back(JPH::IndexedTriangle(Face[0], Face[2], Face[1])); }
            else
            { OutTriangles.push_back(JPH::IndexedTriangle(Face[0], Face[1], Face[2])); }
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_TriMesh_WindingRatioIsSignedAndNormalized,
    "Ck.Jolt.Bake.TriMesh.WindingRatioIsSignedAndNormalized",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_TriMesh_WindingRatioIsSignedAndNormalized::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // Pins the metric the inside-out ensure gates on: sign = winding verdict (+ outward, - inverted),
    // magnitude = enclosed/AABB volume (a solid cube is exactly 1), measured about the AABB CENTER so
    // the verdict survives translation, and 0 for anything flat — 0 is "no verdict", never "healthy".
    //
    // No shapes are created here, but JPH::Array allocates through Jolt's installed allocator — a
    // null function pointer until global init runs. Without this scope the test dies on 0xC0000005
    // at the first push_back (measured), not at any Jolt API call.
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto Vertices = JPH::VertexList{};
    auto Triangles = JPH::IndexedTriangleList{};

    {
        Fill_CubeLists(Vertices, Triangles, 0.0, false);
        const auto Ratio = ComputeMeshWindingRatio(Vertices, Triangles);
        TestTrue(ck::Format_UE(TEXT("outward cube measures ~+1 (got {})"), Ratio),
            FMath::Abs(Ratio - 1.0) <= 0.01);
    }

    {
        Fill_CubeLists(Vertices, Triangles, 0.0, true);
        const auto Ratio = ComputeMeshWindingRatio(Vertices, Triangles);
        TestTrue(ck::Format_UE(TEXT("inside-out cube measures ~-1 (got {})"), Ratio),
            FMath::Abs(Ratio + 1.0) <= 0.01);
    }

    {
        // Far from the origin: an origin-anchored signed volume would dwarf the real verdict here.
        Fill_CubeLists(Vertices, Triangles, 10000.0, false);
        const auto Ratio = ComputeMeshWindingRatio(Vertices, Triangles);
        TestTrue(ck::Format_UE(TEXT("translated outward cube still measures ~+1 (got {})"), Ratio),
            FMath::Abs(Ratio - 1.0) <= 0.01);
    }

    {
        // An open flat quad, deliberately OFF the ground plane: flat AABB -> no verdict.
        Vertices.clear();
        Triangles.clear();
        Vertices.push_back(JPH::Float3(0.0f, 0.0f, 50.0f));
        Vertices.push_back(JPH::Float3(200.0f, 0.0f, 50.0f));
        Vertices.push_back(JPH::Float3(200.0f, 200.0f, 50.0f));
        Vertices.push_back(JPH::Float3(0.0f, 200.0f, 50.0f));
        Triangles.push_back(JPH::IndexedTriangle(0, 1, 2));
        Triangles.push_back(JPH::IndexedTriangle(0, 2, 3));

        const auto Ratio = ComputeMeshWindingRatio(Vertices, Triangles);
        TestEqual(TEXT("an open flat quad measures exactly 0 (no verdict)"), Ratio, 0.0);
    }

    {
        Vertices.clear();
        Triangles.clear();
        const auto Ratio = ComputeMeshWindingRatio(Vertices, Triangles);
        TestEqual(TEXT("empty input measures exactly 0 (no verdict)"), Ratio, 0.0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_TriMesh_WindingNormalization,
    "Ck.Jolt.Bake.TriMesh.WindingNormalization",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_TriMesh_WindingNormalization::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};
    auto Vertices = JPH::VertexList{};
    auto Triangles = JPH::IndexedTriangleList{};

    Fill_CubeLists(Vertices, Triangles, 0.0, false);
    const auto OutwardBefore = Triangles;
    const auto Outward = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("outward closed cube stays unchanged"), Outward._Status,
        ECk_Jolt_WindingNormalizationStatus::Unchanged);
    TestEqual(TEXT("outward closed cube needs no repair"), Outward._NumRepairedComponents, 0);
    TestTrue(TEXT("outward closed cube indices remain unchanged"),
        HaveSameTriangleIndices(Triangles, OutwardBefore));

    Fill_CubeLists(Vertices, Triangles, 10000.0, true);
    const auto Inverted = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("translated inverted closed cube is repaired"), Inverted._Status,
        ECk_Jolt_WindingNormalizationStatus::Normalized);
    TestEqual(TEXT("one translated closed component is repaired"), Inverted._NumRepairedComponents, 1);
    TestTrue(TEXT("repaired translated cube has positive winding"),
        ComputeMeshWindingRatio(Vertices, Triangles) > 0.9);

    Vertices.clear();
    Triangles.clear();
    Vertices.push_back(JPH::Float3(0, 0, 0));
    Vertices.push_back(JPH::Float3(1, 0, 0));
    Vertices.push_back(JPH::Float3(0, 1, 0));
    Triangles.push_back(JPH::IndexedTriangle(0, 1, 2));
    const auto OpenBefore = Triangles;
    const auto Open = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("open mesh has no normalization verdict"), Open._Status,
        ECk_Jolt_WindingNormalizationStatus::NoVerdict);
    TestEqual(TEXT("open mesh is reported"), Open._NumOpenComponents, 1);
    TestTrue(TEXT("open mesh remains unchanged"), HaveSameTriangleIndices(Triangles, OpenBefore));

    Triangles[0] = JPH::IndexedTriangle(0, 1, 99);
    const auto MalformedBefore = Triangles;
    const auto Malformed = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("malformed indices fail closed"), Malformed._Status,
        ECk_Jolt_WindingNormalizationStatus::Malformed);
    TestEqual(TEXT("malformed component is reported"), Malformed._NumMalformedComponents, 1);
    TestTrue(TEXT("malformed index failure is explicit"), Malformed.Get_HasMalformedIndices());
    TestTrue(TEXT("malformed triangles remain unchanged"), HaveSameTriangleIndices(Triangles, MalformedBefore));

    Fill_CubeLists(Vertices, Triangles, 0.0, true);
    Triangles.push_back(JPH::IndexedTriangle(0, 0, 1));
    const auto RepeatedIndexBefore = Triangles;
    const auto RepeatedIndex = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("repeated indices fail closed"), RepeatedIndex._Status,
        ECk_Jolt_WindingNormalizationStatus::Malformed);
    TestEqual(TEXT("repeated index component is reported"), RepeatedIndex._NumMalformedIndexComponents, 1);
    TestTrue(TEXT("malformed preflight prevents partial repair"),
        HaveSameTriangleIndices(Triangles, RepeatedIndexBefore));

    Fill_CubeLists(Vertices, Triangles, 0.0, true);
    Triangles.erase(Triangles.end() - 2, Triangles.end());
    const auto OpenNegativeBefore = Triangles;
    const auto OpenNegative = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("open negative component repairs"), OpenNegative._Status,
        ECk_Jolt_WindingNormalizationStatus::Normalized);
    TestEqual(TEXT("open negative component is reported"), OpenNegative._NumOpenComponents, 1);
    TestEqual(TEXT("open negative component repairs once"), OpenNegative._NumRepairedComponents, 1);
    TestFalse(TEXT("open negative indices are reversed"),
        HaveSameTriangleIndices(Triangles, OpenNegativeBefore));
    TestTrue(TEXT("repaired open component has positive winding"),
        ComputeMeshWindingRatio(Vertices, Triangles) > 0.05);

    Fill_CubeLists(Vertices, Triangles, 0.0, true);
    const auto DuplicateTriangle = Triangles[0];
    Triangles.push_back(DuplicateTriangle);
    const auto NonManifoldBefore = Triangles;
    const auto NonManifold = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("non-manifold negative component repairs"), NonManifold._Status,
        ECk_Jolt_WindingNormalizationStatus::Normalized);
    TestEqual(TEXT("non-manifold component is reported"), NonManifold._NumNonManifoldComponents, 1);
    TestEqual(TEXT("non-manifold negative component repairs once"), NonManifold._NumRepairedComponents, 1);
    TestFalse(TEXT("non-manifold indices are reversed"), HaveSameTriangleIndices(Triangles, NonManifoldBefore));

    Fill_CubeLists(Vertices, Triangles, 0.0, false);
    const auto OutwardDuplicateTriangle = Triangles[0];
    Triangles.push_back(OutwardDuplicateTriangle);
    const auto NonManifoldPositiveBefore = Triangles;
    const auto NonManifoldPositive = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("positive non-manifold component stays unchanged"), NonManifoldPositive._Status,
        ECk_Jolt_WindingNormalizationStatus::Unchanged);
    TestEqual(TEXT("positive non-manifold component is reported"),
        NonManifoldPositive._NumNonManifoldComponents, 1);
    TestTrue(TEXT("positive non-manifold indices remain unchanged"),
        HaveSameTriangleIndices(Triangles, NonManifoldPositiveBefore));

    Fill_CubeLists(Vertices, Triangles, 0.0, true);
    Swap(Triangles[0].mIdx[1], Triangles[0].mIdx[2]);
    const auto InconsistentBefore = Triangles;
    const auto Inconsistent = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("inconsistent negative component repairs"), Inconsistent._Status,
        ECk_Jolt_WindingNormalizationStatus::Normalized);
    TestEqual(TEXT("inconsistent component is reported"), Inconsistent._NumInconsistentComponents, 1);
    TestEqual(TEXT("inconsistent negative component repairs once"), Inconsistent._NumRepairedComponents, 1);
    TestFalse(TEXT("inconsistent indices are reversed"), HaveSameTriangleIndices(Triangles, InconsistentBefore));

    Fill_CubeLists(Vertices, Triangles, 0.0, false);
    auto InvertedVertices = JPH::VertexList{};
    auto InvertedTriangles = JPH::IndexedTriangleList{};
    Fill_CubeLists(InvertedVertices, InvertedTriangles, 1000.0, true);
    for (const auto& Vertex : InvertedVertices)
    { Vertices.push_back(Vertex); }
    for (const auto& Triangle : InvertedTriangles)
    {
        Triangles.push_back(JPH::IndexedTriangle(
            Triangle.mIdx[0] + 8, Triangle.mIdx[1] + 8, Triangle.mIdx[2] + 8));
    }
    const auto Mixed = NormalizeInsideOutMeshComponents(Vertices, Triangles);
    TestEqual(TEXT("mixed disconnected components normalize"), Mixed._Status,
        ECk_Jolt_WindingNormalizationStatus::Normalized);
    TestEqual(TEXT("mixed disconnected components preserve healthy component"), Mixed._NumHealthyComponents, 1);
    TestEqual(TEXT("mixed disconnected components repair only inverted component"), Mixed._NumRepairedComponents, 1);
    TestTrue(TEXT("mixed disconnected components finish outward"),
        ComputeMeshWindingRatio(Vertices, Triangles) > 0.0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_DynamicMesh_OutwardClosedMeshBakesQuietly,
    "Ck.Jolt.Bake.DynamicMesh.OutwardClosedMeshBakesQuietly",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_DynamicMesh_OutwardClosedMeshBakesQuietly::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // NO expected error is registered on purpose: this pins the bake's winding SIGN CONVENTION
    // end-to-end. Outward-authored geometry must still measure outward after the Chaos cook and the
    // Chaos->Jolt b/c swap — if either ever flips convention, the inside-out ensure fires on this
    // healthy cube and this test fails on the unexpected error. The culled down-ray then pins that
    // "outward" really is outward: the TOP face answers from above.
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    constexpr auto SynchronousCook = false;
    auto* Actor = Spawn_DynamicMeshActor(*World, Make_CubeMesh(false), SynchronousCook);
    if (NOT TestNotNull(TEXT("cube dynamic mesh actor spawned"), Actor))
    { return false; }

    auto Cache = FCk_Jolt_ShapeCache{};
    auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};

    const auto NumExtracted = ExtractComponent(*Actor->GetDynamicMeshComponent(), Cache, Bodies, {},
        ECk_Jolt_ExtractionPolicy::ExplicitActor);

    if (NOT TestEqual(TEXT("outward cube extracts exactly one body"), NumExtracted, 1))
    { return false; }

    if (NOT TestNotNull(TEXT("extracted body carries a shape"), Bodies[0]._Shape.GetPtr()))
    { return false; }

    const auto DownStart = JPH::Vec3{
        static_cast<float>(CubeExtent * 0.5), static_cast<float>(CubeExtent * 0.5), 1000.0f};
    const auto DownFraction = CastRay_FrontFacesOnly(
        *Bodies[0]._Shape, DownStart, JPH::Vec3{0.0f, 0.0f, -2000.0f});

    if (TestTrue(TEXT("culled down-ray hits the outward cube from above"), DownFraction.IsSet()))
    {
        const auto HitZ = 1000.0 - 2000.0 * *DownFraction;
        TestTrue(ck::Format_UE(TEXT("hit is the TOP face at ~{} (got {})"), CubeExtent, HitZ),
            FMath::Abs(HitZ - CubeExtent) <= 1.0);
    }

    // The shape-walk form of the metric (the one that audits restored pre-baked blobs) must agree.
    // Tolerance is looser than the list form's: MeshShape stores block-quantized vertices.
    {
        const auto ShapeRatio = ComputeShapeWindingRatio(*Bodies[0]._Shape);
        TestTrue(ck::Format_UE(TEXT("shape-walk ratio of the outward cube is ~+1 (got {})"), ShapeRatio),
            FMath::Abs(ShapeRatio - 1.0) <= 0.05);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_DynamicMesh_InsideOutClosedMeshRepairsQuietly,
    "Ck.Jolt.Bake.DynamicMesh.InsideOutClosedMeshRepairsQuietly",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_DynamicMesh_InsideOutClosedMeshRepairsQuietly::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // A fully inverted closed component is now normalized before the shape is created. No expected
    // error is registered: repair is intentional and must stay quiet.

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();

    constexpr auto SynchronousCook = false;
    auto* Actor = Spawn_DynamicMeshActor(*World, Make_CubeMesh(true), SynchronousCook);
    if (NOT TestNotNull(TEXT("inverted cube dynamic mesh actor spawned"), Actor))
    { return false; }

    auto Cache = FCk_Jolt_ShapeCache{};
    auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};

    const auto NumExtracted = ExtractComponent(*Actor->GetDynamicMeshComponent(), Cache, Bodies, {},
        ECk_Jolt_ExtractionPolicy::ExplicitActor);

    TestEqual(TEXT("the inside-out cube repairs and bakes one body"), NumExtracted, 1);

    if (NOT TestEqual(TEXT("one extracted body is appended"), Bodies.Num(), 1))
    { return false; }

    if (NOT TestNotNull(TEXT("extracted body carries a shape"), Bodies[0]._Shape.GetPtr()))
    { return false; }

    const auto DownStart = JPH::Vec3{
        static_cast<float>(CubeExtent * 0.5), static_cast<float>(CubeExtent * 0.5), 1000.0f};
    const auto DownFraction = CastRay_FrontFacesOnly(
        *Bodies[0]._Shape, DownStart, JPH::Vec3{0.0f, 0.0f, -2000.0f});

    if (TestTrue(TEXT("culled down-ray hits repaired top face from above"), DownFraction.IsSet()))
    {
        const auto HitZ = 1000.0 - 2000.0 * *DownFraction;
        TestTrue(ck::Format_UE(TEXT("the hit is the TOP face at ~{} (got {})"), CubeExtent, HitZ),
            FMath::Abs(HitZ - CubeExtent) <= 1.0);
    }

    {
        const auto ShapeRatio = ComputeShapeWindingRatio(*Bodies[0]._Shape);
        TestTrue(ck::Format_UE(TEXT("shape-walk ratio of repaired cube is positive (got {})"), ShapeRatio),
            ShapeRatio > 0.9);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_StaticMesh_EngineCubeTriMeshBakesOutward,
    "Ck.Jolt.Bake.StaticMesh.EngineCubeTriMeshBakesOutward",
    ck_test_jolt_bake_dynamicmesh::kTestFlags)

bool FCkTest_JoltBake_StaticMesh_EngineCubeTriMeshBakesOutward::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_bake_dynamicmesh;

    // The one fixture whose winding NOBODY in this codebase authored: the engine cube is canonical
    // stock content, so this test is immune to the cancelling-errors failure mode that let the
    // original hand-authored fixtures hide a global winding flip in the bake (the b/c swap bug this
    // spec exposed at ratio -1: same-named commit). If this and the DynamicMesh pins ever disagree
    // again, suspect the FIXTURES' authoring convention before the shared chain — this one wins.
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto* Mesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
    if (NOT TestNotNull(TEXT("engine cube mesh loads"), Mesh))
    { return false; }

    auto* BodySetup = Mesh->GetBodySetup();
    if (NOT TestNotNull(TEXT("engine cube has a BodySetup"), BodySetup))
    { return false; }

    // Force the complex-as-simple path on the SHARED asset for the duration only — nothing is saved.
    const auto RestoreTraceFlag = BodySetup->CollisionTraceFlag;
    BodySetup->CollisionTraceFlag = CTF_UseComplexAsSimple;
    ON_SCOPE_EXIT { BodySetup->CollisionTraceFlag = RestoreTraceFlag; };

    if (BodySetup->TriMeshGeometries.Num() == 0)
    {
        BodySetup->InvalidatePhysicsData();
        BodySetup->CreatePhysicsMeshes();
    }

    if (NOT TestTrue(TEXT("engine cube has a cooked Chaos tri-mesh (test precondition)"),
        BodySetup->TriMeshGeometries.Num() > 0))
    { return false; }

    const auto Shape = BuildShape_FromBodySetup(*BodySetup, FVector::OneVector, TEXT("EngineCube"));
    if (NOT TestNotNull(TEXT("engine cube bakes a shape"), Shape.GetPtr()))
    { return false; }

    {
        const auto ShapeRatio = ComputeShapeWindingRatio(*Shape);
        TestTrue(ck::Format_UE(TEXT("engine cube bakes OUTWARD — ratio ~+1 (got {})"), ShapeRatio),
            FMath::Abs(ShapeRatio - 1.0) <= 0.05);
    }

    // Behavioral pin: the engine cube spans [-50, 50]^3, so a culled down-ray must answer on the
    // TOP face — the same probe that exposes an inside-out bake as "hits the far face from inside".
    {
        const auto DownFraction = CastRay_FrontFacesOnly(
            *Shape, JPH::Vec3{0.0f, 0.0f, 1000.0f}, JPH::Vec3{0.0f, 0.0f, -2000.0f});

        if (TestTrue(TEXT("culled down-ray hits the engine cube from above"), DownFraction.IsSet()))
        {
            const auto HitZ = 1000.0 - 2000.0 * *DownFraction;
            TestTrue(ck::Format_UE(TEXT("hit is the TOP face at ~50 (got {})"), HitZ),
                FMath::Abs(HitZ - 50.0) <= 1.0);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
