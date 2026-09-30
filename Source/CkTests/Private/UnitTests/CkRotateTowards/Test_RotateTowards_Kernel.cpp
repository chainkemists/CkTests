#include "Misc/AutomationTest.h"

#include "CkRotateTowards/CkRotateTowards_Kernel.h"
#include "../CkUnitTest_Common.h"

#include <limits>

namespace ck_test_rotate_towards_kernel
{
    using namespace ck::rotate_towards;

    auto MakeTunables(ECk_RotateTowards_Mode InMode, float InTurnRateDegPerSec) -> FCk_RotateTowards_Tunables
    {
        auto Tunables = FCk_RotateTowards_Tunables{InMode};
        Tunables.Get_Pitch().Set_TurnRateDegPerSec(InTurnRateDegPerSec);
        Tunables.Get_Yaw().Set_TurnRateDegPerSec(InTurnRateDegPerSec);
        Tunables.Get_Roll().Set_TurnRateDegPerSec(InTurnRateDegPerSec);
        return Tunables;
    }

    auto MakeRange(ECk_EnableDisable InEnabled, double InMinDeg, double InMaxDeg) -> FCk_RotateTowards_AxisRange
    {
        return FCk_RotateTowards_AxisRange{InEnabled, FCk_FloatRange{InMinDeg, InMaxDeg}};
    }

    auto IsNear(double InActual, double InExpected, double InTolerance = 1.0e-3) -> bool
    {
        return FMath::IsNearlyEqual(InActual, InExpected, InTolerance);
    }

    auto IsNearRotator(const FRotator& InActual, const FRotator& InExpected, double InTolerance = 1.0e-3) -> bool
    {
        return InActual.Equals(InExpected, InTolerance);
    }
}

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_LookAt_Coincident_IsUnset,
    "Ck.RotateTowards.Kernel.LookAt_Coincident_IsUnset", kCkUnitTestFlags)
bool FCk_RotateTowards_LookAt_Coincident_IsUnset::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Point = FVector{100, 200, 300};
    const auto NaN = std::numeric_limits<double>::quiet_NaN();
    TestFalse(TEXT("From == To is unset"), Compute_LookAtRotation(Point, Point).IsSet());
    TestFalse(TEXT("0.001 cm apart is unset"), Compute_LookAtRotation(FVector::ZeroVector, FVector{0.001, 0, 0}).IsSet());
    TestFalse(TEXT("NaN target is unset"), Compute_LookAtRotation(FVector::ZeroVector, FVector{NaN, 0, 0}).IsSet());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_LookAt_CardinalDirections,
    "Ck.RotateTowards.Kernel.LookAt_CardinalDirections", kCkUnitTestFlags)
bool FCk_RotateTowards_LookAt_CardinalDirections::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Forward = Compute_LookAtRotation(FVector::ZeroVector, FVector{100, 0, 0});
    const auto Right = Compute_LookAtRotation(FVector::ZeroVector, FVector{0, 100, 0});
    const auto Up = Compute_LookAtRotation(FVector::ZeroVector, FVector{0, 0, 100});
    const auto Back = Compute_LookAtRotation(FVector::ZeroVector, FVector{-100, 0, 0});
    if (NOT TestTrue(TEXT("all four are set"), Forward.IsSet() && Right.IsSet() && Up.IsSet() && Back.IsSet()))
    { return false; }

    TestTrue(TEXT("+X is (0, 0, 0)"), IsNearRotator(Forward.GetValue(), FRotator{0, 0, 0}));
    TestTrue(TEXT("+Y is (0, 90, 0)"), IsNearRotator(Right.GetValue(), FRotator{0, 90, 0}));
    TestTrue(TEXT("+Z is (90, 0, 0)"), IsNearRotator(Up.GetValue(), FRotator{90, 0, 0}));
    TestTrue(TEXT("-X pitch is 0"), IsNear(Back->Pitch, 0.0));
    TestTrue(TEXT("-X yaw is 180 (or -180)"), IsNear(FMath::Abs(FRotator::NormalizeAxis(Back->Yaw)), 180.0));
    TestTrue(TEXT("-X roll is 0"), IsNear(Back->Roll, 0.0));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_AxisLocks_HoldCurrent,
    "Ck.RotateTowards.Kernel.AxisLocks_HoldCurrent", kCkUnitTestFlags)
