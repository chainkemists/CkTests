// C++ unit tests for ck::ballistics — the closed-form Carpentier linear-drag trajectory math
// that underpins lag-compensated projectiles.
//
// These tests are headless (no ticking world): the math is pure (InitialConditions, Params, Time)
// → (Position, Velocity), which is exactly the property that makes projectile paths identical on
// every machine. World-dependent behavior (processors, probes, fast-forward) is covered by the
// AS AutoTest harness instead.
//
// Surface in Session Frontend: CkTests.UnitTests.CkProjectile.Ballistic.<scenario>

#include "Misc/AutomationTest.h"

#include "CkProjectile/Ballistic/CkBallistic_Utils.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_ballistic
{
    // Rifle-round-ish trajectory used across scenarios: fast, flat, draggy
    inline auto Make_RifleTrajectory() -> FCk_Ballistic_TrajectoryParams
    {
        return FCk_Ballistic_TrajectoryParams{FVector{0.0, 0.0, -9000.0}};
    }

    // Lobbed mortar-ish trajectory: slow with a pronounced apex
    inline auto Make_LobbedInitialConditions() -> FCk_Ballistic_InitialConditions
    {
        return FCk_Ballistic_InitialConditions{
            FCk_Time::ZeroSecond(),
            FVector{0.0, 0.0, 200.0},
            FVector{1500.0, 0.0, 2500.0}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Ballistic_InitialConditionsExact,
    "CkTests.UnitTests.CkProjectile.Ballistic.InitialConditionsExact",
    kCkUnitTestFlags)

bool FCkTest_Ballistic_InitialConditionsExact::RunTest(const FString& Parameters)
{
    const auto Params = ck_tests_ballistic::Make_RifleTrajectory();
    const auto StartLocation = FVector{100.0, -250.0, 90.0};
    const auto StartVelocity = FVector{65000.0, 0.0, 1000.0};
    const auto InitialConditions = FCk_Ballistic_InitialConditions{FCk_Time::ZeroSecond(), StartLocation, StartVelocity};

    TestEqual(TEXT("Position at t=0 is exactly the start location"),
        ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time::ZeroSecond()), StartLocation);
    TestEqual(TEXT("Velocity at t=0 is exactly the start velocity"),
        ck::ballistics::Get_VelocityAtTime(InitialConditions, Params, FCk_Time::ZeroSecond()), StartVelocity);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Ballistic_NoDragLimitMatchesParabola,
    "CkTests.UnitTests.CkProjectile.Ballistic.NoDragLimitMatchesParabola",
    kCkUnitTestFlags)

bool FCkTest_Ballistic_NoDragLimitMatchesParabola::RunTest(const FString& Parameters)
{
    // With an enormous terminal velocity, drag vanishes and the closed form must converge to
    // the standard parabola p0 + v0·t + ½·g·t²
    const auto Gravity = FVector{0.0, 0.0, -980.0};
    auto Params = FCk_Ballistic_TrajectoryParams{FVector{0.0, 0.0, -1.0e9}};
    Params.Set_Gravity(Gravity);

    const auto InitialConditions = ck_tests_ballistic::Make_LobbedInitialConditions();

    for (const auto T : {0.25, 1.0, 2.5, 5.0})
    {
        const auto Analytic = ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{T});

        // ½·g·t² arises in the closed form from the k·t·Vinf term, since k·Vinf → ½·g⃗ as the
        // terminal speed grows — the comparison validates both the formula and the k definition
        const auto SimpleParabola = InitialConditions.Get_StartLocation() +
            InitialConditions.Get_StartVelocity() * T + 0.5 * Gravity * T * T;

        TestTrue(FString::Printf(TEXT("t=%.2f closed form matches drag-free parabola within 0.1%% (got %s expected %s)"),
                T, *Analytic.ToString(), *SimpleParabola.ToString()),
            Analytic.Equals(SimpleParabola, SimpleParabola.Size() * 0.001 + 1.0));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Ballistic_VelocityIsDerivativeOfPosition,
    "CkTests.UnitTests.CkProjectile.Ballistic.VelocityIsDerivativeOfPosition",
    kCkUnitTestFlags)

bool FCkTest_Ballistic_VelocityIsDerivativeOfPosition::RunTest(const FString& Parameters)
{
    auto Params = ck_tests_ballistic::Make_RifleTrajectory();
    Params.Set_Wind(FVector{300.0, -150.0, 0.0});

    const auto InitialConditions = ck_tests_ballistic::Make_LobbedInitialConditions();

    constexpr auto H = 1.0e-4;

    for (const auto T : {0.1, 0.5, 1.5, 4.0})
    {
        const auto Analytic = ck::ballistics::Get_VelocityAtTime(InitialConditions, Params, FCk_Time{T});

        const auto Ahead = ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{T + H});
        const auto Behind = ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{T - H});
        const auto CentralDifference = (Ahead - Behind) / (2.0 * H);

        TestTrue(FString::Printf(TEXT("t=%.2f velocity matches d(position)/dt (got %s expected %s)"),
                T, *Analytic.ToString(), *CentralDifference.ToString()),
            Analytic.Equals(CentralDifference, Analytic.Size() * 0.001 + 0.1));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Ballistic_VelocityApproachesTerminal,
    "CkTests.UnitTests.CkProjectile.Ballistic.VelocityApproachesTerminal",
    kCkUnitTestFlags)

