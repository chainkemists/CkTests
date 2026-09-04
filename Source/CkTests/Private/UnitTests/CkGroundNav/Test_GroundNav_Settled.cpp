// When a ground-nav volume - and therefore the GroundNav surface - is SETTLED.
//
// Settled is the named condition a fixture waits on after a paint, a release, or a rebuild kick: a
// field is published and no stage still owes this volume a publish. The alternative it replaces is a
// hop count, which has to be re-guessed every time a stage's internal staging changes.
//
// These are NECESSARY-condition pins, and deliberately so. A volume here never PUBLISHES a field -
// that needs a physics world for the geometry backend, and FFragment_GroundNavVolume_BuiltField::_Field
// is friend-private to the build, the repair and the cost derive, with no test-only installer. So each
// marker test below asserts that the marker keeps the volume unsettled without being able to prove the
// marker was the REASON: the missing field already answers false. The sufficiency direction - built,
// clean, and therefore settled - is the PIE settle pin's, where a real bake publishes.
//
// The one clause that IS discriminating headlessly is the request queue, which reads EMPTINESS rather
// than presence. The drains reset a queue's array in place and leave the fragment on the volume, so a
// presence test would read every volume that was ever asked for anything as permanently unsettled. The
// repair-queue test below pins that shape directly.
//
// The drains are invoked by hand, as Test_GroundNav_MarkupAdmission does: a headless registry has no
// scheduler, so the view's TExclude filters are the header's claim rather than this file's.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_ProviderTable.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_settled
{
    constexpr auto InformEngineOfWorld = false;
    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    auto Make_Params() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Profile};
    }

    auto Make_DirtyBox() -> FBox
    {
        return FBox{FVector{100.0, 100.0, -50.0}, FVector{300.0, 300.0, 100.0}};
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

    // The provider's own settled body, reached the way the neutral seam reaches it. Reproducing the
    // fold here instead would test this file's arithmetic rather than the provider's.
    auto Get_WorldIsSurfaceSettled(
        UWorld* InWorld) -> bool
    {
        const auto* Table = ck::nav_surface::TryGet_ProviderTable(ECk_NavSurface_Provider::GroundNav);

        if (Table == nullptr || NOT Table->_IsSurfaceSettled)
        { return false; }

        return Table->_IsSurfaceSettled(InWorld);
    }

    auto Get_ProviderTableCarriesSettled() -> bool
    {
        const auto* Table = ck::nav_surface::TryGet_ProviderTable(ECk_NavSurface_Provider::GroundNav);

        return Table != nullptr && static_cast<bool>(Table->_IsSurfaceSettled);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Settled_NotSettledWithoutAPublishedField,
    "CkTests.UnitTests.CkGroundNav.Volume.Settled_NotSettledWithoutAPublishedField",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Settled_NotSettledWithoutAPublishedField::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_settled;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    if (NOT TestFalse(TEXT("and it has published nothing"),
        UCk_Utils_GroundNavVolume_UE::Get_Field(Volume).IsValid()))
    { return false; }

    // A published field is the first clause and not a formality: settled means every query answers
    // from THIS field, and a volume with none has no answer to be settled about.
    TestFalse(TEXT("a volume with no published field is not settled"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(Volume));

    TestFalse(TEXT("and an invalid volume is not settled either"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(FCk_Handle_GroundNavVolume{}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Settled_NotSettledWhileNeedsRepairIsSet,
    "CkTests.UnitTests.CkGroundNav.Volume.Settled_NotSettledWhileNeedsRepairIsSet",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Settled_NotSettledWhileNeedsRepairIsSet::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_settled;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    Volume.AddOrGet<ck::FTag_GroundNavVolume_NeedsRepair>();

    if (NOT TestTrue(TEXT("the volume carries dirty ground waiting for a repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>()))
    { return false; }

    // A region raised and not yet answered is ground the published field no longer describes, which is
    // exactly what a fixture waiting on settled must not be told is ready.
    TestFalse(TEXT("a volume with a repair still owed is not settled"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(Volume));

    // Stated separately so this stays a pin on NeedsRepair rather than on RepairInProgress: a region
    // pending and a repair sliced open are different states, and settled excludes both.
    TestFalse(TEXT("even though no repair has actually opened"),
        UCk_Utils_GroundNavVolume_UE::Get_IsRepairInProgress(Volume));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Settled_NotSettledWhileMarkupCostDirtyIsSet,
    "CkTests.UnitTests.CkGroundNav.Volume.Settled_NotSettledWhileMarkupCostDirtyIsSet",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Settled_NotSettledWhileMarkupCostDirtyIsSet::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_settled;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    Volume.AddOrGet<ck::FTag_GroundNavVolume_MarkupCostDirty>();

    if (NOT TestTrue(TEXT("the volume owes a cost re-derive"),
        Volume.Has<ck::FTag_GroundNavVolume_MarkupCostDirty>()))
    { return false; }

    // The cost derive republishes without reading a cell, so it moves no build and no repair marker.
    // Leaving it out of settled would let a fixture read a repriced volume one publish early.
    TestFalse(TEXT("a volume with a cost re-derive still owed is not settled"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(Volume));

    TestFalse(TEXT("even though it is neither building nor repairing"),
        UCk_Utils_GroundNavVolume_UE::Get_IsBuilding(Volume) ||
        UCk_Utils_GroundNavVolume_UE::Get_IsRepairInProgress(Volume));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Settled_NotSettledWhileARepairRequestIsQueued,
    "CkTests.UnitTests.CkGroundNav.Volume.Settled_NotSettledWhileARepairRequestIsQueued",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Settled_NotSettledWhileARepairRequestIsQueued::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_settled;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_Params());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_Repair(Volume,
        FCk_Request_GroundNavVolume_Repair{Make_DirtyBox()}, {});

    if (NOT TestTrue(TEXT("the util enqueues the request"),
        Volume.Has<ck::FFragment_GroundNavVolume_RepairRequests>() &&
        NOT Volume.Get<ck::FFragment_GroundNavVolume_RepairRequests>().Get_Requests().IsEmpty()))
    { return false; }

    // A queued request has reached no stage yet, so no marker names it. Settling on the markers alone
    // would report the tick between an enqueue and its drain as settled.
    TestFalse(TEXT("a volume holding an undrained request is not settled"),
        UCk_Utils_GroundNavVolume_UE::Get_IsSettled(Volume));

    TestFalse(TEXT("and no marker names it yet"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());

    DoDrain_RepairRequests(World, Volume);

    // The whole reason the clause reads emptiness rather than presence. The drain resets the array in
    // place and leaves the fragment on the volume, so a presence test would read every volume that was
    // ever asked for anything as permanently unsettled.
    TestTrue(TEXT("the drain leaves the queue fragment on the volume"),
        Volume.Has<ck::FFragment_GroundNavVolume_RepairRequests>());

    TestTrue(TEXT("but empty, which is what nothing-pending means"),
        Volume.Get<ck::FFragment_GroundNavVolume_RepairRequests>().Get_Requests().IsEmpty());

    // Nothing was published, so the drain dropped the region rather than arming a repair for it: the
    // volume is back to being unsettled on the published-field clause alone.
    TestFalse(TEXT("and a region handed to a volume with nothing published arms no repair"),
        Volume.Has<ck::FTag_GroundNavVolume_NeedsRepair>());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Settled_WorldWithNoVolumeIsNotSettled,
    "CkTests.UnitTests.CkGroundNav.Volume.Settled_WorldWithNoVolumeIsNotSettled",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Settled_WorldWithNoVolumeIsNotSettled::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_settled;

    if (NOT TestTrue(TEXT("GroundNav registered a provider table carrying a settled entry"),
        Get_ProviderTableCarriesSettled()))
    { return false; }

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, InformEngineOfWorld, FName{TEXT("CkGroundNavSettledNoVolume")});

    if (NOT TestTrue(TEXT("the probe world is created"), World != nullptr))
    { return false; }

    // A world holding no volume has nothing that could settle. True here would tell a fixture the
    // surface it is waiting on is ready when there is no surface at all - which is the shape of every
    // vacuously-green settle pin.
    TestFalse(TEXT("a world with no ground-nav volume is not settled"),
        Get_WorldIsSurfaceSettled(World));

    World->DestroyWorld(InformEngineOfWorld);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
