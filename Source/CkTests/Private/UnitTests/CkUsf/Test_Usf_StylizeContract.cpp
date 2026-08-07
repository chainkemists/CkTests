// Contract gate for CkUsf's stylize generator extensions: the four GBuffer scene textures
// (BaseColor/Metallic/Roughness/Specular) and the opt-in PostProcess world position.
//
// Two tests, because the two failure modes are opposites:
//
//   StylizeParamCount — the WIDE arm. A PostProcess look with 50 parameters, every scene texture and the
//     world-position opt-in generates, all 62 Custom-node inputs are declared AND connected, and the
//     resulting master force-compiles clean. This is the permanent guard on the "globals as material
//     parameters, not a per-pixel LUT" decision: if an engine limit ever bites the wide node, this test
//     names it rather than leaving the next author to rediscover it while authoring a look.
//
//   StylizeSceneTextureNegative — the BYTE-IDENTICAL arm, the NiagaraSpriteContract pattern. A look
//     that opts into nothing must generate the historical default-trio Custom node: the exact Inputs
//     list and the exact Code string, character for character. Every shipped PostProcess look is then
//     REGENERATED and checked for the same absence, so a leak into the default path is caught on the
//     real roster and not only on the synthetic subject.
//
// Both subjects are transient LookDefinitions built in code against /CkUsf/Looks/StylizeProbe.ush, so
// the guard carries no content dependency; the generated masters are deleted at the end of each test.
//
// Editor-only: the generator lives in CkUsfEditor. Skipped under -nullrhi for the same reason
// GeneratesUsableMasters is — generation force-compiles shaders and a process that cannot render
// reports every look as failed, which is environmental rather than a defect.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "HAL/FileManager.h"
#include "Misc/App.h"
#include "Misc/PackageName.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"
#include "Materials/MaterialExpressionWorldPosition.h"
#include "UObject/StrongObjectPtr.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"
#include "CkUsfEditor/Generator/CkUsf_LookValidator.h"

