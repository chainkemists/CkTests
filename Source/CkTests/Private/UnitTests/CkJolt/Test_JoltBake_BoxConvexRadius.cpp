#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include "../CkUnitTest_Common.h"

#include <Misc/AutomationTest.h>
#include <PhysicsEngine/BodySetup.h>
#include <PhysicsEngine/BoxElem.h>

#include <Jolt/Jolt.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_BoxConvexRadius_ThinBoxPreservesBounds,
    "Ck.Jolt.Bake.BoxConvexRadius.ThinBoxPreservesBounds",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_JoltBake_BoxConvexRadius_ThinBoxPreservesBounds::RunTest(const FString& Parameters)
{
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 80.0f, 0.08f);

    const auto Shape = ck::jolt::bake::BuildShape_FromBodySetup(
        *BodySetup, FVector{2.0, 0.5, 0.5}, TEXT("ThinBoxBodySetup"));

    if (NOT TestNotNull(TEXT("Positive thin box creates a Jolt shape"), Shape.GetPtr()))
    { return false; }

    if (NOT TestTrue(TEXT("Thin box remains a box shape"), Shape->GetSubType() == JPH::EShapeSubType::Box))
    { return false; }

    const auto* BoxShape = static_cast<const JPH::BoxShape*>(Shape.GetPtr());
    const auto HalfExtents = BoxShape->GetHalfExtent();

    TestTrue(TEXT("Scaled X half extent is preserved"), FMath::IsNearlyEqual(HalfExtents.GetX(), 100.0f));
    TestTrue(TEXT("Scaled Y half extent is preserved"), FMath::IsNearlyEqual(HalfExtents.GetY(), 20.0f));
    TestTrue(TEXT("Scaled Z half extent is preserved"), FMath::IsNearlyEqual(HalfExtents.GetZ(), 0.02f));
    TestTrue(TEXT("Adaptive convex radius is below the minimum half extent"),
        BoxShape->GetConvexRadius() < HalfExtents.ReduceMin());

    auto OrdinaryBodySetup = NewObject<UBodySetup>(GetTransientPackage());
    OrdinaryBodySetup->AggGeom.BoxElems.Emplace(100.0f, 100.0f, 100.0f);

    const auto OrdinaryShape = ck::jolt::bake::BuildShape_FromBodySetup(
        *OrdinaryBodySetup, FVector::OneVector, TEXT("OrdinaryBoxBodySetup"));

    if (NOT TestNotNull(TEXT("Ordinary box creates a Jolt shape"), OrdinaryShape.GetPtr()))
    { return false; }

    if (NOT TestTrue(TEXT("Ordinary box remains a box shape"),
        OrdinaryShape->GetSubType() == JPH::EShapeSubType::Box))
    { return false; }

    const auto* OrdinaryBoxShape = static_cast<const JPH::BoxShape*>(OrdinaryShape.GetPtr());
    TestTrue(TEXT("Ordinary box keeps Jolt's default convex radius"),
        FMath::IsNearlyEqual(OrdinaryBoxShape->GetConvexRadius(), JPH::cDefaultConvexRadius));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBake_BoxConvexRadius_InvalidBoxRejectsWholeBodySetup,
    "Ck.Jolt.Bake.BoxConvexRadius.InvalidBoxRejectsWholeBodySetup",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_JoltBake_BoxConvexRadius_InvalidBoxRejectsWholeBodySetup::RunTest(const FString& Parameters)
{
    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto BodySetup = NewObject<UBodySetup>(GetTransientPackage());
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 100.0f, 100.0f);
    BodySetup->AggGeom.BoxElems.Emplace(100.0f, 100.0f, 0.0f);

    AddExpectedError(
        TEXT("HalfExtentsArePositive"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    const auto Shape = ck::jolt::bake::BuildShape_FromBodySetup(
        *BodySetup, FVector::OneVector, TEXT("MixedBoxBodySetup"));

    TestNull(TEXT("One invalid required box rejects the entire BodySetup"), Shape.GetPtr());

    auto NonFiniteBodySetup = NewObject<UBodySetup>(GetTransientPackage());
    NonFiniteBodySetup->AggGeom.BoxElems.Emplace(
        100.0f, 100.0f, std::numeric_limits<float>::infinity());

    const auto NonFiniteShape = ck::jolt::bake::BuildShape_FromBodySetup(
        *NonFiniteBodySetup, FVector::OneVector, TEXT("NonFiniteBoxBodySetup"));

    TestNull(TEXT("A non-finite required box rejects the entire BodySetup"), NonFiniteShape.GetPtr());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
