// End-to-end editor test for CkUsf:
//   - runs the generator over all UCkUsf_LookDefinition assets
//   - for each look, the generated master resolves and a MID can be created
// Editor-only: the generator lives in CkUsfEditor.
//
// Generation writes to a lane-unique root (CkUsf_TestLookMasters.h), never the shipped GeneratedLooks —
// concurrent test editors saving the same .uasset take each other down. The shipped masters are still
// resolved through the RUNTIME lookup below, which is the API game code actually calls; that arm now
// reads committed content rather than something this run rewrote, which is the stronger claim anyway.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "Misc/App.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"
#include "CkUsf/Apply/CkUsf_Utils.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"

#include "CkUsf_TestLookMasters.h"

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
    // In a process that cannot render (-nullrhi CI) materials never build shader maps, so the
    // shader-compile gate reads every look as failed — environmental, not a shader bug.
    if (FApp::CanEverRender() == false)
    {
        AddInfo(TEXT("Skipped: this process cannot render (e.g. -nullrhi) — shader maps never build, the compile gate would be meaningless."));
        return true;
    }

    // 1. Generate masters for every declared look. Generation now also force-compiles each
    //    master's shaders and reports any HLSL compile failures (the silent fallback-to-default
    //    case that a bare object/MID check misses — e.g. a broken PostProcess permutation).
    const auto TestPackageRoot = ck_test_usf::Get_TestPackageRoot();

    const auto Result = ck::usf_editor::Generate_AllLookMaterials(TestPackageRoot);
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

    // 3. Each look: the master this run generated resolves, the shipped one resolves through the runtime
    //    lookup, and a MID can be created from it.
    for (const auto& A : Assets)
    {
        auto* Def = Cast<UCkUsf_LookDefinition>(A.GetAsset());
        if (Def == nullptr) { continue; }

        const auto LookName = Def->Get_EffectiveLookName();
        const auto Name = LookName.ToString();

        const auto GeneratedPath = ck::usf::Get_GeneratedMasterObjectPath(LookName, TestPackageRoot);
        TestNotNull(*FString::Printf(TEXT("the master generated this run resolves for look [%s]"), *Name),
            LoadObject<UMaterialInterface>(nullptr, *GeneratedPath));

        auto* Master = UCk_Utils_Usf_UE::Get_LookMasterMaterial(Def);
        TestNotNull(*FString::Printf(TEXT("shipped master resolves for look [%s]"), *Name), Master);

        auto* MID = UCk_Utils_Usf_UE::Create_MID_ForLook(Def, GetTransientPackage());
        TestNotNull(*FString::Printf(TEXT("MID created for look [%s]"), *Name), MID);

        if (ck_test_usf::Delete_TestGeneratedMaster(LookName) == false)
        {
            AddInfo(FString::Printf(
                TEXT("Could not delete the generated master for look [%s] — harmless, but it is a stray asset on disk."),
                *Name));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
