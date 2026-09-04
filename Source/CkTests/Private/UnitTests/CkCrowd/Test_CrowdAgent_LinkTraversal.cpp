// The crowd half of the link-traversal handshake: what the GroundNav install stamps onto an agent, and
// what the waypoint cursor does with it.
//
// The seam is driven directly rather than through a frame, exactly as the neutral handshake's own rows
// do it: a headless registry has no scheduler, so the cursor is stepped one position at a time and the
// CkNavigation drain is invoked between steps. That is the only way to state "exactly once" as a fact
// about a single cursor advance rather than about whatever a frame happened to contain.
//
// No world, no field and no published surface appear here. The install stamp is a pure function of the
// answer's own metadata and the cursor is a pure function of the stamped spans, so a hand-written
// result is the whole fixture - the same reason Test_CrowdAgent_GroundNavInstall needs a registry and
// nothing more.
//
// What is NOT covered here: an agent physically walking a real ladder on a built field, which needs a
// published surface and is therefore a PIE pin.

#include "CkCore/Time/CkTime.h"

#include "CkCrowd/Agent/CkCrowdAgent_Fragment.h"
#include "CkCrowd/Agent/CkCrowdAgent_Steering_Processor.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Signal/CkSignal_Fragment_Data.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Path/CkGroundNavPath_Fragment_Data.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Processor.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "../CkNavigation/CkTest_LinkTraversalListener.h"
#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>
#include <UObject/StrongObjectPtr.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_link_traversal
{
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    // Distinct primes, so a span that carried one link's id where the other's belonged cannot read as
    // correct. Neither is a waypoint index either.
    constexpr auto kLadderLinkId = int32{7};
    constexpr auto kSecondLinkId = int32{13};

    // A six-waypoint corridor: room for a crossing in the middle with ground on both sides of it, so
    // "before the entry" and "past the exit" are both real positions rather than the ends of the array.
    constexpr auto kWaypointCount = int32{6};
    constexpr auto kEntryWaypointIndex = int32{2};
    constexpr auto kExitWaypointIndex = int32{3};

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_LinkWaypoint(
        int32                                  InWaypointIndex,
        int32                                  InLinkId,
        ECk_GroundNavPath_LinkWaypointRole     InRole,
        ECk_GroundNav_LinkDirection            InEntryDirection) -> FCk_GroundNavPath_LinkWaypoint
    {
        return FCk_GroundNavPath_LinkWaypoint{
            InWaypointIndex,
            InLinkId,
            InRole,
            InEntryDirection,
            static_cast<float>(InWaypointIndex) * 100.0f};
    }

    // A Ready answer whose polyline is a straight run and whose metadata is whatever the caller wants
    // to put on it. The locations are never read by anything under test - the cursor works on indices.
    auto Make_Result(
        const TArray<FCk_GroundNavPath_LinkWaypoint>& InLinkWaypoints) -> FCk_GroundNavPath_Result
    {
        auto Waypoints = TArray<FVector>{};
        for (auto Index = 0; Index < kWaypointCount; ++Index)
        { Waypoints.Emplace(FVector{static_cast<double>(Index) * 100.0, 0.0, 0.0}); }

        auto Result = FCk_GroundNavPath_Result{};
        Result.Set_Status(ECk_GroundNav_PathStatus::Ready);
        Result.Set_Waypoints(Waypoints);
        Result.Set_LinkWaypoints(InLinkWaypoints);

        return Result;
    }

    auto Make_OneCrossingResult() -> FCk_GroundNavPath_Result
    {
        return Make_Result({
            Make_LinkWaypoint(kEntryWaypointIndex, kLadderLinkId,
                ECk_GroundNavPath_LinkWaypointRole::Entry, ECk_GroundNav_LinkDirection::Forward),
            Make_LinkWaypoint(kExitWaypointIndex, kLadderLinkId,
                ECk_GroundNavPath_LinkWaypointRole::Exit, ECk_GroundNav_LinkDirection::Forward)});
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_TraversalListener(
        FCk_Handle& InTraverser) -> TStrongObjectPtr<UCk_Test_NavSurfaceLinkTraversalListener_UE>
    {
        auto Listener = TStrongObjectPtr<UCk_Test_NavSurfaceLinkTraversalListener_UE>{
            NewObject<UCk_Test_NavSurfaceLinkTraversalListener_UE>(GetTransientPackage())};

        auto BegunDelegate = FCk_Delegate_NavSurface_OnLinkTraversalBegun{};
        BegunDelegate.BindUFunction(Listener.Get(), TEXT("OnLinkTraversalBegun"));

        auto CompletedDelegate = FCk_Delegate_NavSurface_OnLinkTraversalCompleted{};
        CompletedDelegate.BindUFunction(Listener.Get(), TEXT("OnLinkTraversalCompleted"));

        UCk_Utils_NavSurface_LinkTraversal_UE::BindTo_OnLinkTraversalBegun(InTraverser, BegunDelegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        UCk_Utils_NavSurface_LinkTraversal_UE::BindTo_OnLinkTraversalCompleted(InTraverser, CompletedDelegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        return Listener;
    }

    // One drain pass. The drain takes the queue OFF the entity, so an agent that enqueued nothing this
    // step carries no queue at all and there is nothing to step.
    auto DoDrain_TraversalRequests(
        ck::FEcsWorld& InWorld,
        FCk_Handle&    InTraverser) -> void
    {
        if (NOT InTraverser.Has<ck::FFragment_NavSurface_LinkTraversal_Requests>())
        { return; }

        ck::FProcessor_NavSurface_LinkTraversal_HandleRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InTraverser,
            InTraverser.Get<ck::FFragment_NavSurface_LinkTraversal_Requests>(),
            InTraverser.Get<ck::FFragment_NavSurface_LinkTraversal_Current>());
    }

    // What one waypoint advance costs: the cursor moves, the requests it raised are drained.
    auto DoStep_Cursor(
        ck::FEcsWorld&                       InWorld,
        FCk_Handle&                          InTraverser,
        ck::FFragment_CrowdAgent_PathFollow& InPathFollow,
        int32                                InCursor) -> void
    {
        ck::FProcessor_CrowdAgent_Steering::DoDriveLinkTraversalCursor(
            InTraverser, InPathFollow, InCursor, kWaypointCount);

        DoDrain_TraversalRequests(InWorld, InTraverser);
    }

    // The whole fixture: a registry, one entity in it, and the path-follow state a ground install would
    // have left on that entity.
    struct FLinkCursorFixture
    {
    public:
        ck::FEcsWorld World;
        FCk_Handle Agent;
        ck::FFragment_CrowdAgent_PathFollow PathFollow;

    public:
        auto Setup() -> bool
        {
            Agent = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
            return ck::IsValid(Agent);
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_InstallStampsLinkSpans,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.InstallStampsLinkSpans",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_InstallStampsLinkSpans::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto PathFollow = ck::FFragment_CrowdAgent_PathFollow{};

    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(PathFollow, Make_OneCrossingResult());

    if (NOT TestEqual(TEXT("one crossing on the route is one span on the agent"),
            PathFollow.Get_LinkSpans().Num(), 1))
    { return false; }

    const auto& Span = PathFollow.Get_LinkSpans()[0];

    TestEqual(TEXT("naming the link the route crossed"), Span.Get_LinkId(), kLadderLinkId);
    TestEqual(TEXT("the waypoint it steps on at"), Span.Get_EntryWaypointIndex(), kEntryWaypointIndex);
    TestEqual(TEXT("and the one it steps off at"), Span.Get_ExitWaypointIndex(), kExitWaypointIndex);

    // The distances are the plan's own integrated ones. A span that recomputed them from the polyline
    // would be a second definition of the route's length.
    TestEqual(TEXT("carrying the plan's own entry distance"),
        Span.Get_EntryDistanceUu(), static_cast<float>(kEntryWaypointIndex) * 100.0f);

    TestTrue(TEXT("and the way in the plan decided at the entry"),
        Span.Get_EntryDirection() == ECk_GroundNav_LinkDirection::Forward);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_InstallWithoutLinksStampsNothing,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.InstallWithoutLinksStampsNothing",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_InstallWithoutLinksStampsNothing::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto PathFollow = ck::FFragment_CrowdAgent_PathFollow{};

    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(PathFollow, Make_OneCrossingResult());

    TestEqual(TEXT("the first route left a span behind"), PathFollow.Get_LinkSpans().Num(), 1);

    // The second install is the load-bearing half: a route that crosses nothing must not leave the
    // PREVIOUS route's spans standing, or the cursor would begin crossings on a corridor with no links
    // on it at all.
    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(PathFollow, Make_Result({}));

    TestEqual(TEXT("and a route across no link stamps an empty array over it"),
        PathFollow.Get_LinkSpans().Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_CursorOntoEntryBeginsExactlyOnce,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.CursorOntoEntryBeginsExactlyOnce",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_CursorOntoEntryBeginsExactlyOnce::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto Fixture = FLinkCursorFixture{};
    if (NOT TestTrue(TEXT("the fixture hands out a valid agent"), Fixture.Setup()))
    { return false; }

    const auto Signals = Make_TraversalListener(Fixture.Agent);

    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(Fixture.PathFollow, Make_OneCrossingResult());

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, 0);
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, 1);

    TestEqual(TEXT("ground before the link begins nothing"), Signals->_BegunLinkIds.Num(), 0);

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kEntryWaypointIndex);

    if (NOT TestEqual(TEXT("stepping onto the entry begins the crossing"),
            Signals->_BegunLinkIds.Num(), 1))
    { return false; }

    TestEqual(TEXT("naming the link"), Signals->_BegunLinkIds[0], kLadderLinkId);

    TestEqual(TEXT("and the correlator the route and the link derive"),
        Signals->_BegunCorrelatorIds[0],
        ck::FProcessor_CrowdAgent_Steering::Get_LinkTraversalCorrelator(
            Fixture.PathFollow, kLadderLinkId));

    // A frame in which nothing advanced, and one that advanced onto the exit: neither leaves the span,
    // and neither may re-announce the crossing already running.
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kEntryWaypointIndex);
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kExitWaypointIndex);

    TestEqual(TEXT("and staying on the link begins nothing further"),
        Signals->_BegunLinkIds.Num(), 1);

    TestEqual(TEXT("nothing has ended"), Signals->_CompletedLinkIds.Num(), 0);

    TestTrue(TEXT("the agent reads as traversing"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Fixture.Agent));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_CursorPastExitCompletesExactlyOnce,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.CursorPastExitCompletesExactlyOnce",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_CursorPastExitCompletesExactlyOnce::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto Fixture = FLinkCursorFixture{};
    if (NOT TestTrue(TEXT("the fixture hands out a valid agent"), Fixture.Setup()))
    { return false; }

    const auto Signals = Make_TraversalListener(Fixture.Agent);

    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(Fixture.PathFollow, Make_OneCrossingResult());

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kEntryWaypointIndex);
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kExitWaypointIndex);

    TestEqual(TEXT("the crossing is running"), Signals->_BegunLinkIds.Num(), 1);
    TestEqual(TEXT("and has not ended on its own exit"), Signals->_CompletedLinkIds.Num(), 0);

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kExitWaypointIndex + 1);

    if (NOT TestEqual(TEXT("walking off the far end ends the crossing"),
            Signals->_CompletedLinkIds.Num(), 1))
    { return false; }

    TestEqual(TEXT("naming the link"), Signals->_CompletedLinkIds[0], kLadderLinkId);
    TestEqual(TEXT("and the correlator the begin named"),
        Signals->_CompletedCorrelatorIds[0], Signals->_BegunCorrelatorIds[0]);

    // Succeeded, not Cancelled: the body ARRIVED at the far end, which is the whole difference a
    // listener deciding what to do next is reading.
    TestTrue(TEXT("reporting the crossing was finished"),
        Signals->_CompletedResults[0] == ECk_Request_OperationResult::Succeeded);

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kWaypointCount - 1);
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kWaypointCount);

    TestEqual(TEXT("and walking the rest of the route ends nothing further"),
        Signals->_CompletedLinkIds.Num(), 1);

    TestEqual(TEXT("nor begins anything"), Signals->_BegunLinkIds.Num(), 1);

    TestFalse(TEXT("the agent is off the link"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Fixture.Agent));

    TestFalse(TEXT("and carries no traversing tag"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_RouteSwapMidTraversalCancels,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.RouteSwapMidTraversalCancels",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_RouteSwapMidTraversalCancels::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto Fixture = FLinkCursorFixture{};
    if (NOT TestTrue(TEXT("the fixture hands out a valid agent"), Fixture.Setup()))
    { return false; }

    const auto Signals = Make_TraversalListener(Fixture.Agent);

    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(Fixture.PathFollow, Make_OneCrossingResult());

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kEntryWaypointIndex);

    TestEqual(TEXT("the agent is on the ladder"), Signals->_BegunLinkIds.Num(), 1);

    // Exactly what the ground install does when a rebuild replan lands mid-walk: the crossing belonged
    // to the polyline being replaced, and the fresh route stamps its own spans over it.
    ck::FProcessor_CrowdAgent_Steering::DoCancelActiveLinkTraversal(Fixture.Agent, Fixture.PathFollow);
    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(Fixture.PathFollow, Make_Result({}));

    DoDrain_TraversalRequests(Fixture.World, Fixture.Agent);

    if (NOT TestEqual(TEXT("a swap mid-ladder ends the crossing"),
            Signals->_CompletedLinkIds.Num(), 1))
    { return false; }

    TestTrue(TEXT("reporting it was abandoned rather than finished"),
        Signals->_CompletedResults[0] == ECk_Request_OperationResult::Failed_Cancelled);

    TestEqual(TEXT("the agent records no crossing"),
        Fixture.PathFollow.Get_ActiveLinkCorrelator(), static_cast<int32>(INDEX_NONE));

    TestFalse(TEXT("and carries no traversing tag"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    // The replacement corridor crosses nothing, so walking it must not resurrect the abandoned one.
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kEntryWaypointIndex);
    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, kExitWaypointIndex + 1);

    TestEqual(TEXT("the new route begins nothing"), Signals->_BegunLinkIds.Num(), 1);
    TestEqual(TEXT("and ends nothing"), Signals->_CompletedLinkIds.Num(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_AgentStaysWalkingWhileTraversing,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.AgentStaysWalkingWhileTraversing",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_AgentStaysWalkingWhileTraversing::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto Fixture = FLinkCursorFixture{};
    if (NOT TestTrue(TEXT("the fixture hands out a valid agent"), Fixture.Setup()))
    { return false; }

    // The movement triple is exclusive and the crossing tag is not part of it: an agent on a ladder is
    // still walking the polyline it was handed. Dropping out of Walking to cross would make every link
    // a visible stall by the same measure the rebuild pin uses.
    Fixture.Agent.AddOrGet<ck::FTag_CrowdAgent_Walking>();

    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(Fixture.PathFollow, Make_OneCrossingResult());

    auto NonWalkingSteps = 0;

    for (auto Cursor = 0; Cursor <= kWaypointCount; ++Cursor)
    {
        DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, Cursor);

        if (NOT Fixture.Agent.Has<ck::FTag_CrowdAgent_Walking>())
        { ++NonWalkingSteps; }
    }

    TestEqual(TEXT("the agent never leaves Walking to cross a link"), NonWalkingSteps, 0);

    TestFalse(TEXT("and is on no link once the route is walked out"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_LinkTraversal_TraversingTagTracksTheActiveSpan,
    "CkTests.UnitTests.CkCrowd.LinkTraversal.TraversingTagTracksTheActiveSpan",
    kCkUnitTestFlags)

bool FCkTest_Crowd_LinkTraversal_TraversingTagTracksTheActiveSpan::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_link_traversal;

    auto Fixture = FLinkCursorFixture{};
    if (NOT TestTrue(TEXT("the fixture hands out a valid agent"), Fixture.Setup()))
    { return false; }

    const auto Signals = Make_TraversalListener(Fixture.Agent);

    // Two crossings on one route, back to back: waypoints 1-2 on the ladder, 3-4 on the second link.
    // Adjacent on purpose - the cursor leaves one span and enters the next in the same advance, which
    // is where a driver that ended a crossing without starting the next would be caught.
    ck::FProcessor_CrowdAgent_Steering::DoStampLinkSpans(Fixture.PathFollow, Make_Result({
        Make_LinkWaypoint(1, kLadderLinkId,
            ECk_GroundNavPath_LinkWaypointRole::Entry, ECk_GroundNav_LinkDirection::Forward),
        Make_LinkWaypoint(2, kLadderLinkId,
            ECk_GroundNavPath_LinkWaypointRole::Exit, ECk_GroundNav_LinkDirection::Forward),
        Make_LinkWaypoint(3, kSecondLinkId,
            ECk_GroundNavPath_LinkWaypointRole::Entry, ECk_GroundNav_LinkDirection::Backward),
        Make_LinkWaypoint(4, kSecondLinkId,
            ECk_GroundNavPath_LinkWaypointRole::Exit, ECk_GroundNav_LinkDirection::Backward)}));

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, 0);

    TestFalse(TEXT("ground before the first link carries no tag"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, 1);

    TestTrue(TEXT("the first crossing tags the agent"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    TestEqual(TEXT("and the active link is the one the cursor stands on"),
        Fixture.PathFollow.Get_ActiveLinkId(), kLadderLinkId);

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, 3);

    TestTrue(TEXT("the second crossing keeps the agent tagged"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    TestEqual(TEXT("and the active link follows the cursor onto it"),
        Fixture.PathFollow.Get_ActiveLinkId(), kSecondLinkId);

    // One begin and one end each, in order: the first crossing was FINISHED before the second started.
    TestEqual(TEXT("two crossings begin"), Signals->_BegunLinkIds.Num(), 2);
    TestEqual(TEXT("in route order"), Signals->_BegunLinkIds[1], kSecondLinkId);

    if (TestEqual(TEXT("and the first one ends"), Signals->_CompletedLinkIds.Num(), 1))
    {
        TestEqual(TEXT("naming the link left behind"),
            Signals->_CompletedLinkIds[0], kLadderLinkId);

        TestTrue(TEXT("and reporting it was walked off rather than abandoned"),
            Signals->_CompletedResults[0] == ECk_Request_OperationResult::Succeeded);
    }

    DoStep_Cursor(Fixture.World, Fixture.Agent, Fixture.PathFollow, 5);

    TestFalse(TEXT("ground past the last link carries no tag"),
        Fixture.Agent.Has<ck::FTag_CrowdAgent_TraversingLink>());

    TestEqual(TEXT("and the agent records no crossing"),
        Fixture.PathFollow.Get_ActiveLinkId(), static_cast<int32>(INDEX_NONE));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
