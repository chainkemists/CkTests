#include "Misc/AutomationTest.h"

#include "CkSway/CkSway_Kernel.h"
#include "../CkUnitTest_Common.h"

#include <limits>

namespace ck_test_sway_kernel
{
    using namespace ck::sway;

    auto MakePose(const FVector& InLocation, const FRotator& InRotation = FRotator::ZeroRotator) -> FTransform
    {
        return FTransform{InRotation, InLocation};
    }

    auto MakeResponse(const FVector& InMax, float InFrequencyHz, float InDampingRatio) -> FCk_Sway_Response
    {
        return FCk_Sway_Response{InMax, InFrequencyHz, InDampingRatio};
    }
}

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Stimulus_ZeroDeltaTime_IsUnset,
    "Ck.Sway.Kernel.Stimulus_ZeroDeltaTime_IsUnset", kCkUnitTestFlags)
bool FCk_Sway_Stimulus_ZeroDeltaTime_IsUnset::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Prev = MakePose(FVector::ZeroVector);
    const auto Curr = MakePose(FVector{100, 0, 0}, FRotator{0, 30, 0});
    TestFalse(TEXT("dt = 0 is unset"), Compute_Stimulus(Prev, Curr, 0.0f, 0.0f, 0.0f).IsSet());
    TestFalse(TEXT("dt = -1 is unset"), Compute_Stimulus(Prev, Curr, -1.0f, 0.0f, 0.0f).IsSet());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Stimulus_PureYaw_ReportsYawRateInLocalFrame,
    "Ck.Sway.Kernel.Stimulus_PureYaw_ReportsYawRateInLocalFrame", kCkUnitTestFlags)
bool FCk_Sway_Stimulus_PureYaw_ReportsYawRateInLocalFrame::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Stimulus = Compute_Stimulus(FTransform::Identity, MakePose(FVector::ZeroVector, FRotator{0, 30, 0}), 0.5f, 0.0f, 0.0f);
    if (NOT TestTrue(TEXT("stimulus is set"), Stimulus.IsSet()))
    { return false; }
    TestTrue(TEXT("angular velocity is (0, 0, 60) deg/s"), Stimulus->Get_AngularVelocityDeg().Equals(FVector{0, 0, 60}, 1.0e-3));
    TestTrue(TEXT("linear velocity is zero"), Stimulus->Get_LinearVelocity().Equals(FVector::ZeroVector, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Stimulus_LocalFrame_WhenParentAlreadyRotated,
    "Ck.Sway.Kernel.Stimulus_LocalFrame_WhenParentAlreadyRotated", kCkUnitTestFlags)
bool FCk_Sway_Stimulus_LocalFrame_WhenParentAlreadyRotated::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Prev = MakePose(FVector::ZeroVector, FRotator{45, 0, 0});
    const auto Curr = FTransform{Prev.GetRotation() * FRotator{0, 10, 0}.Quaternion(), FVector::ZeroVector};
    const auto Stimulus = Compute_Stimulus(Prev, Curr, 1.0f, 0.0f, 0.0f);
    if (NOT TestTrue(TEXT("stimulus is set"), Stimulus.IsSet()))
    { return false; }
    TestTrue(TEXT("local yaw rate is (0, 0, 10) deg/s"), Stimulus->Get_AngularVelocityDeg().Equals(FVector{0, 0, 10}, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Stimulus_ForwardMove_ReportsLocalVelocity,
    "Ck.Sway.Kernel.Stimulus_ForwardMove_ReportsLocalVelocity", kCkUnitTestFlags)
bool FCk_Sway_Stimulus_ForwardMove_ReportsLocalVelocity::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Prev = MakePose(FVector{10, 20, 30}, FRotator{0, 90, 0});
    const auto Curr = MakePose(Prev.GetLocation() + FVector{0, 100, 0}, FRotator{0, 90, 0});
    const auto Stimulus = Compute_Stimulus(Prev, Curr, 0.1f, 0.0f, 0.0f);
    if (NOT TestTrue(TEXT("stimulus is set"), Stimulus.IsSet()))
    { return false; }
    TestTrue(TEXT("local linear velocity is (1000, 0, 0) cm/s"), Stimulus->Get_LinearVelocity().Equals(FVector{1000, 0, 0}, 1.0e-2));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Stimulus_TeleportDistance_IsUnset,
    "Ck.Sway.Kernel.Stimulus_TeleportDistance_IsUnset", kCkUnitTestFlags)
bool FCk_Sway_Stimulus_TeleportDistance_IsUnset::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Prev = MakePose(FVector::ZeroVector);
    const auto Curr = MakePose(FVector{500, 0, 0});
    TestFalse(TEXT("500 cm step over a 100 cm threshold is unset"), Compute_Stimulus(Prev, Curr, 1.0f / 60.0f, 100.0f, 0.0f).IsSet());
    TestTrue(TEXT("threshold 0 disables the distance guard"), Compute_Stimulus(Prev, Curr, 1.0f / 60.0f, 0.0f, 0.0f).IsSet());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Stimulus_TeleportAngle_IsUnset,
    "Ck.Sway.Kernel.Stimulus_TeleportAngle_IsUnset", kCkUnitTestFlags)
