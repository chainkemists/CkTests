#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Misc/App.h"
#include "Engine/SkeletalMesh.h"
#include "Materials/Material.h"
#include "Rendering/SkeletalMeshRenderData.h"
#include "ShaderCompiler.h"

namespace ck_test_iskm_batched_shadow_assets
{
    constexpr TCHAR MeshPath[] =
        TEXT("/CkTests/Characters/Mannequins/Meshes/SKM_Manny_Simple.SKM_Manny_Simple");
    constexpr TCHAR MaterialPath[] =
        TEXT("/CkFoundation/CkUsf/GeneratedLooks/M_CkUsf_Look_VisualLodCrowdFade.M_CkUsf_Look_VisualLodCrowdFade");
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IskmRenderer_BatchedShadowAssets,
    "Ck.IskmRenderer.VisualLod.BatchedShadowAssets",
    ck_test_iskm_batched_shadow_assets::TestFlags)

auto
    FCkTest_IskmRenderer_BatchedShadowAssets::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_iskm_batched_shadow_assets;

    const auto Mesh = LoadObject<USkeletalMesh>(nullptr, MeshPath);
    if (NOT TestNotNull(TEXT("batched-shadow mannequin mesh resolves"), Mesh))
    { return false; }

    const auto RenderData = Mesh->GetResourceForRendering();
    if (NOT TestNotNull(TEXT("batched-shadow mannequin mesh has render data"), RenderData))
    { return false; }

    TestTrue(TEXT("batched-shadow mannequin mesh has at least one render LOD"),
             RenderData->LODRenderData.Num() > 0);

    auto NonEmptySectionCount = 0;
    for (int32 LODIndex = 0; LODIndex < RenderData->LODRenderData.Num(); ++LODIndex)
    {
        const auto& LOD = RenderData->LODRenderData[LODIndex];
        for (int32 SectionIndex = 0; SectionIndex < LOD.RenderSections.Num(); ++SectionIndex)
        {
            const auto& Section = LOD.RenderSections[SectionIndex];
            if (Section.NumTriangles == 0)
            { continue; }

            ++NonEmptySectionCount;
            TestTrue(*FString::Printf(TEXT("LOD %d section %d permits shadow casting"), LODIndex, SectionIndex),
                     Section.bCastShadow);
        }
    }
    TestTrue(TEXT("batched-shadow mannequin mesh has at least one non-empty render section"), NonEmptySectionCount > 0);

    const auto Material = LoadObject<UMaterial>(nullptr, MaterialPath);
    if (NOT TestNotNull(TEXT("VisualLod crowd fade generated master resolves at the CkFoundation mount path"), Material))
    { return false; }

    TestEqual(TEXT("VisualLod crowd fade material uses the Surface domain"),
              Material->MaterialDomain, MD_Surface);
    TestEqual(TEXT("VisualLod crowd fade material uses Masked blending"), Material->GetBlendMode(), BLEND_Masked);
    TestFalse(TEXT("VisualLod crowd fade material is not unlit"),
              Material->GetShadingModels().HasShadingModel(MSM_Unlit));
    TestTrue(TEXT("VisualLod crowd fade material is authored for skeletal-mesh vertex factories"),
             Material->bUsedWithSkeletalMesh != 0);

    if (NOT FApp::CanEverRender())
    {
        AddInfo(TEXT("Skipped material shader-map verdict: this process cannot render (for example -nullrhi)."));
        AddInfo(TEXT("Skipped Ck batched-VF flag inspection: CkTests has no direct public CkIskmRendererVF contract; "
                     "the test does not reach through renderer-private registration state."));
        return true;
    }

    const auto Resource = Material->GetMaterialResource(GMaxRHIShaderPlatform);
    TestNotNull(TEXT("VisualLod crowd fade material exposes a render-platform resource"), Resource);
    TestFalse(TEXT("VisualLod crowd fade material is neither compiling nor carrying a shader compile error"),
              Material->IsCompilingOrHadCompileError(GMaxRHIShaderPlatform));
    // GetCompileErrors is WITH_EDITOR-only, and this file guards on WITH_DEV_AUTOMATION_TESTS.
    // Those are independent: WITH_DEV_AUTOMATION_TESTS comes from bCompileDevTests, so it is ON
    // in a Development GAME build while WITH_EDITOR is not. Without this guard the file compiles
    // in an editor target and fails to compile in every non-editor one, which is invisible to a
    // pipeline that only builds the editor.
    //
    // The compile-failure case stays covered in both configurations by the
    // IsCompilingOrHadCompileError verdict above; only the per-error detail is editor-only.
#if WITH_EDITOR
    if (Resource != nullptr)
    {
        TestTrue(TEXT("VisualLod crowd fade material reports no shader compile errors"),
                 Resource->GetCompileErrors().IsEmpty());
    }
#endif // WITH_EDITOR

    AddInfo(TEXT("Skipped Ck batched-VF flag inspection: CkTests has no direct public CkIskmRendererVF contract; "
                 "the test does not reach through renderer-private registration state."));
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