bool FCk_RotateTowards_AxisLocks_HoldCurrent::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Desired = FRotator{30, 60, 10};
    const auto Current = FRotator{5, 5, 5};

    auto PitchLocked = FCk_RotateTowards_Tunables{};
    PitchLocked.Get_Pitch().Set_Mode(ECk_RotateTowards_AxisMode::Locked);
    TestTrue(TEXT("pitch locked gives (5, 60, 10)"), IsNearRotator(Apply_AxisLocks(Desired, Current, PitchLocked), FRotator{5, 60, 10}));

    auto AllLocked = PitchLocked;
    AllLocked.Get_Yaw().Set_Mode(ECk_RotateTowards_AxisMode::Locked);
    AllLocked.Get_Roll().Set_Mode(ECk_RotateTowards_AxisMode::Locked);
    TestTrue(TEXT("all locked gives (5, 5, 5)"), IsNearRotator(Apply_AxisLocks(Desired, Current, AllLocked), FRotator{5, 5, 5}));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_ClampAngle_InsideRangeUnchanged_AndWraps,
    "Ck.RotateTowards.Kernel.ClampAngle_InsideRangeUnchanged_AndWraps", kCkUnitTestFlags)
bool FCk_RotateTowards_ClampAngle_InsideRangeUnchanged_AndWraps::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Range30 = FCk_FloatRange{-30.0, 30.0};
    TestTrue(TEXT("rest 170, desired -170 (delta 20) stays -170"), IsNear(Clamp_AngleToRange(-170.0f, 170.0f, Range30), -170.0));
    TestTrue(TEXT("rest 170, desired -150 (delta 40) clamps to -160"), IsNear(Clamp_AngleToRange(-150.0f, 170.0f, Range30), -160.0));
    TestTrue(TEXT("rest 0, desired -100 clamps to -45"), IsNear(Clamp_AngleToRange(-100.0f, 0.0f, FCk_FloatRange{-45.0, 45.0}), -45.0));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_RangeClamp_OnlyEnabledAxes,
    "Ck.RotateTowards.Kernel.RangeClamp_OnlyEnabledAxes", kCkUnitTestFlags)
bool FCk_RotateTowards_RangeClamp_OnlyEnabledAxes::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    auto Clamp = FCk_RotateTowards_RangeClamp{};
    Clamp.Set_Yaw(MakeRange(ECk_EnableDisable::Enable, -45.0, 45.0));
    Clamp.Set_Pitch(MakeRange(ECk_EnableDisable::Disable, -45.0, 45.0));
    Clamp.Set_Roll(MakeRange(ECk_EnableDisable::Disable, -45.0, 45.0));
    const auto Clamped = Apply_RangeClamp(FRotator{80, 80, 80}, FRotator::ZeroRotator, Clamp);
    TestTrue(TEXT("only yaw is clamped: (80, 45, 80)"), IsNearRotator(Clamped, FRotator{80, 45, 80}));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_StepAngle_RateLimitsAndTakesShortestArc,
    "Ck.RotateTowards.Kernel.StepAngle_RateLimitsAndTakesShortestArc", kCkUnitTestFlags)
bool FCk_RotateTowards_StepAngle_RateLimitsAndTakesShortestArc::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    TestTrue(TEXT("0 -> 90 at 30 deg/s for 1 s is 30"), IsNear(Step_Angle(0.0f, 90.0f, 30.0f, 1.0f), 30.0));
    TestTrue(TEXT("170 -> -150 at 30 deg/s for 1 s is -160 (a 40 deg arc through 180, never the long way)"), IsNear(Step_Angle(170.0f, -150.0f, 30.0f, 1.0f), -160.0));
    TestTrue(TEXT("0 -> 10 at 100 deg/s for 1 s lands exactly on 10"), IsNear(Step_Angle(0.0f, 10.0f, 100.0f, 1.0f), 10.0));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_StepAngle_ZeroRateOrDt_Holds,
    "Ck.RotateTowards.Kernel.StepAngle_ZeroRateOrDt_Holds", kCkUnitTestFlags)
