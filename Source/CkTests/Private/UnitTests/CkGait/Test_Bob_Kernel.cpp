#include "Misc/AutomationTest.h"

#include "CkGait/Bob/CkBob_Kernel.h"
#include "../CkUnitTest_Common.h"

namespace ck_test_bob_kernel
{
    using namespace ck::bob;

    inline constexpr auto kFrameSeconds = 1.0f / 60.0f;

    auto MakeClock(float InAmount, float InPhase, float InBreathPhase = 0.0f) -> ck::gait::FClockState
    {
        auto Clock = ck::gait::FClockState{};
        Clock._Amount = InAmount;
        Clock._Phase = InPhase;
        Clock._BreathPhase = InBreathPhase;
        return Clock;
    }
}

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Spec_Defaults_AreValid,
    "Ck.Gait.BobKernel.Spec_Defaults_AreValid", kCkUnitTestFlags)
bool FCk_Bob_Spec_Defaults_AreValid::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    TestTrue(TEXT("default spec is valid"), Get_IsSpecValid(FCk_Bob_Spec{}));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Spec_IntensityAboveOne_IsInvalid,
    "Ck.Gait.BobKernel.Spec_IntensityAboveOne_IsInvalid", kCkUnitTestFlags)
bool FCk_Bob_Spec_IntensityAboveOne_IsInvalid::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    {
        auto Spec = FCk_Bob_Spec{};
        Spec.Set_Intensity(1.5f);
        TestFalse(TEXT("intensity 1.5 is invalid"), Get_IsSpecValid(Spec));
    }

    {
        auto Spec = FCk_Bob_Spec{};
        Spec.Get_Stride().Set_RollDeg(50.0f);
        TestFalse(TEXT("roll 50 deg is invalid"), Get_IsSpecValid(Spec));
    }

    {
        auto Spec = FCk_Bob_Spec{};
        Spec.Get_Air().Get_Spring().Set_FrequencyHz(0.0f);
        TestFalse(TEXT("spring frequency 0 is invalid"), Get_IsSpecValid(Spec));
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_StrideTarget_PhaseZero_NoDipNoLateral,
    "Ck.Gait.BobKernel.StrideTarget_PhaseZero_NoDipNoLateral", kCkUnitTestFlags)
