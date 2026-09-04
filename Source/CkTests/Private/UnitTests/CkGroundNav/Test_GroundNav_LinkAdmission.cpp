// Admitting an authored navigation link onto a ground-nav volume.
//
// This is ADMISSION only - what the drain accepts, what it rejects, what the volume then holds, and
// which stage it hands the change to. What a COMPOSITION does with an admitted record - where its two
// points project, what the entry says when an end finds no ground - is the composition's contract and
// is pinned against the resolver in Test_GroundNav_Links. The drains are invoked directly, as
// Test_GroundNav_MarkupAdmission invokes theirs: a headless registry has no scheduler, so the view's
// TExclude filters are the header's claim rather than this file's.
//
// A volume here never PUBLISHES a field: that needs a physics world for the geometry backend, and
// FFragment_GroundNavVolume_BuiltField::_Field is friend-private to the build, the repair and the two
// derives, with no test-only installer. So the link derive is asked here only in its nothing-published
// form - which is a rule of its own, and the reason a link authored before the first bake is never
// lost. The published-field form, where a derive re-resolves and republishes, is Test_GroundNav_Links'
// against Get_FieldWithLinks directly.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_AreaPolicy.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Link_Ladder, "Ck.Test.GroundNav.Link.Ladder");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Link_Unpublished, "Ck.Test.GroundNav.Link.Unpublished");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_linkadmission
{
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    // The volume covers [0,800] on both axes, so these two are inside it and kOutsidePoint is not.
    const auto kStartPoint = FVector{200.0, 200.0, 0.0};
    const auto kEndPoint = FVector{600.0, 200.0, 0.0};
    const auto kMovedEndPoint = FVector{600.0, 600.0, 0.0};
    const auto kOutsidePoint = FVector{2000.0, 200.0, 0.0};

    auto Make_Params() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Profile};
    }

    // Idempotent: re-registering a tag with the same policy is a silent no-op, so every test may arm
    // the table without the registry caring which of them ran first.
    auto DoRegister_TestAreaPolicies() -> void
    {
        ck::nav_surface::Register_AreaPolicy(TAG_Test_GroundNav_Link_Ladder.GetTag(),
            FCk_NavSurface_AreaPolicy{ECk_NavSurface_AreaPolicyKind::Cost, 2.0f});
    }

    // The id the CALLER supplies is deliberately not the one the volume hands out: the drain assigns
    // from _NextId, and every case below reads the record back to say so.
    constexpr auto kUnassignedId = int32{INDEX_NONE};

    auto Make_Record(
        const FVector& InStart,
        const FVector& InEnd) -> FCk_GroundNav_LinkRecord
    {
        return FCk_GroundNav_LinkRecord{kUnassignedId, InStart, InEnd};
    }

    auto Make_Listener() -> TStrongObjectPtr<UCk_Test_CompletionListener_UE>
    {
        return TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
            NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};
    }

    auto Make_Delegate(
        UCk_Test_CompletionListener_UE* InListener) -> FCk_Delegate_Request_OnCompleted
    {
        auto Delegate = FCk_Delegate_Request_OnCompleted{};
        Delegate.BindDynamic(InListener, &UCk_Test_CompletionListener_UE::OnRequestCompleted);
        return Delegate;
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

    auto DoRun_LinkDerive(
        ck::FEcsWorld&              InWorld,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_LinkDerive{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_Links>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_InvalidEntityFails,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.InvalidEntityFails",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_InvalidEntityFails::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    const auto Listener = Make_Listener();

    // The entity is the identity the record would be keyed on, so there is nothing to key one on.
    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{FCk_Handle{}, Make_Record(kStartPoint, kEndPoint)},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("the request names an invalid link Entity"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("an invalid entity admits no record"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and raises no link derive"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("the rejected request still completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_EqualEndpointsFail,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.EqualEndpointsFail",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_EqualEndpointsFail::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    // Both points inside the volume and both finite, so the rejection can only be that they are one
    // point: a zero span prices at zero however high the multiplier is.
    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kStartPoint)},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("are not two distinct finite points"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("one point admits no link"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and leaves no back-pointer behind"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("and raises no link derive"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("the rejected request still completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A link is VOLUME-SCOPED. The field it resolves against covers this volume's ground and no other, so
// an endpoint outside those bounds names ground this volume can never answer for - and there is nothing
// in the module that composes two fields, so a cross-volume link is unrepresentable rather than merely
// unbuilt.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_EndpointOutsideTheVolumeFails,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.EndpointOutsideTheVolumeFails",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_EndpointOutsideTheVolumeFails::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the far endpoint really is outside the authored bounds"),
        NOT Make_Params().Get_VolumeBounds().IsInsideOrOn(kOutsidePoint)))
    { return false; }

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kOutsidePoint)},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("are not both inside the volume's bounds"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("an endpoint outside the volume admits no link"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and leaves no back-pointer behind"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());

    TestEqual(TEXT("the rejected request still completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The multipliers price the link's own straight-line span, so one below 1.0 would make an edge cost
// less than its Euclidean length - and the search's Euclidean heuristic would stop being admissible.
// It would then return cheap paths that are not the cheapest, and no consumer could tell.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_MultiplierBelowOneFails,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.MultiplierBelowOneFails",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_MultiplierBelowOneFails::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto ForwardEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto BackwardEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    auto CheapForward = Make_Record(kStartPoint, kEndPoint);
    CheapForward.Set_CostMultiplierForward(0.5f);

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{ForwardEntity, CheapForward},
        Make_Delegate(Listener.Get()));

    // BOTH directions are refused by the same clause, so both are asked: a link priced honestly one way
    // and dishonestly the other is still a link that breaks the heuristic.
    auto CheapBackward = Make_Record(kStartPoint, kEndPoint);
    CheapBackward.Set_CostMultiplierBackward(0.999f);

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{BackwardEntity, CheapBackward},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("must both be at least 1.0"),
        EAutomationExpectedErrorFlags::Contains,
        4);

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("neither under-priced link is admitted"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and neither entity carries a back-pointer"),
        ForwardEntity.Has<ck::FFragment_GroundNav_LinkRef>() ||
        BackwardEntity.Has<ck::FFragment_GroundNav_LinkRef>());

    TestEqual(TEXT("both rejected requests complete"), Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    // Exactly 1.0 is the boundary and is admitted: an edge that costs exactly its own length is what
    // the heuristic is admissible against.
    auto ExactEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    auto ExactlyOne = Make_Record(kStartPoint, kEndPoint);
    ExactlyOne.Set_CostMultiplierForward(1.0f);
    ExactlyOne.Set_CostMultiplierBackward(1.0f);

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{ExactEntity, ExactlyOne}, {});

    DoDrain_LinkRequests(World, Volume);

    TestEqual(TEXT("a multiplier of exactly one is admitted"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// This module never decides what a tag MEANS, so a link carrying one goes through the same neutral
// registry a markup does. An UNSET tag is the difference between the two: a markup exists to say what
// ground means and one with no tag decides nothing, where a link's traversal stands on its own.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_UnregisteredAreaTagFails,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.UnregisteredAreaTagFails",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_UnregisteredAreaTagFails::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the tag under test is a real tag that simply has no policy"),
        TAG_Test_GroundNav_Link_Unpublished.GetTag().IsValid() &&
        NOT ck::nav_surface::TryGet_AreaPolicy(TAG_Test_GroundNav_Link_Unpublished.GetTag()).IsSet()))
    { return false; }

    const auto Listener = Make_Listener();

    auto Record = Make_Record(kStartPoint, kEndPoint);
    Record.Set_AreaTag(TAG_Test_GroundNav_Link_Unpublished.GetTag());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Record},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("nothing published what that tag MEANS"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("a tag nothing published admits no link"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and leaves no back-pointer behind"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());

    TestEqual(TEXT("the rejected request still completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_UnsetAreaTagIsAdmitted,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.UnsetAreaTagIsAdmitted",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_UnsetAreaTagIsAdmitted::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto UntaggedEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto TaggedEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{UntaggedEntity, Make_Record(kStartPoint, kEndPoint)},
        Make_Delegate(Listener.Get()));

    // The registered tag beside it, so "unset is admitted" cannot pass by the tag clause being dead.
    auto Tagged = Make_Record(kStartPoint, kMovedEndPoint);
    Tagged.Set_AreaTag(TAG_Test_GroundNav_Link_Ladder.GetTag());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{TaggedEntity, Tagged},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("both links are admitted"), Records.Num(), 2))
    { return false; }

    TestFalse(TEXT("the first carries no area tag"), Records[0].Get_AreaTag().IsValid());
    TestTrue(TEXT("and the second carries the one it was authored with"),
        Records[1].Get_AreaTag() == TAG_Test_GroundNav_Link_Ladder.GetTag());

    TestTrue(TEXT("the first record is id 0"), Records[0].Get_Id() == 0);
    TestTrue(TEXT("and the second is id 1 - ids are handed out in admission order"),
        Records[1].Get_Id() == 1);

    // Nothing has baked, so the volume's published epoch is zero and that is what a record is stamped
    // against. A rebuild moving the epoch on is not reachable without a physics world.
    TestEqual(TEXT("stamped against the volume's currently published epoch"),
        Records[0].Get_RequestedAtEpoch(), static_cast<int64>(0));

    TestTrue(TEXT("the link entity carries the back-pointer"),
        UntaggedEntity.Has<ck::FFragment_GroundNav_LinkRef>());
    TestTrue(TEXT("naming the volume that holds the record"),
        UntaggedEntity.Get<ck::FFragment_GroundNav_LinkRef>().Get_VolumeEntity() ==
        Volume.ConvertToHandle());
    TestEqual(TEXT("and the record's id"),
        UntaggedEntity.Get<ck::FFragment_GroundNav_LinkRef>().Get_RecordId(), 0);

    TestTrue(TEXT("a link change raises the link derive and nothing else"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());
    TestFalse(TEXT("no repair - a link changes neither cells nor plates"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and no cost re-derive either"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupCostDirty>());

    TestEqual(TEXT("both requests complete"), Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The LINK ENTITY is the identity, not the two points: a second request naming the same entity updates
// the record in place and keeps its id, because the id is what every later request and every consumer
// keys on. Renumbering it on a move would retire connectivity nothing asked to retire.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_SecondRequestUpdatesInPlaceAndKeepsTheId,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.SecondRequestUpdatesInPlaceAndKeepsTheId",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_SecondRequestUpdatesInPlaceAndKeepsTheId::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kEndPoint)}, {});

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestEqual(TEXT("the link is admitted first"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 1))
    { return false; }

    auto Moved = Make_Record(kStartPoint, kMovedEndPoint);
    Moved.Set_CostMultiplierForward(4.0f);
    Moved.Set_Direction(ECk_GroundNav_LinkDirection::Forward);

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Moved}, {});

    DoDrain_LinkRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("the second request adds no second record"), Records.Num(), 1))
    { return false; }

    TestTrue(TEXT("the record keeps the id it was first admitted under"), Records[0].Get_Id() == 0);
    TestTrue(TEXT("and the back-pointer still names that id"),
        LinkEntity.Get<ck::FFragment_GroundNav_LinkRef>().Get_RecordId() == 0);

    TestTrue(TEXT("the endpoint moved"), Records[0].Get_End().Equals(kMovedEndPoint));
    TestEqual(TEXT("the price moved"), Records[0].Get_CostMultiplierForward(), 4.0f);
    TestTrue(TEXT("and so did the direction"),
        Records[0].Get_Direction() == ECk_GroundNav_LinkDirection::Forward);

    // Not reused, even though the update took no new one: an id retired by a release must never come
    // back meaning a different link, and the counter is what guarantees it.
    TestEqual(TEXT("an update consumes no id"),
        Volume.Get<ck::FFragment_GroundNavVolume_Links>().Get_NextId(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_ReleaseRetiresTheId,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.ReleaseRetiresTheId",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_ReleaseRetiresTheId::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kEndPoint)},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestEqual(TEXT("the link is admitted first"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 1))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseLink(Volume,
        FCk_Request_GroundNavVolume_ReleaseLink{LinkEntity},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("releasing drops the record"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and the back-pointer with it"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("so the id no longer resolves"),
        UCk_Utils_GroundNavVolume_UE::TryGet_LinkRecord(Volume, 0).IsSet());

    TestTrue(TEXT("and the derive is raised to retire what the link contributed"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("both requests completed"), Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("the release reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    // Ids are retired with their records, so the next admission does not reuse the one just freed.
    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kEndPoint)}, {});

    DoDrain_LinkRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("re-linking the same entity admits a fresh record"), Records.Num(), 1))
    { return false; }

    TestTrue(TEXT("carrying a HIGHER id rather than the retired one"), Records[0].Get_Id() == 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_ReleaseOfUnknownEntityIsSucceeded,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.ReleaseOfUnknownEntityIsSucceeded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_ReleaseOfUnknownEntityIsSucceeded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto StrangerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    // The caller's intent - this volume holds no record for that entity - already holds before the
    // request is made, and Succeeded is what that means.
    UCk_Utils_GroundNavVolume_UE::Request_ReleaseLink(Volume,
        FCk_Request_GroundNavVolume_ReleaseLink{StrangerEntity},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    TestEqual(TEXT("the release completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded rather than a failure about a record nobody made"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestTrue(TEXT("the volume still holds nothing"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("and no derive is owed for a change that changed nothing"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// Disabling is a state the record keeps CARRYING. A disabled link is not a released one: the record
// stays, its id stays, and the entity keeps its back-pointer - which is what lets the same link be
// switched back on without renumbering, and what makes a disable an ordinary update.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_DisableIsAnUpdateNotARelease,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.DisableIsAnUpdateNotARelease",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_DisableIsAnUpdateNotARelease::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kEndPoint)}, {});

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestTrue(TEXT("the link is admitted enabled"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num() == 1 &&
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume)[0].Get_Enable() ==
        ECk_EnableDisable::Enable))
    { return false; }

    Volume.Try_Remove<ck::FTag_GroundNavVolume_LinksDirty>();

    auto Disabled = Make_Record(kStartPoint, kEndPoint);
    Disabled.Set_Enable(ECk_EnableDisable::Disable);

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Disabled}, {});

    DoDrain_LinkRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("disabling removes no record"), Records.Num(), 1))
    { return false; }

    TestTrue(TEXT("the record carries the disabled state"),
        Records[0].Get_Enable() == ECk_EnableDisable::Disable);
    TestTrue(TEXT("under the id it was first admitted with"), Records[0].Get_Id() == 0);
    TestTrue(TEXT("and the entity keeps its back-pointer"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());

    TestTrue(TEXT("a disable is a change like any other and owes a derive"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A link authored before the first bake is never lost. The derive has nothing to derive FROM, so it
// clears its tag and waits - and the record it waits on is already on the volume, which is what the
// build reads into FCk_GroundNav_FieldParams::_Links when it starts.
//
// The half a headless world can pin is the SURVIVAL: the record is still there after the derive has
// cleared the tag, and nothing was published on the way. That the first publish then resolves it is
// the composer's contract and is pinned in Test_GroundNav_Links against Get_FieldWithLinks and the
// bake, because a volume cannot publish a field without a physics world for its geometry backend.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_RequestBeforeFirstBuildIsResolvedByThatBuild,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.RequestBeforeFirstBuildIsResolvedByThatBuild",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_RequestBeforeFirstBuildIsResolvedByThatBuild::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume composes and has published no field"),
        ck::IsValid(Volume) && ck::Is_NOT_Valid(UCk_Utils_GroundNavVolume_UE::Get_Field(Volume))))
    { return false; }

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kEndPoint)},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestEqual(TEXT("a link authored before any bake is admitted"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 1))
    { return false; }

    TestTrue(TEXT("and the derive is raised for it"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("the request rides ADMISSION, not the resolution it asked for"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    DoRun_LinkDerive(World, Volume);

    TestFalse(TEXT("the derive clears its tag rather than spinning on it every tick"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());
    TestTrue(TEXT("and publishes nothing, because there was nothing to derive from"),
        ck::Is_NOT_Valid(UCk_Utils_GroundNavVolume_UE::Get_Field(Volume)));

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("the record SURVIVES the wait"), Records.Num(), 1))
    { return false; }

    TestTrue(TEXT("whole, so the build that starts next reads exactly what was authored"),
        Records[0].Get_Start().Equals(kStartPoint) && Records[0].Get_End().Equals(kEndPoint));
    TestTrue(TEXT("and the entity still points at it"),
        LinkEntity.Has<ck::FFragment_GroundNav_LinkRef>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkAdmission_EndPlayCancelsPendingLinkRequests,
    "CkTests.UnitTests.CkGroundNav.LinkAdmission.EndPlayCancelsPendingLinkRequests",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkAdmission_EndPlayCancelsPendingLinkRequests::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkadmission;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartPoint, kEndPoint)},
        Make_Delegate(Listener.Get()));

    // The tag Request_DestroyEntity adds synchronously, and the one the drain's view excludes on. Added
    // directly because tearing the entity down for real needs the scheduler this world does not have.
    Volume.AddOrGet<ck::FTag_DestroyEntity_Initiate>();

    ck::FProcessor_GroundNavVolume_CancelPendingLinkRequests::ForEachEntity(
        FCk_Time{kSixtyHertz},
        Volume,
        Volume.Get<ck::FFragment_GroundNavVolume_LinkRequests>());

    TestEqual(TEXT("the queued request completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed_Cancelled rather than hanging on a drain that will never run"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed_Cancelled);

    TestTrue(TEXT("and nothing was admitted on the way out"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());
    TestFalse(TEXT("nor was a derive owed for it"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
