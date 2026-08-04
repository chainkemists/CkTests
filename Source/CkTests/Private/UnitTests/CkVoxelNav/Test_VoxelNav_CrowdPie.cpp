#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Fragment.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"

#include "CkNavigation/Utils/CkNav_Utils.h"

#include "CkVoxelNav/Occluder/CkVoxelNavOccluder_Utils.h"
#include "CkVoxelNav/Path/CkVoxelNavPath_Utils.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavBake_TestTypes.h"
#include "CkVoxelNavPath_TestTypes.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------
// The crowd integration end-to-end: a crowd agent that owns the VoxelNavPath feature and a bound volume must
// receive its route through FFragment_Nav_PathResult — the provider-agnostic seam every downstream crowd
// processor reads — exactly as a PathNetwork follower or a plain CkNavigation agent does.
//
// The assertion is deliberately made on the SEAM rather than on the VoxelNavPath fragment: what this test
// proves is that MoveTo selected the volumetric provider, that the search answered, and that the answer was
// installed where Steering will find it. The path's own quality is the PathPie test's subject.
//
// The scene is the bake/path tests', deliberately: the same three static JoltBody boxes at the same leaf
// centres, far above the map's own geometry, with endpoints in two layer-2 cells no box touches.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_crowd_pie
{
    // Cross-latent-command state, reset at each test start.
    static FCk_Handle_VoxelNavVolume GVolume;
    static FCk_Handle_CrowdAgent GAgent;
    static FCk_Handle_VoxelNavPath GAgentPath;
    static TArray<FCk_Handle_JoltBody> GBoxBodies;
    static TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE> GBakeListener;
    static TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE> GReplanListener;

    static FCk_Handle_JoltBody GObstacleBody;
    static FCk_Handle_Transform GObstacleTransform;
    static FCk_Handle_VoxelNavOccluder GOccluder;
    static int32 GEpochAfterBake = 0;

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

    const auto RouteFromOffset = FVector{ 700.0, -700.0, 700.0};
    const auto RouteToOffset = FVector{-700.0,  700.0, 700.0};

    // The occluder of the stale-epoch test. Its destination sits ON the straight line between the two route
    // endpoints (Y = -X at constant Z), so the repair genuinely invalidates the installed route rather than
    // merely bumping a counter beside it. Geometry and step size are the Occluder PIE test's, verbatim.
    const auto ObstacleHalfExtents = FVector{50.0};
    const auto ObstacleOffsetBefore = FVector{-100.0, 100.0, 300.0};
    const auto ObstacleOffsetAfter = FVector{-100.0, 100.0, 700.0};

    // The installed waypoints carry the planned endpoints verbatim, so anything above float noise is a
    // real drift.
    constexpr auto EndpointToleranceUu = 1.0;

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

        // The build must start from OUR request, so its completion delegate reports the bake this test
        // waits on rather than one the setup processor already armed.
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
    FCkTest_VoxelNav_CrowdPie_AgentReceivesItsRouteThroughTheNavPathSeam,
    "Ck.VoxelNav.Crowd.Pie.AgentReceivesItsRouteThroughTheNavPathSeam",
    ck_test_voxelnav_crowd_pie::kTestFlags)

