// When an area markup is LIVE on the ground, and the two halves of what a cost markup changes.
//
// "Live" is DERIVED at the read and stored nowhere, which is the property under test here: there is no
// flag anybody has to remember to clear, so the only way to be wrong about it is to read the wrong
// thing. The rule is stated over a field and a record, and that is exactly how most of this file asks
// it — a stub-baked field and a hand-built record need no world, no physics and no scheduler, so the
// epoch arithmetic can be pinned exactly instead of waited on.
//
// The entity-shaped half is asked through the volume drains directly, as Test_GroundNav_MarkupAdmission
// does: a headless registry has no scheduler, and a volume cannot publish a field without a physics
// world for its geometry backend, so what the entity path can prove here is that a markup is NOT live
// until the drain has recorded it and something has been published for it to be live on.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupMask.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Facade/CkGroundNav_NavSurfaceAdapter.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldMarkupCost.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Attributes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_PlatePortalGraph.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_AreaPolicy.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_MarkupLive_Slow, "Ck.Test.GroundNav.MarkupLive.Slow");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_MarkupLive_Blocked, "Ck.Test.GroundNav.MarkupLive.Blocked");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_markuplive
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_PathSharedData;
    using ck::groundnav::Get_AreaMultiplier;
    using ck::groundnav::Get_FieldWithMarkupCost;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_MarkupWorldBounds;
    using ck::groundnav::Get_SurfaceAttributesAt;
    using ck::groundnav::Get_TileWorldBounds;

    namespace facade = ck::groundnav::nav_surface_adapter;

    constexpr auto kSixtyHertz = 1.0f / 60.0f;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    // Distinctly not 1.0, so "the price came from the record" cannot pass on the identity.
    constexpr auto kSlowCostMultiplier = 2.0f;

    // The epoch the fixture bakes at, the one a record is submitted against, and the one a publish
    // that CONSUMED that record lands at. A record is stamped with the epoch the field was already
    // published at, so a tile merely AT the requested epoch is the publish the record was submitted
    // against and knew nothing about it: only kRepublishedEpoch is a republish that observed it.
    constexpr auto kBakedEpoch = int64{1};
    constexpr auto kRequestedEpoch = int64{2};
    constexpr auto kRepublishedEpoch = int64{3};

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off: the subject is markup, and the conservative default would trim the
        // fixture's borders before a single record was applied.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    // 2x2 tiles of 400uu from the world origin, so tile (0,0) covers [0,400] on both axes and its
    // neighbour along X covers [400,800]. Every bound asserted below is computed against that.
    auto Make_FieldParams(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{2, 2};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MarkupRecords = InMarkups;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Ground reaching past the field on every side, so every tile's halo has real world in it.
    auto Bake_Field(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups,
        FCk_GroundNav_Field&                      OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
            TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}}};

        return DoBake_Field(
            Backend, Make_FieldParams(InMarkups), FCk_GroundNav_Epoch{kBakedEpoch}, OutField)
            .Get_IsCompleted();
    }

    auto Make_Record(
        int32                    InId,
        const FVector&           InCentre,
        const FVector&           InHalfExtents,
        ECk_GroundNav_MarkupKind InKind) -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            InId,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{InHalfExtents}},
            FTransform{InCentre},
            InKind};

        Record.Set_AreaTag(InKind == ECk_GroundNav_MarkupKind::Cost
            ? TAG_Test_GroundNav_MarkupLive_Slow.GetTag()
            : TAG_Test_GroundNav_MarkupLive_Blocked.GetTag());

        if (InKind == ECk_GroundNav_MarkupKind::Cost)
        { Record.Set_CostMultiplier(kSlowCostMultiplier); }

        return Record;
    }

    // Which tiles a record's footprint reaches, asked through the same bounds the live rule reads, so
    // the fixture and the rule cannot disagree about which tiles a test is talking about.
    auto Get_ReachedTileIndices(
        const FCk_GroundNav_Field&        InField,
        const FCk_GroundNav_MarkupRecord& InRecord) -> TArray<int32>
    {
        const auto RecordBounds = Get_MarkupWorldBounds(InRecord);

        auto Indices = TArray<int32>{};

        for (auto Index = 0; Index < InField._Tiles.Num(); ++Index)
        {
            if (Get_TileWorldBounds(InField._Params, InField._Tiles[Index]).Intersect(RecordBounds))
            { Indices.Emplace(Index); }
        }

        return Indices;
    }

    auto Make_ColumnQuery(const FVector& InLocation) -> FCk_GroundNav_IsNavigableQuery
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = 100.0f;
        Query._Agent._RadiusUu = 0.0f;

        return Query;
    }

    // ---- The volume-shaped half --------------------------------------------------------------------------

    auto Make_VolumeParams() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Make_Profile()};
    }

    // Idempotent: re-registering a tag with the same policy is a silent no-op.
    auto DoRegister_TestAreaPolicies() -> void
    {
        ck::nav_surface::Register_AreaPolicy(TAG_Test_GroundNav_MarkupLive_Slow.GetTag(),
            FCk_NavSurface_AreaPolicy{ECk_NavSurface_AreaPolicyKind::Cost, kSlowCostMultiplier});

        ck::nav_surface::Register_AreaPolicy(TAG_Test_GroundNav_MarkupLive_Blocked.GetTag(),
            FCk_NavSurface_AreaPolicy{ECk_NavSurface_AreaPolicyKind::Walkability, 1.0f});
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_IsFalseBeforeTheDrain,
    "CkTests.UnitTests.CkGroundNav.Volume.MarkupLive_IsFalseBeforeTheDrain",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_IsFalseBeforeTheDrain::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive;

    DoRegister_TestAreaPolicies();

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_VolumeParams());
    auto MarkupEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    TestFalse(TEXT("an entity nobody has painted is not live"),
        facade::Get_IsMarkupLive(MarkupEntity));

    UCk_Utils_GroundNavVolume_UE::Request_AreaMarkup(Volume,
        FCk_Request_GroundNavVolume_AreaMarkup{
            MarkupEntity,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{100.0}}},
            FTransform{FVector{200.0, 200.0, 0.0}},
            TAG_Test_GroundNav_MarkupLive_Slow.GetTag()},
        {});

    // The util enqueues and the processor mutates, so there is no back-pointer yet and therefore
    // nothing that could report itself live.
    TestFalse(TEXT("an enqueued paint is not live - the drain has not recorded it"),
        facade::Get_IsMarkupLive(MarkupEntity));

    DoDrain_MarkupRequests(World, Volume);

    if (NOT TestTrue(TEXT("the drain records the paint"),
        MarkupEntity.Has<ck::FFragment_GroundNav_MarkupRef>()))
    { return false; }

    // Recorded is not live. The volume has published nothing, so there is no ground for the record to
    // be live on - and answering true here would mean only that nothing had contradicted it.
    TestFalse(TEXT("and a recorded paint on a volume with nothing published is still not live"),
        facade::Get_IsMarkupLive(MarkupEntity));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_IsFalseUntilTheCoveringTilesRepublish,
    "CkTests.UnitTests.CkGroundNav.Volume.MarkupLive_IsFalseUntilTheCoveringTilesRepublish",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_IsFalseUntilTheCoveringTilesRepublish::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"), Bake_Field({}, Field)))
    { return false; }

    // Wholly inside tile (0,0): [100,300] on both axes, against a tile covering [0,400].
    auto Record = Make_Record(1, FVector{200.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    Record.Set_RequestedAtEpoch(kRequestedEpoch);

    const auto Reached = Get_ReachedTileIndices(Field, Record);

    if (NOT TestEqual(TEXT("the record reaches exactly one tile"), Reached.Num(), 1))
    { return false; }

    TestFalse(TEXT("a record submitted against an epoch its covering tile has not reached is not live"),
        facade::Get_IsMarkupLive(Field, Record));

    // A tile in an unrelated corner republishing changes nothing: the rule is about the tiles the
    // record REACHES, not about the field having moved at all.
    for (auto TileIndex = 0; TileIndex < Field._Tiles.Num(); ++TileIndex)
    {
        if (Reached.Contains(TileIndex))
        { continue; }

        Field._Tiles[TileIndex]._Epoch = FCk_GroundNav_Epoch{kRepublishedEpoch};
    }

    TestFalse(TEXT("and every OTHER tile republishing still does not make it live"),
        facade::Get_IsMarkupLive(Field, Record));

    // The epoch the record was stamped WITH is the one the field was already published at when it was
    // admitted, so a covering tile sitting exactly there has published nothing since.
    Field._Tiles[Reached[0]]._Epoch = FCk_GroundNav_Epoch{kRequestedEpoch};

    TestFalse(TEXT("the covering tile AT the requested epoch is the publish that never saw it"),
        facade::Get_IsMarkupLive(Field, Record));

    Field._Tiles[Reached[0]]._Epoch = FCk_GroundNav_Epoch{kRepublishedEpoch};

    TestTrue(TEXT("the covering tile republishing PAST the requested epoch does"),
        facade::Get_IsMarkupLive(Field, Record));

    // A record whose footprint meets no tile is not live either. There is nothing for it to be live
    // on, and true would be a claim the caller cannot check.
    auto OffField = Make_Record(2, FVector{5000.0, 5000.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    OffField.Set_RequestedAtEpoch(0);

    TestEqual(TEXT("a record off the field reaches no tile"),
        Get_ReachedTileIndices(Field, OffField).Num(), 0);

    TestFalse(TEXT("and is not live however old the epoch it was submitted against is"),
        facade::Get_IsMarkupLive(Field, OffField));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_TwoTileRecordIsLiveOnlyWhenBothRepublish,
    "CkTests.UnitTests.CkGroundNav.Volume.MarkupLive_TwoTileRecordIsLiveOnlyWhenBothRepublish",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_TwoTileRecordIsLiveOnlyWhenBothRepublish::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"), Bake_Field({}, Field)))
    { return false; }

    // Straddling the seam at X = 400: [300,500] x [100,300], inside tile (0,0) and tile (1,0) and
    // reaching neither of the tiles above them.
    auto Record = Make_Record(1, FVector{400.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    Record.Set_RequestedAtEpoch(kRequestedEpoch);

    const auto Reached = Get_ReachedTileIndices(Field, Record);

    if (NOT TestEqual(TEXT("the record reaches exactly two tiles"), Reached.Num(), 2))
    { return false; }

    TestFalse(TEXT("neither covering tile has republished, so it is not live"),
        facade::Get_IsMarkupLive(Field, Record));

    Field._Tiles[Reached[0]]._Epoch = FCk_GroundNav_Epoch{kRepublishedEpoch};

    // A record is only as live as its laggard. A caller told otherwise would act on ground half the
    // paint has not reached.
    TestFalse(TEXT("one of the two republishing is still not live"),
        facade::Get_IsMarkupLive(Field, Record));

    Field._Tiles[Reached[1]]._Epoch = FCk_GroundNav_Epoch{kRepublishedEpoch};

    TestTrue(TEXT("both republishing is"), facade::Get_IsMarkupLive(Field, Record));

    // Built is the other half of the rule and is not implied by the epoch: a tile whose bake failed
    // carries whatever epoch it was stamped with and knows nothing about the ground under it.
    Field._Tiles[Reached[1]]._Status = ECk_GroundNav_BuildStatus::Failed;

    TestFalse(TEXT("and a covering tile that is not Built takes it back off"),
        facade::Get_IsMarkupLive(Field, Record));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_CostDirtyRepublishSpendsZeroProbesAndBumpsRevision,
    "CkTests.UnitTests.CkGroundNav.Volume.MarkupLive_CostDirtyRepublishSpendsZeroProbesAndBumpsRevision",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_CostDirtyRepublishSpendsZeroProbesAndBumpsRevision::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive;

    auto Source = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the field bakes"), Bake_Field({}, *Source)))
    { return false; }

    const auto Published = FCk_GroundNav_FieldPtr{Source};

    // The number the provider reports as its surface revision: a SUM over tile epochs, so one tile
    // moving moves it even when the newest epoch in the field does not change.
    const auto RevisionBefore = Published->Get_AggregatedTileEpochSum();

    auto Record = Make_Record(1, FVector{200.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    Record.Set_RequestedAtEpoch(kRequestedEpoch);

    // Baked at kBakedEpoch and submitted against kRequestedEpoch, so the record is PENDING on every
    // tile it reaches - which is the second half of the derive's bump rule, and what carries a record
    // that moves no label. The publish lands past the record's stamp, which is what liveness asks for.
    const auto Derived = Get_FieldWithMarkupCost(
        *Published,
        TArray<FCk_GroundNav_MarkupRecord>{Record},
        FCk_GroundNav_Epoch{kRepublishedEpoch});

    if (NOT TestTrue(TEXT("the derive completes and yields a field"),
        Derived.Value.Get_IsCompleted() && Derived.Key.IsValid()))
    { return false; }

    // Cost is a plate label, not a shape: there is nothing to rasterize, filter or decompose, so this
    // is exactly zero rather than merely small.
    TestEqual(TEXT("republishing a cost change spends no probes at all"),
        Derived.Value.Get_ProbesSpent(), 0);

    TestTrue(TEXT("and moves the revision"),
        Derived.Key->Get_AggregatedTileEpochSum() > RevisionBefore);

    // A derive copies and the caller swaps, so what a reader is already holding is never touched.
    TestEqual(TEXT("while what a reader is already holding keeps its revision"),
        Published->Get_AggregatedTileEpochSum(), RevisionBefore);

    TestTrue(TEXT("the record is live against the derived field"),
        facade::Get_IsMarkupLive(*Derived.Key, Record));

    TestFalse(TEXT("and is not live against the one it was derived from"),
        facade::Get_IsMarkupLive(*Published, Record));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_AttributesReportThePlateCostAndTags,
    "CkTests.UnitTests.CkGroundNav.Volume.MarkupLive_AttributesReportThePlateCostAndTags",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_AttributesReportThePlateCostAndTags::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive;

    const auto Record = Make_Record(1, FVector{200.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes with the record on it"),
        Bake_Field(TArray<FCk_GroundNav_MarkupRecord>{Record}, Field)))
    { return false; }

    const auto Priced = Get_SurfaceAttributesAt(Field, Make_ColumnQuery(FVector{200.0, 200.0, 0.0}));

    if (NOT TestEqual(TEXT("there is ground under the record to report on"),
        Priced._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestEqual(TEXT("and it is priced at the record's multiplier"),
        Priced._CostMultiplier, kSlowCostMultiplier);

    TestTrue(TEXT("carrying the record's area tag"),
        Priced._AreaTags.HasTagExact(TAG_Test_GroundNav_MarkupLive_Slow.GetTag()));

    // A different TILE, so a different plate: any overlap prices a whole plate, and the plate the
    // record covers is confined to the tile it was painted in.
    const auto Bare = Get_SurfaceAttributesAt(Field, Make_ColumnQuery(FVector{700.0, 700.0, 0.0}));

    if (NOT TestEqual(TEXT("there is ground away from the record too"),
        Bare._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestEqual(TEXT("ground no record covers keeps the identity multiplier"),
        Bare._CostMultiplier, 1.0f);

    TestTrue(TEXT("and reports no area tags"), Bare._AreaTags.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_AreaMultiplierTakesTheMaxOfFieldAndQueryTable,
    "CkTests.UnitTests.CkGroundNav.Volume.MarkupLive_AreaMultiplierTakesTheMaxOfFieldAndQueryTable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_AreaMultiplierTakesTheMaxOfFieldAndQueryTable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive;

    const auto Record = Make_Record(1, FVector{200.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes with the record on it"),
        Bake_Field(TArray<FCk_GroundNav_MarkupRecord>{Record}, Field)))
    { return false; }

    const auto Priced = Get_SurfaceAttributesAt(Field, Make_ColumnQuery(FVector{200.0, 200.0, 0.0}));
    const auto Bare = Get_SurfaceAttributesAt(Field, Make_ColumnQuery(FVector{700.0, 700.0, 0.0}));

    if (NOT TestTrue(TEXT("both ends of the field have ground to price"),
        Priced.Get_IsSuccess() && Bare.Get_IsSuccess()))
    { return false; }

    const auto PricedPlate = Get_FlatPlateIndex(
        Field, Priced._Surface._TileIndex, Priced._Surface._PlateIndex);

    const auto BarePlate = Get_FlatPlateIndex(
        Field, Bare._Surface._TileIndex, Bare._Surface._PlateIndex);

    if (NOT TestTrue(TEXT("and the two plates are distinct and both addressable"),
        PricedPlate != INDEX_NONE && BarePlate != INDEX_NONE && PricedPlate != BarePlate))
    { return false; }

    auto Shared = FCk_GroundNav_PathSharedData{};

    // An empty table is the FIELD's own price and nothing else - the marked plate is dearer, the bare
    // one is the identity.
    TestEqual(TEXT("with no query table, a marked plate is priced by the field"),
        Get_AreaMultiplier(Field, Shared, PricedPlate), kSlowCostMultiplier);

    TestEqual(TEXT("and an unmarked one at the identity"),
        Get_AreaMultiplier(Field, Shared, BarePlate), 1.0f);

    Shared._PlateCostMultipliers.Add(PricedPlate, 3.0f);
    Shared._PlateCostMultipliers.Add(BarePlate, 4.0f);

    TestEqual(TEXT("a query table asking for MORE than the field wins"),
        Get_AreaMultiplier(Field, Shared, PricedPlate), 3.0f);

    TestEqual(TEXT("and prices a plate the field never marked"),
        Get_AreaMultiplier(Field, Shared, BarePlate), 4.0f);

    Shared._PlateCostMultipliers.Add(PricedPlate, 1.5f);

    // Upward only. A query cannot talk a marked plate back down to bare ground, which is the same
    // greater-wins rule two overlapping records already merge under.
    TestEqual(TEXT("a query table asking for LESS than the field does not"),
        Get_AreaMultiplier(Field, Shared, PricedPlate), kSlowCostMultiplier);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
