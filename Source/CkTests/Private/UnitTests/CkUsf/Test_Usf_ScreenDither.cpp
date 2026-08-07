// Gate for the CkUsf ScreenDither feature. Three tests, three distinct failure modes:
//
//   ScreenDitherGeneration — the asset<->HLSL contract. A LookDefinition shaped exactly like
//     Script/CkUsf/CkUsf_ScreenDitherLook_Assets.as is built in code, validated, generated, checked pin
//     by pin, and FORCE-compiled. Editor-only and skipped when the process cannot render, for the same
//     reason StylizeParamCount is. The force is what makes "ScreenDither.ush compiles" a real claim
//     rather than a pending shader job — it is destructive, hence a throwaway master that is deleted
//     again. Mutation-proven 2026-08-07: an undeclared identifier in ScreenDither.ush fails this test
//     under a real RHI and passes without the force. Never weaken it to a bare shader-map null check.
//
//   ScreenDitherSubsystemSettings — the subsystem's settings value is the source of truth: a round-trip
//     must be lossless and enable/disable must be idempotent. Deliberately NOT gated on the generated
//     master existing: settings are tracked whether or not there is anything to render them with, and a
//     test that silently needed content would pass vacuously on a fresh checkout.
//
//   ScreenDitherInvalidInput — the rejection boundary. A null preset and a CustomPalette-with-an-empty-
//     palette settings value are each rejected LOUDLY and change NOTHING. The "nothing" half is the one
//     worth testing: a partial application would leave the world in a state no preset describes, and an
//     empty custom palette specifically turns the whole view black with nothing naming the cause. The
//     null world context is covered here too — by design it does not ensure; see the test body.

#include "Misc/AutomationTest.h"

#include "Engine/World.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkUsf/Stylize/CkUsf_ScreenDitherPreset.h"
#include "CkUsf/Stylize/CkUsf_ScreenDitherSubsystem.h"
#include "CkUsf/Stylize/CkUsf_ScreenDither_Params.h"

#include "../CkUnitTest_Common.h"

#if WITH_EDITOR
#include "HAL/FileManager.h"
#include "Misc/App.h"
#include "Misc/PackageName.h"
#include "Materials/Material.h"
#include "Materials/MaterialExpressionCustom.h"
#include "UObject/StrongObjectPtr.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsf/LookDefinition/CkUsf_LookDefinition_Naming.h"
#include "CkUsfEditor/Generator/CkUsf_Generator.h"
#include "CkUsfEditor/Generator/CkUsf_LookValidator.h"
#endif

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_screen_dither
{
    // A settings value that differs from the defaults in EVERY field, so a round-trip that drops one is
    // caught rather than masked by a default that happened to match.
    auto Make_NonDefaultSettings() -> FCk_Usf_ScreenDither_Params
    {
        auto Settings = FCk_Usf_ScreenDither_Params{};

        Settings.Set_Enabled(ECk_EnableDisable::Disable)
                .Set_Pattern(ECk_Usf_DitherPattern::BlueNoise)
                .Set_PixelScale(6.0f)
                .Set_DitherStrength(0.25f)
                .Set_Animate(ECk_EnableDisable::Enable)
                .Set_AnimationPeriod(0.33f)
                .Set_BoxFilterDownsample(ECk_EnableDisable::Enable)
                .Set_StabilizeGrid(ECk_EnableDisable::Disable)
                .Set_PaletteMode(ECk_Usf_PaletteMode::CustomPalette)
                .Set_ColorSteps(3)
                .Set_Palette({FLinearColor::Red, FLinearColor::Green, FLinearColor::Blue})
                .Set_ColorSpace(ECk_Usf_DitherColorSpace::Linear)
                .Set_PreGamma(2.2f)
                .Set_Monochrome(ECk_EnableDisable::Enable)
                .Set_MonochromeShadowTint(FLinearColor(0.1f, 0.2f, 0.3f, 1.0f))
                .Set_MonochromeHighlightTint(FLinearColor(0.9f, 0.8f, 0.7f, 1.0f))
                .Set_Weight(0.4f)
                .Set_Saturation(1.7f)
                .Set_Contrast(0.6f)
                .Set_DebugMode(ECk_Usf_ScreenDither_DebugMode::QuantizationError);

        return Settings;
    }
}