bool FCk_Bob_StrideTarget_PhaseZero_NoDipNoLateral::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Target = Compute_StrideTarget(FCk_Bob_Spec{}, MakeClock(1.0f, 0.0f, UE_HALF_PI));
    TestTrue(TEXT("location is zero (breath fades at A = 1)"), Target._LocationCm.Equals(FVector::ZeroVector, 1.0e-4));
    TestTrue(TEXT("rotation is zero"), Target._RotationDeg.Equals(FVector::ZeroVector, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_StrideTarget_HalfPi_FullDipAndLateral,
    "Ck.Gait.BobKernel.StrideTarget_HalfPi_FullDipAndLateral", kCkUnitTestFlags)
bool FCk_Bob_StrideTarget_HalfPi_FullDipAndLateral::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Spec = FCk_Bob_Spec{};
    const auto Target = Compute_StrideTarget(Spec, MakeClock(1.0f, UE_HALF_PI));
    TestTrue(TEXT("Z = -VerticalCm"), FMath::IsNearlyEqual(Target._LocationCm.Z, -Spec.Get_Stride().Get_VerticalCm(), 1.0e-4));
    TestTrue(TEXT("Y = LateralCm"), FMath::IsNearlyEqual(Target._LocationCm.Y, Spec.Get_Stride().Get_LateralCm(), 1.0e-4));
    TestTrue(TEXT("X = ForwardCm"), FMath::IsNearlyEqual(Target._LocationCm.X, Spec.Get_Stride().Get_ForwardCm(), 1.0e-4));
    TestTrue(TEXT("Roll = RollDeg"), FMath::IsNearlyEqual(Target._RotationDeg.X, Spec.Get_Stride().Get_RollDeg(), 1.0e-4));
    TestTrue(TEXT("Pitch = -PitchDeg"), FMath::IsNearlyEqual(Target._RotationDeg.Y, -Spec.Get_Stride().Get_PitchDeg(), 1.0e-4));
    TestTrue(TEXT("Yaw = 0"), FMath::IsNearlyEqual(Target._RotationDeg.Z, 0.0, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_StrideTarget_ZeroAmount_BreathOnly,
    "Ck.Gait.BobKernel.StrideTarget_ZeroAmount_BreathOnly", kCkUnitTestFlags)
bool FCk_Bob_StrideTarget_ZeroAmount_BreathOnly::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Spec = FCk_Bob_Spec{};
    const auto Target = Compute_StrideTarget(Spec, MakeClock(0.0f, UE_HALF_PI, UE_HALF_PI));
    TestTrue(TEXT("location is (0, 0, BreathCm)"), Target._LocationCm.Equals(FVector{0, 0, Spec.Get_BreathCm()}, 1.0e-4));
    TestTrue(TEXT("rotation is zero"), Target._RotationDeg.Equals(FVector::ZeroVector, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_StrideTarget_SprintAmount_KeepsBreathOff,
    "Ck.Gait.BobKernel.StrideTarget_SprintAmount_KeepsBreathOff", kCkUnitTestFlags)
bool FCk_Bob_StrideTarget_SprintAmount_KeepsBreathOff::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Spec = FCk_Bob_Spec{};
    const auto SprintClock = MakeClock(1.5f, 0.0f, UE_HALF_PI);
    const auto Target = Compute_StrideTarget(Spec, SprintClock);
    TestTrue(TEXT("sprint breath adds no vertical offset"), FMath::IsNearlyZero(Target._LocationCm.Z, 1.0e-4));
    TestTrue(TEXT("sprint stride remains active"),
        FMath::IsNearlyEqual(Compute_StrideTarget(Spec, MakeClock(1.5f, UE_HALF_PI, UE_HALF_PI))._LocationCm.Z,
            -1.5f * Spec.Get_Stride().Get_VerticalCm(), 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Target_Intensity_ScalesLocationAndRotation,
    "Ck.Gait.BobKernel.Target_Intensity_ScalesLocationAndRotation", kCkUnitTestFlags)
bool FCk_Bob_Target_Intensity_ScalesLocationAndRotation::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Clock = MakeClock(1.0f, UE_HALF_PI);
    const auto Full = FCk_Bob_Spec{};
    auto Half = FCk_Bob_Spec{};
    Half.Set_Intensity(0.5f);

    const auto FullTarget = Compute_Target(Full, Clock, 0.0f);
    const auto HalfTarget = Compute_Target(Half, Clock, 0.0f);
    TestTrue(TEXT("intensity 0.5 halves the location"), HalfTarget._LocationCm.Equals(FullTarget._LocationCm * 0.5, 1.0e-4));
    TestTrue(TEXT("intensity 0.5 halves the rotation"), HalfTarget._RotationDeg.Equals(FullTarget._RotationDeg * 0.5, 1.0e-4));

    const auto Sprung = Compute_Target(Half, Clock, 2.0f);
    TestTrue(TEXT("spring offset 2 is added to Z before intensity"),
        FMath::IsNearlyEqual(Sprung._LocationCm.Z, (-Half.Get_Stride().Get_VerticalCm() + 2.0) * 0.5, 1.0e-4));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Spring_LandKick_DipsThenReturns,
    "Ck.Gait.BobKernel.Spring_LandKick_DipsThenReturns", kCkUnitTestFlags)
bool FCk_Bob_Spring_LandKick_DipsThenReturns::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Response = FCk_Bob_Spec{}.Get_Air().Get_Spring();
    auto State = FSpringState{};
    State._Velocity = -70.0f;

    auto MinObserved = State._Offset;
    for (auto Step = 0; Step < 30; ++Step)
    {
        Step_Spring(State, 0.0f, kFrameSeconds, Response);
        MinObserved = FMath::Min(MinObserved, State._Offset);
    }

    TestTrue(TEXT("the kick dips the spring below -1 cm within 0.5 s"), MinObserved < -1.0f);

    for (auto Step = 30; Step < 180; ++Step)
    { Step_Spring(State, 0.0f, kFrameSeconds, Response); }

    TestTrue(TEXT("the spring returns within 0.05 cm of rest after 3 s"), FMath::Abs(State._Offset) < 0.05f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Spring_LargeDt_StaysBounded,
    "Ck.Gait.BobKernel.Spring_LargeDt_StaysBounded", kCkUnitTestFlags)
bool FCk_Bob_Spring_LargeDt_StaysBounded::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Spec = FCk_Bob_Spec{};
    const auto Response = Spec.Get_Air().Get_Spring();
    const auto Target = Spec.Get_Air().Get_MaxLiftCm();

    auto State = FSpringState{};
    State._Velocity = -Spec.Get_Air().Get_MaxLandKick();
    Step_Spring(State, Target, 5.0f, Response);
    TestTrue(TEXT("one dt = 5 s step stays bounded"), FMath::Abs(State._Offset) <= kSpringRunawayCm);

    auto AlwaysBounded = true;
    for (auto Step = 0; Step < 1000; ++Step)
    {
        Step_Spring(State, Target, 1.0f, Response);
        AlwaysBounded = AlwaysBounded && FMath::IsFinite(State._Offset) && FMath::Abs(State._Offset) <= kSpringRunawayCm;
    }

    TestTrue(TEXT("1000 dt = 1 s steps stay bounded"), AlwaysBounded);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Smooth_ZeroRateSnaps_PositiveRateConverges,
    "Ck.Gait.BobKernel.Smooth_ZeroRateSnaps_PositiveRateConverges", kCkUnitTestFlags)
bool FCk_Bob_Smooth_ZeroRateSnaps_PositiveRateConverges::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    auto Target = FTarget{};
    Target._LocationCm = FVector{1, -2, 3};
    Target._RotationDeg = FVector{4, -5, 6};

    const auto Snapped = Smooth(FTarget{}, Target, 0.0f, kFrameSeconds);
    TestTrue(TEXT("rate 0 snaps the location"), Snapped._LocationCm.Equals(Target._LocationCm, 1.0e-6));
    TestTrue(TEXT("rate 0 snaps the rotation"), Snapped._RotationDeg.Equals(Target._RotationDeg, 1.0e-6));

    auto Current = FTarget{};
    for (auto Step = 0; Step < 120; ++Step)
    { Current = Smooth(Current, Target, 10.0f, kFrameSeconds); }

    TestTrue(TEXT("rate 10 converges the location within 1e-3 over 2 s"), Current._LocationCm.Equals(Target._LocationCm, 1.0e-3));
    TestTrue(TEXT("rate 10 converges the rotation within 1e-3 over 2 s"), Current._RotationDeg.Equals(Target._RotationDeg, 1.0e-3));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Clamp_Location_BoundsMagnitude,
    "Ck.Gait.BobKernel.Clamp_Location_BoundsMagnitude", kCkUnitTestFlags)
bool FCk_Bob_Clamp_Location_BoundsMagnitude::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    TestTrue(TEXT("(30, 0, 0) clamps to (20, 0, 0)"), Clamp_Location(FVector{30, 0, 0}, 20.0f).Equals(FVector{20, 0, 0}, 1.0e-4));
    TestTrue(TEXT("(1, 1, 1) is untouched"), Clamp_Location(FVector{1, 1, 1}, 20.0f).Equals(FVector{1, 1, 1}, 1.0e-6));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Bob_Compose_NodeOffset_IsBobThenRest,
    "Ck.Gait.BobKernel.Compose_NodeOffset_IsBobThenRest", kCkUnitTestFlags)
