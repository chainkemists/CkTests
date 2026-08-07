// Gate for the CkUsf CelShade feature. Four tests, four distinct failure modes:
//
//   CelShadeGeneration — the asset<->HLSL contract. A LookDefinition shaped exactly like
//     Script/CkUsf/CkUsf_CelShadeLook_Assets.as is built in code, validated, generated, checked pin by
//     pin, and FORCE-compiled. This look declares far more Custom-node inputs than any shipped look
//     before it (every param plus eight scene textures plus the opt-in world position), so "it still
//     generates AND compiles" is the claim worth holding. Editor-only and skipped when the process
//     cannot render; the force is destructive, hence a throwaway master that is deleted again.
//
//   CelShadeSubsystemSettings — the subsystem's settings value is the source of truth: a round-trip
//     must be lossless and enable/disable must be idempotent. Deliberately NOT gated on the generated
//     master existing: settings are tracked whether or not there is anything to render them with.
//
//   CelShadeInvalidInput — the rejection boundary. A null preset and a stencil range that collides with
//     the outline subsystem's are each rejected LOUDLY and change NOTHING. The collision is the one that
//     matters: both features write the same Custom-Stencil byte, so an accepted overlap restyles the
//     other feature's meshes with nothing on screen naming the cause.
//
//   CelShadeEntityPattern — the entity API. Apply stamps the target fragment (and cascades to lifetime
//     dependents on request), clear removes it and strips only the derived ones, and an entity that
//     already carries an OUTLINE target is refused, because one entity has exactly one stencil value.
//     Request_SetCelPattern mutates immediately and completes synchronously (verified against
//     UCk_Utils_Usf_Outline_UE::Request_ApplyOutline, which it mirrors), so there is no deferred
//     drain to cancel and no Failed_Cancelled path to exercise.

#include "Misc/AutomationTest.h"

#include "Engine/World.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Fragment.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Components/StaticMeshComponent.h"
#include "GameFramework/Actor.h"

#include "CkUsf/Outline/CkUsf_Outline_Fragment.h"
#include "CkUsf/Stylize/CkUsf_CelPattern_Processor.h"

#include "CkUsf/Outline/CkUsf_OutlinePreset.h"
#include "CkUsf/Outline/CkUsf_OutlineSubsystem.h"
#include "CkUsf/Outline/CkUsf_Outline_Utils.h"
#include "CkUsf/Stylize/CkUsf_CelPattern_Fragment.h"
#include "CkUsf/Stylize/CkUsf_CelPattern_Utils.h"
#include "CkUsf/Stylize/CkUsf_CelShadePreset.h"
#include "CkUsf/Stylize/CkUsf_CelShadeSubsystem.h"
#include "CkUsf/Stylize/CkUsf_CelShade_Params.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"

#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialParameters.h"
#include "UObject/StrongObjectPtr.h"

#include "../CkUnitTest_Common.h"

