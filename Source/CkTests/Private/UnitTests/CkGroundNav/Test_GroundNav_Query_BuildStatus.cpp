// What a consumer asks before it asks anything else: is there ground here, and can I trust it yet.
//
// The whole point of this layer is that a published field never says Building — it is immutable, so
// its tiles are built or they are not — and the volume above it composes Building from the field plus
// the fact that a build is running. These tests hold the two apart: the field-only answers over a
// field with a tile taken out of it, and the volume answers over the same field with a build declared
// in flight. The last one drives a real sliced build and watches the health a consumer would see,
// because the transition NoData to Building to Ready is the sequence an agent's spawn logic waits on,
// and a field that appeared before the build finished would be a half-built world answered as whole.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_FieldBuild.h"
#include "CkGroundNav/Query/CkGroundNav_Query_BuildStatus.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_buildstatus
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldBuildState;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_FieldPublisher;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::Get_CompletedField;
    using ck::groundnav::Get_ProviderHealth;
    using ck::groundnav::Get_RegionStatusAt;
    using ck::groundnav::Get_RegionStatusAt_ForVolume;
    using ck::groundnav::Get_RegionStatusWithin;
    using ck::groundnav::Get_SurfaceBounds;
    using ck::groundnav::Request_AdvanceBuild;
    using ck::groundnav::Request_BeginBuild;
    using ck::groundnav::Request_ReleaseCompletedField;

    constexpr auto kBoundsTolerance = 1.0e-3;

    // Bounded so a build that fails to advance ends the test rather than the process.
    constexpr auto kMaxSlices = 256;

    /** A box over one patch of ground, spanning the field's whole vertical slab. */
    auto Make_RegionXY(double InMinX, double InMinY, double InMaxX, double InMaxY) -> FBox
    {
        return FBox{
            FVector{InMinX, InMinY, static_cast<double>(ck_test_groundnav_queryfixtures::kMinZ)},
            FVector{InMaxX, InMaxY, static_cast<double>(ck_test_groundnav_queryfixtures::kMaxZ)}};
    }

    /** The health sequence a consumer would see, with repeats collapsed. */
    auto Do_RecordHealth(
        TArray<ECk_NavSurface_ProviderHealth>& InOutObserved,
        ECk_NavSurface_ProviderHealth          InHealth) -> void
    {
        if (InOutObserved.Num() > 0 && InOutObserved.Last() == InHealth)
        { return; }

        InOutObserved.Emplace(InHealth);
    }

    auto Get_HealthName(ECk_NavSurface_ProviderHealth InHealth) -> const TCHAR*
    {
        switch (InHealth)
        {
            case ECk_NavSurface_ProviderHealth::Ready:    return TEXT("Ready");
            case ECk_NavSurface_ProviderHealth::Building: return TEXT("Building");
            case ECk_NavSurface_ProviderHealth::NoData:   return TEXT("NoData");
            case ECk_NavSurface_ProviderHealth::Error:    return TEXT("Error");
            default: break;
        }

        return TEXT("Unknown");
    }

    auto Get_HealthSequenceText(const TArray<ECk_NavSurface_ProviderHealth>& InObserved) -> FString
    {
        auto Text = FString{};

        for (const auto Health : InObserved)
        { Text += FString::Printf(TEXT("%s "), Get_HealthName(Health)); }

        return Text.TrimEnd();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_BuildStatus_PointAndBoxStatusesOverBuiltUnbuiltAndOutside,
    "CkTests.UnitTests.CkGroundNav.Query.BuildStatus_PointAndBoxStatusesOverBuiltUnbuiltAndOutside",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_BuildStatus_PointAndBoxStatusesOverBuiltUnbuiltAndOutside::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_buildstatus;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto OverTheTakenTile = FVector{1200.0, 1200.0, kGroundZ};
    const auto OverABuiltTile = FVector{400.0, 400.0, kGroundZ};
    const auto FarAway = FVector{-5000.0, -5000.0, kGroundZ};

    const auto TakenTile = Do_MakeTileUnbuiltAt(Field, OverTheTakenTile);

    if (NOT TestTrue(TEXT("one tile can be taken away"), TakenTile != INDEX_NONE))
    { return false; }

    if (NOT TestTrue(TEXT("leaving the rest of the field built"), Field.Get_BuiltTileCount() > 0))
    { return false; }

    TestEqual(TEXT("a point over a tile that baked reads Built"),
        Get_RegionStatusAt(Field, OverABuiltTile), ECk_GroundNav_RegionStatus::Built);

    TestEqual(TEXT("a point over the tile that was taken away reads Unbuilt"),
        Get_RegionStatusAt(Field, OverTheTakenTile), ECk_GroundNav_RegionStatus::Unbuilt);

    // Ground no tile covers is a different thing from ground no tile has baked yet, and only the
    // second is worth waiting for.
    TestEqual(TEXT("and a point no tile covers reads OutsideField, never Unbuilt"),
        Get_RegionStatusAt(Field, FarAway), ECk_GroundNav_RegionStatus::OutsideField);

    TestEqual(TEXT("a box wholly inside one built tile reads Built"),
        Get_RegionStatusWithin(Field, Make_RegionXY(100.0, 100.0, 300.0, 300.0)),
        ECk_GroundNav_RegionStatus::Built);

    // Straddles the middle of the field, so it touches all four tiles and only one of them is gone.
    TestEqual(TEXT("a box touching both built and unbuilt tiles reads PartiallyBuilt"),
        Get_RegionStatusWithin(Field, Make_RegionXY(700.0, 700.0, 900.0, 900.0)),
        ECk_GroundNav_RegionStatus::PartiallyBuilt);

    TestEqual(TEXT("a box touching only the tile that was taken away reads Unbuilt"),
        Get_RegionStatusWithin(Field, Make_RegionXY(900.0, 900.0, 1500.0, 1500.0)),
        ECk_GroundNav_RegionStatus::Unbuilt);

    TestEqual(TEXT("and a box reaching no tile at all reads OutsideField"),
        Get_RegionStatusWithin(Field, Make_RegionXY(-5000.0, -5000.0, -4000.0, -4000.0)),
        ECk_GroundNav_RegionStatus::OutsideField);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_BuildStatus_SurfaceBoundsCoverBuiltTilesOnly,
    "CkTests.UnitTests.CkGroundNav.Query.BuildStatus_SurfaceBoundsCoverBuiltTilesOnly",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_BuildStatus_SurfaceBoundsCoverBuiltTilesOnly::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_buildstatus;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Expected = Field._Params.Get_Bounds();
    const auto Bounds = Get_SurfaceBounds(Field);

    if (NOT TestTrue(TEXT("a field with every tile built has bounds to report"), Bounds.IsValid != 0))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("covering the whole tile lattice in XY over the field's vertical slab (%s against %s)"),
        *Bounds.ToString(), *Expected.ToString()),
        Bounds.Min.Equals(Expected.Min, kBoundsTolerance) &&
        Bounds.Max.Equals(Expected.Max, kBoundsTolerance));

    // A consumer fitting a view to these has to be told there is nothing to fit, rather than handed
    // the authored extent as if it held ground.
    Do_MakeEveryTileUnbuilt(Field);

    TestTrue(TEXT("and a field with nothing built reports no bounds at all"),
        Get_SurfaceBounds(Field).IsValid == 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_BuildStatus_ProviderHealthTruthTable,
    "CkTests.UnitTests.CkGroundNav.Query.BuildStatus_ProviderHealthTruthTable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_BuildStatus_ProviderHealthTruthTable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_buildstatus;

    auto Baked = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(*Baked)))
    { return false; }

    auto Publisher = FCk_GroundNav_FieldPublisher{};
    Publisher.Request_Publish(Baked);

    const auto Published = Publisher.Get_Published();

    if (NOT TestTrue(TEXT("and publishes"), Published.IsValid()))
    { return false; }

    const auto Nothing = FCk_GroundNav_FieldPtr{};

    TestEqual(TEXT("nothing published and nothing tried is NoData"),
        Get_ProviderHealth(Nothing, ECk_GroundNav_BuildStatus::Unbuilt, false),
        ECk_NavSurface_ProviderHealth::NoData);

    TestEqual(TEXT("nothing published after a build that failed is Error"),
        Get_ProviderHealth(Nothing, ECk_GroundNav_BuildStatus::Failed, false),
        ECk_NavSurface_ProviderHealth::Error);

    TestEqual(TEXT("a field published with nothing running is Ready"),
        Get_ProviderHealth(Published, ECk_GroundNav_BuildStatus::Built, false),
        ECk_NavSurface_ProviderHealth::Ready);

    // In flight outranks everything else, published or not: the answer is about to change.
    TestEqual(TEXT("a build in flight is Building even with a field already published"),
        Get_ProviderHealth(Published, ECk_GroundNav_BuildStatus::Built, true),
        ECk_NavSurface_ProviderHealth::Building);

    TestEqual(TEXT("and a build in flight with nothing published yet is Building too"),
        Get_ProviderHealth(Nothing, ECk_GroundNav_BuildStatus::Unbuilt, true),
        ECk_NavSurface_ProviderHealth::Building);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_BuildStatus_VolumeViewPromotesUnbuiltToBuildingWhileInFlight,
    "CkTests.UnitTests.CkGroundNav.Query.BuildStatus_VolumeViewPromotesUnbuiltToBuildingWhileInFlight",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_BuildStatus_VolumeViewPromotesUnbuiltToBuildingWhileInFlight::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_buildstatus;

    const auto VolumeBounds = Make_QueryParams().Get_Bounds();

    const auto Inside = FVector{400.0, 400.0, kGroundZ};
    const auto Outside = FVector{-5000.0, -5000.0, kGroundZ};

    const auto Nothing = FCk_GroundNav_FieldPtr{};

    // Before anything is published the volume's own bounds are the only thing that can answer, and
    // ground it covers is worth waiting for where ground it does not cover never will be.
    TestEqual(TEXT("inside a volume with nothing published and nothing running is Unbuilt"),
        Get_RegionStatusAt_ForVolume(Nothing, VolumeBounds, false, Inside),
        ECk_GroundNav_RegionStatus::Unbuilt);

    TestEqual(TEXT("the same point with a build running is Building"),
        Get_RegionStatusAt_ForVolume(Nothing, VolumeBounds, true, Inside),
        ECk_GroundNav_RegionStatus::Building);

    TestEqual(TEXT("outside the volume it is OutsideField while idle"),
        Get_RegionStatusAt_ForVolume(Nothing, VolumeBounds, false, Outside),
        ECk_GroundNav_RegionStatus::OutsideField);

    // A running build does not extend the volume, so this must not be promoted along with the rest.
    TestEqual(TEXT("and OutsideField while a build runs, because a build cannot reach ground the volume does not cover"),
        Get_RegionStatusAt_ForVolume(Nothing, VolumeBounds, true, Outside),
        ECk_GroundNav_RegionStatus::OutsideField);

    auto Baked = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(*Baked)))
    { return false; }

    const auto OverTheTakenTile = FVector{1200.0, 1200.0, kGroundZ};

    if (NOT TestTrue(TEXT("one tile can be taken away"),
        Do_MakeTileUnbuiltAt(*Baked, OverTheTakenTile) != INDEX_NONE))
    { return false; }

    auto Publisher = FCk_GroundNav_FieldPublisher{};
    Publisher.Request_Publish(Baked);

    const auto Published = Publisher.Get_Published();

    TestEqual(TEXT("over a published field, a tile that has not baked reads Unbuilt while idle"),
        Get_RegionStatusAt_ForVolume(Published, VolumeBounds, false, OverTheTakenTile),
        ECk_GroundNav_RegionStatus::Unbuilt);

    TestEqual(TEXT("and Building once a build is running"),
        Get_RegionStatusAt_ForVolume(Published, VolumeBounds, true, OverTheTakenTile),
        ECk_GroundNav_RegionStatus::Building);

    // Only Unbuilt is promoted. Ground that IS built stays built, because a running build does not
    // make a published answer any less true.
    TestEqual(TEXT("a tile that did bake stays Built while idle"),
        Get_RegionStatusAt_ForVolume(Published, VolumeBounds, false, Inside),
        ECk_GroundNav_RegionStatus::Built);

    TestEqual(TEXT("and stays Built while a build runs"),
        Get_RegionStatusAt_ForVolume(Published, VolumeBounds, true, Inside),
        ECk_GroundNav_RegionStatus::Built);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_BuildStatus_SlicedBuildTransitionsOnceAndPublishesAtomically,
    "CkTests.UnitTests.CkGroundNav.Query.BuildStatus_SlicedBuildTransitionsOnceAndPublishesAtomically",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_BuildStatus_SlicedBuildTransitionsOnceAndPublishesAtomically::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_buildstatus;

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_QueryScene()};

    auto State = FCk_GroundNav_FieldBuildState{};
    auto Publisher = FCk_GroundNav_FieldPublisher{};

    auto Observed = TArray<ECk_NavSurface_ProviderHealth>{};

    Do_RecordHealth(Observed, Get_ProviderHealth(Publisher.Get_Published(), State._Status, false));

    if (NOT TestTrue(TEXT("the build begins"),
        Request_BeginBuild(Make_QueryParams(), Publisher.Get_NextEpoch(), State).Get_IsCompleted()))
    { return false; }

    Do_RecordHealth(Observed, Get_ProviderHealth(Publisher.Get_Published(), State._Status, true));

    // A budget of one probe forces the smallest slice the builder allows, which is one tile.
    auto SliceCount = 0;
    auto Completed = false;

    while (SliceCount < kMaxSlices)
    {
        const auto Result = Request_AdvanceBuild(Backend, 1, State);
        ++SliceCount;

        Do_RecordHealth(Observed, Get_ProviderHealth(Publisher.Get_Published(), State._Status, true));

        if (Result.Get_Status() == ECk_GroundNav_BakeStatus::BudgetExhausted)
        {
            // A field reachable mid-build reads exactly like a world whose missing tiles have no
            // floor, and every query against it would be answered confidently and wrongly.
            if (Get_CompletedField(State) != nullptr)
            {
                AddError(FString::Printf(
                    TEXT("slice %d exposed a field before the build finished"), SliceCount));
                return false;
            }

            if (Publisher.Get_HasPublished())
            {
                AddError(FString::Printf(
                    TEXT("slice %d published before the build finished"), SliceCount));
                return false;
            }

            continue;
        }

        Completed = Result.Get_IsCompleted();
        break;
    }

    if (NOT TestTrue(FString::Printf(TEXT("the sliced build completes (took %d slices)"), SliceCount), Completed))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("in more than one slice (took %d)"), SliceCount), SliceCount > 1))
    { return false; }

    auto Released = Request_ReleaseCompletedField(State);

    if (NOT TestTrue(TEXT("and yields a field to publish"), Released.IsValid()))
    { return false; }

    Publisher.Request_Publish(Released.ToSharedRef());

    Do_RecordHealth(Observed, Get_ProviderHealth(Publisher.Get_Published(), Publisher.Get_Status(), false));

    const auto Sequence = Get_HealthSequenceText(Observed);

    ck::groundnav::Display(TEXT("{}"), FString::Printf(
        TEXT("sliced build over %d slices reported health: %s"), SliceCount, *Sequence));

    TestEqual(FString::Printf(
        TEXT("the health a consumer saw moved through exactly three states [%s]"), *Sequence),
        Observed.Num(), 3);

    if (Observed.Num() == 3)
    {
        TestEqual(FString::Printf(TEXT("starting with nothing to answer from [%s]"), *Sequence),
            Observed[0], ECk_NavSurface_ProviderHealth::NoData);

        TestEqual(FString::Printf(TEXT("then Building for the whole build, entered once [%s]"), *Sequence),
            Observed[1], ECk_NavSurface_ProviderHealth::Building);

        TestEqual(FString::Printf(TEXT("then Ready once, when the whole field arrived at once [%s]"), *Sequence),
            Observed[2], ECk_NavSurface_ProviderHealth::Ready);
    }

    const auto* PublishedField = Publisher.Get_Published().Get();

    if (NOT TestTrue(TEXT("the published field is readable"), PublishedField != nullptr))
    { return false; }

    auto UnbuiltTileCount = 0;

    for (auto TileIndex = 0; TileIndex < PublishedField->Get_TileCount(); ++TileIndex)
    {
        if (Get_RegionStatusAt(*PublishedField, Get_TileCentre(*PublishedField, TileIndex)) ==
            ECk_GroundNav_RegionStatus::Built)
        { continue; }

        ++UnbuiltTileCount;
    }

    TestEqual(TEXT("and every tile of it reads Built, because a sliced publish is still one publish"),
        UnbuiltTileCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
