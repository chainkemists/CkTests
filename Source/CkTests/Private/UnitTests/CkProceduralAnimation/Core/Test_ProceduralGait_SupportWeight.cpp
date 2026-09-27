#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_support_weight
{
    constexpr auto Tolerance = 1.0e-4f;

    auto
        MakeFoot(
            ECk_ProceduralLeg_FootPhase InPhase,
            float InSwingAlpha,
            ECk_ProceduralLeg_FootContact InContact)
        -> FCk_ProceduralLeg_Foot
    {
        return FCk_ProceduralLeg_Foot{}.Set_Phase(InPhase).Set_SwingAlpha(InSwingAlpha).Set_Contact(InContact);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitSupportWeightOfAnUntrustedSwingTest,
    "Ck.ProceduralAnimation.Gait.SupportWeightOfAnUntrustedSwingFadesToNothing",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitSupportWeightOfAnUntrustedSwingTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_support_weight;
    using ck_procedural_gait_utils::Get_SupportWeight;

    TestTrue(TEXT("A trusted plant weighs 1"),
        FMath::IsNearlyEqual(Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Planted, 0.0f, ECk_ProceduralLeg_FootContact::Trusted)), 1.0f, Tolerance));
    TestTrue(TEXT("An untrusted plant weighs 0"),
        FMath::IsNearlyEqual(Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Planted, 0.0f, ECk_ProceduralLeg_FootContact::Guessed)), 0.0f, Tolerance));

    TestTrue(TEXT("A swing toward trusted ground fades back in to 1 at touchdown"),
        FMath::IsNearlyEqual(Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Swinging, 1.0f, ECk_ProceduralLeg_FootContact::Trusted)), 1.0f, Tolerance));
    TestTrue(TEXT("A swing toward untrusted ground fades in to nothing, as its plant will weigh nothing"),
        FMath::IsNearlyEqual(Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Swinging, 1.0f, ECk_ProceduralLeg_FootContact::Guessed)), 0.0f, Tolerance));

    TestTrue(TEXT("The fade-out over the first third does not depend on the target's trust"),
        FMath::IsNearlyEqual(Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Swinging, 0.1f, ECk_ProceduralLeg_FootContact::Guessed)),
            Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Swinging, 0.1f, ECk_ProceduralLeg_FootContact::Trusted)), Tolerance));
    TestTrue(TEXT("Mid-swing a foot weighs nothing either way"),
        FMath::IsNearlyEqual(Get_SupportWeight(MakeFoot(ECk_ProceduralLeg_FootPhase::Swinging, 0.5f, ECk_ProceduralLeg_FootContact::Trusted)), 0.0f, Tolerance));

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
