#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Fragment.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"

#include "CkVoxelNav/Occluder/CkVoxelNavOccluder_Utils.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Raycast.h"
#include "CkVoxelNav/Path/CkVoxelNavPath_Utils.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Fragment.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavBake_TestTypes.h"
#include "CkVoxelNavPath_TestTypes.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------
// The dynamic-occluder loop end-to-end in a real PIE world: bake a volume, plan a route through open air,
// move the obstacle into that route, and watch the volume repair itself locally, the old plan go stale, and
// a replan go around.
//
// What only PIE can prove is that the pieces meet: the occluder feature reading a real entity transform, the
// tracker deciding the move is worth publishing, the volume's own processors running the repair inside the
// Jolt window against LIVE physics geometry, and the epoch bump reaching a path that was planned frames
// earlier.
//
// THE OBSTACLE IS A **STATIC** JoltBody, and that is load-bearing rather than incidental. CkJolt's occupancy
// surface is filtered to the Static body domain, and a JoltBody is Static-domain only when its motion type
// is Static - so a Kinematic body is invisible to voxelization entirely, both at bake time and during a
// repair. Moving a static body is exactly what a "dynamic occluder" means to this module.
//
// The obstacle's destination is the centre of leaf (3,4,7), which lies exactly on the straight line between
// the two route endpoints - so the pre-move route (which visibility pruning reduces to that straight line)
// cannot survive the move, and a replan has to detour.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_occluder_pie
{
    // Cross-latent-command state, reset at each test start.
    static FCk_Handle_VoxelNavVolume GVolume;
    static FCk_Handle_VoxelNavPath GPath;
    static FCk_Handle_JoltBody GObstacleBody;
    static FCk_Handle_Transform GObstacleTransform;
    static FCk_Handle_VoxelNavOccluder GOccluder;
    static TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE> GBakeListener;
    static TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE> GPlanListener;
    static TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE> GReplanListener;

    static int32 GEpochAfterBake = 0;
    static float GStraightRouteLengthUu = 0.0f;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr int32 SettleFrames = 30;
    constexpr int32 GeometrySettleFrames = 10;

    constexpr auto FinestCellSizeUu = 50.0f;

    const auto VolumeCenter = FVector{0.0, 0.0, 20000.0};
    const auto VolumeHalfExtents = FVector{800.0};

    // The default JoltBody box is a 100uu cube, which sits inside a 200uu leaf with room to spare.
    const auto ObstacleHalfExtents = FVector{50.0};

    // The centre of leaf (3,4,5): directly below the route, clear of it.
    const auto ObstacleOffsetBefore = FVector{-100.0, 100.0, 300.0};

    // The centre of leaf (3,4,7) - on the straight line between the two endpoints below. Two leaves is a
    // deliberately SHORT step: the dirty region is the union of where the obstacle was and where it is, so a
    // teleport across the volume would dirty most of it and prove nothing about locality.
    const auto ObstacleOffsetAfter = FVector{-100.0, 100.0, 700.0};

    // The move spans one 400uu layer-1 column across two cells, and one 200uu leaf column across three. A
    // repair that touched more than that is not local; the bake, for comparison, sweeps all 64 layer-1 cells.
    constexpr auto MaxDirtyCellsForThisMove = 4;
    constexpr auto MaxDirtyLeavesForThisMove = 4;
    constexpr auto Layer1CellCount = 64;

    const auto RouteFromOffset = FVector{ 700.0, -700.0, 700.0};
    const auto RouteToOffset = FVector{-700.0,  700.0, 700.0};

    static auto Get_VolumeBounds() -> FBox
    {
        return FBox{VolumeCenter - VolumeHalfExtents, VolumeCenter + VolumeHalfExtents};
    }

    static auto Get_RouteFrom() -> FVector { return VolumeCenter + RouteFromOffset; }
    static auto Get_RouteTo() -> FVector { return VolumeCenter + RouteToOffset; }

    static auto Get_ObstacleBefore() -> FVector { return VolumeCenter + ObstacleOffsetBefore; }
    static auto Get_ObstacleAfter() -> FVector { return VolumeCenter + ObstacleOffsetAfter; }

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

        // The build must start from OUR request, so its completion delegate reports the bake this test waits
        // on rather than one the setup processor already armed.
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        return Params;
    }

    static auto Get_PublishedOctree() -> TSharedPtr<const ck::voxelnav::FOctree>
    {
        if (ck::Is_NOT_Valid(GVolume))
        { return {}; }

        return GVolume.Get<ck::FFragment_VoxelNavVolume_BuiltOctree>().Get_Octree();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_OccluderPie_MovedObstacleRepairsTheVolumeAndForcesAReplan,
    "Ck.VoxelNav.Occluder.Pie.MovedObstacleRepairsTheVolumeAndForcesAReplan",
    ck_test_voxelnav_occluder_pie::kTestFlags)

