#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include <Misc/AutomationTest.h>

#include <Jolt/Jolt.h>
#include <Jolt/Core/StreamWrapper.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/Shape/Shape.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>

#include <sstream>

// --------------------------------------------------------------------------------------------------------------------
// Pins the cooked-data serialization contract: N shapes written into ONE SaveWithChildren stream
// with shared ShapeToIDMap/MaterialToIDMap restore, in order, to shapes that answer raycasts
// identically to the originals. This is exactly what UCk_Jolt_CookedCell_UE's blob format does.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_shapeblob
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter;

    static auto CastRayFraction(const JPH::Shape& InShape, const JPH::Vec3& InOrigin, const JPH::Vec3& InDirection)
        -> TOptional<float>
    {
        const auto Ray = JPH::RayCast{InOrigin, InDirection};
        auto Hit = JPH::RayCastResult{};

        if (NOT InShape.CastRay(Ray, JPH::SubShapeIDCreator{}, Hit))
        { return {}; }

        return Hit.mFraction;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_ShapeBlob_RoundTrip,
    "Ck.Jolt.Bake.ShapeBlob.RoundTrip",
    ck_test_jolt_shapeblob::kTestFlags)

bool FCkTest_JoltBake_ShapeBlob_RoundTrip::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_shapeblob;

    ck::jolt::Request_GlobalJoltInit();
    ON_SCOPE_EXIT { ck::jolt::Request_GlobalJoltShutdown(); };

    // ---- Build three representative shapes (primitive, axis-corrected wrap, heightfield) --------

    auto SourceShapes = TArray<JPH::Ref<JPH::Shape>>{};

    {
        const auto BoxSettings = JPH::BoxShapeSettings{JPH::Vec3{50.0f, 100.0f, 150.0f}};
        const auto BoxResult = BoxSettings.Create();
        if (NOT TestTrue(TEXT("Box shape created"), BoxResult.IsValid()))
        { return false; }
        SourceShapes.Emplace(BoxResult.Get());
    }

    {
        const auto CapsuleSettings = JPH::CapsuleShapeSettings{75.0f, 25.0f};
        const auto CapsuleResult = CapsuleSettings.Create();
        if (NOT TestTrue(TEXT("Capsule shape created"), CapsuleResult.IsValid()))
        { return false; }

        const auto UprightSettings = JPH::RotatedTranslatedShapeSettings{
            JPH::Vec3::sZero(), ck::jolt::Get_ShapeAxisCorrection_YToZ(), CapsuleResult.Get().GetPtr()};
        const auto UprightResult = UprightSettings.Create();
        if (NOT TestTrue(TEXT("Axis-corrected capsule created"), UprightResult.IsValid()))
        { return false; }
        SourceShapes.Emplace(UprightResult.Get());
    }

    {
        auto Heights = TArray<float>{};
        Heights.SetNumUninitialized(4 * 4);
        for (auto Index = 0; Index < Heights.Num(); ++Index)
        { Heights[Index] = 10.0f * Index; }

        const auto HeightField = ck::jolt::bake::CreateHeightFieldShape(Heights, 4, FVector2D{100.0, 100.0});
        if (NOT TestNotNull(TEXT("Heightfield shape created"), HeightField.GetPtr()))
        { return false; }
        SourceShapes.Emplace(HeightField);
    }

    // ---- Serialize all three into ONE stream with shared maps (the cell-blob format) ------------

    auto BlobStream = std::ostringstream{};
    {
        auto StreamWrapper = JPH::StreamOutWrapper{BlobStream};
        auto ShapeToId = JPH::Shape::ShapeToIDMap{};
        auto MaterialToId = JPH::Shape::MaterialToIDMap{};

        for (const auto& Shape : SourceShapes)
        { Shape->SaveWithChildren(StreamWrapper, ShapeToId, MaterialToId); }
    }

    const auto BlobString = BlobStream.str();
    TestTrue(TEXT("Blob is non-empty"), BlobString.size() > 0);

    // ---- Restore and compare raycast answers ----------------------------------------------------

    auto RestoreStream = std::istringstream{BlobString};
    auto StreamWrapper = JPH::StreamInWrapper{RestoreStream};
    auto IdToShape = JPH::Shape::IDToShapeMap{};
    auto IdToMaterial = JPH::Shape::IDToMaterialMap{};

    const JPH::Vec3 ProbeRays[][2] = {
        {JPH::Vec3{0.0f, 0.0f, 1000.0f}, JPH::Vec3{0.0f, 0.0f, -2000.0f}},
        {JPH::Vec3{-1000.0f, 10.0f, 20.0f}, JPH::Vec3{2000.0f, 0.0f, 0.0f}},
        {JPH::Vec3{30.0f, -1000.0f, 40.0f}, JPH::Vec3{0.0f, 2000.0f, 0.0f}}};

    for (auto ShapeIndex = 0; ShapeIndex < SourceShapes.Num(); ++ShapeIndex)
    {
        const auto Result = JPH::Shape::sRestoreWithChildren(StreamWrapper, IdToShape, IdToMaterial);

        if (NOT TestTrue(ck::Format_UE(TEXT("Shape [{}] restored"), ShapeIndex), Result.IsValid()))
        { return false; }

        const auto& Restored = Result.Get();

        for (const auto& [Origin, Direction] : ProbeRays)
        {
            const auto SourceFraction = CastRayFraction(*SourceShapes[ShapeIndex], Origin, Direction);
            const auto RestoredFraction = CastRayFraction(*Restored, Origin, Direction);

            TestEqual(ck::Format_UE(TEXT("Shape [{}]: hit/miss matches"), ShapeIndex),
                RestoredFraction.IsSet(), SourceFraction.IsSet());

            if (SourceFraction.IsSet() && RestoredFraction.IsSet())
            {
                TestTrue(ck::Format_UE(TEXT("Shape [{}]: fraction matches ({} vs {})"),
                        ShapeIndex, *SourceFraction, *RestoredFraction),
                    FMath::Abs(*SourceFraction - *RestoredFraction) < 1e-4f);
            }
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