bool FCk_Sway_Stimulus_TeleportAngle_IsUnset::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Prev = MakePose(FVector::ZeroVector);
    const auto Curr = MakePose(FVector::ZeroVector, FRotator{0, 120, 0});
    TestFalse(TEXT("120 deg turn over a 90 deg threshold is unset"), Compute_Stimulus(Prev, Curr, 1.0f / 60.0f, 0.0f, 90.0f).IsSet());
    TestTrue(TEXT("threshold 0 disables the angle guard"), Compute_Stimulus(Prev, Curr, 1.0f / 60.0f, 0.0f, 0.0f).IsSet());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Targets_FollowNegatedGains_AndClamp,
    "Ck.Sway.Kernel.Targets_FollowNegatedGains_AndClamp", kCkUnitTestFlags)
bool FCk_Sway_Targets_FollowNegatedGains_AndClamp::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    auto Spec = FCk_Sway_Spec{};
    Spec.Set_RotationFromAngularVelocity(FVector{0.01, 0.01, 0.01});
    Spec.Get_Location().Set_Max(FVector{5, 5, 5});
    Spec.Get_Rotation().Set_Max(FVector{5, 5, 5});
    const auto Stimulus = FCk_Sway_Stimulus{FVector{200, 0, 0}, FVector{0, 0, 300}};

    const auto RotationTarget = Compute_RotationTarget(Spec, Stimulus);
    TestTrue(TEXT("rotation target is (0, 0, -3)"), RotationTarget.Equals(FVector{0, 0, -3}, 1.0e-4));

    const auto LocationTarget = Compute_LocationTarget(Spec, Stimulus);
    TestTrue(TEXT("location X = -0.008 * 200"), FMath::IsNearlyEqual(LocationTarget.X, -1.6, 1.0e-4));
    TestTrue(TEXT("location Y = -0.02 * 300 clamped to -5"), FMath::IsNearlyEqual(LocationTarget.Y, -5.0, 1.0e-4));
    TestTrue(TEXT("location Z = 0"), FMath::IsNearlyEqual(LocationTarget.Z, 0.0, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Step_CriticallyDamped_ConvergesWithoutOvershoot,
    "Ck.Sway.Kernel.Step_CriticallyDamped_ConvergesWithoutOvershoot", kCkUnitTestFlags)
bool FCk_Sway_Step_CriticallyDamped_ConvergesWithoutOvershoot::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Response = MakeResponse(FVector{100, 100, 100}, 2.0f, 1.0f);
    const auto Target = FVector{10, 0, 0};
    auto State = FChannelState{};
    auto MaxObserved = State._Value.X;
    for (auto Step = 0; Step < 300; ++Step)
    {
        Step_Channel(State, Target, 1.0f / 120.0f, Response);
        MaxObserved = FMath::Max(MaxObserved, State._Value.X);
    }
    TestTrue(TEXT("value.X converged to 10"), FMath::IsNearlyEqual(State._Value.X, 10.0, 1.0e-2));
    TestTrue(TEXT("value.X never exceeded the target"), MaxObserved <= 10.0 + 1.0e-3);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Step_UnderDamped_Overshoots,
    "Ck.Sway.Kernel.Step_UnderDamped_Overshoots", kCkUnitTestFlags)
bool FCk_Sway_Step_UnderDamped_Overshoots::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Response = MakeResponse(FVector{100, 100, 100}, 2.0f, 0.2f);
    const auto Target = FVector{10, 0, 0};
    auto State = FChannelState{};
    auto MaxObserved = State._Value.X;
    for (auto Step = 0; Step < 300; ++Step)
    {
        Step_Channel(State, Target, 1.0f / 120.0f, Response);
        MaxObserved = FMath::Max(MaxObserved, State._Value.X);
    }
    TestTrue(TEXT("value.X overshot past 10.5"), MaxObserved > 10.5);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Step_ClampsToMax_AndZeroesOutwardVelocity,
    "Ck.Sway.Kernel.Step_ClampsToMax_AndZeroesOutwardVelocity", kCkUnitTestFlags)
