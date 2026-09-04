// The RUNTIME-STATE half of the link API: releasing by id, releasing everything a volume holds, and
// admitting many links under one completion - plus the per-link read of what the published field
// resolved.
//
// What each of these adds over the single-link drain is the ADMISSION and the BOOKKEEPING, and that is
// all this file asks about. What a composition then does with the records - where the two points
// project, what an end says when it finds no ground - is the composition's contract and is pinned
// against the resolver in Test_GroundNav_Links.
//
// A TOGGLE is not here: flipping _Enable is an ordinary Request_Link update that keeps the record and
// its id, and that is already pinned by Test_GroundNav_LinkAdmission.DisableIsAnUpdateNotARelease.
// Restating it here would be a second copy of one claim, not a second claim.
//
// A volume here never PUBLISHES a field: that needs a physics world for the geometry backend, and
// FFragment_GroundNavVolume_BuiltField::_Field is friend-private to the build, the repair and the two
// derives, with no test-only installer (Test_GroundNav_Settled says the same at its head). So
// Get_LinkResolution is asked here only in the form a headless world can put to it - the answer with
// nothing published, which is a rule of its own: a resolution is a property of a publish, and a
// record the volume already holds still has none until something has been published for it to resolve
// against. The other half - a resolved entry read back through the volume - needs a real bake and is
// owed to the PIE layer.
//
// The drains are invoked directly, as Test_GroundNav_LinkAdmission invokes them: a headless registry
// has no scheduler, so the view's TExclude filters are the header's claim rather than this file's.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment_Data.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_linkstate
{
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    // The volume covers [0,800] on both axes, so all six points below are inside it - three links, on
    // three different rows, so a release by id can be told from a release of the wrong entry.
    const auto kStartA = FVector{200.0, 200.0, 0.0};
    const auto kEndA = FVector{600.0, 200.0, 0.0};
    const auto kStartB = FVector{200.0, 400.0, 0.0};
    const auto kEndB = FVector{600.0, 400.0, 0.0};
    const auto kStartC = FVector{200.0, 600.0, 0.0};
    const auto kEndC = FVector{600.0, 600.0, 0.0};

    auto Make_Params() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Profile};
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

    // Every field of a resolution at its default: no id, no plates, NoSurface at both ends, neither
    // resolved nor live. The answer for an id no published field carries an entry for, and the answer
    // for every id while nothing is published at all.
    auto Get_IsEmptyResolution(
        const FCk_GroundNav_LinkResolution& InResolution) -> bool
    {
        return InResolution.Get_LinkId() == INDEX_NONE &&
               InResolution.Get_StartStatus() == ECk_NavSurface_QueryStatus::NoSurface &&
               InResolution.Get_EndStatus() == ECk_NavSurface_QueryStatus::NoSurface &&
               InResolution.Get_StartFlatPlate() == INDEX_NONE &&
               InResolution.Get_EndFlatPlate() == INDEX_NONE &&
               NOT InResolution.Get_Resolved() &&
               NOT InResolution.Get_Live();
    }
}

// --------------------------------------------------------------------------------------------------------------------

