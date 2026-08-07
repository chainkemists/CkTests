// Contract tests for the CkUsf CrossHatch feature. Three tests, three distinct failure modes:
//
//   CrossHatchGeneration — the asset<->HLSL contract. A LookDefinition shaped exactly like
//     Script/CkUsf/CkUsf_CrossHatchLook_Assets.as is built in code, validated, generated, checked pin by
//     pin, and FORCE-compiled. Editor-only and skipped when the process cannot render, for the same
//     reason StylizeParamCount is. The force is what makes "CrossHatch.ush compiles" a real claim rather
//     than a pending shader job — it is destructive, hence a throwaway master that is deleted again.
//     SceneNormal and CustomStencil each get their own assertion: the hatch DIRECTION is the projected
//     normal, and the effect mask is the stencil, and both degrade SILENTLY if the input is dropped
//     (every stroke would run at AngleOffset; every pixel would read as untagged).
//
//   CrossHatchSubsystemSettings — the subsystem's settings value is the source of truth: a round-trip
//     must be lossless and enable/disable must be idempotent. The settings half is deliberately NOT
//     gated on the generated master existing: settings are tracked whether or not there is anything to
//     render them with, and a test that silently needed content would pass vacuously on a fresh
//     checkout. The MID-name half at the end IS gated on it, on purpose — see the comment there.
//
//   CrossHatchInvalidInput — the rejection boundary. A null preset and an unusable effect-mask range are
//     each rejected LOUDLY and change NOTHING. The "nothing" half is the one worth testing: a partial
//     application would leave the world in a state no preset describes. The null world context is
//     covered here too — by design it does not ensure; see the body.

#include "Misc/AutomationTest.h"

#include "Engine/World.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"
#include "CkUsf/Stylize/CkUsf_CrossHatchPreset.h"
#include "CkUsf/Stylize/CkUsf_CrossHatchSubsystem.h"
#include "CkUsf/Stylize/CkUsf_CrossHatch_Params.h"

#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialParameters.h"
#include "UObject/StrongObjectPtr.h"

#include "../CkUnitTest_Common.h"

#if WITH_EDITOR
#include "Misc/App.h"
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"
#include "CkUsfEditor/Generator/CkUsf_LookValidator.h"

