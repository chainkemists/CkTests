// Admitting area markup onto a ground-nav volume.
//
// This is ADMISSION only — what the drain accepts, what it rejects, what the volume then holds, and
// what it hands the stage its kind owes. What the bake does with an admitted record is the bake's
// contract and is verified against the reduction in Test_GroundNav_MarkupMask. The drains are invoked
// directly, as the VoxelNav volume tests do: a headless registry has no scheduler, so the view's
// TExclude filters are the header's claim rather than this file's.
//
// A volume here never PUBLISHES a field: that needs a physics world for the geometry backend, and the
// published field is writable only by the build, the repair and the cost derive. So the walkability
// hand-off is pinned here in its nothing-published form, which is a rule of its own - nothing is
// marked, because the first build bakes the record in through the volume's records. Its one exception
// is reachable headlessly and pinned here too: a build already RUNNING has snapshotted its records, so
// a change arriving mid-build is owed a repair even with nothing published yet. The published-field
// form, where a walkability change marks its record's ground and arms a repair, is pinned by the PIE
// repair tests, CkAutoTest_GroundNav_Repair_*.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Processor.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_AreaPolicy.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Processor.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
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

    // A probe world nothing else has to know about: the engine is deliberately not told, so the world
    // never enters a global list a later test could trip over.
    constexpr auto kInformEngineOfWorld = false;

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

    auto Make_DirtyBox() -> FBox
    {
        return FBox{FVector{100.0, 100.0, -50.0}, FVector{300.0, 300.0, 100.0}};
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

    // The whole destruction chain, driven by hand. Request_DestroyEntity only STAMPS
    // FTag_DestroyEntity_Initiate; the scheduler that walks an entity from there to retired is what a
    // headless registry does not have, so each phase processor is called in the order its tag gates
    // demand and the last one destroys the entity for real. The teardown test below stops at the first
    // stamp because the tag is all its drain reads - here the handle must actually read invalid.
    auto DoDestroy_Entity(
        ck::FEcsWorld& InWorld,
        FCk_Handle&    InEntity) -> void
    {
        const auto DeltaT = FCk_Time{kSixtyHertz};

        UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(InEntity);

        ck::FProcessor_EntityLifetime_DestructionPhase_Endplay::ForEachEntity(DeltaT, InEntity);
        ck::FProcessor_EntityLifetime_DestructionPhase_Teardown::ForEachEntity(DeltaT, InEntity);
        ck::FProcessor_EntityLifetime_DestructionPhase_Await::ForEachEntity(DeltaT, InEntity);
        ck::FProcessor_EntityLifetime_DestructionPhase_Finalize::ForEachEntity(DeltaT, InEntity);

        auto DestroyEntities = ck::FProcessor_EntityLifetime_DestroyEntity{InWorld.Get_Registry()};
        DestroyEntities.DoTick(DeltaT);
    }

    auto DoDrain_MarkupRequests(
        ck::FEcsWorld&              InWorld,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_HandleMarkupRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_RepairState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Markup>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_MarkupRequests>());
    }

    auto DoDrain_RepairRequests(
        ck::FEcsWorld&              InWorld,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_HandleRepairRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_RepairState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_RepairRequests>());
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

    // Nothing is published, so the walkability hand-off marks nothing: there is no field for a repair
    // to carry its untouched tiles over from, and the record is already on the volume for the first
    // build to bake in.
    TestFalse(TEXT("a walkability record on a volume with nothing published arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks no dirty ground"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);
    TestFalse(TEXT("and raises no cost tag - the two kinds are answered by different stages"),
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
    TestFalse(TEXT("and arms no repair - a retint owes no re-bake"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks no ground dirty, published field or not"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

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

    TestFalse(TEXT("no repair is armed"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
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
    TestFalse(TEXT("and arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());

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

    // A release marks the released record's ground for the same reason painting it marked it - but on
    // a volume with nothing published there is no field to repair, so a release marks nothing either.
    // That a release DOES re-raise the record's own footprint once a field exists is pinned by the PIE
    // repair tests, CkAutoTest_GroundNav_Repair_*.
    TestFalse(TEXT("releasing a walkability record on a volume with nothing published arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks no dirty ground"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

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

// The rule the walkability paths above share, stated by name: a walkability record marks NO ground
// while the volume has published nothing. A repair carries its untouched tiles over from a published
// field and there is none, and the record is already on the volume, so the first build bakes it in -
// which is why a paint made before the first bake is never lost. Painting, moving and releasing are
// each asked, because each is a separate call into the hand-off. The published-field form of all
// three is pinned by the PIE repair tests, CkAutoTest_GroundNav_Repair_*.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_WalkabilityRecordMarksNothingUntilAFieldIsPublished,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_WalkabilityRecordMarksNothingUntilAFieldIsPublished",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_WalkabilityRecordMarksNothingUntilAFieldIsPublished::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume has published no field for a repair to carry tiles over from"),
        ck::Is_NOT_Valid(UCk_Utils_GroundNavVolume_UE::Get_Field(Volume))))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        {});

    DoDrain_MarkupRequests(World, Volume);

    if (NOT TestEqual(TEXT("the paint is admitted - what it MARKS is the separate question"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).Num(), 1))
    { return false; }

    TestFalse(TEXT("a paint arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks no dirty ground"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    // An update marks the OLD record's ground as well as the new one's, so it is the path most likely
    // to mark something by accident: here it is the same nothing, twice.
    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{250.0}),
            FTransform{FVector{600.0, 600.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        {});

    DoDrain_MarkupRequests(World, Volume);

    TestFalse(TEXT("moving the record arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks neither the ground it left nor the ground it arrived on"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseAreaMarkup(Volume,
        FCk_Request_GroundNavVolume_ReleaseAreaMarkup{MarkupEntity},
        {});

    DoDrain_MarkupRequests(World, Volume);

    if (NOT TestTrue(TEXT("the release drops the record"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty()))
    { return false; }

    TestFalse(TEXT("releasing it arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks no dirty ground - no published field ever knew the record"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The ORDINARY release, not an edge case: a markup's release is issued by the markup entity's own
// teardown, so by the time the volume drains it the entity it names is already gone. Refusing one
// would refuse every release the neutral NavSurface EndPlay path ever makes, leaving the record on the
// volume for the life of the world and the ground it covers decided by a markup nothing holds.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_ReleaseNamingADestroyedEntityStillRemovesTheRecord,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_ReleaseNamingADestroyedEntityStillRemovesTheRecord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_ReleaseNamingADestroyedEntityStillRemovesTheRecord::RunTest(const FString& Parameters)
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

    const auto AdmittedRecords = UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume);

    if (NOT TestEqual(TEXT("the record is admitted first"), AdmittedRecords.Num(), 1))
    { return false; }

    const auto AdmittedRecordId = AdmittedRecords[0].Get_Record().Get_Id();

    // Retired BEFORE the release is even enqueued: a request made while the entity was still alive
    // would leave the drain reading a live handle, which is not the case under test.
    DoDestroy_Entity(World, MarkupEntity);

    if (NOT TestTrue(TEXT("the markup entity is really gone, not merely stamped for destruction"),
        ck::Is_NOT_Valid(MarkupEntity)))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_ReleaseAreaMarkup(Volume,
        FCk_Request_GroundNavVolume_ReleaseAreaMarkup{MarkupEntity},
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    TestTrue(TEXT("a release naming a destroyed entity still drops the record it was keyed on"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).IsEmpty());
    TestFalse(TEXT("so the id no longer resolves"),
        UCk_Utils_GroundNavVolume_UE::TryGet_MarkupRecord(Volume, AdmittedRecordId).IsSet());

    TestEqual(TEXT("both requests completed"), Listener->_TimesRequestCompleted, 2);
    TestTrue(TEXT("the release reporting Succeeded rather than refusing the entity that owned it"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

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

// The one walkability case that is NOT the nothing-published wait above. A build SNAPSHOTS the volume's
// records when it starts, so a paint arriving while one is running is outside what that build will bake:
// the field it publishes will decide the record's ground without knowing the record. That ground is
// therefore owed a repair the moment the build publishes, and the footprint the record covers is what
// the repair takes. Without a build running the same paint marks nothing, which
// Markup_WalkabilityRecordMarksNothingUntilAFieldIsPublished pins in all three of its shapes.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_WalkabilityRecordDuringABuildRaisesARepair,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_WalkabilityRecordDuringABuildRaisesARepair",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_WalkabilityRecordDuringABuildRaisesARepair::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume has published no field, so the running build is the only thing that can mark anything"),
        ck::IsValid(Volume) && ck::Is_NOT_Valid(UCk_Utils_GroundNavVolume_UE::Get_Field(Volume))))
    { return false; }

    // The tag a volume carries between StartBuild and the publish that ends the build. Added directly
    // because opening a real build needs a physics world for the geometry backend.
    Volume.AddOrGet<ck::FTag_GroundNavVolume_BuildInProgress>();

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            Make_Box(FVector{100.0}),
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_Markup_Blocked.GetTag()},
        Make_Delegate(Listener.Get()));

    DoDrain_MarkupRequests(World, Volume);

    if (NOT TestEqual(TEXT("the drain admits exactly one record"),
        UCk_Utils_GroundNavVolume_UE::Get_MarkupRecords(Volume).Num(), 1))
    { return false; }

    TestTrue(TEXT("a paint landing outside the running build's snapshot arms a repair for after its publish"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestTrue(TEXT("and marks the record's own ground for that repair to take"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    TestFalse(TEXT("and raises no cost tag - the two kinds are answered by different stages"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupCostDirty>());

    TestEqual(TEXT("the request completes exactly once"), Listener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Succeeded - the request rides admission, never the repair it armed"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Succeeded);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// A dirty region raised while a build is running is PARKED, not refused. The build snapshotted the
// volume when it started, so the region names ground that build will publish without having looked at
// it - and the repair that answers the region can only open once there IS a published field to carry
// its untouched tiles over from. Its caller therefore hears nothing yet: a verdict now would be a
// verdict about ground no stage has been to. With nothing published AND no build coming there is no
// publish to wait for, and the same region is refused rather than parked forever.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Repair_RegionDuringABuildWaitsForItsPublish,
    "CkTests.UnitTests.CkGroundNav.Volume.Repair_RegionDuringABuildWaitsForItsPublish",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Repair_RegionDuringABuildWaitsForItsPublish::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes and has published no field"),
        ck::IsValid(Volume) && ck::Is_NOT_Valid(UCk_Utils_GroundNavVolume_UE::Get_Field(Volume))))
    { return false; }

    Volume.AddOrGet<ck::FTag_GroundNavVolume_BuildInProgress>();

    const auto Listener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Repair(Volume,
        FCk_Request_GroundNavVolume_Repair{Make_DirtyBox()},
        Make_Delegate(Listener.Get()));

    DoDrain_RepairRequests(World, Volume);

    TestTrue(TEXT("a region raised during a build arms a repair for after that build's publish"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestTrue(TEXT("and the ground it named is accumulated on the volume"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(Volume).IsValid != 0);

    TestEqual(TEXT("the request is parked, not answered - nothing has looked at that ground yet"),
        Listener->_TimesRequestCompleted, 0);

    // The negative, on a volume of its own so the parked request above cannot colour it: with nothing
    // published and no build coming there is no publish for the region to wait for, and a retry would
    // not change that - which is exactly what Failed says.
    auto QuietOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto QuietVolume = UCk_Utils_GroundNavVolume_UE::Add(QuietOwner, Make_Params());

    if (NOT TestTrue(TEXT("the second volume carries neither a published field nor any build marker"),
        ck::Is_NOT_Valid(UCk_Utils_GroundNavVolume_UE::Get_Field(QuietVolume)) &&
        NOT QuietVolume.Has<ck::FTag_GroundNavVolume_BuildInProgress>() &&
        NOT QuietVolume.Has<ck::FTag_GroundNavVolume_NeedsBuild>()))
    { return false; }

    const auto QuietListener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Repair(QuietVolume,
        FCk_Request_GroundNavVolume_Repair{Make_DirtyBox()},
        Make_Delegate(QuietListener.Get()));

    DoDrain_RepairRequests(World, QuietVolume);

    TestEqual(TEXT("a region with no publish to wait for completes exactly once"),
        QuietListener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("reporting Failed - a build is what bakes that ground"),
        QuietListener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    TestFalse(TEXT("and it arms no repair"),
        QuietVolume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());
    TestFalse(TEXT("and marks no dirty ground"),
        UCk_Utils_GroundNavVolume_UE::Get_PendingDirtyBounds(QuietVolume).IsValid != 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_PaintOutsideEveryVolumeIsRefusedQuietly,
    "CkTests.UnitTests.CkGroundNav.Volume.Markup_PaintOutsideEveryVolumeIsRefusedQuietly",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_PaintOutsideEveryVolumeIsRefusedQuietly::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    // There is deliberately NO AddExpectedError here, and that absence is the assertion: a paint the
    // provider has no ground for used to ensure, and the crowd raises one under every standing body,
    // so a world whose volumes cover part of a level fired one per body per repaint. The harness
    // escalating an ensure is what fails this test if the refusal ever becomes loud again.
    DoRegister_TestAreaPolicies();

    auto* World = UWorld::CreateWorld(EWorldType::Game, kInformEngineOfWorld, TEXT("CkGroundNavMarkupOutside"));

    if (NOT TestTrue(TEXT("the probe world was created"), World != nullptr))
    { return false; }

    auto* EcsWorld = World->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();

    if (NOT TestTrue(TEXT("the probe world carries an ECS registry"), EcsWorld != nullptr))
    {
        World->DestroyWorld(kInformEngineOfWorld);
        return false;
    }

    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    const auto Listener = Make_Listener();

    // Real bounds, so the shape is not what refuses it - and no ground-nav volume anywhere in this
    // world, so no volume can be the one that holds it.
    auto Request = FCk_Request_NavSurface_AreaMarkup{
        Make_Box(FVector{100.0}), TAG_Test_GroundNav_Markup_Slow.GetTag()};
    Request.Set_WorldTransform(FTransform{FVector{5000.0, 5000.0, 0.0}});

    auto Markup = UCk_Utils_NavSurface_UE::Request_AreaMarkup(
        World, Request, Make_Delegate(Listener.Get()));

    if (NOT TestTrue(TEXT("the paint hands back a markup entity"), ck::IsValid(Markup)))
    {
        World->DestroyWorld(kInformEngineOfWorld);
        return false;
    }

    ck::FProcessor_NavSurfaceMarkup_HandleRequests{EcsWorld->Get_Registry()}.ForEachEntity(
        FCk_Time{kSixtyHertz},
        Markup,
        Markup.Get<ck::FFragment_NavSurfaceMarkup_Requests>(),
        Markup.Get<ck::FFragment_NavSurfaceMarkup_Current>());

    TestEqual(TEXT("the paint is answered exactly once"),
        Listener->_TimesRequestCompleted, 1);

    TestTrue(TEXT("with the provider's no-surface answer - there is no ground here to record it on"),
        Listener->_LastRequestResult == ECk_Request_OperationResult::Failed);

    TestTrue(TEXT("the markup handle is still valid - a refusal destroys nothing the caller holds"),
        ck::IsValid(Markup));

    TestFalse(TEXT("and it is not live, which is the whole of what a consumer reads"),
        UCk_Utils_NavSurface_UE::Get_IsMarkupLive(Markup));

    World->DestroyWorld(kInformEngineOfWorld);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