#if WITH_EDITOR
#include "HAL/FileManager.h"
#include "Misc/App.h"
#include "Misc/PackageName.h"
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"
#include "CkUsfEditor/Generator/CkUsf_LookValidator.h"
#endif

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_cel_shade
{
    // A settings value that differs from the defaults in EVERY field, so a round-trip that drops one is
    // caught rather than masked by a default that happened to match. The stencil base stays clear of the
    // outline subsystem's range — a colliding one is REJECTED, which is a different test.
    auto Make_NonDefaultSettings() -> FCk_Usf_CelShade_Params
    {
        auto Settings = FCk_Usf_CelShade_Params{};

        Settings.Set_Enabled(ECk_EnableDisable::Disable)
                .Set_Bands(7)
                .Set_Midpoint(0.31f)
                .Set_BandOffset(0.17f)
                .Set_Distribution(1.8f)
                .Set_BandSoftness(0.42f)
                .Set_ShadowLift(0.33f)
                .Set_Strength(0.66f)
                .Set_QuantizeFinalColor(ECk_EnableDisable::Enable)
                .Set_EnablePattern(ECk_EnableDisable::Disable)
                .Set_Pattern(ECk_Usf_CelPattern::Spiral)
                .Set_PatternSpace(ECk_Usf_CelPatternSpace::Screen)
                .Set_PatternStrength(0.21f)
                .Set_PatternContrast(2.75f)
                .Set_PatternWorldSize(33.0f)
                .Set_PatternPixelSize(11.0f)
                .Set_TriplanarSharpness(7.5f)
                .Set_PatternDistanceScaling(0.4f)
                .Set_PatternOctaveMin(-2.0f)
                .Set_PatternOctaveMax(6.0f)
                .Set_PatternScrollSpeed(3.5f)
                .Set_ShadowTint(FLinearColor(0.1f, 0.2f, 0.3f, 1.0f))
                .Set_LightTint(FLinearColor(0.9f, 0.8f, 0.7f, 1.0f))
                .Set_Saturation(1.45f)
                .Set_MinimumAlbedo(0.12f)
                .Set_AffectUnlit(ECk_EnableDisable::Enable)
                .Set_EnableSky(ECk_EnableDisable::Disable)
                .Set_SkyDistance(54321.0f)
                .Set_SkyBands(9)
                .Set_SkyStrength(0.29f)
                .Set_SkyPattern(ECk_Usf_CelPattern::Triangles)
                .Set_SkyPatternStrength(0.77f)
                .Set_SkyPatternScale(4.5f)
                .Set_MetallicThreshold(0.35f)
                .Set_MetallicBands(11)
                .Set_MetallicStrength(0.44f)
                .Set_MetallicPatternStrength(0.55f)
                .Set_EnableSpecular(ECk_EnableDisable::Disable)
                .Set_SpecularSteps(5)
                .Set_SpecularThreshold(0.62f)
                .Set_SpecularIntensity(1.8f)
                .Set_SpecularRoughnessCutoff(0.71f)
                .Set_EnableRimLight(ECk_EnableDisable::Disable)
                .Set_RimPower(6.5f)
                .Set_RimThreshold(0.19f)
                .Set_RimSoftness(0.51f)
                .Set_RimIntensity(2.25f)
                .Set_RimFollowsLighting(0.3f)
                .Set_RimColor(FLinearColor(0.3f, 0.6f, 0.9f, 1.0f))
                .Set_EnableOutline(ECk_EnableDisable::Disable)
                .Set_OutlineThickness(3.5f)
                .Set_OutlineQuality(ECk_Usf_CelOutlineQuality::EightTap)
                .Set_OutlineColor(FLinearColor(0.4f, 0.1f, 0.05f, 1.0f))
                .Set_OutlineBlendMode(ECk_Usf_CelOutlineBlend::Additive)
                .Set_OutlineOpacity(0.72f)
                .Set_OutlineDepthThreshold(0.42f)
                .Set_OutlineNormalThreshold(0.61f)
                .Set_OutlineAlbedoThreshold(0.83f)
                .Set_OutlineDistanceFade(7500.0f)
                .Set_EnableStencilPatterns(ECk_EnableDisable::Enable)
                .Set_StencilBase(120)
                .Set_DebugMode(ECk_Usf_CelShade_DebugMode::PatternThreshold);

        return Settings;
    }

    // The .ush parameter list, in declaration order — the generator binds POSITIONALLY, so this list and
    // CkUsf_CelShadeLook_Assets.as must agree with CkUsf_PP_CelShade or every parameter past the first
    // difference is mis-bound. Stated here independently on purpose: if the AS asset drifts, this test
    // still holds the shader's own signature. It doubles as the list of names the subsystem writes to
    // the MID, which is what the resolution check at the end of CelShadeSubsystemSettings verifies.
    auto Get_ScalarParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("Bands"), TEXT("Midpoint"), TEXT("BandOffset"), TEXT("Distribution"),
            TEXT("BandSoftness"), TEXT("ShadowLift"), TEXT("Strength"), TEXT("QuantizeFinalColor"),

            TEXT("EnablePattern"), TEXT("Pattern"), TEXT("PatternSpace"), TEXT("PatternStrength"),
            TEXT("PatternContrast"), TEXT("PatternWorldSize"), TEXT("PatternPixelSize"),
            TEXT("TriplanarSharpness"), TEXT("PatternDistanceScaling"), TEXT("PatternOctaveMin"),
            TEXT("PatternOctaveMax"), TEXT("PatternScrollSpeed"),

            TEXT("Saturation"), TEXT("MinimumAlbedo"), TEXT("AffectUnlit"),

            TEXT("EnableSky"), TEXT("SkyDistance"), TEXT("SkyBands"), TEXT("SkyStrength"),
            TEXT("SkyPattern"), TEXT("SkyPatternStrength"), TEXT("SkyPatternScale"),

            TEXT("MetallicThreshold"), TEXT("MetallicBands"), TEXT("MetallicStrength"),
            TEXT("MetallicPatternStrength"),

            TEXT("EnableSpecular"), TEXT("SpecularSteps"), TEXT("SpecularThreshold"),
            TEXT("SpecularIntensity"), TEXT("SpecularRoughnessCutoff"),

            TEXT("EnableRimLight"), TEXT("RimPower"), TEXT("RimThreshold"), TEXT("RimSoftness"),
            TEXT("RimIntensity"), TEXT("RimFollowsLighting"),

            TEXT("EnableOutline"), TEXT("OutlineThickness"), TEXT("OutlineQuality"),
            TEXT("OutlineOpacity"), TEXT("OutlineBlendMode"), TEXT("OutlineDepthThreshold"),
            TEXT("OutlineNormalThreshold"), TEXT("OutlineAlbedoThreshold"), TEXT("OutlineDistanceFade"),

            TEXT("EnableStencilPatterns"), TEXT("StencilBase"), TEXT("DebugMode"),
        };
    }

    auto Get_VectorParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("ShadowTint"), TEXT("LightTint"), TEXT("RimColor"), TEXT("OutlineColor"),
        };
    }

    // Resolve every parameter NAME against a MID built from the look's generated master, and return the
    // ones that do not exist. This is the seam a settings round-trip cannot see: SetScalarParameterValue
    // on a name the material does not carry is a SILENT no-op — it neither warns nor fails — so a rename
    // on either side would leave that setting stuck at its authored default with nothing in the log and
    // only a gym screenshot to catch it.
    auto Get_UnresolvedMidParameterNames(
        UMaterialInterface* InMaster,
        const TArray<FString>& InScalarNames,
        const TArray<FString>& InVectorNames) -> TArray<FString>
    {
        auto Unresolved = TArray<FString>{};

        const auto Mid = TStrongObjectPtr<UMaterialInstanceDynamic>{
            UMaterialInstanceDynamic::Create(InMaster, GetTransientPackage())};

        if (Mid.IsValid() == false)
        {
            Unresolved.Add(TEXT("<the master produced no MID>"));
            return Unresolved;
        }

        for (const auto& Name : InScalarNames)
        {
            auto Value = 0.0f;
            if (Mid->GetScalarParameterValue(FHashedMaterialParameterInfo{FName(*Name)}, Value) == false)
            { Unresolved.Add(Name); }
        }

        for (const auto& Name : InVectorNames)
        {
            auto Value = FLinearColor{};
            if (Mid->GetVectorParameterValue(FHashedMaterialParameterInfo{FName(*Name)}, Value) == false)
            { Unresolved.Add(Name); }
        }

        return Unresolved;
    }
}

