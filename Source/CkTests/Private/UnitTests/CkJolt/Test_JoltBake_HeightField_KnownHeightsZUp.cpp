#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include <Misc/AutomationTest.h>

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the heightfield axis math BEFORE any landscape content exists: Jolt heightfields are local
// Y-up graphs over X/Z; CreateHeightFieldShape must land UE-row-major samples on UE's +X/+Y
// quadrant with heights on +Z, via the +90deg-about-X wrap + row flip + local-Z offset.
// An implementation with the row flip missing (or mirrored) reads the WRONG corner heights —
// the asymmetric h(x,y) = 10x + 100y surface catches every axis/mirror mistake distinctly.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_heightfield
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter;

    constexpr int32 SampleCount = 8;
    constexpr double ScaleXY = 100.0;

    // Jolt heightfields quantize sample heights (block compression over the height range) —
    // range here is 0..770uu, so allow a few uu of quantization slack.
    constexpr double HeightTolerance = 5.0;

    static auto Get_ExpectedHeight(int32 InX, int32 InY) -> float
    {
        return 10.0f * InX + 100.0f * InY;
    }

    // Casts straight down in SHAPE space (the shape embeds the axis-correction wrapper, so shape
    // space == the UE-aligned body-local frame) and returns the hit Z, or unset on miss.
    static auto CastDownAt(const JPH::Shape& InShape, double InX, double InY) -> TOptional<double>
    {
        const auto RayStart = JPH::Vec3{static_cast<float>(InX), static_cast<float>(InY), 1000.0f};
        const auto RayDirection = JPH::Vec3{0.0f, 0.0f, -2000.0f};

        const auto Ray = JPH::RayCast{RayStart, RayDirection};
        auto Hit = JPH::RayCastResult{};

        if (NOT InShape.CastRay(Ray, JPH::SubShapeIDCreator{}, Hit))
        { return {}; }

        return 1000.0 - 2000.0 * Hit.mFraction;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_HeightField_KnownHeightsZUp,
    "Ck.Jolt.Bake.HeightField.KnownHeightsZUp",
    ck_test_jolt_heightfield::kTestFlags)

bool FCkTest_JoltBake_HeightField_KnownHeightsZUp::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_heightfield;

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto Heights = TArray<float>{};
    Heights.SetNumUninitialized(SampleCount * SampleCount);

    for (auto Y = 0; Y < SampleCount; ++Y)
    {
        for (auto X = 0; X < SampleCount; ++X)
        { Heights[Y * SampleCount + X] = Get_ExpectedHeight(X, Y); }
    }

    const auto Shape = ck::jolt::bake::CreateHeightFieldShape(Heights, SampleCount, FVector2D{ScaleXY, ScaleXY});

    if (NOT TestNotNull(TEXT("Heightfield shape created"), Shape.GetPtr()))
    { return false; }

    // World-space probes on the h = 0.1*X + 1.0*Y plane. Each pins a distinct axis/mirror
    // mistake. The far world-Y boundary is half-open (Jolt's cell walk excludes the field's
    // local-origin edge — in real landscapes that seam is covered by the NEIGHBOR component's
    // accepting edge, since adjacent components share the seam row), so high-Y probes sit 1uu
    // inside the boundary instead of exactly on it.
    const TPair<double, double> ProbePoints[] = {{0.0, 0.0}, {700.0, 0.0}, {0.0, 699.0}, {699.0, 699.0}, {300.0, 500.0}};

    for (const auto& [X, Y] : ProbePoints)
    {
        const auto Expected = 0.1 * X + 1.0 * Y;
        const auto HitZ = CastDownAt(*Shape, X, Y);

        if (NOT TestTrue(ck::Format_UE(TEXT("Down-ray at world ({},{}) hits"), X, Y), HitZ.IsSet()))
        { continue; }

        TestTrue(ck::Format_UE(TEXT("Height at world ({},{}) is ~{} (got {})"), X, Y, Expected, *HitZ),
            FMath::Abs(*HitZ - Expected) <= HeightTolerance);
    }

    // Between-sample interpolation: midpoint of a linear surface must sit on the plane.
    {
        const auto HitZ = CastDownAt(*Shape, 2.5 * ScaleXY, 3.5 * ScaleXY);

        if (TestTrue(TEXT("Down-ray at grid (2.5,3.5) hits"), HitZ.IsSet()))
        {
            TestTrue(ck::Format_UE(TEXT("Interpolated height at (2.5,3.5) is ~375 (got {})"), *HitZ),
                FMath::Abs(*HitZ - 375.0) <= HeightTolerance);
        }
    }

    // Holes: a no-collision sample removes its quads; a neighbor stays solid.
    {
        auto HeightsWithHole = Heights;
        HeightsWithHole[2 * SampleCount + 2] = ck::jolt::bake::HeightFieldNoCollisionValue();

        const auto HoleShape = ck::jolt::bake::CreateHeightFieldShape(
            HeightsWithHole, SampleCount, FVector2D{ScaleXY, ScaleXY});

        if (TestNotNull(TEXT("Holed heightfield shape created"), HoleShape.GetPtr()))
        {
            TestFalse(TEXT("Down-ray at the hole sample misses"),
                CastDownAt(*HoleShape, 2.0 * ScaleXY, 2.0 * ScaleXY).IsSet());

            TestTrue(TEXT("Down-ray away from the hole still hits"),
                CastDownAt(*HoleShape, 5.0 * ScaleXY, 5.0 * ScaleXY).IsSet());
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
