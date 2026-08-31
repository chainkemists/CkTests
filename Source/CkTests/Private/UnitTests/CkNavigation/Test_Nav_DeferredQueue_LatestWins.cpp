// The deferred-FindPath queue's latest-request-wins coalescing, and the revision ring it is built
// on. Both are pure value logic over a caller-owned array, so this needs no world and no registry:
// the handles here are identity tokens that AddDeferredLatest only ever compares.
//
// Cancellation is asserted as queue membership — the older entry is gone, or the newer one was
// never added. The completion CALLBACK is not observed: FCk_Delegate_Request_OnCompleted is a
// dynamic delegate and would need a UObject receiver, which would make this test heavier than the
// logic it pins.

#include "CkNavigation/Nav/CkNav_Fragment.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_nav_deferred_queue
{
    auto Make_Handle(int32 InEntityId) -> FCk_Handle
    {
        return FCk_Handle{FCk_Entity{static_cast<FCk_Entity::IdType>(InEntityId)}, FCk_RegistryHandle{}};
    }

    auto Add(
        TArray<ck::FNav_DeferredRequest>& InOutQueue,
        const FCk_Handle& InHandle,
        int32 InRevision) -> void
    {
        auto Request = FCk_Request_Nav_FindPath{FVector::ZeroVector};
        Request.Set_RequestRevision(InRevision);

        ck::nav::AddDeferredLatest(InOutQueue, InHandle, Request, 0.0);
    }

    auto TestQueue(
        FAutomationTestBase& InTest,
        const TCHAR* InWhat,
        const TArray<ck::FNav_DeferredRequest>& InQueue,
        const TArray<int32>& InExpectedRevisions) -> void
    {
        InTest.TestEqual(FString::Printf(TEXT("%s — parked entry count"), InWhat),
            InQueue.Num(), InExpectedRevisions.Num());

        if (InQueue.Num() != InExpectedRevisions.Num())
        { return; }

        for (auto Index = 0; Index < InExpectedRevisions.Num(); ++Index)
        {
            InTest.TestEqual(FString::Printf(TEXT("%s — entry %d revision"), InWhat, Index),
                InQueue[Index].Request.Get_RequestRevision(), InExpectedRevisions[Index]);
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Nav_DeferredQueue_RevisionRing,
    "CkTests.UnitTests.CkNavigation.DeferredQueue.RevisionRing",
    kCkUnitTestFlags)

bool FCkTest_Nav_DeferredQueue_RevisionRing::RunTest(const FString& Parameters)
{
    using ck::nav::IsNewerRevision;

    TestFalse(TEXT("a revision is never newer than itself"), IsNewerRevision(7, 7));
    TestFalse(TEXT("the ring's first revision is not newer than itself"), IsNewerRevision(1, 1));
    TestFalse(TEXT("the ring's last revision is not newer than itself"),
        IsNewerRevision(MAX_int32, MAX_int32));

    TestTrue(TEXT("the immediate successor is newer"), IsNewerRevision(8, 7));
    TestFalse(TEXT("the immediate predecessor is older"), IsNewerRevision(7, 8));
    TestTrue(TEXT("a far-but-under-half-space successor is newer"), IsNewerRevision(1000, 1));
    TestFalse(TEXT("its mirror is older"), IsNewerRevision(1, 1000));

    // The wrap case: MAX_int32 is the last revision on the ring, so 1 is its successor rather than
    // its distant predecessor. A plain `>` comparison gets exactly this pair backwards.
    TestTrue(TEXT("wrapping past MAX_int32 back to 1 reads as newer"),
        IsNewerRevision(1, MAX_int32));
    TestFalse(TEXT("and MAX_int32 is older than the revision that wrapped past it"),
        IsNewerRevision(MAX_int32, 1));

    TestTrue(TEXT("a short forward hop across the wrap is newer"),
        IsNewerRevision(5, MAX_int32 - 5));
    TestFalse(TEXT("and its mirror is older"),
        IsNewerRevision(MAX_int32 - 5, 5));

    // The half-space boundary is what makes the ring unambiguous: strictly less than half the space
    // forward is newer, half or more is the opposite generation.
    constexpr auto HalfSpace = static_cast<int32>(static_cast<int64>(MAX_int32) / 2);
    TestTrue(TEXT("one short of the half space is still newer"), IsNewerRevision(HalfSpace, 1));
    TestFalse(TEXT("the half space itself is not"), IsNewerRevision(HalfSpace + 1, 1));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Nav_DeferredQueue_LatestWinsCoalescing,
    "CkTests.UnitTests.CkNavigation.DeferredQueue.LatestWinsCoalescing",
    kCkUnitTestFlags)

bool FCkTest_Nav_DeferredQueue_LatestWinsCoalescing::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_deferred_queue;

    const auto Agent = Make_Handle(1);
    const auto OtherAgent = Make_Handle(2);

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 5);
        Add(Queue, Agent, 6);
        TestQueue(*this, TEXT("a newer revision evicts the parked one"), Queue, {6});
    }

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 6);
        Add(Queue, Agent, 5);
        TestQueue(*this, TEXT("an older revision is rejected outright"), Queue, {6});
    }

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 7);
        Add(Queue, Agent, 7);
        TestQueue(*this, TEXT("an identical revision is not newer, so it is rejected"), Queue, {7});
    }

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, MAX_int32);
        Add(Queue, Agent, 1);
        TestQueue(*this, TEXT("a revision that wrapped past MAX_int32 supersedes it"), Queue, {1});
    }

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 1);
        Add(Queue, Agent, MAX_int32);
        TestQueue(*this, TEXT("and the wrapped revision is not evicted by the one it lapped"),
            Queue, {1});
    }

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 3);
        Add(Queue, OtherAgent, 1);
        Add(Queue, Agent, 4);
        TestQueue(*this, TEXT("coalescing is per entity — another agent's entry is left alone"),
            Queue, {1, 4});
    }

    {
        // Revision zero opts OUT of latest-wins: those callers want every request answered, so
        // neither side of a zero pairing may cancel the other.
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 0);
        Add(Queue, Agent, 0);
        TestQueue(*this, TEXT("unrevisioned requests never coalesce with each other"), Queue, {0, 0});
    }

    {
        auto Queue = TArray<ck::FNav_DeferredRequest>{};
        Add(Queue, Agent, 0);
        Add(Queue, Agent, 9);
        TestQueue(*this, TEXT("a revisioned request does not evict an unrevisioned one"),
            Queue, {0, 9});
    }

    return true;
}
