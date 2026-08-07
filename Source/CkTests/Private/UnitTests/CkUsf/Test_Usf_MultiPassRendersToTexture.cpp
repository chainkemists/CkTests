// Headless isolation test for the CkUsf render-to-texture (#1) path.
//
// The single-pass looks render fine on meshes, but the RENDER-TO-TEXTURE gym station shows a
// black sphere. This narrows the bug to DrawMaterialToRenderTarget feeding a generated master.
// Three escalating stages localize exactly where the black originates:
//   A) trivial Blit with a known RED input  -> does the canvas draw a generated master at all?
//   B) SmokeBuffer/SmokeImage, single-shot, known WHITE input -> do the pass shaders draw?
//   C) full 12-frame feedback loop (ping-pong + iFrame) -> does the feedback accumulate?
//
// Real RHI required (NO -nullrhi): canvas rendering + readback need a live RHI.
// Editor-only: the generator lives in CkUsfEditor.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "Misc/App.h"
#include "Editor.h"
#include "Engine/World.h"
#include "Engine/TextureRenderTarget2D.h"
#include "TextureResource.h"
#include "RenderingThread.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Kismet/KismetRenderingLibrary.h"
#include "AssetRegistry/AssetRegistryModule.h"

#include "CkUsf/LookDefinition/CkUsf_LookDefinition.h"
#include "CkUsf/Apply/CkUsf_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kUsfRtTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    constexpr auto kRtSize = 64;

    auto Get_TestWorld() -> UWorld*
    {
        if (GEditor != nullptr)
        {
            if (auto* W = GEditor->GetEditorWorldContext().World())
            { return W; }
        }
        return GWorld;
    }

    auto Find_Look(const TArray<FAssetData>& InAssets, const FString& InName) -> UCkUsf_LookDefinition*
    {
        for (const auto& A : InAssets)
        {
            auto* Def = Cast<UCkUsf_LookDefinition>(A.GetAsset());
            if (Def != nullptr && Def->Get_EffectiveLookName().ToString() == InName)
            { return Def; }
        }
        return nullptr;
    }

    auto Make_Rt(UWorld* InWorld, const FLinearColor& InClear) -> UTextureRenderTarget2D*
    {
        auto* Rt = UKismetRenderingLibrary::CreateRenderTarget2D(
            InWorld, kRtSize, kRtSize, ETextureRenderTargetFormat::RTF_RGBA16f);
        UKismetRenderingLibrary::ClearRenderTarget2D(InWorld, Rt, InClear);
        return Rt;
    }

    // Brightest single channel across the whole RT (robust to where the emitter lands).
    auto Max_Brightness(UTextureRenderTarget2D* InRt) -> float
    {
        FlushRenderingCommands();
        auto* Res = InRt->GameThread_GetRenderTargetResource();
        if (Res == nullptr) { return -1.0f; }

        TArray<FLinearColor> Pixels;
        if (Res->ReadLinearColorPixels(Pixels) == false || Pixels.Num() == 0)
        { return -1.0f; }

        auto Max = 0.0f;
        for (const auto& P : Pixels)
        { Max = FMath::Max(Max, FMath::Max3(P.R, P.G, P.B)); }
        return Max;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_MultiPassRendersToTexture,
    "CkTests.UnitTests.CkUsf.MultiPassRendersToTexture",
    kUsfRtTestFlags)