// --------------------------------------------------------------------------------------------------------------------

#if WITH_EDITOR

namespace ck_test_usf_cel_shade
{
    constexpr auto kCelShadeIncludePath = TEXT("/CkUsf/Looks/CelShade.ush");
    constexpr auto kCelShadeFunctionName = TEXT("CkUsf_PP_CelShade");

    // Throwaway name: the real "CelShade" master is content the gym uses, and the force-compile below
    // leaves whatever it touches rendering black.
    constexpr auto kProbeLookName = TEXT("CelShadeGenerationProbe");

    auto Get_SceneTextureInputNames() -> TArray<FString>
    {
        return
        {
            TEXT("SceneColor"), TEXT("SceneDepth"), TEXT("SceneNormal"), TEXT("CustomStencil"),
            TEXT("SceneBaseColor"), TEXT("SceneMetallic"), TEXT("SceneRoughness"),
        };
    }

    auto Make_ProbeLookDefinition() -> UCkUsf_LookDefinition*
    {
        auto* Definition = NewObject<UCkUsf_LookDefinition>(GetTransientPackage());
        Definition->_LookName = FName(kProbeLookName);
        Definition->_UshIncludePath = kCelShadeIncludePath;
        Definition->_UshFunctionName = FName(kCelShadeFunctionName);
        Definition->_Domain = ECk_Usf_Domain::PostProcess;

        // Custom Stencil is TAA-jittered, so this is the only placement class where the mask resolves —
        // the same one the shipped asset declares, so this arm compiles the permutation the gym renders.
        Definition->_BlendableLocation = ECk_Usf_BlendableLocation::SceneColorAfterDOF;

        Definition->_SceneTextures =
        {
            ECk_Usf_SceneTexture::SceneColor, ECk_Usf_SceneTexture::SceneDepth,
            ECk_Usf_SceneTexture::SceneNormal, ECk_Usf_SceneTexture::CustomStencil,
            ECk_Usf_SceneTexture::BaseColor, ECk_Usf_SceneTexture::Metallic,
            ECk_Usf_SceneTexture::Roughness,
        };
        Definition->_PostProcessWorldPosition = true;

        for (const auto& Name : Get_ScalarParamNames())
        {
            FCk_Usf_ParamDesc Param;
            Param._Name = FName(*Name);
            Param._Type = ECk_Usf_ParamType::Scalar;
            Param._DefaultScalar = 1.0f;
            Definition->_Parameters.Add(Param);
        }

        for (const auto& Name : Get_VectorParamNames())
        {
            FCk_Usf_ParamDesc Param;
            Param._Name = FName(*Name);
            Param._Type = ECk_Usf_ParamType::Vector;
            Param._DefaultVector = FLinearColor::White;
            Definition->_Parameters.Add(Param);
        }

        return Definition;
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

    auto Get_IsCustomInputConnected(const UMaterialExpressionCustom* InCustom, const TCHAR* InInputName) -> bool
    {
        for (const auto& Input : InCustom->Inputs)
        {
            if (Input.InputName == FName(InInputName))
            { return Input.Input.GetTracedInput().Expression != nullptr; }
        }
        return false;
    }

    auto Delete_GeneratedMaster(const FName InLookName) -> bool
    {
        const auto FileName = FPackageName::LongPackageNameToFilename(
            ck::usf::Get_GeneratedMasterPackagePath(InLookName), FPackageName::GetAssetPackageExtension());

        if (NOT IFileManager::Get().FileExists(*FileName))
        { return true; }

        constexpr auto RequireExists = false;
        constexpr auto EvenIfReadOnly = true;
        return IFileManager::Get().Delete(*FileName, RequireExists, EvenIfReadOnly);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CelShadeGeneration,
    "CkTests.UnitTests.CkUsf.CelShadeGeneration",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CelShadeGeneration::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_cel_shade;

    if (FApp::CanEverRender() == false)
    {
        AddInfo(TEXT("Skipped: this process cannot render (e.g. -nullrhi) — generation force-compiles shaders "
                     "and would report the look as failed, which is environmental."));
        return true;
    }

    const auto Probe = TStrongObjectPtr<UCkUsf_LookDefinition>{Make_ProbeLookDefinition()};

    const auto Validation = ck::usf_editor::Validate_LookDefinition(Probe.Get());
    for (const auto& Warning : Validation.Warnings)
    { AddInfo(FString::Printf(TEXT("validator warning: %s"), *Warning)); }
    for (const auto& Error : Validation.Errors)
    { AddError(FString::Printf(TEXT("validator error: %s"), *Error)); }
    if (TestEqual(TEXT("the CelShade look validates with no errors"), Validation.Errors.Num(), 0) == false)
    { return false; }

    auto* Master = ck::usf_editor::Generate_LookMaterial(Probe.Get());
    if (TestNotNull(TEXT("the CelShade look generates a master material"), Master) == false)
    { return false; }

    const auto* Custom = Find_CustomNode(Master);
    if (TestNotNull(TEXT("the CelShade master has a Custom node"), Custom))
    {
        for (const auto& Name : Get_ScalarParamNames())
        {
            TestTrue(*FString::Printf(TEXT("scalar param [%s] is connected"), *Name),
                Get_IsCustomInputConnected(Custom, *Name));
        }

        for (const auto& Name : Get_VectorParamNames())
        {
            TestTrue(*FString::Printf(TEXT("vector param [%s] is connected"), *Name),
                Get_IsCustomInputConnected(Custom, *Name));
        }

        // The GBuffer reads and the stencil are the whole reason this look exists; a missing pin here
        // reads as black in the shader rather than as an error.
        for (const auto& Name : Get_SceneTextureInputNames())
        {
            TestTrue(*FString::Printf(TEXT("scene texture [%s] is wired"), *Name),
                Get_IsCustomInputConnected(Custom, *Name));
        }

        TestTrue(TEXT("the opt-in PostProcess WorldPosition is wired (world-space pattern space)"),
            Get_IsCustomInputConnected(Custom, TEXT("WorldPosition")));
    }

    {
        // Throwaway master, so it can afford the destructive force — which is the only thing that turns
        // "generates" into "compiles".
        constexpr auto ForceSynchronousCompile = true;
        auto Errors = TArray<FString>{};
        const auto Compiled = ck::usf_editor::Validate_LookShaderCompile(
            Master, FName(kProbeLookName), Errors, ForceSynchronousCompile);

        const auto CompileErrors = FString::Join(Errors, TEXT("\n"));
        if (Compiled == false)
        { AddError(CompileErrors); }
        TestEqual(TEXT("CelShade.ush reports no HLSL compile errors"), CompileErrors, FString{});
    }

    if (Delete_GeneratedMaster(FName(kProbeLookName)) == false)
    { AddInfo(TEXT("Could not delete the probe's generated master file — harmless, but it is a stray asset on disk.")); }

    return true;
}

#endif // WITH_EDITOR

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CelShadeSubsystemSettings,
    "CkTests.UnitTests.CkUsf.CelShadeSubsystemSettings",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CelShadeSubsystemSettings::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_cel_shade;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    if (TestNotNull(TEXT("the world carries a CelShade subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    TestTrue(TEXT("a fresh subsystem holds the default settings"),
        Subsystem->Get_Settings() == FCk_Usf_CelShade_Params{});
    TestTrue(TEXT("a fresh subsystem is enabled"),
        Subsystem->Get_IsEnabled() == ECk_EnableDisable::Enable);

    // The default base must leave room for the whole contract below it AND above it — the suppress value
    // is one BELOW the base, which is the off-by-one this pins.
    TestEqual(TEXT("the default stencil span starts at the suppress value, one below the base"),
        FCk_Usf_CelShade_Params{}.Get_StencilRangeMin(), 199);
    TestEqual(TEXT("the default stencil span ends at the last of the ten pattern slots"),
        FCk_Usf_CelShade_Params{}.Get_StencilRangeMax(), 209);

    // The stencil helpers are what the entity API and the gym both resolve values through.
    TestEqual(TEXT("pattern 0 resolves to the base itself"),
        Subsystem->Get_StencilValueFor(ECk_Usf_CelPattern::Bayer), 200);
    TestEqual(TEXT("the last pattern resolves to base + 9"),
        Subsystem->Get_StencilValueFor(ECk_Usf_CelPattern::Spiral), 209);
    TestEqual(TEXT("the suppress value is one below the base"),
        Subsystem->Get_StencilSuppressValue(), 199);

    const auto Settings = Make_NonDefaultSettings();
    Subsystem->Request_SetSettings(Settings);
    TestTrue(TEXT("settings round-trip losslessly"), Subsystem->Get_Settings() == Settings);
    TestTrue(TEXT("Get_IsEnabled reads the settings value, not a second copy of it"),
        Subsystem->Get_IsEnabled() == Settings.Get_Enabled());

    // Idempotency: a repeated set must land on the same state, not toggle it.
    Subsystem->Request_SetEnabled(ECk_EnableDisable::Enable);
    Subsystem->Request_SetEnabled(ECk_EnableDisable::Enable);
    TestTrue(TEXT("enabling twice leaves the subsystem enabled"),
        Subsystem->Get_IsEnabled() == ECk_EnableDisable::Enable);

    Subsystem->Request_SetEnabled(ECk_EnableDisable::Disable);
    Subsystem->Request_SetEnabled(ECk_EnableDisable::Disable);
    TestTrue(TEXT("disabling twice leaves the subsystem disabled"),
        Subsystem->Get_IsEnabled() == ECk_EnableDisable::Disable);

    // Toggling enabled must not disturb anything else.
    auto ExpectedAfterToggle = Settings;
    ExpectedAfterToggle.Set_Enabled(ECk_EnableDisable::Disable);
    TestTrue(TEXT("toggling enabled leaves every other setting untouched"),
        Subsystem->Get_Settings() == ExpectedAfterToggle);

    // The disabled contract yields 0 — the engine's "no stencil written" value, so it can never be
    // mistaken for a slot.
    auto StencilOff = Settings;
    StencilOff.Set_EnableStencilPatterns(ECk_EnableDisable::Disable);
    Subsystem->Request_SetSettings(StencilOff);
    TestEqual(TEXT("a disabled stencil contract resolves every pattern to 0"),
        Subsystem->Get_StencilValueFor(ECk_Usf_CelPattern::RoundDots), 0);
    TestEqual(TEXT("a disabled stencil contract resolves the suppress value to 0"),
        Subsystem->Get_StencilSuppressValue(), 0);

    Subsystem->Request_ResetToDefaults();
    TestTrue(TEXT("reset restores the default settings"),
        Subsystem->Get_Settings() == FCk_Usf_CelShade_Params{});

    // ---- The MID name seam ----
    // Everything above proves the settings VALUE survives; none of it proves the value reaches the
    // shader. The subsystem projects onto the MID purely by name, and an unknown name is written into
    // nothing at all, silently. Unlike the settings arms this one IS gated on the generated master,
    // deliberately: the master is shipped content, and its absence is exactly the "look renders nothing"
    // failure the subsystem warns about at runtime, so a missing one is worth a red rather than a skip.
    {
        const auto MasterPath = ck::usf::Get_GeneratedMasterObjectPath(FName(TEXT("CelShade")));
        auto* Master = LoadObject<UMaterialInterface>(nullptr, *MasterPath);

        if (TestNotNull(*FString::Printf(TEXT("the CelShade master exists at [%s]"), *MasterPath), Master))
        {
            const auto Unresolved = Get_UnresolvedMidParameterNames(
                Master, Get_ScalarParamNames(), Get_VectorParamNames());

            TestEqual(TEXT("every parameter name the subsystem writes resolves on the master's MID"),
                FString::Join(Unresolved, TEXT(", ")), FString{});
        }
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CelShadeInvalidInput,
    "CkTests.UnitTests.CkUsf.CelShadeInvalidInput",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CelShadeInvalidInput::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_cel_shade;

    // ---- 1. An unresolvable world context returns null and does NOT ensure ----
    // Deliberate, and the UCkUsf_OutlineSubsystem::Get_OutlineSubsystem precedent: the accessor is called
    // from actor/EntityScript code that legitimately runs while a world is tearing down or before one
    // exists, so a diagnostic here would fire on correct code.
    TestNull(TEXT("a null world context yields a null subsystem rather than a crash or an ensure"),
        UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(nullptr));

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    auto* Outline = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem(World);
    if (TestNotNull(TEXT("the world carries a CelShade subsystem"), Subsystem) == false ||
        TestNotNull(TEXT("the world carries an Outline subsystem to collide with"), Outline) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    Subsystem->Request_SetSettings(Make_NonDefaultSettings());
    const auto Before = Subsystem->Get_Settings();

    // Each ensure fire emits a log entry plus an Error line, both carrying the message — whitelist by
    // substring without enforcing a count.
    AddExpectedError(TEXT("null CelShade preset"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("COLLIDES with the outline subsystem"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    // ---- 2. A null preset ----
    Subsystem->Apply_Preset(nullptr);

    TestTrue(TEXT("a null preset changes nothing at all — no partial application"),
        Subsystem->Get_Settings() == Before);

    // ---- 3. A stencil base whose span overlaps the outline subsystem's range ----
    // Both features write the same Custom-Stencil byte on a primitive. An accepted overlap would restyle
    // outlined meshes (or suppress transitions on them) with nothing on screen naming the cause.
    const auto OutlineMin = static_cast<int32>(Outline->Get_StencilMin());

    auto Colliding = Before;
    Colliding.Set_EnableStencilPatterns(ECk_EnableDisable::Enable)
             .Set_StencilBase(OutlineMin);

    TestFalse(TEXT("a base inside the outline range is reported as NOT free"),
        Subsystem->Get_StencilRangeIsFree(Colliding));

    Subsystem->Request_SetSettings(Colliding);

    TestTrue(TEXT("a colliding stencil range is rejected and the previous settings survive intact"),
        Subsystem->Get_Settings() == Before);

    // The boundary case: the last base whose span still clears the outline range must be ACCEPTED — the
    // guard has to reject an overlap, not a neighbourhood.
    auto Adjacent = Before;
    Adjacent.Set_EnableStencilPatterns(ECk_EnableDisable::Enable)
            .Set_StencilBase(OutlineMin - FCk_Usf_CelShade_Params::PatternSlots);

    TestTrue(TEXT("the last non-overlapping base is reported as free"),
        Subsystem->Get_StencilRangeIsFree(Adjacent));

    Subsystem->Request_SetSettings(Adjacent);

    TestTrue(TEXT("a range that merely abuts the outline range is accepted"),
        Subsystem->Get_Settings() == Adjacent);

    // The same colliding base with the contract SWITCHED OFF claims no values at all, so it is legal —
    // the guard must gate on the claim, not on the number.
    auto CollidingButDisabled = Colliding;
    CollidingButDisabled.Set_EnableStencilPatterns(ECk_EnableDisable::Disable);

    TestTrue(TEXT("a disabled stencil contract claims nothing and so cannot collide"),
        Subsystem->Get_StencilRangeIsFree(CollidingButDisabled));

    // ---- 4. A span that reaches Custom Stencil 0 ----
    // 0 is what the renderer leaves for every mesh that wrote nothing, so a span touching it hands the
    // whole untagged view a slot: base 1 makes suppression the view-wide default, base 0 forces pattern 0
    // on every pixel. Neither reads as a misconfiguration on screen — it reads as the look being broken.
    AddExpectedError(TEXT("reaches the engine's NO-STENCIL value"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    const auto Accepted = Subsystem->Get_Settings();

    auto BaseOne = Accepted;
    BaseOne.Set_EnableStencilPatterns(ECk_EnableDisable::Enable).Set_StencilBase(1);

    TestFalse(TEXT("base 1 (whose suppress value is the engine's 0) is reported as NOT free"),
        Subsystem->Get_StencilRangeIsFree(BaseOne));

    Subsystem->Request_SetSettings(BaseOne);

    TestTrue(TEXT("a span reaching stencil 0 is rejected and the previous settings survive intact"),
        Subsystem->Get_Settings() == Accepted);

    // The first base that clears 0 must be accepted — the guard rejects reaching it, not being near it.
    auto BaseTwo = Accepted;
    BaseTwo.Set_EnableStencilPatterns(ECk_EnableDisable::Enable).Set_StencilBase(2);

    TestTrue(TEXT("base 2 — the lowest whose suppress value is still addressable — is free"),
        Subsystem->Get_StencilRangeIsFree(BaseTwo));

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CelShadeEntityPattern,
    "CkTests.UnitTests.CkUsf.CelShadeEntityPattern",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CelShadeEntityPattern::RunTest(const FString& Parameters)
{
    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    auto Subject = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto Dependent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Subject);
    auto GrandDependent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Dependent);

    constexpr auto Fallback = ECk_Usf_CelPattern::Bayer;

    TestFalse(TEXT("a fresh entity carries no cel pattern"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(Subject));
    TestTrue(TEXT("reading a pattern off an entity that has none returns the caller's fallback"),
        UCk_Utils_Usf_CelPattern_UE::Get_CelPatternOr(Subject, Fallback) == Fallback);

    // ---- 1. EntityOnly ----
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Subject, ECk_Usf_CelPattern::Crosshatch, ECk_Usf_OutlineScope::EntityOnly, {});

    TestTrue(TEXT("the requested entity carries the pattern"),
        UCk_Utils_Usf_CelPattern_UE::Get_CelPatternOr(Subject, Fallback) == ECk_Usf_CelPattern::Crosshatch);
    TestFalse(TEXT("EntityOnly does NOT reach the entity's lifetime dependents"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(Dependent));

    // ---- 2. EntityAndDependents cascades recursively ----
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Subject, ECk_Usf_CelPattern::Spiral, ECk_Usf_OutlineScope::EntityAndDependents, {});

    TestTrue(TEXT("the cascade reaches a direct dependent"),
        UCk_Utils_Usf_CelPattern_UE::Get_CelPatternOr(Dependent, Fallback) == ECk_Usf_CelPattern::Spiral);
    TestTrue(TEXT("the cascade recurses to a dependent of a dependent"),
        UCk_Utils_Usf_CelPattern_UE::Get_CelPatternOr(GrandDependent, Fallback) == ECk_Usf_CelPattern::Spiral);
    TestFalse(TEXT("the explicitly requested entity's target is NOT marked cascade-derived"),
        Subject.Get<ck::FFragment_Usf_CelPatternTarget>().Get_IsCascadeDerived());
    TestTrue(TEXT("a dependent's target IS marked cascade-derived"),
        Dependent.Get<ck::FFragment_Usf_CelPatternTarget>().Get_IsCascadeDerived());

    // ---- 3. An explicit dependent survives a later cascade ----
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Dependent, ECk_Usf_CelPattern::Lines, ECk_Usf_OutlineScope::EntityOnly, {});
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Subject, ECk_Usf_CelPattern::Triangles, ECk_Usf_OutlineScope::EntityAndDependents, {});

    TestTrue(TEXT("a cascade never downgrades an explicitly patterned dependent"),
        UCk_Utils_Usf_CelPattern_UE::Get_CelPatternOr(Dependent, Fallback) == ECk_Usf_CelPattern::Lines);

    // ---- 4. Clear strips the root and the DERIVED dependents only ----
    UCk_Utils_Usf_CelPattern_UE::Request_ClearCelPattern(Subject, {});

    TestFalse(TEXT("clear removes the root's pattern"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(Subject));
    TestTrue(TEXT("clear leaves an explicitly patterned dependent alone"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(Dependent));
    TestFalse(TEXT("clear strips a cascade-derived dependent"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(GrandDependent));

    // ---- 5. One entity, one Custom-Stencil value ----
    // An entity outline already owns that byte, so accepting a cel pattern here would silently replace
    // the silhouette the caller asked for.
    AddExpectedError(TEXT("already carries an OUTLINE target"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto Outlined = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto* Preset = NewObject<UCkUsf_OutlinePreset>(GetTransientPackage());
    UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(
        Outlined, Preset, ECk_Usf_OutlineScope::EntityOnly, {});

    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Outlined, ECk_Usf_CelPattern::RoundDots, ECk_Usf_OutlineScope::EntityOnly, {});

    TestFalse(TEXT("an outlined entity is refused a cel pattern, and nothing is stamped"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(Outlined));
    TestTrue(TEXT("the refused request leaves the outline target intact"),
        UCk_Utils_Usf_Outline_UE::Has_Outline(Outlined));

    // ---- 6. A cascade SKIPS an outlined dependent instead of failing whole ----
    // The caller asked about the root; refusing the entire cascade because one leaf is outlined would
    // lose more than it protects. The direct request on that leaf is still refused loudly (arm 5).
    auto CascadeRoot = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    auto PlainChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CascadeRoot);
    auto OutlinedChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CascadeRoot);

    UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(
        OutlinedChild, Preset, ECk_Usf_OutlineScope::EntityOnly, {});

    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        CascadeRoot, ECk_Usf_CelPattern::SquareDots, ECk_Usf_OutlineScope::EntityAndDependents, {});

    TestTrue(TEXT("the cascade reaches an ordinary dependent"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(PlainChild));
    TestFalse(TEXT("the cascade skips a dependent that already carries an outline target"),
        UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(OutlinedChild));
    TestTrue(TEXT("the skipped dependent keeps its outline"),
        UCk_Utils_Usf_Outline_UE::Has_Outline(OutlinedChild));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The entity API's OTHER half: the fragment is only a declaration, and what the feature actually promises
// is a Custom-Stencil value on the entity's primitives. Everything above this line would still pass if the
// sync processor did nothing at all.
//
// ForEachEntity is driven directly rather than through a scheduler pump: these are the exact statics the
// scheduler calls, and invoking them by hand is what lets one test step an entity through the
// cel -> outline -> outline-removed sequence deterministically.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CelShadeEntityStencilSync,
    "CkTests.UnitTests.CkUsf.CelShadeEntityStencilSync",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CelShadeEntityStencilSync::RunTest(const FString& Parameters)
{
    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_CelShadeSubsystem::Get_CelShadeSubsystem(World);
    if (TestNotNull(TEXT("the world carries a CelShade subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    auto* Actor = World->SpawnActor<AActor>(AActor::StaticClass(), FActorSpawnParameters{});
    if (TestNotNull(TEXT("a subject actor spawns"), Actor) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    auto* Primitive = NewObject<UStaticMeshComponent>(Actor);
    Actor->SetRootComponent(Primitive);
    Primitive->RegisterComponent();

    TestFalse(TEXT("the subject starts with custom depth OFF"), Primitive->bRenderCustomDepth);

    auto  EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);
    UCk_Utils_OwningActor_UE::Add(Entity, Actor);

    const auto Sync = [&Entity]() -> void
    {
        ck::FProcessor_Usf_CelPatternActor_Sync::ForEachEntity(
            ck::FProcessor_Usf_CelPatternActor_Sync::TimeType{}, Entity,
            Entity.Get<ck::FFragment_Usf_CelPatternTarget>(),
            Entity.Get<ck::FFragment_OwningActor_Current>());
    };

    constexpr auto Pattern = ECk_Usf_CelPattern::Crosshatch;
    const auto ExpectedStencil = Subsystem->Get_StencilValueFor(Pattern);

    // ---- 1. Apply reaches the primitive ----
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Entity, Pattern, ECk_Usf_OutlineScope::EntityOnly, {});
    Sync();

    TestTrue(TEXT("the sync processor turns custom depth ON for the entity's primitive"),
        Primitive->bRenderCustomDepth);
    TestEqual(TEXT("the primitive carries the stencil value the contract resolves for that pattern"),
        Primitive->CustomDepthStencilValue, ExpectedStencil);
    TestTrue(TEXT("the applied-state records what was written"),
        Entity.Has<ck::FFragment_Usf_CelPatternApplied_Actor>());

    // ---- 2. Changing the pattern rewrites the value ----
    // The applied-state is a cache; if it is compared on the wrong fields this is where it shows.
    constexpr auto SecondPattern = ECk_Usf_CelPattern::Spiral;
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Entity, SecondPattern, ECk_Usf_OutlineScope::EntityOnly, {});
    Sync();

    TestEqual(TEXT("a changed pattern rewrites the primitive's stencil value"),
        Primitive->CustomDepthStencilValue, Subsystem->Get_StencilValueFor(SecondPattern));

    // ---- 3. Clear DISABLES custom depth (it does not restore a prior value) ----
    // Matching UCkUsf_OutlineSubsystem::Remove_Outline_From_Component, which also only disables. Stated as
    // "disabled" rather than "restored" so the shared limitation is visible from the test name alone: a
    // mesh that was hand-authored to render custom depth does not get that back.
    UCk_Utils_Usf_CelPattern_UE::Request_ClearCelPattern(Entity, {});
    ck::FProcessor_Usf_CelPatternActor_Remove::ForEachEntity(
        ck::FProcessor_Usf_CelPatternActor_Remove::TimeType{}, Entity,
        Entity.Get<ck::FFragment_Usf_CelPatternApplied_Actor>());

    TestFalse(TEXT("clear DISABLES custom depth on the primitive (outline precedent: no prior-state restore)"),
        Primitive->bRenderCustomDepth);
    TestFalse(TEXT("clear drops the applied-state"),
        Entity.Has<ck::FFragment_Usf_CelPatternApplied_Actor>());

    // ---- 4. The outline round trip ----
    // An outline takes the byte over, then goes away again. The cel pattern MUST come back: the applied-
    // state left behind by step 1 would otherwise make the sync processor early-out on a cache describing
    // a value the outline has since overwritten, and the pattern would be gone for the entity's lifetime.
    UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(
        Entity, Pattern, ECk_Usf_OutlineScope::EntityOnly, {});
    Sync();
    TestEqual(TEXT("the pattern is re-applied to the primitive"),
        Primitive->CustomDepthStencilValue, ExpectedStencil);

    // The outline arrives. Its own subsystem owns the write; what matters here is that the cel feature
    // drops its now-false cache and does NOT clear the byte.
    Entity.AddOrGet<ck::FFragment_Usf_OutlineTarget>() = ck::FFragment_Usf_OutlineTarget{nullptr, false};
    constexpr auto OutlineStencil = 241;
    Primitive->SetCustomDepthStencilValue(OutlineStencil);

    ck::FProcessor_Usf_CelPatternActor_DropAppliedOnOutline::ForEachEntity(
        ck::FProcessor_Usf_CelPatternActor_DropAppliedOnOutline::TimeType{}, Entity,
        Entity.Get<ck::FFragment_Usf_CelPatternApplied_Actor>(),
        Entity.Get<ck::FFragment_Usf_OutlineTarget>());

    TestFalse(TEXT("an arriving outline drops the cel applied-state, which no longer describes reality"),
        Entity.Has<ck::FFragment_Usf_CelPatternApplied_Actor>());
    TestEqual(TEXT("dropping the cache does NOT touch the byte the outline now owns"),
        Primitive->CustomDepthStencilValue, OutlineStencil);
    TestTrue(TEXT("the outline's custom depth is left enabled"), Primitive->bRenderCustomDepth);

    // The outline leaves. The cel target never went away, so the pattern must return.
    Entity.Remove<ck::FFragment_Usf_OutlineTarget>();
    Sync();

    TestEqual(TEXT("with the outline gone the cel pattern returns to the primitive"),
        Primitive->CustomDepthStencilValue, ExpectedStencil);
    TestTrue(TEXT("custom depth is still on after the round trip"), Primitive->bRenderCustomDepth);

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
