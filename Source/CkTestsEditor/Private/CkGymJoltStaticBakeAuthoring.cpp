#include "CkTestsEditor/CkTestsEditor_Log.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/Validation/CkIsValid.h"

#include <Components/SplineMeshComponent.h>
#include <Editor.h>
#include <Engine/StaticMesh.h>
#include <Engine/World.h>
#include <EngineUtils.h>
#include <HAL/IConsoleManager.h>
#include <Landscape.h>
#include <LandscapeInfo.h>
#include <LandscapeProxy.h>
#include <UObject/Package.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_gym_jolt_staticbake_authoring
{
    // ---- Landscape tunables --------------------------------------------------------
    // 1x1 component, 1 subsection, 63 quads/section -> SizeX = SizeY = 64 verts, one
    // ULandscapeComponent. Scale (50,50,100) gives a 63*50 = 3150uu square footprint.
    constexpr auto LandscapeQuadsPerSection = int32{63};
    constexpr auto LandscapeNumSubsections  = int32{1};
    constexpr auto LandscapeComponentCountX = int32{1};
    constexpr auto LandscapeComponentCountY = int32{1};

    constexpr auto LandscapeScaleXY = 50.0;
    constexpr auto LandscapeScaleZ  = 100.0;

    constexpr auto LandscapeCenterX = -4300.0;
    constexpr auto LandscapeCenterY = 20000.0;
    constexpr auto LandscapeCenterZ = 0.0;

    // uint16 height encoding: 32768 == local Z zero. Rolling hills: amplitude 320 ticks,
    // wavelength ~21 verts (~1050uu at ScaleXY 50).
    constexpr auto LandscapeHeightMidpoint = int32{32768};
    constexpr auto LandscapeHeightAmplitude = 320.0;
    constexpr auto LandscapeHillWavelength  = 21.0;

    // ---- Spline-mesh tunables ------------------------------------------------------
    constexpr auto SplineSpawnX = -1000.0;
    constexpr auto SplineSpawnY = 21000.0;
    constexpr auto SplineSpawnZ = 250.0;

    constexpr auto CubeMeshPath = TEXT("/Engine/BasicShapes/Cube.Cube");

    // ---- Identity ------------------------------------------------------------------
    constexpr auto TargetLevelSuffix   = TEXT("TestGyms_CkTests_Level");
    constexpr auto LandscapeActorLabel = TEXT("CkJoltGym_AuthoredLandscape");
    constexpr auto SplineActorLabel    = TEXT("CkJoltGym_AuthoredSpline");
    constexpr auto SplineActorTag      = TEXT("CkJoltGym.AuthoredSpline");

    // --------------------------------------------------------------------------------

    auto
        DoAuthorLandscape(
            UWorld* InWorld)
        -> void
    {
        CK_ENSURE_IF_NOT(ck::IsValid(InWorld, ck::IsValid_Policy_NullptrOnly{}), TEXT("Null world in DoAuthorLandscape"))
        { return; }

        const auto QuadsPerComponent = LandscapeQuadsPerSection * LandscapeNumSubsections;
        const auto SizeX = LandscapeComponentCountX * QuadsPerComponent + 1;
        const auto SizeY = LandscapeComponentCountY * QuadsPerComponent + 1;

        // Height field. World height = (Value - 32768) * ScaleZ * LANDSCAPE_ZSCALE, where
        // LANDSCAPE_ZSCALE = 1/128 (Engine/Source/Runtime/Landscape/Public/LandscapeDataAccess.h:13).
        // Amplitude 320 ticks -> 320 * 100 / 128 = 250uu peak-to-flat at ScaleZ 100.
        auto Heights = TArray<uint16>{};
        Heights.Reserve(SizeX * SizeY);
        for (auto Y = int32{0}; Y < SizeY; ++Y)
        {
            for (auto X = int32{0}; X < SizeX; ++X)
            {
                const auto Wave = LandscapeHeightAmplitude
                    * FMath::Sin(2.0 * UE_DOUBLE_PI * X / LandscapeHillWavelength)
                    * FMath::Cos(2.0 * UE_DOUBLE_PI * Y / LandscapeHillWavelength);
                const auto Encoded = LandscapeHeightMidpoint + static_cast<int32>(FMath::RoundToInt(Wave));
                Heights.Add(static_cast<uint16>(Encoded));
            }
        }

        // Both maps key on the DEFAULT FGuid — the base edit layer. No paint layers, so
        // the material-layer entry is an empty array. Mirrors
        // LandscapeEditorDetailCustomization_NewLandscape.cpp:1188-1200.
        auto HeightDataPerLayers = TMap<FGuid, TArray<uint16>>{};
        HeightDataPerLayers.Add(FGuid(), MoveTemp(Heights));

        auto MaterialLayerDataPerLayers = TMap<FGuid, TArray<FLandscapeImportLayerInfo>>{};
        MaterialLayerDataPerLayers.Add(FGuid(), TArray<FLandscapeImportLayerInfo>{});

        const auto Scale         = FVector{LandscapeScaleXY, LandscapeScaleXY, LandscapeScaleZ};
        const auto Rotation      = FRotator::ZeroRotator;
        const auto DesiredCenter = FVector{LandscapeCenterX, LandscapeCenterY, LandscapeCenterZ};

        // SpawnActor places the landscape's (0,0) corner; shift by half the total quad
        // extent (rotated+scaled) so the footprint centers on DesiredCenter.
        // Mirrors LandscapeEditorDetailCustomization_NewLandscape.cpp:1209.
        const auto Offset = FTransform(Rotation, FVector::ZeroVector, Scale).TransformVector(
            FVector(-LandscapeComponentCountX * QuadsPerComponent / 2.0,
                    -LandscapeComponentCountY * QuadsPerComponent / 2.0, 0.0));

        auto* Landscape = InWorld->SpawnActor<ALandscape>(DesiredCenter + Offset, Rotation);
        CK_ENSURE_IF_NOT(ck::IsValid(Landscape, ck::IsValid_Policy_NullptrOnly{}),
            TEXT("Failed to spawn ALandscape at [{}]"), (DesiredCenter + Offset).ToString())
        { return; }

        Landscape->SetActorRelativeScale3D(Scale);
        Landscape->StaticLightingLOD = 0;

        Landscape->Import(FGuid::NewGuid(), 0, 0, SizeX - 1, SizeY - 1,
            LandscapeNumSubsections, LandscapeQuadsPerSection,
            HeightDataPerLayers, TEXT(""), MaterialLayerDataPerLayers,
            ELandscapeImportAlphamapType::Additive, TArrayView<const FLandscapeLayer>());

        auto* Info = Landscape->GetLandscapeInfo();
        CK_ENSURE_IF_NOT(ck::IsValid(Info, ck::IsValid_Policy_NullptrOnly{}),
            TEXT("Landscape has no ULandscapeInfo after Import"))
        { return; }
        Info->UpdateLayerInfoMap(Landscape);

        Landscape->SetActorLabel(LandscapeActorLabel);

        CK_ENSURE_IF_NOT(Landscape->LandscapeComponents.Num() == 1,
            TEXT("Expected exactly 1 landscape component, got [{}]"), Landscape->LandscapeComponents.Num())
        { return; }
    }

    // --------------------------------------------------------------------------------

    auto
        DoAuthorSpline(
            UWorld* InWorld)
        -> void
    {
        CK_ENSURE_IF_NOT(ck::IsValid(InWorld, ck::IsValid_Policy_NullptrOnly{}), TEXT("Null world in DoAuthorSpline"))
        { return; }

        auto* Actor = InWorld->SpawnActor<AActor>(AActor::StaticClass(),
            FTransform{FRotator::ZeroRotator, FVector{SplineSpawnX, SplineSpawnY, SplineSpawnZ}});
        CK_ENSURE_IF_NOT(ck::IsValid(Actor, ck::IsValid_Policy_NullptrOnly{}),
            TEXT("Failed to spawn spline-mesh host actor"))
        { return; }

        auto* SplineComp = NewObject<USplineMeshComponent>(Actor, TEXT("AuthoredSplineMesh"));
        CK_ENSURE_IF_NOT(ck::IsValid(SplineComp, ck::IsValid_Policy_NullptrOnly{}),
            TEXT("Failed to create USplineMeshComponent"))
        { return; }

        // Configure fully before registration.
        SplineComp->SetMobility(EComponentMobility::Static);

        auto* CubeMesh = LoadObject<UStaticMesh>(nullptr, CubeMeshPath);
        CK_ENSURE_IF_NOT(ck::IsValid(CubeMesh, ck::IsValid_Policy_NullptrOnly{}),
            TEXT("Failed to load cube mesh [{}]"), FString{CubeMeshPath})
        { return; }
        SplineComp->SetStaticMesh(CubeMesh);

        SplineComp->SetCollisionProfileName(TEXT("BlockAll"));

        // Mirrors the gym's runtime spline lane so authored and runtime content are visually comparable.
        SplineComp->SetStartAndEnd(FVector::ZeroVector, FVector{400, 0, 0}, FVector{400, 0, 0}, FVector{400, 400, 0});

        Actor->SetRootComponent(SplineComp);
        Actor->AddInstanceComponent(SplineComp);   // required or the component won't serialize into the level
        SplineComp->RegisterComponent();

        // A rootless AActor DROPS its spawn transform (PostSpawnInitialize only applies it to an
        // existing root), and promoting the component to root afterwards leaves it at identity —
        // so the actor would sit at the world origin. Place the now-root component explicitly.
        SplineComp->SetWorldLocation(FVector{SplineSpawnX, SplineSpawnY, SplineSpawnZ});

        // The Jolt level sweep bakes collision off GetBodySetup at PIE, so editor authoring
        // must produce cooked collision now. RecreatePhysicsState is the one retry we allow.
        if (NOT ck::IsValid(SplineComp->GetBodySetup(), ck::IsValid_Policy_NullptrOnly{}))
        {
            SplineComp->RecreatePhysicsState();

            if (NOT ck::IsValid(SplineComp->GetBodySetup(), ck::IsValid_Policy_NullptrOnly{}))
            {
                // Deliberately do NOT destroy the actor and do NOT return — the ensure firing
                // loudly IS the intended outcome, so a human sees it and reports it.
                CK_ENSURE_IF_NOT(false,
                    TEXT("Editor spline-mesh collision did not cook — the Jolt bake will ensure at PIE. Report this."))
                { }
            }
        }

        Actor->Tags.Add(FName{SplineActorTag});
        Actor->SetActorLabel(SplineActorLabel);
    }

    // --------------------------------------------------------------------------------

    auto
        DoAuthorJoltStaticBakeContent()
        -> void
    {
        if (NOT GEditor)
        { return; }

        auto* World = GEditor->GetEditorWorldContext().World();
        CK_ENSURE_IF_NOT(ck::IsValid(World, ck::IsValid_Policy_NullptrOnly{}),
            TEXT("No editor world available — open the TestGyms_CkTests_Level level first."))
        { return; }

        const auto WorldPackageName = World->GetPackage()->GetName();
        CK_ENSURE_IF_NOT(WorldPackageName.EndsWith(TargetLevelSuffix),
            TEXT("Open the TestGyms_CkTests_Level level before running this command (current world: [{}])."), WorldPackageName)
        { return; }

        CK_ENSURE_IF_NOT(World->GetWorldPartition() == nullptr,
            TEXT("This authoring ritual assumes a classic (non-World-Partition) level."))
        { return; }

        // ---- Idempotent cleanup: remove any prior output before re-authoring ----------
        constexpr auto ShouldModifyLevel = true;

        auto LandscapesToRemove = TArray<AActor*>{};
        for (TActorIterator<ALandscape> It{World}; It; ++It)
        {
            if (It->GetActorLabel() == LandscapeActorLabel)
            { LandscapesToRemove.Add(*It); }
        }
        for (auto* Actor : LandscapesToRemove)
        { World->EditorDestroyActor(Actor, ShouldModifyLevel); }

        auto SplinesToRemove = TArray<AActor*>{};
        for (TActorIterator<AActor> It{World}; It; ++It)
        {
            if (It->ActorHasTag(FName{SplineActorTag}))
            { SplinesToRemove.Add(*It); }
        }
        for (auto* Actor : SplinesToRemove)
        { World->EditorDestroyActor(Actor, ShouldModifyLevel); }

        // ---- Author ---------------------------------------------------------------------
        DoAuthorLandscape(World);
        DoAuthorSpline(World);

        ck::tests_editor::Log(
            TEXT("[CkJoltGym Authoring] Done. Removed [{}] prior landscape(s) and [{}] prior spline actor(s), then ")
            TEXT("authored landscape '{}' (center -4300,20000; 3150uu rolling hills) and spline-mesh actor '{}' at ")
            TEXT("(-1000,21000,250). Nothing was saved — review the level and save it (Ctrl+S) to persist."),
            LandscapesToRemove.Num(), SplinesToRemove.Num(),
            FString{LandscapeActorLabel}, FString{SplineActorLabel});
    }

    // --------------------------------------------------------------------------------

    static FAutoConsoleCommand GAuthorCommand(
        TEXT("Ck.Gym.AuthorJoltStaticBakeContent"),
        TEXT("Author a procedural landscape + spline-mesh actor next to the Jolt StaticBake gym station ")
        TEXT("in the open TestGyms_CkTests_Level. Idempotent; does NOT save the level (human reviews and saves)."),
        FConsoleCommandDelegate::CreateLambda([]()
        {
            DoAuthorJoltStaticBakeContent();
        }));
}
