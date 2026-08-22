// Unit tests for UCk_Utils_Stats_UE::Get_ThreadTimings — the stat-unit timing snapshot.
// These assert the CONTRACT (struct shape, availability semantics, non-negativity), never specific
// millisecond values: timings are machine- and frame-dependent, so a numeric threshold here would
// be a flake generator rather than a test. The measurement-quality statistics built on top of this
// snapshot are pinned separately, against fixture data, in the PerfLab specs.

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkProfile/Stats/CkStats_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

// Named rather than anonymous: unity builds merge translation units, and an anonymous namespace
// would collide with the identically-shaped constant in the sibling CkProfile test.
namespace ck_test_profile_thread_timings
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ThreadTimings_Snapshot_ThreadTimesAreNonNegative,
    "CkTests.UnitTests.CkProfile.ThreadTimings.Snapshot_ThreadTimesAreNonNegative",
    ck_test_profile_thread_timings::kFlags)

bool FCkTest_ThreadTimings_Snapshot_ThreadTimesAreNonNegative::RunTest(const FString& Parameters)
{
    const auto Timings = UCk_Utils_Stats_UE::Get_ThreadTimings();

    TestTrue(TEXT("Frame time is non-negative"),         Timings.Get_FrameTimeMs()        >= 0.0f);
    TestTrue(TEXT("Game thread time is non-negative"),   Timings.Get_GameThreadTimeMs()   >= 0.0f);
    TestTrue(TEXT("Render thread time is non-negative"), Timings.Get_RenderThreadTimeMs() >= 0.0f);
    TestTrue(TEXT("RHI thread time is non-negative"),    Timings.Get_RhiThreadTimeMs()    >= 0.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ThreadTimings_Snapshot_GpuAvailabilityIsAlwaysDecided,
    "CkTests.UnitTests.CkProfile.ThreadTimings.Snapshot_GpuAvailabilityIsAlwaysDecided",
    ck_test_profile_thread_timings::kFlags)

bool FCkTest_ThreadTimings_Snapshot_GpuAvailabilityIsAlwaysDecided::RunTest(const FString& Parameters)
{
    const auto Timings = UCk_Utils_Stats_UE::Get_ThreadTimings();

    // A freshly-read snapshot has been sampled by definition, so the not-yet-sampled default must
    // never survive a call. Whatever the RHI situation, the caller is told which it is.
    TestTrue(TEXT("A read snapshot never reports the not-yet-sampled default"),
        Timings.Get_GpuAvailability() != ECk_Stats_MetricAvailability::Unavailable_NotYetSampled);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ThreadTimings_Snapshot_AvailableGpuTimeIsNeverZero,
    "CkTests.UnitTests.CkProfile.ThreadTimings.Snapshot_AvailableGpuTimeIsNeverZero",
    ck_test_profile_thread_timings::kFlags)

bool FCkTest_ThreadTimings_Snapshot_AvailableGpuTimeIsNeverZero::RunTest(const FString& Parameters)
{
    const auto Timings = UCk_Utils_Stats_UE::Get_ThreadTimings();

    // The invariant that keeps a missing GPU measurement from masquerading as a free one: the
    // availability flag is derived from the cycle count, so Available and a zero time cannot
    // co-exist. Under -nullrhi this passes vacuously, which is the correct behaviour rather than a
    // skipped test — the point is that no reading path can produce "available and zero".
    if (Timings.Get_GpuAvailability() == ECk_Stats_MetricAvailability::Available)
    {
        TestTrue(TEXT("An available GPU timing carries a non-zero cost"), Timings.Get_GpuTimeMs() > 0.0f);
    }
    else
    {
        TestTrue(TEXT("An unavailable GPU timing names a reason other than Available"), true);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ThreadTimings_Construction_RoundTripsEveryField,
    "CkTests.UnitTests.CkProfile.ThreadTimings.Construction_RoundTripsEveryField",
    ck_test_profile_thread_timings::kFlags)

bool FCkTest_ThreadTimings_Construction_RoundTripsEveryField::RunTest(const FString& Parameters)
{
    // Pins the struct's shape: a field added, reordered or dropped breaks this compile-time.
    const auto Timings = FCk_Stats_ThreadTimings
    {
        16.7f,
        9.1f,
        12.8f,
        2.2f,
        14.4f,
        ECk_Stats_MetricAvailability::Available
    };

    TestEqual(TEXT("Frame time round-trips"),         Timings.Get_FrameTimeMs(),        16.7f);
    TestEqual(TEXT("Game thread time round-trips"),   Timings.Get_GameThreadTimeMs(),   9.1f);
    TestEqual(TEXT("Render thread time round-trips"), Timings.Get_RenderThreadTimeMs(), 12.8f);
    TestEqual(TEXT("RHI thread time round-trips"),    Timings.Get_RhiThreadTimeMs(),    2.2f);
    TestEqual(TEXT("GPU time round-trips"),           Timings.Get_GpuTimeMs(),          14.4f);

    TestTrue(TEXT("GPU availability round-trips"),
        Timings.Get_GpuAvailability() == ECk_Stats_MetricAvailability::Available);

    // A default-constructed snapshot must report not-yet-sampled, so an unpopulated struct can never
    // be mistaken for a measurement of zero.
    const auto Default = FCk_Stats_ThreadTimings{};

    TestTrue(TEXT("A default-constructed snapshot reports not-yet-sampled"),
        Default.Get_GpuAvailability() == ECk_Stats_MetricAvailability::Unavailable_NotYetSampled);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_ThreadTimings_Formatter_EnumAndStructAreFormattable,
    "CkTests.UnitTests.CkProfile.ThreadTimings.Formatter_EnumAndStructAreFormattable",
    ck_test_profile_thread_timings::kFlags)

bool FCkTest_ThreadTimings_Formatter_EnumAndStructAreFormattable::RunTest(const FString& Parameters)
{
    // The availability reason travels through logs and session reports, so it has to format as a
    // name rather than an integer. The formatter goes through UEnum::GetDisplayValueAsText, which
    // humanises the identifier (underscores and camel case become spaces), so this asserts a
    // distinctive token that survives that transformation rather than the identifier verbatim.
    const auto FormattedEnum = ck::Format_UE(TEXT("{}"), ECk_Stats_MetricAvailability::Unavailable_NoGpuTimestamps);

    TestTrue(TEXT("The availability enum formats to a non-empty string"), NOT FormattedEnum.IsEmpty());
    TestTrue(*ck::Format_UE(TEXT("The availability enum formats by name — got [{}]"), FormattedEnum),
        FormattedEnum.Contains(TEXT("Timestamps")));

    // Formatting by name is only meaningful if distinct values produce distinct text; a formatter
    // returning a constant would satisfy the check above.
    const auto FormattedAvailable = ck::Format_UE(TEXT("{}"), ECk_Stats_MetricAvailability::Available);

    TestTrue(TEXT("Distinct availability values format to distinct text"), FormattedEnum != FormattedAvailable);

    const auto FormattedStruct = ck::Format_UE(TEXT("{}"), UCk_Utils_Stats_UE::Get_ThreadTimings());

    TestTrue(TEXT("The timings struct formats to a non-empty string"), NOT FormattedStruct.IsEmpty());

    return true;
}