bool FCkTest_Ballistic_VelocityApproachesTerminal::RunTest(const FString& Parameters)
{
    auto Params = ck_tests_ballistic::Make_RifleTrajectory();
    Params.Set_Wind(FVector{500.0, 250.0, 0.0});

    // Convergence is polynomial, not exponential: v(t) = Vinf + (v0 − Vinf)/(1+kt)².
    // With k ≈ 0.054 here, t=600s gives (1+kt)² ≈ 1100, i.e. ~0.1% residual — well inside 1%
    const auto InitialConditions = ck_tests_ballistic::Make_LobbedInitialConditions();
    const auto LateVelocity = ck::ballistics::Get_VelocityAtTime(InitialConditions, Params, FCk_Time{600.0});
    const auto TerminalWithWind = Params.Get_TerminalVelocityWithWind();

    TestTrue(FString::Printf(TEXT("Velocity at t=600s converges to terminal+wind within 1%% (got %s expected %s)"),
            *LateVelocity.ToString(), *TerminalWithWind.ToString()),
        LateVelocity.Equals(TerminalWithWind, TerminalWithWind.Size() * 0.01));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Ballistic_TimeOfFlightInvertsPosition,
    "CkTests.UnitTests.CkProjectile.Ballistic.TimeOfFlightInvertsPosition",
    kCkUnitTestFlags)

bool FCkTest_Ballistic_TimeOfFlightInvertsPosition::RunTest(const FString& Parameters)
{
    // The lobbed trajectory apexes around t≈2s on Z — samples on both sides exercise the
    // quadratic's two-root disambiguation via the current-velocity hint
    const auto Params = ck_tests_ballistic::Make_RifleTrajectory();
    const auto InitialConditions = ck_tests_ballistic::Make_LobbedInitialConditions();

    for (const auto T : {0.1, 0.75, 1.9, 2.6, 4.5, 8.0})
    {
        const auto Position = ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{T});
        const auto Velocity = ck::ballistics::Get_VelocityAtTime(InitialConditions, Params, FCk_Time{T});

        const auto RecoveredTime = ck::ballistics::Get_TimeOfFlightTo(InitialConditions, Params, Position, Velocity);

        TestTrue(FString::Printf(TEXT("t=%.2f recovered from position (got %.6f)"), T, RecoveredTime.Get_Seconds()),
            FMath::IsNearlyEqual(RecoveredTime.Get_Seconds(), T, T * 0.001 + 1.0e-4));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Ballistic_EvaluationIsStateless,
    "CkTests.UnitTests.CkProjectile.Ballistic.EvaluationIsStateless",
    kCkUnitTestFlags)

bool FCkTest_Ballistic_EvaluationIsStateless::RunTest(const FString& Parameters)
{
    // The determinism guarantee behind lag compensation: position is a pure function of
    // (initial conditions, time). Evaluation order and intermediate sampling must not matter —
    // results are bitwise identical
    const auto Params = ck_tests_ballistic::Make_RifleTrajectory();
    const auto InitialConditions = ck_tests_ballistic::Make_LobbedInitialConditions();

    const auto DirectEvaluation = ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{2.0});

    // Simulate a different machine sampling the trajectory at a different tick rate first
    for (auto Step = 1; Step <= 33; ++Step)
    {
        ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{Step * 0.0613});
    }

    const auto AfterIntermediateSampling = ck::ballistics::Get_PositionAtTime(InitialConditions, Params, FCk_Time{2.0});

    TestEqual(TEXT("Evaluation at t=2.0 is bitwise identical regardless of prior sampling"),
        AfterIntermediateSampling, DirectEvaluation);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
