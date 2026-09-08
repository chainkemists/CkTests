// Liveness asks whether the published field PRICED a record, and the tile epochs alone cannot answer
// that. A tile's epoch bumps for reasons that have nothing to do with this record, and a build that
// was ALREADY RUNNING when the paint drained snapshotted its record list before the record existed:
// its publish lands with a strictly newer epoch on every tile the record reaches, carrying plates that
// were stamped from a list the record is not in. Under an epoch-only rule that reads live while no
// plate carries the record's tag, so the strict query overlay denies nothing and the very first plan
// runs dead-straight through the volume the paint was supposed to close.
//
// The sequence is staged over field VALUES rather than through the volume: a bake is what takes a
// record snapshot, so a field baked at a later epoch from an empty list IS the in-flight build's
// publish, exactly and with no scheduler to wait on. The derive that observes the record is the same
// Get_FieldWithMarkupCost the volume's cost pass runs.

#include "CkCore/Macros/CkMacros.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupMask.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Facade/CkGroundNav_NavSurfaceAdapter.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldMarkupCost.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_MarkupLive_Priced, "Ck.Test.GroundNav.MarkupLive.Priced");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_markuplive_requirespricing
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::Get_FieldWithMarkupCost;
    using ck::groundnav::Get_MarkupWorldBounds;
    using ck::groundnav::Get_TileWorldBounds;

    namespace facade = ck::groundnav::nav_surface_adapter;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    constexpr auto kSlowCostMultiplier = 2.0f;

    // The three epochs the staging turns on. The build BEGAN at some epoch already behind us and is
    // still slicing when the paint drains, so the record is stamped with the epoch the field was
    // published at THEN; the in-flight build publishes past that stamp off the list it snapshotted
    // before the paint existed; only the derive at kPricedPublishEpoch ever sees the record.
    constexpr auto kAdmittedAtEpoch = int64{1};
    constexpr auto kInFlightPublishEpoch = int64{2};
    constexpr auto kPricedPublishEpoch = int64{3};

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    // 2x2 tiles of 400uu from the world origin, so tile (0,0) covers [0,400] on both axes.
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

    auto Bake_Field(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups,
        int64                                     InEpoch,
        FCk_GroundNav_Field&                      OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
            TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}}};

        return DoBake_Field(
            Backend, Make_FieldParams(InMarkups), FCk_GroundNav_Epoch{InEpoch}, OutField)
            .Get_IsCompleted();
    }

    // Wholly inside tile (0,0): [100,300] on both axes.
    auto Make_Record() -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            1,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{100.0, 100.0, 50.0}}},
            FTransform{FVector{200.0, 200.0, 0.0}},
            ECk_GroundNav_MarkupKind::Cost};

        Record.Set_AreaTag(TAG_Test_GroundNav_MarkupLive_Priced.GetTag());
        Record.Set_CostMultiplier(kSlowCostMultiplier);
        Record.Set_RequestedAtEpoch(kAdmittedAtEpoch);

        return Record;
    }

    // The EPOCH half of the rule, asked on its own. Answering it separately is what makes the pin
    // discriminating: without it a false could mean the record reached no tile, or reached one that
    // never republished, rather than the thing under test.
    auto Get_EveryReachedTileIsBuiltAndPastTheStamp(
        const FCk_GroundNav_Field&        InField,
        const FCk_GroundNav_MarkupRecord& InRecord) -> bool
    {
        const auto RecordBounds = Get_MarkupWorldBounds(InRecord);

        auto ReachedAnyTile = false;

        for (const auto& Tile : InField._Tiles)
        {
            if (NOT Get_TileWorldBounds(InField._Params, Tile).Intersect(RecordBounds))
            { continue; }

            ReachedAnyTile = true;

            if (NOT Tile.Get_IsBuilt() || Tile._Epoch._Value <= InRecord.Get_RequestedAtEpoch())
            { return false; }
        }

        return ReachedAnyTile;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_MarkupLive_RequiresThePublishToHavePricedTheRecord,
    "CkTests.UnitTests.CkGroundNav.MarkupLive.RequiresThePublishToHavePricedTheRecord",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_MarkupLive_RequiresThePublishToHavePricedTheRecord::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markuplive_requirespricing;

    const auto Record = Make_Record();

    // The publish of the build that was already running: baked from the EMPTY list it snapshotted
    // before the paint drained, and stamped past the epoch the record was admitted against.
    auto InFlightPublish = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the in-flight build's field bakes"),
        Bake_Field({}, kInFlightPublishEpoch, InFlightPublish)))
    { return false; }

    if (NOT TestTrue(TEXT("and it published past the record's stamp on every tile the record reaches"),
        Get_EveryReachedTileIsBuiltAndPastTheStamp(InFlightPublish, Record)))
    { return false; }

    if (NOT TestEqual(TEXT("while carrying none of the record in its params"),
        InFlightPublish._Params._MarkupRecords.Num(), 0))
    { return false; }

    // The whole claim: a newer epoch off a stale snapshot is not liveness. Nothing in this field's
    // plates carries the record's tag, so a strict query overlay would refuse nothing here.
    TestFalse(TEXT("a publish that never saw the record does not make it live, however new its epoch"),
        facade::Get_IsMarkupLive(InFlightPublish, Record));

    // The derive the volume's cost pass runs the moment that publish lands: it restamps every built
    // tile from the whole record list and carries that list on the field it produces.
    const auto Priced = Get_FieldWithMarkupCost(
        InFlightPublish,
        TArray<FCk_GroundNav_MarkupRecord>{Record},
        FCk_GroundNav_Epoch{kPricedPublishEpoch});

    if (NOT TestTrue(TEXT("the derive completes and yields a field"),
        Priced.Value.Get_IsCompleted() && Priced.Key.IsValid()))
    { return false; }

    TestTrue(TEXT("and the publish that DID price the record makes it live"),
        facade::Get_IsMarkupLive(*Priced.Key, Record));

    // Identity, not merely presence: the field priced the record as it was AUTHORED, so a record
    // re-authored since is one this publish has never seen either.
    auto Reauthored = Record;
    Reauthored.Set_CostMultiplier(kSlowCostMultiplier + 1.0f);

    TestFalse(TEXT("a record re-authored since that publish is not live on it"),
        facade::Get_IsMarkupLive(*Priced.Key, Reauthored));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