bool FCk_Bob_Compose_NodeOffset_IsBobThenRest::RunTest(const FString& Parameters)
{
    using namespace ck_test_bob_kernel;
    const auto Rest = FTransform{FVector{0, 0, 64}};

    auto Dip = FTarget{};
    Dip._LocationCm = FVector{0, 0, -2};
    const auto NodeOffset = Compose_NodeOffset(Compose_Offset(Dip), Rest);
    TestTrue(TEXT("bob (0, 0, -2) over rest (0, 0, 64) lands at (0, 0, 62)"), NodeOffset.GetLocation().Equals(FVector{0, 0, 62}, 1.0e-4));

    const auto YawedRest = FTransform{FRotator{0, 90, 0}, FVector{0, 0, 64}};
    auto Lateral = FTarget{};
    Lateral._LocationCm = FVector{0, 10, 0};
    const auto Rotated = Compose_NodeOffset(Compose_Offset(Lateral), YawedRest);
    TestTrue(TEXT("a 90 deg yawed rest turns the bob's +Y lateral into -X"), Rotated.GetLocation().Equals(FVector{-10, 0, 64}, 1.0e-3));
    TestTrue(TEXT("the rest yaw is kept"), FMath::IsNearlyEqual(Rotated.Rotator().Yaw, 90.0, 1.0e-3));
    return true;
}