bool FCkTest_VoxelNav_CrowdPie_AgentReceivesItsRouteThroughTheNavPathSeam::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_crowd_pie;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to pathfinding — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GVolume = FCk_Handle_VoxelNavVolume{};
    GAgent = FCk_Handle_CrowdAgent{};
    GBoxBodies.Reset();
    GBakeListener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr auto BakeTimeoutSeconds = 60.0;
    constexpr auto RouteTimeoutSeconds = 15.0;
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
            if (NOT TestTrue(TEXT("the volume published its bake before the agent was moved"),
                ck::IsValid(GVolume) && UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume)))
            { return; }

            auto AgentEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});
            auto AgentTransform = UCk_Utils_Transform_UE::Add(AgentEntity, FTransform{Get_RouteFrom()},
                ECk_Replication::DoesNotReplicate);

            constexpr auto AgentRadiusUu = 42.0f;
            constexpr auto AgentHeightUu = 192.0f;
            GAgent = UCk_Utils_CrowdAgent_UE::Add(AgentTransform,
                FCk_Fragment_CrowdAgent_ParamsData{AgentRadiusUu, AgentHeightUu});

            if (NOT TestTrue(TEXT("the crowd agent composed"), ck::IsValid(GAgent)))
            { return; }

            auto AgentHandle = GAgent.ConvertToHandle();
            auto Path = UCk_Utils_VoxelNavPath_UE::Add(AgentHandle,
                FCk_Fragment_VoxelNavPath_ParamsData{AgentRadiusUu});

            if (NOT TestTrue(TEXT("the volumetric path feature composed onto the same agent entity"),
                ck::IsValid(Path)))
            { return; }

            // Binding the volume is what makes MoveTo choose the volumetric provider — without it the
            // agent falls through to CkNavigation exactly as it did before this integration existed.
            UCk_Utils_VoxelNavPath_UE::Request_SetVolume(Path, GVolume, {});

            UCk_Utils_CrowdAgent_UE::Request_MoveTo(GAgent,
                FCk_Request_CrowdAgent_MoveTo{Get_RouteTo()}, {});
        })));

    // Walking is one processor pass behind Ready — the install parks a Ready result in the seam and
    // OnPathResolved normalizes the agent onto it, exactly as it does for every other provider.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GAgent) &&
                UCk_Utils_Nav_UE::Get_PathStatus(GAgent) == ECk_Nav_PathStatus::Ready &&
                GAgent.Has<ck::FTag_CrowdAgent_Walking>();
        }),
        RouteTimeoutSeconds,
        TEXT("the agent walks the route the volumetric provider installed into its nav-path slot")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto PathResult = UCk_Utils_Nav_UE::Get_PathResult(GAgent);

            const auto SeamReportsReady = TestTrue(
                TEXT("the provider-agnostic seam reports Ready"),
                PathResult.Get_Status() == ECk_Nav_PathStatus::Ready);

            const auto& Waypoints = PathResult.Get_Waypoints();

            if (NOT TestTrue(TEXT("the installed route holds at least the two endpoints"),
                Waypoints.Num() >= 2))
            { return false; }

            const auto StartsAtTheAgent = TestTrue(
                TEXT("the installed route starts where the agent stood when it was told to move"),
                FVector::Dist(Waypoints[0], Get_RouteFrom()) < EndpointToleranceUu);

            const auto EndsAtTheGoal = TestTrue(
                TEXT("the installed route ends at the goal the MoveTo asked for"),
                FVector::Dist(Waypoints.Last(), Get_RouteTo()) < EndpointToleranceUu);

            const auto DestinationIsTheGoal = TestTrue(
                TEXT("the seam records the MoveTo goal as the path destination"),
                FVector::Dist(PathResult.Get_DestinationLocation(), Get_RouteTo()) < EndpointToleranceUu);

            // The install has to drive the agent's own state machine too, or nothing downstream steers.
            const auto AgentIsWalking = TestTrue(
                TEXT("the agent left PathPending for Walking on the installed route"),
                GAgent.Has<ck::FTag_CrowdAgent_Walking>() && NOT GAgent.Has<ck::FTag_CrowdAgent_PathPending>());

            return SeamReportsReady && StartsAtTheAgent && EndsAtTheGoal && DestinationIsTheGoal &&
                   AgentIsWalking;
        }),
        TEXT("the volumetric route reached the crowd agent through the nav-path seam")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// The stale-epoch auto-replan. A repair bumps the volume's epoch underneath an agent that is already walking,
