#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGroundNav/Bake/CkGroundNav_DataLayerSelector.h"
#include "CkGroundNav/Bake/CkGroundNav_GeometryBatch.h"
#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend.h"
#include "CkGroundNavEditor/Cook/CkGroundNavCook_GeometrySnapshotBackend.h"
#include "CkJolt/CkJolt_Utils.h"
#include "CkJoltEditor/Cook/CkJoltCook_GeometrySnapshot.h"

#include <Components/StaticMeshComponent.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <Engine/World.h>
#include <Tests/AutomationCommon.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_cook_geometry_snapshot
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    auto Spawn_Cube(UWorld& InWorld) -> AStaticMeshActor*
    {
        auto* Mesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (Mesh == nullptr)
        { return nullptr; }

        auto* Actor = InWorld.SpawnActor<AStaticMeshActor>();
        if (Actor == nullptr)
        { return nullptr; }

        auto* Component = Actor->GetStaticMeshComponent();
        Component->SetMobility(EComponentMobility::Static);
        Component->SetStaticMesh(Mesh);
        Component->SetCollisionProfileName(TEXT("BlockAll"));
        Actor->RegisterAllComponents();
        return Actor;
    }

    auto Make_Selector(TConstArrayView<FName> InNames) -> ck::groundnav::FCk_GroundNav_DataLayerSelector
    {
        auto Selector = ck::groundnav::FCk_GroundNav_DataLayerSelector{};
        ck::groundnav::TryMake_DataLayerSelector(InNames, Selector);
        return Selector;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookGeometrySnapshot_LevelSweepValueBackend,
    "CkTests.UnitTests.CkGroundNav.CookGeometrySnapshot.LevelSweepValueBackend",
    ck_test_groundnav_cook_geometry_snapshot::kTestFlags)

bool FCkTest_GroundNav_CookGeometrySnapshot_LevelSweepValueBackend::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cook_geometry_snapshot;

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};
    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("the temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* Actor = Spawn_Cube(*WorldWrapper.GetTestWorld());
    if (NOT TestNotNull(TEXT("the LevelSweep source actor is spawned"), Actor))
    { return false; }

    auto Snapshot = ck::jolt::cook::FCk_Jolt_CookGeometrySnapshot{};
    if (NOT TestTrue(TEXT("production LevelSweep extraction copies the actor"), Snapshot.Try_AddActor(*Actor)))
    { return false; }

    TestTrue(TEXT("the completed snapshot owns at least one extracted value body"),
        Snapshot.Get_IsComplete() && Snapshot.Get_NumActors() == 1 && NOT Snapshot.Get_Bodies().IsEmpty());

    const auto AllLayers = Make_Selector({});
    auto Backend = ck::groundnav::cook::FCk_GroundNav_CookGeometrySnapshotBackend{Snapshot, AllLayers};
    const auto Region = FBox{FVector{-100.0, -100.0, -100.0}, FVector{100.0, 100.0, 100.0}};
    auto Bodies = TArray<ck::groundnav::FCk_GroundNav_BodyRef>{};

    if (NOT TestTrue(TEXT("the complete value snapshot is a valid GroundNav backend"), Backend.Get_IsValid()) ||
        NOT TestEqual(TEXT("the query region finds the extracted body"), Backend.Get_StaticBodiesInBounds(Region, Bodies), 1))
    { return false; }

    const auto Body = Bodies[0];
    const auto Bounds = Backend.Get_BodyBounds(Body);
    TestTrue(TEXT("the copied body bounds remain valid and intersect the queried region"),
        Bounds.IsValid != 0 && Bounds.Intersect(Region));
    TestTrue(TEXT("the extracted static mesh is reported as a solid body"),
        Backend.Get_BodyKind(Body) == ck::groundnav::ECk_GroundNav_BodyKind::Solid);

    auto RegionTriangles = FCk_GroundNav_GeometryBatch{};
    auto FullBodyTriangles = FCk_GroundNav_GeometryBatch{};
    const auto RegionTriangleCount = Backend.Get_TrianglesInBounds(Region, RegionTriangles);
    const auto FullBodyTriangleCount = Backend.Get_BodyTriangles(Body, FullBodyTriangles);
    TestTrue(TEXT("the region query returns copied triangles"),
        RegionTriangleCount > 0 && RegionTriangleCount == RegionTriangles.Get_TriangleCount());
    TestTrue(TEXT("the full-body query returns copied triangles"),
        FullBodyTriangleCount > 0 && FullBodyTriangleCount == FullBodyTriangles.Get_TriangleCount());
    TestTrue(TEXT("the region is not larger than the complete body"), RegionTriangleCount <= FullBodyTriangleCount);

    // An unlayered actor is excluded by a non-empty exact-any selector. Empty is the explicit all-layer
    // case and was admitted above; this locks the snapshot backend's selector gate without touching
    // its private copied-body array.
    auto MissingLayerBackend = ck::groundnav::cook::FCk_GroundNav_CookGeometrySnapshotBackend{
        Snapshot, Make_Selector(TArray<FName>{FName{TEXT("/Game/DataLayers/NotPresent.NotPresent")}})};
    auto ExcludedBodies = TArray<ck::groundnav::FCk_GroundNav_BodyRef>{};
    TestEqual(TEXT("a nonmatching exact-any selector excludes the unlayered body"),
        MissingLayerBackend.Get_StaticBodiesInBounds(Region, ExcludedBodies), 0);
    TestEqual(TEXT("and its region query returns no triangles"),
        MissingLayerBackend.Get_TrianglesInBounds(Region, RegionTriangles), 0);

    // The production snapshot copies values while the actor is loaded. Destroying the source cannot
    // invalidate its bounds, kind, or triangle bytes held by the backend.
    Actor->Destroy();
    auto BodiesAfterDestroy = TArray<ck::groundnav::FCk_GroundNav_BodyRef>{};
    auto TrianglesAfterDestroy = FCk_GroundNav_GeometryBatch{};
    TestEqual(TEXT("the value backend still finds its body after source destruction"),
        Backend.Get_StaticBodiesInBounds(Region, BodiesAfterDestroy), 1);
    TestEqual(TEXT("the value backend still reads its full body after source destruction"),
        Backend.Get_BodyTriangles(BodiesAfterDestroy[0], TrianglesAfterDestroy), FullBodyTriangleCount);
    TestTrue(TEXT("the copied bounds survive source destruction"),
        Backend.Get_BodyBounds(BodiesAfterDestroy[0]) == Bounds);

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
