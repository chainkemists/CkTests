// Unit tests for the mesh-collision -> Ck shape derivation.
//
// Exercises the CORE (ck::shapes::Derive_FromCollision) rather than the UStaticMesh wrapper: a
// transient UStaticMesh reports zero-extent GetBounds(), so the VisualBounds tier's values are not
// assertable through the mesh path. A transient UBodySetup is a complete fixture for everything else.

#include "CkShapes/CkShapes_Common.h"
#include "CkShapes/CkShapes_Utils.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>
#include <PhysicsEngine/BodySetup.h>
#include <PhysicsEngine/BoxElem.h>
#include <PhysicsEngine/SphereElem.h>
#include <PhysicsEngine/SphylElem.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_shapes_from_mesh
{
    // Deliberately asymmetric, so a fallback result is distinguishable from a real derivation.
    inline auto Get_DummyVisualBounds() -> FBoxSphereBounds
    {
        return FBoxSphereBounds{FVector{7.0, 8.0, 9.0}, FVector{70.0, 80.0, 90.0}, 130.0};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_SingleBox_IsExactAndHalved,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.SingleBox_IsExactAndHalved",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_SingleBox_IsExactAndHalved::RunTest(const FString& Parameters)
{
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 80.0f, 40.0f);
    BodySetup->AggGeom.BoxElems[0].Center = FVector{1.0, 2.0, 3.0};

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector::OneVector);

    TestEqual(TEXT("Single box is Exact"), Result.Get_Fidelity(), ECk_Shape_FromMeshFidelity::Exact);
    TestEqual(TEXT("Shape type is Box"), Result.Get_Shape().Get_ShapeType(), ECk_Shape_Type::Box);

    // FKBoxElem X/Y/Z are FULL extents; the probe wants half.
    const auto HalfExtents = Result.Get_Shape().Get_Box().Get_HalfExtents();
    TestTrue(TEXT("X is half the full extent"), FMath::IsNearlyEqual(HalfExtents.X, 50.0));
    TestTrue(TEXT("Y is half the full extent"), FMath::IsNearlyEqual(HalfExtents.Y, 40.0));
    TestTrue(TEXT("Z is half the full extent"), FMath::IsNearlyEqual(HalfExtents.Z, 20.0));

    TestTrue(TEXT("Offset carries the element centre"),
        Result.Get_LocalOffset().GetLocation().Equals(FVector{1.0, 2.0, 3.0}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_MirroredScale_StaysPositive,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.MirroredScale_StaysPositive",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_MirroredScale_StaysPositive::RunTest(const FString& Parameters)
{
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 80.0f, 40.0f);

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{-2.0, 1.0, 1.0});

    const auto HalfExtents = Result.Get_Shape().Get_Box().Get_HalfExtents();
    TestTrue(TEXT("A mirrored scale never yields a negative half extent"),
        HalfExtents.X > 0.0 && HalfExtents.Y > 0.0 && HalfExtents.Z > 0.0);
    TestTrue(TEXT("Magnitude follows the absolute scale"), FMath::IsNearlyEqual(HalfExtents.X, 100.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_SingleSphere_UsesMinScale,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.SingleSphere_UsesMinScale",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_SingleSphere_UsesMinScale::RunTest(const FString& Parameters)
{
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.SphereElems.Emplace(50.0f);

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{3.0, 2.0, 4.0});

    TestEqual(TEXT("Shape type is Sphere"), Result.Get_Shape().Get_ShapeType(), ECk_Shape_Type::Sphere);

    // The engine scales a sphere by the MINIMUM absolute scale component, not the maximum. Pinned
    // here so a "use MaxAbs" regression cannot pass silently.
    TestTrue(TEXT("Sphere radius follows the minimum absolute scale"),
        FMath::IsNearlyEqual(Result.Get_Shape().Get_Sphere().Get_Radius(), 100.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_SingleSphyl_HalfHeightIsCylinderSegment,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.SingleSphyl_HalfHeightIsCylinderSegment",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_SingleSphyl_HalfHeightIsCylinderSegment::RunTest(const FString& Parameters)
{
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.SphylElems.Emplace(20.0f, 60.0f);

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector::OneVector);

    TestEqual(TEXT("Shape type is Capsule"), Result.Get_Shape().Get_ShapeType(), ECk_Shape_Type::Capsule);

    const auto Capsule = Result.Get_Shape().Get_Capsule();
    TestTrue(TEXT("Radius round-trips"), FMath::IsNearlyEqual(Capsule.Get_Radius(), 20.0f));

    // Ck/Jolt HalfHeight is half the CYLINDER SEGMENT, not half the total capsule length.
    TestTrue(TEXT("HalfHeight is half the cylinder segment"),
        FMath::IsNearlyEqual(Capsule.Get_HalfHeight(), 30.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_ConvexElem_FallsBackToVisualBounds,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.ConvexElem_FallsBackToVisualBounds",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_ConvexElem_FallsBackToVisualBounds::RunTest(const FString& Parameters)
{
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.ConvexElems.AddDefaulted();

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector::OneVector);

    TestEqual(TEXT("Convex collision degrades to VisualBounds"),
        Result.Get_Fidelity(), ECk_Shape_FromMeshFidelity::VisualBounds);
    TestTrue(TEXT("Fallback uses the render bounds extent"),
        Result.Get_Shape().Get_Box().Get_HalfExtents().Equals(FVector{70.0, 80.0, 90.0}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_ComplexAsSimple_BeatsBoxElems,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.ComplexAsSimple_BeatsBoxElems",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_ComplexAsSimple_BeatsBoxElems::RunTest(const FString& Parameters)
{
    // A mesh may carry BOTH a box primitive and the complex-as-simple flag. The Jolt bake resolves
    // the flag first and uses the tri-mesh, so this must agree, or the click target would disagree
    // with what physics actually collides against.
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->CollisionTraceFlag = ECollisionTraceFlag::CTF_UseComplexAsSimple;
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 80.0f, 40.0f);

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector::OneVector);

    TestEqual(TEXT("Trace flag is honoured ahead of AggGeom"),
        Result.Get_Fidelity(), ECk_Shape_FromMeshFidelity::VisualBounds);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_TwoPrimitives_UnionAABox,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.TwoPrimitives_UnionAABox",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_TwoPrimitives_UnionAABox::RunTest(const FString& Parameters)
{
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(20.0f, 20.0f, 20.0f);
    BodySetup->AggGeom.BoxElems[0].Center = FVector{-50.0, 0.0, 0.0};
    BodySetup->AggGeom.BoxElems.Emplace(20.0f, 20.0f, 20.0f);
    BodySetup->AggGeom.BoxElems[1].Center = FVector{50.0, 0.0, 0.0};

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector::OneVector);

    TestEqual(TEXT("Two primitives report PrimitiveUnion"),
        Result.Get_Fidelity(), ECk_Shape_FromMeshFidelity::PrimitiveUnion);

    // Union spans -60..+60 on X, and stays tight at +/-10 on Y.
    const auto HalfExtents = Result.Get_Shape().Get_Box().Get_HalfExtents();
    TestTrue(TEXT("Union spans both boxes on X"), FMath::IsNearlyEqual(HalfExtents.X, 60.0));
    TestTrue(TEXT("Union stays tight on Y"), FMath::IsNearlyEqual(HalfExtents.Y, 10.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_NonUniformSphere_IsNotExact,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.NonUniformSphere_IsNotExact",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_NonUniformSphere_IsNotExact::RunTest(const FString& Parameters)
{
    // A non-uniformly scaled sphere is an ellipsoid, which this vocabulary cannot express. The
    // engine collapses it with MinScaleAbs - an INSCRIBED sphere - so the honest answer is
    // Approximated. Claiming Exact here would hand a caller a click target smaller than the visual
    // with nothing in the log to say so, which is the silent approximation the enum exists to stop.
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.SphereElems.Emplace(50.0f);

    const auto NonUniform = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{3.0, 2.0, 4.0});

    TestEqual(TEXT("A non-uniformly scaled sphere is NOT Exact"),
        NonUniform.Get_Fidelity(), ECk_Shape_FromMeshFidelity::Approximated);
    TestEqual(TEXT("It is still a sphere, not a union"),
        NonUniform.Get_Shape().Get_ShapeType(), ECk_Shape_Type::Sphere);

    const auto Uniform = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{2.0, 2.0, 2.0});

    TestEqual(TEXT("A uniformly scaled sphere IS Exact"),
        Uniform.Get_Fidelity(), ECk_Shape_FromMeshFidelity::Exact);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_RotatedBoxNonUniform_IsNotExact,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.RotatedBoxNonUniform_IsNotExact",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_RotatedBoxNonUniform_IsNotExact::RunTest(const FString& Parameters)
{
    // An axis-aligned box scales exactly component-wise at ANY scale; a rotated one shears under
    // non-uniform scale, and an axis-aligned box cannot express a sheared box.
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 80.0f, 40.0f);
    BodySetup->AggGeom.BoxElems[0].Rotation = FRotator{0.0, 45.0, 0.0};

    const auto Sheared = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{3.0, 1.0, 1.0});

    TestEqual(TEXT("Rotated box under non-uniform scale is Approximated"),
        Sheared.Get_Fidelity(), ECk_Shape_FromMeshFidelity::Approximated);

    const auto Unsheared = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{3.0, 3.0, 3.0});

    TestEqual(TEXT("Rotated box under UNIFORM scale stays Exact"),
        Unsheared.Get_Fidelity(), ECk_Shape_FromMeshFidelity::Exact);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_OffsetIsUnscaled,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.OffsetIsUnscaled",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_OffsetIsUnscaled::RunTest(const FString& Parameters)
{
    // Dimensions carry the scale (a probe has none of its own); the OFFSET deliberately does not,
    // because the usual consumer composes it under a node that already applies the mesh scale.
    // Baking it into both is the double-application this pins against.
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 80.0f, 40.0f);
    BodySetup->AggGeom.BoxElems[0].Center = FVector{10.0, 20.0, 30.0};

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{2.0, 3.0, 4.0});

    TestTrue(TEXT("Dimensions ARE scaled"),
        Result.Get_Shape().Get_Box().Get_HalfExtents().Equals(FVector{100.0, 120.0, 80.0}));
    TestTrue(TEXT("Offset is NOT scaled"),
        Result.Get_LocalOffset().GetLocation().Equals(FVector{10.0, 20.0, 30.0}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ShapeFromMesh_UnionRespectsNonUniformScale,
    "CkTests.UnitTests.CkShapes.ShapeFromMeshCollision.UnionRespectsNonUniformScale",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_ShapeFromMesh_UnionRespectsNonUniformScale::RunTest(const FString& Parameters)
{
    // FKAggregateGeom::CalcAABB collapses a non-uniform scale to ONE min-absolute scalar
    // (SelectMinScale) and applies it to every element, which under-scales every axis but the
    // smallest. Two 20-unit boxes at X=+/-50, scaled (4,1,1), must span 4*(50+10) = 240 on X.
    // Routing through CalcAABB would give 60 - a click target 4x too narrow on a scaled rig piece.
    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(20.0f, 20.0f, 20.0f);
    BodySetup->AggGeom.BoxElems[0].Center = FVector{-50.0, 0.0, 0.0};
    BodySetup->AggGeom.BoxElems.Emplace(20.0f, 20.0f, 20.0f);
    BodySetup->AggGeom.BoxElems[1].Center = FVector{50.0, 0.0, 0.0};

    const auto Result = ck::shapes::Derive_FromCollision(
        BodySetup, ck_test_shapes_from_mesh::Get_DummyVisualBounds(), FVector{4.0, 1.0, 1.0});

    TestEqual(TEXT("Still reports PrimitiveUnion"),
        Result.Get_Fidelity(), ECk_Shape_FromMeshFidelity::PrimitiveUnion);

    const auto HalfExtents = Result.Get_Shape().Get_Box().Get_HalfExtents();
    TestTrue(TEXT("X follows the X scale, not the minimum component"),
        FMath::IsNearlyEqual(HalfExtents.X, 240.0));
    TestTrue(TEXT("Y is untouched by the X scale"),
        FMath::IsNearlyEqual(HalfExtents.Y, 10.0));

    return true;
}
