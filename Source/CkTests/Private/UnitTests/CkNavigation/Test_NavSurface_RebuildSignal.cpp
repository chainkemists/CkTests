// The two halves of OnSurfaceRebuilt: the pushed queue a provider fills with the regions it rebuilt,
// and the polled revision counter that stands in for a provider which never says where.
//
// Both are asked of the watch processor directly. A headless world has no navmesh and no scheduler, so
// the drain can be stepped exactly one tick at a time and the queue read back afterwards - which is the
// only way to state "one broadcast per publish, in order, and the list is empty afterwards" as a fact
// about a single pass rather than about whatever the frame happened to contain.
//
// The revision half cannot be driven the same way: Recast's counter advances only on the engine's
// navigation-generation-finished event, which needs a built navmesh and therefore a PIE world (the AS
// test CkAutoTest_NavSurface_RebuildAdvancesRevisionAndSignals covers that path end to end). What is
// asked here is the rule the counter feeds: a move past the last broadcast produces exactly one
// bounds-unknown broadcast, and standing still produces none.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/Signal/CkSignal_Macros.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Processor.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "CkTest_RebuiltListener.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
#include <UObject/StrongObjectPtr.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_nav_surface_rebuild_signal
{
    constexpr auto InformEngineOfWorld = false;
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    struct FWatchFixture
    {
        UWorld* _World = nullptr;
        FCk_Handle _WorldEntity;
        TStrongObjectPtr<UCk_Test_NavSurfaceRebuiltListener_UE> _Listener;
    };

    // The fragments the watch drives are seeded by its DoTick, which needs a scheduler. Adding them here
    // is that seeding, done by hand.
    auto Make_Fixture(
        const TCHAR* InWorldName) -> FWatchFixture
    {
        auto Fixture = FWatchFixture{};

        Fixture._World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, FName{InWorldName});
        if (Fixture._World == nullptr)
        { return Fixture; }

        Fixture._WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Fixture._World);
        if (ck::Is_NOT_Valid(Fixture._WorldEntity))
        { return Fixture; }

        Fixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_Provider>();
        Fixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_RevisionWatch>();
        Fixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_PendingRebuilds>();

        Fixture._Listener = TStrongObjectPtr<UCk_Test_NavSurfaceRebuiltListener_UE>{
            NewObject<UCk_Test_NavSurfaceRebuiltListener_UE>()};

        auto Delegate = FCk_Delegate_NavSurface_OnSurfaceRebuilt{};
        Delegate.BindUFunction(Fixture._Listener.Get(), TEXT("OnSurfaceRebuilt"));

        CK_SIGNAL_BIND(ck::UUtils_Signal_NavSurface_OnSurfaceRebuilt, Fixture._WorldEntity, Delegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        return Fixture;
    }

    auto Destroy_Fixture(
        FWatchFixture& InFixture) -> void
    {
        InFixture._Listener.Reset();

        if (InFixture._World != nullptr)
        { InFixture._World->DestroyWorld(InformEngineOfWorld); }
    }

    auto Run_Watch(
        FWatchFixture& InFixture) -> void
    {
        ck::FProcessor_NavSurface_RevisionWatch::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InFixture._WorldEntity,
            InFixture._WorldEntity.Get<ck::FFragment_NavSurface_Provider>(),
            InFixture._WorldEntity.Get<ck::FFragment_NavSurface_RevisionWatch>(),
            InFixture._WorldEntity.Get<ck::FFragment_NavSurface_PendingRebuilds>());
    }

    auto Get_PendingCount(
        FWatchFixture& InFixture) -> int32
    {
        return InFixture._WorldEntity.Get<ck::FFragment_NavSurface_PendingRebuilds>().Get_Bounds().Num();
    }

    // Distinct, non-overlapping and ordered along X, so a collapsed or reordered delivery cannot be
    // mistaken for a correct one.
    auto Make_Region(
        int32 InIndex) -> FBox
    {
        const auto MinX = static_cast<double>(InIndex) * 1000.0;

        return FBox{FVector{MinX, 0.0, 0.0}, FVector{MinX + 100.0, 100.0, 100.0}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_RebuiltFiresExactlyOncePerQueuedPublish,
    "CkTests.UnitTests.CkNavigation.NavSurface.RebuiltFiresExactlyOncePerQueuedPublish",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_RebuiltFiresExactlyOncePerQueuedPublish::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_rebuild_signal;

    constexpr auto PublishCount = 3;

    auto Fixture = Make_Fixture(TEXT("CkNavSurfaceRebuiltPerPublish"));

    if (NOT TestTrue(TEXT("the probe world has an ECS transient entity to watch"),
        ck::IsValid(Fixture._WorldEntity)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    for (auto Index = 0; Index < PublishCount; ++Index)
    {
        ck::nav_surface::Request_NotifySurfaceRebuilt(Fixture._World, Make_Region(Index));
    }

    TestEqual(TEXT("a publish queues without broadcasting - the drain owns delivery"),
        Fixture._Listener->_ObservedBounds.Num(), 0);

    TestEqual(TEXT("every publish is parked, none coalesced"),
        Get_PendingCount(Fixture), PublishCount);

    Run_Watch(Fixture);

    if (NOT TestEqual(TEXT("one drain delivers one broadcast per publish"),
        Fixture._Listener->_ObservedBounds.Num(), PublishCount))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    for (auto Index = 0; Index < PublishCount; ++Index)
    {
        TestTrue(FString::Printf(TEXT("broadcast %d carries the region published %dth"), Index, Index),
            Fixture._Listener->_ObservedBounds[Index] == Make_Region(Index));
    }

    TestEqual(TEXT("and the queue is empty afterwards"), Get_PendingCount(Fixture), 0);

    Destroy_Fixture(Fixture);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_RebuiltDrainsToEmptyAndRefiresNothing,
    "CkTests.UnitTests.CkNavigation.NavSurface.RebuiltDrainsToEmptyAndRefiresNothing",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_RebuiltDrainsToEmptyAndRefiresNothing::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_rebuild_signal;

    auto Fixture = Make_Fixture(TEXT("CkNavSurfaceRebuiltDrainsToEmpty"));

    if (NOT TestTrue(TEXT("the probe world has an ECS transient entity to watch"),
        ck::IsValid(Fixture._WorldEntity)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    ck::nav_surface::Request_NotifySurfaceRebuilt(Fixture._World, Make_Region(0));

    Run_Watch(Fixture);

    if (NOT TestEqual(TEXT("the publish is delivered once"),
        Fixture._Listener->_ObservedBounds.Num(), 1))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    // Nothing was published in between, so a second pass has nothing to say. A drain that re-read what it
    // had already delivered would invalidate every listener's caches again for a change that is over.
    Run_Watch(Fixture);
    Run_Watch(Fixture);

    TestEqual(TEXT("and later drains over an empty queue deliver nothing at all"),
        Fixture._Listener->_ObservedBounds.Num(), 1);

    TestEqual(TEXT("the queue stays empty"), Get_PendingCount(Fixture), 0);

    Destroy_Fixture(Fixture);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_NavSurface_FallbackFiresOnceWithUnknownBoundsWhenOnlyTheRevisionMoved,
    "CkTests.UnitTests.CkNavigation.NavSurface.FallbackFiresOnceWithUnknownBoundsWhenOnlyTheRevisionMoved",
    kCkUnitTestFlags)

bool FCkTest_NavSurface_FallbackFiresOnceWithUnknownBoundsWhenOnlyTheRevisionMoved::RunTest(const FString& Parameters)
{
    using namespace ck_test_nav_surface_rebuild_signal;

    constexpr auto MovedRevision = int64{7};

    auto Fixture = Make_Fixture(TEXT("CkNavSurfaceRebuiltRevisionFallback"));

    if (NOT TestTrue(TEXT("the probe world has an ECS transient entity to watch"),
        ck::IsValid(Fixture._WorldEntity)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    auto& Watch = Fixture._WorldEntity.Get<ck::FFragment_NavSurface_RevisionWatch>();

    // The poll is fed the counter rather than reading it, because Recast's only advances on the engine's
    // navigation-generation-finished event and there is no navmesh here to raise one.
    ck::FProcessor_NavSurface_RevisionWatch::DoBroadcast_RevisionPoll(
        Fixture._WorldEntity, Watch, Watch.Get_LastBroadcastRevision());

    TestEqual(TEXT("a counter that has not moved says nothing"),
        Fixture._Listener->_ObservedBounds.Num(), 0);

    ck::FProcessor_NavSurface_RevisionWatch::DoBroadcast_RevisionPoll(
        Fixture._WorldEntity, Watch, MovedRevision);

    if (NOT TestEqual(TEXT("a counter that moved broadcasts exactly once"),
        Fixture._Listener->_ObservedBounds.Num(), 1))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    // A provider that reports only a counter cannot say WHERE it rebuilt, and an invalid box is how the
    // contract says so. A zero-extent box at the origin would read as a real region nothing intersects.
    TestFalse(TEXT("carrying bounds that read as unknown"),
        Fixture._Listener->_ObservedBounds[0].IsValid != 0);

    TestTrue(TEXT("and the watch is now caught up to that revision"),
        Watch.Get_LastBroadcastRevision() == MovedRevision);

    ck::FProcessor_NavSurface_RevisionWatch::DoBroadcast_RevisionPoll(
        Fixture._WorldEntity, Watch, MovedRevision);

    TestEqual(TEXT("so re-reading the same counter says nothing more"),
        Fixture._Listener->_ObservedBounds.Num(), 1);

    Destroy_Fixture(Fixture);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