// --------------------------------------------------------------------------------------------------------------------

#if WITH_EDITOR

namespace ck_test_usf_screen_dither
{
    constexpr auto kScreenDitherIncludePath = TEXT("/CkUsf/Looks/ScreenDither.ush");
    constexpr auto kScreenDitherFunctionName = TEXT("CkUsf_PP_ScreenDither");

    // Throwaway name: the real "ScreenDither" master is content the gym uses, and the force-compile below
    // leaves whatever it touches rendering black.
    constexpr auto kProbeLookName = TEXT("ScreenDitherGenerationProbe");

    // The .ush parameter list, in declaration order — the generator binds POSITIONALLY, so this list and
    // CkUsf_ScreenDitherLook_Assets.as must agree with CkUsf_PP_ScreenDither or every parameter past the
    // first difference is mis-bound. Stated here independently on purpose: if the AS asset drifts, this
    // test still holds the shader's own signature.
    auto Get_ScalarParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("DitherPattern"), TEXT("PixelScale"), TEXT("DitherStrength"), TEXT("Animate"),
            TEXT("AnimationPeriod"), TEXT("BoxFilterDownsample"), TEXT("StabilizeGrid"),
            TEXT("PaletteMode"), TEXT("ColorSteps"), TEXT("PaletteCount"),
            TEXT("ColorSpace"), TEXT("PreGamma"), TEXT("Monochrome"), TEXT("Saturation"),
            TEXT("Contrast"), TEXT("Weight"), TEXT("DebugMode"),
        };
    }

    auto Get_VectorParamNames() -> TArray<FString>
    {
        return
        {
            TEXT("MonochromeShadowTint"), TEXT("MonochromeHighlightTint"),
            TEXT("PaletteColor0"), TEXT("PaletteColor1"), TEXT("PaletteColor2"), TEXT("PaletteColor3"),
            TEXT("PaletteColor4"), TEXT("PaletteColor5"), TEXT("PaletteColor6"), TEXT("PaletteColor7"),
        };
    }

    auto Make_ProbeLookDefinition() -> UCkUsf_LookDefinition*
    {
        auto* Definition = NewObject<UCkUsf_LookDefinition>(GetTransientPackage());
        Definition->_LookName = FName(kProbeLookName);
        Definition->_UshIncludePath = kScreenDitherIncludePath;
        Definition->_UshFunctionName = FName(kScreenDitherFunctionName);
        Definition->_Domain = ECk_Usf_Domain::PostProcess;
        // Palette reduction must see the final display-referred frame — the same placement the shipped
        // asset declares, so this arm compiles the permutation the gym actually renders.
        Definition->_BlendableLocation = ECk_Usf_BlendableLocation::AfterTonemapping;

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
    FCkTest_Usf_ScreenDitherGeneration,
    "CkTests.UnitTests.CkUsf.ScreenDitherGeneration",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_ScreenDitherGeneration::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_screen_dither;

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
    if (TestEqual(TEXT("the ScreenDither look validates with no errors"), Validation.Errors.Num(), 0) == false)
    { return false; }

    auto* Master = ck::usf_editor::Generate_LookMaterial(Probe.Get());
    if (TestNotNull(TEXT("the ScreenDither look generates a master material"), Master) == false)
    { return false; }

    const auto* Custom = Find_CustomNode(Master);
    if (TestNotNull(TEXT("the ScreenDither master has a Custom node"), Custom))
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

        TestTrue(TEXT("SceneColor is wired (the look reads nothing else from the scene)"),
            Get_IsCustomInputConnected(Custom, TEXT("SceneColor")));
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
        TestEqual(TEXT("ScreenDither.ush reports no HLSL compile errors"), CompileErrors, FString{});
    }

    if (Delete_GeneratedMaster(FName(kProbeLookName)) == false)
    { AddInfo(TEXT("Could not delete the probe's generated master file — harmless, but it is a stray asset on disk.")); }

    return true;
}