// By RECORD ID rather than by entity: the id is what a caller that has outlived the link entity still
// holds. It retires exactly the entry it names and leaves every other one where it was.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_ReleaseByIdRetiresTheEntry,
    "CkTests.UnitTests.CkGroundNav.LinkState.ReleaseByIdRetiresTheEntry",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_ReleaseByIdRetiresTheEntry::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    auto LinkEntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntityA, Make_Record(kStartA, kEndA)}, {});
    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntityB, Make_Record(kStartB, kEndB)}, {});

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestEqual(TEXT("both links are admitted first"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 2))
    { return false; }

    Volume.Try_Remove<ck::FTag_GroundNavVolume_LinksDirty>();

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseLink_ById(Volume,
        FCk_Request_GroundNavVolume_ReleaseLink_ById{1},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("the named id is the only record dropped"), Records.Num(), 1))
    { return false; }

    TestTrue(TEXT("and the one that stays is the one that was not named"), Records[0].Get_Id() == 0);
    TestFalse(TEXT("so the released id no longer resolves"),
        UCk_Utils_GroundNavVolume_UE::TryGet_LinkRecord(Volume, 1).IsSet());

    TestFalse(TEXT("the released link's entity loses its back-pointer"),
        LinkEntityB.Has<ck::FFragment_GroundNav_LinkRef>());
    TestTrue(TEXT("and the other entity keeps its own"),
        LinkEntityA.Has<ck::FFragment_GroundNav_LinkRef>());

    TestTrue(TEXT("the derive is raised to retire what the link contributed"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("the release completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    // Retired with the record, exactly as an entity-shaped release retires it: the counter is what
    // guarantees a released id never comes back meaning a different link.
    TestEqual(TEXT("a release rewinds no id"),
        Volume.Get<ck::FFragment_GroundNavVolume_Links>().Get_NextId(), 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_ReleaseByUnknownIdIsSucceeded,
    "CkTests.UnitTests.CkGroundNav.LinkState.ReleaseByUnknownIdIsSucceeded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_ReleaseByUnknownIdIsSucceeded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartA, kEndA)}, {});

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestEqual(TEXT("the link is admitted first"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 1))
    { return false; }

    Volume.Try_Remove<ck::FTag_GroundNavVolume_LinksDirty>();

    const auto Listener = Make_Listener();

    // Ids are never reused, so an id the volume does not hold means retired or never handed out -
    // and the caller's intent, this volume holds no record under it, already holds.
    UCk_Utils_GroundNavVolume_UE::Request_ReleaseLink_ById(Volume,
        FCk_Request_GroundNavVolume_ReleaseLink_ById{7},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    TestEqual(TEXT("the release completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded rather than a failure about a record nobody made"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestEqual(TEXT("the record the volume does hold is untouched"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 1);
    TestFalse(TEXT("and no derive is owed for a change that changed nothing"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// One request, one derive, whatever the list held. The tag is idempotent, so what "one derive" means
// here is that the whole retirement is a single raise rather than a per-record one - and the volume is
// left holding nothing, with every back-pointer gone with its record.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_ReleaseAllEmptiesTheVolumeAndRaisesOneDirty,
    "CkTests.UnitTests.CkGroundNav.LinkState.ReleaseAllEmptiesTheVolumeAndRaisesOneDirty",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_ReleaseAllEmptiesTheVolumeAndRaisesOneDirty::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    auto LinkEntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityC = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntityA, Make_Record(kStartA, kEndA)}, {});
    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntityB, Make_Record(kStartB, kEndB)}, {});
    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntityC, Make_Record(kStartC, kEndC)}, {});

    DoDrain_LinkRequests(World, Volume);

    if (NOT TestEqual(TEXT("all three links are admitted first"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).Num(), 3))
    { return false; }

    Volume.Try_Remove<ck::FTag_GroundNavVolume_LinksDirty>();

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseAllLinks(Volume,
        FCk_Request_GroundNavVolume_ReleaseAllLinks{},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("the volume holds nothing afterwards"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());

    TestFalse(TEXT("the first entity's back-pointer went with its record"),
        LinkEntityA.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("and the second's"),
        LinkEntityB.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("and the third's"),
        LinkEntityC.Has<ck::FFragment_GroundNav_LinkRef>());

    TestTrue(TEXT("one derive is owed for the whole retirement"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("the bulk release completes exactly once, not once per record"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    // Every id this volume handed out stays retired, so the emptied list can still be diffed against
    // a field that was resolved before it.
    TestEqual(TEXT("emptying the list rewinds no id"),
        Volume.Get<ck::FFragment_GroundNavVolume_Links>().Get_NextId(), 3);

    Volume.Try_Remove<ck::FTag_GroundNavVolume_LinksDirty>();

    // A volume that already holds nothing satisfies the caller's intent before the request is made,
    // and Succeeded is what that means - the same answer releasing one unheld record gives.
    UCk_Utils_GroundNavVolume_UE::Request_ReleaseAllLinks(Volume,
        FCk_Request_GroundNavVolume_ReleaseAllLinks{},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    TestEqual(TEXT("releasing an already empty list completes too"),
        Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);
    TestFalse(TEXT("and owes no derive for a change that changed nothing"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// ALL or NOTHING. Every entry is judged before any is applied, so a batch carrying one refusal leaves
// the volume exactly as it found it: no records, no back-pointers, no derive, and the id counter
// unspent. A batch that admitted its good half would leave the caller unable to say which part of its
// intent holds.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_BatchAdmitsAllOrNothing,
    "CkTests.UnitTests.CkGroundNav.LinkState.BatchAdmitsAllOrNothing",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_BatchAdmitsAllOrNothing::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    auto LinkEntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityC = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    // Below one, so the edge would cost less than its own Euclidean length and the search heuristic
    // would stop being admissible. The entries on either side of it are impeccable.
    auto Underpriced = Make_Record(kStartB, kEndB);
    Underpriced.Set_CostMultiplierForward(0.5f);

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_LinkBatch(Volume,
        FCk_Request_GroundNavVolume_LinkBatch{TArray<FCk_Request_GroundNavVolume_Link>{
            FCk_Request_GroundNavVolume_Link{LinkEntityA, Make_Record(kStartA, kEndA)},
            FCk_Request_GroundNavVolume_Link{LinkEntityB, Underpriced},
            FCk_Request_GroundNavVolume_Link{LinkEntityC, Make_Record(kStartC, kEndC)}}},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("batch is admitted whole or not at all"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_LinkRequests(World, Volume);

    TestTrue(TEXT("a refused batch admits no record at all, not even its good ones"),
        UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume).IsEmpty());

    TestFalse(TEXT("the entry before the refusal gets no back-pointer"),
        LinkEntityA.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("nor the refused one"),
        LinkEntityB.Has<ck::FFragment_GroundNav_LinkRef>());
    TestFalse(TEXT("nor the entry after it"),
        LinkEntityC.Has<ck::FFragment_GroundNav_LinkRef>());

    TestFalse(TEXT("and no derive is owed for a batch that applied nothing"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    // Unspent, so the ids a re-submitted batch is handed start where they would have.
    TestEqual(TEXT("a refused batch spends no id"),
        Volume.Get<ck::FFragment_GroundNavVolume_Links>().Get_NextId(), 0);

    TestEqual(TEXT("the batch completes exactly once, not once per entry"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_BatchOfThreeIsOneDirtyAndThreeEntries,
    "CkTests.UnitTests.CkGroundNav.LinkState.BatchOfThreeIsOneDirtyAndThreeEntries",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_BatchOfThreeIsOneDirtyAndThreeEntries::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    auto LinkEntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto LinkEntityC = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_LinkBatch(Volume,
        FCk_Request_GroundNavVolume_LinkBatch{TArray<FCk_Request_GroundNavVolume_Link>{
            FCk_Request_GroundNavVolume_Link{LinkEntityA, Make_Record(kStartA, kEndA)},
            FCk_Request_GroundNavVolume_Link{LinkEntityB, Make_Record(kStartB, kEndB)},
            FCk_Request_GroundNavVolume_Link{LinkEntityC, Make_Record(kStartC, kEndC)}}},
        Make_Delegate(Listener.Get()));

    DoDrain_LinkRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_LinkRecords(Volume);

    if (NOT TestEqual(TEXT("every entry is admitted"), Records.Num(), 3))
    { return false; }

    // Handed out in entry order from the same monotone counter one-at-a-time admission draws from.
    TestTrue(TEXT("the first entry takes the first id"), Records[0].Get_Id() == 0);
    TestTrue(TEXT("the second the next"), Records[1].Get_Id() == 1);
    TestTrue(TEXT("and the third the one after that"), Records[2].Get_Id() == 2);

    TestTrue(TEXT("every entity gets its back-pointer"),
        LinkEntityA.Has<ck::FFragment_GroundNav_LinkRef>() &&
        LinkEntityB.Has<ck::FFragment_GroundNav_LinkRef>() &&
        LinkEntityC.Has<ck::FFragment_GroundNav_LinkRef>());

    TestTrue(TEXT("one derive is owed for the whole batch"),
        Volume.Has<ck::FTag_GroundNavVolume_LinksDirty>());

    TestEqual(TEXT("the batch completes exactly once, not once per entry"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A resolution is a property of a PUBLISH. The volume holds the record the moment the drain admits it,
// but there is nothing resolved to report until something has been published for it to resolve
// against - which is the whole reason this read is separate from TryGet_LinkRecord.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_LinkResolutionIsEmptyWithNothingPublished,
    "CkTests.UnitTests.CkGroundNav.LinkState.LinkResolutionIsEmptyWithNothingPublished",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_LinkResolutionIsEmptyWithNothingPublished::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    UCk_Utils_GroundNavVolume_UE::Request_Link(Volume,
        FCk_Request_GroundNavVolume_Link{LinkEntity, Make_Record(kStartA, kEndA)}, {});

    DoDrain_LinkRequests(World, Volume);

    // The AUTHORED half is there: the record is on the volume, under the id the drain assigned.
    if (NOT TestTrue(TEXT("the volume holds the record"),
        UCk_Utils_GroundNavVolume_UE::TryGet_LinkRecord(Volume, 0).IsSet()))
    { return false; }

    TestTrue(TEXT("yet its resolution reads empty, because nothing is published to resolve against"),
        Get_IsEmptyResolution(UCk_Utils_GroundNavVolume_UE::Get_LinkResolution(Volume, 0)));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_LinkState_LinkResolutionForUnknownIdIsEmpty,
    "CkTests.UnitTests.CkGroundNav.LinkState.LinkResolutionForUnknownIdIsEmpty",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_LinkState_LinkResolutionForUnknownIdIsEmpty::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_linkstate;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    // An id no volume ever handed out reads the default rather than a partly filled answer, so a
    // caller can tell "nothing to report" from "reported nothing found".
    TestTrue(TEXT("an id the volume never handed out reads empty"),
        Get_IsEmptyResolution(UCk_Utils_GroundNavVolume_UE::Get_LinkResolution(Volume, 42)));

    // And so does the id an emptied volume would next hand out, for the same reason: the read is
    // about a published field, and this volume has none.
    TestTrue(TEXT("and so does the first id it would"),
        Get_IsEmptyResolution(UCk_Utils_GroundNavVolume_UE::Get_LinkResolution(Volume, 0)));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
