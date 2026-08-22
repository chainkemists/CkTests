// Unit tests for the spread statistics in ck::algo — variance, standard deviation, coefficient of
// variation, and the projected sum. Exact values against hand-computed fixtures.

#include "Misc/AutomationTest.h"

#include "CkCore/Algorithms/CkAlgorithms.h"
#include "CkCore/Macros/CkMacros.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_algorithms_spread
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    constexpr auto kTolerance = 1e-6;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Spread_KnownValues,
    "CkTests.UnitTests.CkCore.Spread.KnownValues",
    ck_test_algorithms_spread::kFlags)

bool FCkTest_Spread_KnownValues::RunTest(const FString& Parameters)
{
    // Mean 4; deviations -2,-1,0,1,2; squares 4,1,0,1,4; population variance 10/5 = 2.
    const auto Values = TArray<float>{2.0f, 3.0f, 4.0f, 5.0f, 6.0f};

    TestEqual(TEXT("Population variance"), *ck::algo::Variance(Values), 2.0, ck_test_algorithms_spread::kTolerance);
    TestEqual(TEXT("Standard deviation is its square root"),
        *ck::algo::StandardDeviation(Values), FMath::Sqrt(2.0), ck_test_algorithms_spread::kTolerance);
    TestEqual(TEXT("Coefficient of variation is deviation over mean"),
        *ck::algo::CoefficientOfVariation(Values), FMath::Sqrt(2.0) / 4.0, ck_test_algorithms_spread::kTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Spread_IdenticalValuesHaveNone,
    "CkTests.UnitTests.CkCore.Spread.IdenticalValuesHaveNone",
    ck_test_algorithms_spread::kFlags)

bool FCkTest_Spread_IdenticalValuesHaveNone::RunTest(const FString& Parameters)
{
    auto Values = TArray<float>{};
    Values.Init(9.0f, 12);

    TestEqual(TEXT("Identical values have zero variance"),
        *ck::algo::Variance(Values), 0.0, ck_test_algorithms_spread::kTolerance);
    TestEqual(TEXT("Identical values have zero relative spread"),
        *ck::algo::CoefficientOfVariation(Values), 0.0, ck_test_algorithms_spread::kTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Spread_UndefinedCasesAreUnsetNotZero,
    "CkTests.UnitTests.CkCore.Spread.UndefinedCasesAreUnsetNotZero",
    ck_test_algorithms_spread::kFlags)

bool FCkTest_Spread_UndefinedCasesAreUnsetNotZero::RunTest(const FString& Parameters)
{
    const auto Empty = TArray<float>{};

    TestFalse(TEXT("Variance of nothing is unset"),            ck::algo::Variance(Empty).IsSet());
    TestFalse(TEXT("Standard deviation of nothing is unset"),  ck::algo::StandardDeviation(Empty).IsSet());
    TestFalse(TEXT("Relative spread of nothing is unset"),     ck::algo::CoefficientOfVariation(Empty).IsSet());

    // A relative spread around a mean of zero has no meaning; reporting it as unset is the honest
    // answer, where returning zero would claim the values were steady.
    const auto AroundZero = TArray<float>{-5.0f, 5.0f};

    TestTrue (TEXT("Values around zero still have a variance"), ck::algo::Variance(AroundZero).IsSet());
    TestFalse(TEXT("...but no meaningful relative spread"),     ck::algo::CoefficientOfVariation(AroundZero).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Spread_SumByProjects,
    "CkTests.UnitTests.CkCore.Spread.SumByProjects",
    ck_test_algorithms_spread::kFlags)

bool FCkTest_Spread_SumByProjects::RunTest(const FString& Parameters)
{
    const auto Values = TArray<int32>{1, 2, 3, 4};

    TestEqual(TEXT("SumBy sums the projection"),
        ck::algo::SumBy(Values, [](int32 InValue) { return InValue * 10; }), 100.0, ck_test_algorithms_spread::kTolerance);

    // Unlike an average, a sum of nothing has an unambiguous answer, so this one is a value rather
    // than an optional.
    TestEqual(TEXT("SumBy of nothing is zero"),
        ck::algo::SumBy(TArray<int32>{}, [](int32 InValue) { return InValue; }), 0.0, ck_test_algorithms_spread::kTolerance);

    return true;
}
