#include "CkCore/Format/CkFormat.h"

#include "CkJolt/World/CkJoltWorld.h"

#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------
// Pins the fixed-timestep accumulator math (ck::jolt::ComputeStepPlan) BEFORE it is wired into a physics world:
// the pure function is the whole contract for "how many sub-steps fire this frame, what is the interpolation
// alpha, and how much time is dropped under load". No PhysicsSystem, no PIE — feed accumulator + delta, assert
// the plan. Each case pins one property: native-rate single step, sub-threshold accumulation, the max-steps
// clamp (spiral-of-death guard), the zero-dt no-op, and cross-frame time conservation.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_fixedtimestep
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter;

    constexpr int32 FixedHz = 60;
    constexpr int32 MaxSteps = 4;

    // Mirror the product's own FixedDt derivation (1 / max(1, Hz)) so every expectation is expressed in the
    // exact float the function computes internally — the power-of-two ratios below are then bit-exact.
    constexpr float FixedDt = 1.0f / static_cast<float>(FixedHz);
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltWorld_FixedTimestep_SingleStepAtNativeRate,
    "Ck.Jolt.World.FixedTimestep.SingleStepAtNativeRate",
    ck_test_jolt_fixedtimestep::kTestFlags)

bool FCkTest_JoltWorld_FixedTimestep_SingleStepAtNativeRate::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_fixedtimestep;

    const auto Plan = ck::jolt::ComputeStepPlan(0.0f, FixedDt, FixedHz, MaxSteps);

    TestEqual(TEXT("dt = 1/60 at 60Hz yields exactly one step"), Plan.NumSteps, 1);
    TestTrue(TEXT("alpha is ~0 after a clean single step"), FMath::IsNearlyZero(Plan.Alpha, 1e-4f));
    TestTrue(TEXT("accumulator is ~0 after a clean single step"), FMath::IsNearlyZero(Plan.NewAccumulator, 1e-4f));
    TestTrue(TEXT("no time is dropped at the native rate"), Plan.DroppedTime == 0.0f);
    TestTrue(TEXT("pending sim time equals one fixed step"), FMath::IsNearlyEqual(Plan.PendingSimTime, FixedDt, 1e-5f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltWorld_FixedTimestep_SubStepAccumulation,
    "Ck.Jolt.World.FixedTimestep.SubStepAccumulation",
    ck_test_jolt_fixedtimestep::kTestFlags)

bool FCkTest_JoltWorld_FixedTimestep_SubStepAccumulation::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_fixedtimestep;

    // Feed sub-fixed-dt slices (0.005s < 1/60s) and thread the accumulator forward. A step must fire only once
    // the running accumulator crosses a fixed-dt boundary, and alpha must stay in [0,1) on every call.
    constexpr float SmallDt = 0.005f;
    constexpr int32 Iterations = 12;
    constexpr int32 GenerousMaxSteps = 8; // never clamps for a sub-threshold feed

    auto Accumulator = 0.0f;
    auto TotalSteps = 0;
    auto TotalTimeFed = 0.0f;

    for (auto Index = 0; Index < Iterations; ++Index)
    {
        const auto Plan = ck::jolt::ComputeStepPlan(Accumulator, SmallDt, FixedHz, GenerousMaxSteps);

        TotalTimeFed += SmallDt;
        TotalSteps += Plan.NumSteps;

        TestTrue(ck::Format_UE(TEXT("alpha stays in [0,1) on call [{}] (got {})"), Index, Plan.Alpha),
            Plan.Alpha >= 0.0f && Plan.Alpha < 1.0f);
        TestTrue(TEXT("a sub-threshold feed never drops time"), Plan.DroppedTime == 0.0f);

        Accumulator = Plan.NewAccumulator;
    }

    // 12 * 0.005 = 0.06s -> floor(0.06 / (1/60)) = floor(3.6) = 3 steps. Threading the remainder makes the
    // running step total exactly floor(TotalFed / FixedDt).
    const auto ExpectedSteps = FMath::FloorToInt(TotalTimeFed / FixedDt);
    TestEqual(TEXT("steps fire only as the accumulator crosses the fixed dt"), TotalSteps, ExpectedSteps);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltWorld_FixedTimestep_MaxStepsClampDropsExcess,
    "Ck.Jolt.World.FixedTimestep.MaxStepsClampDropsExcess",
    ck_test_jolt_fixedtimestep::kTestFlags)