#include "CkUsf_TestLookMasters.h"
#endif

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_cross_hatch
{
    // A settings value that differs from the defaults in EVERY field, so a round-trip that drops one is
    // caught rather than masked by a default that happened to match. The mask range is ordered and clear
    // of both other stencil claimants — an unusable one is the InvalidInput test's subject, not this one's.
    auto Make_NonDefaultSettings() -> FCk_Usf_CrossHatch_Params
    {
        auto Mask = FCk_Usf_StylizeMask_Params{};
        Mask.Set_Mode(ECk_Usf_StylizeMaskMode::ExcludeStencilRange)
            .Set_StencilMin(180)
            .Set_StencilMax(185);

        auto Settings = FCk_Usf_CrossHatch_Params{};

        Settings.Set_Enabled(ECk_EnableDisable::Disable)
                .Set_StyleStrength(0.37f)
                .Set_UseWorldSpaceNormals(ECk_EnableDisable::Enable)
                .Set_AngleOffset(-115.0f)
                .Set_NormalAlignment(0.42f)
                .Set_Spacing(21.5f)
                .Set_LayerCount(2)
                .Set_LayerAngleStep(93.0f)
                .Set_StrokePattern(ECk_Usf_HandDrawnStrokePattern::Stipple)
                .Set_StrokeThickness(0.83f)
                .Set_StrokeIrregularity(0.91f)
                .Set_DarknessBias(-0.24f)
                .Set_DarknessContrast(2.6f)
                .Set_BackgroundMode(ECk_Usf_CrossHatchBackground::Scene)
                .Set_PaperColor(FLinearColor(0.3f, 0.6f, 0.9f, 1.0f))
                .Set_InkColor(FLinearColor(0.7f, 0.1f, 0.4f, 1.0f))
                .Set_Saturation(1.7f)
                .Set_AffectSky(ECk_EnableDisable::Enable)
                .Set_SkyDistance(64321.0f)
                .Set_Mask(Mask)
                .Set_DebugMode(ECk_Usf_CrossHatch_DebugMode::HatchDirection);

        return Settings;
    }

    // The .ush parameter list, in declaration order — the generator binds POSITIONALLY, so this list and
    // CkUsf_CrossHatchLook_Assets.as must agree with CkUsf_PP_CrossHatch or every parameter past the
    // first difference is mis-bound. Stated here independently on purpose: if the AS asset drifts, this
    // test still holds the shader's own signature. It doubles as the list of names the subsystem writes
    // to the MID, which is what the resolution check at the end of CrossHatchSubsystemSettings verifies.
    auto Get_ScalarParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("StyleStrength"),
            TEXT("UseWorldSpaceNormals"), TEXT("AngleOffset"), TEXT("NormalAlignment"),
            TEXT("Spacing"), TEXT("LayerCount"), TEXT("LayerAngleStep"), TEXT("StrokePattern"),
            TEXT("StrokeThickness"), TEXT("StrokeIrregularity"),
            TEXT("DarknessBias"), TEXT("DarknessContrast"),
            TEXT("BackgroundMode"), TEXT("Saturation"),
            TEXT("AffectSky"), TEXT("SkyDistance"),
            TEXT("DebugMode"),
            TEXT("MaskMode"), TEXT("MaskStencilMin"), TEXT("MaskStencilMax"),
        };
    }

    auto Get_VectorParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("InkColor"), TEXT("PaperColor"),
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

namespace ck_test_usf_cross_hatch
{
    constexpr auto kCrossHatchIncludePath = TEXT("/CkUsf/Looks/CrossHatch.ush");
    constexpr auto kCrossHatchFunctionName = TEXT("CkUsf_PP_CrossHatch");

    // Throwaway name: the real "CrossHatch" master is content the gym uses, and the force-compile below
    // leaves whatever it touches rendering black.
    constexpr auto kProbeLookName = TEXT("CrossHatchGenerationProbe");

