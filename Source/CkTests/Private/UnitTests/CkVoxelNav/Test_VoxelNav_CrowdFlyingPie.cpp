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

#include "CkPhysics/Acceleration/CkAcceleration_Utils.h"
#include "CkPhysics/EulerIntegrator/CkEulerIntegrator_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Utils.h"

#include "CkVoxelNav/Path/CkVoxelNavPath_Utils.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavBake_TestTypes.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

// --------------------------------------------------------------------------------------------------------------------
// Flying-agent enablement, end to end in PIE: an agent composed with _AgentMode = Flying opts out of every
// surface-bound and planar stage of the crowd pipeline by tag, and must still MOVE — the navmesh constraint
// it now skips was the sole consumer of the staged per-frame displacement, so its replacement carrying the
// full 3D offset is what this test is really pinning.
//
// The route CLIMBS: it runs from a low corner of the baked volume to the opposite high one, so an agent that
// followed it in XY while its Z was substituted from somewhere else would miss the polyline by ~1400uu.
//
// A GROUNDED agent flies the same route beside it as the control. Note what that control can and cannot say
// here: /Engine/Maps/Entry has no nav data anywhere near Z=20000, so ConstrainToNavmesh passes displacement
// through untouched (its documented nav-less behavior) and the grounded agent is NOT held down — the
// discriminator this world can prove is which FACING processor owns each agent, since the yaw-only one leaves
// pitch at zero forever and the 3D one tracks the climb. That a grounded agent is still surface-clamped where
// a navmesh exists is the crowd suite's own subject and the flying gym's [EDITOR-VERIFY] step.
//
// The scene is the bake/path/crowd tests', deliberately: the same three static JoltBody boxes at the same
// leaf centres, far above the map's own geometry.
//
// Tracking is asserted as DIRECTION-of-travel against the route's goal rather than as distance to the
// installed polyline, and that is not a softening. On this route the provider emits a leading waypoint whose
// X is 0 where the agent stands at X=700 (the other two components are the agent's exactly), and the crowd
// path-follow normalizer retires that corner immediately — so the agent's true flight line runs from where it
// stands to the goal, and distance to the installed first SEGMENT measures the provider's endpoint
// resolution, not the follower's 3D tracking. The leading-waypoint anomaly belongs to the path provider and
// is recorded as a follow-up against it.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_crowd_flying_pie
{
    // Cross-latent-command state, reset at each test start.
    static FCk_Handle_VoxelNavVolume GVolume;
    static FCk_Handle_CrowdAgent GFlyingAgent;
    static FCk_Handle_CrowdAgent GGroundedAgent;
    static TArray<FCk_Handle_JoltBody> GBoxBodies;
    static TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE> GBakeListener;

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

    // Low corner to opposite high corner: 1400uu of climb over ~1980uu of ground track, so the route's own
    // inclination is ~35 degrees and cannot be mistaken for numerical drift.
    const auto RouteFromOffset = FVector{ 700.0, -700.0, -700.0};
    const auto RouteToOffset = FVector{-700.0,  700.0,  700.0};

    constexpr auto AgentRadiusUu = 42.0f;
    constexpr auto AgentHeightUu = 192.0f;

    // Enough climb that no float noise, and no single frame's integration, could produce it.
    constexpr auto RequiredClimbUu = 300.0;

    // cos(~8 degrees). The agent tracks the ideal line to within a couple of uu in practice; the slack is
    // for the acceleration ramp off the spawn, not a real budget.
    constexpr auto RouteAlignmentMinimum = 0.99;

    // The final waypoint carries the requested goal verbatim, so anything above float noise is real drift.
    constexpr auto EndpointToleranceUu = 1.0;

    // The route climbs at ~35 degrees and MaxTurnRate (4 rad/s) reaches that within two frames, so a flyer
    // that is tracking it at all clears this comfortably.
    constexpr auto RequiredPitchDegrees = 10.0f;

    // The yaw-only processor writes rotation offsets with a zero pitch component, so a grounded agent's pitch
    // is not merely small, it is untouched.
    constexpr auto GroundedPitchToleranceDegrees = 0.5f;

    static auto Get_VolumeBounds() -> FBox
    {
        return FBox{VolumeCenter - VolumeHalfExtents, VolumeCenter + VolumeHalfExtents};
    }

    static auto Get_RouteFrom() -> FVector { return VolumeCenter + RouteFromOffset; }
    static auto Get_RouteTo() -> FVector { return VolumeCenter + RouteToOffset; }

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

    // The agents differ ONLY in _AgentMode, so anything the two do differently is the tag's doing.
    static auto Make_AgentParams(ECk_CrowdAgent_Mode InMode) -> FCk_Fragment_CrowdAgent_ParamsData
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData{AgentRadiusUu, AgentHeightUu};
        Params.Set_AgentMode(InMode);
        return Params;
    }

    // A crowd agent carries no locomotion of its own: steering writes a desired velocity, and the velocity
    // bridge only reaches CkPhysics if the entity actually owns the Velocity feature and a running integrator.
    static auto Spawn_Agent(
        UWorld* InServer,
        const FVector& InSpawnLocation,
        ECk_CrowdAgent_Mode InMode) -> FCk_Handle_CrowdAgent
    {
        auto AgentEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});
        auto AgentTransform = UCk_Utils_Transform_UE::Add(AgentEntity, FTransform{InSpawnLocation},
            ECk_Replication::DoesNotReplicate);

        auto Agent = UCk_Utils_CrowdAgent_UE::Add(AgentTransform, Make_AgentParams(InMode));

        UCk_Utils_Velocity_UE::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector::ZeroVector},
            ECk_Replication::DoesNotReplicate);
        UCk_Utils_Acceleration_UE::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData{ECk_LocalWorld::World, FVector::ZeroVector},
            ECk_Replication::DoesNotReplicate);
        UCk_Utils_EulerIntegrator_UE::Request_Start(AgentEntity, {});

        return Agent;
    }

    static auto Bind_Agent_ToVolume(FCk_Handle_CrowdAgent& InAgent) -> bool
    {
        auto AgentHandle = InAgent.ConvertToHandle();
        auto Path = UCk_Utils_VoxelNavPath_UE::Add(AgentHandle,
            FCk_Fragment_VoxelNavPath_ParamsData{AgentRadiusUu});

        if (ck::Is_NOT_Valid(Path))
        { return false; }

        // Binding the volume is what makes MoveTo choose the volumetric provider.
        UCk_Utils_VoxelNavPath_UE::Request_SetVolume(Path, GVolume, {});
        return true;
    }

    static auto Get_AgentLocation(const FCk_Handle_CrowdAgent& InAgent) -> FVector
    {
        return UCk_Utils_Transform_UE::Get_EntityCurrentLocation(
            UCk_Utils_Transform_UE::CastChecked(InAgent));
    }

    static auto Get_AgentPitchDegrees(const FCk_Handle_CrowdAgent& InAgent) -> float
    {
        return UCk_Utils_Transform_UE::Get_EntityCurrentRotation(
            UCk_Utils_Transform_UE::CastChecked(InAgent)).Pitch;
    }

}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_CrowdFlyingPie_FlyingAgentFliesItsRouteInThreeDimensions,
    "Ck.VoxelNav.Crowd.Pie.FlyingAgentFliesItsRouteInThreeDimensions",
    ck_test_voxelnav_crowd_flying_pie::kTestFlags)

