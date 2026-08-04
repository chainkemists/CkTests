#include "CkVoxelNav/Authoring/CkVoxelNavVolume_Actor.h"

#include "CkJolt/StaticWorld/CkJoltStaticWorld_CookedQuery.h"

#include "CkCore/Validation/CkIsValid.h"

#include "../CkUnitTest_Common.h"

#include <Components/BoxComponent.h>
#include <Misc/AutomationTest.h>
#include <Tests/AutomationCommon.h>

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_DebugSnapshot_AuthoringActorMapsExactParams,
    "Ck.VoxelNav.DebugSnapshot.AuthoringActorMapsExactParams",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_VoxelNav_DebugSnapshot_AuthoringActorMapsExactParams::RunTest(const FString& Parameters)
{
    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* World = WorldWrapper.GetTestWorld();
    auto* Actor = World != nullptr ? World->SpawnActor<ACk_VoxelNavVolume_UE>() : nullptr;
    if (NOT TestNotNull(TEXT("VoxelNav authoring actor is placeable in an editor world"), Actor))
    { return false; }

    auto* BoundsComponent = Actor->FindComponentByClass<UBoxComponent>();
    if (NOT TestNotNull(TEXT("authoring actor owns an editable box"), BoundsComponent))
    { return false; }

    const auto Location = FVector{1200.0, -900.0, 300.0};
    const auto Extents = FVector{800.0, 600.0, 400.0};
    Actor->SetActorLocation(Location);
    BoundsComponent->SetBoxExtent(Extents);

    const auto ExpectedBounds = FBox{Location - Extents, Location + Extents};
    const auto Params = Actor->Build_ParamsData();

    TestTrue(TEXT("world bounds follow the placed actor box"),
        Actor->Get_WorldVolumeBounds().Equals(ExpectedBounds));
    TestTrue(TEXT("runtime params receive those exact world bounds"),
        Params.Get_VolumeBounds().Equals(ExpectedBounds));
    TestEqual(TEXT("runtime params retain the authored finest-cell default"),
        Params.Get_FinestCellSizeUu(), 50.0f);
    TestEqual(TEXT("runtime params retain the authored clearance default"),
        Params.Get_ClearanceUu(), 0.0f);
    TestTrue(TEXT("runtime params retain auto-build"),
        Params.Get_AutoBuildOnSetup() == ECk_EnableDisable::Enable);
    TestTrue(TEXT("runtime params retain chunk partitioning"),
        Params.Get_ChunkPartitioning() == ECk_EnableDisable::Enable);
    TestFalse(TEXT("editor-only actor has no runtime handle before BeginPlay"),
        ck::IsValid(Actor->Get_VolumeHandle()));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_DebugSnapshot_CookedQueryIsFailClosedBeforeLoad,
    "Ck.VoxelNav.DebugSnapshot.CookedQueryIsFailClosedBeforeLoad",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_VoxelNav_DebugSnapshot_CookedQueryIsFailClosedBeforeLoad::RunTest(const FString& Parameters)
{
    const auto Query = ck::jolt::FCk_Jolt_CookedWorldQuery{};

    TestFalse(TEXT("new cooked query is not ready"), Query.Get_IsReady());
    TestTrue(TEXT("new cooked query reports NotLoaded"),
        Query.Get_LoadResult()._Status == ck::jolt::ECk_Jolt_CookedWorldQueryLoadStatus::NotLoaded);
    TestFalse(TEXT("unready query cannot report an occupied box"),
        Query.Get_IsBoxOccupied(FVector::ZeroVector, FVector{50.0}));
    TestFalse(TEXT("unready query cannot report a blocked segment"),
        Query.Get_IsSegmentBlocked(FVector::ZeroVector, FVector{100.0, 0.0, 0.0}));
    TestEqual(TEXT("unready query has no broadphase bodies"),
        Query.Get_BroadphaseBodyCount(FBox{FVector{-100.0}, FVector{100.0}}), 0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
