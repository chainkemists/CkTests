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

#include "CkVoxelNav/Path/CkVoxelNavPath_Utils.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavBake_TestTypes.h"

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

    const auto RouteFromOffset = FVector{ 700.0, -700.0, 700.0};
    const auto RouteToOffset = FVector{-700.0,  700.0, 700.0};

    // The installed waypoints carry the planned endpoints verbatim, so anything above float noise is a
    // real drift.
    constexpr auto EndpointToleranceUu = 1.0;

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

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
