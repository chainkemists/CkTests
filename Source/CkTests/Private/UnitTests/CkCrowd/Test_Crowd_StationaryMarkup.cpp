// Pure coverage for the position-window classifier used to paint and remove stationary-agent
// nav markup. World-dependent painting and path detours remain covered by Crowd AutoTests.

#include <limits>

#include "CkCrowd/Agent/CkCrowdAgent_StationaryMarkup_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;
using ck::ck_crowd_agent_stationary_markup_algorithm::IsStationarySample;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_StationaryMarkup_WindowedSpeedThreshold,
    "CkTests.UnitTests.CkCrowd.StationaryMarkup.WindowedSpeedThreshold",
    kCkUnitTestFlags)

bool FCkTest_Crowd_StationaryMarkup_WindowedSpeedThreshold::RunTest(const FString& Parameters)
{
    constexpr auto SampleSeconds = 0.25f;
    constexpr auto DefaultSpeedThreshold = 84.0f;

    TestTrue(TEXT("Movement below the configured speed remains stationary"),
        IsStationarySample(
            FVector::ZeroVector,
            FVector{20.0f, 0.0f, 50.0f},
            SampleSeconds,
            DefaultSpeedThreshold));
    TestTrue(TEXT("The configured boundary remains stationary"),
        IsStationarySample(
            FVector::ZeroVector,
            FVector{21.0f, 0.0f, 50.0f},
            SampleSeconds,
            DefaultSpeedThreshold));
    TestFalse(TEXT("Movement above the configured speed is not stationary"),
        IsStationarySample(
            FVector::ZeroVector,
            FVector{22.0f, 0.0f, 50.0f},
            SampleSeconds,
            DefaultSpeedThreshold));
    TestTrue(TEXT("The classifier uses actual elapsed time rather than a fixed-distance threshold"),
        IsStationarySample(
            FVector::ZeroVector,
            FVector{22.0f, 0.0f, 50.0f},
            0.5f,
            DefaultSpeedThreshold));

    AddExpectedError(
        TEXT("Invalid stationary-markup movement sample"),
        EAutomationExpectedErrorFlags::Contains,
        6);
    const auto NotANumber = std::numeric_limits<float>::quiet_NaN();
    TestFalse(TEXT("A non-finite location fails closed"),
        IsStationarySample(
            FVector{NotANumber, 0.0f, 0.0f},
            FVector::ZeroVector,
            SampleSeconds,
            DefaultSpeedThreshold));
    TestFalse(TEXT("A non-positive sample duration fails closed"),
        IsStationarySample(
            FVector::ZeroVector,
            FVector::ZeroVector,
            0.0f,
            DefaultSpeedThreshold));
    TestFalse(TEXT("A negative speed threshold fails closed"),
        IsStationarySample(
            FVector::ZeroVector,
            FVector::ZeroVector,
            SampleSeconds,
            -1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
