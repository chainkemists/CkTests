// When an authored nav link is LIVE on the ground, and when a volume owing a link derive is SETTLED.
//
// "Live" is DERIVED at the read and stored nowhere, which is the property under test: there is no flag
// anybody has to remember to clear, so the only way to be wrong about it is to read the wrong thing.
// The rule is stated over a field and a record, and that is how most of this file asks it - a
// stub-baked field and a hand-built record need no world, no physics and no scheduler, so the epoch
// arithmetic can be pinned exactly instead of waited on.
//
// It is narrower than the markup rule in exactly one way, and that way is the whole point: the link
// must have RESOLVED. A markup that reaches nothing is admitted and simply decides nothing, where a
// link that did not resolve is a link that is not there.
//
// The entity-shaped half is asked through the volume drain directly, as Test_GroundNav_LinkAdmission
// does: a headless registry has no scheduler, and a volume cannot publish a field without a physics
// world for its geometry backend, so what the entity path can prove here is that a link is NOT live
// until the drain has recorded it and something has been published for it to be live on.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldLinks.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "Test_GroundNav_QueryFixtures.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_linklive
{
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::Get_FieldWithLinks;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;

    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    // The fixture bakes at epoch 1, so a record stamped against it was submitted against the publish
    // that is already out - and that publish, by construction, knew nothing about it. Only a LATER
    // epoch on both endpoint tiles is a republish that observed the link.
    constexpr auto kBakedEpoch = int64{1};
    constexpr auto kRepublishedEpoch = int64{2};

    // Two points on GROUND in the query scene's 2x2 field of 800uu tiles, deliberately on DIFFERENT
    // tiles: the rule is about both ends, and a link inside one tile could not tell the two apart.
    const auto kLinkStart = FVector{410.0, 410.0, kGroundZ};
    const auto kLinkEnd = FVector{1400.0, 1400.0, kGroundZ};

    auto Make_Link(
        int32 InId) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, kLinkStart, kLinkEnd};

        Record.Set_ClearanceUu(60.0f);
        Record.Set_RequestedAtEpoch(kBakedEpoch);

        return Record;
    }

    auto Get_TileIndexAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InPoint) -> int32
    {
        const auto* Tile = InField.Get_TileAt(InPoint);

        if (Tile == nullptr)
        { return INDEX_NONE; }

        return InField._Tiles.IndexOfByPredicate(
            [&](const FCk_GroundNav_Tile& InCandidate) -> bool
            {
                return &InCandidate == Tile;
            });
    }

    // ---- The volume-shaped half --------------------------------------------------------------------------

    auto Make_VolumeParams() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Profile};
    }

    // The drain assigns the id from the volume's own counter, so what a request carries is ignored.
    constexpr auto kUnassignedId = int32{INDEX_NONE};

    auto Make_VolumeLink() -> FCk_GroundNav_LinkRecord
    {
        return FCk_GroundNav_LinkRecord{
            kUnassignedId, FVector{200.0, 200.0, 0.0}, FVector{600.0, 200.0, 0.0}};
    }

    auto DoDrain_LinkRequests(
        ck::FEcsWorld&              InWorld,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_HandleLinkRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_Params>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Links>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_LinkRequests>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkLive_LinkIsNotLiveUntilBothEndpointTilesRepublish,
    "CkTests.UnitTests.CkGroundNav.LinkLive.LinkIsNotLiveUntilBothEndpointTilesRepublish",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkLive_LinkIsNotLiveUntilBothEndpointTilesRepublish::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linklive;

    auto Source = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the field bakes"), Bake(Make_QueryScene(), Make_QueryParams(), *Source)))
    { return false; }

    const auto Published = FCk_GroundNav_FieldPtr{Source};

    const auto Record = Make_Link(0);

    // Nothing resolved it, because it was authored after the publish that is out. There is no entry
    // for it to be live through, and answering true would mean only that nothing had contradicted it.
    TestFalse(TEXT("a link the published field never resolved is not live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(*Published, Record));

    const auto Derived = Get_FieldWithLinks(
        *Published, TArray<FCk_GroundNav_LinkRecord>{Record}, FCk_GroundNav_Epoch{kRepublishedEpoch});

    if (NOT TestTrue(TEXT("the derive completes and yields a field"),
        Derived.Value.Get_IsCompleted() && Derived.Key.IsValid()))
    { return false; }

    if (NOT TestEqual(TEXT("with the link resolved at both ends"),
        Derived.Key->Get_UnresolvedLinkCount(), 0))
    { return false; }

    const auto StartTileIndex = Get_TileIndexAt(*Derived.Key, kLinkStart);
    const auto EndTileIndex = Get_TileIndexAt(*Derived.Key, kLinkEnd);

    if (NOT TestTrue(TEXT("the two endpoints stand on two different tiles of the field"),
        StartTileIndex != INDEX_NONE && EndTileIndex != INDEX_NONE &&
        StartTileIndex != EndTileIndex))
    { return false; }

    TestTrue(TEXT("a link both of whose endpoint tiles republished past its stamp is live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(*Derived.Key, Record));

    // A derive copies and the caller swaps, so what a reader is already holding is never touched - and
    // the link is still not live against it.
    TestFalse(TEXT("and is not live against the field it was derived from"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(*Published, Record));

    // BOTH ends, one at a time: a link is only as live as its laggard, so putting either endpoint tile
    // back to the epoch the record was stamped against is enough to take it out of live.
    auto StartBehind = FCk_GroundNav_Field{*Derived.Key};
    StartBehind._Tiles[StartTileIndex]._Epoch = FCk_GroundNav_Epoch{kBakedEpoch};

    TestFalse(TEXT("a link whose START tile has not republished past its stamp is not live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(StartBehind, Record));

    auto EndBehind = FCk_GroundNav_Field{*Derived.Key};
    EndBehind._Tiles[EndTileIndex]._Epoch = FCk_GroundNav_Epoch{kBakedEpoch};

    TestFalse(TEXT("and neither is one whose END tile has not"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(EndBehind, Record));

    // Equal, not merely older: _RequestedAtEpoch is stamped with the epoch the field was ALREADY
    // published at, so a tile AT that epoch is the very publish the record was submitted against.
    auto EndAtTheStamp = FCk_GroundNav_Field{*Derived.Key};
    EndAtTheStamp._Tiles[EndTileIndex]._Epoch = FCk_GroundNav_Epoch{Record.Get_RequestedAtEpoch()};

    TestFalse(TEXT("a tile AT the stamped epoch is the publish that knew nothing of the link"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(EndAtTheStamp, Record));

    // The clause with no markup analogue: an end that found no ground leaves the entry present but
    // UNRESOLVED, and an unresolved link is not there however far its tiles have republished.
    auto Unresolved = FCk_GroundNav_Field{*Derived.Key};
    Unresolved._ResolvedLinks[0]._EndStatus = ECk_NavSurface_QueryStatus::NoSurface;

    TestFalse(TEXT("a link that did not resolve is not live even with both tiles ahead of its stamp"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(Unresolved, Record));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A RELEASED link is not live, and the reason is structural rather than a flag: every entry is
// re-derived wholesale from the whole record list at every publish, so a list one shorter is the whole
// change - the entry simply is not in the field any more. Asked in both shapes, because the entity path
// and the field path can fail differently.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkLive_ReleasedLinkIsNotLive,
    "CkTests.UnitTests.CkGroundNav.LinkLive.ReleasedLinkIsNotLive",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkLive_ReleasedLinkIsNotLive::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linklive;

    auto Source = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the field bakes"), Bake(Make_QueryScene(), Make_QueryParams(), *Source)))
    { return false; }

    const auto Published = FCk_GroundNav_FieldPtr{Source};

    const auto Record = Make_Link(0);

    const auto WithLink = Get_FieldWithLinks(
        *Published, TArray<FCk_GroundNav_LinkRecord>{Record}, FCk_GroundNav_Epoch{kRepublishedEpoch});

    if (NOT TestTrue(TEXT("the link is live once a publish has resolved it"),
        WithLink.Value.Get_IsCompleted() && WithLink.Key.IsValid() &&
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(*WithLink.Key, Record)))
    { return false; }

    // The release, as the derive sees it: the same field re-resolved from a list that no longer holds
    // the record.
    const auto WithoutLink = Get_FieldWithLinks(
        *WithLink.Key, TArray<FCk_GroundNav_LinkRecord>{}, FCk_GroundNav_Epoch{kRepublishedEpoch + 1});

    if (NOT TestTrue(TEXT("re-deriving from an empty list completes and yields a field"),
        WithoutLink.Value.Get_IsCompleted() && WithoutLink.Key.IsValid()))
    { return false; }

    TestEqual(TEXT("the released link leaves no entry behind"),
        WithoutLink.Key->Get_ResolvedLinkCount(), 0);
    TestFalse(TEXT("and is not live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLiveOnField(*WithoutLink.Key, Record));

    // The entity shape of the same question. The volume publishes nothing here, so this is the guard
    // half of the rule: no back-pointer means no link to be live, before and after the release.
    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_VolumeParams());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    TestFalse(TEXT("an entity nobody has linked is not live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLive(LinkEntity));

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_VolumeLink()}, {});

    TestFalse(TEXT("an enqueued link is not live - the drain has not recorded it"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLive(LinkEntity));

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestTrue(TEXT("the drain records the link"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>()))
    { return false; }

    // Recorded is not live. The volume has published nothing, so there is no ground for the link to be
    // live on - and answering true here would mean only that nothing had contradicted it.
    TestFalse(TEXT("and a recorded link on a volume with nothing published is still not live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLive(LinkEntity));

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseLink(Volume,
        FCk_Request_GroundNavVolume_ReleaseLink{LinkEntity}, {});

    DoDrain_LinkRequests(World, Volume);

    TestFalse(TEXT("a released link keeps no back-pointer"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("and is not live"),
        UCk_Utils_GroundNavVolume_UE::Get_IsLinkLive(LinkEntity));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// SETTLED is about the VOLUME rather than about one link: a field is published and no stage still owes
// this volume a publish. A link derive is one such stage, and Get_IsSettled has to know about it or a
// fixture will settle while a re-resolution is owed.
//
// This is a NECESSARY-condition pin, deliberately, and for the reason Test_GroundNav_Settled states:
// a volume here never PUBLISHES a field, so the missing field already answers false and the marker
// cannot be shown to be the REASON. The clause that IS discriminating headlessly is the request queue,
// which reads EMPTINESS rather than presence - the drain resets the array in place and leaves the
// fragment on the volume, so a presence test would read every volume that was ever asked for anything
// as permanently unsettled. That shape is pinned directly below.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkLive_SettledIsFalseWhileALinkDeriveIsOwed,
    "CkTests.UnitTests.CkGroundNav.LinkLive.SettledIsFalseWhileALinkDeriveIsOwed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkLive_SettledIsFalseWhileALinkDeriveIsOwed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linklive;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_VolumeParams());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_VolumeLink()}, {});

    TestFalse(TEXT("a volume holding a queued link request is not settled"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(Volume));

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestTrue(TEXT("the drain leaves a link derive owed"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>()))
    { return false; }

    TestFalse(TEXT("and a volume owing a link derive is not settled"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(Volume));

    // The discriminating half. The drain reset the queue's array in place and left the fragment on the
    // volume, so the settled clause has to read EMPTINESS: a presence test would report this volume as
    // permanently unsettled from here on, whatever any other stage said.
    if (NOT TestTrue(TEXT("the drained volume still carries the link request fragment"),
        Volume.Has<ck::FFragment_GroundNavVolume_LinkRequests>()))
    { return false; }

    TestTrue(TEXT("with nothing in it"),
        Volume.Get<ck::FFragment_GroundNavVolume_LinkRequests>().Get_Requests().IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
