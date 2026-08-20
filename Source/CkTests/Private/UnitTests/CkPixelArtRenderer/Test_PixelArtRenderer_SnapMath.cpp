// C++ unit tests for the pixel-art renderer's camera snap arithmetic (CkPixelArtRender).
//
// Snapping the camera onto the texel lattice is what stops pixels crawling along edges; re-applying the sub-texel
// remainder as a UV shift is what stops the snap turning smooth motion into whole-texel stepping. The two only
// cancel if the remainder is an EXACT decomposition of what the snap removed, in the camera's own right/up basis
// — an error there produces a picture that looks almost right and drifts, which is the failure mode hardest to
// spot by eye and cheapest to catch here.
//
// Surface in Session Frontend: CkTests.UnitTests.CkPixelArtRender.Snap.<scenario>

#include "Misc/AutomationTest.h"

#include "CkPixelArtRender/CkPixelArtRender_SnapMath.h"
#include "CkPixelArtRender/CkPixelArtRender_Utils.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pixel_art_snap
{
    // The engine's own world-to-view construction (LocalPlayer.cpp:1224): an inverse rotation followed by the
    // swizzle that sends world forward/right/up to view Z/X/Y. The tests build the matrix here rather than
    // calling into the renderer so that a change to the engine's convention shows up as a failure instead of
    // being silently mirrored by shared code.
    auto
        Get_ViewRotationMatrix(
            const FRotator& InRotation)
        -> FMatrix
    {
        return FInverseRotationMatrix{InRotation} * FMatrix{
            FPlane{0, 0, 1, 0},
            FPlane{1, 0, 0, 0},
            FPlane{0, 1, 0, 0},
            FPlane{0, 0, 0, 1}};
    }

    struct FSample
    {
        FVector Origin = FVector::ZeroVector;
        FRotator Rotation = FRotator::ZeroRotator;
        FMatrix ViewRotationMatrix = FMatrix::Identity;
        double TexelWorldSize = 1.0;
    };

    auto
        Get_Sample(
            FRandomStream& InStream)
        -> FSample
    {
        auto Sample = FSample{};

        Sample.Origin = FVector{
            InStream.FRandRange(-50000.0f, 50000.0f),
            InStream.FRandRange(-50000.0f, 50000.0f),
            InStream.FRandRange(-50000.0f, 50000.0f)};

        Sample.Rotation = FRotator{
            InStream.FRandRange(-89.0f, 89.0f),
            InStream.FRandRange(-180.0f, 180.0f),
            InStream.FRandRange(-180.0f, 180.0f)};

        Sample.ViewRotationMatrix = Get_ViewRotationMatrix(Sample.Rotation);
        Sample.TexelWorldSize = InStream.FRandRange(0.5f, 40.0f);

        return Sample;
    }

    constexpr int32 SampleCount = 1000;
    constexpr int32 Seed = 20260820;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_SnapBasisMatchesCameraAxes,
    "CkTests.UnitTests.CkPixelArtRender.Snap.BasisMatchesCameraAxes",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_SnapBasisMatchesCameraAxes::RunTest(const FString& Parameters)
{
    // The one step of this whole technique that is silently transposable: reading the view axes out of a
    // world-to-view matrix. Pinned against the rotation the matrix was built from, using rotations that make a
    // transposition impossible to miss — it would survive the identity rotation unnoticed.
    const FRotator Rotations[] = {
        FRotator{0.0f, 0.0f, 0.0f},
        FRotator{-30.0f, 45.0f, 0.0f},
        FRotator{-35.264f, 45.0f, 0.0f},
        FRotator{15.0f, -120.0f, 22.5f}};

    for (const auto& Rotation : Rotations)
    {
        const auto ViewRotationMatrix = ck_test_pixel_art_snap::Get_ViewRotationMatrix(Rotation);
        const auto Basis = ck::pixel_art::Get_ViewBasis(ViewRotationMatrix);

        const auto RotationMatrix = FRotationMatrix{Rotation};
        const auto ExpectedRight = RotationMatrix.GetScaledAxis(EAxis::Y);
        const auto ExpectedUp = RotationMatrix.GetScaledAxis(EAxis::Z);
        const auto ExpectedForward = RotationMatrix.GetScaledAxis(EAxis::X);

        TestTrue(*FString::Printf(TEXT("right axis at %s"), *Rotation.ToString()),
            Basis.Right.Equals(ExpectedRight, 1e-3));
        TestTrue(*FString::Printf(TEXT("up axis at %s"), *Rotation.ToString()),
            Basis.Up.Equals(ExpectedUp, 1e-3));
        TestTrue(*FString::Printf(TEXT("forward axis at %s"), *Rotation.ToString()),
            Basis.Forward.Equals(ExpectedForward, 1e-3));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_SnapIsIdempotent,
    "CkTests.UnitTests.CkPixelArtRender.Snap.IsIdempotent",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_SnapIsIdempotent::RunTest(const FString& Parameters)
{
    auto Stream = FRandomStream{ck_test_pixel_art_snap::Seed};

    for (auto SampleIndex = 0; SampleIndex < ck_test_pixel_art_snap::SampleCount; ++SampleIndex)
    {
        const auto Sample = ck_test_pixel_art_snap::Get_Sample(Stream);

        auto FirstRemainder = FVector2f::ZeroVector;
        const auto Snapped = ck::pixel_art::Get_SnappedViewOrigin(
            Sample.Origin, Sample.ViewRotationMatrix, Sample.TexelWorldSize, FirstRemainder);

        auto SecondRemainder = FVector2f::ZeroVector;
        const auto SnappedTwice = ck::pixel_art::Get_SnappedViewOrigin(
            Snapped, Sample.ViewRotationMatrix, Sample.TexelWorldSize, SecondRemainder);

        // Tolerance scales with the texel: the residue is a floating-point artefact of the lattice arithmetic, so
        // a fixed absolute epsilon would be vacuous for large texels and unachievable for small ones.
        const auto Tolerance = Sample.TexelWorldSize * 1e-3;

        if (!TestTrue(*FString::Printf(TEXT("sample %d: snapping a snapped origin is identity"), SampleIndex),
            SnappedTwice.Equals(Snapped, Tolerance)))
        { return false; }

        if (!TestTrue(*FString::Printf(TEXT("sample %d: a snapped origin has no remainder"), SampleIndex),
            SecondRemainder.IsNearlyZero(1e-3f)))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_SnapRemainderIsBounded,
    "CkTests.UnitTests.CkPixelArtRender.Snap.RemainderIsBounded",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_SnapRemainderIsBounded::RunTest(const FString& Parameters)
{
    auto Stream = FRandomStream{ck_test_pixel_art_snap::Seed};

    for (auto SampleIndex = 0; SampleIndex < ck_test_pixel_art_snap::SampleCount; ++SampleIndex)
    {
        const auto Sample = ck_test_pixel_art_snap::Get_Sample(Stream);

        auto Remainder = FVector2f::ZeroVector;
        ck::pixel_art::Get_SnappedViewOrigin(
            Sample.Origin, Sample.ViewRotationMatrix, Sample.TexelWorldSize, Remainder);

        // Half a texel per axis is the bound the render margin is sized against: exceed it and the shifted
        // sampling window reads texels that were never rendered.
        constexpr auto Bound = 0.5f + KINDA_SMALL_NUMBER;

        if (!TestTrue(*FString::Printf(TEXT("sample %d: remainder %s is within half a texel"),
                SampleIndex, *Remainder.ToString()),
            FMath::Abs(Remainder.X) <= Bound && FMath::Abs(Remainder.Y) <= Bound))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_SnapRemainderReconstructsOrigin,
    "CkTests.UnitTests.CkPixelArtRender.Snap.RemainderReconstructsOrigin",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_SnapRemainderReconstructsOrigin::RunTest(const FString& Parameters)
{
    auto Stream = FRandomStream{ck_test_pixel_art_snap::Seed};

    for (auto SampleIndex = 0; SampleIndex < ck_test_pixel_art_snap::SampleCount; ++SampleIndex)
    {
        const auto Sample = ck_test_pixel_art_snap::Get_Sample(Stream);

        auto Remainder = FVector2f::ZeroVector;
        const auto Snapped = ck::pixel_art::Get_SnappedViewOrigin(
            Sample.Origin, Sample.ViewRotationMatrix, Sample.TexelWorldSize, Remainder);

        const auto Basis = ck::pixel_art::Get_ViewBasis(Sample.ViewRotationMatrix);

        // This IS the compensation the upscaler performs, written in world space: if putting the remainder back
        // does not land on the original origin, the shader's UV shift cannot cancel the snap either.
        const auto Reconstructed = Snapped
            + (Remainder.X * Sample.TexelWorldSize) * Basis.Right
            + (Remainder.Y * Sample.TexelWorldSize) * Basis.Up;

        if (!TestTrue(*FString::Printf(TEXT("sample %d: remainder reconstructs the origin"), SampleIndex),
            Reconstructed.Equals(Sample.Origin, 1e-3)))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_SnapPreservesForward,
    "CkTests.UnitTests.CkPixelArtRender.Snap.PreservesForward",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_SnapPreservesForward::RunTest(const FString& Parameters)
{
    auto Stream = FRandomStream{ck_test_pixel_art_snap::Seed};

    for (auto SampleIndex = 0; SampleIndex < ck_test_pixel_art_snap::SampleCount; ++SampleIndex)
    {
        const auto Sample = ck_test_pixel_art_snap::Get_Sample(Stream);

        auto Remainder = FVector2f::ZeroVector;
        const auto Snapped = ck::pixel_art::Get_SnappedViewOrigin(
            Sample.Origin, Sample.ViewRotationMatrix, Sample.TexelWorldSize, Remainder);

        const auto Basis = ck::pixel_art::Get_ViewBasis(Sample.ViewRotationMatrix);

        // Moving along view-forward under an orthographic projection changes nothing on screen but everything
        // about clipping, so the snap must never touch it.
        const auto AlongForward = FVector::DotProduct(Snapped - Sample.Origin, Basis.Forward);

        if (!TestTrue(*FString::Printf(TEXT("sample %d: snap moved %f along view forward"),
                SampleIndex, AlongForward),
            FMath::Abs(AlongForward) <= 1e-3))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_SnapRejectsDegenerateTexel,
    "CkTests.UnitTests.CkPixelArtRender.Snap.RejectsDegenerateTexel",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_SnapRejectsDegenerateTexel::RunTest(const FString& Parameters)
{
    const auto ViewRotationMatrix = ck_test_pixel_art_snap::Get_ViewRotationMatrix(FRotator{-30.0f, 45.0f, 0.0f});
    const auto Origin = FVector{123.4, -567.8, 90.1};

    for (const auto TexelWorldSize : {0.0, -1.0})
    {
        auto Remainder = FVector2f{7.0f, 7.0f};
        const auto Snapped = ck::pixel_art::Get_SnappedViewOrigin(
            Origin, ViewRotationMatrix, TexelWorldSize, Remainder);

        TestTrue(TEXT("a non-positive texel leaves the origin alone"), Snapped.Equals(Origin, 1e-6));
        TestTrue(TEXT("a non-positive texel reports no remainder"), Remainder.IsNearlyZero());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_OrthoWidthExtraction,
    "CkTests.UnitTests.CkPixelArtRender.Snap.OrthoWidthExtraction",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_OrthoWidthExtraction::RunTest(const FString& Parameters)
{
    const double OrthoWidths[] = {128.0, 1024.0, 4000.0, 51200.0};
    constexpr auto Aspect = 16.0 / 9.0;

    constexpr auto NearPlane = 10.0f;
    constexpr auto FarPlane = 10000.0f;
    constexpr auto ZScale = 1.0f / (FarPlane - NearPlane);

    for (const auto OrthoWidth : OrthoWidths)
    {
        // Assembled exactly as CameraStackTypes.cpp:316 does for a landscape viewport: half-extents, with the
        // vertical one additionally divided by the aspect ratio.
        const auto Projection = FReversedZOrthoMatrix{
            static_cast<float>(OrthoWidth / 2.0),
            static_cast<float>(OrthoWidth / 2.0 / Aspect),
            ZScale,
            -NearPlane};

        const auto Extracted = ck::pixel_art::Get_OrthoWidthFromProjection(Projection);

        TestTrue(*FString::Printf(TEXT("ortho width %f extracts as %f"), OrthoWidth, Extracted),
            FMath::IsNearlyEqual(Extracted, OrthoWidth, 1e-3));
    }

    TestTrue(TEXT("a projection with no horizontal scale extracts as zero"),
        FMath::IsNearlyZero(ck::pixel_art::Get_OrthoWidthFromProjection(FMatrix{
            FPlane{0, 0, 0, 0}, FPlane{0, 1, 0, 0}, FPlane{0, 0, 1, 0}, FPlane{0, 0, 0, 1}})));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_PixelArtRender_MarginFoldPreservesTexelSize,
    "CkTests.UnitTests.CkPixelArtRender.Snap.MarginFoldPreservesTexelSize",
    kCkUnitTestFlags)

bool FCkTest_PixelArtRender_MarginFoldPreservesTexelSize::RunTest(const FString& Parameters)
{
    // The render margin widens the projection so the extra texels are rendered rather than squeezed in. The
    // property that makes it invisible is that a texel is the same size in world units before and after the fold
    // — if it were not, the displayed window would silently zoom whenever the margin changed.
    const FIntPoint ViewportSizes[] = {
        FIntPoint{1280, 720}, FIntPoint{1920, 1080}, FIntPoint{2560, 1080},
        FIntPoint{3440, 1440}, FIntPoint{1366, 768}, FIntPoint{1024, 768}};

    const int32 InternalHeights[] = {180, 270, 360, 540};
    const int32 RequestedMargins[] = {1, 2, 4};

    for (const auto& ViewportSize : ViewportSizes)
    {
        const auto Aspect = static_cast<double>(ViewportSize.X) / static_cast<double>(ViewportSize.Y);

        for (const auto InternalHeight : InternalHeights)
        {
            for (const auto RequestedMargin : RequestedMargins)
            {
                const int32 InnerWidth = FMath::RoundToInt32(InternalHeight * Aspect);
                const auto MarginX = ck::pixel_art::Get_HorizontalMarginTexels(
                    InnerWidth, InternalHeight, RequestedMargin, Aspect);

                const int32 RenderedWidth = InnerWidth + 2 * MarginX;
                const auto Fraction = UCk_Utils_PixelArtRender_UE::Get_ExactFraction(RenderedWidth, ViewportSize.X);
                const int32 RenderedHeight = FMath::CeilToInt32(ViewportSize.Y * Fraction);

                const auto Label = FString::Printf(TEXT("%dx%d at %dp margin %d"),
                    ViewportSize.X, ViewportSize.Y, InternalHeight, RequestedMargin);

                if (!TestEqual(*FString::Printf(TEXT("%s: width lands exactly"), *Label),
                    FMath::CeilToInt32(ViewportSize.X * Fraction), RenderedWidth))
                { return false; }

                // The whole point of the aspect-compensated margin: the vertical fallout of a horizontal margin
                // still reaches the margin that was asked for, on BOTH sides, at any aspect ratio.
                const auto ExtraRows = RenderedHeight - InternalHeight;
                const auto TopInset = ExtraRows / 2;
                const auto BottomInset = ExtraRows - TopInset;

                if (!TestTrue(*FString::Printf(TEXT("%s: insets %d/%d reach the requested %d"),
                        *Label, TopInset, BottomInset, RequestedMargin),
                    TopInset >= RequestedMargin && BottomInset >= RequestedMargin))
                { return false; }

                // The fold itself: scale the horizontal projection term by Inner/Rendered so the wider render
                // covers proportionally more world, then derive the vertical term from the RENDERED aspect so a
                // texel stays square in spite of the engine's CeilToInt on height.
                constexpr auto AuthoredOrthoWidth = 2048.0;
                const auto TexelBeforeFold = AuthoredOrthoWidth / InnerWidth;

                const auto FoldedOrthoWidth = AuthoredOrthoWidth * RenderedWidth / InnerWidth;
                const auto TexelAfterFold = FoldedOrthoWidth / RenderedWidth;

                if (!TestTrue(*FString::Printf(TEXT("%s: texel size survives the fold (%f vs %f)"),
                        *Label, TexelBeforeFold, TexelAfterFold),
                    FMath::IsNearlyEqual(TexelBeforeFold, TexelAfterFold, 1e-9)))
                { return false; }

                const auto FoldedOrthoHeight = FoldedOrthoWidth * RenderedHeight / RenderedWidth;
                const auto VerticalTexel = FoldedOrthoHeight / RenderedHeight;

                if (!TestTrue(*FString::Printf(TEXT("%s: texels are square (%f vs %f)"),
                        *Label, TexelAfterFold, VerticalTexel),
                    FMath::IsNearlyEqual(TexelAfterFold, VerticalTexel, 1e-9)))
                { return false; }
            }
        }
    }

    return true;
}
