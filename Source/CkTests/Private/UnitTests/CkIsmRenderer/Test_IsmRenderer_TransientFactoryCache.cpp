#if WITH_DEV_AUTOMATION_TESTS

#include "Misc/AutomationTest.h"

#include "CkIsmRenderer/Renderer/CkIsmRenderer_TransientFactory.h"

#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "UObject/UObjectGlobals.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_ismrenderer_transient_factory
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::EngineFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmRenderer_TransientFactory_WorldAndMobilityCache,
    "Ck.CkIsmRenderer.TransientFactory.WorldAndMobilityCache",
    ck_test_ismrenderer_transient_factory::kTestFlags)

bool FCkTest_IsmRenderer_TransientFactory_WorldAndMobilityCache::RunTest(const FString&)
{
    auto* WorldA = UWorld::CreateWorld(EWorldType::Game, false);
    auto* WorldB = UWorld::CreateWorld(EWorldType::Game, false);
    auto* Mesh = NewObject<UStaticMesh>(GetTransientPackage());

    if (TestNotNull(TEXT("first transient world exists"), WorldA) == false ||
        TestNotNull(TEXT("second transient world exists"), WorldB) == false ||
        TestNotNull(TEXT("transient mesh exists"), Mesh) == false)
    {
        if (WorldA != nullptr)
        { WorldA->DestroyWorld(false); }
        if (WorldB != nullptr)
        { WorldB->DestroyWorld(false); }
        return false;
    }

    const auto* MeshStaticA = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMesh(
        WorldA, Mesh, ECk_Mobility::Static);
    const auto* MeshStaticARepeated = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMesh(
        WorldA, Mesh, ECk_Mobility::Static);
    const auto* MeshMovableA = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMesh(
        WorldA, Mesh, ECk_Mobility::Movable);
    const auto* MeshStaticB = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMesh(
        WorldB, Mesh, ECk_Mobility::Static);

    const auto* MaterialStaticA = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterialsAndCustomData(
        WorldA, Mesh, {}, 2, ECk_Mobility::Static);
    const auto* MaterialStaticARepeated = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterialsAndCustomData(
        WorldA, Mesh, {}, 2, ECk_Mobility::Static);
    const auto* MaterialMovableA = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterialsAndCustomData(
        WorldA, Mesh, {}, 2, ECk_Mobility::Movable);
    const auto* MaterialStaticB = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterialsAndCustomData(
        WorldB, Mesh, {}, 2, ECk_Mobility::Static);

    TestNotNull(TEXT("mesh-only static renderer is created"), MeshStaticA);
    TestTrue(TEXT("mesh-only same world and mobility reuses data"), MeshStaticARepeated == MeshStaticA);
    TestTrue(TEXT("mesh-only mobility selects distinct data"), MeshMovableA != MeshStaticA);
    TestTrue(TEXT("mesh-only world selects distinct data"), MeshStaticB != MeshStaticA);

    TestNotNull(TEXT("material renderer is created"), MaterialStaticA);
    TestTrue(TEXT("material same world and mobility reuses data"), MaterialStaticARepeated == MaterialStaticA);
    TestTrue(TEXT("material mobility selects distinct data"), MaterialMovableA != MaterialStaticA);
    TestTrue(TEXT("material world selects distinct data"), MaterialStaticB != MaterialStaticA);

    UCk_Utils_IsmRenderer_TransientFactory_UE::ClearCache(WorldA);

    const auto* MeshStaticBAfterWorldAClear = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMesh(
        WorldB, Mesh, ECk_Mobility::Static);
    const auto* MaterialStaticBAfterWorldAClear = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMeshWithMaterialsAndCustomData(
        WorldB, Mesh, {}, 2, ECk_Mobility::Static);
    const auto* MeshStaticAAfterWorldAClear = UCk_Utils_IsmRenderer_TransientFactory_UE::GetOrCreate_ForMesh(
        WorldA, Mesh, ECk_Mobility::Static);

    TestTrue(TEXT("world-scoped clear preserves another world's mesh-only entry"),
        MeshStaticBAfterWorldAClear == MeshStaticB);
    TestTrue(TEXT("world-scoped clear preserves another world's material entry"),
        MaterialStaticBAfterWorldAClear == MaterialStaticB);
    TestTrue(TEXT("world-scoped clear evicts the target world's mesh-only entry"),
        MeshStaticAAfterWorldAClear != MeshStaticA);

    UCk_Utils_IsmRenderer_TransientFactory_UE::ClearCache(WorldA);
    UCk_Utils_IsmRenderer_TransientFactory_UE::ClearCache(WorldB);
    WorldA->DestroyWorld(false);
    WorldB->DestroyWorld(false);
    return true;
}

#endif
