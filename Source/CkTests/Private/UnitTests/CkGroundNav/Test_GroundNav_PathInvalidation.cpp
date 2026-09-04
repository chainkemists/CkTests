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
// The link claims are the exact half of the same decision. The registry entry carries a note naming
// the epoch of the last publish that could have moved ground and the authored ids every link-only
// publish since it moved, and a corridor caches the ids it crosses; the two agents below are planned
// so that both corridors sit in the SAME endpoint tile and only one of them crosses the link, which is
// what makes "flagged by identity" distinguishable from "flagged by the box". Every one of those rows
// asserts that the published box DOES reach the corridor it did not flag - without that, the row would
// pass on a fixture whose geometry happened to miss.
//
// Two of them are about that RUN rather than about one publish, because publishes do not arrive one at
// a time. A repair and a derive in the same tick leave the queue holding the repair's box under a note
// the derive wrote, and the corridor the repair moved has to be flagged by that box anyway; two toggles
// before anything replans have to flag by EITHER of them, which is asserted in both orders because a
// note remembering only its newest publish answers one of the two right by accident.
//
// Everything is driven by hand. The corridor lives on a fragment nothing below the drain writes, so
// the agents plan through FProcessor_GroundNavPath_HandleRequests and _Slice; the world is a real
// UWorld because both world_fields and Request_NotifySurfaceRebuilt key on one; and the queue is
// emptied through FProcessor_NavSurface_RevisionWatch, which is what empties it under the scheduler.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldLinks.h"
#include "CkGroundNav/Field/CkGroundNav_FieldMarkupCost.h"
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
    using ck::groundnav::Get_ChangedTileBounds;
    using ck::groundnav::Get_FieldWithLinks;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
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

    // A wall the full height and depth of the one tile, so the two halves of the floor are joined by
    // the LINK and by nothing else. A cost crossover would decide whether the route takes it; a wall
    // with no way round decides it by construction, which is what a claim about invalidation wants.
    constexpr auto kWallMinXUu = 350.0;
    constexpr auto kWallMaxXUu = 450.0;

    const auto kNearSide = FVector{200.0, 400.0, kGroundZ};
    const auto kFarSide = FVector{600.0, 400.0, kGroundZ};

    // Straight across the wall at the height of both ends, so the crossing route is one line.
    const auto kCrossingLinkStart = FVector{300.0, 400.0, kGroundZ};
    const auto kCrossingLinkEnd = FVector{500.0, 400.0, kGroundZ};

    // A second link, far enough off that line that no route between the two points above would price
    // it, and DISABLED besides - it exists to occupy an entry in _ResolvedLinks, so removing it
    // renumbers the one the route uses.
    const auto kSpareLinkStart = FVector{300.0, 100.0, kGroundZ};
    const auto kSpareLinkEnd = FVector{500.0, 100.0, kGroundZ};

    // Both on the near side, so this route never reaches the wall and crosses no link. Chosen inside
    // the same tile as the link's ends, so the changed-tile box reaches this corridor too and only
    // identity can tell the two agents apart.
    const auto kBesideStart = FVector{200.0, 200.0, kGroundZ};
    const auto kBesideGoal = FVector{200.0, 600.0, kGroundZ};

    // Lower than the one the route uses, so a removal of the spare shifts the used one DOWN an index
    // and an implementation comparing indices would answer with the wrong link.
    constexpr auto kSpareLinkId = 1;
    constexpr auto kCrossingLinkId = 2;

    // Never authored on any of these fields, so a derive naming it would be naming something that does
    // not exist.
    constexpr auto kAddedLinkId = 3;

    constexpr auto kRepricedMultiplier = 2.0f;

    constexpr auto kCrossingAgent = 0;
    constexpr auto kBesideAgent = 1;

    /** One floor under the whole tile and its halo, split in two by a wall nothing can walk round. */
    auto Make_LinkScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}});

        Boxes.Emplace(FBox{
            FVector{kWallMinXUu, -400.0, 0.0},
            FVector{kWallMaxXUu, 1200.0, 300.0}});

        return Boxes;
    }

    auto Make_LinkRecord(
        int32             InId,
        const FVector&    InStart,
        const FVector&    InEnd,
        ECk_EnableDisable InEnable) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};

        Record.Set_Enable(InEnable);

        return Record;
    }

    auto Make_SpareLink() -> FCk_GroundNav_LinkRecord
    {
        return Make_LinkRecord(
            kSpareLinkId, kSpareLinkStart, kSpareLinkEnd, ECk_EnableDisable::Disable);
    }

    auto Make_CrossingLink(
        ECk_EnableDisable InEnable = ECk_EnableDisable::Enable)
        -> FCk_GroundNav_LinkRecord
    {
        return Make_LinkRecord(kCrossingLinkId, kCrossingLinkStart, kCrossingLinkEnd, InEnable);
    }

    /** Both records, in authored-id order, which is the order a derive re-resolves them in. */
    auto Make_BothLinks() -> TArray<FCk_GroundNav_LinkRecord>
    {
        return TArray<FCk_GroundNav_LinkRecord>{Make_SpareLink(), Make_CrossingLink()};
    }

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
     * Publishes whatever field the fixture already holds into a world set to the given provider, and
     * gives the named number of agents the path feature.
     *
     * The three NavSurface fragments are seeded by hand for the reason Test_NavSurface_RebuildSignal
     * seeds them: the watch's DoTick composes them, and a headless world has no scheduler to run it.
     */
    auto Do_SetupWorld(
        FInvalidationFixture&   InOutFixture,
        const TCHAR*            InWorldName,
        int32                   InAgentCount,
        ECk_NavSurface_Provider InProvider) -> bool
    {
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

    /** The two-route scene, which every claim about boxes and epochs below is measured on. */
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

        return Do_SetupWorld(InOutFixture, InWorldName, InAgentCount, InProvider);
    }

    /**
     * The same world over the ONE-TILE link scene, with both records already authored.
     *
     * The links go in through the bake's own params rather than through a derive, so the field the
     * agents plan over is the field a build would have published and the first derive in a test is the
     * change under test rather than the setup.
     */
    auto Do_Setup_LinkScene(
        FInvalidationFixture& InOutFixture,
        const TCHAR*          InWorldName) -> bool
    {
        auto Params = Make_FlatParams();
        Params._Links = Make_BothLinks();

        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_LinkScene(), Params, *Baked))
        { return false; }

        InOutFixture._Field = Baked;

        return Do_SetupWorld(
            InOutFixture, InWorldName, 2, ECk_NavSurface_Provider::GroundNav);
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

    /** One cold plan for ONE agent, sliced until its own slot carries a finished episode. */
    auto Do_PlanAgent(
        FInvalidationFixture& InOutFixture,
        int32                 InAgentIndex,
        const FVector&        InFrom,
        const FVector&        InGoal) -> bool
    {
        auto Request = FCk_Request_GroundNavPath_FindPath{InFrom, InGoal};

        Request.Set_RequestRevision(1);
        Request.Set_PlanMode(ECk_GroundNav_PlanMode::Cold);

        UCk_Utils_GroundNavPath_UE::Request_FindPath(InOutFixture._Paths[InAgentIndex], Request, {});

        Do_DrainRequests(InOutFixture, InAgentIndex);

        auto Slice = ck::FProcessor_GroundNavPath_Slice{InOutFixture._WorldEntity.Get_RegistryView()};

        auto Ticks = 0;

        while (NOT InOutFixture.Get_HasFreshResult(InAgentIndex) && Ticks < kMaxTicks)
        {
            Slice.DoTick(FCk_Time{kSixtyHertz});
            ++Ticks;
        }

        return UCk_Utils_GroundNavPath_UE::Get_LastCorridorBounds(
            InOutFixture._Paths[InAgentIndex]).IsValid != 0;
    }

    auto Get_CorridorLinkIds(
        const FInvalidationFixture& InFixture,
        int32                       InAgentIndex) -> TArray<int32>
    {
        return InFixture.Get_Current(InAgentIndex).Get_LastCorridorLinkIds();
    }

    auto Get_NamesExactly(
        const TArray<int32>& InIds,
        int32                InExpectedId) -> bool
    {
        return InIds.Num() == 1 && InIds[0] == InExpectedId;
    }

    auto Get_IdsText(
        const TArray<int32>& InIds) -> FString
    {
        auto Text = FString{};

        for (const auto Id : InIds)
        { Text += Text.IsEmpty() ? FString::FromInt(Id) : FString::Printf(TEXT(", %d"), Id); }

        return Text.IsEmpty() ? FString{TEXT("none")} : Text;
    }

    /**
     * The link scene, one agent routed ACROSS the link and one routed beside it, and the pin that says
     * the two corridors really are those two things.
     *
     * Every link row below is a claim about which of the two the invalidator singles out, so a fixture
     * that quietly planned both the same way would pass them all without testing anything.
     */
    auto Do_Setup_AndPlanAcrossTheLink(
        FInvalidationFixture& InOutFixture,
        const TCHAR*          InWorldName) -> bool
    {
        if (NOT Do_Setup_LinkScene(InOutFixture, InWorldName))
        { return false; }

        if (NOT Do_PlanAgent(InOutFixture, kCrossingAgent, kNearSide, kFarSide))
        { return false; }

        if (NOT Do_PlanAgent(InOutFixture, kBesideAgent, kBesideStart, kBesideGoal))
        { return false; }

        return Get_NamesExactly(Get_CorridorLinkIds(InOutFixture, kCrossingAgent), kCrossingLinkId) &&
            Get_CorridorLinkIds(InOutFixture, kBesideAgent).IsEmpty();
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

    /**
     * The derive's own publish, done by hand: a field re-resolved from a new record list, the ids that
     * say which links moved, and the endpoint-tile box beside it.
     *
     * Answers the BOX, because every row here has to be able to say that the box reached the corridor
     * it did not flag - otherwise the claim is about where the fixture put its geometry.
     */
    auto Do_PublishLinkDerive(
        FInvalidationFixture&                   InOutFixture,
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        TArray<int32>&                          OutChangedLinkIds) -> FBox
    {
        const auto Derived = Get_FieldWithLinks(
            *InOutFixture._Field, InLinks, InOutFixture._Field->_Epoch.Get_Next());

        InOutFixture._Field = Derived._Field;
        OutChangedLinkIds = Derived._ChangedLinkIds;

        world_fields::Publish(
            InOutFixture._World, FCk_Handle{}, InOutFixture._Field, Derived._ChangedLinkIds);

        const auto Bounds = Get_ChangedTileBounds(*InOutFixture._Field, InOutFixture._Field->_Epoch);

        Do_NotifyRebuilt(InOutFixture, Bounds);

        return Bounds;
    }

    /**
     * A link-only publish naming NO ids. The derive never emits one - a re-resolution that moved
     * nothing moves no epoch and is not published at all - so this is built by hand to pin what the
     * invalidator does when it is handed one anyway. An EMPTY list is still a claim that nothing but
     * links moved, which is what tells it apart from the geometry publish that names nothing at all.
     */
    auto Do_PublishLinkOnlyNamingNothing(
        FInvalidationFixture& InOutFixture) -> void
    {
        auto Rebuilt = MakeShared<FCk_GroundNav_Field>(*InOutFixture._Field);

        Rebuilt->_Epoch = InOutFixture._Field->_Epoch.Get_Next();

        InOutFixture._Field = Rebuilt;

        world_fields::Publish(
            InOutFixture._World, FCk_Handle{}, InOutFixture._Field, TArray<int32>{});
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

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * Everything one two-toggle run leaves behind, copied out of the world before it goes: the
     * corridors and the flags live on entities in that world, so an assertion taken afterwards would be
     * reading a registry that has been torn down.
     */
    struct FTwoTogglesOutcome
    {
    public:
        bool _Planned = false;

        TArray<int32> _FirstNamed;
        TArray<int32> _SecondNamed;

        FBox _SecondPublished = FBox{ForceInit};
        FBox _BesideCorridor = FBox{ForceInit};

        bool _CrossingIsFlagged = false;
        bool _BesideIsFlagged = false;
    };

    /**
     * Two link derives with nothing between them, then ONE invalidator pass, on a world of its own so
     * the same pair of toggles can be put through in either order.
     */
    auto Do_RunTwoToggles(
        const TCHAR*                            InWorldName,
        const TArray<FCk_GroundNav_LinkRecord>& InAfterFirstToggle,
        const TArray<FCk_GroundNav_LinkRecord>& InAfterSecondToggle) -> FTwoTogglesOutcome
    {
        auto Outcome = FTwoTogglesOutcome{};

        auto Fixture = FInvalidationFixture{};

        Outcome._Planned = Do_Setup_AndPlanAcrossTheLink(Fixture, InWorldName);

        if (NOT Outcome._Planned)
        {
            Do_Teardown(Fixture);
            return Outcome;
        }

        Outcome._BesideCorridor = Get_StoredCorridor(Fixture, kBesideAgent);

        Do_PublishLinkDerive(Fixture, InAfterFirstToggle, Outcome._FirstNamed);

        // No drain and no invalidator pass in between: the second publish lands on corridors that have
        // already missed the first, which is the whole of what this asks about.
        Outcome._SecondPublished =
            Do_PublishLinkDerive(Fixture, InAfterSecondToggle, Outcome._SecondNamed);

        Do_RunInvalidator(Fixture);

        Outcome._CrossingIsFlagged = Get_IsFlagged(Fixture, kCrossingAgent);
        Outcome._BesideIsFlagged = Get_IsFlagged(Fixture, kBesideAgent);

        Do_Teardown(Fixture);

        return Outcome;
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_LinkOnlyPublishFlagsOnlyCorridorsUsingTheLink,
    "CkTests.UnitTests.CkGroundNav.Invalidation.LinkOnlyPublishFlagsOnlyCorridorsUsingTheLink",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_LinkOnlyPublishFlagsOnlyCorridorsUsingTheLink::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the link scene bakes and takes one agent across the link and one beside it"),
        Do_Setup_AndPlanAcrossTheLink(Fixture, TEXT("CkGroundNavInvalidationLinkOnly"))))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto BesideCorridor = Get_StoredCorridor(Fixture, kBesideAgent);

    auto ChangedLinkIds = TArray<int32>{};

    const auto Published = Do_PublishLinkDerive(
        Fixture,
        TArray<FCk_GroundNav_LinkRecord>{Make_SpareLink(), Make_CrossingLink(ECk_EnableDisable::Disable)},
        ChangedLinkIds);

    if (NOT TestTrue(FString::Printf(
            TEXT("the derive names exactly the link it switched off [named %s]"),
            *Get_IdsText(ChangedLinkIds)),
        Get_NamesExactly(ChangedLinkIds, kCrossingLinkId)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // Without this the row would be a statement about where the fixture put its geometry: the whole
    // claim is that the corridor the box REACHES is spared anyway, because it crosses no changed link.
    if (NOT TestTrue(FString::Printf(
            TEXT("and the box it published reaches the corridor beside the link ")
            TEXT("[published %s vs corridor %s]"),
            *Get_BoxText(Published), *Get_BoxText(BesideCorridor)),
        Published.IsValid != 0 && Published.Intersect(BesideCorridor)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    TestTrue(TEXT("the corridor that crosses the disabled link is flagged"),
        Get_IsFlagged(Fixture, kCrossingAgent));

    TestFalse(TEXT("and the corridor through the same endpoint tile that does not cross it is not"),
        Get_IsFlagged(Fixture, kBesideAgent));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_LinkOnlyPublishWithNoChangedIdsFlagsNothing,
    "CkTests.UnitTests.CkGroundNav.Invalidation.LinkOnlyPublishWithNoChangedIdsFlagsNothing",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_LinkOnlyPublishWithNoChangedIdsFlagsNothing::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the link scene bakes and takes one agent across the link and one beside it"),
        Do_Setup_AndPlanAcrossTheLink(Fixture, TEXT("CkGroundNavInvalidationLinkOnlyEmpty"))))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // Reaching BOTH corridors, so the only thing that can spare either of them is the empty id list.
    // The same box under a publish that is not link-only flags both, which is the next row.
    const auto ReachesBoth =
        Get_StoredCorridor(Fixture, kCrossingAgent) + Get_StoredCorridor(Fixture, kBesideAgent);

    Do_PublishLinkOnlyNamingNothing(Fixture);
    Do_NotifyRebuilt(Fixture, ReachesBoth);
    Do_RunInvalidator(Fixture);

    TestEqual(FString::Printf(
            TEXT("a link-only publish that moved no link flags nobody, box or no box [published %s]"),
            *Get_BoxText(ReachesBoth)),
        Get_FlaggedAgentCount(Fixture), 0);

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_ABuildPublishStillFlagsByBounds,
    "CkTests.UnitTests.CkGroundNav.Invalidation.ABuildPublishStillFlagsByBounds",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_ABuildPublishStillFlagsByBounds::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the link scene bakes and takes one agent across the link and one beside it"),
        Do_Setup_AndPlanAcrossTheLink(Fixture, TEXT("CkGroundNavInvalidationLinkBuild"))))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto ReachesBoth =
        Get_StoredCorridor(Fixture, kCrossingAgent) + Get_StoredCorridor(Fixture, kBesideAgent);

    // No note: the shape every publisher but the link derive goes out under. The ground itself moved,
    // and no list of link ids describes that, so the floor is the box and the box is the whole answer.
    Do_PublishNextEpoch(Fixture);
    Do_NotifyRebuilt(Fixture, ReachesBoth);
    Do_RunInvalidator(Fixture);

    TestEqual(FString::Printf(
            TEXT("a publish that is not link-only flags every corridor the box reaches, link or no ")
            TEXT("link [published %s]"),
            *Get_BoxText(ReachesBoth)),
        Get_FlaggedAgentCount(Fixture), Fixture._Paths.Num());

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_RemovedLinkIsFlaggedByItsStableId,
    "CkTests.UnitTests.CkGroundNav.Invalidation.RemovedLinkIsFlaggedByItsStableId",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_RemovedLinkIsFlaggedByItsStableId::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the link scene bakes and takes one agent across the link and one beside it"),
        Do_Setup_AndPlanAcrossTheLink(Fixture, TEXT("CkGroundNavInvalidationLinkRenumber"))))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto CrossingCorridor = Get_StoredCorridor(Fixture, kCrossingAgent);

    auto ChangedLinkIds = TArray<int32>{};

    // The SPARE goes first. It is the lower id, so removing it slides the link the route uses down one
    // index - and an implementation comparing indices would answer this half wrong.
    const auto FirstPublished = Do_PublishLinkDerive(
        Fixture, TArray<FCk_GroundNav_LinkRecord>{Make_CrossingLink()}, ChangedLinkIds);

    if (NOT TestTrue(FString::Printf(
            TEXT("removing the spare names the spare and nothing else [named %s]"),
            *Get_IdsText(ChangedLinkIds)),
        Get_NamesExactly(ChangedLinkIds, kSpareLinkId)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and the link the route uses has renumbered under it"),
        Fixture._Field->_ResolvedLinks.Num() == 1 &&
        Fixture._Field->_ResolvedLinks[0]._Id == kCrossingLinkId))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(FString::Printf(
            TEXT("with the box reaching the crossing corridor [published %s vs corridor %s]"),
            *Get_BoxText(FirstPublished), *Get_BoxText(CrossingCorridor)),
        FirstPublished.IsValid != 0 && FirstPublished.Intersect(CrossingCorridor)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    // The negative FIRST, on the agent the positive below flags: nothing removes the tag, so a positive
    // taken before it would leave this unable to fail.
    TestEqual(TEXT("removing a link no corridor crosses flags nobody"),
        Get_FlaggedAgentCount(Fixture), 0);

    Do_DrainPublishedRebuilds(Fixture);

    const auto SecondPublished = Do_PublishLinkDerive(
        Fixture, TArray<FCk_GroundNav_LinkRecord>{}, ChangedLinkIds);

    if (NOT TestTrue(FString::Printf(
            TEXT("removing the link the route crosses names that link [named %s, published %s]"),
            *Get_IdsText(ChangedLinkIds), *Get_BoxText(SecondPublished)),
        Get_NamesExactly(ChangedLinkIds, kCrossingLinkId)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    TestTrue(TEXT("and the corridor that crossed it is flagged by that id, though the entry it was ")
            TEXT("cached against is long gone"),
        Get_IsFlagged(Fixture, kCrossingAgent));

    TestFalse(TEXT("while the corridor beside it is still not"),
        Get_IsFlagged(Fixture, kBesideAgent));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_RepairAndLinkDeriveInOneTickFallToBounds,
    "CkTests.UnitTests.CkGroundNav.Invalidation.RepairAndLinkDeriveInOneTickFallToBounds",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_RepairAndLinkDeriveInOneTickFallToBounds::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    auto Fixture = FInvalidationFixture{};

    if (NOT TestTrue(TEXT("the link scene bakes and takes one agent across the link and one beside it"),
        Do_Setup_AndPlanAcrossTheLink(Fixture, TEXT("CkGroundNavInvalidationRepairThenDerive"))))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto BesideCorridor = Get_StoredCorridor(Fixture, kBesideAgent);
    const auto RepairedGround = Get_StoredCorridor(Fixture, kCrossingAgent) + BesideCorridor;

    // The repair first: ground moved, under an epoch both corridors are now behind.
    Do_PublishNextEpoch(Fixture);
    Do_NotifyRebuilt(Fixture, RepairedGround);

    auto ChangedLinkIds = TArray<int32>{};

    // ...and the derive lands in the SAME tick, before anything drains the queue, so the newest thing
    // said about this entry is link-only while the queue is still holding the repair's box.
    Do_PublishLinkDerive(
        Fixture,
        TArray<FCk_GroundNav_LinkRecord>{Make_SpareLink(), Make_CrossingLink(ECk_EnableDisable::Disable)},
        ChangedLinkIds);

    if (NOT TestTrue(FString::Printf(
            TEXT("the derive names exactly the link it switched off, so narrowing on it alone would ")
            TEXT("spare the corridor beside it [named %s]"),
            *Get_IdsText(ChangedLinkIds)),
        Get_NamesExactly(ChangedLinkIds, kCrossingLinkId)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    TestTrue(FString::Printf(
            TEXT("the corridor that crosses no changed link is flagged anyway, by the ground the repair ")
            TEXT("moved out from under it [repaired %s vs corridor %s]"),
            *Get_BoxText(RepairedGround), *Get_BoxText(BesideCorridor)),
        Get_IsFlagged(Fixture, kBesideAgent));

    TestEqual(TEXT("and so is the one that does cross it"),
        Get_FlaggedAgentCount(Fixture), Fixture._Paths.Num());

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_TwoTogglesBeforeAReplanStayExact,
    "CkTests.UnitTests.CkGroundNav.Invalidation.TwoTogglesBeforeAReplanStayExact",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_TwoTogglesBeforeAReplanStayExact::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    const auto SpareEnabled = Make_LinkRecord(
        kSpareLinkId, kSpareLinkStart, kSpareLinkEnd, ECk_EnableDisable::Enable);

    const auto SpareOnCrossingOn =
        TArray<FCk_GroundNav_LinkRecord>{SpareEnabled, Make_CrossingLink()};

    const auto SpareOnCrossingOff =
        TArray<FCk_GroundNav_LinkRecord>{SpareEnabled, Make_CrossingLink(ECk_EnableDisable::Disable)};

    const auto SpareOffCrossingOff = TArray<FCk_GroundNav_LinkRecord>{
        Make_SpareLink(), Make_CrossingLink(ECk_EnableDisable::Disable)};

    const auto Do_Assert = [&](
        const FTwoTogglesOutcome& InOutcome,
        const TCHAR*              InOrder,
        int32                     InFirstId,
        int32                     InSecondId) -> void
    {
        if (NOT TestTrue(FString::Printf(
                TEXT("[%s] the link scene bakes and takes one agent across the link and one beside it"),
                InOrder),
            InOutcome._Planned))
        { return; }

        if (NOT TestTrue(FString::Printf(
                TEXT("[%s] the first toggle names link [%d] and nothing else [named %s]"),
                InOrder, InFirstId, *Get_IdsText(InOutcome._FirstNamed)),
            Get_NamesExactly(InOutcome._FirstNamed, InFirstId)))
        { return; }

        if (NOT TestTrue(FString::Printf(
                TEXT("[%s] and the second names link [%d] and nothing else, so neither publish knows ")
                TEXT("what the other moved [named %s]"),
                InOrder, InSecondId, *Get_IdsText(InOutcome._SecondNamed)),
            Get_NamesExactly(InOutcome._SecondNamed, InSecondId)))
        { return; }

        if (NOT TestTrue(FString::Printf(
                TEXT("[%s] with the box the second published reaching the corridor beside both links ")
                TEXT("[published %s vs corridor %s]"),
                InOrder, *Get_BoxText(InOutcome._SecondPublished),
                *Get_BoxText(InOutcome._BesideCorridor)),
            InOutcome._SecondPublished.IsValid != 0 &&
                InOutcome._SecondPublished.Intersect(InOutcome._BesideCorridor)))
        { return; }

        TestTrue(FString::Printf(
                TEXT("[%s] the corridor across the link that moved is flagged, whichever of the two ")
                TEXT("publishes moved it"),
                InOrder),
            InOutcome._CrossingIsFlagged);

        TestFalse(FString::Printf(
                TEXT("[%s] and the corridor through the same tile that crosses neither link is not"),
                InOrder),
            InOutcome._BesideIsFlagged);
    };

    // The link the corridor does NOT use moves first, so the newest publish is the one it does use.
    Do_Assert(
        Do_RunTwoToggles(
            TEXT("CkGroundNavInvalidationTwoTogglesSpareFirst"), SpareOnCrossingOn, SpareOnCrossingOff),
        TEXT("spare then crossing"), kSpareLinkId, kCrossingLinkId);

    // And the other way round, which is the order a note remembering only its newest publish gets
    // wrong: the corridor's own link moved FIRST, and nothing published after it names that id.
    Do_Assert(
        Do_RunTwoToggles(
            TEXT("CkGroundNavInvalidationTwoTogglesCrossingFirst"), SpareOffCrossingOff, SpareOnCrossingOff),
        TEXT("crossing then spare"), kCrossingLinkId, kSpareLinkId);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Invalidation_ChangedLinkIdsNameExactlyWhatChanged,
    "CkTests.UnitTests.CkGroundNav.Invalidation.ChangedLinkIdsNameExactlyWhatChanged",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Invalidation_ChangedLinkIdsNameExactlyWhatChanged::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathinvalidation;

    // No world and no agent: this is the derive's own answer, and the invalidator above is only as
    // exact as this list is.
    auto Params = Make_FlatParams();
    Params._Links = Make_BothLinks();

    auto Baked = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the link scene bakes with both records authored"),
        Bake(Make_LinkScene(), Params, *Baked)))
    { return false; }

    const auto Base = FCk_GroundNav_FieldPtr{Baked};

    if (NOT TestEqual(TEXT("and resolves both of them"), Base->_ResolvedLinks.Num(), 2))
    { return false; }

    const auto NextEpoch = Base->_Epoch.Get_Next();

    const auto Unchanged = Get_FieldWithLinks(*Base, Make_BothLinks(), NextEpoch);

    TestEqual(FString::Printf(TEXT("a derive over the same list names nothing [named %s]"),
            *Get_IdsText(Unchanged._ChangedLinkIds)),
        Unchanged._ChangedLinkIds.Num(), 0);

    auto WithAdded = Make_BothLinks();
    WithAdded.Emplace(Make_LinkRecord(
        kAddedLinkId, kBesideStart, kBesideGoal, ECk_EnableDisable::Enable));

    const auto Added = Get_FieldWithLinks(*Base, WithAdded, NextEpoch);

    TestTrue(FString::Printf(TEXT("an added record names the added id and nothing else [named %s]"),
            *Get_IdsText(Added._ChangedLinkIds)),
        Get_NamesExactly(Added._ChangedLinkIds, kAddedLinkId));

    const auto Disabled = Get_FieldWithLinks(
        *Base,
        TArray<FCk_GroundNav_LinkRecord>{
            Make_SpareLink(), Make_CrossingLink(ECk_EnableDisable::Disable)},
        NextEpoch);

    TestTrue(FString::Printf(TEXT("switching one off names that one [named %s]"),
            *Get_IdsText(Disabled._ChangedLinkIds)),
        Get_NamesExactly(Disabled._ChangedLinkIds, kCrossingLinkId));

    // Back on again, from the field that has it off - the other direction of the same toggle, which a
    // diff comparing only the AFTER side would miss.
    const auto ReEnabled = Get_FieldWithLinks(
        *Disabled._Field, Make_BothLinks(), Disabled._Field->_Epoch.Get_Next());

    TestTrue(FString::Printf(TEXT("switching it back on names it again [named %s]"),
            *Get_IdsText(ReEnabled._ChangedLinkIds)),
        Get_NamesExactly(ReEnabled._ChangedLinkIds, kCrossingLinkId));

    auto Repriced = Make_BothLinks();
    Repriced.Last().Set_CostMultiplierForward(kRepricedMultiplier);

    const auto WithNewPrice = Get_FieldWithLinks(*Base, Repriced, NextEpoch);

    TestTrue(FString::Printf(TEXT("repricing one names that one [named %s]"),
            *Get_IdsText(WithNewPrice._ChangedLinkIds)),
        Get_NamesExactly(WithNewPrice._ChangedLinkIds, kCrossingLinkId));

    const auto Removed = Get_FieldWithLinks(
        *Base, TArray<FCk_GroundNav_LinkRecord>{Make_SpareLink()}, NextEpoch);

    TestTrue(FString::Printf(TEXT("and removing one names the id it was authored under [named %s]"),
            *Get_IdsText(Removed._ChangedLinkIds)),
        Get_NamesExactly(Removed._ChangedLinkIds, kCrossingLinkId));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
