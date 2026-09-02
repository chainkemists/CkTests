// What the field says about the ground at a surface, and what it refuses to say.
//
// Two halves. The normal is DERIVED from the plate's own heights rather than stored, so it is pinned
// against ground whose plane is known by construction: flat floor answers exactly up, and a ramp
// authored at a known angle answers that angle. The refusals matter as much — a reference the field
// does not have must answer NoSurface rather than a default attribute set, because a caller handed
// silent defaults reads an up normal and a cost of one for ground that is not there and cannot tell.

#include "CkGroundNav/Query/CkGroundNav_QueryCore.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Attributes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_attributes
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_SurfaceAttributes;
    using ck::groundnav::FCk_GroundNav_SurfaceRef;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_SurfaceAttributes;
    using ck::groundnav::Get_SurfaceAttributesAt;
    using ck::groundnav::Get_SurfaceAttributesAt_Batch;

    constexpr auto kNormalTolerance = 1.0e-3;

    // The plate is planar only within the merge tolerance, and the normal is recovered from cell
    // heights rather than from the authored plane, so the ramp assertion is stated in degrees.
    constexpr auto kRampNormalToleranceDegrees = 3.0;

    constexpr auto kBatchPointCount = 500;
    constexpr auto kBatchSeed = 991733;

    auto Make_ColumnQuery(
        const FVector& InLocation,
        float          InTolerance,
        float          InRadius) -> FCk_GroundNav_IsNavigableQuery
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = InTolerance;
        Query._Agent._RadiusUu = InRadius;

        return Query;
    }

    auto Make_MixedColumnQuery(const FVector& InLocation, int32 InIndex) -> FCk_GroundNav_IsNavigableQuery
    {
        constexpr float Tolerances[] = {0.0f, 25.0f, 100.0f, 250.0f};
        constexpr float Radii[] = {0.0f, 20.0f, 60.0f, 120.0f};

        return Make_ColumnQuery(InLocation, Tolerances[InIndex % 4], Radii[(InIndex + 1) % 4]);
    }

    auto Get_AttributesMatch(
        const FCk_GroundNav_SurfaceAttributes& InLeft,
        const FCk_GroundNav_SurfaceAttributes& InRight) -> bool
    {
        return InLeft._Status == InRight._Status &&
               InLeft._Surface == InRight._Surface &&
               InLeft._SurfaceNormal == InRight._SurfaceNormal &&
               InLeft._CostMultiplier == InRight._CostMultiplier &&
               InLeft._ClearanceUu == InRight._ClearanceUu &&
               InLeft._AreaTags == InRight._AreaTags;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Attributes_FlatPlateReportsUpNormalAndIdentity,
    "CkTests.UnitTests.CkGroundNav.Query.Attributes_FlatPlateReportsUpNormalAndIdentity",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Attributes_FlatPlateReportsUpNormalAndIdentity::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_attributes;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(Field)))
    { return false; }

    const auto Standing = FVector{kFlatProbeX, kFlatProbeY, kGroundZ};
    const auto Query = Make_ColumnQuery(Standing, 100.0f, 0.0f);

    const auto Attributes = Get_SurfaceAttributesAt(Field, Query);

    if (NOT TestEqual(TEXT("flat floor has attributes to report"),
        Attributes._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("its plate is level, so the derived normal is exactly up (%s)"),
        *Attributes._SurfaceNormal.ToString()),
        Attributes._SurfaceNormal.Equals(FVector::UpVector, kNormalTolerance));

    // Attributes-at is defined as the column lookup followed by the attributes of what it found, so
    // the two have to name the same surface or one of them is looking somewhere else.
    const auto Navigable = Get_IsNavigable(Field, Query);

    TestTrue(TEXT("and it names the same surface the column lookup found"),
        Attributes._Surface == Navigable._Surface);

    // Nothing in the bake carries traversal policy yet, so these are the shape of the answer rather
    // than its content — pinned so the day markup arrives, the change is visible here.
    TestEqual(TEXT("with no traversal policy on it, so the cost multiplier is one"),
        Attributes._CostMultiplier, 1.0f);

    TestTrue(TEXT("and no area tags"), Attributes._AreaTags.IsEmpty());

    TestTrue(FString::Printf(TEXT("standing on open floor, it reports room to stand (%.2f)"),
        Attributes._ClearanceUu),
        Attributes._ClearanceUu > 0.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Attributes_RampNormalMatchesAnalytic,
    "CkTests.UnitTests.CkGroundNav.Query.Attributes_RampNormalMatchesAnalytic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Attributes_RampNormalMatchesAnalytic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_attributes;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the ramp scene bakes"), Bake_RampScene(Field)))
    { return false; }

    // Well inside the tile, so the cell has same-plate neighbours on both sides along both axes and
    // the central difference is reading the ramp rather than its edge.
    const auto Interior = FVector{400.0, 400.0, 0.0};

    // The ramp climbs 400 uu across the field, so the query has to reach the whole slab to find it
    // from a point at the field's base height.
    const auto Attributes = Get_SurfaceAttributesAt(Field, Make_ColumnQuery(Interior, 500.0f, 0.0f));

    if (NOT TestEqual(TEXT("the middle of the ramp has attributes to report"),
        Attributes._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto Expected = Get_RampNormal();
    const auto ErrorDegrees = Get_AngleBetweenDegrees(Attributes._SurfaceNormal, Expected);

    TestTrue(FString::Printf(
        TEXT("and the normal recovered from the plate's heights is the %.0f-degree ramp's own, to within %.2f degrees (got %s, expected %s)"),
        kRampAngleDegrees, ErrorDegrees, *Attributes._SurfaceNormal.ToString(), *Expected.ToString()),
        ErrorDegrees <= kRampNormalToleranceDegrees);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Attributes_StaleOrForeignReferenceIsNoSurface,
    "CkTests.UnitTests.CkGroundNav.Query.Attributes_StaleOrForeignReferenceIsNoSurface",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Attributes_StaleOrForeignReferenceIsNoSurface::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_attributes;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto OverTheFarTile = FVector{kFarTileProbeX, kFarTileProbeY, kGroundZ};

    const auto Held = Get_IsNavigable(Field, Make_ColumnQuery(OverTheFarTile, 100.0f, 0.0f));

    if (NOT TestEqual(TEXT("there is ground under the far probe to take a reference to"),
        Held._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    // A plate index the tile does not carry: valid-looking, because a ref only knows it is not the
    // no-plate sentinel, and answerable only by looking.
    auto Foreign = Held._Surface;
    Foreign._PlateIndex = 1000000;

    TestEqual(TEXT("a reference to a plate the field does not have finds no surface"),
        Get_SurfaceAttributes(Field, Foreign)._Status, ECk_NavSurface_QueryStatus::NoSurface);

    TestEqual(TEXT("and a default reference, which names nothing at all, finds no surface either"),
        Get_SurfaceAttributes(Field, FCk_GroundNav_SurfaceRef{})._Status,
        ECk_NavSurface_QueryStatus::NoSurface);

    // The same reference, once the tile it points into is gone. The distinction has to survive being
    // asked through a held reference rather than a position, or a consumer caching refs loses it.
    const auto TakenTile = Do_MakeTileUnbuiltAt(Field, OverTheFarTile);

    if (NOT TestTrue(TEXT("the far probe's tile can be taken away"), TakenTile == Held._Surface._TileIndex))
    { return false; }

    TestEqual(TEXT("a reference into a tile that is no longer built answers Unbuilt, not NoSurface"),
        Get_SurfaceAttributes(Field, Held._Surface)._Status, ECk_NavSurface_QueryStatus::Unbuilt);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Attributes_BatchIsElementWiseIdenticalToSingles,
    "CkTests.UnitTests.CkGroundNav.Query.Attributes_BatchIsElementWiseIdenticalToSingles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Attributes_BatchIsElementWiseIdenticalToSingles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_attributes;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kBatchPointCount, kBatchSeed);

    auto Queries = TArray<FCk_GroundNav_IsNavigableQuery>{};
    Queries.Reserve(Points.Num());

    for (auto Index = 0; Index < Points.Num(); ++Index)
    { Queries.Emplace(Make_MixedColumnQuery(Points[Index], Index)); }

    auto BatchResults = TArray<FCk_GroundNav_SurfaceAttributes>{};
    BatchResults.SetNum(Queries.Num());

    Get_SurfaceAttributesAt_Batch(Field, Queries, BatchResults);

    auto MismatchCount = 0;
    auto FirstMismatch = int32{INDEX_NONE};

    for (auto Index = 0; Index < Queries.Num(); ++Index)
    {
        if (Get_AttributesMatch(Get_SurfaceAttributesAt(Field, Queries[Index]), BatchResults[Index]))
        { continue; }

        ++MismatchCount;

        if (FirstMismatch == INDEX_NONE)
        { FirstMismatch = Index; }
    }

    TestEqual(FString::Printf(
        TEXT("every one of %d batched attribute reads answers exactly as the single call does (first disagreement at %d)"),
        Queries.Num(), FirstMismatch),
        MismatchCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