bool FCkTest_JoltWorld_FixedTimestep_MaxStepsClampDropsExcess::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_fixedtimestep;

    // A 1-second frame at 60Hz would want 60 steps; the max-steps budget clamps it to exactly MaxSteps and the
    // excess is DROPPED (the spiral-of-death guard), not banked into the accumulator.
    const auto Plan = ck::jolt::ComputeStepPlan(0.0f, 1.0f, FixedHz, MaxSteps);

    TestEqual(TEXT("a huge frame clamps to exactly MaxSteps steps"), Plan.NumSteps, MaxSteps);
    TestTrue(TEXT("excess time is dropped, not banked"), Plan.DroppedTime > 0.0f);
    TestTrue(TEXT("no accumulator is carried after a clamped max-step frame"),
        FMath::IsNearlyZero(Plan.NewAccumulator, 1e-4f));

    const auto ExpectedDropped = 1.0f - static_cast<float>(MaxSteps) * FixedDt;
    TestTrue(ck::Format_UE(TEXT("dropped time is ~{} (got {})"), ExpectedDropped, Plan.DroppedTime),
        FMath::IsNearlyEqual(Plan.DroppedTime, ExpectedDropped, 1e-3f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltWorld_FixedTimestep_ZeroDeltaNoStep,
    "Ck.Jolt.World.FixedTimestep.ZeroDeltaNoStep",
    ck_test_jolt_fixedtimestep::kTestFlags)

bool FCkTest_JoltWorld_FixedTimestep_ZeroDeltaNoStep::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_fixedtimestep;

    // A paused frame (dt == 0) must not advance the sim and must leave the accumulator (and therefore alpha)
    // exactly where it was. Start mid-way between two fixed steps.
    const float StartAccumulator = FixedDt * 0.5f;

    const auto Plan = ck::jolt::ComputeStepPlan(StartAccumulator, 0.0f, FixedHz, MaxSteps);

    TestEqual(TEXT("zero dt produces zero steps"), Plan.NumSteps, 0);
    TestTrue(TEXT("zero dt leaves the accumulator unchanged"),
        FMath::IsNearlyEqual(Plan.NewAccumulator, StartAccumulator, 1e-6f));
    TestTrue(TEXT("alpha reflects the unchanged accumulator (~0.5)"),
        FMath::IsNearlyEqual(Plan.Alpha, 0.5f, 1e-4f));
    TestTrue(TEXT("zero dt drops nothing"), Plan.DroppedTime == 0.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltWorld_FixedTimestep_AccumulatorContinuity,
    "Ck.Jolt.World.FixedTimestep.AccumulatorContinuity",
    ck_test_jolt_fixedtimestep::kTestFlags)

bool FCkTest_JoltWorld_FixedTimestep_AccumulatorContinuity::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_fixedtimestep;

    // Conservation across a run of mixed frame deltas: the simulated time (sum of NumSteps * FixedDt), the
    // leftover accumulator, and the dropped time must together account for every second fed in.
    const float MixedDts[] = {0.013f, 0.004f, 0.05f, 0.001f, 0.02f, 0.009f};

    auto Accumulator = 0.0f;
    auto TotalTimeFed = 0.0f;
    auto TotalDropped = 0.0f;
    auto TotalSimulated = 0.0f;

    for (const auto Dt : MixedDts)
    {
        const auto Plan = ck::jolt::ComputeStepPlan(Accumulator, Dt, FixedHz, MaxSteps);

        TotalTimeFed += Dt;
        TotalDropped += Plan.DroppedTime;
        TotalSimulated += Plan.PendingSimTime;

        TestTrue(TEXT("pending sim time equals NumSteps * fixed dt"),
            FMath::IsNearlyEqual(Plan.PendingSimTime, static_cast<float>(Plan.NumSteps) * FixedDt, 1e-5f));
        TestTrue(ck::Format_UE(TEXT("alpha stays in [0,1) for dt {} (got {})"), Dt, Plan.Alpha),
            Plan.Alpha >= 0.0f && Plan.Alpha < 1.0f);

        Accumulator = Plan.NewAccumulator;
    }

    TestTrue(TEXT("simulated + leftover + dropped accounts for all fed time"),
        FMath::IsNearlyEqual(TotalSimulated + Accumulator + TotalDropped, TotalTimeFed, 1e-3f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
