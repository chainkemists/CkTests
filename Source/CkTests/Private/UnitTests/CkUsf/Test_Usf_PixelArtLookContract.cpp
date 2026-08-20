// Contract gate for the PixelArt look: the asset and the HLSL entry point must agree.
//
// The generator binds look parameters POSITIONALLY — the Nth entry of _Parameters becomes the Nth argument of
// CkUsf_PP_PixelArt after the surface input. Nothing at runtime notices when that order drifts: the shader still
// compiles, the material still renders, and every knob simply drives the wrong thing. Inserting one parameter in
// the middle of the asset silently turns DepthThreshold into AngleZCutoff, which reads as "the outline settings
// stopped working" and sends the next person to the shader.
//
// So this test reads the .ush source off disk, parses the entry signature, and checks it against the asset name
// for name, in order. It also pins the three declarations that are not free choices:
//
//   Domain            — PostProcess; a surface look cannot read scene depth or normals at all.
//   BlendableLocation — SceneColorAfterDOF, i.e. RENDER resolution and pre-TAA. This is what makes an outline
//                       exactly one texel wide; after tonemapping the kernel steps in display pixels instead.
//   SceneTextures     — colour, depth and world normal, because all three are read.
//
// Editor-only: it needs the asset registry to find the AngelScript-authored LookDefinition.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"

#include "CkCore/Macros/CkMacros.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_pixel_art_contract
{
    constexpr auto kLookName = TEXT("PixelArt");
    constexpr auto kEntryPoint = TEXT("CkUsf_PP_PixelArt");
    constexpr auto kUshRelativePath = TEXT("Source/CkUsf/Shaders/CkUsf/Looks/PixelArt.ush");

    auto
        TryFind_LookDefinition()
        -> UCkUsf_LookDefinition*
    {
        auto& AssetRegistryModule =
            FModuleManager::LoadModuleChecked<FAssetRegistryModule>(TEXT("AssetRegistry"));

        auto Assets = TArray<FAssetData>{};
        AssetRegistryModule.Get().GetAssetsByClass(
            UCkUsf_LookDefinition::StaticClass()->GetClassPathName(), Assets, true);

        for (const auto& Asset : Assets)
        {
            auto* Definition = Cast<UCkUsf_LookDefinition>(Asset.GetAsset());

            if (ck::IsValid(Definition) && Definition->_LookName == FName{kLookName})
            { return Definition; }
        }

        return nullptr;
    }

    auto
        TryRead_UshSource(
            FString& OutSource)
        -> bool
    {
        const auto Plugin = IPluginManager::Get().FindPlugin(TEXT("CkFoundation"));

        if (NOT Plugin.IsValid())
        { return false; }

        const auto FullPath = FPaths::Combine(Plugin->GetBaseDir(), kUshRelativePath);

        return FFileHelper::LoadFileToString(OutSource, *FullPath);
    }

    // Parameter names of the entry point, in declaration order, skipping the leading FCkUsf_SurfaceInput.
    //
    // Deliberately a parse of the real file rather than a second hand-maintained list: a list would have to be
    // edited in lockstep with both sides, which is the same failure this test exists to catch.
    auto
        Get_EntryParameterNames(
            const FString& InSource)
        -> TArray<FString>
    {
        auto Names = TArray<FString>{};

        const auto SignatureStart = InSource.Find(FString{kEntryPoint} + TEXT("("));

        if (SignatureStart == INDEX_NONE)
        { return Names; }

        const auto OpenParen = InSource.Find(TEXT("("), ESearchCase::CaseSensitive,
            ESearchDir::FromStart, SignatureStart);
        const auto CloseParen = InSource.Find(TEXT(")"), ESearchCase::CaseSensitive,
            ESearchDir::FromStart, OpenParen);

        if (OpenParen == INDEX_NONE || CloseParen == INDEX_NONE)
        { return Names; }

        const auto Signature = InSource.Mid(OpenParen + 1, CloseParen - OpenParen - 1);

        auto Arguments = TArray<FString>{};
        Signature.ParseIntoArray(Arguments, TEXT(","), true);

        for (const auto& Argument : Arguments)
        {
            auto Trimmed = Argument;
            Trimmed.ReplaceInline(TEXT("\r"), TEXT(" "));
            Trimmed.ReplaceInline(TEXT("\n"), TEXT(" "));
            Trimmed.TrimStartAndEndInline();

            auto Tokens = TArray<FString>{};
            Trimmed.ParseIntoArrayWS(Tokens);

            if (Tokens.Num() < 2)
            { continue; }

            // The surface input is the fixed first argument the generator supplies itself, not a parameter.
            if (Tokens[0] == TEXT("FCkUsf_SurfaceInput"))
            { continue; }

            Names.Add(Tokens.Last());
        }

        return Names;
    }
}

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_PixelArtLookContract,
    "CkTests.UnitTests.CkUsf.PixelArtLook.MatchesEntrySignature",
    kCkUnitTestFlags)

bool FCkTest_Usf_PixelArtLookContract::RunTest(const FString& Parameters)
{
    auto* Definition = ck_test_usf_pixel_art_contract::TryFind_LookDefinition();

    if (NOT TestNotNull(TEXT("the PixelArt LookDefinition asset exists"), Definition))
    { return false; }

    TestEqual(TEXT("entry point"), Definition->_UshFunctionName,
        FName{ck_test_usf_pixel_art_contract::kEntryPoint});
    TestEqual(TEXT("include path"), Definition->_UshIncludePath,
        FString{TEXT("/CkUsf/Looks/PixelArt.ush")});

    TestTrue(TEXT("domain is PostProcess"),
        Definition->_Domain == ECk_Usf_Domain::PostProcess);

    // The one declaration that decides whether an outline is one texel or one display pixel wide.
    TestTrue(TEXT("blendable location is SceneColorAfterDOF (render resolution, pre-TAA)"),
        Definition->_BlendableLocation == ECk_Usf_BlendableLocation::SceneColorAfterDOF);

    TestTrue(TEXT("scene colour is wired"),
        Definition->_SceneTextures.Contains(ECk_Usf_SceneTexture::SceneColor));
    TestTrue(TEXT("scene depth is wired"),
        Definition->_SceneTextures.Contains(ECk_Usf_SceneTexture::SceneDepth));
    TestTrue(TEXT("world normal is wired"),
        Definition->_SceneTextures.Contains(ECk_Usf_SceneTexture::SceneNormal));

    auto Source = FString{};

    if (NOT TestTrue(TEXT("PixelArt.ush is readable from the plugin directory"),
        ck_test_usf_pixel_art_contract::TryRead_UshSource(Source)))
    { return false; }

    const auto EntryNames = ck_test_usf_pixel_art_contract::Get_EntryParameterNames(Source);

    if (NOT TestEqual(TEXT("the asset declares one parameter per shader argument"),
        Definition->_Parameters.Num(), EntryNames.Num()))
    { return false; }

    for (auto Index = 0; Index < EntryNames.Num(); ++Index)
    {
        TestEqual(
            *FString::Printf(TEXT("parameter %d binds positionally"), Index),
            Definition->_Parameters[Index]._Name.ToString(), EntryNames[Index]);
    }

    // Grouping is what makes 22 parameters navigable in the material editor, and it is trivially forgotten on a
    // parameter added later.
    for (const auto& Parameter : Definition->_Parameters)
    {
        TestTrue(
            *FString::Printf(TEXT("parameter %s is grouped"), *Parameter._Name.ToString()),
            Parameter._Group != NAME_None);
    }

    return true;
}

#endif