// and the resolver's install dedupe — correctly — refuses to re-install the pre-repair result the agent still
// holds. Without a re-request that is a silent dead end: the agent walks a route planned through space that
// may no longer be free, and nothing ever asks again.
//
// EXACTLY ONCE is the whole contract. A per-frame poll of "is my epoch stale" would re-request every frame
// until an answer landed, so the test counts OnPathReady fires rather than merely observing that one replan
// happened, and keeps ticking afterwards to catch a second.
//
// The agent deliberately owns no locomotion (no Velocity, no integrator), exactly as the sibling test above:
// the resolver keys on the Walking TAG, and an agent that cannot arrive cannot leave that state while the
// asynchronous repair lands. Real 3D locomotion is the flying test's subject.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_CrowdPie_StaleVolumeEpochReplansTheWalkingAgentExactlyOnce,
    "Ck.VoxelNav.Crowd.Pie.StaleVolumeEpochReplansTheWalkingAgentExactlyOnce",
    ck_test_voxelnav_crowd_pie::kTestFlags)

bool FCkTest_VoxelNav_CrowdPie_StaleVolumeEpochReplansTheWalkingAgentExactlyOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_crowd_pie;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to pathfinding — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GVolume = FCk_Handle_VoxelNavVolume{};
    GAgent = FCk_Handle_CrowdAgent{};
    GAgentPath = FCk_Handle_VoxelNavPath{};
    GObstacleBody = FCk_Handle_JoltBody{};
    GObstacleTransform = FCk_Handle_Transform{};
    GOccluder = FCk_Handle_VoxelNavOccluder{};
    GEpochAfterBake = 0;
    GBoxBodies.Reset();
    GBakeListener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};
    GReplanListener = TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE>{
        NewObject<UCk_VoxelNavPathTest_Listener_UE>(GetTransientPackage())};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr auto BakeTimeoutSeconds = 60.0;
    constexpr auto RouteTimeoutSeconds = 15.0;
    constexpr auto RepairTimeoutSeconds = 30.0;
    constexpr auto ReplanTimeoutSeconds = 15.0;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;
    constexpr int32 GeometrySettleFrames = 10;

    // Long enough that a per-frame re-request would show up as a double-digit count, not a second fire.
    constexpr int32 SecondReplanWatchFrames = 60;

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

            auto ObstacleEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());
            GObstacleTransform = UCk_Utils_Transform_UE::Add(ObstacleEntity,
                FTransform{Get_ObstacleBefore()}, ECk_Replication::DoesNotReplicate);
            GObstacleBody = UCk_Utils_JoltBody_UE::Add(ObstacleEntity, Make_StaticBoxParams());

            TestTrue(TEXT("the movable obstacle composed a transform and a static Jolt body"),
                ck::IsValid(GObstacleTransform) && ck::IsValid(GObstacleBody));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return Get_AllBodiesAdded() && ck::IsValid(GObstacleBody) &&
                UCk_Utils_JoltBody_UE::Get_IsBodyAdded(GObstacleBody);
        }),
        BodyAddedTimeoutSeconds,
        TEXT("every static body, the obstacle's included, was added to the Jolt world")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
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
            if (NOT TestTrue(TEXT("the volume published its bake before the agent was moved"),
                ck::IsValid(GVolume) && UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume)))
            { return; }

            GEpochAfterBake = UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume);

            // Composed AFTER the bake: the tracker seeds itself from the pose the bake already saw, so
            // nothing is dirtied until the obstacle actually moves.
            auto ObstacleEntity = GObstacleTransform.ConvertToHandle();
            GOccluder = UCk_Utils_VoxelNavOccluder_UE::Add(ObstacleEntity,
                FCk_Fragment_VoxelNavOccluder_ParamsData{ObstacleHalfExtents});

            if (NOT TestTrue(TEXT("the occluder feature composed onto the obstacle entity"),
                ck::IsValid(GOccluder)))
            { return; }

            auto AgentEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});
            auto AgentTransform = UCk_Utils_Transform_UE::Add(AgentEntity, FTransform{Get_RouteFrom()},
                ECk_Replication::DoesNotReplicate);

            constexpr auto AgentRadiusUu = 42.0f;
            constexpr auto AgentHeightUu = 192.0f;
            GAgent = UCk_Utils_CrowdAgent_UE::Add(AgentTransform,
                FCk_Fragment_CrowdAgent_ParamsData{AgentRadiusUu, AgentHeightUu});

            auto AgentHandle = GAgent.ConvertToHandle();
            GAgentPath = UCk_Utils_VoxelNavPath_UE::Add(AgentHandle,
                FCk_Fragment_VoxelNavPath_ParamsData{AgentRadiusUu});

            if (NOT TestTrue(TEXT("the crowd agent and its volumetric path feature composed"),
                ck::IsValid(GAgent) && ck::IsValid(GAgentPath)))
            { return; }

            UCk_Utils_VoxelNavPath_UE::Request_SetVolume(GAgentPath, GVolume, {});

            UCk_Utils_CrowdAgent_UE::Request_MoveTo(GAgent,
                FCk_Request_CrowdAgent_MoveTo{Get_RouteTo()}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GAgent) && GAgent.Has<ck::FTag_CrowdAgent_Walking>();
        }),
        RouteTimeoutSeconds,
        TEXT("the agent walks the route the volumetric provider installed into its nav-path slot")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            TestEqual(TEXT("the walked route was planned against the bake's epoch"),
                UCk_Utils_VoxelNavPath_UE::Get_PlannedAgainstEpoch(GAgentPath), GEpochAfterBake);

            // IgnorePayloadInFlight: the MoveTo's own answer already fired, and replaying it would be
            // counted as the replan this test is looking for.
            auto ReadyDelegate = FCk_Delegate_VoxelNavPath_OnPathReady{};
            ReadyDelegate.BindDynamic(GReplanListener.Get(),
                &UCk_VoxelNavPathTest_Listener_UE::OnPathReady);

            UCk_Utils_VoxelNavPath_UE::BindTo_OnPathReady(GAgentPath, ReadyDelegate,
                ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
                ECk_Signal_PostFireBehavior::DoNothing);

            // The body moves first and the world is ticked before the entity's transform follows, so the
            // repair the transform move triggers cannot race the physics update it has to read.
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
        TEXT("the moved occluder dirtied the volume and its local repair published a new epoch")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GAgentPath) && ck::IsValid(GVolume) &&
                UCk_Utils_VoxelNavPath_UE::Get_PlannedAgainstEpoch(GAgentPath) ==
                    UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume);
        }),
        ReplanTimeoutSeconds,
        TEXT("the resolver noticed the drift on its own and the replan it issued answered against the "
             "repaired volume")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SecondReplanWatchFrames));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto ReplannedOnce = TestEqual(
                TEXT("the epoch drift was answered by EXACTLY one replan, and the settled state does not "
                     "keep re-requesting"),
                GReplanListener->_TimesPathReadyFired, 1);

            const auto StillWalking = TestTrue(
                TEXT("the agent kept walking across the replan rather than being dropped to Idle"),
                GAgent.Has<ck::FTag_CrowdAgent_Walking>());

            const auto SeamIsReady = TestTrue(
                TEXT("the replanned route was installed through the provider-agnostic seam"),
                UCk_Utils_Nav_UE::Get_PathStatus(GAgent) == ECk_Nav_PathStatus::Ready);

            const auto InstalledIsFresh = TestEqual(
                TEXT("and the agent's installed-route identity now names the repaired epoch, which is what "
                     "stops the next tick asking again"),
                GAgent.Get<ck::FFragment_CrowdAgent_InstalledVoxelPath>().Get_VolumeEpoch(),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume));

            return ReplannedOnce && StillWalking && SeamIsReady && InstalledIsFresh;
        }),
        TEXT("a repair-driven epoch bump replans the walking agent exactly once")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