bool FCkTest_VoxelNav_OccluderPie_MovedObstacleRepairsTheVolumeAndForcesAReplan::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_occluder_pie;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to occluders — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GVolume = FCk_Handle_VoxelNavVolume{};
    GPath = FCk_Handle_VoxelNavPath{};
    GObstacleBody = FCk_Handle_JoltBody{};
    GObstacleTransform = FCk_Handle_Transform{};
    GOccluder = FCk_Handle_VoxelNavOccluder{};
    GEpochAfterBake = 0;
    GStraightRouteLengthUu = 0.0f;

    GBakeListener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};
    GPlanListener = TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE>{
        NewObject<UCk_VoxelNavPathTest_Listener_UE>(GetTransientPackage())};
    GReplanListener = TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE>{
        NewObject<UCk_VoxelNavPathTest_Listener_UE>(GetTransientPackage())};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr auto BakeTimeoutSeconds = 60.0;
    constexpr auto PathTimeoutSeconds = 15.0;
    constexpr auto RepairTimeoutSeconds = 30.0;
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

            auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());

            GObstacleTransform = UCk_Utils_Transform_UE::Add(Entity, FTransform{Get_ObstacleBefore()},
                ECk_Replication::DoesNotReplicate);

            GObstacleBody = UCk_Utils_JoltBody_UE::Add(Entity, Make_StaticBoxParams());

            TestTrue(TEXT("the movable obstacle composed a transform and a static Jolt body"),
                ck::IsValid(GObstacleTransform) && ck::IsValid(GObstacleBody));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GObstacleBody) && UCk_Utils_JoltBody_UE::Get_IsBodyAdded(GObstacleBody);
        }),
        BodyAddedTimeoutSeconds,
        TEXT("the obstacle's static body was added to the Jolt world")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            // The bake resolves its world by walking the volume's lifetime-ownership chain, and an entity
            // created straight off the registry has no lifetime owner to walk. The transient root does.
            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});

            GVolume = UCk_Utils_VoxelNavVolume_UE::Add(Owner, Make_VolumeParams());

            if (NOT TestTrue(TEXT("the VoxelNav volume composed"), ck::IsValid(GVolume)))
            { return; }

            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(GBakeListener.Get(),
                &UCk_VoxelNavBakeTest_Listener_UE::OnBuildRequestCompleted);

            UCk_Utils_VoxelNavVolume_UE::Request_Build(GVolume,
                FCk_Request_VoxelNavVolume_Build{}, CompletionDelegate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return GBakeListener.IsValid() && GBakeListener->_TimesRequestCompleted > 0;
        }),
        BakeTimeoutSeconds,
        TEXT("the bake ran to completion and fired its request-completion delegate")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT TestTrue(TEXT("the volume published its bake"),
                ck::IsValid(GVolume) && UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume)))
            { return; }

            GEpochAfterBake = UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume);

            TestTrue(TEXT("the obstacle's starting cell is blocked by the bake"),
                NOT UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_ObstacleBefore()));
            TestTrue(TEXT("the cell it will move into is open space before it moves"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_ObstacleAfter()));

            // Composed AFTER the bake on purpose: the tracker seeds itself from the pose the bake already
            // saw, so nothing is dirtied until the obstacle actually moves.
            auto ObstacleEntity = GObstacleTransform.ConvertToHandle();

            GOccluder = UCk_Utils_VoxelNavOccluder_UE::Add(ObstacleEntity,
                FCk_Fragment_VoxelNavOccluder_ParamsData{ObstacleHalfExtents});

            TestTrue(TEXT("the occluder feature composed onto the obstacle entity itself"),
                ck::IsValid(GOccluder) && UCk_Utils_VoxelNavOccluder_UE::Has(ObstacleEntity));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(GeometrySettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            TestEqual(TEXT("an occluder that has not moved dirties nothing"),
                UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(GOccluder), 0);
            TestEqual(TEXT("and the volume has not rebuilt behind the bake"),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume), GEpochAfterBake);

            auto Agent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});

            GPath = UCk_Utils_VoxelNavPath_UE::Add(Agent, FCk_Fragment_VoxelNavPath_ParamsData{});

            if (NOT TestTrue(TEXT("the path feature composed onto the agent"), ck::IsValid(GPath)))
            { return; }

            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(GPlanListener.Get(),
                &UCk_VoxelNavPathTest_Listener_UE::OnFindPathCompleted);

            UCk_Utils_VoxelNavPath_UE::Request_FindPath(GPath,
                FCk_Request_VoxelNavPath_FindPath{GVolume, Get_RouteFrom(), Get_RouteTo()},
                CompletionDelegate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return GPlanListener.IsValid() && GPlanListener->_TimesRequestCompleted > 0;
        }),
        PathTimeoutSeconds,
        TEXT("the pre-move path request was drained and reported back")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Planned = TestTrue(TEXT("the pre-move route was found"),
                GPlanListener->_LastRequestResult == ECk_Request_OperationResult::Succeeded &&
                UCk_Utils_VoxelNavPath_UE::Get_Status(GPath) == ECk_VoxelNav_PathStatus::Ready);

            GStraightRouteLengthUu = UCk_Utils_VoxelNavPath_UE::Get_PathLengthUu(GPath);

            const auto PlannedAgainstTheBake = TestEqual(
                TEXT("the pre-move route planned against the bake's epoch"),
                UCk_Utils_VoxelNavPath_UE::Get_PlannedAgainstEpoch(GPath), GEpochAfterBake);

            const auto Octree = Get_PublishedOctree();

            if (NOT TestTrue(TEXT("the volume's published octree is readable"),
                Octree.IsValid() && Octree->Get_IsValid()))
            { return false; }

            // The obstacle's destination sits ON this segment, so this is the line the move has to break.
            const auto DirectLineIsOpen = TestTrue(
                TEXT("the straight line between the endpoints is clear before the obstacle moves"),
                NOT ck::voxelnav::Get_IsSegmentBlocked(*Octree, Get_RouteFrom(), Get_RouteTo()));

            return Planned && PlannedAgainstTheBake && DirectLineIsOpen;
        }),
        TEXT("the pre-move route runs straight through the space the obstacle is about to occupy")));

    // The body moves FIRST and the world is ticked before the entity's transform follows, so the repair that
    // the transform move triggers cannot race the physics update it has to read.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            UCk_Utils_JoltBody_UE::Request_Teleport(GObstacleBody,
                FCk_Request_JoltBody_Teleport{Get_ObstacleAfter(), FRotator::ZeroRotator}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(GeometrySettleFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            UCk_Utils_Transform_UE::Request_SetLocation(GObstacleTransform,
                FCk_Request_Transform_SetLocation{Get_ObstacleAfter()}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GVolume) &&
                   UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume) > GEpochAfterBake;
        }),
        RepairTimeoutSeconds,
        TEXT("the moved occluder dirtied the volume and its local repair published a new octree")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Dirtied = TestTrue(TEXT("the occluder noticed the move and dirtied the volume"),
                UCk_Utils_VoxelNavOccluder_UE::Get_TimesDirtied(GOccluder) >= 1);

            const auto EpochBumped = TestEqual(
                TEXT("one completed repair bumps the epoch exactly once past the bake"),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume), GEpochAfterBake + 1);

            const auto RepairStats = UCk_Utils_VoxelNavVolume_UE::Get_RepairStats(GVolume);

            const auto RepairDidWork = TestTrue(TEXT("the repair probed the dirty region and changed leaves"),
                RepairStats.Get_DirtyCellsProbed() > 0 && RepairStats.Get_LeavesChanged() > 0);

            // The local-repair contract as a number in a live world. Probe COUNTS are pinned exactly by the
            // hermetic tests; what PIE adds is that the region really is derived from the obstacle's own
            // movement - a bake has to sweep all 64 layer-1 cells, and this repair touches a handful.
            const auto RepairIsLocal = TestTrue(
                TEXT("the repair probed a handful of cells rather than sweeping the layer-1 lattice the bake "
                     "had to"),
                RepairStats.Get_DirtyCellsProbed() <= MaxDirtyCellsForThisMove &&
                RepairStats.Get_DirtyLeavesProbed() <= MaxDirtyLeavesForThisMove &&
                RepairStats.Get_DirtyCellsProbed() < Layer1CellCount);

            const auto DirtyRegionConsumed = TestFalse(
                TEXT("the dirty region is consumed by the repair that answered it"),
                UCk_Utils_VoxelNavVolume_UE::Get_PendingDirtyBounds(GVolume).IsValid != 0);

            return Dirtied && EpochBumped && RepairDidWork && RepairIsLocal && DirtyRegionConsumed;
        }),
        TEXT("the repair ran locally, changed leaves and published exactly one new epoch")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto SpaceFreed = TestTrue(
                TEXT("the space the obstacle left is navigable again - not a residual trail of it"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_ObstacleBefore()));

            const auto SpaceBlocked = TestFalse(
                TEXT("the space the obstacle moved into is blocked"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_ObstacleAfter()));

            const auto Octree = Get_PublishedOctree();

            if (NOT TestTrue(TEXT("the repaired octree is readable"),
                Octree.IsValid() && Octree->Get_IsValid()))
            { return false; }

            const auto DirectLineIsBlocked = TestTrue(
                TEXT("the straight line the pre-move route took is now blocked by the repaired bake"),
                ck::voxelnav::Get_IsSegmentBlocked(*Octree, Get_RouteFrom(), Get_RouteTo()));

            // Staleness is DERIVED from the epoch drift, so a repair never has to find the paths that
            // planned against it - this is that mechanism working across a real frame gap.
            const auto PlanWentStale = TestTrue(
                TEXT("the route planned before the move now reads Stale"),
                UCk_Utils_VoxelNavPath_UE::Get_IsStale(GPath) &&
                UCk_Utils_VoxelNavPath_UE::Get_Status(GPath) == ECk_VoxelNav_PathStatus::Stale);

            return SpaceFreed && SpaceBlocked && DirectLineIsBlocked && PlanWentStale;
        }),
        TEXT("occupancy followed the obstacle and the old plan reads stale")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(GReplanListener.Get(),
                &UCk_VoxelNavPathTest_Listener_UE::OnFindPathCompleted);

            UCk_Utils_VoxelNavPath_UE::Request_FindPath(GPath,
                FCk_Request_VoxelNavPath_FindPath{GVolume, Get_RouteFrom(), Get_RouteTo()},
                CompletionDelegate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return GReplanListener.IsValid() && GReplanListener->_TimesRequestCompleted > 0;
        }),
        PathTimeoutSeconds,
        TEXT("the replan was drained and reported back")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Replanned = TestTrue(TEXT("the replan succeeded against the repaired volume"),
                GReplanListener->_LastRequestResult == ECk_Request_OperationResult::Succeeded &&
                UCk_Utils_VoxelNavPath_UE::Get_Status(GPath) == ECk_VoxelNav_PathStatus::Ready);

            const auto ReplannedAgainstTheRepair = TestEqual(
                TEXT("the replan planned against the repaired epoch, so it reads fresh again"),
                UCk_Utils_VoxelNavPath_UE::Get_PlannedAgainstEpoch(GPath),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume));

            const auto Waypoints = UCk_Utils_VoxelNavPath_UE::Get_Waypoints(GPath);

            if (NOT TestTrue(TEXT("the replanned route holds at least its endpoints"), Waypoints.Num() >= 2))
            { return false; }

            const auto Octree = Get_PublishedOctree();

            if (NOT TestTrue(TEXT("the repaired octree is readable"),
                Octree.IsValid() && Octree->Get_IsValid()))
            { return false; }

            auto EverySegmentIsClear = true;
            for (auto WaypointIdx = 1; WaypointIdx < Waypoints.Num(); ++WaypointIdx)
            {
                EverySegmentIsClear &= NOT ck::voxelnav::Get_IsSegmentBlocked(
                    *Octree, Waypoints[WaypointIdx - 1], Waypoints[WaypointIdx]);
            }

            const auto RouteAvoidsTheObstacle = TestTrue(
                TEXT("every segment of the replanned route is clear against the repaired bake"),
                EverySegmentIsClear);

            // The obstacle stands on the straight line, so any route that gets past it is longer than one.
            const auto RouteDetours = TestTrue(
                TEXT("the replanned route is longer than the straight line the obstacle now blocks"),
                UCk_Utils_VoxelNavPath_UE::Get_PathLengthUu(GPath) > GStraightRouteLengthUu);

            return Replanned && ReplannedAgainstTheRepair && RouteAvoidsTheObstacle && RouteDetours;
        }),
        TEXT("the replanned route goes around the obstacle's new position")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
