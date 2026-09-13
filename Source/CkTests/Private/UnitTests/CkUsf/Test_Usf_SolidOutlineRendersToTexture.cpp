// Real-RHI image regression for SolidOutline's renderer-backed stencil path.

#if WITH_EDITOR

#include "Misc/AutomationTest.h"
#include "Misc/App.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/ScopeExit.h"

#include "CkUsf/Outline/CkUsf_OutlinePreset.h"
#include "CkUsf/Outline/CkUsf_Outline_ProjectSettings.h"
#include "CkUsf/Outline/CkUsf_OutlineSubsystem.h"

#include "../CkUnitTest_Common.h"

#include "Components/SceneCaptureComponent2D.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/TextureRenderTarget2D.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "HAL/FileManager.h"
#include "GameFramework/Actor.h"
#include "ImageUtils.h"
#include "RenderingThread.h"
#include "TextureResource.h"

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_usf_outline_render
{
    constexpr auto kRtSize = 256;

    struct FRedBlob
    {
        int32 Area = 0;
        int32 MinX = kRtSize;
        int32 MinY = kRtSize;
        int32 MaxX = -1;
        int32 MaxY = -1;

        auto Width() const -> int32 { return MaxX - MinX + 1; }
    };

    auto NonBlackBounds(const TArray<FColor>& InPixels) -> FRedBlob
    {
        auto Result = FRedBlob{};
        for (auto Y = 0; Y < kRtSize; ++Y)
        for (auto X = 0; X < kRtSize; ++X)
        {
            const auto& Pixel = InPixels[Y * kRtSize + X];
            if (Pixel.R == 0 && Pixel.G == 0 && Pixel.B == 0) { continue; }
            ++Result.Area;
            Result.MinX = FMath::Min(Result.MinX, X);
            Result.MinY = FMath::Min(Result.MinY, Y);
            Result.MaxX = FMath::Max(Result.MaxX, X);
            Result.MaxY = FMath::Max(Result.MaxY, Y);
        }
        return Result;
    }

    auto Same_Settings(const FCk_Usf_OutlineThicknessSettings& InA,
                       const FCk_Usf_OutlineThicknessSettings& InB) -> bool
    {
        return InA.Get_Space() == InB.Get_Space() &&
               InA.Get_WorldSpaceThickness() == InB.Get_WorldSpaceThickness() &&
               InA.Get_ScreenSpaceThickness() == InB.Get_ScreenSpaceThickness() &&
               InA.Get_SquareCorners() == InB.Get_SquareCorners();
    }

    auto Is_OpaqueOutlineRed(const FColor& InPixel) -> bool
    {
        return InPixel.R > 180 && InPixel.R > InPixel.G + 80 && InPixel.R > InPixel.B + 80;
    }

    auto Find_RedBlobs(const TArray<FColor>& InPixels) -> TArray<FRedBlob>
    {
        auto Blobs = TArray<FRedBlob>{};
        auto Seen = TBitArray<>{false, InPixels.Num()};
        const auto IsRedAt = [&](int32 InX, int32 InY)
        {
            return InX >= 0 && InX < kRtSize && InY >= 0 && InY < kRtSize &&
                   Is_OpaqueOutlineRed(InPixels[InY * kRtSize + InX]);
        };

        for (auto Y = 0; Y < kRtSize; ++Y)
        for (auto X = 0; X < kRtSize; ++X)
        {
            const auto First = Y * kRtSize + X;
            if (Seen[First] || IsRedAt(X, Y) == false) { continue; }

            auto Queue = TArray<FIntPoint>{FIntPoint{X, Y}};
            Seen[First] = true;
            auto Blob = FRedBlob{};
            for (auto Read = 0; Read < Queue.Num(); ++Read)
            {
                const auto P = Queue[Read];
                ++Blob.Area;
                Blob.MinX = FMath::Min(Blob.MinX, P.X);
                Blob.MinY = FMath::Min(Blob.MinY, P.Y);
                Blob.MaxX = FMath::Max(Blob.MaxX, P.X);
                Blob.MaxY = FMath::Max(Blob.MaxY, P.Y);
                for (auto DY = -1; DY <= 1; ++DY)
                for (auto DX = -1; DX <= 1; ++DX)
                {
                    const auto NX = P.X + DX;
                    const auto NY = P.Y + DY;
                    if (DX == 0 && DY == 0 || IsRedAt(NX, NY) == false) { continue; }
                    const auto Next = NY * kRtSize + NX;
                    if (Seen[Next] == false)
                    {
                        Seen[Next] = true;
                        Queue.Add(FIntPoint{NX, NY});
                    }
                }
            }
            Blobs.Add(Blob);
        }
        return Blobs;
    }

    auto Add_Bar(UWorld* InWorld, UStaticMesh* InMesh, float InY) -> UStaticMeshComponent*
    {
        auto* Actor = InWorld->SpawnActor<AActor>(AActor::StaticClass());
        if (Actor == nullptr) { return nullptr; }

        auto* Mesh = NewObject<UStaticMeshComponent>(Actor);
        Actor->SetRootComponent(Mesh);
        Mesh->SetStaticMesh(InMesh);
        // With a square 256px orthographic view, these project to a 2px and a 16px wide feature.
        Mesh->SetWorldScale3D(FVector(0.1f, InY < 0.0f ? 0.02f : 0.16f, 0.5f));
        Mesh->SetWorldLocation(FVector(0.0f, InY, 0.0f));
        Mesh->RegisterComponent();
        return Mesh;
    }

    auto Save_InspectionPng(const TArray<FColor>& InPixels, const TCHAR* InName = TEXT("SolidOutlineRendersToTexture")) -> FString
    {
        const auto Dir = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation"), TEXT("SolidOutline"));
        IFileManager::Get().MakeDirectory(*Dir, true);
        const auto Path = FPaths::Combine(Dir, FString(InName) + TEXT(".png"));
        auto CompressedPng = TArray64<uint8>{};
        FImageUtils::PNGCompressImageArray(kRtSize, kRtSize,
            TArrayView64<const FColor>{InPixels.GetData(), InPixels.Num()}, CompressedPng);
        auto Png = TArray<uint8>{};
        Png.Append(CompressedPng.GetData(), CompressedPng.Num());
        return FFileHelper::SaveArrayToFile(Png, *Path) ? Path : FString{};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_SolidOutlineRendersToTexture,
    "CkTests.UnitTests.CkUsf.SolidOutlineRendersToTexture",
    // Toolbox discovers under NullRHI even for --no-nullrhi execution. Keep discovery enabled;
    // RunTest explicitly rejects a non-rendering invocation before touching GPU resources.
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Usf_SolidOutlineRendersToTexture::RunTest(const FString& Parameters)
{
    using namespace ck_test_usf_outline_render;

    if (FApp::CanEverRender() == false)
    {
        AddError(TEXT("Requires a real RHI; run with UnrealToolbox --no-nullrhi."));
        return false;
    }

    const auto* CustomDepth = IConsoleManager::Get().FindConsoleVariable(TEXT("r.CustomDepth"));
    if (TestNotNull(TEXT("r.CustomDepth is registered"), CustomDepth) == false ||
        TestEqual(TEXT("Custom depth carries a stencil"), CustomDepth->GetInt(), 3) == false)
    { return false; }

    auto* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (TestNotNull(TEXT("isolated preview world exists"), World) == false) { return false; }
    ON_SCOPE_EXIT
    {
        World->DestroyWorld(false);
        FlushRenderingCommands();
    };

    auto* Subsystem = UCkUsf_OutlineSubsystem::Get_OutlineSubsystem(World);
    if (TestNotNull(TEXT("outline subsystem exists"), Subsystem) == false) { return false; }

    const auto Defaults = Subsystem->Get_ThicknessSettings();
    if (TestEqual(TEXT("default thickness uses physical world-space units"),
        Defaults.Get_Space(), ECk_Usf_OutlineThicknessSpace::WorldSpace) == false ||
        TestEqual(TEXT("default world-space thickness is 5cm"), Defaults.Get_WorldSpaceThickness(), 5.0f) == false ||
        TestEqual(TEXT("default screen-space thickness is 5px"), Defaults.Get_ScreenSpaceThickness(), 5.0f) == false ||
        TestTrue(TEXT("default corners are square"), Defaults.Get_SquareCorners()) == false)
    { return false; }

    auto* Preset = NewObject<UCkUsf_OutlinePreset>(World);
    Preset->_OutlineColor = FLinearColor(1.0f, 0.0f, 0.0f);
    Preset->_OutlineBrightness = 1.0f;
    Preset->_ThicknessScale = 1.0f;
    const auto Stencil = Subsystem->Get_OrAllocate_StencilFor(Preset);
    ON_SCOPE_EXIT { Subsystem->Release_StencilFor(Preset); };
    if (TestNotEqual(TEXT("subsystem allocated a custom-stencil slot"), Stencil, static_cast<uint8>(0)) == false)
    { return false; }

    auto Screen5 = Defaults;
    Screen5.Set_Space(ECk_Usf_OutlineThicknessSpace::ScreenSpace);
    Screen5.Set_ScreenSpaceThickness(5.0f);
    Screen5.Set_SquareCorners(true);
    if (TestTrue(TEXT("screen-space 5px settings are accepted"), Subsystem->TrySet_ThicknessSettings(Screen5)) == false ||
        TestTrue(TEXT("accepted settings round-trip"), Same_Settings(Subsystem->Get_ThicknessSettings(), Screen5)) == false)
    { return false; }
    AddExpectedErrorPlain(TEXT("Outline thickness settings:"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    for (auto Invalid : {Screen5})
    {
        Invalid.Set_Space(static_cast<ECk_Usf_OutlineThicknessSpace>(255));
        TestFalse(TEXT("invalid thickness-space enum is rejected"), Subsystem->TrySet_ThicknessSettings(Invalid));
        TestTrue(TEXT("invalid enum does not mutate thickness settings"), Same_Settings(Subsystem->Get_ThicknessSettings(), Screen5));
        Invalid = Screen5;
        Invalid.Set_WorldSpaceThickness(0.0f);
        TestFalse(TEXT("zero world-space width is rejected"), Subsystem->TrySet_ThicknessSettings(Invalid));
        Invalid = Screen5;
        Invalid.Set_ScreenSpaceThickness(0.0f);
        TestFalse(TEXT("zero screen-space width is rejected"), Subsystem->TrySet_ThicknessSettings(Invalid));
        Invalid = Screen5;
        Invalid.Set_ScreenSpaceThickness(std::numeric_limits<float>::infinity());
        TestFalse(TEXT("infinite screen-space width is rejected"), Subsystem->TrySet_ThicknessSettings(Invalid));
        Invalid = Screen5;
        Invalid.Set_WorldSpaceThickness(std::numeric_limits<float>::quiet_NaN());
        TestFalse(TEXT("non-finite world-space width is rejected"), Subsystem->TrySet_ThicknessSettings(Invalid));
        TestTrue(TEXT("all invalid settings leave the accepted settings intact"), Same_Settings(Subsystem->Get_ThicknessSettings(), Screen5));
    }

    auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
    if (TestNotNull(TEXT("engine cube mesh exists"), Cube) == false) { return false; }
    FlushRenderingCommands();
    auto* Narrow = Add_Bar(World, Cube, -48.0f);
    auto* Broad = Add_Bar(World, Cube, 48.0f);
    if (TestNotNull(TEXT("2px feature was created"), Narrow) == false ||
        TestNotNull(TEXT("16px feature was created"), Broad) == false)
    { return false; }

    auto* Rt = NewObject<UTextureRenderTarget2D>(GetTransientPackage());
    Rt->RenderTargetFormat = ETextureRenderTargetFormat::RTF_RGBA8;
    Rt->ClearColor = FLinearColor::Black;
    Rt->InitAutoFormat(kRtSize, kRtSize);
    Rt->UpdateResourceImmediate(true);
    if (TestNotNull(TEXT("RGBA render target resource exists"), Rt->GameThread_GetRenderTargetResource()) == false)
    { return false; }

    auto* CaptureActor = World->SpawnActor<AActor>(AActor::StaticClass());
    if (TestNotNull(TEXT("scene-capture actor exists"), CaptureActor) == false) { return false; }
    auto* Capture = NewObject<USceneCaptureComponent2D>(CaptureActor);
    CaptureActor->SetRootComponent(Capture);
    Capture->TextureTarget = Rt;
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
    Capture->ProjectionType = ECameraProjectionMode::Orthographic;
    Capture->OrthoWidth = static_cast<float>(kRtSize);
    Capture->PostProcessBlendWeight = 1.0f;
    Capture->PostProcessSettings.bOverride_AutoExposureMethod = true;
    Capture->PostProcessSettings.AutoExposureMethod = EAutoExposureMethod::AEM_Manual;
    Capture->bCaptureEveryFrame = false;
    // UMaterialInterface::OverrideBlendableSettings rejects views without a state.
    // Manual captures still need this state for the production post-process material to run.
    Capture->bAlwaysPersistRenderingState = true;
    Capture->bCaptureOnMovement = false;
    Capture->SetWorldLocation(FVector(-1000.0f, 0.0f, 0.0f));
    Capture->SetWorldRotation(FRotator::ZeroRotator);
    Capture->RegisterComponent();
    // OnRegister calls UpdateShowFlags, restoring flags from the archetype. Apply deterministic
    // capture flags AFTER registration; otherwise physical exposure turns the unlit fixture black.
    Capture->ShowFlags.SetAntiAliasing(false);
    Capture->ShowFlags.SetBloom(false);
    Capture->ShowFlags.SetEyeAdaptation(false);
    Capture->ShowFlags.SetTonemapper(false);
    if (TestNotNull(TEXT("manual capture retains the view state required by post-process materials"),
        Capture->GetViewState(0)) == false)
    { return false; }

    const auto Capture_Read = [&]() -> TArray<FColor>
    {
        Capture->CaptureScene();
        FlushRenderingCommands();
        auto Pixels = TArray<FColor>{};
        if (Rt->GameThread_GetRenderTargetResource()->ReadPixels(Pixels) == false)
        { Pixels.Reset(); }
        return Pixels;
    };

    // Calibrate the geometry independently of lighting and the outline post-process.
    Capture->CaptureSource = ESceneCaptureSource::SCS_BaseColor;
    const auto Geometry = Capture_Read();
    if (TestEqual(TEXT("base-color calibration readback has the expected resolution"), Geometry.Num(), kRtSize * kRtSize) == false)
    { return false; }
    const auto GeometryPath = Save_InspectionPng(Geometry, TEXT("SolidOutlineGeometry"));
    auto GeometryPixelCount = 0;
    for (const auto& Pixel : Geometry)
    {
        if (Pixel.R > 10 || Pixel.G > 10 || Pixel.B > 10) { ++GeometryPixelCount; }
    }
    AddInfo(FString::Printf(TEXT("Base-color calibration: %d visible pixels; %s"), GeometryPixelCount, *GeometryPath));
    if (TestTrue(TEXT("unlit base-color calibration sees the two bars"), GeometryPixelCount >= 700 && GeometryPixelCount <= 1100) == false)
    { return false; }
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;

    const auto Baseline = Capture_Read();
    if (TestEqual(TEXT("unstenciled capture readback has the expected resolution"), Baseline.Num(), kRtSize * kRtSize) == false ||
        TestEqual(TEXT("unstenciled capture has no outline-red pixels"), Find_RedBlobs(Baseline).Num(), 0) == false)
    { return false; }

    Narrow->SetRenderCustomDepth(true);
    Narrow->SetCustomDepthStencilValue(Stencil);
    Broad->SetRenderCustomDepth(true);
    Broad->SetCustomDepthStencilValue(Stencil);

    auto* DebugMode = IConsoleManager::Get().FindConsoleVariable(TEXT("ck.Usf.Outline.Debug"));
    if (TestNotNull(TEXT("outline diagnostic mode exists"), DebugMode) == false) { return false; }
    const auto PreviousDebugMode = DebugMode->GetInt();
    ON_SCOPE_EXIT { DebugMode->Set(PreviousDebugMode, ECVF_SetByCode); };
    for (int32 Mode = 1; Mode <= 2; ++Mode)
    {
        DebugMode->Set(Mode, ECVF_SetByCode);
        const auto Diagnostic = Capture_Read();
        const auto Occupied = NonBlackBounds(Diagnostic).Area;
        Save_InspectionPng(Diagnostic, *FString::Printf(TEXT("OutlineDiagnostic%d"), Mode));
        TestEqual(FString::Printf(TEXT("diagnostic %d sees the calibrated stencil footprint"), Mode),
            Occupied, GeometryPixelCount);
    }
    DebugMode->Set(0, ECVF_SetByCode);

    const auto Pixels = Capture_Read();
    if (TestEqual(TEXT("stenciled capture readback has the expected resolution"), Pixels.Num(), kRtSize * kRtSize) == false)
    { return false; }
    const auto PngPath = Save_InspectionPng(Pixels);
    if (PngPath.IsEmpty()) { AddWarning(TEXT("Could not write SolidOutline inspection PNG.")); }
    else { AddInfo(FString::Printf(TEXT("Inspection PNG: %s"), *PngPath)); }

    auto Blobs = Find_RedBlobs(Pixels);
    Blobs.Sort([](const FRedBlob& A, const FRedBlob& B) { return A.Area < B.Area; });
    if (TestEqual(TEXT("exactly two contiguous opaque outline bands; no detached halo"), Blobs.Num(), 2) == false)
    { return false; }

    // A full 5px neighborhood band around 2px/16px by 50px bars is respectively about 620/760 opaque
    // pixels and 12px/26px wide. Sparse probes are too small; an unbounded halo is too large.
    const auto NarrowPass = TestTrue(TEXT("narrow feature has a dense five-pixel outline band"),
        Blobs[0].Area >= 450 && Blobs[0].Area <= 720 && Blobs[0].Width() >= 11 && Blobs[0].Width() <= 14);
    const auto BroadPass = TestTrue(TEXT("broad feature has a dense five-pixel outline band"),
        Blobs[1].Area >= 600 && Blobs[1].Area <= 860 && Blobs[1].Width() >= 25 && Blobs[1].Width() <= 28);

    auto ScreenFractional = Screen5;
    ScreenFractional.Set_ScreenSpaceThickness(5.5f);
    const auto FractionalAccepted = TestTrue(TEXT("positive fractional screen-space thickness is accepted"),
        Subsystem->TrySet_ThicknessSettings(ScreenFractional));
    auto FractionalBlobs = Find_RedBlobs(Capture_Read());
    FractionalBlobs.Sort([](const FRedBlob& A, const FRedBlob& B) { return A.Area < B.Area; });
    const auto FractionalRendered = TestTrue(TEXT("fractional screen-space thickness still renders both contours"),
        FractionalBlobs.Num() == 2 && FractionalBlobs[0].Width() >= Blobs[0].Width() &&
        FractionalBlobs[1].Width() >= Blobs[1].Width());

    auto ScreenWide = Screen5;
    ScreenWide.Set_ScreenSpaceThickness(24.0f);
    const auto WideAccepted = TestTrue(TEXT("screen-space thickness above the retired 16px ceiling is accepted"),
        Subsystem->TrySet_ThicknessSettings(ScreenWide));
    auto WideBlobs = Find_RedBlobs(Capture_Read());
    WideBlobs.Sort([](const FRedBlob& A, const FRedBlob& B) { return A.Area < B.Area; });
    const auto WideRendered = TestTrue(TEXT("24px screen-space contours exceed the old 16px footprint"),
        WideBlobs.Num() == 2 && WideBlobs[0].Width() >= 48 && WideBlobs[1].Width() >= 62);

    Subsystem->TrySet_ThicknessSettings(Screen5);
    Capture->ProjectionType = ECameraProjectionMode::Perspective;
    Capture->FOVAngle = 90.0f;
    Broad->SetWorldScale3D(FVector(0.1f, 2.0f, 2.0f));
    Broad->SetWorldLocation(FVector(0.0f, 0.0f, 0.0f));
    Narrow->SetVisibility(false);
    const auto ScreenNearGeometry = NonBlackBounds([&]() { Capture->CaptureSource = ESceneCaptureSource::SCS_BaseColor; return Capture_Read(); }());
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
    const auto ScreenNearOutline = NonBlackBounds(Capture_Read());
    Broad->SetWorldLocation(FVector(1000.0f, 0.0f, 0.0f));
    const auto ScreenFarGeometry = NonBlackBounds([&]() { Capture->CaptureSource = ESceneCaptureSource::SCS_BaseColor; return Capture_Read(); }());
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
    const auto ScreenFarOutline = NonBlackBounds(Capture_Read());
    const auto ScreenNearBand = ScreenNearOutline.Width() - ScreenNearGeometry.Width();
    const auto ScreenFarBand = ScreenFarOutline.Width() - ScreenFarGeometry.Width();
    const auto PixelInvariant = TestTrue(TEXT("screen-space 5px width is depth invariant"),
        FMath::Abs(ScreenNearBand - ScreenFarBand) <= 1);

    // World space is physically scaled: the same 50cm ring grows when the perspective FOV narrows and
    // shrinks when the identical mesh moves away.  Measure each capture's red extent against its own
    // base-color extent rather than assuming a screen coordinate.
    auto World50 = Defaults;
    World50.Set_Space(ECk_Usf_OutlineThicknessSpace::WorldSpace);
    World50.Set_WorldSpaceThickness(50.0f);
    const auto WorldAccepted = TestTrue(TEXT("positive world-space thickness is accepted"),
        Subsystem->TrySet_ThicknessSettings(World50));
    Capture->ProjectionType = ECameraProjectionMode::Perspective;
    Capture->FOVAngle = 90.0f;
    Broad->SetWorldLocation(FVector(0.0f, 0.0f, 0.0f));
    const auto NearGeometry = NonBlackBounds([&]() { Capture->CaptureSource = ESceneCaptureSource::SCS_BaseColor; return Capture_Read(); }());
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
    const auto NearOutline = NonBlackBounds(Capture_Read());
    Broad->SetWorldLocation(FVector(1000.0f, 0.0f, 0.0f));
    const auto FarGeometry = NonBlackBounds([&]() { Capture->CaptureSource = ESceneCaptureSource::SCS_BaseColor; return Capture_Read(); }());
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
    const auto FarOutline = NonBlackBounds(Capture_Read());
    Broad->SetWorldLocation(FVector(0.0f, 0.0f, 0.0f));
    Capture->FOVAngle = 60.0f;
    const auto NarrowFovGeometry = NonBlackBounds([&]() { Capture->CaptureSource = ESceneCaptureSource::SCS_BaseColor; return Capture_Read(); }());
    Capture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
    const auto NarrowFovOutline = NonBlackBounds(Capture_Read());
    const auto NearBand = NearOutline.Width() - NearGeometry.Width();
    const auto FarBand = FarOutline.Width() - FarGeometry.Width();
    const auto NarrowFovBand = NarrowFovOutline.Width() - NarrowFovGeometry.Width();
    AddInfo(FString::Printf(TEXT("World-space band deltas: near=%d far=%d fov60=%d"), NearBand, FarBand, NarrowFovBand));
    const auto WorldScales = TestTrue(TEXT("world-space outline shrinks with distance and grows as FOV narrows"),
        NearBand > FarBand && NarrowFovBand > NearBand);
    return NarrowPass && BroadPass && FractionalAccepted && FractionalRendered && WideAccepted && WideRendered &&
           PixelInvariant && WorldAccepted && WorldScales;
}

#endif