bool FCk_Sway_Step_ClampsToMax_AndZeroesOutwardVelocity::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Response = MakeResponse(FVector{2, 2, 2}, 4.0f, 0.8f);
    const auto Target = FVector{10, 0, 0};
    auto State = FChannelState{};
    for (auto Step = 0; Step < 60; ++Step)
    { Step_Channel(State, Target, 1.0f / 60.0f, Response); }
    TestTrue(TEXT("value.X held at Max 2"), FMath::IsNearlyEqual(State._Value.X, 2.0, 1.0e-4));
    TestTrue(TEXT("velocity.X is not outward after clamping"), State._Velocity.X <= 0.0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Step_ZeroTarget_SettlesToRest,
    "Ck.Sway.Kernel.Step_ZeroTarget_SettlesToRest", kCkUnitTestFlags)
bool FCk_Sway_Step_ZeroTarget_SettlesToRest::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Response = MakeResponse(FVector{100, 100, 100}, 4.0f, 0.8f);
    auto State = FChannelState{};
    State._Value = FVector{5, 5, 5};
    State._Velocity = FVector{50, 0, 0};
    for (auto Step = 0; Step < 180; ++Step)
    { Step_Channel(State, FVector::ZeroVector, 1.0f / 60.0f, Response); }
    TestTrue(TEXT("channel settled after 3 s"), Get_IsSettled(State));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Spec_Validation_RejectsBadValues,
    "Ck.Sway.Kernel.Spec_Validation_RejectsBadValues", kCkUnitTestFlags)
bool FCk_Sway_Spec_Validation_RejectsBadValues::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    TestTrue(TEXT("default spec is valid"), Get_IsSpecValid(FCk_Sway_Spec{}));
    {
        auto Spec = FCk_Sway_Spec{};
        Spec.Get_RotationFromAngularVelocity().X = std::numeric_limits<double>::quiet_NaN();
        TestFalse(TEXT("NaN gain is invalid"), Get_IsSpecValid(Spec));
    }
    {
        auto Spec = FCk_Sway_Spec{};
        Spec.Get_Location().Get_Max().X = -1.0;
        TestFalse(TEXT("negative Max.X is invalid"), Get_IsSpecValid(Spec));
    }
    {
        auto Spec = FCk_Sway_Spec{};
        Spec.Get_Rotation().Get_Max().Y = 46.0;
        TestFalse(TEXT("rotation Max.Y over 45 deg is invalid"), Get_IsSpecValid(Spec));
    }
    {
        auto Spec = FCk_Sway_Spec{};
        Spec.Get_Location().Set_FrequencyHz(0.0f);
        TestFalse(TEXT("zero frequency is invalid"), Get_IsSpecValid(Spec));
    }
    {
        auto Spec = FCk_Sway_Spec{};
        Spec.Get_Rotation().Set_DampingRatio(-0.1f);
        TestFalse(TEXT("negative damping ratio is invalid"), Get_IsSpecValid(Spec));
    }
    {
        auto Spec = FCk_Sway_Spec{};
        Spec.Set_TeleportDistanceCm(-1.0f);
        TestFalse(TEXT("negative teleport distance is invalid"), Get_IsSpecValid(Spec));
    }

    const auto Offset = Compose_Offset(FVector{1, 2, 3}, FVector{4, 5, 6});
    const auto Rotator = Offset.Rotator();
    TestTrue(TEXT("offset pitch is rotation Y"), FMath::IsNearlyEqual(Rotator.Pitch, 5.0, 1.0e-3));
    TestTrue(TEXT("offset yaw is rotation Z"), FMath::IsNearlyEqual(Rotator.Yaw, 6.0, 1.0e-3));
    TestTrue(TEXT("offset roll is rotation X"), FMath::IsNearlyEqual(Rotator.Roll, 4.0, 1.0e-3));
    TestTrue(TEXT("offset location"), Offset.GetLocation().Equals(FVector{1, 2, 3}, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Sway_Compose_NodeOffset_AppliesSwayInRestFrame,
    "Ck.Sway.Kernel.Compose_NodeOffset_AppliesSwayInRestFrame", kCkUnitTestFlags)
bool FCk_Sway_Compose_NodeOffset_AppliesSwayInRestFrame::RunTest(const FString& Parameters)
{
    using namespace ck_test_sway_kernel;
    const auto Rest = MakePose(FVector{100, 0, 0}, FRotator{0, 90, 0});
    const auto Sway = MakePose(FVector{10, 0, 0});

    const auto NodeOffset = Compose_NodeOffset(Sway, Rest);
    TestTrue(TEXT("sway +X in the yawed rest frame lands at (100, 10, 0)"), NodeOffset.GetLocation().Equals(FVector{100, 10, 0}, 1.0e-3));
    TestTrue(TEXT("rest yaw 90 is kept"), FMath::IsNearlyEqual(NodeOffset.Rotator().Yaw, 90.0, 1.0e-3));

    const auto AtRest = Compose_NodeOffset(FTransform::Identity, Rest);
    TestTrue(TEXT("identity sway yields the rest offset"), AtRest.Equals(Rest, 1.0e-4));
    return true;
}
