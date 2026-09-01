// Publishing a ground field, and what a reader is entitled to while it holds one.
//
// The guarantee under test is not "the data is correct" — the bake tests own that. It is that a
// reader which took a field keeps EXACTLY that field until it lets go, whatever happens to the world
// meanwhile. Without it, an off-thread query would need a lock discipline around every read, and a
// repair could tear a structure someone was walking.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_fieldpublish
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPublisher;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_TileCoord;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    auto Make_Params() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{2, 2};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Ground reaching past the field on every side, so every tile's halo has real world in it rather
    // than the edge of the fixture.
    auto Make_WholeGround() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}};
    }

    // The same ground with a chasm cut through the middle of it, so a rebuild against this has
    // measurably less to walk on.
    auto Make_GroundWithChasm() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 300.0, 0.0}},
            FBox{FVector{-400.0, 500.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}};
    }

    auto Get_WalkableCellCount(const FCk_GroundNav_Field& InField) -> int32
    {
        auto Count = 0;

        for (const auto& Tile : InField._Tiles)
        { Count += Tile.Get_WalkableCellCount(); }

        return Count;
    }

    auto Bake(const TArray<FBox>& InBoxes, const FCk_GroundNav_Epoch& InEpoch, FCk_GroundNav_Field& OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        return DoBake_Field(Backend, Make_Params(), InEpoch, OutField).Get_IsCompleted();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Field_ReaderKeepsWhatItTookAcrossARebuild,
    "CkTests.UnitTests.CkGroundNav.Bake.Field_ReaderKeepsWhatItTookAcrossARebuild",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Field_ReaderKeepsWhatItTookAcrossARebuild::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldpublish;

    auto Publisher = FCk_GroundNav_FieldPublisher{};

    TestFalse(TEXT("nothing is published before a build"), Publisher.Get_HasPublished());
    TestEqual(TEXT("and the status says so"), Publisher.Get_Status(),
        ECk_GroundNav_BuildStatus::Unbuilt);

    auto First = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the first build completes"),
        Bake(Make_WholeGround(), Publisher.Get_NextEpoch(), *First)))
    { return false; }

    Publisher.Request_Publish(First);

    // The reader takes its reference here and does not look again until the very end.
    const auto Reader = Publisher.Get_Published();
    const auto CellsWhenTaken = Get_WalkableCellCount(*Reader);
    const auto EpochWhenTaken = Reader->_Epoch;

    TestTrue(TEXT("the first field has ground in it"), CellsWhenTaken > 0);
    TestEqual(TEXT("every tile of it built"), Reader->Get_BuiltTileCount(), Reader->Get_TileCount());

    auto Second = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the rebuild completes"),
        Bake(Make_GroundWithChasm(), Publisher.Get_NextEpoch(), *Second)))
    { return false; }

    Publisher.Request_Publish(Second);

    const auto CellsAfterRebuild = Get_WalkableCellCount(*Publisher.Get_Published());

    if (NOT TestTrue(TEXT("the rebuild actually changed the world"),
        CellsAfterRebuild != CellsWhenTaken))
    { return false; }

    // The whole point: the reader's field is byte-for-byte the one it took, not the one now current.
    TestEqual(TEXT("the reader still sees what it took"), Get_WalkableCellCount(*Reader),
        CellsWhenTaken);

    TestTrue(TEXT("carrying the epoch it took"), Reader->_Epoch == EpochWhenTaken);

    TestTrue(TEXT("while the publisher has moved on"),
        Publisher.Get_Epoch().Get_IsNewerThan(EpochWhenTaken));

    // Staleness is a comparison the reader makes, not a flag anybody had to remember to set.
    TestTrue(TEXT("so the reader can tell it is behind"), Publisher.Get_IsStale(EpochWhenTaken));
    TestFalse(TEXT("and the current field is not behind itself"),
        Publisher.Get_IsStale(Publisher.Get_Epoch()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Field_FailedBuildLeavesThePublishedFieldAlone,
    "CkTests.UnitTests.CkGroundNav.Bake.Field_FailedBuildLeavesThePublishedFieldAlone",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Field_FailedBuildLeavesThePublishedFieldAlone::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldpublish;

    auto Publisher = FCk_GroundNav_FieldPublisher{};

    auto Field = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the build completes"),
        Bake(Make_WholeGround(), Publisher.Get_NextEpoch(), *Field)))
    { return false; }

    Publisher.Request_Publish(Field);

    const auto EpochBefore = Publisher.Get_Epoch();
    const auto CellsBefore = Get_WalkableCellCount(*Publisher.Get_Published());

    Publisher.Request_RecordFailure();

    TestEqual(TEXT("a failure is recorded as a status"), Publisher.Get_Status(),
        ECk_GroundNav_BuildStatus::Failed);

    // The previous answer is old. It is not wrong, and it is the only answer there is — publishing
    // nothing here would turn a failed rebuild into a world with no floor.
    if (NOT TestTrue(TEXT("but something is still published"), Publisher.Get_HasPublished()))
    { return false; }

    TestEqual(TEXT("and it is the same field as before"),
        Get_WalkableCellCount(*Publisher.Get_Published()), CellsBefore);

    TestTrue(TEXT("at the same epoch"), Publisher.Get_Epoch() == EpochBefore);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Field_EpochSumIsMonotoneUnderPerTileRebuilds,
    "CkTests.UnitTests.CkGroundNav.Bake.Field_EpochSumIsMonotoneUnderPerTileRebuilds",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Field_EpochSumIsMonotoneUnderPerTileRebuilds::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldpublish;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field builds"), Bake(Make_WholeGround(), FCk_GroundNav_Epoch{1}, Field)))
    { return false; }

    if (NOT TestEqual(TEXT("a 2x2 division is four tiles"), Field.Get_TileCount(), 4))
    { return false; }

    TestEqual(TEXT("four tiles at epoch one sum to four"), Field.Get_AggregatedTileEpochSum(),
        static_cast<int64>(4));

    // Tiles rebuild independently, so the field's fingerprint has to move whichever one moves. A max
    // over tile epochs would call two fields equal when three of their four tiles differ.
    auto Previous = Field.Get_AggregatedTileEpochSum();

    for (const auto& Order : {TArray<int32>{2, 0, 3, 1}, TArray<int32>{1, 3, 0, 2}})
    {
        for (const auto TileIndex : Order)
        {
            Field._Tiles[TileIndex]._Epoch = Field._Tiles[TileIndex]._Epoch.Get_Next();

            const auto Current = Field.Get_AggregatedTileEpochSum();

            if (Current <= Previous)
            {
                AddError(FString::Printf(
                    TEXT("rebuilding tile %d moved the sum from %lld to %lld"),
                    TileIndex, Previous, Current));
                return false;
            }

            Previous = Current;
        }
    }

    // Two interleavings that rebuilt every tile the same number of times must land on the same
    // fingerprint, or the number would depend on the order work happened to be scheduled in.
    TestEqual(TEXT("and two full passes in different orders land on the same sum"),
        Field.Get_AggregatedTileEpochSum(), static_cast<int64>(12));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Field_TilesPartitionTheFieldWithoutGaps,
    "CkTests.UnitTests.CkGroundNav.Bake.Field_TilesPartitionTheFieldWithoutGaps",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Field_TilesPartitionTheFieldWithoutGaps::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fieldpublish;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field builds"), Bake(Make_WholeGround(), FCk_GroundNav_Epoch{1}, Field)))
    { return false; }

    const auto Span = Field._Params.Get_TileSpanUu();

    TestEqual(TEXT("the tile span is a whole number of cells"), Span,
        static_cast<double>(kTileSize));

    TestEqual(TEXT("and the field covers every tile of it"), Field._Params.Get_Bounds().GetSize().X,
        Span * 2.0);

    // A point in each tile, taken at its centre, must resolve to that tile and no other. Getting this
    // wrong puts a query in a neighbour's coordinates, where every index it then uses is real and
    // wrong.
    for (auto Y = 0; Y < 2; ++Y)
    {
        for (auto X = 0; X < 2; ++X)
        {
            const auto Centre = FVector{
                (static_cast<double>(X) + 0.5) * Span, (static_cast<double>(Y) + 0.5) * Span, 0.0};

            const auto Coord = Field._Params.Get_TileCoordAt(Centre);
            const auto* Tile = Field.Get_TileAt(Centre);

            if (Coord._X != X || Coord._Y != Y || Tile == nullptr)
            {
                AddError(FString::Printf(TEXT("the centre of tile (%d,%d) resolved to (%d,%d)"),
                    X, Y, Coord._X, Coord._Y));
                return false;
            }

            TestEqual(TEXT("and the tile knows its own coordinate"), Tile->_Coord._X, X);
            TestEqual(TEXT("on both axes"), Tile->_Coord._Y, Y);
        }
    }

    // Outside the field is a miss, not the nearest tile. A query that silently clamped would answer
    // confidently about ground the field never covered.
    TestTrue(TEXT("a point past the last tile resolves to nothing"),
        Field.Get_TileAt(FVector{Span * 2.5, Span * 0.5, 0.0}) == nullptr);

    TestTrue(TEXT("and so does one before the first"),
        Field.Get_TileAt(FVector{-Span * 0.5, Span * 0.5, 0.0}) == nullptr);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