#endif // WITH_EDITOR

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_ScreenDitherSubsystemSettings,
    "CkTests.UnitTests.CkUsf.ScreenDitherSubsystemSettings",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_ScreenDitherSubsystemSettings::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_screen_dither;

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(World);
    if (TestNotNull(TEXT("the world carries a ScreenDither subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    TestTrue(TEXT("a fresh subsystem holds the default settings"),
        Subsystem->Get_Settings() == FCk_Usf_ScreenDither_Params{});
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
        Subsystem->Get_Settings() == FCk_Usf_ScreenDither_Params{});

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_ScreenDitherInvalidInput,
    "CkTests.UnitTests.CkUsf.ScreenDitherInvalidInput",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_ScreenDitherInvalidInput::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_screen_dither;

    // ---- 1. An unresolvable world context returns null and does NOT ensure ----
    // Deliberate, and the UCkUsf_OutlineSubsystem::Get_OutlineSubsystem precedent: the accessor is called
    // from actor/EntityScript code that legitimately runs while a world is tearing down or before one
    // exists, so a diagnostic here would fire on correct code. The contract worth pinning is therefore
    // "null, not a crash" — if this ever grows an ensure, this arm turns red and names the decision.
    TestNull(TEXT("a null world context yields a null subsystem rather than a crash or an ensure"),
        UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(nullptr));

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("a transient world exists"), World) == false)
    { return false; }

    auto* Subsystem = UCkUsf_ScreenDitherSubsystem::Get_ScreenDitherSubsystem(World);
    if (TestNotNull(TEXT("the world carries a ScreenDither subsystem"), Subsystem) == false)
    {
        World->DestroyWorld(false);
        return false;
    }

    Subsystem->Request_SetSettings(Make_NonDefaultSettings());
    const auto Before = Subsystem->Get_Settings();

    // Each ensure fire emits a log entry plus an Error line, both carrying the message — whitelist by
    // substring without enforcing a count.
    AddExpectedError(TEXT("null ScreenDither preset"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("CustomPalette with an EMPTY palette"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    // ---- 2. A null preset ----
    Subsystem->Apply_Preset(nullptr);

    TestTrue(TEXT("a null preset changes nothing at all — no partial application"),
        Subsystem->Get_Settings() == Before);

    // ---- 3. CustomPalette with nothing in the palette ----
    // Not a cosmetic misconfiguration: every pixel snaps to the black the unused shader slots hold, so
    // the whole view goes black with nothing naming the cause. Accepting it and rendering that is worse
    // than refusing it.
    auto EmptyPalette = Make_NonDefaultSettings();
    EmptyPalette.Set_PaletteMode(ECk_Usf_PaletteMode::CustomPalette)
                .Set_Palette(TArray<FLinearColor>{});

    Subsystem->Request_SetSettings(EmptyPalette);

    TestTrue(TEXT("an empty custom palette is rejected and the previous settings survive intact"),
        Subsystem->Get_Settings() == Before);

    // The same value with one entry is legitimate — the guard must reject emptiness, not the mode.
    auto OneEntryPalette = EmptyPalette;
    OneEntryPalette.Set_Palette({FLinearColor::White});

    Subsystem->Request_SetSettings(OneEntryPalette);

    TestTrue(TEXT("a single-entry custom palette is accepted"),
        Subsystem->Get_Settings() == OneEntryPalette);

    World->DestroyWorld(false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
