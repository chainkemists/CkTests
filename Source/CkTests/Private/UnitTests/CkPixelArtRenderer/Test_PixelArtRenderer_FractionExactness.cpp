// C++ unit test for the pixel-art renderer's screen-percentage fraction (CkPixelArtRenderer).
//
// The renderer derives the internal (pre-upscale) view size as CeilToInt(UnscaledViewSize * Fraction), so a
// fraction of TargetWidth/ViewportWidth is one float rounding error away from producing TargetWidth + 1 texels —
// and a single extra texel column silently breaks the texel grid the whole technique rests on. Get_ExactFraction
// subtracts half a pixel before dividing so the product lands just under the target and CeilToInt is forced onto
// it exactly, for any viewport width.
//
// Surface in Session Frontend: CkTests.UnitTests.CkPixelArtRenderer.Fraction.<scenario>

#include "Misc/AutomationTest.h"

#include "CkPixelArtRenderer/CkPixelArtRenderer_Utils.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_FractionExactness,
    "CkTests.UnitTests.CkPixelArtRenderer.Fraction.LandsOnTargetWidth",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_FractionExactness::RunTest(const FString& Parameters)
{
    const int32 ViewportWidths[] = {1280, 1366, 1367, 1600, 1920, 2560, 3440, 3840};
    const int32 TargetWidths[]   = {320, 640, 644, 960};

    for (const auto ViewportWidth : ViewportWidths)
    {
        for (const auto TargetWidth : TargetWidths)
        {
            const auto Fraction = UCk_Utils_PixelArtRenderer_UE::Get_ExactFraction(TargetWidth, ViewportWidth);
            const auto Resolved = FMath::CeilToInt(ViewportWidth * Fraction);

            TestEqual(
                *FString::Printf(TEXT("viewport %d at target %d resolves to exactly %d"),
                    ViewportWidth, TargetWidth, TargetWidth),
                Resolved, TargetWidth);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_FractionRejectsDegenerateInput,
    "CkTests.UnitTests.CkPixelArtRenderer.Fraction.RejectsDegenerateInput",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_FractionRejectsDegenerateInput::RunTest(const FString& Parameters)
{
    // A zero/negative viewport width is a division by zero away from an inf fraction reaching the renderer's
    // resolution-fraction check. The contract is to answer 1.0 (render at native resolution) rather than produce
    // a value that asserts deep inside the scene renderer.
    TestEqual(TEXT("zero viewport width falls back to native resolution"),
        UCk_Utils_PixelArtRenderer_UE::Get_ExactFraction(640, 0), 1.0f);

    TestEqual(TEXT("negative viewport width falls back to native resolution"),
        UCk_Utils_PixelArtRenderer_UE::Get_ExactFraction(640, -1920), 1.0f);

    TestEqual(TEXT("non-positive target width falls back to native resolution"),
        UCk_Utils_PixelArtRenderer_UE::Get_ExactFraction(0, 1920), 1.0f);

    // A target wider than the viewport would ask the renderer to supersample, which this renderer never wants.
    TestEqual(TEXT("target wider than the viewport falls back to native resolution"),
        UCk_Utils_PixelArtRenderer_UE::Get_ExactFraction(2560, 1920), 1.0f);

    return true;
}
