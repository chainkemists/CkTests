// End-to-end editor test for CkUsf:
//   - runs the generator over all UCkUsf_LookDefinition assets
//   - for each look, the generated master resolves and a MID can be created
// Editor-only: the generator lives in CkUsfEditor.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Materials/MaterialInstanceDynamic.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsf/Apply/CkUsf_Utils.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kUsfTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_GeneratesUsableMasters,
    "CkTests.UnitTests.CkUsf.GeneratesUsableMasters",
    kUsfTestFlags)

bool FCkTest_Usf_GeneratesUsableMasters::RunTest(const FString& Parameters)
{
    // 1. Generate masters for every declared look. Generation now also force-compiles each
    //    master's shaders and reports any HLSL compile failures (the silent fallback-to-default
    //    case that a bare object/MID check misses — e.g. a broken PostProcess permutation).
    const auto Result = ck::usf_editor::Generate_AllLookMaterials();
    TestTrue(TEXT("at least one look material generated"), Result.NumGenerated > 0);
    TestEqual(TEXT("no looks skipped"), Result.NumSkipped, 0);

    for (const auto& ShaderError : Result.Errors)
    { AddError(ShaderError); }
    TestEqual(TEXT("no shader compile errors across looks"), Result.Errors.Num(), 0);

    // 2. Discover the look definitions.
    const auto& ARM = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry").Get();
    TArray<FAssetData> Assets;
    ARM.GetAssetsByClass(UCkUsf_LookDefinition::StaticClass()->GetClassPathName(), Assets);
    TestTrue(TEXT("found at least one UCkUsf_LookDefinition"), Assets.Num() > 0);

    // 3. Each look: master resolves + a MID can be created.
    for (const auto& A : Assets)
    {
        auto* Def = Cast<UCkUsf_LookDefinition>(A.GetAsset());
        if (Def == nullptr) { continue; }

        const auto Name = Def->Get_EffectiveLookName().ToString();

        auto* Master = UCk_Utils_Usf_UE::Get_LookMasterMaterial(Def);
        TestNotNull(*FString::Printf(TEXT("generated master resolves for look [%s]"), *Name), Master);

        auto* MID = UCk_Utils_Usf_UE::Create_MID_ForLook(Def, GetTransientPackage());
        TestNotNull(*FString::Printf(TEXT("MID created for look [%s]"), *Name), MID);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
