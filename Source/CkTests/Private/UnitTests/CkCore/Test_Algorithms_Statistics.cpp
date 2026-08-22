// Unit tests for the summary statistics in ck::algo. Each asserts an exact value against a
// hand-computed fixture: these are pure functions of their input, so there is nothing here that
// justifies a tolerance beyond floating-point representation.

#include "Misc/AutomationTest.h"

#include "CkCore/Algorithms/CkAlgorithms.h"
#include "CkCore/Macros/CkMacros.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_algorithms_statistics
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    constexpr auto kTolerance = 1e-6;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Statistics_Empty_IsUnsetNotZero,
    "CkTests.UnitTests.CkCore.Statistics.Empty_IsUnsetNotZero",
    ck_test_algorithms_statistics::kFlags)

bool FCkTest_Statistics_Empty_IsUnsetNotZero::RunTest(const FString& Parameters)
{
    const auto Empty = TArray<float>{};

    // Zero is a legitimate statistic, so "nothing to measure" has to be a different thing entirely.
    TestFalse(TEXT("Mean of nothing is unset"),     ck::algo::Mean(Empty).IsSet());
    TestFalse(TEXT("Median of nothing is unset"),   ck::algo::Median(Empty).IsSet());
    TestFalse(TEXT("Percentile of nothing is unset"), ck::algo::Percentile(Empty, 0.5).IsSet());
    TestFalse(TEXT("MAD of nothing is unset"),      ck::algo::MedianAbsoluteDeviation(Empty).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Statistics_KnownValues,
    "CkTests.UnitTests.CkCore.Statistics.KnownValues",
    ck_test_algorithms_statistics::kFlags)

bool FCkTest_Statistics_KnownValues::RunTest(const FString& Parameters)
{
    const auto Values = TArray<float>{1.0f, 2.0f, 3.0f, 4.0f, 5.0f};

    TestEqual(TEXT("Mean of 1..5"),   *ck::algo::Mean(Values),   3.0, ck_test_algorithms_statistics::kTolerance);
    TestEqual(TEXT("Median of 1..5"), *ck::algo::Median(Values), 3.0, ck_test_algorithms_statistics::kTolerance);

    // An even count has no middle element, so the median interpolates between the two straddling it.
    const auto Even = TArray<float>{1.0f, 2.0f, 3.0f, 4.0f};
    TestEqual(TEXT("Median of 1..4 interpolates"), *ck::algo::Median(Even), 2.5, ck_test_algorithms_statistics::kTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Statistics_PercentileBoundsAndAgreement,
    "CkTests.UnitTests.CkCore.Statistics.PercentileBoundsAndAgreement",
    ck_test_algorithms_statistics::kFlags)

bool FCkTest_Statistics_PercentileBoundsAndAgreement::RunTest(const FString& Parameters)
{
    const auto Values = TArray<float>{10.0f, 20.0f, 30.0f, 40.0f, 50.0f};

    TestEqual(TEXT("The 0th percentile is the minimum"), *ck::algo::Percentile(Values, 0.0), 10.0, ck_test_algorithms_statistics::kTolerance);
    TestEqual(TEXT("The 100th percentile is the maximum"), *ck::algo::Percentile(Values, 1.0), 50.0, ck_test_algorithms_statistics::kTolerance);

    // The documented relationship between the two entry points, pinned so it cannot quietly drift.
    TestEqual(TEXT("The 50th percentile agrees with the median"),
        *ck::algo::Percentile(Values, 0.5), *ck::algo::Median(Values), ck_test_algorithms_statistics::kTolerance);

    // Out-of-range fractions clamp rather than reading off the end of the array.
    TestEqual(TEXT("A negative fraction clamps to the minimum"), *ck::algo::Percentile(Values, -1.0), 10.0, ck_test_algorithms_statistics::kTolerance);
    TestEqual(TEXT("A fraction above one clamps to the maximum"), *ck::algo::Percentile(Values, 5.0), 50.0, ck_test_algorithms_statistics::kTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Statistics_MadResistsTheOutlierItFinds,
    "CkTests.UnitTests.CkCore.Statistics.MadResistsTheOutlierItFinds",
    ck_test_algorithms_statistics::kFlags)

bool FCkTest_Statistics_MadResistsTheOutlierItFinds::RunTest(const FString& Parameters)
{
    // Five tight values and one wild one. The mean is dragged upward; the median and the MAD are
    // not — which is exactly why outlier detection uses the latter pair.
    const auto Values = TArray<float>{10.0f, 10.0f, 10.0f, 10.0f, 10.0f, 1000.0f};

    TestTrue (TEXT("The mean is dragged by the outlier"),   *ck::algo::Mean(Values) > 100.0);
    TestEqual(TEXT("The median ignores the outlier"),       *ck::algo::Median(Values), 10.0, ck_test_algorithms_statistics::kTolerance);
    TestEqual(TEXT("The MAD ignores the outlier"),          *ck::algo::MedianAbsoluteDeviation(Values), 0.0, ck_test_algorithms_statistics::kTolerance);

    // ...and that zero is the documented trap: a MAD of zero does NOT mean the set has no spread,
    // only that most of it agrees. The mean form is what still sees the outlier, which is why it
    // exists as the fallback.
    TestTrue(TEXT("The mean absolute deviation still sees the outlier"),
        *ck::algo::MeanAbsoluteDeviation(Values) > 100.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Statistics_TrulySpreadless_IsZeroByBothMeasures,
    "CkTests.UnitTests.CkCore.Statistics.TrulySpreadless_IsZeroByBothMeasures",
    ck_test_algorithms_statistics::kFlags)

bool FCkTest_Statistics_TrulySpreadless_IsZeroByBothMeasures::RunTest(const FString& Parameters)
{
    // The one case where zero spread is the honest answer, and both measures agree on it.
    auto Values = TArray<float>{};
    Values.Init(7.0f, 20);

    TestEqual(TEXT("MAD of identical values is zero"),
        *ck::algo::MedianAbsoluteDeviation(Values), 0.0, ck_test_algorithms_statistics::kTolerance);
    TestEqual(TEXT("Mean absolute deviation of identical values is zero"),
        *ck::algo::MeanAbsoluteDeviation(Values), 0.0, ck_test_algorithms_statistics::kTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Statistics_CallerContainerIsNotReordered,
    "CkTests.UnitTests.CkCore.Statistics.CallerContainerIsNotReordered",
    ck_test_algorithms_statistics::kFlags)

bool FCkTest_Statistics_CallerContainerIsNotReordered::RunTest(const FString& Parameters)
{
    // These sort internally; a caller passing a deliberately ordered array must get it back intact.
    auto Values = TArray<float>{5.0f, 1.0f, 3.0f};

    const auto Median     = ck::algo::Median(Values);
    const auto Percentile = ck::algo::Percentile(Values, 0.9);
    const auto Mad        = ck::algo::MedianAbsoluteDeviation(Values);

    TestTrue(TEXT("All three produced a result"), Median.IsSet() && Percentile.IsSet() && Mad.IsSet());

    TestEqual(TEXT("The first element is untouched"),  Values[0], 5.0f);
    TestEqual(TEXT("The second element is untouched"), Values[1], 1.0f);
    TestEqual(TEXT("The third element is untouched"),  Values[2], 3.0f);

    return true;
}