bool FCkTest_VoxelNav_CrowdFlyingPie_FlyingAgentFliesItsRouteInThreeDimensions::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_crowd_flying_pie;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to flying agents — whitelist it.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GVolume = FCk_Handle_VoxelNavVolume{};
    GFlyingAgent = FCk_Handle_CrowdAgent{};
    GGroundedAgent = FCk_Handle_CrowdAgent{};
    GBoxBodies.Reset();
    GBakeListener = TStrongObjectPtr<UCk_VoxelNavBakeTest_Listener_UE>{
        NewObject<UCk_VoxelNavBakeTest_Listener_UE>(GetTransientPackage())};

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto BodyAddedTimeoutSeconds = 15.0;
    constexpr auto BakeTimeoutSeconds = 60.0;
    constexpr auto RouteTimeoutSeconds = 15.0;
    constexpr auto ClimbTimeoutSeconds = 30.0;
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
            if (NOT TestTrue(TEXT("the volume published its bake before the agents were moved"),
                ck::IsValid(GVolume) && UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume)))
            { return; }

            // The two agents share one route, endpoints included. Offsetting the control would put its
            // endpoints in cells this bake never created — the octree is sparse, and only cells the
            // authored scene caused to exist are addressable — so a "nearby" goal is not a safe
            // substitute for the proven one. Sharing costs nothing here: the flying agent is excluded
            // from Separation and PushApart, so the co-located pair cannot perturb it.
            GFlyingAgent = Spawn_Agent(InServer, Get_RouteFrom(), ECk_CrowdAgent_Mode::Flying);
            GGroundedAgent = Spawn_Agent(InServer, Get_RouteFrom(), ECk_CrowdAgent_Mode::Grounded);

            if (NOT TestTrue(TEXT("both crowd agents composed"),
                ck::IsValid(GFlyingAgent) && ck::IsValid(GGroundedAgent)))
            { return; }

            const auto FlyingIsTagged = TestTrue(
                TEXT("_AgentMode Flying stamped the exclusion tag every planar stage filters on"),
                GFlyingAgent.Has<ck::FTag_CrowdAgent_Flying>());

            const auto GroundedIsNotTagged = TestFalse(
                TEXT("the default _AgentMode leaves an agent in the grounded population"),
                GGroundedAgent.Has<ck::FTag_CrowdAgent_Flying>());

            if (NOT (FlyingIsTagged && GroundedIsNotTagged))
            { return; }

            if (NOT TestTrue(TEXT("the volumetric path feature bound to the volume on both agents"),
                Bind_Agent_ToVolume(GFlyingAgent) && Bind_Agent_ToVolume(GGroundedAgent)))
            { return; }

            UCk_Utils_CrowdAgent_UE::Request_MoveTo(GFlyingAgent,
                FCk_Request_CrowdAgent_MoveTo{Get_RouteTo()}, {});
            UCk_Utils_CrowdAgent_UE::Request_MoveTo(GGroundedAgent,
                FCk_Request_CrowdAgent_MoveTo{Get_RouteTo()}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GFlyingAgent) && ck::IsValid(GGroundedAgent) &&
                GFlyingAgent.Has<ck::FTag_CrowdAgent_Walking>() &&
                GGroundedAgent.Has<ck::FTag_CrowdAgent_Walking>();
        }),
        RouteTimeoutSeconds,
        TEXT("both agents walk the routes the volumetric provider installed into their nav-path slots")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GFlyingAgent) &&
                Get_AgentLocation(GFlyingAgent).Z - Get_RouteFrom().Z >= RequiredClimbUu;
        }),
        ClimbTimeoutSeconds,
        TEXT("the flying agent gained altitude along its route — the displacement it staged reached its "
             "transform with its vertical component intact")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto& Waypoints = UCk_Utils_Nav_UE::Get_PathResult(GFlyingAgent).Get_Waypoints();

            if (NOT TestTrue(TEXT("the flying agent's installed route holds at least the two endpoints"),
                Waypoints.Num() >= 2))
            { return false; }

            const auto FlyingLocation = Get_AgentLocation(GFlyingAgent);

            if (NOT TestTrue(TEXT("the installed route ends at the goal the MoveTo asked for"),
                FVector::Dist(Waypoints.Last(), Get_RouteTo()) <= EndpointToleranceUu))
            { return false; }

            // The measure is the DIRECTION the agent has actually travelled against the direction of its
            // route's own goal, in three dimensions. An agent whose Z was being substituted from a surface
            // would still make the same ground track, so a planar or floor-clamped follower reads ~0.82
            // here (the route inclines ~35 degrees) while a true 3D follower reads ~1.
            const auto TravelledDirection = (FlyingLocation - Get_RouteFrom()).GetSafeNormal();
            const auto RouteDirection = (Waypoints.Last() - Get_RouteFrom()).GetSafeNormal();

            const auto TracksTheRouteInThreeDimensions = TestTrue(
                TEXT("the flying agent's travel is aligned with its route in 3D, not just in the XY plane — "
                     "nothing substituted a surface height for its Z"),
                FVector::DotProduct(TravelledDirection, RouteDirection) >= RouteAlignmentMinimum);

            const auto Climbed = TestTrue(
                TEXT("and it is measurably above where it started"),
                FlyingLocation.Z - Get_RouteFrom().Z >= RequiredClimbUu);

            const auto FlyingPitches = TestTrue(
                TEXT("the flying agent pitched toward its climb"),
                FMath::Abs(Get_AgentPitchDegrees(GFlyingAgent)) >= RequiredPitchDegrees);

            const auto FlyingTargetPitchIsLive = TestTrue(
                TEXT("and the 3D facing processor is the one that wrote it"),
                FMath::Abs(UCk_Utils_CrowdAgent_UE::Get_TargetPitchDegrees(GFlyingAgent)) >=
                    RequiredPitchDegrees);

            const auto GroundedNeverPitches = TestTrue(
                TEXT("the grounded agent walking the same climbing route is still faced by the yaw-only "
                     "processor — its pitch is untouched"),
                FMath::Abs(Get_AgentPitchDegrees(GGroundedAgent)) <= GroundedPitchToleranceDegrees &&
                FMath::IsNearlyZero(UCk_Utils_CrowdAgent_UE::Get_TargetPitchDegrees(GGroundedAgent)));

            return TracksTheRouteInThreeDimensions && Climbed && FlyingPitches &&
                   FlyingTargetPitchIsLive && GroundedNeverPitches;
        }),
        TEXT("the flying agent tracks its 3D route while the grounded one stays in the surface-bound "
             "population")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
