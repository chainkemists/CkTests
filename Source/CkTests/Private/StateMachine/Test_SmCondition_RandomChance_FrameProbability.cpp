// Pins the frame-rate-independence contract of the RandomChance SM condition: _Probability is
// the chance of firing within one second of continuous evaluation, so the per-frame probability
// must compound identically at any tick rate (1 - (1-p)^dt). Before the 2026-07 fix the condition
// re-rolled a raw FMath::FRand() < p every evaluation cycle, so any p converged to "always fires"
// at a frame-rate-dependent speed.
//
// Surface in Session Frontend: Ck.StateMachine.UnitTests.RandomChance.FrameProbability

#include "CkStateMachine/Condition/EntityScripts/CkSmCondition_RandomChance.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_SmCondition_RandomChance_FrameProbability_Test,
    "Ck.StateMachine.UnitTests.RandomChance.FrameProbability",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_SmCondition_RandomChance_FrameProbability_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    using ck::statemachine::Get_RandomChance_FrameProbability;

    constexpr auto Tolerance = 1.0e-4f;

    // Degenerate endpoints.
    TestEqual(TEXT("p=0 never fires regardless of dt"),
        Get_RandomChance_FrameProbability(0.0f, 0.016f), 0.0f, Tolerance);
    TestEqual(TEXT("p=1 fires on the first evaluation"),
        Get_RandomChance_FrameProbability(1.0f, 0.016f), 1.0f, Tolerance);
    TestEqual(TEXT("dt=0 contributes zero probability"),
        Get_RandomChance_FrameProbability(0.5f, 0.0f), 0.0f, Tolerance);
    TestEqual(TEXT("negative dt contributes zero probability"),
        Get_RandomChance_FrameProbability(0.5f, -1.0f), 0.0f, Tolerance);
    TestEqual(TEXT("out-of-range p clamps to [0,1]"),
        Get_RandomChance_FrameProbability(2.0f, 0.016f), 1.0f, Tolerance);

    // One full second of evaluation yields exactly p.
    TestEqual(TEXT("h(p, 1s) == p"),
        Get_RandomChance_FrameProbability(0.3f, 1.0f), 0.3f, Tolerance);

    // Frame-rate invariance: compounding N frames of dt covers the same window as one frame of
    // N*dt. P(not fired) over the window must match: (1-h(dt))^N == 1 - h(N*dt).
    {
        const auto POverHalfSecond = Get_RandomChance_FrameProbability(0.4f, 0.5f);
        const auto NotFiredTwice   = (1.0f - POverHalfSecond) * (1.0f - POverHalfSecond);
        const auto POverOneSecond  = Get_RandomChance_FrameProbability(0.4f, 1.0f);

        TestEqual(TEXT("two 0.5s windows compound to one 1s window"),
            1.0f - NotFiredTwice, POverOneSecond, Tolerance);
    }
    {
        // 60 fps vs 30 fps over the same 1-second window.
        const auto P60 = Get_RandomChance_FrameProbability(0.25f, 1.0f / 60.0f);
        const auto P30 = Get_RandomChance_FrameProbability(0.25f, 1.0f / 30.0f);

        auto NotFired60 = 1.0f;
        for (auto Frame = 0; Frame < 60; ++Frame)
        { NotFired60 *= (1.0f - P60); }

        auto NotFired30 = 1.0f;
        for (auto Frame = 0; Frame < 30; ++Frame)
        { NotFired30 *= (1.0f - P30); }

        TestEqual(TEXT("60fps and 30fps compound to the same 1s fire probability"),
            NotFired60, NotFired30, 1.0e-3f);
        TestEqual(TEXT("...and that probability is (1-p)"),
            NotFired60, 0.75f, 1.0e-3f);
    }

    // Monotonic in dt: a longer window never lowers the fire chance.
    {
        const auto PShort = Get_RandomChance_FrameProbability(0.5f, 0.01f);
        const auto PLong  = Get_RandomChance_FrameProbability(0.5f, 0.1f);
        TestTrue(TEXT("longer window has strictly higher fire probability"), PLong > PShort);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
