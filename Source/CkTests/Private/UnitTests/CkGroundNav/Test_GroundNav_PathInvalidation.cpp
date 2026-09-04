// What a published surface rebuild does to a route already planned over it.
//
// The invalidator is the one thing standing between a rebuilt world and an agent still walking a
// corridor through ground that moved, and it decides with two numbers and nothing else: the box the
// publisher named, and the box the plan left behind. So every claim here is measured against a box
// this file reads back off the agent - never against a constant, and never against the bake - because
// a corridor box that moved for its own reasons would otherwise take the expectation with it and the
// test would pass straight through the regression.
//
// The margin claim is the sharp one. FBox::Intersect is CLOSED, so a rebuild whose face lands exactly
// on the corridor's is a rebuild that reached it, and one unreal unit further out is not. Both halves
// are asserted, in that order, on the same agent: nothing here removes the tag, so the negative has to
// be taken before the positive or it cannot fail.
//
// The epoch claim exists because a rebuild does not arrive alone. A volume republishes its field and
// THEN pushes the region it rebuilt, so an agent that replanned in between is already walking the new
// ground and the queue describing that rebuild must not send it back for another search. It is
// asserted as a PAIR - the same box, the same agent, first with the corridor's epoch current and then
// with the field moved past it - because a gate that simply never fires would pass the first half
// alone.
//
// Everything is driven by hand. The corridor lives on a fragment nothing below the drain writes, so
// the agents plan through FProcessor_GroundNavPath_HandleRequests and _Slice; the world is a real
// UWorld because both world_fields and Request_NotifySurfaceRebuilt key on one; and the queue is
// emptied through FProcessor_NavSurface_RevisionWatch, which is what empties it under the scheduler.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Path/CkGroundNavPath_Invalidate_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Processor.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathinvalidation
{
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_TwoRouteScene;

    namespace world_fields = ck::groundnav::world_fields;

    constexpr auto kInformEngineOfWorld = false;
    constexpr auto kSixtyHertz = 1.0 / 60.0;

    // A real body, so the stored inflation is not the margin alone and a box placed against it is
    // placed against something an implementation could have got wrong.
    constexpr auto kAgentRadiusUu = 20.0f;

    // The corner-offset pass off, for the reason Test_GroundNav_PathPlanMode turns it off: the corridor
    // box is the subject, and that pass moves waypoints for reasons of its own.
    constexpr auto kNoCornerOffset = 0.0f;

    // Far past what this scene needs, so a run that stops on it is a search that never terminated.
    constexpr auto kMaxTicks = 4096;

    // What "one unit outside" means, said once. The whole margin claim is that this number is enough.
    constexpr auto kOneUu = 1.0;

    // Comfortably past the inflation a plan stores, so a box placed this far out is clear of the
    // corridor's raw plates by more than the margin however the two were combined.
    constexpr auto kWellClearUu = 100.0;

    constexpr auto kBoxSpanUu = 200.0;

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_BoxText(
        const FBox& InBox) -> FString
    {
        if (InBox.IsValid == 0)
        { return FString{TEXT("invalid")}; }

        return FString::Printf(TEXT("min(%.3f, %.3f, %.3f) max(%.3f, %.3f, %.3f)"),
            InBox.Min.X, InBox.Min.Y, InBox.Min.Z, InBox.Max.X, InBox.Max.Y, InBox.Max.Z);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * A real world, the field it publishes, and agents holding corridors planned over it.
     *
     * The world is a UWorld rather than a bare ck::FEcsWorld: Request_NotifySurfaceRebuilt reaches the
     * queue through the world's ECS subsystem, so the agents and the queue have to live in that same
     * registry or the invalidator would be reading a world nothing published into.
     */
    struct FInvalidationFixture
    {
    public:
        UWorld* _World = nullptr;

        FCk_Handle _WorldEntity;

        FCk_GroundNav_FieldPtr _Field;

        TArray<FCk_Handle_GroundNavPath> _Paths;

    public:
        auto Get_Current(
            int32 InAgentIndex) const -> const ck::FFragment_GroundNavPath_Current&
        {
            return _Paths[InAgentIndex].Get<ck::FFragment_GroundNavPath_Current>();
        }

        auto Get_HasFreshResult(
            int32 InAgentIndex) const -> bool
        {
            return _Paths[InAgentIndex].Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult();
        }
    };

    auto Make_PathParams() -> FCk_Fragment_GroundNavPath_ParamsData
    {
        auto Params = FCk_Fragment_GroundNavPath_ParamsData{kAgentRadiusUu};

        Params.Set_VerticalToleranceUu(kStepHeight);
        Params.Set_CornerOffsetK(kNoCornerOffset);

        return Params;
    }

    auto Do_Teardown(
        FInvalidationFixture& InOutFixture) -> void
    {
        if (InOutFixture._World == nullptr)
        { return; }

        InOutFixture._World->DestroyWorld(kInformEngineOfWorld);
        InOutFixture._World = nullptr;
    }

    /**
     * Bakes the two-route scene, publishes it into a world set to the given provider, and gives the
     * named number of agents the path feature.
     *
     * The three NavSurface fragments are seeded by hand for the reason Test_NavSurface_RebuildSignal
     * seeds them: the watch's DoTick composes them, and a headless world has no scheduler to run it.
     */
    auto Do_Setup(
        FInvalidationFixture&   InOutFixture,
        const TCHAR*            InWorldName,
        int32                   InAgentCount,
        ECk_NavSurface_Provider InProvider) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_TwoRouteScene(), Make_QueryParams(), *Baked))
        { return false; }

        InOutFixture._Field = Baked;

        InOutFixture._World = UWorld::CreateWorld(
            EWorldType::Game, kInformEngineOfWorld, FName{InWorldName});

        if (ck::Is_NOT_Valid(InOutFixture._World))
        { return false; }

        InOutFixture._WorldEntity =
            UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InOutFixture._World);

        if (ck::Is_NOT_Valid(InOutFixture._WorldEntity))
        { return false; }

        InOutFixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_Provider>();
        InOutFixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_RevisionWatch>();
        InOutFixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_PendingRebuilds>();

        world_fields::Publish(InOutFixture._World, FCk_Handle{}, InOutFixture._Field);

        UCk_Utils_NavSurface_UE::Request_SetProvider(InOutFixture._World, InProvider);

        if (UCk_Utils_NavSurface_UE::Get_Provider(InOutFixture._World) != InProvider)
        { return false; }

        for (auto Index = 0; Index < InAgentCount; ++Index)
        {
            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InOutFixture._WorldEntity);

            auto Path = UCk_Utils_GroundNavPath_UE::Add(Owner, Make_PathParams());

            if (ck::Is_NOT_Valid(Path))
            { return false; }

            InOutFixture._Paths.Emplace(Path);
        }

        return true;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Do_DrainRequests(
        FInvalidationFixture& InOutFixture,
        int32                 InAgentIndex) -> void
    {
        auto& Path = InOutFixture._Paths[InAgentIndex];

        ck::FProcessor_GroundNavPath_HandleRequests{InOutFixture._WorldEntity.Get_RegistryView()}
            .ForEachEntity(
                FCk_Time{kSixtyHertz},
                Path,
                Path.Get<ck::FFragment_GroundNavPath_Params>(),
                Path.Get<ck::FFragment_GroundNavPath_Current>(),
                Path.Get<ck::FFragment_GroundNavPath_Result>(),
                Path.Get<ck::FFragment_GroundNavPath_Requests>());
    }

    auto Get_EveryAgentAnswered(
        const FInvalidationFixture& InFixture) -> bool
    {
        for (auto Index = 0; Index < InFixture._Paths.Num(); ++Index)
        {
            if (NOT InFixture.Get_HasFreshResult(Index))
            { return false; }
        }

        return true;
    }

    /** One cold plan per agent, sliced until every slot carries a finished episode with a corridor. */
    auto Do_PlanEveryAgent(
        FInvalidationFixture& InOutFixture) -> bool
    {
        for (auto Index = 0; Index < InOutFixture._Paths.Num(); ++Index)
        {
            auto Request = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};

            Request.Set_RequestRevision(1);
            Request.Set_PlanMode(ECk_GroundNav_PlanMode::Cold);

            UCk_Utils_GroundNavPath_UE::Request_FindPath(InOutFixture._Paths[Index], Request, {});

            Do_DrainRequests(InOutFixture, Index);
        }

        auto Slice = ck::FProcessor_GroundNavPath_Slice{InOutFixture._WorldEntity.Get_RegistryView()};

        auto Ticks = 0;

        while (NOT Get_EveryAgentAnswered(InOutFixture) && Ticks < kMaxTicks)
        {
            Slice.DoTick(FCk_Time{kSixtyHertz});
            ++Ticks;
        }

        for (auto Index = 0; Index < InOutFixture._Paths.Num(); ++Index)
        {
            const auto Corridor = UCk_Utils_GroundNavPath_UE::Get_LastCorridorBounds(
                InOutFixture._Paths[Index]);

            if (Corridor.IsValid == 0)
            { return false; }
        }

        return true;
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * Republishes the SAME ground under the next epoch, which is what a rebuild leaves behind for a
     * later query to find. The bake is not re-run: the epoch is the subject, and re-baking would make
     * the corridor's own plates a second variable.
     */
    auto Do_PublishNextEpoch(
        FInvalidationFixture& InOutFixture) -> void
    {
        auto Rebuilt = MakeShared<FCk_GroundNav_Field>(*InOutFixture._Field);

        Rebuilt->_Epoch = InOutFixture._Field->_Epoch.Get_Next();

        InOutFixture._Field = Rebuilt;

        world_fields::Publish(InOutFixture._World, FCk_Handle{}, InOutFixture._Field);
    }

    auto Do_NotifyRebuilt(
        FInvalidationFixture& InOutFixture,
        const FBox&           InBounds) -> void
    {
        ck::nav_surface::Request_NotifySurfaceRebuilt(InOutFixture._World, InBounds);
    }

    auto Do_RunInvalidator(
        FInvalidationFixture& InOutFixture) -> void
    {
        ck::FProcessor_GroundNavPath_InvalidateOnRebuilt{InOutFixture._WorldEntity.Get_RegistryView()}
            .DoTick(FCk_Time{kSixtyHertz});
    }

    /** The watch's own drain, which is what empties the queue under the scheduler too. */
    auto Do_DrainPublishedRebuilds(
        FInvalidationFixture& InOutFixture) -> void
    {
        ck::FProcessor_NavSurface_RevisionWatch::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InOutFixture._WorldEntity,
            InOutFixture._WorldEntity.Get<ck::FFragment_NavSurface_Provider>(),
            InOutFixture._WorldEntity.Get<ck::FFragment_NavSurface_RevisionWatch>(),
            InOutFixture._WorldEntity.Get<ck::FFragment_NavSurface_PendingRebuilds>());
    }

    auto Get_QueuedRebuildCount(
        const FInvalidationFixture& InFixture) -> int32
    {
        return InFixture._WorldEntity.Get<ck::FFragment_NavSurface_PendingRebuilds>()
            .Get_Bounds().Num();
    }

    auto Get_IsFlagged(
        const FInvalidationFixture& InFixture,
        int32                       InAgentIndex) -> bool
    {
        return InFixture._Paths[InAgentIndex].Has<ck::FTag_GroundNavPath_RepathRequired>();
    }

    auto Get_FlaggedAgentCount(
        const FInvalidationFixture& InFixture) -> int32
    {
        auto Count = 0;

        for (auto Index = 0; Index < InFixture._Paths.Num(); ++Index)
        {
            if (Get_IsFlagged(InFixture, Index))
            { ++Count; }
        }

        return Count;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_StoredCorridor(
        const FInvalidationFixture& InFixture,
        int32                       InAgentIndex) -> FBox
    {
        return UCk_Utils_GroundNavPath_UE::Get_LastCorridorBounds(InFixture._Paths[InAgentIndex]);
    }

    /** A box well inside the corridor, so the overlap is a fact about the boxes and not about a face. */
    auto Make_OverlappingBox(
        const FBox& InCorridor) -> FBox
    {
        return FBox{InCorridor.GetCenter() - FVector{kWellClearUu},
                    InCorridor.GetCenter() + FVector{kWellClearUu}};
    }

    /** A box off the corridor's far X face by an offset, spanning its Y and Z so only X can separate them. */
    auto Make_BoxPastFarFace(
        const FBox& InCorridor,
        double      InOffsetUu) -> FBox
    {
        return FBox{
            FVector{InCorridor.Max.X + InOffsetUu, InCorridor.Min.Y, InCorridor.Min.Z},
            FVector{InCorridor.Max.X + InOffsetUu + kBoxSpanUu, InCorridor.Max.Y, InCorridor.Max.Z}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_AdjacentBoundsDoesNotFlag,
    "CkTests.UnitTests.CkGroundNav.Invalidation.AdjacentBoundsDoesNotFlag",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_AdjacentBoundsDoesNotFlag::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationAdjacent"), 1,
            ECk_NavSurface_Provider::GroundNav)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and the agent plans a route with a corridor to measure against"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Corridor = Get_StoredCorridor(Fixture, 0);
    const auto Inflation = Fixture.Get_Current(0).Get_CorridorInflationUu();

    Do_PublishNextEpoch(Fixture);

    // Clear of the STORED box, which is already the raw plates grown by the inflation - so this box is
    // further from those plates than the margin, which is what "adjacent, not reached" has to mean.
    const auto Adjacent = Make_BoxPastFarFace(Corridor, kWellClearUu);

    Do_NotifyRebuilt(Fixture, Adjacent);
    Do_RunInvalidator(Fixture);

    TestFalse(FString::Printf(
            TEXT("a rebuild clear of the corridor by more than its %.1fuu inflation flags nobody ")
            TEXT("[rebuild %s vs corridor %s]"),
            Inflation, *Get_BoxText(Adjacent), *Get_BoxText(Corridor)),
        Get_IsFlagged(Fixture, 0));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_IntersectingBoundsFlags,
    "CkTests.UnitTests.CkGroundNav.Invalidation.IntersectingBoundsFlags",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_IntersectingBoundsFlags::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationIntersecting"), 1,
            ECk_NavSurface_Provider::GroundNav)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and the agent plans a route with a corridor to measure against"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Corridor = Get_StoredCorridor(Fixture, 0);

    Do_PublishNextEpoch(Fixture);

    const auto Overlapping = Make_OverlappingBox(Corridor);

    Do_NotifyRebuilt(Fixture, Overlapping);
    Do_RunInvalidator(Fixture);

    TestTrue(FString::Printf(TEXT("a rebuild overlapping the corridor flags the agent ")
            TEXT("[rebuild %s vs corridor %s]"),
            *Get_BoxText(Overlapping), *Get_BoxText(Corridor)),
        Get_IsFlagged(Fixture, 0));

    // The queue belongs to the watch, and reading it is all this pass is entitled to do: a pass that
    // consumed it would take the neutral broadcast down with it.
    TestEqual(TEXT("and leaves the published rebuild on the queue for the watch to broadcast"),
        Get_QueuedRebuildCount(Fixture), 1);

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_MarginIsRespectedExactly,
    "CkTests.UnitTests.CkGroundNav.Invalidation.MarginIsRespectedExactly",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_MarginIsRespectedExactly::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationMargin"), 1,
            ECk_NavSurface_Provider::GroundNav)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and the agent plans a route with a corridor to measure against"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Corridor = Get_StoredCorridor(Fixture, 0);

    Do_PublishNextEpoch(Fixture);

    // The negative FIRST. Nothing here removes the tag, so a positive taken before it would leave the
    // negative unable to fail.
    const auto JustOutside = Make_BoxPastFarFace(Corridor, kOneUu);

    Do_NotifyRebuilt(Fixture, JustOutside);
    Do_RunInvalidator(Fixture);

    TestFalse(FString::Printf(
            TEXT("a rebuild one unit past the corridor's face flags nobody [rebuild %s vs corridor %s]"),
            *Get_BoxText(JustOutside), *Get_BoxText(Corridor)),
        Get_IsFlagged(Fixture, 0));

    Do_DrainPublishedRebuilds(Fixture);

    if (NOT TestEqual(TEXT("the watch empties the queue, so the next publish stands alone"),
        Get_QueuedRebuildCount(Fixture), 0))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto ExactlyOnTheFace = Make_BoxPastFarFace(Corridor, 0.0);

    Do_NotifyRebuilt(Fixture, ExactlyOnTheFace);
    Do_RunInvalidator(Fixture);

    // Closed intersection: a face landing exactly on the corridor's is ground the corridor reaches, and
    // the margin exists precisely so that boundary sits where it does.
    TestTrue(FString::Printf(
            TEXT("a rebuild whose face lies exactly on the corridor's flags the agent ")
            TEXT("[rebuild %s vs corridor %s]"),
            *Get_BoxText(ExactlyOnTheFace), *Get_BoxText(Corridor)),
        Get_IsFlagged(Fixture, 0));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_OnePublishFlagsEachPathAtMostOnce,
    "CkTests.UnitTests.CkGroundNav.Invalidation.OnePublishFlagsEachPathAtMostOnce",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_OnePublishFlagsEachPathAtMostOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes two agents"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationAtMostOnce"), 2,
            ECk_NavSurface_Provider::GroundNav)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and both agents plan routes with corridors to measure against"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto FirstCorridor = Get_StoredCorridor(Fixture, 0);
    const auto SecondCorridor = Get_StoredCorridor(Fixture, 1);

    Do_PublishNextEpoch(Fixture);

    // Two boxes that overlap each other as well as both corridors, so an implementation flagging once
    // per queued box rather than once per path has two chances to say so.
    Do_NotifyRebuilt(Fixture, Make_OverlappingBox(FirstCorridor));
    Do_NotifyRebuilt(Fixture, Make_OverlappingBox(SecondCorridor).ExpandBy(kWellClearUu));

    if (NOT TestEqual(TEXT("both rebuilds are queued in the one publish frame"),
        Get_QueuedRebuildCount(Fixture), 2))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    TestTrue(TEXT("the first agent carries the repath flag"), Get_IsFlagged(Fixture, 0));
    TestTrue(TEXT("and so does the second"), Get_IsFlagged(Fixture, 1));

    const auto FlaggedAfterPublish = Get_FlaggedAgentCount(Fixture);

    TestEqual(TEXT("which is every agent and no more - the tag is set membership, so a burst of ")
            TEXT("overlapping boxes still leaves one flag per path"),
        FlaggedAfterPublish, 2);

    Do_DrainPublishedRebuilds(Fixture);

    if (NOT TestEqual(TEXT("the watch empties the queue"), Get_QueuedRebuildCount(Fixture), 0))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    // Nothing published, nothing raised, and - the half that matters to the consumer - nothing taken
    // away: this module raises the flag and never clears it.
    TestEqual(TEXT("and a second pass over an empty queue adds nothing and removes nothing"),
        Get_FlaggedAgentCount(Fixture), FlaggedAfterPublish);

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_UnknownBoundsFlagsEveryPath,
    "CkTests.UnitTests.CkGroundNav.Invalidation.UnknownBoundsFlagsEveryPath",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_UnknownBoundsFlagsEveryPath::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes two agents"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationUnknownBounds"), 2,
            ECk_NavSurface_Provider::GroundNav)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and both agents plan routes with corridors to measure against"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_PublishNextEpoch(Fixture);

    // Bounds the publisher did not know. Nothing can be ruled out against it, so nothing is.
    Do_NotifyRebuilt(Fixture, FBox{ForceInit});
    Do_RunInvalidator(Fixture);

    TestEqual(TEXT("a rebuild with unknown bounds flags every agent holding a corridor"),
        Get_FlaggedAgentCount(Fixture), Fixture._Paths.Num());

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_RecastWorldIsUntouched,
    "CkTests.UnitTests.CkGroundNav.Invalidation.RecastWorldIsUntouched",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_RecastWorldIsUntouched::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes and publishes into a RECAST world"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationRecast"), 1,
            ECk_NavSurface_Provider::Recast)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and the agent still plans over the published field"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Corridor = Get_StoredCorridor(Fixture, 0);

    Do_PublishNextEpoch(Fixture);

    const auto Overlapping = Make_OverlappingBox(Corridor);

    Do_NotifyRebuilt(Fixture, Overlapping);
    Do_RunInvalidator(Fixture);

    // The queue is shared across providers, and what Recast rebuilt is not what moved a GroundNav route.
    TestFalse(FString::Printf(
            TEXT("a rebuild published into a Recast world flags nobody, overlap or not ")
            TEXT("[rebuild %s vs corridor %s]"),
            *Get_BoxText(Overlapping), *Get_BoxText(Corridor)),
        Get_IsFlagged(Fixture, 0));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_CorridorPlannedAgainstTheCurrentEpochIsNotFlagged,
    "CkTests.UnitTests.CkGroundNav.Invalidation.CorridorPlannedAgainstTheCurrentEpochIsNotFlagged",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_CorridorPlannedAgainstTheCurrentEpochIsNotFlagged::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"),
        Do_Setup(Fixture, TEXT("CkGroundNavInvalidationEpoch"), 1,
            ECk_NavSurface_Provider::GroundNav)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and the agent plans a route with a corridor to measure against"),
        Do_PlanEveryAgent(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Corridor = Get_StoredCorridor(Fixture, 0);
    const auto Overlapping = Make_OverlappingBox(Corridor);

    if (NOT TestEqual(TEXT("the corridor was planned against the epoch the world publishes now"),
        Fixture.Get_Current(0).Get_LastCorridorEpoch()._Value, Fixture._Field->_Epoch._Value))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_NotifyRebuilt(Fixture, Overlapping);
    Do_RunInvalidator(Fixture);

    // The route already postdates every rebuild this queue can describe: an agent that replanned
    // between the publish and this pass is walking the new ground, and sending it back would buy a
    // second search that answers the same question.
    TestFalse(FString::Printf(
            TEXT("an overlapping rebuild does not flag a corridor found on the current epoch ")
            TEXT("[epoch %lld, rebuild %s]"),
            Fixture._Field->_Epoch._Value, *Get_BoxText(Overlapping)),
        Get_IsFlagged(Fixture, 0));

    // The other half, on the SAME box and the SAME agent: move the field past the corridor and that
    // very queue entry now flags it. Without this, a gate that never fires would pass above.
    Do_PublishNextEpoch(Fixture);
    Do_RunInvalidator(Fixture);

    TestTrue(FString::Printf(
            TEXT("and does flag it once the world has published past that epoch [epoch %lld]"),
            Fixture._Field->_Epoch._Value),
        Get_IsFlagged(Fixture, 0));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
