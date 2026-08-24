#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"
#include "CkJolt/StaticWorld/CkJoltMeshShape_Utils.h"

#include <PhysicsEngine/BodySetup.h>

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>

// --------------------------------------------------------------------------------------------------------------------
// Locks the per-mesh pre-bake library's PURE pieces:
//
//   - The path convention (/Game mirror under <Root>/Meshes, non-/Game roots yield empty).
//   - Get_IsWorthPreBaking: hulls and tri-meshes qualify, pure primitives do not — the cooker's
//     skip rule and the runtime miss-loudness rule share this function so they can never disagree.
//   - TryWrap_AtScale: identity returns the shape unwrapped; a valid uniform scale wraps and the
//     wrapped shape raycasts EXACTLY like a shape built with the scale baked into the geometry
//     (the parity that makes the cooked path a pure optimization); a scale the topology rejects
//     (non-uniform on a sphere) returns null so callers fall back to the baked-in build; negative
//     scale returns null (mirroring stays with the build path).
//
// TryGet_ScaleOneShape's asset plumbing (LoadObject by convention, staleness ensures) needs saved
// assets and is exercised by the cooker path — not unit-testable without writable content.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_mesh_shape_utils
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    // Down-ray in shape space; returns the hit fraction or -1.
    static auto CastDownAt(const JPH::Shape& InShape, double InX, double InY, double InStartZ) -> float
    {
        const auto Ray = JPH::RayCast{
            JPH::Vec3(static_cast<float>(InX), static_cast<float>(InY), static_cast<float>(InStartZ)),
            JPH::Vec3(0.0f, 0.0f, -2.0f * static_cast<float>(InStartZ))};

        auto Hit = JPH::RayCastResult{};
        if (NOT InShape.CastRay(Ray, JPH::SubShapeIDCreator{}, Hit))
        { return -1.0f; }

        return Hit.mFraction;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltMeshShape_Utils,
    "Ck.Jolt.MeshShape.Utils",
    ck_test_jolt_mesh_shape_utils::kTestFlags)

bool FCkTest_JoltMeshShape_Utils::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_mesh_shape_utils;

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    // ---- Path convention -----------------------------------------------------------------------------
    {
        TestEqual(TEXT("path: /Game mesh maps under <Root>/Meshes"),
            mesh_shape_utils::Get_CookedMeshShapeAssetPath(TEXT("/Game/CkJoltData"), TEXT("/Game/Props/SM_Crate")),
            FString{TEXT("/Game/CkJoltData/Meshes/Props/SM_Crate_JoltShape.SM_Crate_JoltShape")});

        TestTrue(TEXT("path: /Engine mesh yields empty (never pre-baked)"),
            mesh_shape_utils::Get_CookedMeshShapeAssetPath(TEXT("/Game/CkJoltData"), TEXT("/Engine/BasicShapes/Cube")).IsEmpty());
    }

    // ---- Worth-pre-baking rule -----------------------------------------------------------------------
    {
        auto* ConvexSetup = NewObject<UBodySetup>(GetTransientPackage());
        auto& ConvexElem = ConvexSetup->AggGeom.ConvexElems.Emplace_GetRef();
        ConvexElem.VertexData = {
            FVector{-50, -50, -50}, FVector{50, -50, -50}, FVector{-50, 50, -50}, FVector{50, 50, -50},
            FVector{-50, -50, 50}, FVector{50, -50, 50}, FVector{-50, 50, 50}, FVector{50, 50, 50}};
        ConvexElem.UpdateElemBox();

        auto* BoxOnlySetup = NewObject<UBodySetup>(GetTransientPackage());
        auto& BoxElem = BoxOnlySetup->AggGeom.BoxElems.Emplace_GetRef();
        BoxElem.X = 100.0f; BoxElem.Y = 100.0f; BoxElem.Z = 100.0f;

        TestTrue(TEXT("worth-baking: convex hull qualifies"),
            mesh_shape_utils::Get_IsWorthPreBaking(*ConvexSetup));
        TestFalse(TEXT("worth-baking: pure-primitive box does not"),
            mesh_shape_utils::Get_IsWorthPreBaking(*BoxOnlySetup));

        // ---- Scale-wrap parity (uses the convex setup — the shape class the pre-bake exists for) ----
        const auto ScaleOne = BuildShape_FromBodySetup(*ConvexSetup, FVector::OneVector, TEXT("ScaleOneConvex"));
        if (NOT TestNotNull(TEXT("scale-1 convex builds"), ScaleOne.GetPtr()))
        { return false; }

        TestTrue(TEXT("wrap: identity scale returns the shape itself, unwrapped"),
            mesh_shape_utils::TryWrap_AtScale(ScaleOne, FVector::OneVector, TEXT("Identity")).GetPtr() == ScaleOne.GetPtr());

        constexpr auto Scale = 2.0;
        const auto Wrapped = mesh_shape_utils::TryWrap_AtScale(ScaleOne, FVector{Scale}, TEXT("Uniform2"));
        const auto BakedIn = BuildShape_FromBodySetup(*ConvexSetup, FVector{Scale}, TEXT("BakedIn2"));

        if (NOT TestNotNull(TEXT("wrap: uniform scale wraps"), Wrapped.GetPtr()) ||
            NOT TestNotNull(TEXT("baked-in comparison shape builds"), BakedIn.GetPtr()))
        { return false; }

        // Probe points chosen to hit the top face and to miss just outside the scaled extent.
        const auto WrappedHit = CastDownAt(*Wrapped, 0.0, 0.0, 500.0);
        const auto BakedInHit = CastDownAt(*BakedIn, 0.0, 0.0, 500.0);

        TestTrue(TEXT("parity: both hit the scaled hull"), WrappedHit >= 0.0f && BakedInHit >= 0.0f);
        TestTrue(TEXT("parity: hit fractions agree within 1e-4"),
            FMath::Abs(WrappedHit - BakedInHit) <= 1e-4f);

        TestTrue(TEXT("parity: outside the scaled extent both miss"),
            CastDownAt(*Wrapped, 120.0, 0.0, 500.0) < 0.0f && CastDownAt(*BakedIn, 120.0, 0.0, 500.0) < 0.0f);

        // ---- Rejection paths ----
        TestNull(TEXT("wrap: negative scale returns null (mirroring stays with the build path)"),
            mesh_shape_utils::TryWrap_AtScale(ScaleOne, FVector{-1.0, 1.0, 1.0}, TEXT("Mirrored")).GetPtr());

        auto* SphereSetup = NewObject<UBodySetup>(GetTransientPackage());
        auto& SphereElem = SphereSetup->AggGeom.SphereElems.Emplace_GetRef();
        SphereElem.Radius = 50.0f;

        const auto SphereScaleOne = BuildShape_FromBodySetup(*SphereSetup, FVector::OneVector, TEXT("Sphere"));
        if (NOT TestNotNull(TEXT("scale-1 sphere builds"), SphereScaleOne.GetPtr()))
        { return false; }

        TestNull(TEXT("wrap: non-uniform scale on a sphere returns null (topology rejects it)"),
            mesh_shape_utils::TryWrap_AtScale(SphereScaleOne, FVector{1.0, 2.0, 3.0}, TEXT("NonUniformSphere")).GetPtr());
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