bool FCkTest_Usf_MultiPassRendersToTexture::RunTest(const FString& Parameters)
{
    if (FApp::CanEverRender() == false)
    {
        AddInfo(TEXT("Skipped: this process cannot render (e.g. -nullrhi) — canvas draw + RT readback need a live RHI."));
        return true;
    }

    auto* World = Get_TestWorld();
    if (TestNotNull(TEXT("editor world available"), World) == false)
    { return false; }

    // Deliberately does NOT regenerate: this is the RUNTIME path (Create_MID_ForLook resolves the shipped
    // master), and a whole-roster regeneration here would write the same .uasset files another concurrent
    // test editor is writing, taking both processes down. Generator
    // freshness is GeneratesUsableMasters' and the contract tests' job; .ush edits need no regeneration.

    const auto& ARM = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry").Get();
    TArray<FAssetData> Looks;
    ARM.GetAssetsByClass(UCkUsf_LookDefinition::StaticClass()->GetClassPathName(), Looks);

    auto* BlitDef   = Find_Look(Looks, TEXT("Blit"));
    auto* BufferDef = Find_Look(Looks, TEXT("SmokeBuffer"));
    auto* ImageDef  = Find_Look(Looks, TEXT("SmokeImage"));
    TestNotNull(TEXT("Blit look found"), BlitDef);
    TestNotNull(TEXT("SmokeBuffer look found"), BufferDef);
    TestNotNull(TEXT("SmokeImage look found"), ImageDef);
    if (BlitDef == nullptr || BufferDef == nullptr || ImageDef == nullptr)
    { return false; }

    const auto Res = FLinearColor(kRtSize, kRtSize, 0.0f, 1.0f);

    // ---- Stage A: canvas draws a generated master at all (trivial Blit, known RED input) ----
    {
        auto* RedInput = Make_Rt(World, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
        auto* Out      = Make_Rt(World, FLinearColor::Black);

        auto* MID = UCk_Utils_Usf_UE::Create_MID_ForLook(BlitDef, World);
        TestNotNull(TEXT("[A] Blit MID"), MID);
        if (MID != nullptr)
        {
            MID->SetTextureParameterValue(TEXT("iChannel0"), RedInput);
            UKismetRenderingLibrary::DrawMaterialToRenderTarget(World, Out, MID);

            const auto B = Max_Brightness(Out);
            AddInfo(FString::Printf(TEXT("[A] Blit(known red) -> out max brightness = %.4f"), B));
            TestTrue(TEXT("[A] DrawMaterialToRenderTarget on a generated master is non-black"), B > 0.1f);
        }
    }

    // ---- Stage B: the pass shaders draw with a known WHITE input (single-shot, no feedback) ----
    {
        auto* WhiteInput = Make_Rt(World, FLinearColor::White);

        // SmokeBuffer: iFrame=1 so it accumulates (frame 0 self-clears).
        {
            auto* Out = Make_Rt(World, FLinearColor::Black);
            auto* MID = UCk_Utils_Usf_UE::Create_MID_ForLook(BufferDef, World);
            TestNotNull(TEXT("[B] SmokeBuffer MID"), MID);
            if (MID != nullptr)
            {
                MID->SetVectorParameterValue(TEXT("iResolution"), Res);
                MID->SetScalarParameterValue(TEXT("iFrame"), 1.0f);
                MID->SetScalarParameterValue(TEXT("iTimeDelta"), 0.016f);
                MID->SetTextureParameterValue(TEXT("iChannel0"), WhiteInput);
                UKismetRenderingLibrary::DrawMaterialToRenderTarget(World, Out, MID);

                const auto B = Max_Brightness(Out);
                AddInfo(FString::Printf(TEXT("[B] SmokeBuffer(known white) -> max brightness = %.4f"), B));
                TestTrue(TEXT("[B] SmokeBuffer pass draws non-black"), B > 0.1f);
            }
        }

        // SmokeImage: colorize a known white field.
        {
            auto* Out = Make_Rt(World, FLinearColor::Black);
            auto* MID = UCk_Utils_Usf_UE::Create_MID_ForLook(ImageDef, World);
            TestNotNull(TEXT("[B] SmokeImage MID"), MID);
            if (MID != nullptr)
            {
                MID->SetVectorParameterValue(TEXT("iResolution"), Res);
                MID->SetScalarParameterValue(TEXT("iFrame"), 1.0f);
                MID->SetScalarParameterValue(TEXT("iTimeDelta"), 0.016f);
                MID->SetTextureParameterValue(TEXT("iChannel0"), WhiteInput);
                UKismetRenderingLibrary::DrawMaterialToRenderTarget(World, Out, MID);

                const auto B = Max_Brightness(Out);
                AddInfo(FString::Printf(TEXT("[B] SmokeImage(known white) -> max brightness = %.4f"), B));
                TestTrue(TEXT("[B] SmokeImage pass draws non-black"), B > 0.1f);
            }
        }
    }

    // ---- Stage C: full feedback loop (ping-pong + iFrame), mirrors UCkUsf_MultiPassRenderer ----
    {
        auto* BufMID = UCk_Utils_Usf_UE::Create_MID_ForLook(BufferDef, World);
        auto* ImgMID = UCk_Utils_Usf_UE::Create_MID_ForLook(ImageDef, World);
        TestNotNull(TEXT("[C] SmokeBuffer MID"), BufMID);
        TestNotNull(TEXT("[C] SmokeImage MID"), ImgMID);

        if (BufMID != nullptr && ImgMID != nullptr)
        {
            auto* Read    = Make_Rt(World, FLinearColor::Black);
            auto* Write   = Make_Rt(World, FLinearColor::Black);
            auto* Display = Make_Rt(World, FLinearColor::Black);

            constexpr auto Frames = 12;
            for (auto Frame = 0; Frame < Frames; ++Frame)
            {
                const auto FrameF = static_cast<float>(Frame);

                // BufferA pass: read self, write the other buffer.
                BufMID->SetVectorParameterValue(TEXT("iResolution"), Res);
                BufMID->SetScalarParameterValue(TEXT("iFrame"), FrameF);
                BufMID->SetScalarParameterValue(TEXT("iTimeDelta"), 0.016f);
                BufMID->SetTextureParameterValue(TEXT("iChannel0"), Read);
                UKismetRenderingLibrary::DrawMaterialToRenderTarget(World, Write, BufMID);

                // Image pass: reads the (pre-swap) buffer, like the renderer.
                ImgMID->SetVectorParameterValue(TEXT("iResolution"), Res);
                ImgMID->SetScalarParameterValue(TEXT("iFrame"), FrameF);
                ImgMID->SetScalarParameterValue(TEXT("iTimeDelta"), 0.016f);
                ImgMID->SetTextureParameterValue(TEXT("iChannel0"), Read);
                UKismetRenderingLibrary::DrawMaterialToRenderTarget(World, Display, ImgMID);

                Swap(Read, Write);
                FlushRenderingCommands();
            }

            const auto BufB = Max_Brightness(Read);     // newest buffer content
            const auto DispB = Max_Brightness(Display);
            AddInfo(FString::Printf(TEXT("[C] after %d frames: buffer max = %.4f, display max = %.4f"),
                Frames, BufB, DispB));
            TestTrue(TEXT("[C] feedback buffer accumulates non-black"), BufB > 0.1f);
            TestTrue(TEXT("[C] display RT is non-black"), DispB > 0.05f);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
