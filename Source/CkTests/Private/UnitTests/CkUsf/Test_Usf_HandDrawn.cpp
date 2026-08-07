// Gate for the CkUsf HandDrawn feature. Three tests, three distinct failure modes:
//
//   HandDrawnGeneration — the asset<->HLSL contract. A LookDefinition shaped exactly like
//     Script/CkUsf/CkUsf_HandDrawnLook_Assets.as is built in code, validated, generated, checked pin by
//     pin, and FORCE-compiled. Editor-only and skipped when the process cannot render, for the same
//     reason StylizeParamCount is. The force is what makes "HandDrawn.ush compiles" a real claim rather
//     than a pending shader job — it is destructive, hence a throwaway master that is deleted again.
//     The WorldPosition pin gets its own assertion: it is an OPT-IN the world-attached stroke space
//     depends on entirely, and without it In.WorldPosition would read zero and the strokes would look
//     screen-locked with nothing failing.
//
//   HandDrawnSubsystemSettings — the subsystem's settings value is the source of truth: a round-trip
//     must be lossless and enable/disable must be idempotent. The settings half is deliberately NOT
//     gated on the generated master existing: settings are tracked whether or not there is anything to
//     render them with, and a test that silently needed content would pass vacuously on a fresh
//     checkout. The MID-name half at the end IS gated on it, on purpose — see the comment there.
//
//   HandDrawnInvalidInput — the rejection boundary. A null preset and an INVERTED ink fade range are
//     each rejected LOUDLY and change NOTHING. The "nothing" half is the one worth testing: a partial
//     application would leave the world in a state no preset describes, and an inverted fade collapses
//     the shader's ramp into a hard cutoff at the end distance — the setting silently stops being a
//     fade. The null world context is covered here too — by design it does not ensure; see the body.

#include "Misc/AutomationTest.h"

#include "Engine/World.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"
#include "CkUsf/Stylize/CkUsf_HandDrawnPreset.h"
#include "CkUsf/Stylize/CkUsf_HandDrawnSubsystem.h"
#include "CkUsf/Stylize/CkUsf_HandDrawn_Params.h"

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

#include "CkUsf_TestLookMasters.h"
#endif

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_hand_drawn
{
    // A settings value that differs from the defaults in EVERY field, so a round-trip that drops one is
    // caught rather than masked by a default that happened to match. The ink fade range is ordered — an
    // inverted one is the InvalidInput test's subject, not this one's.
    auto Make_NonDefaultSettings() -> FCk_Usf_HandDrawn_Params
    {
        auto Settings = FCk_Usf_HandDrawn_Params{};

        Settings.Set_Enabled(ECk_EnableDisable::Disable)
                .Set_StyleStrength(0.42f)
                .Set_SimplifyColor(ECk_EnableDisable::Disable)
                .Set_ColorLevels(11)
                .Set_ColorSoftness(0.77f)
                .Set_Saturation(1.4f)
                .Set_Contrast(0.6f)
                .Set_ShadowTint(FLinearColor(0.1f, 0.2f, 0.3f, 1.0f))
                .Set_HighlightTint(FLinearColor(0.9f, 0.8f, 0.7f, 1.0f))
                .Set_TintStrength(0.9f)
                .Set_AffectSky(ECk_EnableDisable::Enable)
                .Set_SkyDistance(54321.0f)
                .Set_EnableInk(ECk_EnableDisable::Disable)
                .Set_InkColor(FLinearColor(0.3f, 0.1f, 0.2f, 1.0f))
                .Set_InkThickness(4.5f)
                .Set_InkOpacity(0.33f)
                .Set_DepthThreshold(0.44f)
                .Set_NormalThreshold(0.55f)
                .Set_ColorEdgeThreshold(0.66f)
                .Set_LineVariation(3.1f)
                .Set_LineScale(77.0f)
                .Set_InkFadeStartDistance(1500.0f)
                .Set_InkFadeEndDistance(4500.0f)
                .Set_EnableShadowStrokes(ECk_EnableDisable::Disable)
                .Set_StrokePattern(ECk_Usf_HandDrawnStrokePattern::Stipple)
                .Set_StrokeSpace(ECk_Usf_HandDrawnStrokeSpace::WorldAttached)
                .Set_StrokeStrength(0.21f)
                .Set_StrokeShadowThreshold(0.81f)
                .Set_StrokePixelSize(13.0f)
                .Set_StrokeWorldSize(29.0f)
                .Set_StrokeIrregularity(0.95f)
                .Set_StrokeTriplanarSharpness(7.5f)
                .Set_EnablePaper(ECk_EnableDisable::Disable)
                .Set_GrainStrength(0.66f)
                .Set_GrainScale(5.5f)
                .Set_FiberStrength(0.44f)
                .Set_PaperWarmth(0.15f)
                .Set_DebugMode(ECk_Usf_HandDrawn_DebugMode::ShadowStrokeMask);

        return Settings;
    }

    // The .ush parameter list, in declaration order — the generator binds POSITIONALLY, so this list and
    // CkUsf_HandDrawnLook_Assets.as must agree with CkUsf_PP_HandDrawn or every parameter past the first
    // difference is mis-bound. Stated here independently on purpose: if the AS asset drifts, this test
    // still holds the shader's own signature. It doubles as the list of names the subsystem writes to the
    // MID, which is what the resolution check at the end of HandDrawnSubsystemSettings verifies.
    auto Get_ScalarParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("StyleStrength"),
            TEXT("SimplifyColor"), TEXT("ColorLevels"), TEXT("ColorSoftness"), TEXT("Saturation"),
            TEXT("Contrast"), TEXT("TintStrength"), TEXT("AffectSky"), TEXT("SkyDistance"),
            TEXT("EnableInk"), TEXT("InkThickness"), TEXT("InkOpacity"), TEXT("DepthThreshold"),
            TEXT("NormalThreshold"), TEXT("ColorEdgeThreshold"), TEXT("LineVariation"),
            TEXT("LineScale"), TEXT("InkFadeStartDistance"), TEXT("InkFadeEndDistance"),
            TEXT("EnableShadowStrokes"), TEXT("StrokePattern"), TEXT("StrokeSpace"),
            TEXT("StrokeStrength"), TEXT("StrokeShadowThreshold"), TEXT("StrokePixelSize"),
            TEXT("StrokeWorldSize"), TEXT("StrokeIrregularity"), TEXT("StrokeTriplanarSharpness"),
            TEXT("EnablePaper"), TEXT("GrainStrength"), TEXT("GrainScale"), TEXT("FiberStrength"),
            TEXT("PaperWarmth"),
            TEXT("DebugMode"),
        };
    }

    auto Get_VectorParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("ShadowTint"), TEXT("HighlightTint"), TEXT("InkColor"),
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

