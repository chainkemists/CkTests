#include "CkAStar/Algorithm/CkAStar_Search.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorGraph.h"
#include "CkEcs/Scheduler/CkProcessorScheduler.h"
#include "CkEcs/Scheduler/CkProcessorTraits.inl.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkVoxelNav/Backend/CkVoxelNav_GeometryBackend_Stub.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Build.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Query.h"
#include "CkVoxelNav/Octree/CkVoxelNav_Octree_Types.h"
#include "CkVoxelNav/Path/CkVoxelNav_Path_Graph.h"
#include "CkVoxelNav/Path/CkVoxelNavPath_Fragment.h"
#include "CkVoxelNav/Path/CkVoxelNavPath_Processor.h"
#include "CkVoxelNav/Path/CkVoxelNavPath_Utils.h"
#include "CkVoxelNav/Volume/CkVoxelNavVolume_Utils.h"

#include "CkVoxelNavPath_TestTypes.h"

#include "../CkUnitTest_Common.h"

#include "UObject/Package.h"
#include "UObject/StrongObjectPtr.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pathfinding over a hand-authored bake, driven through the stub geometry backend: no world, no physics,
// no PIE. The search half of these tests calls the synchronous seam directly against an octree baked in
// the test; the feature half drives the request drain through a private scheduler over a private registry.
//
// Scene, in a 1600uu cube at a 50uu finest cell (leaf 200uu, four layers, layer-2 cells 800uu):
//   - a floor slab across the whole footprint, 150uu thick
//   - a 200uu-square pillar rising through the middle
// Only five of the eight layer-2 cells are subdivided, so a route across the upper half crosses coarse
// open cells AND descends into the pillar's subtree - the parent/child transition is on the path, not
// merely available.
//
// A volume containing NO geometry is deliberately not used as a path fixture: its bake short-circuits at
// the broadphase sweep and creates zero nodes, so there are no cells to path through at all.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voxelnav_path
{
    constexpr auto FinestCellSizeUu = 50.0f;
    constexpr auto VolumeHalfSizeUu = 800.0;

    constexpr auto UnlimitedProbeBudget = 1000000;

    // Generous enough that a real search never reaches it.
    constexpr auto SearchIterationCap = 200000;

    const auto VolumeBounds = FBox{FVector{-VolumeHalfSizeUu}, FVector{VolumeHalfSizeUu}};

    const auto FloorSlab = FBox{FVector{-800.0, -800.0, -800.0}, FVector{800.0, 800.0, -650.0}};
    const auto Pillar = FBox{FVector{100.0, 100.0, -390.0}, FVector{300.0, 300.0, 390.0}};

    // Spans the whole footprint and overhangs it, so no sub-node column anywhere crosses it and no cell
    // boundary is touched exactly - the seal is unambiguous rather than a tie-break.
    const auto SealingWall = FBox{FVector{-900.0, -900.0, -10.0}, FVector{900.0, 900.0, 110.0}};

    // Open air in a layer-2 cell that was never subdivided.
    const auto OpenAirStart = FVector{-575.0, -575.0, 575.0};

    // Open air ABOVE the pillar, inside the one upper layer-2 cell the pillar forced to subdivide - so
    // reaching it means descending from a coarse cell into a finer one.
    const auto AbovePillarGoal = FVector{175.0, 175.0, 575.0};

    const auto BelowWall = FVector{-500.0, -500.0, -500.0};
    const auto AboveWall = FVector{500.0, 500.0, 500.0};

    const auto PointOutsideVolume = FVector{0.0, 0.0, 10000.0};

    const auto TestVolumeId = ck::voxelnav::FVolumeId{1};

    static auto
        Bake_Octree(
            const TArray<FBox>& InObstacles)
        -> TSharedPtr<const ck::voxelnav::FOctree>
    {
        using namespace ck::voxelnav;

        // Generous enough that a working machine never reaches it, small enough that a machine that stops
        // making progress fails the test instead of hanging the run.
        constexpr auto MaxSlices = 100000;

        const auto Backend = FCk_VoxelNav_GeometryBackend_Stub{InObstacles};

        auto Params = FBuildParams{};
        Params._VolumeBounds = VolumeBounds;
        Params._FinestCellSizeUu = FinestCellSizeUu;

        auto Budget = FBuildBudget{};
        Budget._MaxOccupancyProbes = UnlimitedProbeBudget;
        Budget._MaxSeconds = 0.0f;

        auto State = FBuildState{};

        for (auto SliceIdx = 0; SliceIdx < MaxSlices && NOT State.Get_IsFinished(); ++SliceIdx)
        { Request_AdvanceBuild(State, Params, Backend, Budget); }

        return Request_ReleaseBuiltOctree(State);
    }

    static auto
        Make_SearchParams(
            const FVector& InFrom,
            const FVector& InTo)
        -> ck::voxelnav::FPathSearchParams
    {
        auto Params = ck::voxelnav::FPathSearchParams{};

        Params._From = InFrom;
        Params._To = InTo;
        Params._MaxIterations = SearchIterationCap;

        return Params;
    }

    // Rebuilds the graph the plan was produced by, so the path's connectivity is checked against the same
    // neighbour relation the search expanded - not against a looser distance approximation.
    static auto
        Make_GraphForPlan(
            const ck::voxelnav::FOctree& InOctree,
            const ck::voxelnav::FPathPlan& InPlan)
        -> ck::voxelnav::FPathGraph
    {
        using namespace ck::voxelnav;

        auto SharedData = FPathGraphSharedData{};

        SharedData._GoalCell = InPlan._Cells.Last();
        SharedData._GoalLocation = Get_CellCenter(InOctree, SharedData._GoalCell);
        SharedData._FinestCellExtentUu = InOctree.Get_LeafNodes().Get_LeafSubNodeExtent();

        return FPathGraph{
            &InOctree,
            TestVolumeId,
            TSharedPtr<const FPathGraphSharedData>{MakeShared<FPathGraphSharedData>(MoveTemp(SharedData))}};
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Private registry plus a single-processor scheduler holding only the path request drain, so the test
    // exercises the real processor without pulling every registered processor into a hermetic world.
    struct FPathRequestFixture
    {
        ck::FEcsWorld World;
        TUniquePtr<ck::FProcessorScheduler> Scheduler;

        auto
            Build()
            -> bool
        {
            const auto TransientHandle = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(World.Get_Registry());

            auto Descriptors = TArray<ck::FProcessorDescriptor>{};

            // The graph builder resolves a processor's group to start/end nodes it must find in the SAME
            // descriptor list, and the group in turn names the one it runs after - so both travel with the
            // processor into a private graph.
            Descriptors.Add(ck::BuildGroupDescriptor<ck::FGroup_DestructionPipeline>());
            Descriptors.Add(ck::BuildGroupDescriptor<ck::FGroup_Gameplay_TimeDelta>());

            Descriptors.Add(ck::BuildDescriptor<ck::FProcessor_VoxelNavPath_HandleRequests>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                {
                    return ck::FProcessor_VoxelNavPath_HandleRequests{InRegistry};
                }));

            auto Builder = ck::FProcessorGraphBuilder{};
            auto Graph = Builder.Build(Descriptors, World.Get_Registry(), TransientHandle);

            for (auto& Kvp : Graph._Partitions)
            {
                if (Kvp.Value._Nodes.Num() > 0)
                {
                    Scheduler = MakeUnique<ck::FProcessorScheduler>(MoveTemp(Kvp.Value));
                    return true;
                }
            }

            return false;
        }

        auto
            Tick()
            -> void
        {
            constexpr auto SixtyHertz = 1.0f / 60.0f;

            Scheduler->Tick(FCk_Time{SixtyHertz}, World.Get_Registry());
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_FindsRouteAcrossBakedFreeSpace,
    "Ck.VoxelNav.Path.Search.FindsRouteAcrossBakedFreeSpace",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_FindsRouteAcrossBakedFreeSpace::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_path;

    const auto Octree = Bake_Octree(TArray<FBox>{FloorSlab, Pillar});

    if (NOT TestTrue(TEXT("the fixture bake publishes a valid octree"),
        Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    const auto Plan = Search_PathGraph(*Octree, TestVolumeId, Make_SearchParams(OpenAirStart, AbovePillarGoal));

    if (NOT TestTrue(TEXT("a route across open air is found"),
        Plan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    if (NOT TestTrue(TEXT("the route spans more than one cell"), Plan._Cells.Num() >= 2))
    { return false; }

    TestEqual(TEXT("the waypoints are the cell centres plus the two requested endpoints"),
        Plan._Waypoints.Num(), Plan._Cells.Num() + 2);

    TestTrue(TEXT("the first waypoint is exactly the requested start"), Plan._Waypoints[0] == OpenAirStart);
    TestTrue(TEXT("the last waypoint is exactly the requested goal"), Plan._Waypoints.Last() == AbovePillarGoal);

    auto EveryCellIsFree = true;
    for (const auto& Cell : Plan._Cells)
    { EveryCellIsFree &= Get_CellIsFree(*Octree, Cell); }

    TestTrue(TEXT("every cell on the route is navigable free space"), EveryCellIsFree);

    auto EveryWaypointIsFree = true;
    for (const auto& Waypoint : Plan._Waypoints)
    { EveryWaypointIsFree &= Get_IsPositionFree(*Octree, Waypoint); }

    TestTrue(TEXT("every waypoint stands in free space"), EveryWaypointIsFree);

    // The graph's own neighbour relation is the definition of "adjacent" here: it covers a shared face at
    // one layer AND the parent/child transitions across a layer change, which a distance check would not.
    const auto Graph = Make_GraphForPlan(*Octree, Plan);
    const auto FirstBrokenStep = ck::astar::ValidateExistingPath<FCellId, FPathGraph>(Graph, Plan._Cells);

    TestEqual(TEXT("every consecutive pair of cells is connected in the graph the search expanded"),
        FirstBrokenStep, Plan._Cells.Num());

    // The route starts in an 800uu cell and ends inside the pillar's subdivided subtree, so it cannot be
    // expressed at one layer - a regression that broke the layer transition would still find SOME path,
    // just not one that changes resolution.
    auto SmallestCellExtent = TNumericLimits<float>::Max();
    auto LargestCellExtent = 0.0f;

    for (const auto& Cell : Plan._Cells)
    {
        const auto CellExtent = Get_CellExtent(*Octree, Cell);

        SmallestCellExtent = FMath::Min(SmallestCellExtent, CellExtent);
        LargestCellExtent = FMath::Max(LargestCellExtent, CellExtent);
    }

    TestTrue(TEXT("the route crosses cells of more than one size, so it changed layers"),
        LargestCellExtent > SmallestCellExtent);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_WalledOffGoalIsUnreachable,
    "Ck.VoxelNav.Path.Search.WalledOffGoalIsUnreachable",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_WalledOffGoalIsUnreachable::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_path;

    const auto Octree = Bake_Octree(TArray<FBox>{SealingWall});

    if (NOT TestTrue(TEXT("the sealed bake publishes a valid octree"),
        Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    if (NOT TestTrue(TEXT("both endpoints are themselves free - the wall is what separates them"),
        Get_IsPositionFree(*Octree, BelowWall) && Get_IsPositionFree(*Octree, AboveWall)))
    { return false; }

    const auto Plan = Search_PathGraph(*Octree, TestVolumeId, Make_SearchParams(BelowWall, AboveWall));

    TestTrue(TEXT("a goal sealed behind a wall reports Unreachable, not a path"),
        Plan._Outcome == ECk_VoxelNav_PathSearchOutcome::Unreachable);

    TestTrue(TEXT("a failed search produces no waypoints"), Plan._Waypoints.IsEmpty());

    // The distinction matters: a caller retries a capped search with a bigger budget and does not retry
    // an unreachable one at all.
    TestTrue(TEXT("the search exhausted its reachable space rather than its iteration budget"),
        Plan._Iterations < SearchIterationCap);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_EndpointOutsideTheBakeIsRejected,
    "Ck.VoxelNav.Path.Search.EndpointOutsideTheBakeIsRejected",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_EndpointOutsideTheBakeIsRejected::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_path;

    const auto Octree = Bake_Octree(TArray<FBox>{FloorSlab, Pillar});

    if (NOT TestTrue(TEXT("the fixture bake publishes a valid octree"),
        Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    const auto PlanFromOutside = Search_PathGraph(*Octree, TestVolumeId,
        Make_SearchParams(PointOutsideVolume, OpenAirStart));

    TestTrue(TEXT("a start outside the baked cube is rejected"),
        PlanFromOutside._Outcome == ECk_VoxelNav_PathSearchOutcome::EndpointUnresolvable);

    const auto PlanToOutside = Search_PathGraph(*Octree, TestVolumeId,
        Make_SearchParams(OpenAirStart, PointOutsideVolume));

    TestTrue(TEXT("a goal outside the baked cube is rejected"),
        PlanToOutside._Outcome == ECk_VoxelNav_PathSearchOutcome::EndpointUnresolvable);

    const auto UnbakedOctree = FOctree{};
    const auto PlanWithoutBake = Search_PathGraph(UnbakedOctree, TestVolumeId,
        Make_SearchParams(OpenAirStart, AbovePillarGoal));

    TestTrue(TEXT("an octree that was never built reports NoBake, distinctly from a bad endpoint"),
        PlanWithoutBake._Outcome == ECk_VoxelNav_PathSearchOutcome::NoBake);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_IterationCapStopsTheSearch,
    "Ck.VoxelNav.Path.Search.IterationCapStopsTheSearch",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_IterationCapStopsTheSearch::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_path;

    // One expansion cannot cross a 1600uu volume, so the cap is provably what stops this search.
    constexpr auto OneExpansion = 1;

    const auto Octree = Bake_Octree(TArray<FBox>{FloorSlab, Pillar});

    if (NOT TestTrue(TEXT("the fixture bake publishes a valid octree"),
        Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    auto CappedParams = Make_SearchParams(OpenAirStart, AbovePillarGoal);
    CappedParams._MaxIterations = OneExpansion;

    const auto CappedPlan = Search_PathGraph(*Octree, TestVolumeId, CappedParams);

    TestTrue(TEXT("a search that spends its whole budget reports IterationCapReached"),
        CappedPlan._Outcome == ECk_VoxelNav_PathSearchOutcome::IterationCapReached);

    TestTrue(TEXT("a capped search produces no waypoints"), CappedPlan._Waypoints.IsEmpty());

    auto ZeroCapParams = Make_SearchParams(OpenAirStart, AbovePillarGoal);
    ZeroCapParams._MaxIterations = 0;

    const auto ZeroCapPlan = Search_PathGraph(*Octree, TestVolumeId, ZeroCapParams);

    TestTrue(TEXT("a budget of zero is a malformed request, not a search that ran out"),
        ZeroCapPlan._Outcome == ECk_VoxelNav_PathSearchOutcome::InvalidRequest);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_PlanCarriesTheEpochItWasPlannedAgainst,
    "Ck.VoxelNav.Path.Search.PlanCarriesTheEpochItWasPlannedAgainst",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_PlanCarriesTheEpochItWasPlannedAgainst::RunTest(const FString& Parameters)
{
    using namespace ck::voxelnav;
    using namespace ck_test_voxelnav_path;

    constexpr auto PlannedEpoch = 7;
    constexpr auto RebuiltEpoch = 8;

    const auto Octree = Bake_Octree(TArray<FBox>{FloorSlab, Pillar});

    if (NOT TestTrue(TEXT("the fixture bake publishes a valid octree"),
        Octree.IsValid() && Octree->Get_IsValid()))
    { return false; }

    auto EpochParams = Make_SearchParams(OpenAirStart, AbovePillarGoal);
    EpochParams._PlannedAgainstEpoch = PlannedEpoch;

    const auto Plan = Search_PathGraph(*Octree, TestVolumeId, EpochParams);

    if (NOT TestTrue(TEXT("the route is found"),
        Plan._Outcome == ECk_VoxelNav_PathSearchOutcome::Succeeded))
    { return false; }

    TestEqual(TEXT("the plan carries the build epoch it was planned against"),
        Plan._PlannedAgainstEpoch, PlannedEpoch);

    TestFalse(TEXT("a plan is not stale while its volume sits at the epoch it planned against"),
        Get_IsPlannedEpochStale(Plan._PlannedAgainstEpoch, PlannedEpoch));

    TestTrue(TEXT("a plan is stale once its volume has rebuilt"),
        Get_IsPlannedEpochStale(Plan._PlannedAgainstEpoch, RebuiltEpoch));

    auto FailedParams = Make_SearchParams(OpenAirStart, PointOutsideVolume);
    FailedParams._PlannedAgainstEpoch = PlannedEpoch;

    const auto FailedPlan = Search_PathGraph(*Octree, TestVolumeId, FailedParams);

    TestEqual(TEXT("a failed plan still records which bake it was attempted against"),
        FailedPlan._PlannedAgainstEpoch, PlannedEpoch);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_AddComposesOnTheAgentEntity,
    "Ck.VoxelNav.Path.Feature.AddComposesOnTheAgentEntity",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_AddComposesOnTheAgentEntity::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_path;

    constexpr auto AgentRadiusUu = 25.0f;

    auto EcsWorld = ck::FEcsWorld{};
    auto Agent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    const auto Path = UCk_Utils_VoxelNavPath_UE::Add(Agent,
        FCk_Fragment_VoxelNavPath_ParamsData{AgentRadiusUu});

    if (NOT TestTrue(TEXT("Add returns a valid VoxelNavPath handle"), ck::IsValid(Path)))
    { return false; }

    TestTrue(TEXT("the feature lands on the AGENT entity itself, not on a child of it"),
        UCk_Utils_VoxelNavPath_UE::Has(Agent));

    TestTrue(TEXT("the returned handle addresses the same entity the feature was stamped on"),
        Path.Get_Entity() == Agent.Get_Entity());

    TestTrue(TEXT("a path that has never planned reports no status"),
        UCk_Utils_VoxelNavPath_UE::Get_Status(Path) == ECk_VoxelNav_PathStatus::None);

    TestTrue(TEXT("a path that has never planned reports no waypoints"),
        UCk_Utils_VoxelNavPath_UE::Get_Waypoints(Path).IsEmpty());

    TestFalse(TEXT("a path that has never planned is not stale"),
        UCk_Utils_VoxelNavPath_UE::Get_IsStale(Path));

    TestEqual(TEXT("the authored agent radius round-trips"),
        Agent.Get<ck::FFragment_VoxelNavPath_Params>().Get_AgentRadiusUu(), AgentRadiusUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_RequestOnInvalidPathCompletesNotEnqueued,
    "Ck.VoxelNav.Path.Feature.RequestOnInvalidPathCompletesNotEnqueued",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_RequestOnInvalidPathCompletesNotEnqueued::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_path;

    auto InvalidPath = FCk_Handle_VoxelNavPath{};

    auto Listener = TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE>{
        NewObject<UCk_VoxelNavPathTest_Listener_UE>(GetTransientPackage())};

    // One ensure fire emits a log entry + an Error line, both carrying the message - whitelist by substring
    // without enforcing a count. The debug-callstack record runs ahead of the validity check and ensures
    // on the same invalid handle, so it is whitelisted too.
    AddExpectedError(TEXT("Invalid entity handle"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedError(TEXT("supplied to Request_FindPath"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
    CompletionDelegate.BindDynamic(Listener.Get(), &UCk_VoxelNavPathTest_Listener_UE::OnFindPathCompleted);

    UCk_Utils_VoxelNavPath_UE::Request_FindPath(InvalidPath,
        FCk_Request_VoxelNavPath_FindPath{FCk_Handle_VoxelNavVolume{}, FVector::ZeroVector, FVector::ZeroVector},
        CompletionDelegate);

    TestEqual(TEXT("a request rejected at the Utils boundary completes exactly once"),
        Listener->_TimesRequestCompleted, 1);

    TestTrue(TEXT("it completes as Failed_NotEnqueued - it never reached a queue"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed_NotEnqueued);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoxelNav_Path_RequestAgainstUnbuiltVolumeFails,
    "Ck.VoxelNav.Path.Feature.RequestAgainstUnbuiltVolumeFails",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_VoxelNav_Path_RequestAgainstUnbuiltVolumeFails::RunTest(const FString& Parameters)
{
    using namespace ck_test_voxelnav_path;

    auto Fixture = FPathRequestFixture{};

    if (NOT TestTrue(TEXT("the private path-request scheduler builds"), Fixture.Build()))
    { return false; }

    auto Listener = TStrongObjectPtr<UCk_VoxelNavPathTest_Listener_UE>{
        NewObject<UCk_VoxelNavPathTest_Listener_UE>(GetTransientPackage())};

    auto Agent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture.World.Get_Registry());
    auto Volume = UCk_Utils_VoxelNavVolume_UE::Add(Agent,
        FCk_Fragment_VoxelNavVolume_ParamsData{VolumeBounds, FinestCellSizeUu});

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    if (NOT TestFalse(TEXT("the volume has published no bake - which is the situation under test"),
        UCk_Utils_VoxelNavVolume_UE::Get_IsBuilt(Volume)))
    { return false; }

    auto Path = UCk_Utils_VoxelNavPath_UE::Add(Agent, FCk_Fragment_VoxelNavPath_ParamsData{});

    if (NOT TestTrue(TEXT("the path feature composes"), ck::IsValid(Path)))
    { return false; }

    auto FailedDelegate = FCk_Delegate_VoxelNavPath_OnPathFailed{};
    FailedDelegate.BindDynamic(Listener.Get(), &UCk_VoxelNavPathTest_Listener_UE::OnPathFailed);

    UCk_Utils_VoxelNavPath_UE::BindTo_OnPathFailed(Path, FailedDelegate,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing);

    auto CompletionDelegate = FCk_Delegate_Request_OnCompleted{};
    CompletionDelegate.BindDynamic(Listener.Get(), &UCk_VoxelNavPathTest_Listener_UE::OnFindPathCompleted);

    UCk_Utils_VoxelNavPath_UE::Request_FindPath(Path,
        FCk_Request_VoxelNavPath_FindPath{Volume, OpenAirStart, AbovePillarGoal}, CompletionDelegate);

    TestEqual(TEXT("the request is queued, not answered synchronously"),
        Listener->_TimesRequestCompleted, 0);

    Fixture.Tick();

    TestEqual(TEXT("the drain completes the caller exactly once"), Listener->_TimesRequestCompleted, 1);

    TestTrue(TEXT("a request against a volume with no bake completes as Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    TestEqual(TEXT("OnPathFailed fires exactly once"), Listener->_TimesPathFailedFired, 1);

    TestTrue(TEXT("the failure names the missing bake, so the caller knows to wait rather than re-aim"),
        Listener->_LastFailureOutcome == ECk_VoxelNav_PathSearchOutcome::NoBake);

    TestEqual(TEXT("OnPathReady does not fire"), Listener->_TimesPathReadyFired, 0);

    TestTrue(TEXT("the path reports Failed"),
        UCk_Utils_VoxelNavPath_UE::Get_Status(Path) == ECk_VoxelNav_PathStatus::Failed);

    TestTrue(TEXT("the recorded outcome survives for a caller that reads it later"),
        UCk_Utils_VoxelNavPath_UE::Get_LastSearchOutcome(Path) == ECk_VoxelNav_PathSearchOutcome::NoBake);

    TestTrue(TEXT("a failed path holds no waypoints"),
        UCk_Utils_VoxelNavPath_UE::Get_Waypoints(Path).IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
