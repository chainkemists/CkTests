// Pure C++ coverage for the tight-corridor predicate behind the sampler's corridor stand-down.
// These assertions do not instantiate an ECS world or processor; the stand-down's behavioural
// effect is covered by the Crowd NarrowGap AutoTests.

#include "CkCrowd/Agent/CkCrowdAgent_AvoidanceSample_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_tight_corridor
{
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FWallSegment;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FWallSegments;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::Is_InTightCorridor;

    constexpr auto kAgentRadius = 42.0f;
    constexpr auto kSlackCm = 40.0f;   // threshold = 2*42 + 40 = 124

    const auto kAgentAtOrigin = FVector::ZeroVector;

    auto MakeWall(const FVector& InStart, const FVector& InEnd) -> FWallSegment
    {
        return FWallSegment{InStart, InEnd, false};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_TightCorridor_BracketingWallsUnderThreshold,
    "CkTests.UnitTests.CkCrowd.TightCorridor.BracketingWallsUnderThreshold",
    kCkUnitTestFlags)
auto FCkTest_Crowd_TightCorridor_BracketingWallsUnderThreshold::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_tight_corridor;

    // Two parallel walls along X, 110 apart, agent centred between them: 55 + 55 = 110 < 124.
    auto Walls = FWallSegments{};
    Walls.Emplace(MakeWall(FVector{-200.0, 55.0, 0.0}, FVector{200.0, 55.0, 0.0}));
    Walls.Emplace(MakeWall(FVector{-200.0, -55.0, 0.0}, FVector{200.0, -55.0, 0.0}));

    TestTrue(TEXT("110cm corridor around a 42cm agent is tight"),
        Is_InTightCorridor(kAgentAtOrigin, kAgentRadius, kSlackCm, Walls));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_TightCorridor_WideCorridorDoesNotTrigger,
    "CkTests.UnitTests.CkCrowd.TightCorridor.WideCorridorDoesNotTrigger",
    kCkUnitTestFlags)
auto FCkTest_Crowd_TightCorridor_WideCorridorDoesNotTrigger::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_tight_corridor;

    // Same shape, 200 apart: 100 + 100 = 200 >= 124.
    auto Walls = FWallSegments{};
    Walls.Emplace(MakeWall(FVector{-200.0, 100.0, 0.0}, FVector{200.0, 100.0, 0.0}));
    Walls.Emplace(MakeWall(FVector{-200.0, -100.0, 0.0}, FVector{200.0, -100.0, 0.0}));

    TestFalse(TEXT("200cm corridor is not tight"),
        Is_InTightCorridor(kAgentAtOrigin, kAgentRadius, kSlackCm, Walls));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_TightCorridor_HuggingOneWallOfAWideCorridor,
    "CkTests.UnitTests.CkCrowd.TightCorridor.HuggingOneWallOfAWideCorridorDoesNotTrigger",
    kCkUnitTestFlags)
auto FCkTest_Crowd_TightCorridor_HuggingOneWallOfAWideCorridor::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_tight_corridor;

    // Agent 10 from one wall, 190 from the other: near ONE wall is not "in a pinch".
    auto Walls = FWallSegments{};
    Walls.Emplace(MakeWall(FVector{-200.0, 10.0, 0.0}, FVector{200.0, 10.0, 0.0}));
    Walls.Emplace(MakeWall(FVector{-200.0, -190.0, 0.0}, FVector{200.0, -190.0, 0.0}));

    TestFalse(TEXT("hugging one wall of a 200cm corridor is not tight"),
        Is_InTightCorridor(kAgentAtOrigin, kAgentRadius, kSlackCm, Walls));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_TightCorridor_SameSideWallsDoNotTrigger,
    "CkTests.UnitTests.CkCrowd.TightCorridor.SameSideWallsDoNotTrigger",
    kCkUnitTestFlags)
auto FCkTest_Crowd_TightCorridor_SameSideWallsDoNotTrigger::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_tight_corridor;

    // Two collinear-ish segments of the SAME wall face (both at +Y): directions to them agree,
    // so no pair opposes even though both are close.
    auto Walls = FWallSegments{};
    Walls.Emplace(MakeWall(FVector{-200.0, 50.0, 0.0}, FVector{-10.0, 50.0, 0.0}));
    Walls.Emplace(MakeWall(FVector{10.0, 50.0, 0.0}, FVector{200.0, 50.0, 0.0}));

    TestFalse(TEXT("two segments of one wall face are not a corridor"),
        Is_InTightCorridor(kAgentAtOrigin, kAgentRadius, kSlackCm, Walls));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_TightCorridor_ConvexCornerDoesNotTrigger,
    "CkTests.UnitTests.CkCrowd.TightCorridor.ConvexCornerDoesNotTrigger",
    kCkUnitTestFlags)
auto FCkTest_Crowd_TightCorridor_ConvexCornerDoesNotTrigger::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_tight_corridor;

    // A corner: one wall ahead (+X), one beside (+Y), both close. Directions to them are
    // perpendicular (dot 0 > -0.5) — rounding a corner is not a pinch.
    auto Walls = FWallSegments{};
    Walls.Emplace(MakeWall(FVector{50.0, -200.0, 0.0}, FVector{50.0, 200.0, 0.0}));
    Walls.Emplace(MakeWall(FVector{-200.0, 50.0, 0.0}, FVector{200.0, 50.0, 0.0}));

    TestFalse(TEXT("a convex corner's two faces are not a corridor"),
        Is_InTightCorridor(kAgentAtOrigin, kAgentRadius, kSlackCm, Walls));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_TightCorridor_DoorwayJambsTrigger,
    "CkTests.UnitTests.CkCrowd.TightCorridor.DoorwayJambsTrigger",
    kCkUnitTestFlags)
auto FCkTest_Crowd_TightCorridor_DoorwayJambsTrigger::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_tight_corridor;

    // Short jamb segments either side of a 110cm doorway the agent stands in.
    auto Walls = FWallSegments{};
    Walls.Emplace(MakeWall(FVector{-30.0, 55.0, 0.0}, FVector{30.0, 55.0, 0.0}));
    Walls.Emplace(MakeWall(FVector{-30.0, -55.0, 0.0}, FVector{30.0, -55.0, 0.0}));

    TestTrue(TEXT("a 110cm doorway's jambs are a pinch"),
        Is_InTightCorridor(kAgentAtOrigin, kAgentRadius, kSlackCm, Walls));
    return true;
}