bool FCk_RotateTowards_StepAngle_ZeroRateOrDt_Holds::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    TestTrue(TEXT("rate 0 holds"), IsNear(Step_Angle(15.0f, 60.0f, 0.0f, 1.0f), 15.0));
    TestTrue(TEXT("dt 0 holds"), IsNear(Step_Angle(15.0f, 60.0f, 90.0f, 0.0f), 15.0));
    TestTrue(TEXT("negative rate holds"), IsNear(Step_Angle(15.0f, 60.0f, -5.0f, 1.0f), 15.0));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_StepRotation_Instant_SnapsFreeAxesOnly,
    "Ck.RotateTowards.Kernel.StepRotation_Instant_SnapsFreeAxesOnly", kCkUnitTestFlags)
bool FCk_RotateTowards_StepRotation_Instant_SnapsFreeAxesOnly::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    auto Tunables = FCk_RotateTowards_Tunables{ECk_RotateTowards_Mode::Instant};
    Tunables.Get_Roll().Set_Mode(ECk_RotateTowards_AxisMode::Locked);
    const auto New = Step_Rotation(FRotator{0, 0, 7}, FRotator{20, 40, 60}, Tunables, 1.0f / 60.0f);
    TestTrue(TEXT("free axes snap, locked roll holds: (20, 40, 7)"), IsNearRotator(New, FRotator{20, 40, 7}));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_StepRotation_RateLimited_ConvergesExactly,
    "Ck.RotateTowards.Kernel.StepRotation_RateLimited_ConvergesExactly", kCkUnitTestFlags)
bool FCk_RotateTowards_StepRotation_RateLimited_ConvergesExactly::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Tunables = MakeTunables(ECk_RotateTowards_Mode::RateLimited, 90.0f);
    const auto Desired = FRotator{10, -120, 45};
    constexpr auto MaxIterations = 600;

    auto Current = FRotator::ZeroRotator;
    auto Iterations = 0;
    auto YawSteps = 0;
    auto NeverOvershoots = true;
    for (; Iterations < MaxIterations; ++Iterations)
    {
        const auto New = Step_Rotation(Current, Desired, Tunables, 1.0f / 60.0f);
        if (New.Equals(Current, 1.0e-6))
        { break; }

        const auto Before = Compute_RemainingDelta(Current, Desired);
        const auto After = Compute_RemainingDelta(New, Desired);
        for (const auto& [BeforeDeg, AfterDeg] : {std::pair{Before.Pitch, After.Pitch}, std::pair{Before.Yaw, After.Yaw}, std::pair{Before.Roll, After.Roll}})
        {
            if (FMath::Abs(AfterDeg) > FMath::Abs(BeforeDeg) + 1.0e-3 || AfterDeg * BeforeDeg < -1.0e-6)
            { NeverOvershoots = false; }
        }

        if (NOT FMath::IsNearlyEqual(New.Yaw, Current.Yaw, 1.0e-6))
        { ++YawSteps; }

        Current = New;
    }

    TestTrue(TEXT("converges within 600 iterations"), Iterations < MaxIterations);
    TestTrue(TEXT("lands on the desired rotation"), IsNearRotator(Current, Desired));
    TestTrue(FString::Printf(TEXT("yaw takes 79-81 frames (120 deg / 90 deg/s * 60), took %d"), YawSteps), YawSteps >= 79 && YawSteps <= 81);
    TestTrue(TEXT("no axis ever overshoots"), NeverOvershoots);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_Remaining_And_AtTarget,
    "Ck.RotateTowards.Kernel.Remaining_And_AtTarget", kCkUnitTestFlags)
bool FCk_RotateTowards_Remaining_And_AtTarget::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Current = FRotator{0, 10, 0};
    const auto Desired = FRotator{0, 12, 0};
    TestTrue(TEXT("remaining is (0, 2, 0)"), IsNearRotator(Compute_RemainingDelta(Current, Desired), FRotator{0, 2, 0}));
    TestFalse(TEXT("tolerance 1 is not at target"), Get_IsAtTarget(Current, Desired, 1.0f));
    TestTrue(TEXT("tolerance 2 is at target"), Get_IsAtTarget(Current, Desired, 2.0f));
    TestTrue(TEXT("179 -> -179 remaining yaw is 2"), IsNear(Compute_RemainingDelta(FRotator{0, 179, 0}, FRotator{0, -179, 0}).Yaw, 2.0));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_ComposeOffset_WorldDeltaInLocalFrame,
    "Ck.RotateTowards.Kernel.ComposeOffset_WorldDeltaInLocalFrame", kCkUnitTestFlags)
