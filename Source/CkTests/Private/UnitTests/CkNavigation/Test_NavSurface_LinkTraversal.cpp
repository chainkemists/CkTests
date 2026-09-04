// The neutral link-traversal handshake: what a Begin, a Complete and a Cancel do to the traverser, and
// what each of them reports.
//
// The drain is invoked directly, as the markup and GroundNav admission tests invoke theirs: a headless
// registry has no scheduler, so a request can be enqueued and stepped exactly one pass at a time - which
// is the only way to state "exactly once" as a fact about a single drain rather than about whatever the
// frame happened to contain.
//
// No world, no provider and no navmesh appear here, and that is the contract rather than a shortcut:
// crossing a link changes no geometry, so the handshake consults no provider and needs nothing published.
//
// What is NOT covered here: an agent driving the handshake off its own waypoint cursor, which needs a
// built field and is therefore a PIE pin.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/Signal/CkSignal_Fragment_Data.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"
#include "CkNavigation/NavSurface/CkNavSurface_Processor.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "CkTest_LinkTraversalListener.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include <UObject/StrongObjectPtr.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_nav_surface_link_traversal
{
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    // Distinct primes so a payload that carried the link id where the correlator belonged, or vice
    // versa, cannot read as correct.
    constexpr auto kLadderLinkId = int32{7};
    constexpr auto kLadderCorrelatorId = int32{101};
    constexpr auto kOtherLinkId = int32{13};
    constexpr auto kOtherCorrelatorId = int32{307};

    auto Make_CompletionListener() -> TStrongObjectPtr<UCk_Test_CompletionListener_UE>
    {
        return TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
            NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};
    }

    auto Make_CompletionDelegate(
        UCk_Test_CompletionListener_UE* InListener) -> FCk_Delegate_Request_OnCompleted
    {
        auto Delegate = FCk_Delegate_Request_OnCompleted{};
        Delegate.BindDynamic(InListener, &UCk_Test_CompletionListener_UE::OnRequestCompleted);
        return Delegate;
    }

    // Bound with IgnorePayloadInFlight so the listener observes only broadcasts made after it attached -
    // a replay would make "exactly once" unfalsifiable.
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

    auto Make_BeginRequest(
        int32 InLinkId,
        int32 InCorrelatorId) -> FCk_Request_NavSurface_BeginLinkTraversal
    {
        return FCk_Request_NavSurface_BeginLinkTraversal{InLinkId, InCorrelatorId};
    }

    auto DoDrain_TraversalRequests(
        ck::FEcsWorld& InWorld,
        FCk_Handle&    InTraverser) -> void
    {
        ck::FProcessor_NavSurface_LinkTraversal_HandleRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InTraverser,
            InTraverser.Get<ck::FFragment_NavSurface_LinkTraversal_Requests>(),
            InTraverser.Get<ck::FFragment_NavSurface_LinkTraversal_Current>());
    }

    auto DoRun_EndPlay(
        FCk_Handle& InTraverser) -> void
    {
        ck::FProcessor_NavSurface_LinkTraversal_EndPlay::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InTraverser,
            InTraverser.Get<ck::FFragment_NavSurface_LinkTraversal_Current>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_BeginFiresBegunExactlyOnce,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.BeginFiresBegunExactlyOnce",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_BeginFiresBegunExactlyOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the traverser exists"), ck::IsValid(Traverser)))
    { return false; }

    const auto Signals = Make_TraversalListener(Traverser);
    const auto Completions = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId),
        Make_CompletionDelegate(Completions.Get()));

    TestEqual(TEXT("enqueuing broadcasts nothing - the drain owns delivery"),
        Signals->_BegunLinkIds.Num(), 0);

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("one Begin is one Begun"), Signals->_BegunLinkIds.Num(), 1);
    TestEqual(TEXT("carrying the link it named"), Signals->_BegunLinkIds[0], kLadderLinkId);
    TestEqual(TEXT("and the correlator it named"), Signals->_BegunCorrelatorIds[0], kLadderCorrelatorId);

    TestEqual(TEXT("nothing has ended"), Signals->_CompletedLinkIds.Num(), 0);

    TestEqual(TEXT("the request completes exactly once"),
        Completions->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Completions->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestTrue(TEXT("and the traverser is on the link"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Traverser));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_BeginWithTheActiveCorrelatorIsSucceededAndSilent,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.BeginWithTheActiveCorrelatorIsSucceededAndSilent",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_BeginWithTheActiveCorrelatorIsSucceededAndSilent::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId), {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Repeat = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId),
        Make_CompletionDelegate(Repeat.Get()));

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("the repeated Begin completes exactly once"),
        Repeat->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded - the caller's intent already holds"),
        Repeat->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestEqual(TEXT("and no second Begun is broadcast"), Signals->_BegunLinkIds.Num(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_BeginWithAnotherCorrelatorFailsAndKeepsTheActiveOne,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.BeginWithAnotherCorrelatorFailsAndKeepsTheActiveOne",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_BeginWithAnotherCorrelatorFailsAndKeepsTheActiveOne::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId), {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Intruder = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kOtherLinkId, kOtherCorrelatorId),
        Make_CompletionDelegate(Intruder.Get()));

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("the second Begin completes exactly once"),
        Intruder->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed - one link at a time"),
        Intruder->_LastRequestResult == ECk_Request_OperationResult::Failed);

    TestEqual(TEXT("no second Begun is broadcast"), Signals->_BegunLinkIds.Num(), 1);
    TestEqual(TEXT("and the refused crossing does not end the running one"),
        Signals->_CompletedLinkIds.Num(), 0);

    const auto Traversal = UCk_Utils_NavSurface_LinkTraversal_UE::Get_LinkTraversal(Traverser);

    TestEqual(TEXT("the original link is still the one being crossed"),
        Traversal.Get_LinkId(), kLadderLinkId);
    TestEqual(TEXT("under the original correlator"),
        Traversal.Get_CorrelatorId(), kLadderCorrelatorId);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_CompleteFiresCompletedExactlyOnce,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.CompleteFiresCompletedExactlyOnce",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_CompleteFiresCompletedExactlyOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId), {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Completions = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_CompleteLinkTraversal(Traverser,
        FCk_Request_NavSurface_CompleteLinkTraversal{kLadderCorrelatorId},
        Make_CompletionDelegate(Completions.Get()));

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("one Complete is one Completed"), Signals->_CompletedLinkIds.Num(), 1);
    TestEqual(TEXT("carrying the link that was crossed"),
        Signals->_CompletedLinkIds[0], kLadderLinkId);
    TestEqual(TEXT("and the correlator that named the crossing"),
        Signals->_CompletedCorrelatorIds[0], kLadderCorrelatorId);
    TestTrue(TEXT("reporting Succeeded, which is how a listener tells an arrival from an abort"),
        Signals->_CompletedResults[0] == ECk_Request_OperationResult::Succeeded);

    TestEqual(TEXT("the request completes exactly once"),
        Completions->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Completions->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestFalse(TEXT("and the traverser is off the link"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Traverser));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_CompleteForAnInactiveCorrelatorFails,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.CompleteForAnInactiveCorrelatorFails",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_CompleteForAnInactiveCorrelatorFails::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId), {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Stranger = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_CompleteLinkTraversal(Traverser,
        FCk_Request_NavSurface_CompleteLinkTraversal{kOtherCorrelatorId},
        Make_CompletionDelegate(Stranger.Get()));

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("the stray Complete completes exactly once"),
        Stranger->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed - that crossing is not the one running"),
        Stranger->_LastRequestResult == ECk_Request_OperationResult::Failed);

    TestEqual(TEXT("nothing is reported as ended"), Signals->_CompletedLinkIds.Num(), 0);
    TestTrue(TEXT("and the running crossing survives"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Traverser));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_CancelCompletesFailedCancelled,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.CancelCompletesFailedCancelled",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_CancelCompletesFailedCancelled::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId), {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Cancels = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_CancelLinkTraversal(Traverser,
        FCk_Request_NavSurface_CancelLinkTraversal{kLadderCorrelatorId},
        Make_CompletionDelegate(Cancels.Get()));

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("the crossing reports an end"), Signals->_CompletedLinkIds.Num(), 1);
    TestTrue(TEXT("as Failed_Cancelled, which is what separates an abort from an arrival"),
        Signals->_CompletedResults[0] == ECk_Request_OperationResult::Failed_Cancelled);

    // The cancel itself succeeded; only the CROSSING failed. Collapsing the two would leave a caller
    // unable to tell "I could not cancel" from "I cancelled a crossing that never arrived".
    TestEqual(TEXT("the cancel request completes exactly once"),
        Cancels->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Cancels->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestFalse(TEXT("and the traverser is off the link"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Traverser));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_CancelForAnInactiveCorrelatorIsSucceeded,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.CancelForAnInactiveCorrelatorIsSucceeded",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_CancelForAnInactiveCorrelatorIsSucceeded::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);
    const auto Cancels = Make_CompletionListener();

    // Nothing was ever begun on this entity, so the fragments compose here for the first time and the
    // cancel has nothing to abandon.
    UCk_Utils_NavSurface_LinkTraversal_UE::Request_CancelLinkTraversal(Traverser,
        FCk_Request_NavSurface_CancelLinkTraversal{kOtherCorrelatorId},
        Make_CompletionDelegate(Cancels.Get()));

    DoDrain_TraversalRequests(World, Traverser);

    TestEqual(TEXT("the cancel completes exactly once"),
        Cancels->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded - the caller's intent holds afterwards"),
        Cancels->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestEqual(TEXT("and nothing is reported as ended"), Signals->_CompletedLinkIds.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_EndPlayCancelsActiveAndPending,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.EndPlayCancelsActiveAndPending",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_EndPlayCancelsActiveAndPending::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId), {});

    DoDrain_TraversalRequests(World, Traverser);

    // Left in the queue on purpose: this is the request nobody drained, and its caller is owed an
    // answer as much as the crossing's listener is.
    const auto Pending = Make_CompletionListener();

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_CompleteLinkTraversal(Traverser,
        FCk_Request_NavSurface_CompleteLinkTraversal{kLadderCorrelatorId},
        Make_CompletionDelegate(Pending.Get()));

    DoRun_EndPlay(Traverser);

    TestEqual(TEXT("the undrained request completes exactly once"),
        Pending->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed_Cancelled"),
        Pending->_LastRequestResult == ECk_Request_OperationResult::Failed_Cancelled);

    TestEqual(TEXT("the live crossing reports an end"), Signals->_CompletedLinkIds.Num(), 1);
    TestEqual(TEXT("naming the link it was on"),
        Signals->_CompletedLinkIds[0], kLadderLinkId);
    TestTrue(TEXT("as Failed_Cancelled - the body never came off the ladder"),
        Signals->_CompletedResults[0] == ECk_Request_OperationResult::Failed_Cancelled);

    TestFalse(TEXT("and nothing is left traversing"),
        UCk_Utils_NavSurface_LinkTraversal_UE::Get_IsTraversingLink(Traverser));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_InvalidLinkIdIsFailedNotEnqueued,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.InvalidLinkIdIsFailedNotEnqueued",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_InvalidLinkIdIsFailedNotEnqueued::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Signals = Make_TraversalListener(Traverser);
    const auto Rejected = Make_CompletionListener();

    AddExpectedError(TEXT("names no link"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser,
        Make_BeginRequest(INDEX_NONE, kLadderCorrelatorId),
        Make_CompletionDelegate(Rejected.Get()));

    TestEqual(TEXT("the rejection completes on the caller's own stack, exactly once"),
        Rejected->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed_NotEnqueued"),
        Rejected->_LastRequestResult == ECk_Request_OperationResult::Failed_NotEnqueued);

    TestFalse(TEXT("nothing was queued"),
        Traverser.Has<ck::FFragment_NavSurface_LinkTraversal_Requests>());
    TestEqual(TEXT("and nothing was broadcast"), Signals->_BegunLinkIds.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_LinkTraversal_ReadBackReflectsTheActiveTraversal,
    "CkTests.UnitTests.CkNavigation.LinkTraversal.ReadBackReflectsTheActiveTraversal",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_LinkTraversal_ReadBackReflectsTheActiveTraversal::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_link_traversal;

    auto World = ck::FEcsWorld{};
    auto Traverser = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    // An entity nothing has composed reads the same None as one whose crossing ended, so a caller
    // never has to ask whether the feature is there.
    const auto Fresh = UCk_Utils_NavSurface_LinkTraversal_UE::Get_LinkTraversal(Traverser);

    TestTrue(TEXT("an untouched entity is crossing nothing"),
        Fresh.Get_State() == ECk_NavSurface_LinkTraversalState::None);
    TestEqual(TEXT("and names no link"), Fresh.Get_LinkId(), int32{INDEX_NONE});

    auto Request = Make_BeginRequest(kLadderLinkId, kLadderCorrelatorId);
    Request.Set_EntryDirection(ECk_NavSurface_LinkEntryDirection::Backward);

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_BeginLinkTraversal(Traverser, Request, {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Active = UCk_Utils_NavSurface_LinkTraversal_UE::Get_LinkTraversal(Traverser);

    TestTrue(TEXT("the read-back reports the crossing"),
        Active.Get_State() == ECk_NavSurface_LinkTraversalState::Traversing);
    TestEqual(TEXT("the link it is on"), Active.Get_LinkId(), kLadderLinkId);
    TestEqual(TEXT("the correlator naming it"), Active.Get_CorrelatorId(), kLadderCorrelatorId);
    TestTrue(TEXT("and the end it was entered from"),
        Active.Get_EntryDirection() == ECk_NavSurface_LinkEntryDirection::Backward);

    TestTrue(TEXT("a view can filter on the same fact"),
        Traverser.Has<ck::FTag_NavSurface_LinkTraversal_Active>());

    UCk_Utils_NavSurface_LinkTraversal_UE::Request_CompleteLinkTraversal(Traverser,
        FCk_Request_NavSurface_CompleteLinkTraversal{kLadderCorrelatorId}, {});

    DoDrain_TraversalRequests(World, Traverser);

    const auto Ended = UCk_Utils_NavSurface_LinkTraversal_UE::Get_LinkTraversal(Traverser);

    TestTrue(TEXT("an ended crossing reads None"),
        Ended.Get_State() == ECk_NavSurface_LinkTraversalState::None);
    TestEqual(TEXT("and carries no ids"), Ended.Get_LinkId(), int32{INDEX_NONE});
    TestFalse(TEXT("and the filter tag is gone"),
        Traverser.Has<ck::FTag_NavSurface_LinkTraversal_Active>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
