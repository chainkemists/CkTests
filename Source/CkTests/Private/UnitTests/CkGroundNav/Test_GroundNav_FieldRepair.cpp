// A LOCAL REPAIR of a published ground field, and the three claims that make one usable at all.
//
// The claims are not independent. A repair is only worth doing if it costs less than a rebuild, it is
// only SAFE if the field a reader is already holding never moves under it, and it is only CORRECT if
// what it publishes is the field a full rebake of the same world would have published - byte for
// byte, tile epochs excluded, because the epochs are the one thing a repair is supposed to move.
// Drop any one of the three and the other two stop being worth asserting: a cheap repair that
// diverges is a wrong answer delivered faster.
//
// So every comparison here is exact and diagnostic. The tile set is computed a second time in this
// file from the field params alone rather than read back from the code under test, the untouched
// tiles are compared INCLUDING their epochs, and every byte-identity assertion goes through
// Get_FirstFieldDifference / Get_FirstTileDifference so a failure names the member that moved
// instead of saying that something did.
//
// The fixture is a 3x3 lattice of 400 uu tiles over a floor slab, with one 150 uu obstacle that moves
// 600 uu along X. World A holds it at its first position, world B at its second, and the dirty box is
// the union of the two footprints. With a 200 uu clearance cap over 25 uu cells the halo is eight
// cells - 200 uu - which puts the obstacle's whole travel inside the bottom tile row and leaves the
// other six tiles with geometry that did not move. That split is the point: it is what lets "changed
// only where it moved" be an assertion rather than a restatement of the tile count.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldRepair.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "Test_GroundNav_FieldEquality.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_fieldrepair
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_FieldRepairState;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::Get_HaloCellCount;
    using ck::groundnav::Get_RepairedField;
    using ck::groundnav::Get_RepairTileIndices;
    using ck::groundnav::ICk_GroundNav_GeometryBackend;
    using ck::groundnav::Request_AdvanceRepair;
    using ck::groundnav::Request_BeginRepair;
    using ck::groundnav::Request_ReleaseRepairedField;

    using ck_test_groundnav_field_equality::EEpochComparison;
    using ck_test_groundnav_field_equality::EPolicyComparison;
    using ck_test_groundnav_field_equality::Get_FirstFieldDifference;
    using ck_test_groundnav_field_equality::Get_FirstTileDifference;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 200.0f;

    constexpr auto kDivisions = 3;
    constexpr auto kTileCount = kDivisions * kDivisions;

    constexpr auto kFieldMinZ = -50.0f;
    constexpr auto kFieldMaxZ = 300.0f;

    // 400 uu of tile over 25 uu cells is a whole number of cells, so the lattice span is the authored
    // size. Asserted against the params rather than assumed - every hand-computed bound below rests on
    // it, and a config that no longer snapped evenly would move all of them at once.
    constexpr auto kTileSpanUu = 400.0;

    // A 200 uu cap over 25 uu cells is eight cells of halo. Same treatment: asserted, not assumed.
    constexpr auto kHaloUu = 200.0;

    constexpr auto kSourceEpoch = int64{1};
    constexpr auto kRepairEpoch = int64{2};

    constexpr auto kUnlimitedProbeBudget = TNumericLimits<int32>::Max();

    auto Get_IndicesAsString(
        const TArray<int32>& InIndices) -> FString
    {
        auto Text = FString{};

        for (const auto Index : InIndices)
        {
            if (NOT Text.IsEmpty())
            { Text.Append(TEXT(",")); }

            Text.AppendInt(Index);
        }

        return Text;
    }

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off: the subject is repair, and the conservative default would trim the
        // fixture's tile borders before the obstacle moved anywhere.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_FieldParams(
        TConstArrayView<FCk_GroundNav_MarkupRecord> InMarkups = {}) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{kDivisions, kDivisions};
        Params._MinZUu = kFieldMinZ;
        Params._MaxZUu = kFieldMaxZ;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MarkupRecords = InMarkups;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Reaches 400 uu past the field on every side, so the halo of every rim tile has real world in it
    // rather than the edge of the fixture.
    auto Make_Floor() -> FBox
    {
        return FBox{FVector{-400.0, -400.0, -10.0}, FVector{1600.0, 1600.0, 0.0}};
    }

    // Standing ON the floor rather than through it, so the cells beneath it lose their headroom and
    // drop out - the same shape of change a real obstacle makes.
    //
    // Its Y range stops at 175, which is 25 uu clear of the 200 uu halo that tile row y=1 reaches down
    // into. A footprint flush with that boundary would be asserting a tie-break in FBox::Intersect
    // rather than the selection rule.
    auto Make_ObstacleAtA() -> FBox
    {
        return FBox{FVector{100.0, 25.0, 0.0}, FVector{250.0, 175.0, 200.0}};
    }

    auto Make_ObstacleAtB() -> FBox
    {
        return FBox{FVector{700.0, 25.0, 0.0}, FVector{850.0, 175.0, 200.0}};
    }

    auto Make_WorldA() -> TArray<FBox>
    {
        return TArray<FBox>{Make_Floor(), Make_ObstacleAtA()};
    }

    auto Make_WorldB() -> TArray<FBox>
    {
        return TArray<FBox>{Make_Floor(), Make_ObstacleAtB()};
    }

    /** What the mover would report: the ground the obstacle left plus the ground it arrived on. */
    auto Make_DirtyBounds() -> FBox
    {
        return Make_ObstacleAtA() + Make_ObstacleAtB();
    }

    /** A dirty box the lattice does not reach at all, halo included. */
    auto Make_DirtyBoundsOutsideTheField() -> FBox
    {
        return FBox{FVector{5000.0, 5000.0, 0.0}, FVector{5100.0, 5100.0, 100.0}};
    }

    // A Walkability record wholly inside tile 0, and the cells it covers.
    //
    // The half extents put its footprint at [62.5, 137.5] x [262.5, 337.5]: no bound falls on a cell
    // line, so the closed-square rule has nothing to arbitrate and the covered rectangle is the only
    // one it can produce - cells 2..5 on X and 10..13 on Y of a tile whose origin IS the world origin.
    //
    // Placed clear of the obstacle, whose footprint stops at y=175, and far enough from every tile the
    // record's dirty box does NOT select that no such tile's halo reaches it: the nearest unselected
    // tile's halo begins at x=200, and the record ends at 137.5. That is what lets the carried-over
    // tiles be compared byte for byte against a full bake that HAS the record.
    constexpr auto kMarkupCellMinX = 2;
    constexpr auto kMarkupCellMaxX = 5;
    constexpr auto kMarkupCellMinY = 10;
    constexpr auto kMarkupCellMaxY = 13;

    auto Make_WalkabilityMarkup() -> FCk_GroundNav_MarkupRecord
    {
        return FCk_GroundNav_MarkupRecord{
            1,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{37.5, 37.5, 50.0}}},
            FTransform{FVector{100.0, 300.0, 0.0}},
            ECk_GroundNav_MarkupKind::Walkability};
    }

    /** The record's own footprint, which is the ground a walkability paint declares untrustworthy. */
    auto Make_MarkupDirtyBounds() -> FBox
    {
        return FBox{FVector{62.5, 262.5, -50.0}, FVector{137.5, 337.5, 50.0}};
    }

    auto Bake_Field(
        const TArray<FBox>&                         InBoxes,
        const FCk_GroundNav_Epoch&                  InEpoch,
        FCk_GroundNav_Field&                        OutField,
        TConstArrayView<FCk_GroundNav_MarkupRecord> InMarkups = {}) -> FCk_GroundNav_BakeStageResult
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        return DoBake_Field(Backend, Make_FieldParams(InMarkups), InEpoch, OutField);
    }

    auto Make_PublishedFieldA() -> FCk_GroundNav_FieldPtr
    {
        auto Field = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake_Field(Make_WorldA(), FCk_GroundNav_Epoch{kSourceEpoch}, *Field).Get_IsCompleted())
        { return {}; }

        return FCk_GroundNav_FieldPtr{Field};
    }

    /**
     * The tiles a repair of Make_DirtyBounds() must re-bake, derived here from the fixture's own
     * numbers rather than from the code under test.
     *
     * The rule being reproduced is the one the header states: a tile is selected when the dirty box
     * INFLATED BY THE HALO in XY - and not in Z - reaches the tile's world bounds. Placing the tiles
     * from the lattice arithmetic rather than from what a tile carries is deliberate: it is the same
     * account the selection uses, and it is the only one a failed tile could be selected under.
     */
    auto Get_ExpectedRepairTileIndices(
        const FBox& InDirtyBounds) -> TArray<int32>
    {
        const auto Inflated = FBox{
            FVector{InDirtyBounds.Min.X - kHaloUu, InDirtyBounds.Min.Y - kHaloUu, InDirtyBounds.Min.Z},
            FVector{InDirtyBounds.Max.X + kHaloUu, InDirtyBounds.Max.Y + kHaloUu, InDirtyBounds.Max.Z}};

        auto Indices = TArray<int32>{};

        for (auto Y = 0; Y < kDivisions; ++Y)
        {
            for (auto X = 0; X < kDivisions; ++X)
            {
                const auto TileBounds = FBox{
                    FVector{static_cast<double>(X) * kTileSpanUu,
                            static_cast<double>(Y) * kTileSpanUu,
                            static_cast<double>(kFieldMinZ)},
                    FVector{static_cast<double>(X + 1) * kTileSpanUu,
                            static_cast<double>(Y + 1) * kTileSpanUu,
                            static_cast<double>(kFieldMaxZ)}};

                if (NOT Inflated.Intersect(TileBounds))
                { continue; }

                Indices.Emplace((Y * kDivisions) + X);
            }
        }

        return Indices;
    }

    /** Run a whole repair at the given budget, reporting how many Advance calls it took. */
    auto Run_Repair(
        const ICk_GroundNav_GeometryBackend&        InBackend,
        const FCk_GroundNav_FieldPtr&               InSource,
        const FBox&                                 InDirtyBounds,
        TConstArrayView<FCk_GroundNav_MarkupRecord> InCurrentMarkupRecords,
        int32                                       InProbeBudget,
        FCk_GroundNav_FieldRepairState&             OutState,
        int32&                                      OutSliceCount) -> FCk_GroundNav_BakeStageResult
    {
        OutSliceCount = 0;

        const auto BeginResult = Request_BeginRepair(
            OutState, InSource, InDirtyBounds, FCk_GroundNav_Epoch{kRepairEpoch},
            InCurrentMarkupRecords);

        if (NOT BeginResult.Get_IsCompleted())
        { return BeginResult; }

        // Bounded so a repair that failed to advance ends the test rather than the process.
        constexpr auto MaxSlices = 256;

        while (OutSliceCount < MaxSlices)
        {
            const auto Result = Request_AdvanceRepair(InBackend, InProbeBudget, OutState);
            ++OutSliceCount;

            if (Result.Get_Status() == ECk_GroundNav_BakeStatus::BudgetExhausted)
            { continue; }

            return Result;
        }

        auto Overrun = FCk_GroundNav_BakeStageResult{};
        Overrun.Set_Status(ECk_GroundNav_BakeStatus::BudgetExhausted);

        return Overrun;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_LatticeArithmeticIsWhatTheFixtureAssumes,
    "CkTests.UnitTests.CkGroundNav.Repair.LatticeArithmeticIsWhatTheFixtureAssumes",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_LatticeArithmeticIsWhatTheFixtureAssumes::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    // Every hand-computed bound in this file rests on these two numbers. A config change that moved
    // either would otherwise surface as an unexplained set-equality failure three tests down.
    //
    // Compared with == rather than through TestEqual's double overload, which carries a default
    // tolerance: a lattice that snapped a hair off would be a different lattice, not a close one.
    const auto TileSpanUu = Make_FieldParams().Get_TileSpanUu();

    TestTrue(FString::Printf(TEXT("a 400 uu tile over 25 uu cells snaps to exactly 400 uu (got %f)"),
        TileSpanUu), TileSpanUu == kTileSpanUu);

    TestEqual(TEXT("and a 200 uu clearance cap over 25 uu cells is eight cells of halo"),
        Get_HaloCellCount(kMaxClearance, kCellSize), 8);

    const auto HaloUu =
        static_cast<double>(Get_HaloCellCount(kMaxClearance, kCellSize)) * static_cast<double>(kCellSize);

    TestTrue(FString::Printf(TEXT("which is the 200 uu the fixture inflates by (got %f)"), HaloUu),
        HaloUu == kHaloUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_RepairedFieldMatchesAFullRebake,
    "CkTests.UnitTests.CkGroundNav.Repair.RepairedFieldMatchesAFullRebake",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_RepairedFieldMatchesAFullRebake::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    const auto FieldA = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A bakes and publishes"), FieldA.IsValid()))
    { return false; }

    auto FullB = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("and a full bake of world B completes"),
        Bake_Field(Make_WorldB(), FCk_GroundNav_Epoch{kRepairEpoch}, FullB).Get_IsCompleted()))
    { return false; }

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldB()};

    auto State = FCk_GroundNav_FieldRepairState{};
    auto SliceCount = 0;

    if (NOT TestTrue(TEXT("the repair against world B completes"),
        Run_Repair(Backend, FieldA, Make_DirtyBounds(), FieldA->_Params._MarkupRecords,
            kUnlimitedProbeBudget, State, SliceCount)
            .Get_IsCompleted()))
    { return false; }

    const auto Repaired = Get_RepairedField(State);

    if (NOT TestTrue(TEXT("and yields a field"), Repaired.IsValid()))
    { return false; }

    // The whole claim of the feature, and the reason every field-level pass is re-derived rather than
    // patched: seams, tile edge boundary, plate labels and the open-body report included.
    const auto FieldDiff = Get_FirstFieldDifference(
        *Repaired, FullB, EPolicyComparison::Include, EEpochComparison::Exclude);

    if (NOT FieldDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("the repaired field differs from a full rebake of the same world at %s"), *FieldDiff));
        return false;
    }

    TestEqual(TEXT("the repaired field carries the epoch the repair was asked for"),
        Repaired->_Epoch._Value, kRepairEpoch);

    const auto Selected = Get_RepairTileIndices(*FieldA, Make_DirtyBounds());

    for (auto TileIndex = 0; TileIndex < kTileCount; ++TileIndex)
    {
        const auto WasRepaired = Selected.Contains(TileIndex);
        const auto ExpectedEpoch = WasRepaired ? kRepairEpoch : kSourceEpoch;

        if (Repaired->_Tiles[TileIndex]._Epoch._Value == ExpectedEpoch)
        { continue; }

        AddError(FString::Printf(
            TEXT("tile %d was %s and carries epoch %lld against the expected %lld"),
            TileIndex, WasRepaired ? TEXT("re-baked") : TEXT("carried across"),
            Repaired->_Tiles[TileIndex]._Epoch._Value, ExpectedEpoch));
        return false;
    }

    // Without this the epoch sweep above could pass on a repair that stamped nothing, because a field
    // whose tiles all kept the source epoch satisfies every "carried across" branch of it.
    TestTrue(TEXT("and the repair stamped at least one tile"), Selected.Num() > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_MovedObstacleChangesOnlyWhereItMoved,
    "CkTests.UnitTests.CkGroundNav.Repair.MovedObstacleChangesOnlyWhereItMoved",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_MovedObstacleChangesOnlyWhereItMoved::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    const auto FieldA = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A bakes and publishes"), FieldA.IsValid()))
    { return false; }

    const auto DirtyBounds = Make_DirtyBounds();

    // Set equality against a second derivation of the same rule, not against a recorded count: a
    // count would pass on the off-by-one that repairs the tile beside the one the obstacle crossed.
    const auto Selected = Get_RepairTileIndices(*FieldA, DirtyBounds);
    const auto Expected = Get_ExpectedRepairTileIndices(DirtyBounds);

    if (Selected != Expected)
    {
        AddError(FString::Printf(
            TEXT("the repair selected tiles [%s] against the [%s] the halo-inflated dirty box reaches"),
            *Get_IndicesAsString(Selected), *Get_IndicesAsString(Expected)));
        return false;
    }

    if (NOT TestTrue(FString::Printf(
        TEXT("and leaves tiles untouched to compare against (%d of %d selected)"),
        Selected.Num(), kTileCount), Selected.Num() > 0 && Selected.Num() < kTileCount))
    { return false; }

    auto FullB = FCk_GroundNav_Field{};
    const auto FullBakeResult = Bake_Field(Make_WorldB(), FCk_GroundNav_Epoch{kRepairEpoch}, FullB);

    if (NOT TestTrue(TEXT("a full bake of world B completes"), FullBakeResult.Get_IsCompleted()))
    { return false; }

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldB()};

    auto State = FCk_GroundNav_FieldRepairState{};
    auto SliceCount = 0;

    if (NOT TestTrue(TEXT("the repair completes"),
        Run_Repair(Backend, FieldA, DirtyBounds, FieldA->_Params._MarkupRecords,
            kUnlimitedProbeBudget, State, SliceCount)
            .Get_IsCompleted()))
    { return false; }

    const auto Repaired = Get_RepairedField(State);

    if (NOT TestTrue(TEXT("and yields a field"), Repaired.IsValid()))
    { return false; }

    // Epochs INCLUDED for the tiles nobody touched: a tile re-baked to the same numbers under a new
    // epoch would satisfy a content-only comparison and would still be work the repair must not do.
    for (auto TileIndex = 0; TileIndex < kTileCount; ++TileIndex)
    {
        if (Selected.Contains(TileIndex))
        { continue; }

        const auto TileDiff = Get_FirstTileDifference(TileIndex,
            Repaired->_Tiles[TileIndex], FieldA->_Tiles[TileIndex],
            EPolicyComparison::Include, EEpochComparison::Include);

        if (TileDiff.IsEmpty())
        { continue; }

        AddError(FString::Printf(
            TEXT("a tile the dirty box never reached moved: %s"), *TileDiff));
        return false;
    }

    // Non-vacuity. Tile 0 held the obstacle at A and holds nothing at B, so a repair that carried
    // every tile across unchanged would fail here rather than pass the sweep above.
    const auto MovedTileDiff = Get_FirstTileDifference(0,
        Repaired->_Tiles[0], FieldA->_Tiles[0],
        EPolicyComparison::Include, EEpochComparison::Exclude);

    TestFalse(TEXT("while the tile the obstacle left did change"), MovedTileDiff.IsEmpty());

    const auto RepairProbes = State.Get_ProbesSpent();
    const auto FullBakeProbes = FullBakeResult.Get_ProbesSpent();

    const auto Report = FString::Printf(
        TEXT("[REPAIR-BUDGET] tiles=%d of %d probes=%d fullBakeProbes=%d"),
        Selected.Num(), kTileCount, RepairProbes, FullBakeProbes);

    ck::groundnav::Display(TEXT("{}"), Report);

    // An inequality rather than a recorded number: the ratio is a property of this fixture's tile
    // split, and pinning it would break on every unrelated change to what a probe counts.
    if (RepairProbes >= FullBakeProbes)
    {
        AddError(FString::Printf(
            TEXT("a repair of %d of %d tiles spent %d probes against %d for the whole bake"),
            Selected.Num(), kTileCount, RepairProbes, FullBakeProbes));
        return false;
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_SlicedRepairMatchesOneShotRepair,
    "CkTests.UnitTests.CkGroundNav.Repair.SlicedRepairMatchesOneShotRepair",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_SlicedRepairMatchesOneShotRepair::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    const auto FieldA = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A bakes and publishes"), FieldA.IsValid()))
    { return false; }

    const auto DirtyBounds = Make_DirtyBounds();
    const auto Selected = Get_RepairTileIndices(*FieldA, DirtyBounds);

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldB()};

    auto OneShotState = FCk_GroundNav_FieldRepairState{};
    auto OneShotSlices = 0;

    if (NOT TestTrue(TEXT("the unbudgeted repair completes"),
        Run_Repair(Backend, FieldA, DirtyBounds, FieldA->_Params._MarkupRecords,
            kUnlimitedProbeBudget, OneShotState, OneShotSlices)
            .Get_IsCompleted()))
    { return false; }

    auto SlicedState = FCk_GroundNav_FieldRepairState{};
    auto SlicedSlices = 0;

    if (NOT TestTrue(TEXT("and the repair at the smallest budget completes too"),
        Run_Repair(Backend, FieldA, DirtyBounds, FieldA->_Params._MarkupRecords, 1,
            SlicedState, SlicedSlices).Get_IsCompleted()))
    { return false; }

    TestEqual(TEXT("an unbudgeted repair takes one slice"), OneShotSlices, 1);

    // Exactly one slice per repair tile, and NOT one more. The budget is checked after the first tile
    // of a slice, so a budget of one probe admits exactly one tile per call; and the closure pass, the
    // seam derivation and the labelling all run inside the call that finishes the last tile rather
    // than in a slice of their own.
    TestEqual(FString::Printf(TEXT("a budget of one probe takes one slice per repair tile (%d)"),
        Selected.Num()), SlicedSlices, Selected.Num());

    const auto OneShot = Get_RepairedField(OneShotState);
    const auto Sliced = Get_RepairedField(SlicedState);

    if (NOT TestTrue(TEXT("both repairs yield a field"), OneShot.IsValid() && Sliced.IsValid()))
    { return false; }

    // Epochs INCLUDED here, unlike the rebake comparison: both repairs were opened under the same
    // epoch and stamp the same tiles with it, so a difference in them is a defect rather than the
    // one thing a repair is supposed to move.
    const auto FieldDiff = Get_FirstFieldDifference(
        *OneShot, *Sliced, EPolicyComparison::Include, EEpochComparison::Include);

    if (NOT FieldDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("the sliced repair differs from the one-shot repair at %s"), *FieldDiff));
        return false;
    }

    // The property the whole budgeting contract rests on: a probe count that moved with the slice size
    // would mean the resume point was re-probing, and no budget in probes could be asserted against it.
    TestEqual(TEXT("with the same probes spent however the slices fell"),
        SlicedState.Get_ProbesSpent(), OneShotState.Get_ProbesSpent());

    TestTrue(TEXT("and probes worth counting"), OneShotState.Get_ProbesSpent() > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_HeldPreRepairFieldIsUnchanged,
    "CkTests.UnitTests.CkGroundNav.Repair.HeldPreRepairFieldIsUnchanged",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_HeldPreRepairFieldIsUnchanged::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    const auto FieldA = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A bakes and publishes"), FieldA.IsValid()))
    { return false; }

    // What a reader holds across the repair, and a value copy of the same thing to compare it against.
    const auto* HeldAddress = FieldA.Get();
    const auto Before = FCk_GroundNav_Field{*FieldA};

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldB()};

    auto State = FCk_GroundNav_FieldRepairState{};
    auto SliceCount = 0;

    if (NOT TestTrue(TEXT("the repair completes"),
        Run_Repair(Backend, FieldA, Make_DirtyBounds(), FieldA->_Params._MarkupRecords, 1,
            State, SliceCount).Get_IsCompleted()))
    { return false; }

    const auto Repaired = Get_RepairedField(State);

    if (NOT TestTrue(TEXT("and yields a field"), Repaired.IsValid()))
    { return false; }

    // Epochs included: a repair that restamped the source in place would look identical without them.
    const auto FieldDiff = Get_FirstFieldDifference(
        *FieldA, Before, EPolicyComparison::Include, EEpochComparison::Include);

    if (NOT FieldDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("the published field a reader is holding moved under it at %s"), *FieldDiff));
        return false;
    }

    // Not merely equal - the SAME object. A repair that handed the reader a fresh copy of the old
    // values would satisfy the comparison above and would still have invalidated every pointer into it.
    TestTrue(TEXT("and it is still the same object, not a copy of the old values"),
        FieldA.Get() == HeldAddress);

    TestTrue(TEXT("with the repair holding its own reference to it for the whole run"),
        State.Get_Source().Get() == HeldAddress);

    // The published field and the repaired one are two fields, not one aliased twice.
    TestTrue(TEXT("while the repaired field is a different object entirely"),
        Repaired.Get() != HeldAddress);

    const auto Released = Request_ReleaseRepairedField(State);

    TestTrue(TEXT("releasing hands over the same repaired field"), Released.Get() == Repaired.Get());

    // Releasing drops the source reference, which is what keeps a spent state from pinning the largest
    // thing this module produces.
    TestFalse(TEXT("and leaves the repair spent, holding neither field"),
        State.Get_Source().IsValid() || Get_RepairedField(State).IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_ZeroTileDirtyBoxCompletesWithoutChange,
    "CkTests.UnitTests.CkGroundNav.Repair.ZeroTileDirtyBoxCompletesWithoutChange",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_ZeroTileDirtyBoxCompletesWithoutChange::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    const auto FieldA = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A bakes and publishes"), FieldA.IsValid()))
    { return false; }

    const auto OutsideBounds = Make_DirtyBoundsOutsideTheField();

    TestEqual(TEXT("a dirty box past every tile, halo included, selects nothing"),
        Get_RepairTileIndices(*FieldA, OutsideBounds).Num(), 0);

    // Get_RepairTileIndices rather than a repair: Request_BeginRepair refuses a degenerate box through
    // CK_ENSURE_IF_NOT, and an ensure the harness would escalate is not how a pure selection rule is
    // asserted. The two answers are deliberately distinct - a box bounding nothing and a box reaching
    // no tile - and only the second is a repair anybody is owed.
    TestEqual(TEXT("and so does a box that bounds nothing at all"),
        Get_RepairTileIndices(*FieldA, FBox{ForceInit}).Num(), 0);

    auto State = FCk_GroundNav_FieldRepairState{};

    const auto BeginResult = Request_BeginRepair(
        State, FieldA, OutsideBounds, FCk_GroundNav_Epoch{kRepairEpoch},
        FieldA->_Params._MarkupRecords);

    TestEqual(TEXT("beginning such a repair is admitted, not refused"),
        BeginResult.Get_Status(), ECk_GroundNav_BakeStatus::Completed);

    TestEqual(TEXT("with no tile to re-bake"), State.Get_RepairTileCount(), 0);
    TestEqual(TEXT("and nothing outstanding"), State.Get_RemainingTileCount(), 0);

    // The repair is whole AT BEGIN. A caller is owed an answer to a paint outside every tile, and the
    // honest answer is that no ground changed.
    if (NOT TestTrue(TEXT("the repair is complete before a single slice runs"), State.Get_IsBuilt()))
    { return false; }

    const auto Repaired = Get_RepairedField(State);

    if (NOT TestTrue(TEXT("and the field is reachable immediately"), Repaired.IsValid()))
    { return false; }

    // Epochs included: nothing was re-baked, so nothing may have been restamped either - the field's
    // own epoch included.
    const auto FieldDiff = Get_FirstFieldDifference(
        *Repaired, *FieldA, EPolicyComparison::Include, EEpochComparison::Include);

    if (NOT FieldDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("a zero-tile repair changed the field at %s"), *FieldDiff));
        return false;
    }

    // A driver that advances unconditionally gets the same answer the slice that finished one would
    // have given it, rather than a second opinion.
    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldB()};

    TestEqual(TEXT("advancing a finished repair completes rather than re-running it"),
        Request_AdvanceRepair(Backend, 1, State).Get_Status(), ECk_GroundNav_BakeStatus::Completed);

    TestEqual(TEXT("having spent no probes at all"), State.Get_ProbesSpent(), 0);

    // Begin reports Completed for a repair with tiles outstanding too, so the status alone is not the
    // completion signal - Get_IsBuilt is. Pinned here so the assertions above cannot be read as saying
    // Begin finished the work.
    auto OutstandingState = FCk_GroundNav_FieldRepairState{};

    TestEqual(TEXT("beginning a repair that HAS tiles is admitted on the same status"),
        Request_BeginRepair(OutstandingState, FieldA, Make_DirtyBounds(),
            FCk_GroundNav_Epoch{kRepairEpoch}, FieldA->_Params._MarkupRecords).Get_Status(),
        ECk_GroundNav_BakeStatus::Completed);

    TestFalse(TEXT("while that one is not built and reaches no field"),
        OutstandingState.Get_IsBuilt() || Get_RepairedField(OutstandingState).IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_StaleGeometryFailsClosed,
    "CkTests.UnitTests.CkGroundNav.Repair.StaleGeometryFailsClosed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_StaleGeometryFailsClosed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    const auto FieldA = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A bakes and publishes"), FieldA.IsValid()))
    { return false; }

    const auto* HeldAddress = FieldA.Get();
    const auto Before = FCk_GroundNav_Field{*FieldA};

    const auto DirtyBounds = Make_DirtyBounds();
    const auto Selected = Get_RepairTileIndices(*FieldA, DirtyBounds);

    if (NOT TestTrue(TEXT("the fixture repairs more than one tile, so a slice can pause mid-repair"),
        Selected.Num() > 1))
    { return false; }

    auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldB()};

    auto State = FCk_GroundNav_FieldRepairState{};

    if (NOT TestTrue(TEXT("the repair begins"),
        Request_BeginRepair(State, FieldA, DirtyBounds, FCk_GroundNav_Epoch{kRepairEpoch},
            FieldA->_Params._MarkupRecords).Get_IsCompleted()))
    { return false; }

    if (NOT TestEqual(TEXT("one slice at the smallest budget pauses rather than finishing"),
        Request_AdvanceRepair(Backend, 1, State).Get_Status(),
        ECk_GroundNav_BakeStatus::BudgetExhausted))
    { return false; }

    TestTrue(TEXT("having repaired some tiles but not all of them"),
        State.Get_RemainingTileCount() > 0 && State.Get_RemainingTileCount() < Selected.Num());

    Backend.Request_BumpWorldRevision();

    // Tiles produced either side of a world change disagree at their shared seam, and the seam portal
    // derived from them is the one structure with no local evidence that it is wrong. So the repair
    // refuses to finish rather than publishing a field assembled out of two worlds.
    TestEqual(TEXT("a world that moved mid-repair fails the repair closed"),
        Request_AdvanceRepair(Backend, 1, State).Get_Status(),
        ECk_GroundNav_BakeStatus::StaleGeometry);

    TestEqual(TEXT("recording the failure on the repair itself"),
        State.Get_Status(), ECk_GroundNav_BuildStatus::Failed);

    TestFalse(TEXT("with nothing publishable to reach for"), Get_RepairedField(State).IsValid());
    TestFalse(TEXT("and nothing to release either"), Request_ReleaseRepairedField(State).IsValid());

    // What is published stays published. The previous answer is old; it is not wrong, and it is the
    // only answer there is.
    const auto FieldDiff = Get_FirstFieldDifference(
        *FieldA, Before, EPolicyComparison::Include, EEpochComparison::Include);

    if (NOT FieldDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("a failed repair moved the published field it opened against at %s"), *FieldDiff));
        return false;
    }

    TestTrue(TEXT("which is still the same object"), FieldA.Get() == HeldAddress);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_FieldRepair_RepairBakesUnderTheCallersRecordsNotTheSourceFields,
    "CkTests.UnitTests.CkGroundNav.Repair.RepairBakesUnderTheCallersRecordsNotTheSourceFields",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldRepair_RepairBakesUnderTheCallersRecordsNotTheSourceFields::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldrepair;

    // The world does not move at all here: every bake and every repair below reads world A. So the ONLY
    // thing that can separate a repaired field from the bake it is measured against is which markup
    // records its tiles were baked under, which is the whole subject.
    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_WorldA()};

    const auto Markup = Make_WalkabilityMarkup();
    const auto Markups = TArray<FCk_GroundNav_MarkupRecord>{Markup};

    const auto DirtyBounds = Make_MarkupDirtyBounds();

    const auto Unmarked = Make_PublishedFieldA();

    if (NOT TestTrue(TEXT("world A publishes a field whose params carry no records at all"),
        Unmarked.IsValid() && Unmarked->_Params._MarkupRecords.IsEmpty()))
    { return false; }

    auto FullMarked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("and a full bake of the same world WITH the record completes"),
        Bake_Field(Make_WorldA(), FCk_GroundNav_Epoch{kSourceEpoch}, FullMarked, Markups)
            .Get_IsCompleted()))
    { return false; }

    const auto Selected = Get_RepairTileIndices(*Unmarked, DirtyBounds);

    if (NOT TestTrue(FString::Printf(
        TEXT("the record's own footprint selects the tile it lands on, and not every tile (%s of %d)"),
        *Get_IndicesAsString(Selected), kTileCount),
        Selected.Contains(0) && Selected.Num() < kTileCount))
    { return false; }

    auto State = FCk_GroundNav_FieldRepairState{};
    auto SliceCount = 0;

    if (NOT TestTrue(TEXT("the repair under the record the CALLER holds completes"),
        Run_Repair(Backend, Unmarked, DirtyBounds, Markups, kUnlimitedProbeBudget, State, SliceCount)
            .Get_IsCompleted()))
    { return false; }

    const auto Repaired = Get_RepairedField(State);

    if (NOT TestTrue(TEXT("and yields a field"), Repaired.IsValid()))
    { return false; }

    const auto& RepairedPlates = Repaired->_Tiles[0]._Plates;
    const auto& SourcePlates = Unmarked->_Tiles[0]._Plates;

    auto CoveredStillPlated = 0;

    for (auto Layer = 0; Layer < RepairedPlates._LayerCount; ++Layer)
    {
        for (auto Y = kMarkupCellMinY; Y <= kMarkupCellMaxY; ++Y)
        {
            for (auto X = kMarkupCellMinX; X <= kMarkupCellMaxX; ++X)
            {
                if (RepairedPlates.Get_PlateIndexAt(X, Y, Layer) != FCk_GroundNav_Plate::kNoPlate)
                { ++CoveredStillPlated; }
            }
        }
    }

    auto CoveredWasPlated = 0;

    for (auto Layer = 0; Layer < SourcePlates._LayerCount; ++Layer)
    {
        for (auto Y = kMarkupCellMinY; Y <= kMarkupCellMaxY; ++Y)
        {
            for (auto X = kMarkupCellMinX; X <= kMarkupCellMaxX; ++X)
            {
                if (SourcePlates.Get_PlateIndexAt(X, Y, Layer) != FCk_GroundNav_Plate::kNoPlate)
                { ++CoveredWasPlated; }
            }
        }
    }

    TestEqual(TEXT("every cell the record covers is unplated in the re-baked tile"),
        CoveredStillPlated, 0);

    // Non-vacuity. Those cells were plain walkable floor in the field the repair opened against, so the
    // zero above is the record's doing rather than a hole the fixture always had.
    TestTrue(TEXT("where the source the repair opened against had them walkable"), CoveredWasPlated > 0);

    const auto FieldDiff = Get_FirstFieldDifference(
        *Repaired, FullMarked, EPolicyComparison::Include, EEpochComparison::Exclude);

    if (NOT FieldDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("a repair handed the record differs from a full bake that HAS it at %s"), *FieldDiff));
        return false;
    }

    if (NOT TestEqual(TEXT("and the repaired field's params carry the records it was handed"),
        Repaired->_Params._MarkupRecords.Num(), 1))
    { return false; }

    TestEqual(TEXT("the very record, by id"),
        Repaired->_Params._MarkupRecords[0].Get_Id(), Markup.Get_Id());

    // The other direction, and the one that says the SOURCE's records are never consulted: repairing a
    // field whose params DO carry the record, under an empty list, must produce the field a full bake
    // without it produces. A repair reading its records off the source would keep the paint here.
    const auto MarkedSource = FCk_GroundNav_FieldPtr{MakeShared<FCk_GroundNav_Field>(FullMarked)};

    if (NOT TestEqual(TEXT("the marked source's own params do carry the record"),
        MarkedSource->_Params._MarkupRecords.Num(), 1))
    { return false; }

    auto UnpaintState = FCk_GroundNav_FieldRepairState{};
    auto UnpaintSlices = 0;

    if (NOT TestTrue(TEXT("a repair of it under an EMPTY record list completes"),
        Run_Repair(Backend, MarkedSource, DirtyBounds, {}, kUnlimitedProbeBudget,
            UnpaintState, UnpaintSlices).Get_IsCompleted()))
    { return false; }

    const auto Unpainted = Get_RepairedField(UnpaintState);

    if (NOT TestTrue(TEXT("and yields a field"), Unpainted.IsValid()))
    { return false; }

    const auto UnpaintedDiff = Get_FirstFieldDifference(
        *Unpainted, *Unmarked, EPolicyComparison::Include, EEpochComparison::Exclude);

    if (NOT UnpaintedDiff.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("a repair handed no records consulted the source field's own at %s"), *UnpaintedDiff));
        return false;
    }

    TestEqual(TEXT("and its params hold no records either"),
        Unpainted->_Params._MarkupRecords.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