#include "CkUsf_TestLookMasters.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_stylize_contract
{
    constexpr auto kStylizeTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    constexpr auto kProbeLookName = TEXT("StylizeProbe");
    constexpr auto kMinimalLookName = TEXT("StylizeProbeMinimal");
    constexpr auto kProbeIncludePath = TEXT("/CkUsf/Looks/StylizeProbe.ush");

    constexpr auto kNumProbeScalars = 35;
    constexpr auto kNumProbeVectors = 15;

    // 9 scene textures + WorldPosition + 50 params + Time + UV. Stated as a literal rather than derived
    // so a generator that silently drops an input cannot make the expectation drop with it.
    constexpr auto kExpectedProbeInputCount = 62;

    // The inputs a look that opted into NOTHING must never carry.
    auto Get_OptInInputNames() -> TArray<FString>
    {
        return
        {
            TEXT("SceneBaseColor"), TEXT("SceneMetallic"), TEXT("SceneRoughness"), TEXT("SceneSpecular"),
            TEXT("WorldPosition"),
        };
    }

    auto Get_AllSceneTextures() -> TArray<ECk_Usf_SceneTexture>
    {
        return
        {
            ECk_Usf_SceneTexture::SceneColor,  ECk_Usf_SceneTexture::SceneDepth,
            ECk_Usf_SceneTexture::SceneNormal, ECk_Usf_SceneTexture::CustomDepth,
            ECk_Usf_SceneTexture::CustomStencil,
            ECk_Usf_SceneTexture::BaseColor,   ECk_Usf_SceneTexture::Metallic,
            ECk_Usf_SceneTexture::Roughness,   ECk_Usf_SceneTexture::Specular,
        };
    }

    auto Get_ProbeScalarName(int32 InIndex) -> FString
    {
        return FString::Printf(TEXT("ProbeScalar%02d"), InIndex);
    }

    auto Get_ProbeVectorName(int32 InIndex) -> FString
    {
        return FString::Printf(TEXT("ProbeVector%02d"), InIndex);
    }

    // 35 scalars then 15 vectors, matching StylizeProbe.ush's declaration order — the generator wires
    // positionally, so an order change here mis-binds every parameter past the first difference.
    auto Make_ProbeParameters() -> TArray<FCk_Usf_ParamDesc>
    {
        auto Parameters = TArray<FCk_Usf_ParamDesc>{};

        for (auto Index = 0; Index < kNumProbeScalars; ++Index)
        {
            FCk_Usf_ParamDesc Param;
            Param._Name = FName(*Get_ProbeScalarName(Index));
            Param._Type = ECk_Usf_ParamType::Scalar;
            Param._DefaultScalar = static_cast<float>(Index) * 0.01f;
            Parameters.Add(Param);
        }

        for (auto Index = 0; Index < kNumProbeVectors; ++Index)
        {
            FCk_Usf_ParamDesc Param;
            Param._Name = FName(*Get_ProbeVectorName(Index));
            Param._Type = ECk_Usf_ParamType::Vector;
            Param._DefaultVector = FLinearColor(0.1f, 0.2f, 0.3f);
            Parameters.Add(Param);
        }

        return Parameters;
    }

    auto Make_ProbeLookDefinition() -> UCkUsf_LookDefinition*
    {
        auto* Definition = NewObject<UCkUsf_LookDefinition>(GetTransientPackage());
        Definition->_LookName = FName(kProbeLookName);
        Definition->_UshIncludePath = kProbeIncludePath;
        Definition->_UshFunctionName = TEXT("CkUsf_Look_StylizeProbe");
        Definition->_Domain = ECk_Usf_Domain::PostProcess;
        // Where the stylize looks' WorldPosition consumers sit: the after-tonemap reconstruction is
        // dynamic-resolution scaled, so the wide arm proves the placement the looks will actually use.
        Definition->_BlendableLocation = ECk_Usf_BlendableLocation::SceneColorAfterDOF;
        Definition->_SceneTextures = Get_AllSceneTextures();
        Definition->_PostProcessWorldPosition = true;
        Definition->_Parameters = Make_ProbeParameters();
        return Definition;
    }

    auto Make_MinimalLookDefinition() -> UCkUsf_LookDefinition*
    {
        auto* Definition = NewObject<UCkUsf_LookDefinition>(GetTransientPackage());
        Definition->_LookName = FName(kMinimalLookName);
        Definition->_UshIncludePath = kProbeIncludePath;
        Definition->_UshFunctionName = TEXT("CkUsf_Look_StylizeProbeMinimal");
        Definition->_Domain = ECk_Usf_Domain::PostProcess;

        FCk_Usf_ParamDesc Param;
        Param._Name = TEXT("ProbeAmount");
        Param._Type = ECk_Usf_ParamType::Scalar;
        Param._DefaultScalar = 1.0f;
        Definition->_Parameters = { Param };

        return Definition;
    }

    // The Custom-node Code a PostProcess look generated BEFORE the stylize extensions — character for
    // character. Anything the extensions leak into the default path shows up as a diff here.
    auto Get_ExpectedMinimalCustomCode() -> FString
    {
        return
            TEXT("FCkUsf_SurfaceInput In = CkUsf_DefaultInput();\n")
            TEXT("In.Time = Time;\n")
            TEXT("In.UV = UV;\n")
            TEXT("In.SceneColor = SceneColor;\n")
            TEXT("In.SceneDepth = SceneDepth;\n")
            TEXT("In.SceneNormal = SceneNormal;\n")
            TEXT("FCkUsf_SurfaceOutput O = CkUsf_Look_StylizeProbeMinimal(In, ProbeAmount);\n")
            TEXT("return O.EmissiveColor;");
    }

    auto Get_ExpectedMinimalInputNames() -> TArray<FString>
    {
        return
        {
            TEXT("SceneColor"), TEXT("SceneDepth"), TEXT("SceneNormal"),
            TEXT("ProbeAmount"), TEXT("Time"), TEXT("UV"),
        };
    }

    // "Declared" is the input existing on the Custom node; "connected" is something actually driving it.
    // A wide node whose pins were declared but never connected still generates and still compiles.
    enum class ECk_InputState : uint8 { Absent, Declared, Connected };

    auto Get_CustomInputState(const UMaterialExpressionCustom* InCustom, const TCHAR* InInputName) -> ECk_InputState
    {
        if (InCustom == nullptr)
        { return ECk_InputState::Absent; }

        for (const auto& Input : InCustom->Inputs)
        {
            if (Input.InputName != FName(InInputName))
            { continue; }

            return Input.Input.GetTracedInput().Expression != nullptr
                ? ECk_InputState::Connected
                : ECk_InputState::Declared;
        }
        return ECk_InputState::Absent;
    }

    auto Find_CustomNode(const UMaterial* InMaterial) -> const UMaterialExpressionCustom*
    {
        for (const auto& Expression : InMaterial->GetExpressions())
        {
            if (const auto* Custom = Cast<UMaterialExpressionCustom>(Expression))
            { return Custom; }
        }
        return nullptr;
    }

    auto Get_HasWorldPositionExpression(const UMaterial* InMaterial) -> bool
    {
        for (const auto& Expression : InMaterial->GetExpressions())
        {
            if (Cast<UMaterialExpressionWorldPosition>(Expression) != nullptr)
            { return true; }
        }
        return false;
    }

    auto Get_CustomInputNames(const UMaterialExpressionCustom* InCustom) -> TArray<FString>
    {
        auto Names = TArray<FString>{};
        for (const auto& Input : InCustom->Inputs)
        { Names.Add(Input.InputName.ToString()); }
        return Names;
    }

    auto Get_AllLookDefinitions() -> TArray<UCkUsf_LookDefinition*>
    {
        const auto& AssetRegistry = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry").Get();

        auto Assets = TArray<FAssetData>{};
        AssetRegistry.GetAssetsByClass(UCkUsf_LookDefinition::StaticClass()->GetClassPathName(), Assets);

        auto Definitions = TArray<UCkUsf_LookDefinition*>{};
        for (const auto& Asset : Assets)
        {
            if (auto* Definition = Cast<UCkUsf_LookDefinition>(Asset.GetAsset()))
            { Definitions.Add(Definition); }
        }
        return Definitions;
    }

    // The generator's own gate, CALLED rather than re-implemented, so the probe is held to exactly the bar
    // every shipped look is: synchronous force-compile, then the resource's real HLSL errors.
    // A bare `IsCompilingOrHadCompileError` check is toothless — a deliberately-undefined function in
    // StylizeProbe.ush passes it — so that check must never stand alone here.
    auto Get_ShaderCompileSucceeded(
        UMaterial* InMaterial, const FName InLookName, const bool InForceSynchronousCompile, FString& OutErrors) -> bool
    {
        auto Errors = TArray<FString>{};
        const auto Compiled = ck::usf_editor::Validate_LookShaderCompile(
            InMaterial, InLookName, Errors, InForceSynchronousCompile);
        OutErrors = FString::Join(Errors, TEXT("\n"));
        return Compiled;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeParamCount,
    "CkTests.UnitTests.CkUsf.StylizeParamCount",
    ck_test_usf_stylize_contract::kStylizeTestFlags)

bool FCkTest_Usf_StylizeParamCount::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_contract;

    if (FApp::CanEverRender() == false)
    {
        AddInfo(TEXT("Skipped: this process cannot render (e.g. -nullrhi) — generation force-compiles shaders "
                     "and would report the probe as failed, which is environmental."));
        return true;
    }

    const auto Probe = TStrongObjectPtr<UCkUsf_LookDefinition>{Make_ProbeLookDefinition()};

    // ---- 1. The asset↔HLSL contract holds at 50 parameters ----
    const auto Validation = ck::usf_editor::Validate_LookDefinition(Probe.Get());
    for (const auto& Warning : Validation.Warnings)
    { AddInfo(FString::Printf(TEXT("validator warning: %s"), *Warning)); }
    for (const auto& Error : Validation.Errors)
    { AddError(FString::Printf(TEXT("validator error: %s"), *Error)); }
    if (TestEqual(TEXT("the 50-param probe validates with no errors"), Validation.Errors.Num(), 0) == false)
    { return false; }

    // ---- 2. It generates ----
    auto* Master = ck::usf_editor::Generate_LookMaterial(Probe.Get(), ck_test_usf::Get_TestPackageRoot());
    if (TestNotNull(TEXT("the 50-param probe generates a master material"), Master) == false)
    { return false; }

    // ---- 3. Every input is DECLARED and CONNECTED — a wide node can lose pins silently ----
    const auto* Custom = Find_CustomNode(Master);
    if (TestNotNull(TEXT("the probe master has a Custom node"), Custom))
    {
        TestEqual(TEXT("the Custom node carries all 62 inputs"), Custom->Inputs.Num(), kExpectedProbeInputCount);

        for (const auto* SceneInputName :
            { TEXT("SceneColor"), TEXT("SceneDepth"), TEXT("SceneNormal"), TEXT("CustomDepth"), TEXT("CustomStencil"),
              TEXT("SceneBaseColor"), TEXT("SceneMetallic"), TEXT("SceneRoughness"), TEXT("SceneSpecular") })
        {
            TestEqual(*FString::Printf(TEXT("scene-texture input [%s] is connected"), SceneInputName),
                static_cast<int32>(Get_CustomInputState(Custom, SceneInputName)),
                static_cast<int32>(ECk_InputState::Connected));
        }

        TestEqual(TEXT("the opt-in PostProcess WorldPosition input is connected"),
            static_cast<int32>(Get_CustomInputState(Custom, TEXT("WorldPosition"))),
            static_cast<int32>(ECk_InputState::Connected));

        for (auto Index = 0; Index < kNumProbeScalars; ++Index)
        {
            const auto Name = Get_ProbeScalarName(Index);
            TestEqual(*FString::Printf(TEXT("scalar param [%s] is connected"), *Name),
                static_cast<int32>(Get_CustomInputState(Custom, *Name)),
                static_cast<int32>(ECk_InputState::Connected));
        }

        for (auto Index = 0; Index < kNumProbeVectors; ++Index)
        {
            const auto Name = Get_ProbeVectorName(Index);
            TestEqual(*FString::Printf(TEXT("vector param [%s] is connected"), *Name),
                static_cast<int32>(Get_CustomInputState(Custom, *Name)),
                static_cast<int32>(ECk_InputState::Connected));
        }

        TestTrue(TEXT("the generated code assigns the GBuffer base colour"),
            Custom->Code.Contains(TEXT("In.SceneBaseColor = SceneBaseColor;")));
        TestTrue(TEXT("the generated code assigns the reconstructed world position"),
            Custom->Code.Contains(TEXT("In.WorldPosition = WorldPosition;")));
    }

    // ---- 4. It COMPILES at 62 inputs. With the gate force-compiling synchronously and reading the
    //         resource's HLSL errors, this is the parameter-count proof behind the
    //         "globals as MID params, not a LUT" decision. ----
    {
        // The probe is a throwaway master, deleted below, so it can afford the destructive force-compile that
        // is what actually runs the shader jobs. That is the whole reason this arm can claim "it compiles".
        constexpr auto ForceSynchronousCompile = true;
        auto CompileErrors = FString{};
        if (Get_ShaderCompileSucceeded(Master, FName(kProbeLookName), ForceSynchronousCompile, CompileErrors) == false)
        { AddError(CompileErrors); }
        TestEqual(TEXT("the 50-param probe reports no HLSL compile errors"), CompileErrors, FString{});
    }

    if (ck_test_usf::Delete_TestGeneratedMaster(FName(kProbeLookName)) == false)
    { AddInfo(TEXT("Could not delete the probe's generated master file — harmless, but it is a stray asset on disk.")); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_StylizeSceneTextureNegative,
    "CkTests.UnitTests.CkUsf.StylizeSceneTextureNegative",
    ck_test_usf_stylize_contract::kStylizeTestFlags)

bool FCkTest_Usf_StylizeSceneTextureNegative::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_stylize_contract;

    if (FApp::CanEverRender() == false)
    {
        AddInfo(TEXT("Skipped: this process cannot render (e.g. -nullrhi) — generation force-compiles shaders "
                     "and would report every look as failed, which is environmental."));
        return true;
    }

    // ---- 1. The synthetic subject: byte-identical to the pre-extension shape ----
    {
        const auto Minimal = TStrongObjectPtr<UCkUsf_LookDefinition>{Make_MinimalLookDefinition()};

        TestTrue(TEXT("the minimal look opts into no scene textures"), Minimal->_SceneTextures.IsEmpty());
        TestFalse(TEXT("the minimal look leaves _PostProcessWorldPosition at its default"),
            Minimal->_PostProcessWorldPosition);

        auto* Master = ck::usf_editor::Generate_LookMaterial(Minimal.Get(), ck_test_usf::Get_TestPackageRoot());
        if (TestNotNull(TEXT("the minimal look generates a master material"), Master) == false)
        { return false; }

        const auto* Custom = Find_CustomNode(Master);
        if (TestNotNull(TEXT("the minimal master has a Custom node"), Custom))
        {
            // Exact list, exact order: an input appended anywhere shifts nothing functionally but proves
            // the default path changed, which is what "byte-identical" means for a generated master.
            TestEqual(TEXT("the minimal Custom node's Inputs are exactly the historical default-trio shape"),
                FString::Join(Get_CustomInputNames(Custom), TEXT(",")),
                FString::Join(Get_ExpectedMinimalInputNames(), TEXT(",")));

            TestEqual(TEXT("the minimal Custom node's Code is character-for-character the pre-extension shape"),
                Custom->Code, Get_ExpectedMinimalCustomCode());
        }

        TestFalse(TEXT("the minimal master gained no WorldPosition expression"),
            Get_HasWorldPositionExpression(Master));

        {
            // Also a throwaway master, so it can afford the same force. It does NOT stand in for the wide arm's
            // compile proof: a broken sibling entry point in the shared StylizeProbe.ush
            // failed StylizeParamCount while this arm still passed — only the entry point a look actually
            // calls is proven by that look.
            constexpr auto ForceSynchronousCompile = true;
            auto CompileErrors = FString{};
            if (Get_ShaderCompileSucceeded(Master, FName(kMinimalLookName), ForceSynchronousCompile, CompileErrors) == false)
            { AddError(CompileErrors); }
            TestEqual(TEXT("the minimal look reports no HLSL compile errors"), CompileErrors, FString{});
        }

        if (ck_test_usf::Delete_TestGeneratedMaster(FName(kMinimalLookName)) == false)
        { AddInfo(TEXT("Could not delete the minimal look's generated master file — harmless, but it is a stray asset on disk.")); }
    }

    // ---- 2. The real roster: every shipped PostProcess look that opted into none of the new inputs
    //         REGENERATES without them. Regenerated rather than read off disk — a master generated
    //         before the extensions lacks the inputs whether or not the generator leaks them. ----
    const auto OptInInputNames = Get_OptInInputNames();
    auto NumRosterLooksChecked = 0;
    auto RegeneratedLookNames = TArray<FName>{};

    for (auto* Definition : Get_AllLookDefinitions())
    {
        if (Definition->_Domain != ECk_Usf_Domain::PostProcess || Definition->_PostProcessWorldPosition)
        { continue; }

        const auto OptedIntoGBuffer = Definition->_SceneTextures.ContainsByPredicate(
            [](ECk_Usf_SceneTexture InSceneTexture) -> bool
            {
                return InSceneTexture == ECk_Usf_SceneTexture::BaseColor
                    || InSceneTexture == ECk_Usf_SceneTexture::Metallic
                    || InSceneTexture == ECk_Usf_SceneTexture::Roughness
                    || InSceneTexture == ECk_Usf_SceneTexture::Specular;
            });
        if (OptedIntoGBuffer)
        { continue; }

        const auto Name = Definition->Get_EffectiveLookName().ToString();

        auto* Master = ck::usf_editor::Generate_LookMaterial(Definition, ck_test_usf::Get_TestPackageRoot());
        if (TestNotNull(*FString::Printf(TEXT("PostProcess look [%s] regenerates"), *Name), Master) == false)
        { continue; }

        ++NumRosterLooksChecked;
        RegeneratedLookNames.Add(Definition->Get_EffectiveLookName());

        const auto* Custom = Find_CustomNode(Master);
        if (TestNotNull(*FString::Printf(TEXT("PostProcess look [%s] has a Custom node"), *Name), Custom) == false)
        { continue; }

        for (const auto& InputName : OptInInputNames)
        {
            TestEqual(*FString::Printf(TEXT("look [%s] did not gain the [%s] input"), *Name, *InputName),
                static_cast<int32>(Get_CustomInputState(Custom, *InputName)),
                static_cast<int32>(ECk_InputState::Absent));
        }

        TestFalse(*FString::Printf(TEXT("look [%s] did not gain a world-position assignment"), *Name),
            Custom->Code.Contains(TEXT("In.WorldPosition")));
    }

    for (const auto& RegeneratedLookName : RegeneratedLookNames)
    {
        if (ck_test_usf::Delete_TestGeneratedMaster(RegeneratedLookName) == false)
        {
            AddInfo(FString::Printf(
                TEXT("Could not delete the regenerated master for look [%s] — harmless, but it is a stray asset on disk."),
                *RegeneratedLookName.ToString()));
        }
    }

    TestTrue(TEXT("at least one shipped PostProcess look was checked (else this test passes vacuously)"),
        NumRosterLooksChecked > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
