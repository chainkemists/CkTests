// C++ unit tests pinning the ENGINE behaviour the explicit-planes rule rests on: with the default
// r.Ortho.AutoPlanes configuration, FMinimalViewInfo::AutoCalculateOrthoPlanes derives the far plane from the
// VIEW RECT, so the same camera rendered at a lower internal resolution gets a DIFFERENT depth range. That is
// why CkCamera's orthographic path and the pixel-art gym both author explicit planes. If the first test ever
// fails, the engine stopped deriving planes from resolution and the explicit-planes rule can be revisited.
//
// Surface in Session Frontend: CkTests.UnitTests.CkPixelArtRenderer.OrthoPlanes.<scenario>

#include "Misc/AutomationTest.h"

#include <Camera/CameraTypes.h>
#include <SceneView.h>

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pixel_art_ortho_planes
{
    // The pixel-art gym's framing: OrthoWidth 2200 at 16:9, pitched down like an isometric boom.
    auto
        Get_ViewInfo()
        -> FMinimalViewInfo
    {
        auto ViewInfo = FMinimalViewInfo{};
        ViewInfo.Location = FVector{0.0, 0.0, 1500.0};
        ViewInfo.Rotation = FRotator{-35.0f, 45.0f, 0.0f};
        ViewInfo.ProjectionMode = ECameraProjectionMode::Orthographic;
        ViewInfo.OrthoWidth = 2200.0f;
        ViewInfo.AspectRatio = 16.0f / 9.0f;

        return ViewInfo;
    }

    auto
        Get_ProjectionData(
            const FIntRect& InViewRect)
        -> FSceneViewProjectionData
    {
        auto ProjectionData = FSceneViewProjectionData{};
        ProjectionData.SetViewRectangle(InViewRect);

        return ProjectionData;
    }

    // A native viewport and the internal rect the renderer drives the same viewport down to at 360p.
    const FIntRect kNativeViewRect = FIntRect{0, 0, 1920, 1080};
    const FIntRect kInternalViewRect = FIntRect{0, 0, 648, 365};
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_AutoOrthoFarPlaneTracksViewRect,
    "CkTests.UnitTests.CkPixelArtRenderer.OrthoPlanes.AutoFarPlaneTracksViewRect",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_AutoOrthoFarPlaneTracksViewRect::RunTest(const FString& Parameters)
{
    auto AtNative = ck_test_pixel_art_ortho_planes::Get_ViewInfo();
    auto NativeProjectionData = ck_test_pixel_art_ortho_planes::Get_ProjectionData(
        ck_test_pixel_art_ortho_planes::kNativeViewRect);

    auto AtInternal = ck_test_pixel_art_ortho_planes::Get_ViewInfo();
    auto InternalProjectionData = ck_test_pixel_art_ortho_planes::Get_ProjectionData(
        ck_test_pixel_art_ortho_planes::kInternalViewRect);

    TestTrue(TEXT("auto planes ran for the native rect"),
        AtNative.AutoCalculateOrthoPlanes(NativeProjectionData));
    TestTrue(TEXT("auto planes ran for the internal rect"),
        AtInternal.AutoCalculateOrthoPlanes(InternalProjectionData));

    // The claim under pin: the auto far plane is a function of the render resolution. The renderer drives the
    // scene to a low internal rect every frame, so relying on auto planes would clip a different depth range
    // than the same camera at native resolution.
    TestTrue(*FString::Printf(
            TEXT("auto far plane differs between rects (native %f vs internal %f)"),
            AtNative.OrthoFarClipPlane, AtInternal.OrthoFarClipPlane),
        FMath::Abs(AtNative.OrthoFarClipPlane - AtInternal.OrthoFarClipPlane) > 1.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRenderer_ExplicitOrthoPlanesIgnoreViewRect,
    "CkTests.UnitTests.CkPixelArtRenderer.OrthoPlanes.ExplicitPlanesIgnoreViewRect",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRenderer_ExplicitOrthoPlanesIgnoreViewRect::RunTest(const FString& Parameters)
{
    constexpr auto AuthoredNearPlane = 10.0f;
    constexpr auto AuthoredFarPlane = 50000.0f;

    for (const auto& ViewRect : {
        ck_test_pixel_art_ortho_planes::kNativeViewRect,
        ck_test_pixel_art_ortho_planes::kInternalViewRect})
    {
        auto ViewInfo = ck_test_pixel_art_ortho_planes::Get_ViewInfo();
        ViewInfo.bAutoCalculateOrthoPlanes = false;
        ViewInfo.OrthoNearClipPlane = AuthoredNearPlane;
        ViewInfo.OrthoFarClipPlane = AuthoredFarPlane;

        auto ProjectionData = ck_test_pixel_art_ortho_planes::Get_ProjectionData(ViewRect);

        TestFalse(TEXT("auto planes decline to run when explicit planes are authored"),
            ViewInfo.AutoCalculateOrthoPlanes(ProjectionData));

        TestEqual(TEXT("authored near plane survives"), ViewInfo.OrthoNearClipPlane, AuthoredNearPlane);
        TestEqual(TEXT("authored far plane survives"), ViewInfo.OrthoFarClipPlane, AuthoredFarPlane);
    }

    return true;
}
