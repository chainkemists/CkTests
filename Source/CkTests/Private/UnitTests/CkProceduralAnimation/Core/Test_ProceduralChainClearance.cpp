#include "CkProceduralAnimation/Core/CkProceduralChainClearance.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_chain_clearance
{
    constexpr auto Tolerance = 1.0e-4;
    const auto Hip = FVector{0.0, 0.0, 0.0};
    const auto Foot = FVector{100.0, 0.0, 0.0};
    const auto Pole = FVector{50.0, 40.0, 0.0};

    auto
        Get_IsSameBits(
            const FVector& InA,
            const FVector& InB)
        -> bool
    {
        return FMemory::Memcmp(&InA, &InB, sizeof(FVector)) == 0;
    }

    auto
        Get_Order(
            float InLastClearDegrees)
        -> TArray<float>
    {
        auto Order = TArray<float>{};
        Order.Init(TNumericLimits<float>::Max(), static_cast<int32>(UE_ARRAY_COUNT(ck::ProceduralPoleSwivelFanDegrees)));
        const auto Count = ck::Get_ProceduralPoleSwivelOrder(InLastClearDegrees, Order);
        Order.SetNum(FMath::Clamp(Count, 0, Order.Num()));
        return Order;
    }

    auto
        Get_OrderText(
            const TArray<float>& InOrder)
        -> FString
    {
        return FString::JoinBy(InOrder, TEXT(", "), [](float InDegrees)
        {
            return FString::Printf(TEXT("%.0f"), InDegrees);
        });
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceSwivelKeepsTheDistanceToTheAxisTest,
    "Ck.ProceduralAnimation.ChainClearance.SwivelKeepsTheDistanceToTheAxis",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceSwivelKeepsTheDistanceToTheAxisTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto Axis = (Foot - Hip).GetSafeNormal();
    for (const auto Degrees : ck::ProceduralPoleSwivelFanDegrees)
    {
        const auto Swivelled = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, Degrees);
        const auto Along = FVector::DotProduct(Swivelled - Hip, Axis);
        const auto FromAxis = (Swivelled - Hip - Axis * Along).Size();
        TestTrue(FString::Printf(TEXT("At %.0f degrees the pole stays 40 cm from the axis (got %.6f)"), Degrees, FromAxis),
            FMath::IsNearlyEqual(FromAxis, 40.0, Tolerance));
        TestTrue(FString::Printf(TEXT("At %.0f degrees the pole projects 50 cm along the axis (got %.6f)"), Degrees, Along),
            FMath::IsNearlyEqual(Along, 50.0, Tolerance));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceSwivelSignIsRightHandedTest,
    "Ck.ProceduralAnimation.ChainClearance.SwivelSignIsRightHanded",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceSwivelSignIsRightHandedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto Swivelled = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 90.0f);
    TestTrue(FString::Printf(TEXT("+90 degrees about +X takes (50, 40, 0) to (50, 0, 40) (got %s)"), *Swivelled.ToString()),
        Swivelled.Equals(FVector{50.0, 0.0, 40.0}, Tolerance));

    const auto Back = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, -90.0f);
    TestTrue(FString::Printf(TEXT("-90 degrees about +X takes (50, 40, 0) to (50, 0, -40) (got %s)"), *Back.ToString()),
        Back.Equals(FVector{50.0, 0.0, -40.0}, Tolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceSwivelZeroAndDegenerateReturnInputTest,
    "Ck.ProceduralAnimation.ChainClearance.SwivelZeroAndDegenerateReturnInput",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceSwivelZeroAndDegenerateReturnInputTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto NaN = std::numeric_limits<double>::quiet_NaN();

    TestTrue(TEXT("0 degrees returns the input pole"), Get_IsSameBits(ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 0.0f), Pole));
    TestTrue(TEXT("A hip on the foot returns the input pole"),
        Get_IsSameBits(ck::ComputeProceduralPoleSwivel(Foot, Foot, Pole, 60.0f), Pole));

    const auto NaNPole = FVector{NaN, 40.0, 0.0};
    TestTrue(TEXT("A NaN pole returns the input pole"), Get_IsSameBits(ck::ComputeProceduralPoleSwivel(Hip, Foot, NaNPole, 60.0f), NaNPole));

    TestTrue(TEXT("Positive control: 60 degrees moves the pole"),
        NOT ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 60.0f).Equals(Pole, 1.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceOrderTriesLastClearFirstTest,
    "Ck.ProceduralAnimation.ChainClearance.OrderTriesLastClearFirst",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceOrderTriesLastClearFirstTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto Fan = TArray<float>{0.0f, 30.0f, -30.0f, 60.0f, -60.0f, 90.0f, -90.0f, 120.0f, -120.0f, 150.0f, -150.0f};

    const auto AfterSixty = Get_Order(60.0f);
    TestTrue(FString::Printf(TEXT("Last clear 60 orders 60, 0, 30, -30, -60, 90, -90, 120, -120, 150, -150 (got %s)"),
        *Get_OrderText(AfterSixty)),
        AfterSixty == TArray<float>{60.0f, 0.0f, 30.0f, -30.0f, -60.0f, 90.0f, -90.0f, 120.0f, -120.0f, 150.0f, -150.0f});

    const auto AfterOneFifty = Get_Order(150.0f);
    TestTrue(FString::Printf(TEXT("Last clear 150 is tried first, then 0 and the fan (got %s)"), *Get_OrderText(AfterOneFifty)),
        AfterOneFifty == TArray<float>{150.0f, 0.0f, 30.0f, -30.0f, 60.0f, -60.0f, 90.0f, -90.0f, 120.0f, -120.0f, -150.0f});

    const auto AfterZero = Get_Order(0.0f);
    TestTrue(FString::Printf(TEXT("Last clear 0 is the fan order (got %s)"), *Get_OrderText(AfterZero)), AfterZero == Fan);

    const auto AfterNonFanAngle = Get_Order(45.0f);
    TestTrue(FString::Printf(TEXT("Last clear 45, not a fan angle, is the fan order (got %s)"), *Get_OrderText(AfterNonFanAngle)),
        AfterNonFanAngle == Fan);

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
