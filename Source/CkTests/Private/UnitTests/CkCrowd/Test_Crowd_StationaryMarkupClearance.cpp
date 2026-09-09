// The strict GroundNav verdict and PathRefresh detours use this same centreline rule. It is
// deliberately a pure check: runtime confirmation and path installation are covered by AutoTests.

#include "CkCrowd/Agent/CkCrowdAgent_PathRefresh_Processor.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_StationaryMarkupClearance_QueryingAgentExpandsConfirmedDisc,
    "CkTests.UnitTests.CkCrowd.StationaryMarkup.Clearance.QueryingAgentExpandsConfirmedDisc",
    kCkUnitTestFlags)

bool FCkTest_Crowd_StationaryMarkupClearance_QueryingAgentExpandsConfirmedDisc::RunTest(
    const FString& InParameters)
{
    constexpr auto MarkupRadiusUu = 84.0f;
    constexpr auto QueryingAgentRadiusUu = 42.0f;
    constexpr auto RequiredCentreClearanceUu = MarkupRadiusUu + QueryingAgentRadiusUu;

    const auto MarkupCentre = FVector::ZeroVector;

    TestTrue(TEXT("a 42uu walker rejects a line 125uu from an 84uu confirmed disc"),
        ck::FProcessor_CrowdAgent_PathRefresh::Get_DoesSegmentCrossStationaryMarkup(
            FVector{-100.0, 125.0, 0.0}, FVector{100.0, 125.0, 0.0}, MarkupCentre,
            MarkupRadiusUu, QueryingAgentRadiusUu));

    TestFalse(TEXT("the 126uu tangent is clear for the same walker"),
        ck::FProcessor_CrowdAgent_PathRefresh::Get_DoesSegmentCrossStationaryMarkup(
            FVector{-100.0, RequiredCentreClearanceUu, 0.0},
            FVector{100.0, RequiredCentreClearanceUu, 0.0}, MarkupCentre,
            MarkupRadiusUu, QueryingAgentRadiusUu));

    TestFalse(TEXT("a line beyond the combined 126uu radius remains clear"),
        ck::FProcessor_CrowdAgent_PathRefresh::Get_DoesSegmentCrossStationaryMarkup(
            FVector{-100.0, 127.0, 0.0}, FVector{100.0, 127.0, 0.0}, MarkupCentre,
            MarkupRadiusUu, QueryingAgentRadiusUu));

    return true;
}
