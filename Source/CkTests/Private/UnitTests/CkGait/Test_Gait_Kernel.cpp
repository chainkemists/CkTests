#include "Misc/AutomationTest.h"
#include "Misc/ScopeExit.h"

#include "CkGait/Gait/CkGait_Kernel.h"
#include "CkGait/Gait/CkGait_Processor.h"
#include "CkGait/Gait/CkGait_Utils.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "../CkUnitTest_Common.h"

#include "GameFramework/FloatingPawnMovement.h"
#include "UObject/StrongObjectPtr.h"

#include <limits>

namespace ck_test_gait_kernel
{
    using namespace ck::gait;

    inline constexpr auto kFrameSeconds = 1.0f / 60.0f;

    auto MakeMotion(const FVector& InVelocity, ECk_Gait_Footing InFooting = ECk_Gait_Footing::Grounded, ECk_Gait_Stance InStance = ECk_Gait_Stance::Standing) -> FCk_Gait_Motion
    {
        return FCk_Gait_Motion{InVelocity, InFooting, InStance};
    }

    auto StepFor(FClockState& InOutState, const FCk_Gait_Spec& InSpec, const FCk_Gait_Motion& InMotion, float InSeconds) -> void
    {
        const auto Steps = FMath::RoundToInt(InSeconds / kFrameSeconds);
        for (auto Step = 0; Step < Steps; ++Step)
        { Step_Clock(InOutState, InSpec, InMotion, kFrameSeconds); }
    }
}

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Spec_DefaultTunables_AreValid,
    "Ck.Gait.Kernel.Spec_DefaultTunables_AreValid", kCkUnitTestFlags)
bool FCk_Gait_Spec_DefaultTunables_AreValid::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    TestTrue(TEXT("default tunables are valid"), Get_AreTunablesValid(FCk_Gait_Spec{}));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Spec_ZeroReferenceSpeed_IsInvalid,
    "Ck.Gait.Kernel.Spec_ZeroReferenceSpeed_IsInvalid", kCkUnitTestFlags)
bool FCk_Gait_Spec_ZeroReferenceSpeed_IsInvalid::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    {
        auto Spec = FCk_Gait_Spec{};
        Spec.Get_Stride().Set_ReferenceSpeed(0.0f);
        TestFalse(TEXT("zero reference speed is invalid"), Get_AreTunablesValid(Spec));
    }

    {
        auto Spec = FCk_Gait_Spec{};
        Spec.Get_Stride().Set_StridesPerSecond(std::numeric_limits<float>::quiet_NaN());
        TestFalse(TEXT("NaN strides per second is invalid"), Get_AreTunablesValid(Spec));
    }

    {
        auto Spec = FCk_Gait_Spec{};
        Spec.Get_Stride().Set_CrouchScale(1.5f);
        TestFalse(TEXT("crouch scale 1.5 is invalid"), Get_AreTunablesValid(Spec));
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_AtRest_AmountStaysZero_PhaseTurnsAtMinCadence,
    "Ck.Gait.Kernel.Step_AtRest_AmountStaysZero_PhaseTurnsAtMinCadence", kCkUnitTestFlags)