    auto Make_ProbeLookDefinition() -> UCkUsf_LookDefinition*
    {
        auto* Definition = NewObject<UCkUsf_LookDefinition>(GetTransientPackage());
        Definition->_LookName = FName(kProbeLookName);
        Definition->_UshIncludePath = kCrossHatchIncludePath;
        Definition->_UshFunctionName = FName(kCrossHatchFunctionName);
        Definition->_Domain = ECk_Usf_Domain::PostProcess;
        // Pre-TAA, the same placement the shipped asset declares — so this arm compiles the permutation
        // the gym actually renders, and the stencil mask sees a temporally resolved buffer.
        Definition->_BlendableLocation = ECk_Usf_BlendableLocation::SceneColorAfterDOF;
        Definition->_SceneTextures =
        {
            ECk_Usf_SceneTexture::SceneColor, ECk_Usf_SceneTexture::SceneDepth,
            ECk_Usf_SceneTexture::SceneNormal, ECk_Usf_SceneTexture::CustomStencil,
        };

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
            Param._DefaultVector = FLinearColor::Black;
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
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CrossHatchGeneration,
    "CkTests.UnitTests.CkUsf.CrossHatchGeneration",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CrossHatchGeneration::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_cross_hatch;

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
    if (TestEqual(TEXT("the CrossHatch look validates with no errors"), Validation.Errors.Num(), 0) == false)
    { return false; }

    auto* Master = ck::usf_editor::Generate_LookMaterial(Probe.Get(), ck_test_usf::Get_TestPackageRoot());
    if (TestNotNull(TEXT("the CrossHatch look generates a master material"), Master) == false)
    { return false; }

    const auto* Custom = Find_CustomNode(Master);
    if (TestNotNull(TEXT("the CrossHatch master has a Custom node"), Custom))
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

        TestTrue(TEXT("SceneColor is wired"), Get_IsCustomInputConnected(Custom, TEXT("SceneColor")));
        TestTrue(TEXT("SceneDepth is wired"), Get_IsCustomInputConnected(Custom, TEXT("SceneDepth")));

        // The hatch DIRECTION is the projected scene normal. Without this input every stroke would run at
        // AngleOffset and the look would silently become a screen-space texture — the one thing that
        // separates hatching from a pattern overlay, gone with nothing failing.
        TestTrue(TEXT("SceneNormal is wired (the hatch direction IS the projected normal)"),
            Get_IsCustomInputConnected(Custom, TEXT("SceneNormal")));

        // Without this the effect mask silently degrades: In.CustomStencil reads zero, every pixel looks
        // untagged, and an IncludeStencilRange mask hides the whole look with nothing failing.
        TestTrue(TEXT("CustomStencil is wired (the effect mask needs it)"),
            Get_IsCustomInputConnected(Custom, TEXT("CustomStencil")));

        // The stroke lattice is screen-space by construction, so opting into the world-position
        // reconstruction would cost a pin and an expression for nothing.
        TestFalse(TEXT("WorldPosition is NOT wired — the hatch lattice is screen-space"),
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
        TestEqual(TEXT("CrossHatch.ush reports no HLSL compile errors"), CompileErrors, FString{});
    }

    if (ck_test_usf::Delete_TestGeneratedMaster(FName(kProbeLookName)) == false)
    { AddInfo(TEXT("Could not delete the probe's generated master file — harmless, but it is a stray asset on disk.")); }

    return true;
}

#endif // WITH_EDITOR

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_CrossHatchSubsystemSettings,
    "CkTests.UnitTests.CkUsf.CrossHatchSubsystemSettings",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CrossHatchSubsystemSettings::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_cross_hatch;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem(World);
    if (TestNotNull(TEXT("the world carries a CrossHatch subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    TestTrue(TEXT("a fresh subsystem holds the default settings"),
        Subsystem->Get_Settings() == FCk_Usf_CrossHatch_Params{});
    TestTrue(TEXT("a fresh subsystem is enabled"),
        Subsystem->Get_IsEnabled() == ECk_EnableDisable::Enable);

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

    Subsystem->Request_ResetToDefaults();
    TestTrue(TEXT("reset restores the default settings"),
        Subsystem->Get_Settings() == FCk_Usf_CrossHatch_Params{});

    // ---- The MID name seam ----
    // Everything above proves the settings VALUE survives; none of it proves the value reaches the
    // shader. The subsystem projects onto the MID purely by name, and an unknown name is written into
    // nothing at all, silently. Unlike the settings arms this one IS gated on the generated master,
    // deliberately: the master is shipped content, and its absence is exactly the "look renders nothing"
    // failure the subsystem warns about at runtime, so a missing one is worth a red rather than a skip.
    {
        const auto MasterPath = ck::usf::Get_GeneratedMasterObjectPath(FName(TEXT("CrossHatch")));
        auto* Master = LoadObject<UMaterialInterface>(nullptr, *MasterPath);

        if (TestNotNull(*FString::Printf(TEXT("the CrossHatch master exists at [%s]"), *MasterPath), Master))
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
    FCkTest_Usf_CrossHatchInvalidInput,
    "CkTests.UnitTests.CkUsf.CrossHatchInvalidInput",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_CrossHatchInvalidInput::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_cross_hatch;

    // ---- 1. An unresolvable world context returns null and does NOT ensure ----
    // Deliberate, and the UCkUsf_OutlineSubsystem::Get_OutlineSubsystem precedent: the accessor is called
    // from actor/EntityScript code that legitimately runs while a world is tearing down or before one
    // exists, so a diagnostic here would fire on correct code.
    TestNull(TEXT("a null world context yields a null subsystem rather than a crash or an ensure"),
        UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem(nullptr));

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_CrossHatchSubsystem::Get_CrossHatchSubsystem(World);
    if (TestNotNull(TEXT("the world carries a CrossHatch subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    Subsystem->Request_SetSettings(Make_NonDefaultSettings());
    const auto Before = Subsystem->Get_Settings();

    // Each ensure fire emits a log entry plus an Error line, both carrying the message — whitelist by
    // substring without enforcing a count.
    AddExpectedError(TEXT("null CrossHatch preset"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("effect-mask range"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    // ---- 2. A null preset ----
    Subsystem->Apply_Preset(nullptr);

    TestTrue(TEXT("a null preset changes nothing at all — no partial application"),
        Subsystem->Get_Settings() == Before);

    // ---- 3. An inverted effect-mask range ----
    // It matches NO stencil value, so IncludeStencilRange would render the look nowhere and
    // ExcludeStencilRange everywhere — in both directions the setting stops meaning what it says with
    // nothing in the frame naming the cause.
    {
        auto InvertedMask = FCk_Usf_StylizeMask_Params{};
        InvertedMask.Set_Mode(ECk_Usf_StylizeMaskMode::IncludeStencilRange)
                    .Set_StencilMin(200)
                    .Set_StencilMax(190);

        auto Inverted = Make_NonDefaultSettings();
        Inverted.Set_Mask(InvertedMask);

        Subsystem->Request_SetSettings(Inverted);

        TestTrue(TEXT("an inverted mask range is rejected and the previous settings survive intact"),
            Subsystem->Get_Settings() == Before);
    }

    // ---- 4. A mask range reaching Custom Stencil 0 ----
    // 0 is what the renderer leaves for every mesh that wrote nothing, so a range containing it hands
    // the whole untagged view membership.
    {
        auto ZeroMask = FCk_Usf_StylizeMask_Params{};
        ZeroMask.Set_Mode(ECk_Usf_StylizeMaskMode::IncludeStencilRange)
                .Set_StencilMin(0)
                .Set_StencilMax(5);

        auto ReachesZero = Make_NonDefaultSettings();
        ReachesZero.Set_Mask(ZeroMask);

        Subsystem->Request_SetSettings(ReachesZero);

        TestTrue(TEXT("a mask range reaching stencil 0 is rejected and changes nothing"),
            Subsystem->Get_Settings() == Before);
    }

    // ---- 5. The legitimate neighbours of that boundary ----
    // The guard must reject an unusable RANGE, not the feature. Off claims no stencil at all, so its
    // bounds are never examined; a single-value ordered range is the ordinary case.
    {
        auto OffMask = FCk_Usf_StylizeMask_Params{};
        OffMask.Set_Mode(ECk_Usf_StylizeMaskMode::Off)
               .Set_StencilMin(200)
               .Set_StencilMax(190);

        auto MaskOff = Make_NonDefaultSettings();
        MaskOff.Set_Mask(OffMask);

        Subsystem->Request_SetSettings(MaskOff);

        TestTrue(TEXT("an Off mask claims no stencil, so even an inverted range is accepted"),
            Subsystem->Get_Settings() == MaskOff);
    }

    {
        auto SingleMask = FCk_Usf_StylizeMask_Params{};
        SingleMask.Set_Mode(ECk_Usf_StylizeMaskMode::IncludeStencilRange)
                  .Set_StencilMin(190)
                  .Set_StencilMax(190);

        auto SingleValue = Make_NonDefaultSettings();
        SingleValue.Set_Mask(SingleMask);

        Subsystem->Request_SetSettings(SingleValue);

        TestTrue(TEXT("a single-value mask range is accepted"),
            Subsystem->Get_Settings() == SingleValue);
    }

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
