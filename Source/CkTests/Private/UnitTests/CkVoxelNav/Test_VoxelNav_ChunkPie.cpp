#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Fragment.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"

#include "CkVoxelNav/Chunk/CkVoxelNav_Chunk_Search.h"
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
// A PARTITIONED volume end-to-end in a real PIE world: an authored box too long for one chunk splits into two,
// both chunks bake through the volume's own processors, the volume aggregates them into one completion and one
// epoch, and an agent plans a route that crosses from one bake into the other.
//
// The hermetic chunk tests drive the partition math, the adjacency bake and the stitching directly. What only
// PIE can prove is that the pieces meet: chunk children composed at Add, baked by the same budgeted processors
// an unpartitioned volume uses, adjacency baked once they had all published, and a request drained by the
// globally registered path processor that routes to the chunked search on its own.
//
// The scene is the path test's, doubled: four static JoltBody boxes, two per chunk. Both chunks need geometry -
// a chunk that sees an empty world short-circuits at the broadphase sweep and creates no cells at all, so there
// would be nothing to path through on that side.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_chunk_pie
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

    // 3200 long on X at a 1600uu chunk size: two chunks, meeting at the volume's own centre plane.
    constexpr auto MaxChunkSizeUu = 1600.0f;
    constexpr auto ExpectedChunkCount = 2;

    const auto VolumeCenter = FVector{0.0, 0.0, 20000.0};
    const auto VolumeHalfExtents = FVector{1600.0, 800.0, 800.0};

    // Two per chunk. A chunk with no geometry bakes zero nodes and offers no cells to path through.
    const auto BoxOffsets = TArray<FVector>
    {
        FVector{-700.0, -700.0, -700.0},
        FVector{-300.0,  300.0,  100.0},
        FVector{ 700.0,  500.0, -300.0},
        FVector{ 300.0, -300.0,  100.0}
    };

    // Opposite upper corners, one per chunk, each in a layer-2 cell no box subdivided.
    const auto RouteFromOffset = FVector{-1400.0, -700.0, 700.0};
    const auto RouteToOffset = FVector{ 1400.0,  700.0, 700.0};

    // The waypoints carry the requested endpoints verbatim, so anything above float noise is a real drift.
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

        // The build must start from OUR request, so its completion delegate reports the bake this test waits
        // on rather than one the setup processor already armed on every chunk.
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        Params.Set_MaxChunkSizeOverride(ECk_EnableDisable::Enable);
        Params.Set_MaxChunkSizeUuOverride(MaxChunkSizeUu);

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
    FCkTest_VoxelNav_ChunkPie_PartitionedBakeRoutesAcrossAChunkBoundary,
    "Ck.VoxelNav.Chunk.Pie.PartitionedBakeRoutesAcrossAChunkBoundary",
    ck_test_voxelnav_chunk_pie::kTestFlags)

