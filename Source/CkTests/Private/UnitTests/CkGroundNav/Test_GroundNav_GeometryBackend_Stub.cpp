// The geometry backend seam, driven entirely by a hand-authored box list.
//
// Geometry reaches the bake with NO world, NO registry and NO physics. Every bake stage is math over
// what these calls return, so if this substrate needed a world, every bake test would inherit that
// weight.
//
// The stub is exact AABB-vs-AABB and FBox::Intersect counts a shared face as an intersection, so the
// fixtures below deliberately either clearly straddle or clearly clear the query bounds. A fixture
// that touched them exactly would be asserting a tie-break rather than the behaviour under test.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_backend
{
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;

    auto Make_Floor() -> FBox
    {
        return FBox{FVector{0.0, 0.0, 0.0}, FVector{1000.0, 1000.0, 10.0}};
    }

    auto Make_FarAwayBox() -> FBox
    {
        return FBox{FVector{50000.0, 50000.0, 0.0}, FVector{50100.0, 50100.0, 10.0}};
    }

    auto Make_QueryBounds() -> FBox
    {
        return FBox{FVector{-100.0, -100.0, -100.0}, FVector{1100.0, 1100.0, 300.0}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Backend_EmptyWorldIsEmptyNotInvalid,
    "CkTests.UnitTests.CkGroundNav.Bake.Backend_EmptyWorldIsEmptyNotInvalid",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Backend_EmptyWorldIsEmptyNotInvalid::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_backend;

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{};

    // A backend with nothing in it is VALID and empty. That distinction is load-bearing: "valid but
    // empty" bakes as free space, while "invalid" must bake as Unbuilt, and conflating them is exactly
    // how a hole becomes indistinguishable from a floor.
    TestTrue(TEXT("a stub over an empty box list is still a valid backend"),
        Backend.Get_IsValid());

    TestFalse(TEXT("an empty world reports no geometry in bounds"),
        Backend.Get_HasGeometryInBounds(Make_QueryBounds()));

    auto Bodies = TArray<ck::groundnav::FCk_GroundNav_BodyRef>{};
    TestEqual(TEXT("an empty world enumerates zero bodies"),
        Backend.Get_StaticBodiesInBounds(Make_QueryBounds(), Bodies), 0);

    auto Batch = FCk_GroundNav_GeometryBatch{};
    TestEqual(TEXT("an empty world yields zero triangles"),
        Backend.Get_TrianglesInBounds(Make_QueryBounds(), Batch), 0);

    TestTrue(TEXT("and the batch is left empty"), Batch.Get_IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Backend_BoxListReachesTheBake,
    "CkTests.UnitTests.CkGroundNav.Bake.Backend_BoxListReachesTheBake",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Backend_BoxListReachesTheBake::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_backend;

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{Make_Floor()}};

    TestTrue(TEXT("the floor is found in bounds"),
        Backend.Get_HasGeometryInBounds(Make_QueryBounds()));

    auto Bodies = TArray<ck::groundnav::FCk_GroundNav_BodyRef>{};
    TestEqual(TEXT("one box enumerates as one body"),
        Backend.Get_StaticBodiesInBounds(Make_QueryBounds(), Bodies), 1);

    TestTrue(TEXT("and its ref is not the never-a-body sentinel"),
        Bodies.Num() == 1 && Bodies[0].Get_IsValid());

    auto Batch = FCk_GroundNav_GeometryBatch{};
    const auto TriangleCount = Backend.Get_TrianglesInBounds(Make_QueryBounds(), Batch);

    // A box is six quads, each two triangles.
    TestEqual(TEXT("one box yields exactly 12 triangles"), TriangleCount, 12);
    TestEqual(TEXT("and the batch agrees with the returned count"),
        Batch.Get_TriangleCount(), 12);
    TestEqual(TEXT("with three indices per triangle"), Batch._Indices.Num(), 36);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Backend_OutOfBoundsGeometryIsExcluded,
    "CkTests.UnitTests.CkGroundNav.Bake.Backend_OutOfBoundsGeometryIsExcluded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Backend_OutOfBoundsGeometryIsExcluded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_backend;

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
        TArray<FBox>{Make_Floor(), Make_FarAwayBox()}};

    auto Bodies = TArray<ck::groundnav::FCk_GroundNav_BodyRef>{};
    TestEqual(TEXT("only the overlapping box enumerates"),
        Backend.Get_StaticBodiesInBounds(Make_QueryBounds(), Bodies), 1);

    auto Batch = FCk_GroundNav_GeometryBatch{};
    TestEqual(TEXT("and only its triangles are collected"),
        Backend.Get_TrianglesInBounds(Make_QueryBounds(), Batch), 12);

    // The far box IS reachable — through bounds that contain it. This proves the exclusion above was
    // a bounds decision and not the fixture silently failing to exist.
    auto FarBatch = FCk_GroundNav_GeometryBatch{};
    TestEqual(TEXT("the far box is collected when the bounds reach it"),
        Backend.Get_TrianglesInBounds(Make_FarAwayBox().ExpandBy(10.0), FarBatch), 12);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Backend_CollectionAppendsAndIsRebased,
    "CkTests.UnitTests.CkGroundNav.Bake.Backend_CollectionAppendsAndIsRebased",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Backend_CollectionAppendsAndIsRebased::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_backend;

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{Make_Floor()}};

    // Collection APPENDS, so a caller may accumulate several regions into one batch. If the second
    // append failed to rebase its indices onto the vertices already present, the triangles would read
    // back as the first region's geometry — silently duplicating a floor instead of adding one.
    auto Batch = FCk_GroundNav_GeometryBatch{};
    Backend.Get_TrianglesInBounds(Make_QueryBounds(), Batch);
    Backend.Get_TrianglesInBounds(Make_QueryBounds(), Batch);

    TestEqual(TEXT("two collections accumulate"), Batch.Get_TriangleCount(), 24);

    for (const auto& Index : Batch._Indices)
    {
        if (Batch._Vertices.IsValidIndex(Index))
        { continue; }

        AddError(FString::Printf(TEXT("index %d is out of range for %d vertices — indices were not rebased"),
            Index, Batch._Vertices.Num()));
        break;
    }

    // The top face of the floor sits at its max Z, and the winding is authored so the top face exists
    // as two triangles all of whose corners are at that height.
    const auto TopZ = Make_Floor().Max.Z;
    auto TopTriangleCount = 0;

    for (auto TriangleIndex = 0; TriangleIndex < Batch.Get_TriangleCount(); ++TriangleIndex)
    {
        auto A = FVector::ZeroVector;
        auto B = FVector::ZeroVector;
        auto C = FVector::ZeroVector;
        Batch.Get_Triangle(TriangleIndex, A, B, C);

        if (FMath::IsNearlyEqual(A.Z, TopZ) && FMath::IsNearlyEqual(B.Z, TopZ) && FMath::IsNearlyEqual(C.Z, TopZ))
        { ++TopTriangleCount; }
    }

    // Two per box, two boxes' worth of appends.
    TestEqual(TEXT("the walkable top face is present as two triangles per collected box"),
        TopTriangleCount, 4);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