bool FCk_Gait_Step_AtRest_AmountStaysZero_PhaseTurnsAtMinCadence::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Spec = FCk_Gait_Spec{};
    auto State = FClockState{};
    for (auto Step = 0; Step < 60; ++Step)
    { Step_Clock(State, Spec, Get_RestMotion(), kFrameSeconds); }

    const auto ExpectedPhase = Wrap_Phase(kTwoPi * 1.6f * 0.35f * 1.0f);
    const auto ExpectedBreath = kTwoPi / 3.6f;
    TestEqual(TEXT("amount stays 0 at rest"), State._Amount, 0.0f);
    TestTrue(TEXT("phase turned at 2pi * 1.6 * 0.35 over 1 s"), FMath::IsNearlyEqual(State._Phase, ExpectedPhase, 1.0e-3f));
    TestTrue(TEXT("breath phase turned at 2pi / 3.6 over 1 s"), FMath::IsNearlyEqual(State._BreathPhase, ExpectedBreath, 1.0e-3f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_AtReferenceSpeed_AmountApproachesOne_PhaseRateIsStrides,
    "Ck.Gait.Kernel.Step_AtReferenceSpeed_AmountApproachesOne_PhaseRateIsStrides", kCkUnitTestFlags)
bool FCk_Gait_Step_AtReferenceSpeed_AmountApproachesOne_PhaseRateIsStrides::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Spec = FCk_Gait_Spec{};
    const auto Motion = MakeMotion(FVector{420, 0, 0});

    auto State = FClockState{};
    StepFor(State, Spec, Motion, 3.0f);
    TestTrue(TEXT("amount > 0.99 after 3 s at the reference speed"), State._Amount > 0.99f);
    TestTrue(TEXT("speed ratio is 1"), FMath::IsNearlyEqual(State._SpeedRatio, 1.0f, 1.0e-4f));

    auto OneStep = FClockState{};
    Step_Clock(OneStep, Spec, Motion, kFrameSeconds);
    TestTrue(TEXT("one step advances the phase by 2pi * 1.6 * dt"), FMath::IsNearlyEqual(OneStep._Phase, kTwoPi * 1.6f * kFrameSeconds, 1.0e-5f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_Crouched_ScalesAmountTarget,
    "Ck.Gait.Kernel.Step_Crouched_ScalesAmountTarget", kCkUnitTestFlags)
bool FCk_Gait_Step_Crouched_ScalesAmountTarget::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    auto State = FClockState{};
    StepFor(State, FCk_Gait_Spec{}, MakeMotion(FVector{420, 0, 0}, ECk_Gait_Footing::Grounded, ECk_Gait_Stance::Crouched), 3.0f);
    TestTrue(TEXT("crouched amount settles at 0.6"), FMath::IsNearlyEqual(State._Amount, 0.6f, 0.01f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_AboveReference_AmountCapsAtMaxScale,
    "Ck.Gait.Kernel.Step_AboveReference_AmountCapsAtMaxScale", kCkUnitTestFlags)
bool FCk_Gait_Step_AboveReference_AmountCapsAtMaxScale::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    auto State = FClockState{};
    StepFor(State, FCk_Gait_Spec{}, MakeMotion(FVector{4200, 0, 0}), 3.0f);
    TestTrue(TEXT("amount caps at MaxAmountScale 1.5"), FMath::IsNearlyEqual(State._Amount, 1.5f, 0.01f));
    TestTrue(TEXT("amount never exceeds 1.5"), State._Amount <= 1.5f + 1.0e-4f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_Airborne_GroundSpeedIsZero_AmountDecays,
    "Ck.Gait.Kernel.Step_Airborne_GroundSpeedIsZero_AmountDecays", kCkUnitTestFlags)
bool FCk_Gait_Step_Airborne_GroundSpeedIsZero_AmountDecays::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Spec = FCk_Gait_Spec{};
    const auto Airborne = MakeMotion(FVector{420, 0, -600}, ECk_Gait_Footing::Airborne);
    TestEqual(TEXT("airborne ground speed is 0"), Compute_GroundSpeed(Airborne), 0.0f);

    auto State = FClockState{};
    StepFor(State, Spec, MakeMotion(FVector{420, 0, 0}), 3.0f);
    const auto AmountBefore = State._Amount;

    StepFor(State, Spec, Airborne, 0.5f);
    TestTrue(TEXT("airborne speed ratio is 0"), FMath::IsNearlyEqual(State._SpeedRatio, 0.0f));
    TestTrue(TEXT("amount decayed while airborne"), State._Amount < AmountBefore * 0.1f);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_NonFiniteGroundSpeed_RestsAndRecovers,
    "Ck.Gait.Kernel.Step_NonFiniteGroundSpeed_RestsAndRecovers", kCkUnitTestFlags)
bool FCk_Gait_Step_NonFiniteGroundSpeed_RestsAndRecovers::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Spec = FCk_Gait_Spec{};
    const auto Moving = MakeMotion(FVector{420, 0, 0});
    for (const auto InvalidSpeed : {std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::infinity()})
    {
        auto State = FClockState{};
        StepFor(State, Spec, Moving, 3.0f);
        const auto MovingAmount = State._Amount;
        const auto InvalidMotion = MakeMotion(FVector{InvalidSpeed, 0, 0});
        Step_Clock(State, Spec, InvalidMotion, kFrameSeconds);
        TestEqual(TEXT("non-finite ground speed produces a zero speed ratio"), State._SpeedRatio, 0.0f);
        TestTrue(TEXT("amount relaxes toward rest"), State._Amount < MovingAmount);
        TestTrue(TEXT("clock remains finite"),
            FMath::IsFinite(State._Amount) && FMath::IsFinite(State._Phase) && FMath::IsFinite(State._BreathPhase));

        const auto RestingAmount = State._Amount;
        Step_Clock(State, Spec, Moving, kFrameSeconds);
        TestTrue(TEXT("finite speed restores the speed ratio"), FMath::IsNearlyEqual(State._SpeedRatio, 1.0f, 1.0e-4f));
        TestTrue(TEXT("amount starts recovering on the next finite frame"), State._Amount > RestingAmount);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Processor_NonFiniteVelocity_RestsAndRecovers,
    "Ck.Gait.Processor.NonFiniteVelocity_RestsAndRecovers", kCkUnitTestFlags)
bool FCk_Gait_Processor_NonFiniteVelocity_RestsAndRecovers::RunTest(const FString& Parameters)
{
    auto Registry = ck::registry_table::EnttRegistryType{};
    const auto Slot = ck::registry_table::Allocate(&Registry);
    ON_SCOPE_EXIT { ck::registry_table::Free(Slot); };

    const TStrongObjectPtr<UFloatingPawnMovement> Movement{NewObject<UFloatingPawnMovement>(GetTransientPackage())};
    if (NOT TestTrue(TEXT("movement source is valid"), Movement.IsValid()))
    { return false; }

    auto Owner = FCk_Handle{FCk_Entity{Registry.create()}, Slot};
    auto Gait = UCk_Utils_Gait_UE::Add(Owner, FCk_Gait_Spec{Movement.Get(), FCk_Gait_StrideParams{}});
    if (NOT TestTrue(TEXT("public Gait Add registers a valid feature"), ck::IsValid(Gait)
        && Gait.Has_All<ck::FFragment_Gait_Tunables, ck::FFragment_Gait>()))
    { return false; }

    auto Tick = [&]()
    {
        ck::FProcessor_Gait_Update::ForEachEntity(FCk_Time{ck_test_gait_kernel::kFrameSeconds}, Gait,
            Gait.Get<ck::FFragment_Gait_Tunables>(), Gait.Get<ck::FFragment_Gait>());
    };

    Movement->Velocity = FVector{420, 0, 0};
    Tick();
    TestTrue(TEXT("finite movement is sampled before rejection"),
        UCk_Utils_Gait_UE::Get_LastMotion(Gait).Get_Velocity().Equals(Movement->Velocity));
    const auto AmountBefore = UCk_Utils_Gait_UE::Get_Amount(Gait);

    AddExpectedError(TEXT("sampled a non-finite velocity"), EAutomationExpectedErrorFlags::Contains, 2);
    Movement->Velocity = FVector{std::numeric_limits<double>::quiet_NaN(), 0, 0};
    Tick();
    const auto RestMotion = UCk_Utils_Gait_UE::Get_LastMotion(Gait);
    TestTrue(TEXT("rejected velocity publishes zero motion"), RestMotion.Get_Velocity().Equals(FVector::ZeroVector));
    TestEqual(TEXT("rejected velocity publishes grounded footing"), RestMotion.Get_Footing(), ECk_Gait_Footing::Grounded);
    TestEqual(TEXT("rejected velocity publishes standing stance"), RestMotion.Get_Stance(), ECk_Gait_Stance::Standing);
    TestEqual(TEXT("rejected velocity has zero speed ratio"), UCk_Utils_Gait_UE::Get_SpeedRatio(Gait), 0.0f);
    TestTrue(TEXT("rejected sample keeps clock finite"),
        FMath::IsFinite(UCk_Utils_Gait_UE::Get_Amount(Gait))
            && FMath::IsFinite(UCk_Utils_Gait_UE::Get_Phase(Gait))
            && FMath::IsFinite(UCk_Utils_Gait_UE::Get_BreathPhase(Gait)));
    TestTrue(TEXT("rejected sample relaxes amount"), UCk_Utils_Gait_UE::Get_Amount(Gait) < AmountBefore);

    const auto RestingAmount = UCk_Utils_Gait_UE::Get_Amount(Gait);
    Movement->Velocity = FVector{420, 0, 0};
    Tick();
    TestTrue(TEXT("finite follow-up publishes motion"),
        UCk_Utils_Gait_UE::Get_LastMotion(Gait).Get_Velocity().Equals(Movement->Velocity));
    TestTrue(TEXT("finite follow-up restores speed ratio"),
        FMath::IsNearlyEqual(UCk_Utils_Gait_UE::Get_SpeedRatio(Gait), 1.0f, 1.0e-4f));
    TestTrue(TEXT("finite follow-up grows amount"), UCk_Utils_Gait_UE::Get_Amount(Gait) > RestingAmount);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Step_NonPositiveDt_NoChange,
    "Ck.Gait.Kernel.Step_NonPositiveDt_NoChange", kCkUnitTestFlags)
bool FCk_Gait_Step_NonPositiveDt_NoChange::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Spec = FCk_Gait_Spec{};
    const auto Motion = MakeMotion(FVector{420, 0, 0});

    auto State = FClockState{};
    StepFor(State, Spec, Motion, 0.5f);
    const auto Before = State;

    Step_Clock(State, Spec, Motion, 0.0f);
    TestTrue(TEXT("dt = 0 leaves the state bit-identical"), FMemory::Memcmp(&State, &Before, sizeof(FClockState)) == 0);
    Step_Clock(State, Spec, Motion, -1.0f);
    TestTrue(TEXT("dt = -1 leaves the state bit-identical"), FMemory::Memcmp(&State, &Before, sizeof(FClockState)) == 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Detect_Landing_AirborneToGrounded_ReportsImpact,
    "Ck.Gait.Kernel.Detect_Landing_AirborneToGrounded_ReportsImpact", kCkUnitTestFlags)
bool FCk_Gait_Detect_Landing_AirborneToGrounded_ReportsImpact::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Landing = Detect_Landing(MakeMotion(FVector{0, 0, -600}, ECk_Gait_Footing::Airborne), MakeMotion(FVector::ZeroVector));
    if (NOT TestTrue(TEXT("landing is set"), Landing.IsSet()))
    { return false; }

    TestTrue(TEXT("impact speed is 600"), FMath::IsNearlyEqual(Landing.GetValue(), 600.0f, 1.0e-3f));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCk_Gait_Detect_Landing_NoEdge_IsUnset,
    "Ck.Gait.Kernel.Detect_Landing_NoEdge_IsUnset", kCkUnitTestFlags)
bool FCk_Gait_Detect_Landing_NoEdge_IsUnset::RunTest(const FString& Parameters)
{
    using namespace ck_test_gait_kernel;
    const auto Grounded = MakeMotion(FVector::ZeroVector);
    const auto Airborne = MakeMotion(FVector{0, 0, -600}, ECk_Gait_Footing::Airborne);
    TestFalse(TEXT("grounded -> grounded is unset"), Detect_Landing(Grounded, Grounded).IsSet());
    TestFalse(TEXT("airborne -> airborne is unset"), Detect_Landing(Airborne, Airborne).IsSet());
    TestFalse(TEXT("grounded -> airborne is unset"), Detect_Landing(Grounded, Airborne).IsSet());
    return true;
}
