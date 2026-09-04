// What a field survives being written down and read back, and what a reader answers when it cannot.
//
// The round trip is pinned against the SHARED field comparator rather than against a byte compare of
// the two fields: these structures carry doubles beside int32s, so they have padding a byte compare
// would read, and padding is not a value anything set. The BLOB is the thing compared byte for byte,
// and only where two writes of one field must agree.

#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_FieldTypes.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_FieldEquality.h"
#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <GameplayTagContainer.h>
#include <NativeGameplayTags.h>
#include <UObject/Class.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Two tags whose names sort Alpha before Zulu whichever order they are authored in, which is what the
// table-order pin reads. A third name of the SAME BYTE LENGTH as the first is what the unknown-tag pin
// overwrites it with, so the blob stays structurally intact and only the name stops resolving.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Serialization_AreaAlpha, "CkTests.GroundNav.Serialization.AreaAlpha");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Serialization_AreaZulu, "CkTests.GroundNav.Serialization.AreaZulu");

namespace ck_test_groundnav_serialization
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::Get_TileCoord;
    using ck::groundnav::Get_TileIndex;
    using ck::groundnav::Read_Field;
    using ck::groundnav::Read_TagTable;
    using ck::groundnav::Read_TileInto;
    using ck::groundnav::Write_Field;
    using ck::groundnav::Write_FieldSubset;
    using ck::groundnav::Write_Tile;
    using ck::groundnav::kFieldBlobCookSecondsOffset;

    using ck_test_groundnav_field_equality::EPolicyComparison;
    using ck_test_groundnav_field_equality::Get_FirstFieldDifference;
    using ck_test_groundnav_field_equality::Get_FirstParamsDifference;
    using ck_test_groundnav_field_equality::Get_TilesEqual;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_FlatScene;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;
    using ck_test_groundnav_queryfixtures::kGroundZ;

    constexpr auto kAlphaTagName = TEXT("CkTests.GroundNav.Serialization.AreaAlpha");

    // Same byte length as the name above, and deliberately not a tag anything registers.
    constexpr auto kUnregisteredTagName = TEXT("CkTests.GroundNav.Serialization.AreaOmega");

    // --------------------------------------------------------------------------------------------------

    auto Get_StatusName(ECk_GroundNav_LoadStatus InStatus) -> FString
    {
        return StaticEnum<ECk_GroundNav_LoadStatus>()->GetNameStringByValue(static_cast<int64>(InStatus));
    }

    /** A field of the given lattice with every tile present, carrying its coord, and Unbuilt. */
    auto Make_EmptyFieldLike(
        const FCk_GroundNav_FieldParams& InParams) -> FCk_GroundNav_Field
    {
        auto Field = FCk_GroundNav_Field{};

        Field._Params = InParams;
        Field._Tiles.SetNum(InParams.Get_TileCount());

        for (auto TileIndex = 0; TileIndex < Field._Tiles.Num(); ++TileIndex)
        { Field._Tiles[TileIndex]._Coord = Get_TileCoord(InParams._Divisions, TileIndex); }

        return Field;
    }

    auto Make_Link(
        int32               InId,
        const FVector&      InStart,
        const FVector&      InEnd,
        const FGameplayTag& InUserTypeTag) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};
        Record.Set_UserTypeTag(InUserTypeTag);

        return Record;
    }

    auto Bake_FlatSceneWithLinks(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_Field&                    OutField) -> bool
    {
        auto Params = Make_FlatParams();
        Params._Links = InLinks;

        return Bake(Make_FlatScene(), Params, OutField);
    }

    // Every member of the params below is moved OFF its default, which is what makes the round trip
    // evidence: a default that survives says nothing about whether the writer wrote it.
    constexpr auto kAuthoredMaxColumnsPerTile = 131072;
    constexpr auto kAuthoredPlaneFitToleranceUu = 3.5f;
    constexpr auto kAuthoredNormalConeDegrees = 12.5f;
    constexpr auto kAuthoredMaxClearanceUu = 175.0f;

    // Far outside the fixture's floor, and a value whose eight bytes appear nowhere else in the blob:
    // the corrupt-transform pin finds the markup's translation by searching for exactly this number.
    constexpr auto kAuthoredMarkupCentreX = 12345.5;

    auto Make_AuthoredMarkup() -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            7,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{120.0, 80.0, 40.0}}},
            FTransform{FRotator{0.0, 30.0, 0.0}, FVector{kAuthoredMarkupCentreX, 250.0, 15.0}, FVector{2.0}},
            ECk_GroundNav_MarkupKind::Cost};

        Record.Set_AreaTag(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
        Record.Set_Enable(ECk_EnableDisable::Enable);
        Record.Set_CostMultiplier(2.5f);
        Record.Set_RequestedAtEpoch(11);

        return Record;
    }

    auto Make_AuthoredLink() -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{
            3, FVector{200.0, 200.0, kGroundZ}, FVector{600.0, 200.0, kGroundZ}};

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Forward);
        Record.Set_CostMultiplierForward(1.75f);
        Record.Set_CostMultiplierBackward(2.25f);
        Record.Set_ClearanceUu(65.0f);
        Record.Set_AreaTag(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
        Record.Set_UserTypeTag(TAG_CkTests_GroundNav_Serialization_AreaZulu);
        Record.Set_Enable(ECk_EnableDisable::Enable);
        Record.Set_ProjectionMode(ECk_NavSurface_ProjectionMode::Down);
        Record.Set_ProjectionHorizontalExtentUu(75.0f);
        Record.Set_ProjectionVerticalExtentUu(125.0f);
        Record.Set_RequestedAtEpoch(13);

        return Record;
    }

    auto Make_AuthoredParams() -> FCk_GroundNav_FieldParams
    {
        auto Params = Make_FlatParams();

        Params._Config.Set_MaxColumnsPerTile(kAuthoredMaxColumnsPerTile);
        Params._MergeTunables = FCk_GroundNav_MergeTunables{
            kAuthoredPlaneFitToleranceUu, kAuthoredNormalConeDegrees};
        Params._MaxClearanceUu = kAuthoredMaxClearanceUu;
        Params._MarkupRecords = TArray<FCk_GroundNav_MarkupRecord>{Make_AuthoredMarkup()};
        Params._Links = TArray<FCk_GroundNav_LinkRecord>{Make_AuthoredLink()};

        return Params;
    }

    /**
     * A quiet NaN, spelled by its bits rather than computed.
     *
     * What a corrupt blob holds is a bit pattern, and arithmetic that produces one is at the mercy of
     * whatever the compiler decides to fold.
     */
    auto Get_NotANumber() -> double
    {
        constexpr auto QuietNaNBits = uint64{0x7FF8000000000000};

        auto Value = 0.0;
        FMemory::Memcpy(&Value, &QuietNaNBits, sizeof(Value));

        return Value;
    }

    /** Overwrite the first occurrence of one eight-byte double in a blob with another. */
    auto Do_ReplaceDouble(
        TArray<uint8>& InOutBlob,
        double         InFrom,
        double         InTo) -> bool
    {
        constexpr auto Width = static_cast<int32>(sizeof(double));

        auto FromBytes = TArray<uint8>{};
        auto ToBytes = TArray<uint8>{};

        FromBytes.SetNumZeroed(Width);
        ToBytes.SetNumZeroed(Width);

        FMemory::Memcpy(FromBytes.GetData(), &InFrom, Width);
        FMemory::Memcpy(ToBytes.GetData(), &InTo, Width);

        for (auto Index = 0; (Index + Width) <= InOutBlob.Num(); ++Index)
        {
            if (FMemory::Memcmp(&InOutBlob[Index], FromBytes.GetData(), Width) != 0)
            { continue; }

            FMemory::Memcpy(&InOutBlob[Index], ToBytes.GetData(), Width);
            return true;
        }

        return false;
    }

    /** Overwrite the first occurrence of one UTF-8 string in a blob with another of the same length. */
    auto Do_ReplaceBytes(
        TArray<uint8>& InOutBlob,
        const FString& InFrom,
        const FString& InTo) -> bool
    {
        const auto From = FTCHARToUTF8{*InFrom};
        const auto To = FTCHARToUTF8{*InTo};

        const auto Length = static_cast<int32>(From.Length());

        if (Length == 0 || Length != static_cast<int32>(To.Length()))
        { return false; }

        const auto* FromBytes = reinterpret_cast<const uint8*>(From.Get());
        const auto* ToBytes = reinterpret_cast<const uint8*>(To.Get());

        for (auto Index = 0; (Index + Length) <= InOutBlob.Num(); ++Index)
        {
            if (FMemory::Memcmp(&InOutBlob[Index], FromBytes, Length) != 0)
            { continue; }

            FMemory::Memcpy(&InOutBlob[Index], ToBytes, Length);
            return true;
        }

        return false;
    }

    /** Every byte of two blobs but the header's cook date, which is the one run they may differ in. */
    auto Get_BlobsMatchOutsideTheCookDate(
        const TArray<uint8>& InLeft,
        const TArray<uint8>& InRight) -> bool
    {
        if (InLeft.Num() != InRight.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft.Num(); ++Index)
        {
            const auto IsCookDate = Index >= kFieldBlobCookSecondsOffset &&
                                    Index < (kFieldBlobCookSecondsOffset + static_cast<int32>(sizeof(int64)));

            if (IsCookDate)
            { continue; }

            if (InLeft[Index] != InRight[Index])
            { return false; }
        }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_WholeFieldRoundTripsThroughTheComparator,
    "CkTests.UnitTests.CkGroundNav.Serialization.WholeFieldRoundTripsThroughTheComparator",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_WholeFieldRoundTripsThroughTheComparator::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the field writes to a non-empty blob"), Blob.Num() > 0))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the blob reads back [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    // Every derived array in the loaded field was re-derived, never read, so this compares the derives
    // against themselves as much as it compares the tiles.
    const auto Difference = Get_FirstFieldDifference(Field, Loaded, EPolicyComparison::Include);

    TestTrue(FString::Printf(TEXT("the loaded field equals the baked one [%s]"), *Difference), Difference.IsEmpty());

    TestEqual(TEXT("and holds the same number of tiles"), Loaded._Tiles.Num(), Field._Tiles.Num());

    TestTrue(TEXT("and the same params divisions"), Loaded._Params._Divisions == Field._Params._Divisions);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_ParamsRoundTripEveryMember,
    "CkTests.UnitTests.CkGroundNav.Serialization.ParamsRoundTripEveryMember",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_ParamsRoundTripEveryMember::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes under fully authored params"),
        Bake(Make_FlatScene(), Make_AuthoredParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the blob reads back [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    // The comparator names the member, so a writer that drops one says which one it dropped.
    const auto Difference = Get_FirstParamsDifference(Field._Params, Loaded._Params);

    TestTrue(FString::Printf(TEXT("every params member survives the round trip [%s]"), *Difference),
        Difference.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_CorruptTransformIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.CorruptTransformIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_CorruptTransformIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes under fully authored params"),
        Bake(Make_FlatScene(), Make_AuthoredParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    // A NaN where the markup's transform carries its X. Nothing downstream would catch it: a bound
    // built from it compares false against every point tested against it, and the field would simply
    // stop deciding anything there without a reader ever being told.
    if (NOT TestTrue(TEXT("the markup's translation is in the blob and can be overwritten"),
        Do_ReplaceDouble(Blob, kAuthoredMarkupCentreX, Get_NotANumber())))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a non-finite transform is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Corrupt);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    TestEqual(TEXT("including its records"), Loaded._Params._MarkupRecords.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_TileRoundTripEqualsTheWholeFieldsTile,
    "CkTests.UnitTests.CkGroundNav.Serialization.TileRoundTripEqualsTheWholeFieldsTile",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_TileRoundTripEqualsTheWholeFieldsTile::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto Coord = FCk_GroundNav_TileCoord{1, 0};
    const auto TileIndex = Get_TileIndex(Field._Params._Divisions, Coord);

    if (NOT TestTrue(TEXT("the field has the tile the pin writes"), Field._Tiles.IsValidIndex(TileIndex)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Tile(Field, Coord, Blob);

    auto Target = Make_EmptyFieldLike(Field._Params);
    const auto Status = Read_TileInto(Blob, Target);

    if (NOT TestTrue(FString::Printf(TEXT("the tile blob reads into a field of the same lattice [%s]"),
        *Get_StatusName(Status)), Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    TestTrue(TEXT("the loaded tile equals the whole field's tile"),
        Get_TilesEqual(Field._Tiles[TileIndex], Target._Tiles[TileIndex], EPolicyComparison::Include));

    // The rest of the target is untouched, which is what makes a per-tile read a per-tile read.
    for (auto OtherIndex = 0; OtherIndex < Target._Tiles.Num(); ++OtherIndex)
    {
        if (OtherIndex == TileIndex)
        { continue; }

        TestTrue(FString::Printf(TEXT("tile %d stays unbuilt"), OtherIndex),
            Target._Tiles[OtherIndex]._Status == ECk_GroundNav_BuildStatus::Unbuilt);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_SubsetDropsPortalsAndLinksTouchingAbsentTiles,
    "CkTests.UnitTests.CkGroundNav.Serialization.SubsetDropsPortalsAndLinksTouchingAbsentTiles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_SubsetDropsPortalsAndLinksTouchingAbsentTiles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    // A link with one end on the tile the subset keeps and the other on a tile it leaves out, so the
    // resolution has something to lose.
    auto Params = Make_QueryParams();
    Params._Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, FVector{200.0, 200.0, kGroundZ}, FVector{1200.0, 200.0, kGroundZ},
            TAG_CkTests_GroundNav_Serialization_AreaAlpha)};

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Params, Field)))
    { return false; }

    if (NOT TestTrue(TEXT("the whole field has crossings between its tiles"), Field.Get_SeamPortalCount() > 0))
    { return false; }

    // The drop only means something if the link reached both tiles to begin with.
    if (NOT TestTrue(TEXT("and the authored link resolves on the whole field"),
        Field._ResolvedLinks.Num() == 1 && Field._ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    const auto KeptTiles = TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1}};

    auto Blob = TArray<uint8>{};
    Write_FieldSubset(Field, KeptTiles, Blob);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the subset reads back [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    if (NOT TestEqual(TEXT("the subset keeps the whole lattice"), Loaded._Tiles.Num(), Field._Tiles.Num()))
    { return false; }

    auto IsKept = TArray<bool>{};
    IsKept.Init(false, Loaded._Tiles.Num());

    for (const auto& Coord : KeptTiles)
    {
        const auto KeptIndex = Get_TileIndex(Field._Params._Divisions, Coord);

        if (IsKept.IsValidIndex(KeptIndex))
        { IsKept[KeptIndex] = true; }
    }

    for (auto TileIndex = 0; TileIndex < Loaded._Tiles.Num(); ++TileIndex)
    {
        if (IsKept[TileIndex])
        {
            TestTrue(FString::Printf(TEXT("kept tile %d equals the original's"), TileIndex),
                Get_TilesEqual(Field._Tiles[TileIndex], Loaded._Tiles[TileIndex], EPolicyComparison::Include));

            continue;
        }

        TestTrue(FString::Printf(TEXT("absent tile %d reads unbuilt"), TileIndex),
            Loaded._Tiles[TileIndex]._Status == ECk_GroundNav_BuildStatus::Unbuilt);

        TestEqual(FString::Printf(TEXT("absent tile %d holds no cells"), TileIndex),
            Loaded._Tiles[TileIndex]._SurfaceZ.Num(), 0);

        TestEqual(FString::Printf(TEXT("absent tile %d holds no plates"), TileIndex),
            Loaded._Tiles[TileIndex]._Plates._Plates.Num(), 0);
    }

    for (const auto& Portal : Loaded._SeamPortals)
    {
        TestTrue(TEXT("no seam portal names an absent tile"),
            IsKept.IsValidIndex(Portal._TileIndexA) && IsKept[Portal._TileIndexA] &&
            IsKept.IsValidIndex(Portal._TileIndexB) && IsKept[Portal._TileIndexB]);
    }

    if (NOT TestEqual(TEXT("the authored link survives the subset"), Loaded._ResolvedLinks.Num(), 1))
    { return false; }

    const auto& ResolvedLink = Loaded._ResolvedLinks[0];

    TestTrue(TEXT("the link end over an absent tile resolved to no plate"),
        ResolvedLink._EndFlatPlate == INDEX_NONE);

    TestTrue(TEXT("and the link is therefore counted unresolved"), Loaded.Get_UnresolvedLinkCount() > 0);

    for (const auto& Link : Loaded._ResolvedLinks)
    {
        const auto StartIsAnchored = Link._StartFlatPlate == INDEX_NONE ||
                                     (IsKept.IsValidIndex(Link._StartSurface._TileIndex) &&
                                      IsKept[Link._StartSurface._TileIndex]);

        const auto EndIsAnchored = Link._EndFlatPlate == INDEX_NONE ||
                                   (IsKept.IsValidIndex(Link._EndSurface._TileIndex) &&
                                    IsKept[Link._EndSurface._TileIndex]);

        TestTrue(TEXT("no resolved link holds a flat plate on an absent tile"), StartIsAnchored && EndIsAnchored);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_WrongVersionIsAStatusNotAnEnsure,
    "CkTests.UnitTests.CkGroundNav.Serialization.WrongVersionIsAStatusNotAnEnsure",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_WrongVersionIsAStatusNotAnEnsure::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake(Make_FlatScene(), Make_FlatParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the blob is long enough to carry a version"), Blob.Num() > 8))
    { return false; }

    // The format version's low byte, straight after the magic.
    Blob[4] = static_cast<uint8>(Blob[4] + 1);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a bumped version is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::WrongVersion);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    TestTrue(TEXT("including its params"), Loaded._Params._Divisions == FIntPoint{1, 1});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_TruncatedBlobIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.TruncatedBlobIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_TruncatedBlobIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake(Make_FlatScene(), Make_FlatParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the blob is long enough to halve"), Blob.Num() > 64))
    { return false; }

    // Half a blob still carries an intact magic and version, so what is being pinned is the body
    // running out rather than the header being refused.
    Blob.SetNum(Blob.Num() / 2);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a half blob is refused as truncated [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Truncated);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_UnknownTagOnLoadIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.UnknownTagOnLoadIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_UnknownTagOnLoadIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    const auto Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, FVector{200.0, 200.0, kGroundZ}, FVector{600.0, 200.0, kGroundZ},
            TAG_CkTests_GroundNav_Serialization_AreaAlpha)};

    if (NOT TestTrue(TEXT("the flat scene bakes with a tagged link"), Bake_FlatSceneWithLinks(Links, Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the tag's name is in the blob and can be overwritten"),
        Do_ReplaceBytes(Blob, kAlphaTagName, kUnregisteredTagName)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a name that resolves to no tag is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::UnknownTag);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_LatticeMismatchIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.LatticeMismatchIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_LatticeMismatchIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Tile(Field, FCk_GroundNav_TileCoord{0, 0}, Blob);

    // Same origin, same cell size, a different number of divisions: a lattice the tile's indices were
    // never derived against.
    auto Target = Make_EmptyFieldLike(Make_FlatParams());
    const auto Status = Read_TileInto(Blob, Target);

    TestTrue(FString::Printf(TEXT("a tile from another lattice is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::LatticeMismatch);

    TestTrue(TEXT("and the caller's field is untouched"),
        Target._Tiles[0]._Status == ECk_GroundNav_BuildStatus::Unbuilt);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_NothingProcessRelativeIsPersisted,
    "CkTests.UnitTests.CkGroundNav.Serialization.NothingProcessRelativeIsPersisted",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_NothingProcessRelativeIsPersisted::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    const auto StartA = FVector{200.0, 200.0, kGroundZ};
    const auto EndA = FVector{600.0, 200.0, kGroundZ};
    const auto StartB = FVector{200.0, 600.0, kGroundZ};
    const auto EndB = FVector{600.0, 600.0, kGroundZ};

    auto AlphaFirst = FCk_GroundNav_Field{};

    const auto AlphaFirstLinks = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, StartA, EndA, TAG_CkTests_GroundNav_Serialization_AreaAlpha),
        Make_Link(2, StartB, EndB, TAG_CkTests_GroundNav_Serialization_AreaZulu)};

    if (NOT TestTrue(TEXT("the flat scene bakes with alpha first"), Bake_FlatSceneWithLinks(AlphaFirstLinks, AlphaFirst)))
    { return false; }

    auto FirstWrite = TArray<uint8>{};
    auto SecondWrite = TArray<uint8>{};

    Write_Field(AlphaFirst, FirstWrite);
    Write_Field(AlphaFirst, SecondWrite);

    TestTrue(TEXT("two writes of one field differ only in the header's cook date"),
        Get_BlobsMatchOutsideTheCookDate(FirstWrite, SecondWrite));

    // The same two tags, reached in the opposite order. What makes this evidence is the ASCENDING-SORT
    // assertion at the end rather than the reversal itself: two authored orders could agree by luck,
    // where a table sorted by string cannot come out in any order but that one whatever reached the
    // writer first.
    auto ZuluFirst = FCk_GroundNav_Field{};

    const auto ZuluFirstLinks = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, StartA, EndA, TAG_CkTests_GroundNav_Serialization_AreaZulu),
        Make_Link(2, StartB, EndB, TAG_CkTests_GroundNav_Serialization_AreaAlpha)};

    if (NOT TestTrue(TEXT("the flat scene bakes with zulu first"), Bake_FlatSceneWithLinks(ZuluFirstLinks, ZuluFirst)))
    { return false; }

    auto ZuluFirstBlob = TArray<uint8>{};
    Write_Field(ZuluFirst, ZuluFirstBlob);

    auto AlphaFirstTable = TArray<FString>{};
    auto ZuluFirstTable = TArray<FString>{};

    const auto AlphaStatus = Read_TagTable(FirstWrite, AlphaFirstTable);
    const auto ZuluStatus = Read_TagTable(ZuluFirstBlob, ZuluFirstTable);

    if (NOT TestTrue(FString::Printf(TEXT("both tables read back [%s] [%s]"),
        *Get_StatusName(AlphaStatus), *Get_StatusName(ZuluStatus)),
        AlphaStatus == ECk_GroundNav_LoadStatus::Loaded && ZuluStatus == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    if (NOT TestEqual(TEXT("the table carries both tags"), AlphaFirstTable.Num(), 2))
    { return false; }

    TestEqual(TEXT("and both blobs carry the same number of names"), ZuluFirstTable.Num(), AlphaFirstTable.Num());

    for (auto Index = 0; Index < AlphaFirstTable.Num(); ++Index)
    {
        TestEqual(FString::Printf(TEXT("table entry %d is the same whichever order the tags were authored in"), Index),
            ZuluFirstTable[Index], AlphaFirstTable[Index]);
    }

    for (auto Index = 1; Index < AlphaFirstTable.Num(); ++Index)
    {
        TestTrue(FString::Printf(TEXT("table entry %d sorts after the one before it"), Index),
            AlphaFirstTable[Index - 1].Compare(AlphaFirstTable[Index], ESearchCase::CaseSensitive) < 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