bool FCkTest_VoxelNav_ChunkPie_PartitionedBakeRoutesAcrossAChunkBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_chunk_pie;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the
    // Jolt static-world bake ensures on it at PIE start. Unrelated to chunking — whitelist it.
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
    constexpr auto BakeTimeoutSeconds = 90.0;
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

            // Partitioning is decided at composition, so it is observable before a single tick has run.
            if (NOT TestTrue(TEXT("an oversized volume partitioned"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsPartitioned(GVolume)))
            { return; }

            TestEqual(TEXT("into the hand-computed number of chunks"),
                UCk_Utils_VoxelNavVolume_UE::Get_ChunkCount(GVolume), ExpectedChunkCount);

            TestFalse(TEXT("a partitioned volume has published nothing yet"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume));

            auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
            CompletionDelegate.BindDynamic(GBakeListener.Get(),
                &UCk_VoxelNavBakeTest_Listener_UE::OnBuildRequestCompleted);

            auto BuildCompleteDelegate = FCk_Delegate_VoxelNavVolume_OnBuildComplete{};
            BuildCompleteDelegate.BindDynamic(GBakeListener.Get(),
                &UCk_VoxelNavBakeTest_Listener_UE::OnBuildComplete);

            UCk_Utils_VoxelNavVolume_UE::BindTo_OnBuildComplete(GVolume, BuildCompleteDelegate,
                ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

            UCk_Utils_VoxelNavVolume_UE::Request_Build(GVolume,
                FCk_Request_VoxelNavVolume_Build{}, CompletionDelegate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return GBakeListener.IsValid() && GBakeListener->_TimesRequestCompleted > 0;
        }),
        BakeTimeoutSeconds,
        TEXT("every chunk baked and the volume aggregated them into one completion")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto CompletedExactlyOnce = TestEqual(
                TEXT("the volume reports ONE completion however many chunks it owns"),
                GBakeListener->_TimesRequestCompleted, 1);

            const auto SignalFiredOnce = TestEqual(
                TEXT("and fires OnBuildComplete once, not once per chunk"),
                GBakeListener->_TimesBuildCompleteFired, 1);

            const auto VolumeIsBuilt = TestTrue(TEXT("the volume reports built once every chunk has"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(GVolume));

            const auto EveryChunkIsBuilt = TestTrue(TEXT("and so does every chunk it owns"),
                UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(UCk_Utils_VoxelNavVolume_UE::Get_Chunk(GVolume, 0)) &&
                UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(UCk_Utils_VoxelNavVolume_UE::Get_Chunk(GVolume, 1)));

            // The aggregated stats are the sum of the chunks', so a partitioned bake's cost is as
            // deterministic and as inspectable as an unpartitioned one's.
            const auto StatsAggregated = TestTrue(TEXT("the aggregated bake spent probes on real geometry"),
                GBakeListener->_LastStats.Get_OccupancyProbes() > 0 &&
                GBakeListener->_LastStats.Get_BroadphaseBodyCount() > 0);

            const auto AdjacencyBaked = TestTrue(
                TEXT("the two chunks found crossings between them"),
                UCk_Utils_VoxelNavVolume_UE::Get_ChunkPortalCount(GVolume) > 0);

            return CompletedExactlyOnce && SignalFiredOnce && VolumeIsBuilt && EveryChunkIsBuilt &&
                   StatsAggregated && AdjacencyBaked;
        }),
        TEXT("the partitioned volume published once, with adjacency, after every chunk had baked")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            // Both endpoints have to be navigable for a route between them to mean anything - a failure here
            // is a fixture problem, not a pathfinding one. Each routes to the chunk that owns it.
            const auto EndpointsAreFree =
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_RouteFrom()) &&
                UCk_Utils_VoxelNavVolume_UE::Get_IsPointFree(GVolume, Get_RouteTo());

            if (NOT TestTrue(TEXT("both requested endpoints stand in baked free space"), EndpointsAreFree))
            { return; }

            const auto Chunks = UCk_Utils_VoxelNavVolume_UE::Get_ChunkSearchInputs(GVolume);

            if (NOT TestTrue(TEXT("the two endpoints are in DIFFERENT chunks - the route must cross"),
                ck::voxelnav::TryGet_ChunkIndexContainingPoint(Chunks, Get_RouteFrom()) !=
                ck::voxelnav::TryGet_ChunkIndexContainingPoint(Chunks, Get_RouteTo())))
            { return; }

            auto Agent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});

            GPath = UCk_Utils_VoxelNavPath_UE::Add(Agent, FCk_Fragment_VoxelNavPath_ParamsData{});

            if (NOT TestTrue(TEXT("the path feature composed onto the agent"), ck::IsValid(GPath)))
            { return; }

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
        TEXT("the cross-chunk path request was drained and reported back to its caller")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            const auto CompletedSucceeded = TestTrue(
                TEXT("the cross-chunk search reported Succeeded to its caller"),
                GPathListener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

            const auto ReadyFiredOnce = TestEqual(TEXT("OnPathReady fired exactly once"),
                GPathListener->_TimesPathReadyFired, 1);

            const auto FailedNeverFired = TestEqual(TEXT("OnPathFailed does not fire"),
                GPathListener->_TimesPathFailedFired, 0);

            const auto PlannedAgainstTheVolume = TestEqual(
                TEXT("the path planned against the VOLUME's aggregated epoch, not a chunk's"),
                UCk_Utils_VoxelNavPath_UE::Get_PlannedAgainstEpoch(GPath),
                UCk_Utils_VoxelNavVolume_UE::Get_BuildEpoch(GVolume));

            return CompletedSucceeded && ReadyFiredOnce && FailedNeverFired && PlannedAgainstTheVolume;
        }),
        TEXT("the cross-chunk search succeeded once and reported through both channels")));

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

            const auto Chunks = UCk_Utils_VoxelNavVolume_UE::Get_ChunkSearchInputs(GVolume);

            auto ChunksVisited = TSet<int32>{};
            auto EverySpanIsClear = true;

            for (auto WaypointIdx = 1; WaypointIdx < Waypoints.Num(); ++WaypointIdx)
            {
                const auto FromChunk = ck::voxelnav::TryGet_ChunkIndexContainingPoint(
                    Chunks, Waypoints[WaypointIdx - 1]);
                const auto ToChunk = ck::voxelnav::TryGet_ChunkIndexContainingPoint(
                    Chunks, Waypoints[WaypointIdx]);

                ChunksVisited.Emplace(FromChunk);
                ChunksVisited.Emplace(ToChunk);

                // Checked against BOTH ends' bakes. A span inside one chunk is answered by that chunk; a
                // span across the boundary is answered by each side for its own half, which is the most any
                // octree can say about it.
                for (const auto ChunkIdx : {FromChunk, ToChunk})
                {
                    if (NOT Chunks.IsValidIndex(ChunkIdx) || NOT Chunks[ChunkIdx]._Octree.IsValid())
                    { continue; }

                    EverySpanIsClear &= NOT ck::voxelnav::Get_IsSegmentBlocked(
                        *Chunks[ChunkIdx]._Octree, Waypoints[WaypointIdx - 1], Waypoints[WaypointIdx]);
                }
            }

            const auto RouteIsCollisionFree = TestTrue(
                TEXT("every span of the route is clear against the bakes it passes through"),
                EverySpanIsClear);

            const auto RouteCrossedTheBoundary = TestEqual(
                TEXT("the route actually passed through both chunks"), ChunksVisited.Num(), ExpectedChunkCount);

            return StartsWhereAsked && EndsWhereAsked && RouteIsCollisionFree && RouteCrossedTheBoundary;
        }),
        TEXT("the cross-chunk route is collision free against the chunk bakes it crosses")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
