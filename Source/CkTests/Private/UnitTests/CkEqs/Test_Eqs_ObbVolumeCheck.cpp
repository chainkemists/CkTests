// Unit tests for FCk_Eqs_Algorithm::Get_IsPointInOrientedBox — the containment
// math behind the VolumeCheck test's WorldRotation (OBB) support.

#include "Misc/AutomationTest.h"

#include "CkEqs/Query/CkEqs_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Eqs_VolumeCheck_ObbContainment,
    "CkTests.UnitTests.CkEqs.VolumeCheck.ObbContainment",
    ck::tests::kCkUnitTestFlags)

bool FCkTest_Eqs_VolumeCheck_ObbContainment::RunTest(const FString& Parameters)
{
    const auto Center = FVector{1000.0f, 0.0f, 0.0f};
    const auto HalfExtent = FVector{200.0f, 50.0f, 100.0f};

    // Zero rotation — must reproduce the legacy AABB behavior exactly.
    TestTrue(TEXT("AA: point inside"),
        FCk_Eqs_Algorithm::Get_IsPointInOrientedBox(
            FVector{1100.0f, 25.0f, 50.0f}, Center, HalfExtent, FRotator::ZeroRotator));
    TestFalse(TEXT("AA: point outside on Y"),
        FCk_Eqs_Algorithm::Get_IsPointInOrientedBox(
            FVector{1100.0f, 75.0f, 50.0f}, Center, HalfExtent, FRotator::ZeroRotator));

    // 90° yaw: the box's long X half-extent (200) now lies along world Y.
    const auto Rot90 = FRotator{0.0f, 90.0f, 0.0f};
    TestTrue(TEXT("OBB 90: inside along rotated long axis"),
        FCk_Eqs_Algorithm::Get_IsPointInOrientedBox(
            FVector{1000.0f, 180.0f, 0.0f}, Center, HalfExtent, Rot90));
    TestFalse(TEXT("OBB 90: outside (an unrotated AABB would contain this)"),
        FCk_Eqs_Algorithm::Get_IsPointInOrientedBox(
            FVector{1180.0f, 0.0f, 0.0f}, Center, HalfExtent, Rot90));

    // 45° yaw: a point ON the rotated X axis at distance 150 (< 200) is inside.
    const auto Rot45 = FRotator{0.0f, 45.0f, 0.0f};
    const auto OnAxis45 = Center + Rot45.RotateVector(FVector{150.0f, 0.0f, 0.0f});
    TestTrue(TEXT("OBB 45: inside on rotated axis"),
        FCk_Eqs_Algorithm::Get_IsPointInOrientedBox(OnAxis45, Center, HalfExtent, Rot45));

    return true;
}