bool FCk_RotateTowards_ComposeOffset_WorldDeltaInLocalFrame::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    const auto Offset = FRotator{0, 90, 0}.Quaternion();
    const auto CurrentWorld = FRotator{0, 135, 0}.Quaternion();
    const auto NewWorld = FRotator{0, 150, 0}.Quaternion();
    const auto NewOffset = Compose_OffsetRotation(Offset, CurrentWorld, NewWorld);
    TestTrue(TEXT("driver yaw 45, offset yaw 90, world 135 -> 150 gives offset yaw 105"),
        IsNear(FRotator::NormalizeAxis(NewOffset.Rotator().Yaw), 105.0));

    const auto Q = FRotator{10, 20, 30}.Quaternion();
    TestTrue(TEXT("no world change keeps an identity offset"), Compose_OffsetRotation(FQuat::Identity, Q, Q).Equals(FQuat::Identity, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_RotateTowards_Validation_RejectsBadValues,
    "Ck.RotateTowards.Kernel.Validation_RejectsBadValues", kCkUnitTestFlags)
bool FCk_RotateTowards_Validation_RejectsBadValues::RunTest(const FString& Parameters)
{
    using namespace ck_test_rotate_towards_kernel;
    TestTrue(TEXT("default tunables are valid"), Get_IsTunablesValid(FCk_RotateTowards_Tunables{}));

    auto NaNRate = FCk_RotateTowards_Tunables{};
    NaNRate.Get_Yaw().Set_TurnRateDegPerSec(std::numeric_limits<float>::quiet_NaN());
    TestFalse(TEXT("NaN yaw rate is invalid"), Get_IsTunablesValid(NaNRate));

    auto NegativeRate = FCk_RotateTowards_Tunables{};
    NegativeRate.Get_Yaw().Set_TurnRateDegPerSec(-1.0f);
    TestFalse(TEXT("rate -1 is invalid"), Get_IsTunablesValid(NegativeRate));

    auto NegativeTolerance = FCk_RotateTowards_Tunables{};
    NegativeTolerance.Set_ReachedToleranceDeg(-0.1f);
    TestFalse(TEXT("tolerance -0.1 is invalid"), Get_IsTunablesValid(NegativeTolerance));

    const auto DefaultClamp = FCk_RotateTowards_RangeClamp{};
    TestFalse(TEXT("default clamp has no range"), Get_HasAnyRange(DefaultClamp));
    TestTrue(TEXT("default clamp is valid"), Get_IsRangeClampValid(DefaultClamp));

    auto YawClamp = FCk_RotateTowards_RangeClamp{};
    YawClamp.Set_Yaw(MakeRange(ECk_EnableDisable::Enable, -30.0, 30.0));
    TestTrue(TEXT("yaw [-30, 30] has a range"), Get_HasAnyRange(YawClamp));
    TestTrue(TEXT("yaw [-30, 30] is valid"), Get_IsRangeClampValid(YawClamp));

    auto InvertedClamp = FCk_RotateTowards_RangeClamp{};
    InvertedClamp.Set_Yaw(MakeRange(ECk_EnableDisable::Enable, 30.0, -30.0));
    TestFalse(TEXT("yaw [30, -30] is invalid"), Get_IsRangeClampValid(InvertedClamp));

    auto OutOfBoundsClamp = FCk_RotateTowards_RangeClamp{};
    OutOfBoundsClamp.Set_Yaw(MakeRange(ECk_EnableDisable::Enable, -200.0, 10.0));
    TestFalse(TEXT("yaw [-200, 10] is invalid"), Get_IsRangeClampValid(OutOfBoundsClamp));

    auto DisabledInvertedClamp = FCk_RotateTowards_RangeClamp{};
    DisabledInvertedClamp.Set_Pitch(MakeRange(ECk_EnableDisable::Disable, 30.0, -30.0));
    TestTrue(TEXT("a disabled inverted pitch range is not inspected"), Get_IsRangeClampValid(DisabledInvertedClamp));
    return true;
}
