// C++ unit test for the Camera POV geometry (CkCamera).
//
// World-free coverage of ck::camera::FPov boom/framing placement (collision disabled → no world needed,
// orientation control + auto-reorient disabled, noise frozen at default speed 0, springs instant at default speed 0).
//
// Surface in Session Frontend: CkTests.UnitTests.CkCamera.CameraPov.<scenario>

#include "Misc/AutomationTest.h"

#include "CkCamera/Camera/CkCamera_POV.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kCkUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    auto MakeGeometryOnlyProfile(float InBoomLength, const FVector& InFramingOffset) -> FCk_CameraProfile
    {
        auto Profile = FCk_CameraProfile{};
        Profile.Set_HasCollision(false);
        Profile.Set_HasOrientationControl(false);
        Profile.Set_HasAutoReorient(false);

        auto Rig = Profile.Get_Rig();
        Rig.Set_BoomArmLength(InBoomLength);
        Rig.Set_FramingOffset(InFramingOffset);
        Profile.Set_Rig(Rig);

        return Profile;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CameraPov_BoomPlacement,
    "CkTests.UnitTests.CkCamera.CameraPov.BoomPlacement",
    kCkUnitTestFlags)

bool FCkTest_CameraPov_BoomPlacement::RunTest(const FString& Parameters)
{
    const auto Profile = MakeGeometryOnlyProfile(300.0f, FVector::ZeroVector);

    auto Input = ck::camera::FPov_Input{};
    Input._AnchorTransform = FTransform(FRotator::ZeroRotator, FVector(1000.0f, 0.0f, 0.0f));
    Input._DeltaSeconds    = 0.016f;

    auto State = ck::camera::FPov_State{};
    ck::camera::FPov::Run(Profile, Input, State);

    // Anchor faces +X; camera sits 300 behind → (700, 0, 0), facing the same way.
    const auto Location = State._CameraTransform.GetLocation();
    const auto Rotation = State._CameraTransform.Rotator();

    TestTrue(TEXT("camera is boom-length behind the pivot"), Location.Equals(FVector(700.0f, 0.0f, 0.0f), 0.1f));
    TestTrue(TEXT("camera adopts the anchor facing"),        Rotation.Equals(FRotator::ZeroRotator, 0.1f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_CameraPov_FramingOffset,
    "CkTests.UnitTests.CkCamera.CameraPov.FramingOffset",
    kCkUnitTestFlags)

bool FCkTest_CameraPov_FramingOffset::RunTest(const FString& Parameters)
{
    const auto Profile = MakeGeometryOnlyProfile(0.0f, FVector(0.0f, 100.0f, 0.0f));

    auto Input = ck::camera::FPov_Input{};
    Input._AnchorTransform = FTransform(FRotator::ZeroRotator, FVector::ZeroVector);
    Input._DeltaSeconds    = 0.016f;

    auto State = ck::camera::FPov_State{};
    ck::camera::FPov::Run(Profile, Input, State);

    // Zero boom → camera at pivot, then framing offset (0,100,0) in the unrotated framing frame.
    const auto Location = State._CameraTransform.GetLocation();
    TestTrue(TEXT("framing offset translates the camera"), Location.Equals(FVector(0.0f, 100.0f, 0.0f), 0.1f));

    return true;
}
