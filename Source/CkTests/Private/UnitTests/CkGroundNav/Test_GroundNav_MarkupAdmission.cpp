// Admitting area markup onto a ground-nav volume.
//
// This is ADMISSION only — what the drain accepts, what it
// rejects, what the volume then holds, and which dirty tag it raises. What the bake does with an
// admitted record is the bake's contract and is verified against the reduction in
// Test_GroundNav_MarkupMask. The drains are invoked directly, as the VoxelNav volume tests do: a
// headless registry has no scheduler, so the view's TExclude filters are the header's claim rather
// than this file's.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_AreaPolicy.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Markup_Blocked, "Ck.Test.GroundNav.Markup.Blocked");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Markup_Slow, "Ck.Test.GroundNav.Markup.Slow");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Markup_Unpublished, "Ck.Test.GroundNav.Markup.Unpublished");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_markup
{
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    // Distinctly not 1.0, so "the multiplier came from the policy" cannot pass on the record's default.
    constexpr auto kSlowCostMultiplier = 3.5f;

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
        ck::nav_surface::Register_AreaPolicy(TAG_Test_GroundNav_Markup_Blocked.GetTag(),
            FCk_NavSurface_AreaPolicy{ECk_NavSurface_AreaPolicyKind::Walkability, 1.0f});

        ck::nav_surface::Register_AreaPolicy(TAG_Test_GroundNav_Markup_Slow.GetTag(),
            FCk_NavSurface_AreaPolicy{ECk_NavSurface_AreaPolicyKind::Cost, kSlowCostMultiplier});
    }

    auto Make_Box(const FVector& InHalfExtents) -> FCk_AnyShape
    {
        return FCk_AnyShape{FCk_ShapeBox_Dimensions{InHalfExtents}};
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

    auto DoDrain_MarkupRequests(
        ck::FEcsWorld&              InWorld,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_HandleMarkupRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Markup>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_MarkupRequests>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_AdmitsAWalkabilityRecord,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_AdmitsAWalkabilityRecord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_AdmitsAWalkabilityRecord::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        Make_Delegate(Listener.Get()));

    TestTrue(TEXT("nothing is admitted by the call itself - the util enqueues and the processor mutates"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty());

    DoDrain_MarkupRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume);

    if (NOT TestEqual(TEXT("the drain admits exactly one record"), Records.Num(), 1))
    { return false; }

    TestEqual(TEXT("the first record is id 0"), Records[0].Get_Record().Get_Id(), 0);
    TestTrue(TEXT("keyed on the markup entity"), Records[0].Get_MarkupEntity() == MarkupEntity);

    TestTrue(TEXT("the record's kind comes from the tag's registered policy"),
        Records[0].Get_Record().Get_Kind() == ECk_GroundNav_MarkupKind::Walkability);
    TestTrue(TEXT("and it is enabled"),
        Records[0].Get_Record().Get_Enable() == ECk_EnableDisable::Enable);

    // Nothing has baked, so the volume's published epoch is zero and that is what the record is
    // stamped against. A rebuild moving the epoch on is not reachable without a physics world.
    TestEqual(TEXT("stamped against the volume's currently published epoch"),
        Records[0].Get_Record().Get_RequestedAtEpoch(), static_cast<int64>(0));

    if (NOT TestTrue(TEXT("the markup entity carries the back-pointer"),
        MarkupEntity.Has<ck::FFragment_GroundNav_MarkupRef>()))
    { return false; }

    const auto& MarkupRef = MarkupEntity.Get<ck::FFragment_GroundNav_MarkupRef>();

    TestTrue(TEXT("naming the volume that holds the record"),
        MarkupRef.Get_VolumeEntity() == Volume.ConvertToHandle());
    TestEqual(TEXT("and the record's id"), MarkupRef.Get_RecordId(), 0);

    TestTrue(TEXT("a walkability record raises the walkability dirty tag"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupWalkabilityDirty>());
    TestFalse(TEXT("and not the cost one - the two are answered by different stages"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupCostDirty>());

    TestEqual(TEXT("the request completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    TestTrue(TEXT("and the record is reachable by its id"),
        UCk_Utils_GroundNavVolume_UE::TryGet_MarkupRecord(Volume, 0).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_AdmitsACostRecord,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_AdmitsACostRecord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_AdmitsACostRecord::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Slow.GetTag()},
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume);

    if (NOT TestEqual(TEXT("the drain admits exactly one record"), Records.Num(), 1))
    { return false; }

    TestTrue(TEXT("a Cost policy yields a Cost record"),
        Records[0].Get_Record().Get_Kind() == ECk_GroundNav_MarkupKind::Cost);

    // Read from the registry rather than restated here: the point is that the record carries what the
    // POLICY published, not that it carries a number this file also happens to know.
    const auto Policy = ck::nav_surface::TryGet_AreaPolicy(TAG_Test_GroundNav_Markup_Slow.GetTag());

    if (NOT TestTrue(TEXT("the test tag has a published policy"), Policy.IsSet()))
    { return false; }

    TestEqual(TEXT("and the multiplier the policy published"),
        Records[0].Get_Record().Get_CostMultiplier(), Policy->Get_CostMultiplier());

    TestTrue(TEXT("a cost record raises the cost dirty tag"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupCostDirty>());
    TestFalse(TEXT("and not the walkability one - a retint owes no re-bake"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupWalkabilityDirty>());

    TestEqual(TEXT("the request completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_RejectsAnUnpublishedAreaTag,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_RejectsAnUnpublishedAreaTag",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_RejectsAnUnpublishedAreaTag::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    if (NOT TestTrue(TEXT("the tag under test is a real tag that simply has no policy"),
        TAG_Test_GroundNav_Markup_Unpublished.GetTag().IsValid() &&
        NOT ck::nav_surface::TryGet_AreaPolicy(TAG_Test_GroundNav_Markup_Unpublished.GetTag()).IsSet()))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Unpublished.GetTag()},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("nothing published what that tag MEANS"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_MarkupRequests(World, Volume);

    TestTrue(TEXT("a tag nothing published admits no record"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty());
    TestFalse(TEXT("and leaves no back-pointer behind"),
        MarkupEntity.Has<ck::FFragment_GroundNav_MarkupRef>());

    TestFalse(TEXT("no walkability dirty tag is raised"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupWalkabilityDirty>());
    TestFalse(TEXT("and no cost dirty tag either"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupCostDirty>());

    TestEqual(TEXT("the rejected request still completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_RejectsADegenerateShape,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_RejectsADegenerateShape",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_RejectsADegenerateShape::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    // A published tag, so the rejection can only be the shape's.
    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector::ZeroVector),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        Make_Delegate(Listener.Get()));

    AddExpectedError(
        TEXT("its shape and transform bound nothing"),
        EAutomationExpectedErrorFlags::Contains,
        2);

    DoDrain_MarkupRequests(World, Volume);

    TestTrue(TEXT("a volume that bounds nothing admits no record"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty());
    TestFalse(TEXT("and leaves no back-pointer behind"),
        MarkupEntity.Has<ck::FFragment_GroundNav_MarkupRef>());
    TestFalse(TEXT("and raises no dirty tag"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupWalkabilityDirty>());

    TestEqual(TEXT("the rejected request still completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_ReRequestUpdatesInPlace,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_ReRequestUpdatesInPlace",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_ReRequestUpdatesInPlace::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    if (NOT TestEqual(TEXT("the first request admits a record"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).Num(), 1))
    { return false; }

    // Disabling is a STATE the record keeps carrying, not a release - the second request must find the
    // same entry and rewrite it rather than adding a second one beside it.
    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{250.0}),
            FTransform{FVector{400.0, 400.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()}
        .Set_Enable(ECk_EnableDisable::Disable),
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume);

    if (NOT TestEqual(TEXT("a second request on the same entity still leaves one record"),
        Records.Num(), 1))
    { return false; }

    TestEqual(TEXT("carrying the id the first request gave it"),
        Records[0].Get_Record().Get_Id(), 0);
    TestTrue(TEXT("with the enable state the second request asked for"),
        Records[0].Get_Record().Get_Enable() == ECk_EnableDisable::Disable);
    TestEqual(TEXT("re-stamped against the volume's currently published epoch"),
        Records[0].Get_Record().Get_RequestedAtEpoch(), static_cast<int64>(0));

    TestEqual(TEXT("and no id was spent on the update"),
        Volume.Get<ck::FFragment_GroundNavVolume_Markup>().Get_NextId(), 1);

    TestEqual(TEXT("the back-pointer still names that one record"),
        MarkupEntity.Get<ck::FFragment_GroundNav_MarkupRef>().Get_RecordId(), 0);

    TestEqual(TEXT("both requests completed"), Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("the second reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_ReleaseRemovesTheRecord,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_ReleaseRemovesTheRecord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_ReleaseRemovesTheRecord::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    if (NOT TestEqual(TEXT("the record is admitted first"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).Num(), 1))
    { return false; }

    // Standing in for the bake having consumed the tag: without clearing it first, the release's own
    // raise would be indistinguishable from the admission's.
    Volume.Try_Remove<ck::FTag_GroundNavVolume_MarkupWalkabilityDirty>();

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseAreaMarkup(Volume,
        FCk_Request_GroundNavVolume_ReleaseAreaMarkup{MarkupEntity},
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    TestTrue(TEXT("releasing drops the record"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty());
    TestFalse(TEXT("and the back-pointer with it"),
        MarkupEntity.Has<ck::FFragment_GroundNav_MarkupRef>());
    TestFalse(TEXT("so the id no longer resolves"),
        UCk_Utils_GroundNavVolume_UE::TryGet_MarkupRecord(Volume, 0).IsSet());

    TestTrue(TEXT("a removed walkability record is a walkability change"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupWalkabilityDirty>());

    TestEqual(TEXT("both requests completed"), Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("the release reporting Succeeded"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    // Ids are retired with their records, so the next admission does not reuse the one just freed.
    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        {});

    DoDrain_MarkupRequests(World, Volume);

    const auto Records = UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume);

    if (NOT TestEqual(TEXT("re-painting the same entity admits a fresh record"), Records.Num(), 1))
    { return false; }

    TestEqual(TEXT("carrying a new id rather than the retired one"),
        Records[0].Get_Record().Get_Id(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_TeardownCancelsPendingRequests,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_TeardownCancelsPendingRequests",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_TeardownCancelsPendingRequests::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        Make_Delegate(Listener.Get()));

    // The tag Request_DestroyEntity adds synchronously, and the one the drain's view excludes on. Added
    // directly because tearing the entity down for real needs the scheduler this world does not have.
    Volume.AddOrGet<ck::FTag_DestroyEntity_Initiate>();

    ck::FProcessor_GroundNavVolume_CancelPendingMarkupRequests::ForEachEntity(
        FCk_Time{kSixtyHertz},
        Volume,
        Volume.Get<ck::FFragment_GroundNavVolume_MarkupRequests>());

    TestEqual(TEXT("the queued request completes exactly once"),
        Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed_Cancelled rather than hanging on a drain that will never run"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed_Cancelled);

    TestTrue(TEXT("and nothing was admitted on the way out"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
