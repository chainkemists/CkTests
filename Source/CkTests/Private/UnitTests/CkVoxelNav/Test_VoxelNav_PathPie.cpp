#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Fragment.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"

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
// The success path end-to-end in a real PIE world: bake the three-box scene, compose the path feature onto an
// agent, ask for a route across the volume, and hold the answer to the same standard the bake is held to.
//
// This is the counterpart of the hermetic path tests, which drive the search seam directly over a
// hand-authored octree. What only PIE can prove is that the pieces meet: a bake published by the volume's own
// processors, a request drained by the globally registered path processor, and waypoints that are collision
// free against the octree that bake produced.
//
// The scene is the bake test's, deliberately: the same three static JoltBody boxes at the same leaf centres,
// far above the map's own geometry. The endpoints sit in the two layer-2 cells no box touches, so the route
// has to cross the volume rather than sit inside one cell.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_path_pie
{
    // Cross-latent-command state, reset at each test start.
    static FCk_Handle_VoxelNavVolume GVolume;
    static FCk_Handle_VoxelNavPath GPath;
    static TArray<FCk_Handle_JoltBody> GBoxBodies;
    static TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE> GBakeListener;
    static TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE> GPathListener;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr int32 SettleFrames = 30;

    constexpr auto FinestCellSizeUu = 50.0f;

    const auto VolumeCenter = FVector{0.0, 0.0, 20000.0};
    const auto VolumeHalfExtents = FVector{800.0};

    const auto BoxOffsets = TArray<FVector>
    {
        FVector{-700.0, -700.0, -700.0},
        FVector{ 300.0,  300.0,  100.0},
        FVector{-100.0,  500.0, -300.0}
    };

    // Opposite corners of the volume's upper half, each in a layer-2 cell no box subdivided. They differ in
    // two axes, so no single face step connects them.
    const auto RouteFromOffset = FVector{ 700.0, -700.0, 700.0};
    const auto RouteToOffset = FVector{-700.0,  700.0, 700.0};

    // The waypoints carry the requested endpoints verbatim, so anything above float noise is a real drift.
    constexpr auto EndpointToleranceUu = 1.0;

    static auto Get_VolumeBounds() -> FBox
    {
        return FBox{VolumeCenter - VolumeHalfExtents, VolumeCenter + VolumeHalfExtents};
    }

    static auto Get_RouteFrom() -> FVector { return VolumeCenter + RouteFromOffset; }
    static auto Get_RouteTo() -> FVector { return VolumeCenter + RouteToOffset; }

    static auto Make_StaticBoxParams() -> FCk_JoltBody_Spec
    {
        auto Params = FCk_JoltBody_Spec{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(ECk_MotionType::Static);
        return Params;
    }

    static auto Make_VolumeParams() -> FCk_VoxelNavVolume_Spec
    {
        auto Params = FCk_VoxelNavVolume_Spec{Get_VolumeBounds(), FinestCellSizeUu};

        // The build must start from OUR request, so its completion delegate reports the bake this test waits
        // on rather than one the setup processor already armed.
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

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
    FCkTest_VoxelNav_PathPie_PlansACollisionFreeRouteAcrossTheBakedScene,
    "Ck.VoxelNav.Path.Pie.PlansACollisionFreeRouteAcrossTheBakedScene",
    ck_test_voxelnav_path_pie::kTestFlags)

bool FCkTest_VoxelNav_PathPie_PlansACollisionFreeRouteAcrossTheBakedScene::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_path_pie;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to pathfinding — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GVolume = FCk_Handle_VoxelNavVolume{};
    GPath = FCk_Handle_VoxelNavPath{};
    GBoxBodies.Reset();
    GBakeListener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};
    GPathListener = TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE>{
        NewObject<UCk_VoxelNavPathTest_Listener_UE>(GetTransientPackage())};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr auto BakeTimeoutSeconds = 60.0;
    constexpr auto PathTimeoutSeconds = 15.0;
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
            if (NOT TestTrue(TEXT("the volume published its bake before the route was asked for"),
                ck::IsValid(GVolume) && UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume)))
            { return; }

            // Both endpoints have to be navigable for a route between them to mean anything - a failure here
            // is a fixture problem, not a pathfinding one.
            const auto EndpointsAreFree =
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_RouteFrom()) &&
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_RouteTo());

            if (NOT TestTrue(TEXT("both requested endpoints stand in baked free space"), EndpointsAreFree))
            { return; }

            auto Agent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});

            GPath = UCk_Utils_VoxelNavPath_UE::Add(Agent, FCk_VoxelNavPath_Spec{});

            if (NOT TestTrue(TEXT("the path feature composed onto the agent"), ck::IsValid(GPath)))
            { return; }

            // Bound BEFORE the request, so a search that somehow answered synchronously would still be
            // observed rather than silently missed.
            auto ReadyDelegate = FCk_Delegate_VoxelNavPath_OnPathReady{};
            ReadyDelegate.BindDynamic(GPathListener.Get(), &UCk_VoxelNavPathTest_Listener_UE::OnPathReady);

            UCk_Utils_VoxelNavPath_UE::BindTo_OnPathReady(GPath, ReadyDelegate,
                ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

            auto FailedDelegate = FCk_Delegate_VoxelNavPath_OnPathFailed{};
            FailedDelegate.BindDynamic(GPathListener.Get(), &UCk_VoxelNavPathTest_Listener_UE::OnPathFailed);

            UCk_Utils_VoxelNavPath_UE::BindTo_OnPathFailed(GPath, FailedDelegate,
                ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(GPathListener.Get(),
                &UCk_VoxelNavPathTest_Listener_UE::OnFindPathCompleted);

            UCk_Utils_VoxelNavPath_UE::Request_FindPath(GPath,
                FCk_Request_VoxelNavPath_FindPath{GVolume, Get_RouteFrom(), Get_RouteTo()},
                CompletionDelegate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return GPathListener.IsValid() && GPathListener->_TimesRequestCompleted > 0;
        }),
        PathTimeoutSeconds,
        TEXT("the path request was drained and reported back to its caller")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (NOT TestTrue(TEXT("the test listener survived to the assertion"), GPathListener.IsValid()))
            { return false; }

            const auto CompletedExactlyOnce = TestEqual(
                TEXT("the request-completion delegate fired exactly once"),
                GPathListener->_TimesRequestCompleted, 1);

            const auto CompletedSucceeded = TestTrue(
                TEXT("the search reported Succeeded to the caller that requested it"),
                GPathListener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

            const auto ReadyFiredOnce = TestEqual(TEXT("OnPathReady fired exactly once"),
                GPathListener->_TimesPathReadyFired, 1);

            const auto FailedNeverFired = TestEqual(TEXT("OnPathFailed does not fire"),
                GPathListener->_TimesPathFailedFired, 0);

            const auto StatusIsReady = TestTrue(TEXT("the path reports Ready against the bake it planned on"),
                UCk_Utils_VoxelNavPath_UE::Get_Status(GPath) == ECk_VoxelNav_PathStatus::Ready);

            return CompletedExactlyOnce && CompletedSucceeded && ReadyFiredOnce && FailedNeverFired &&
                   StatusIsReady;
        }),
        TEXT("the search succeeded once and reported success through both channels")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto Waypoints = UCk_Utils_VoxelNavPath_UE::Get_Waypoints(GPath);

            if (NOT TestTrue(TEXT("a Ready path holds at least the two requested endpoints"),
                Waypoints.Num() >= 2))
            { return false; }

            const auto StartsWhereAsked = TestTrue(
                TEXT("the route starts at the requested From position"),
                FVector::Dist(Waypoints[0], Get_RouteFrom()) < EndpointToleranceUu);

            const auto EndsWhereAsked = TestTrue(
                TEXT("the route ends at the requested To position"),
                FVector::Dist(Waypoints.Last(), Get_RouteTo()) < EndpointToleranceUu);

            // The bake the search planned against is the only structure entitled to answer this: asking
            // physics instead would validate a route against geometry the search never saw.
            const auto& BuiltOctree = GVolume.Get<ck::FFragment_VoxelNavVolume_BuiltOctree>();
            const auto Octree = BuiltOctree.Get_Octree();

            if (NOT TestTrue(TEXT("the volume's published octree is readable"),
                Octree.IsValid() && Octree->Get_IsValid()))
            { return false; }

            auto EverySegmentIsClear = true;
            for (auto WaypointIdx = 1; WaypointIdx < Waypoints.Num(); ++WaypointIdx)
            {
                EverySegmentIsClear &= NOT ck::voxelnav::Get_IsSegmentBlocked(
                    *Octree, Waypoints[WaypointIdx - 1], Waypoints[WaypointIdx]);
            }

            const auto RouteIsCollisionFree = TestTrue(
                TEXT("every consecutive segment of the route is clear against the bake"), EverySegmentIsClear);

            const auto PlannedAgainstTheLiveBake = TestEqual(
                TEXT("the path planned against the volume's current build epoch"),
                UCk_Utils_VoxelNavPath_UE::Get_PlannedAgainstEpoch(GPath),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume));

            return StartsWhereAsked && EndsWhereAsked && RouteIsCollisionFree && PlannedAgainstTheLiveBake;
        }),
        TEXT("the planned route is collision free against the bake it was planned through")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            // Refinement is on by default, so the stored path is the refined one and the raw count is the
            // only surviving trace of what the search actually produced.
            const auto RawCount = UCk_Utils_VoxelNavPath_UE::Get_RawWaypointCount(GPath);
            const auto RefinedCount = UCk_Utils_VoxelNavPath_UE::Get_RefinedWaypointCount(GPath);

            const auto RawCountRecorded = TestTrue(
                TEXT("the search's own waypoint count is recorded"), RawCount >= 2);

            const auto RefinementNeverGrowsThePath = TestTrue(
                TEXT("the default refinement never adds waypoints"), RefinedCount <= RawCount);

            const auto CountMatchesTheStoredPath = TestEqual(
                TEXT("the reported refined count is the stored waypoint count"),
                RefinedCount, UCk_Utils_VoxelNavPath_UE::Get_Waypoints(GPath).Num());

            const auto LengthRecorded = TestTrue(TEXT("the stored path has a recorded length"),
                UCk_Utils_VoxelNavPath_UE::Get_PathLengthUu(GPath) > 0.0f);

            return RawCountRecorded && RefinementNeverGrowsThePath && CountMatchesTheStoredPath &&
                   LengthRecorded;
        }),
        TEXT("the refinement stats describe the path the caller reads")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
