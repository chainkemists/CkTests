#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Fragment.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"

#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavBake_TestTypes.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------
// End-to-end bake in a real PIE world: three static JoltBody boxes in a known layout, a VoxelNavVolume over
// them, and a budgeted build driven by its own processors to completion — the whole 1C machine, the 1D
// entity, and CkJolt's occupancy surface together.
//
// The boxes sit far above the map's own geometry so the volume contains nothing this test did not spawn,
// and each is centred on a LEAF centre, one per layer-1 cell: that puts the occupied cells where the
// assertions expect them without depending on how a probe flush against a cell face resolves.
//
// The budget is deliberately far smaller than the bake needs, because the point of the whole resumable
// machine is that a bake spans frames instead of stalling one.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_bake
{
    // Cross-latent-command state, reset at each test start.
    static FCk_Handle_VoxelNavVolume GVolume;
    static TArray<FCk_Handle_JoltBody> GBoxBodies;
    static TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE> GListener;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr int32 SettleFrames = 30;

    constexpr auto FinestCellSizeUu = 50.0f;

    // Far above the map, matching the CkJolt occupancy exemplar's clearance.
    const auto VolumeCenter = FVector{0.0, 0.0, 20000.0};
    const auto VolumeHalfExtents = FVector{800.0};

    // Leaf centres inside three DIFFERENT layer-1 cells, expressed relative to the volume centre.
    const auto BoxOffsets = TArray<FVector>
    {
        FVector{-700.0, -700.0, -700.0},
        FVector{ 300.0,  300.0,  100.0},
        FVector{-100.0,  500.0, -300.0}
    };

    // Well clear of every box, and inside the volume.
    const auto FreeOffsets = TArray<FVector>
    {
        FVector{ 700.0, -700.0,  700.0},
        FVector{ 100.0, -500.0, -100.0}
    };

    // Small enough that a bake of a few hundred probes cannot finish in one tick.
    constexpr int32 ProbesPerTickOverride = 16;

    static auto Get_VolumeBounds() -> FBox
    {
        return FBox{VolumeCenter - VolumeHalfExtents, VolumeCenter + VolumeHalfExtents};
    }

    static auto Make_StaticBoxParams() -> FCk_Fragment_JoltBody_ParamsData
    {
        auto Params = FCk_Fragment_JoltBody_ParamsData{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(ECk_MotionType::Static);
        return Params;
    }

    static auto Make_VolumeParams() -> FCk_Fragment_VoxelNavVolume_ParamsData
    {
        auto Params = FCk_Fragment_VoxelNavVolume_ParamsData{Get_VolumeBounds(), FinestCellSizeUu};

        // The build must start from OUR request, so its completion delegate reports the bake this test is
        // waiting on rather than one the setup processor already armed.
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        Params.Set_BuildBudgetOverride(ECk_EnableDisable::Enable);
        Params.Set_MaxOccupancyProbesPerTickOverride(ProbesPerTickOverride);

        return Params;
    }

    static auto Get_AllBodiesAdded() -> bool
    {
        if (GBoxBodies.Num() != BoxOffsets.Num())
        { return false; }

        return NOT GBoxBodies.ContainsByPredicate([](const FCk_Handle_JoltBody& InBody) -> bool
        {
            return ck::Is_NOT_Valid(InBody) || NOT UCk_Utils_JoltBody_UE::Get_IsBodyAdded(InBody);
        });
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Bake_BudgetedBakeOfStaticBoxesSpansFramesAndMatchesGeometry,
    "Ck.VoxelNav.Bake.BudgetedBakeOfStaticBoxesSpansFramesAndMatchesGeometry",
    ck_test_voxelnav_bake::kTestFlags)

bool FCkTest_VoxelNav_Bake_BudgetedBakeOfStaticBoxesSpansFramesAndMatchesGeometry::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_bake;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to voxelization — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GVolume = FCk_Handle_VoxelNavVolume{};
    GBoxBodies.Reset();
    GListener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr auto BakeTimeoutSeconds = 60.0;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Ecs = InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(Ecs))
            { AddError(TEXT("ECS world subsystem not available on the server world")); return; }

            for (const auto& BoxOffset : BoxOffsets)
            {
                auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());
                UCk_Utils_Transform_UE::Add(Entity, FTransform{VolumeCenter + BoxOffset},
                    ECk_Replication::DoesNotReplicate);

                GBoxBodies.Emplace(UCk_Utils_JoltBody_UE::Add(Entity, Make_StaticBoxParams()));
            }

            TestEqual(TEXT("every static box JoltBody composed"), GBoxBodies.Num(), BoxOffsets.Num());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return Get_AllBodiesAdded();
        }),
        BodyAddedTimeoutSeconds,
        TEXT("every static box's body was added to the Jolt world")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Ecs = InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(Ecs))
            { AddError(TEXT("ECS world subsystem not available on the server world")); return; }

            // The bake resolves its world by walking the volume's lifetime-ownership chain, and an entity
            // created straight off the registry has no lifetime owner to walk. The transient root does.
            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});

            GVolume = UCk_Utils_VoxelNavVolume_UE::Add(Owner, Make_VolumeParams());

            if (NOT TestTrue(TEXT("the VoxelNav volume composed"), ck::IsValid(GVolume)))
            { return; }

            TestFalse(TEXT("a freshly added volume has published no bake yet"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume));

            // Bound BEFORE the request, so a bake that somehow completed synchronously would still be
            // observed rather than silently missed.
            auto BuildCompleteDelegate = FCk_Delegate_VoxelNavVolume_OnBuildComplete{};
            BuildCompleteDelegate.BindDynamic(GListener.Get(),
                &UCk_VoxelNavBakeTest_Listener_UE::OnBuildComplete);

            UCk_Utils_VoxelNavVolume_UE::BindTo_OnBuildComplete(GVolume, BuildCompleteDelegate,
                ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(GListener.Get(),
                &UCk_VoxelNavBakeTest_Listener_UE::OnBuildRequestCompleted);

            UCk_Utils_VoxelNavVolume_UE::Request_Build(GVolume,
                FCk_Request_VoxelNavVolume_Build{}, CompletionDelegate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return GListener.IsValid() && GListener->_TimesRequestCompleted > 0;
        }),
        BakeTimeoutSeconds,
        TEXT("the budgeted bake ran to completion and fired its request-completion delegate")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (NOT TestTrue(TEXT("the test listener survived to the assertion"), GListener.IsValid()))
            { return false; }

            const auto CompletedExactlyOnce = TestEqual(
                TEXT("the request-completion delegate fired exactly once"),
                GListener->_TimesRequestCompleted, 1);

            const auto CompletedSucceeded = TestTrue(
                TEXT("the bake reported Succeeded to the caller that requested it"),
                GListener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

            const auto SignalFiredOnce = TestEqual(
                TEXT("the OnBuildComplete signal fired exactly once"),
                GListener->_TimesBuildCompleteFired, 1);

            const auto SignalSucceeded = TestTrue(
                TEXT("the OnBuildComplete signal carried Succeeded"),
                GListener->_LastSignalResult == ECk_SucceededFailed::Succeeded);

            return CompletedExactlyOnce && CompletedSucceeded && SignalFiredOnce && SignalSucceeded;
        }),
        TEXT("the bake completed once and reported success through both channels")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (NOT TestTrue(TEXT("the volume survived to the budget assertion"), ck::IsValid(GVolume)))
            { return false; }

            const auto Stats = UCk_Utils_VoxelNavVolume_UE::Get_BuildStats(GVolume);

            const auto SpannedFrames = TestTrue(
                TEXT("the bake respected its budget and spanned more than one frame"),
                Stats.Get_Slices() > 1);

            const auto SpentProbes = TestTrue(
                TEXT("the bake spent occupancy probes"), Stats.Get_OccupancyProbes() > 0);

            const auto FoundTheBoxes = TestTrue(
                TEXT("the whole-volume broadphase sweep found at least the three spawned boxes"),
                Stats.Get_BroadphaseBodyCount() >= BoxOffsets.Num());

            const auto OccludedLeaves = TestTrue(
                TEXT("at least one leaf per box is occluded"),
                Stats.Get_OccludedLeafCount() >= BoxOffsets.Num());

            const auto ProgressComplete = TestEqual(
                TEXT("a finished bake reports full progress"),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildProgress(GVolume), 1.0f);

            return SpannedFrames && SpentProbes && FoundTheBoxes && OccludedLeaves && ProgressComplete;
        }),
        TEXT("the bake was budgeted across frames and saw the spawned geometry")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (NOT TestTrue(TEXT("the volume survived to the occupancy assertion"), ck::IsValid(GVolume)))
            { return false; }

            const auto IsBuilt = TestTrue(TEXT("the volume published its bake"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume));

            const auto EpochBumped = TestEqual(TEXT("the first completed bake bumps the epoch to one"),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume), 1);

            const auto LayerCount = TestEqual(
                TEXT("a 1600uu volume at a 50uu finest cell bakes to four layers"),
                UCk_Utils_VoxelNavVolume_UE::Get_NumLayers(GVolume), 4);

            auto OccupiedSpotChecksHold = true;
            for (const auto& BoxOffset : BoxOffsets)
            {
                OccupiedSpotChecksHold &= TestFalse(
                    *FString::Printf(TEXT("the cell at the static box offset %s is NOT free"),
                        *BoxOffset.ToString()),
                    UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, VolumeCenter + BoxOffset));
            }

            auto FreeSpotChecksHold = true;
            for (const auto& FreeOffset : FreeOffsets)
            {
                FreeSpotChecksHold &= TestTrue(
                    *FString::Printf(TEXT("the cell at the empty offset %s is free"), *FreeOffset.ToString()),
                    UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, VolumeCenter + FreeOffset));
            }

            const auto OutsideIsNotFree = TestFalse(
                TEXT("a point outside the baked cube is not free - the bake makes no claim there"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, VolumeCenter + FVector{0.0, 0.0, 100000.0}));

            return IsBuilt && EpochBumped && LayerCount && OccupiedSpotChecksHold && FreeSpotChecksHold &&
                   OutsideIsNotFree;
        }),
        TEXT("baked occupancy matches the spawned geometry")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