namespace ck_test_usf_hand_drawn
{
    constexpr auto kHandDrawnIncludePath = TEXT("/CkUsf/Looks/HandDrawn.ush");
    constexpr auto kHandDrawnFunctionName = TEXT("CkUsf_PP_HandDrawn");

    // Throwaway name: the real "HandDrawn" master is content the gym uses, and the force-compile below
    // leaves whatever it touches rendering black.
    constexpr auto kProbeLookName = TEXT("HandDrawnGenerationProbe");

    auto Make_ProbeLookDefinition() -> UCkUsf_LookDefinition*
    {
        auto* Definition = NewObject<UCkUsf_LookDefinition>(GetTransientPackage());
        Definition->_LookName = FName(kProbeLookName);
        Definition->_UshIncludePath = kHandDrawnIncludePath;
        Definition->_UshFunctionName = FName(kHandDrawnFunctionName);
        Definition->_Domain = ECk_Usf_Domain::PostProcess;
        // Pre-TAA, the same placement the shipped asset declares — so this arm compiles the permutation
        // the gym actually renders, and the WorldPosition reconstruction is the un-scaled one.
        Definition->_BlendableLocation = ECk_Usf_BlendableLocation::SceneColorAfterDOF;
        // The whole world-attached stroke space rides on this opt-in.
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
    FCkTest_Usf_HandDrawnGeneration,
    "CkTests.UnitTests.CkUsf.HandDrawnGeneration",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_HandDrawnGeneration::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_hand_drawn;

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
    if (TestEqual(TEXT("the HandDrawn look validates with no errors"), Validation.Errors.Num(), 0) == false)
    { return false; }

    auto* Master = ck::usf_editor::Generate_LookMaterial(Probe.Get(), ck_test_usf::Get_TestPackageRoot());
    if (TestNotNull(TEXT("the HandDrawn look generates a master material"), Master) == false)
    { return false; }

    const auto* Custom = Find_CustomNode(Master);
    if (TestNotNull(TEXT("the HandDrawn master has a Custom node"), Custom))
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

        // The default trio: the ink detectors tap depth and normal, the sky test reads depth, and every
        // colour path reads SceneColor. None of the GBuffer reads are opted into.
        TestTrue(TEXT("SceneColor is wired"), Get_IsCustomInputConnected(Custom, TEXT("SceneColor")));
        TestTrue(TEXT("SceneDepth is wired"), Get_IsCustomInputConnected(Custom, TEXT("SceneDepth")));
        TestTrue(TEXT("SceneNormal is wired"), Get_IsCustomInputConnected(Custom, TEXT("SceneNormal")));

        // Without this the world-attached stroke space silently degenerates: In.WorldPosition reads zero,
        // every pixel lands in the same pattern cell, and nothing in the pipeline reports a problem.
        TestTrue(TEXT("WorldPosition is wired (the world-attached stroke space needs the opt-in)"),
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
        TestEqual(TEXT("HandDrawn.ush reports no HLSL compile errors"), CompileErrors, FString{});
    }

    if (ck_test_usf::Delete_TestGeneratedMaster(FName(kProbeLookName)) == false)
    { AddInfo(TEXT("Could not delete the probe's generated master file — harmless, but it is a stray asset on disk.")); }

    return true;
}

#endif // WITH_EDITOR

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_HandDrawnSubsystemSettings,
    "CkTests.UnitTests.CkUsf.HandDrawnSubsystemSettings",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_HandDrawnSubsystemSettings::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_hand_drawn;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(World);
    if (TestNotNull(TEXT("the world carries a HandDrawn subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    TestTrue(TEXT("a fresh subsystem holds the default settings"),
        Subsystem->Get_Settings() == FCk_Usf_HandDrawn_Params{});
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
        Subsystem->Get_Settings() == FCk_Usf_HandDrawn_Params{});

    // ---- The MID name seam ----
    // Everything above proves the settings VALUE survives; none of it proves the value reaches the
    // shader. The subsystem projects onto the MID purely by name, and an unknown name is written into
    // nothing at all, silently. Unlike the settings arms this one IS gated on the generated master,
    // deliberately: the master is shipped content, and its absence is exactly the "look renders nothing"
    // failure the subsystem warns about at runtime, so a missing one is worth a red rather than a skip.
    {
        const auto MasterPath = ck::usf::Get_GeneratedMasterObjectPath(FName(TEXT("HandDrawn")));
        auto* Master = LoadObject<UMaterialInterface>(nullptr, *MasterPath);

        if (TestNotNull(*FString::Printf(TEXT("the HandDrawn master exists at [%s]"), *MasterPath), Master))
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
    FCkTest_Usf_HandDrawnInvalidInput,
    "CkTests.UnitTests.CkUsf.HandDrawnInvalidInput",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_HandDrawnInvalidInput::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_hand_drawn;

    // ---- 1. An unresolvable world context returns null and does NOT ensure ----
    // Deliberate, and the UCkUsf_OutlineSubsystem::Get_OutlineSubsystem precedent: the accessor is called
    // from actor/EntityScript code that legitimately runs while a world is tearing down or before one
    // exists, so a diagnostic here would fire on correct code. The contract worth pinning is therefore
    // "null, not a crash" — if this ever grows an ensure, this arm turns red and names the decision.
    TestNull(TEXT("a null world context yields a null subsystem rather than a crash or an ensure"),
        UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(nullptr));

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_HandDrawnSubsystem::Get_HandDrawnSubsystem(World);
    if (TestNotNull(TEXT("the world carries a HandDrawn subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    Subsystem->Request_SetSettings(Make_NonDefaultSettings());
    const auto Before = Subsystem->Get_Settings();

    // Each ensure fire emits a log entry plus an Error line, both carrying the message — whitelist by
    // substring without enforcing a count.
    AddExpectedError(TEXT("null HandDrawn preset"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("ink fade range is INVERTED"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    // ---- 2. A null preset ----
    Subsystem->Apply_Preset(nullptr);

    TestTrue(TEXT("a null preset changes nothing at all — no partial application"),
        Subsystem->Get_Settings() == Before);

    // ---- 3. An inverted ink fade range ----
    // Not a cosmetic misconfiguration: the shader divides by max(End - Start, epsilon), so a non-positive
    // width pins that denominator at the epsilon and the ramp collapses into a HARD CUTOFF at the end
    // distance — full-weight line right up to it, gone immediately after. The setting silently stops
    // being a fade, with nothing in the frame saying why.
    auto InvertedFade = Make_NonDefaultSettings();
    InvertedFade.Set_InkFadeStartDistance(9000.0f)
                .Set_InkFadeEndDistance(3000.0f);


    Subsystem->Request_SetSettings(InvertedFade);

    TestTrue(TEXT("an inverted ink fade range is rejected and the previous settings survive intact"),
        Subsystem->Get_Settings() == Before);

    // Equal start and end is the same defect with a zero-width window, and must be refused for the same
    // reason — the guard is "ordered", not "not backwards".
    auto DegenerateFade = Make_NonDefaultSettings();
    DegenerateFade.Set_InkFadeStartDistance(3000.0f)
                  .Set_InkFadeEndDistance(3000.0f);

    Subsystem->Request_SetSettings(DegenerateFade);

    TestTrue(TEXT("a zero-width ink fade range is rejected too"),
        Subsystem->Get_Settings() == Before);

    // ---- 4. The legitimate neighbours of that boundary ----
    // The guard must reject an inverted RANGE, not the feature. An end of 0 means "no fade" and is legal
    // whatever the start says, and an ordered range is the ordinary case.
    auto FadeDisabled = Make_NonDefaultSettings();
    FadeDisabled.Set_InkFadeStartDistance(9000.0f)
                .Set_InkFadeEndDistance(0.0f);

    Subsystem->Request_SetSettings(FadeDisabled);

    TestTrue(TEXT("an end distance of 0 disables the fade and is accepted whatever the start is"),
        Subsystem->Get_Settings() == FadeDisabled);

    auto OrderedFade = Make_NonDefaultSettings();
    OrderedFade.Set_InkFadeStartDistance(1000.0f)
               .Set_InkFadeEndDistance(2000.0f);

    Subsystem->Request_SetSettings(OrderedFade);

    TestTrue(TEXT("an ordered ink fade range is accepted"),
        Subsystem->Get_Settings() == OrderedFade);

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
