// The batched path must draw the same immediate-mode primitives.  The legacy wrappers are the
// oracle: this test reads their real ULineBatchComponent output, then compares every primitive
// field and ordering against the private production geometry builder.

#include "CkCrowd/Agent/CkCrowdAgent_DrawNavStatus_Processor.h"

#include "CkCore/Debug/CkDebugDraw_Utils.h"
#include "CkCore/Diagnostics/CkDiagnosticVisibility.h"

#include "../CkUnitTest_Common.h"

#include <Components/LineBatchComponent.h>
#include <Engine/World.h>
#include <HAL/IConsoleManager.h>
#include <Misc/ScopeExit.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_crowd_nav_status_geometry
{
    constexpr auto InformEngineOfWorld = false;

    constexpr auto MarkerHalfSize  = 30.0f;
    constexpr auto MarkerThickness = 4.0f;
    constexpr auto DashThickness   = 3.0f;
    constexpr auto StarSize        = 24.0f;
    constexpr auto StarPoints      = 5;
    constexpr auto OneFrame        = 0.0f;

    struct FGeometryRow
    {
        const TCHAR* _Name;
        FVector _MarkerCentre;
        FVector _GoalLineStart;
        FVector _GoalLineEnd;
        float _GoalDashSize;
        FLinearColor _Color;
        int32 _ExpectedLineCount;
    };

    auto
        Draw_LegacyGeometry(
            UWorld& InWorld,
            const FGeometryRow& InRow) -> TArray<FBatchedLine>
    {
        auto* Batcher = InWorld.GetLineBatcher(UWorld::ELineBatcherType::World);
        if (Batcher == nullptr)
        { return {}; }

        Batcher->BatchedLines.Reset();

        UCk_Utils_DebugDraw_UE::DrawDebugLine(
            &InWorld,
            InRow._MarkerCentre + FVector{-MarkerHalfSize, -MarkerHalfSize, 0.0f},
            InRow._MarkerCentre + FVector{+MarkerHalfSize, +MarkerHalfSize, 0.0f},
            InRow._Color,
            OneFrame,
            MarkerThickness);
        UCk_Utils_DebugDraw_UE::DrawDebugLine(
            &InWorld,
            InRow._MarkerCentre + FVector{-MarkerHalfSize, +MarkerHalfSize, 0.0f},
            InRow._MarkerCentre + FVector{+MarkerHalfSize, -MarkerHalfSize, 0.0f},
            InRow._Color,
            OneFrame,
            MarkerThickness);
        UCk_Utils_DebugDraw_UE::DrawDebugDashedLine(
            &InWorld,
            InRow._GoalLineStart,
            InRow._GoalLineEnd,
            InRow._GoalDashSize,
            InRow._Color,
            OneFrame,
            DashThickness);
        UCk_Utils_DebugDraw_UE::DrawDebugStar(
            &InWorld,
            InRow._GoalLineEnd,
            StarSize,
            StarPoints,
            InRow._Color,
            OneFrame,
            DashThickness);

        auto Lines = Batcher->BatchedLines;
        Batcher->BatchedLines.Reset();
        return Lines;
    }

    auto
        IsSamePrimitive(
            const FBatchedLine& InLegacy,
            const FBatchedLine& InBatched) -> bool
    {
        return InLegacy.Start == InBatched.Start
            && InLegacy.End == InBatched.End
            && InLegacy.Color == InBatched.Color
            && InLegacy.Thickness == InBatched.Thickness
            && InLegacy.RemainingLifeTime == InBatched.RemainingLifeTime
            && InLegacy.DepthPriority == InBatched.DepthPriority
            && InLegacy.BatchID == InBatched.BatchID;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_NavStatusGeometry,
    "CkTests.UnitTests.CkCrowd.NavStatus.GeometryMatchesLegacyPrimitives",
    kCkUnitTestFlags)

bool FCkTest_Crowd_NavStatusGeometry::RunTest(const FString& Parameters)
{
    using namespace ck_test_crowd_nav_status_geometry;

    auto* StreamerMode = IConsoleManager::Get().FindConsoleVariable(TEXT("ck.Debug.StreamerMode"));
    if (NOT TestNotNull(TEXT("the streamer-mode CVar exists"), StreamerMode))
    { return false; }
    const auto OriginalStreamerMode = StreamerMode->GetInt();
    StreamerMode->Set(0, ECVF_SetByCode);
    ON_SCOPE_EXIT { StreamerMode->Set(OriginalStreamerMode, ECVF_SetByCode); };

    auto* DrawDebugHelpers = IConsoleManager::Get().FindConsoleVariable(TEXT("r.EnableDrawDebugHelpers"));
    if (NOT TestNotNull(TEXT("the engine debug-helper CVar exists"), DrawDebugHelpers))
    { return false; }
    const auto OriginalDrawDebugHelpers = DrawDebugHelpers->GetInt();
    DrawDebugHelpers->Set(1, ECVF_SetByCode);
    ON_SCOPE_EXIT { DrawDebugHelpers->Set(OriginalDrawDebugHelpers, ECVF_SetByCode); };

    // The launch switch intentionally outranks the CVar. A capture started with it cannot expose
    // legacy primitives, so skip rather than mistake that policy for a geometry regression.
    if (ck::diagnostic_visibility::Is_HiddenForStreamerMode())
    {
        AddInfo(TEXT("NavStatus geometry equivalence is skipped under the -CkStreamerMode launch policy"));
        return true;
    }

    auto* World = UWorld::CreateWorld(
        EWorldType::Game,
        InformEngineOfWorld,
        FName{TEXT("CkCrowdNavStatusGeometry")});
    if (NOT TestNotNull(TEXT("the fixture owns a game world"), World))
    { return false; }
    ON_SCOPE_EXIT { World->DestroyWorld(InformEngineOfWorld); };

    // CreateWorld alone has no line batcher. This is the engine's normal world-component path
    // which creates and registers it before the legacy Kismet wrappers write real primitives.
    World->UpdateWorldComponents(/*bRerunConstructionScripts*/ false, /*bCurrentLevelOnly*/ false);
    auto* Batcher = World->GetLineBatcher(UWorld::ELineBatcherType::World);
    if (NOT TestNotNull(TEXT("the fixture has the initialized world line batcher"), Batcher))
    { return false; }
    const auto OriginalDefaultLifeTime = Batcher->DefaultLifeTime;
    Batcher->DefaultLifeTime = 7.25f;
    ON_SCOPE_EXIT { Batcher->DefaultLifeTime = OriginalDefaultLifeTime; };

    const auto Rows = TArray<FGeometryRow>{
        {TEXT("zero-length goal line with faded alpha"),
         FVector{100.0, 200.0, 230.0}, FVector{300.0, 100.0, 96.0}, FVector{300.0, 100.0, 96.0},
         20.0f, FLinearColor{1.0f, 0.10f, 0.10f, 0.35f}, 12},
        {TEXT("short goal line"),
         FVector{-100.0, 100.0, 230.0}, FVector{0.0, 0.0, 96.0}, FVector{10.0, 0.0, 96.0},
         20.0f, FLinearColor{1.0f, 0.85f, 0.20f, 0.50f}, 13},
        {TEXT("ordinary goal line"),
         FVector{0.0, 0.0, 230.0}, FVector{0.0, 0.0, 96.0}, FVector{400.0, 0.0, 96.0},
         20.0f, FLinearColor{1.0f, 0.35f, 0.05f, 0.75f}, 22},
        {TEXT("diagonal goal line with a nonzero Z delta"),
         FVector{-50.0, 50.0, 230.0}, FVector{10.0, -20.0, 96.0}, FVector{250.0, 320.0, 596.0},
         20.0f, FLinearColor{0.20f, 0.70f, 1.0f, 0.60f}, 28},
        {TEXT("long goal line capped at sixty-four dashes"),
         FVector{50.0, -50.0, 230.0}, FVector{0.0, 0.0, 96.0}, FVector{5120.0, 0.0, 96.0},
         40.0f, FLinearColor{1.0f, 0.05f, 0.60f, 1.0f}, 76},
    };

    for (const auto& Row : Rows)
    {
        const auto LegacyLines = Draw_LegacyGeometry(*World, Row);
        TestEqual(
            FString::Printf(TEXT("%s: legacy wrappers emit the expected primitive count"), Row._Name),
            LegacyLines.Num(),
            Row._ExpectedLineCount);

        auto BatchedLines = TArray<FBatchedLine>{};
        BatchedLines.Emplace(
            FVector{-999.0, -999.0, -999.0},
            FVector{+999.0, +999.0, +999.0},
            FLinearColor::Black,
            -1.0f,
            -1.0f,
            SDPG_Foreground,
            77);
        ck::FProcessor_CrowdAgent_DrawNavStatus::Build_GeometryLines(
            Row._MarkerCentre,
            Row._GoalLineStart,
            Row._GoalLineEnd,
            Row._GoalDashSize,
            Row._Color,
            Batcher->DefaultLifeTime,
            BatchedLines);

        TestEqual(
            FString::Printf(TEXT("%s: batched primitive count matches legacy"), Row._Name),
            BatchedLines.Num(),
            LegacyLines.Num());

        Batcher->DrawLines(BatchedLines);
        const auto SubmittedLines = Batcher->BatchedLines;
        Batcher->BatchedLines.Reset();

        TestEqual(
            FString::Printf(TEXT("%s: the world batcher receives the same primitive count"), Row._Name),
            SubmittedLines.Num(),
            LegacyLines.Num());

        const auto ComparableLineCount = FMath::Min(LegacyLines.Num(), SubmittedLines.Num());
        for (auto LineIndex = 0; LineIndex < ComparableLineCount; ++LineIndex)
        {
            TestTrue(
                FString::Printf(TEXT("%s: primitive %d preserves order, points, colour, thickness, depth, lifetime, and id"),
                    Row._Name,
                    LineIndex),
                IsSamePrimitive(LegacyLines[LineIndex], SubmittedLines[LineIndex]));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
