// C++ unit tests for ck::pronav::Compute_FiringSolution — the constant-velocity intercept solver
// (the upgraded replacement for the aim-ahead quadratic).
//
// The defining property of every successful solution: in the shooter's inertial frame, the aim
// point sits exactly ProjectileSpeed·TimeToImpact away from the shooter while coinciding with the
// target's relative position at that time. Each scenario asserts that property plus its edge case.
//
// Surface in Session Frontend: CkTests.UnitTests.CkProjectile.Homing.FiringSolution.<scenario>

#include "Misc/AutomationTest.h"

#include "CkProjectile/Homing/CkHoming_ProNav.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_firing_solution
{
    // Asserts the intercept identity |AimPoint − Shooter| == Speed·T and that the aim point is the
    // target's shooter-relative position at T
    inline auto VerifyInterceptIdentity(
        FAutomationTestBase& InTest,
        const FCk_Homing_FiringSolution& InSolution,
        const FVector& InShooterLocation,
        const FVector& InShooterVelocity,
        const FVector& InTargetLocation,
        const FVector& InTargetVelocity,
        const float InProjectileSpeed) -> void
    {
        const auto Time = InSolution.Get_TimeToImpact().Get_Seconds();

        const auto DistanceToAimPoint = FVector::Dist(InSolution.Get_ImpactLocation(), InShooterLocation);
        const auto ProjectileTravel = InProjectileSpeed * Time;

        InTest.TestTrue(FString::Printf(TEXT("Projectile reaches the aim point exactly at T (%.4f vs %.4f)"),
                DistanceToAimPoint, ProjectileTravel),
            FMath::IsNearlyEqual(DistanceToAimPoint, ProjectileTravel, ProjectileTravel * 0.001 + 1.0e-4));

        const auto RelativeTargetAtTime = InTargetLocation + (InTargetVelocity - InShooterVelocity) * Time;

        InTest.TestTrue(TEXT("Aim point is the target's shooter-relative position at T"),
            InSolution.Get_ImpactLocation().Equals(RelativeTargetAtTime, 1.0e-3));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_StationaryTargetDirectShot,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.StationaryTargetDirectShot",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_StationaryTargetDirectShot::RunTest(const FString& Parameters)
{
    const auto ShooterLocation = FVector{100.0, -200.0, 50.0};
    const auto TargetLocation = FVector{3100.0, 3800.0, 50.0};
    constexpr auto ProjectileSpeed = 500.0f;

    const auto Solution = ck::pronav::Compute_FiringSolution(
        ShooterLocation, FVector::ZeroVector, TargetLocation, FVector::ZeroVector, ProjectileSpeed);

    TestTrue(TEXT("Solution found"), Solution.Get_Result() == ECk_SucceededFailed::Succeeded);
    TestTrue(TEXT("Aim point is the target itself"), Solution.Get_ImpactLocation().Equals(TargetLocation, 1.0e-6));

    const auto ExpectedTime = FVector::Dist(ShooterLocation, TargetLocation) / ProjectileSpeed;
    TestTrue(FString::Printf(TEXT("Time is distance/speed (%.4f vs %.4f)"),
            Solution.Get_TimeToImpact().Get_Seconds(), ExpectedTime),
        FMath::IsNearlyEqual(Solution.Get_TimeToImpact().Get_Seconds(), ExpectedTime, 1.0e-6));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_CrossingTargetLeadsAim,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.CrossingTargetLeadsAim",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_CrossingTargetLeadsAim::RunTest(const FString& Parameters)
{
    const auto ShooterLocation = FVector::ZeroVector;
    const auto TargetLocation = FVector{4000.0, 0.0, 0.0};
    const auto TargetVelocity = FVector{0.0, 600.0, 0.0};
    constexpr auto ProjectileSpeed = 2000.0f;

    const auto Solution = ck::pronav::Compute_FiringSolution(
        ShooterLocation, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed);

    TestTrue(TEXT("Solution found"), Solution.Get_Result() == ECk_SucceededFailed::Succeeded);

    ck_tests_firing_solution::VerifyInterceptIdentity(*this, Solution,
        ShooterLocation, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed);

    TestTrue(TEXT("Aim point leads the target along its velocity"),
        Solution.Get_ImpactLocation().Y > TargetLocation.Y);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_EqualSpeedsLinearRoot,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.EqualSpeedsLinearRoot",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_EqualSpeedsLinearRoot::RunTest(const FString& Parameters)
{
    // Target speed == projectile speed makes the quadratic's leading coefficient vanish —
    // the solver must fall back to the linear root instead of dividing by ~zero
    const auto ShooterLocation = FVector::ZeroVector;
    const auto TargetLocation = FVector{1000.0, 0.0, 0.0};
    const auto TargetVelocity = FVector{-300.0, 0.0, 0.0};
    constexpr auto ProjectileSpeed = 300.0f;

    const auto Solution = ck::pronav::Compute_FiringSolution(
        ShooterLocation, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed);

    TestTrue(TEXT("Linear-root solution found"), Solution.Get_Result() == ECk_SucceededFailed::Succeeded);

    ck_tests_firing_solution::VerifyInterceptIdentity(*this, Solution,
        ShooterLocation, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_TooSlowNoSolution,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.TooSlowNoSolution",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_TooSlowNoSolution::RunTest(const FString& Parameters)
{
    // Target outrunning the projectile straight away — no intercept exists
    const auto Solution = ck::pronav::Compute_FiringSolution(
        FVector::ZeroVector, FVector::ZeroVector,
        FVector{1000.0, 0.0, 0.0}, FVector{500.0, 0.0, 0.0}, 100.0f);

    TestTrue(TEXT("No solution reported"), Solution.Get_Result() == ECk_SucceededFailed::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_MovingShooterMatchesRelativeFrame,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.MovingShooterMatchesRelativeFrame",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_MovingShooterMatchesRelativeFrame::RunTest(const FString& Parameters)
{
    // A moving shooter is exactly equivalent to a stationary shooter with the target velocity
    // shifted into the shooter's frame — the two formulations must agree to the last digit
    const auto ShooterLocation = FVector{500.0, 250.0, 0.0};
    const auto ShooterVelocity = FVector{300.0, -150.0, 25.0};
    const auto TargetLocation = FVector{5500.0, 2250.0, 400.0};
    const auto TargetVelocity = FVector{-200.0, 450.0, 0.0};
    constexpr auto ProjectileSpeed = 1800.0f;

    const auto MovingShooter = ck::pronav::Compute_FiringSolution(
        ShooterLocation, ShooterVelocity, TargetLocation, TargetVelocity, ProjectileSpeed);

    const auto RelativeFrame = ck::pronav::Compute_FiringSolution(
        ShooterLocation, FVector::ZeroVector, TargetLocation, TargetVelocity - ShooterVelocity, ProjectileSpeed);

    TestTrue(TEXT("Both formulations succeed"),
        MovingShooter.Get_Result() == ECk_SucceededFailed::Succeeded &&
        RelativeFrame.Get_Result() == ECk_SucceededFailed::Succeeded);

    TestEqual(TEXT("Aim points are identical"),
        MovingShooter.Get_ImpactLocation(), RelativeFrame.Get_ImpactLocation());
    TestEqual(TEXT("Impact times are identical"),
        MovingShooter.Get_TimeToImpact().Get_Seconds(), RelativeFrame.Get_TimeToImpact().Get_Seconds());

    ck_tests_firing_solution::VerifyInterceptIdentity(*this, MovingShooter,
        ShooterLocation, ShooterVelocity, TargetLocation, TargetVelocity, ProjectileSpeed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_PreferencePicksAmongTwoRoots,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.PreferencePicksAmongTwoRoots",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_PreferencePicksAmongTwoRoots::RunTest(const FString& Parameters)
{
    // A fast target running down a slow projectile's lane crosses the intercept sphere twice —
    // both roots positive: t = 12.5 s (head-on) and t = 50 s (overtaken)
    const auto TargetLocation = FVector{10000.0, 0.0, 0.0};
    const auto TargetVelocity = FVector{-500.0, 0.0, 0.0};
    constexpr auto ProjectileSpeed = 300.0f;

    const auto Earliest = ck::pronav::Compute_FiringSolution(
        FVector::ZeroVector, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed,
        ECk_Homing_InterceptPreference::EarliestIntercept);

    const auto Latest = ck::pronav::Compute_FiringSolution(
        FVector::ZeroVector, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed,
        ECk_Homing_InterceptPreference::LatestIntercept);

    TestTrue(TEXT("Both preferences find a solution"),
        Earliest.Get_Result() == ECk_SucceededFailed::Succeeded &&
        Latest.Get_Result() == ECk_SucceededFailed::Succeeded);

    TestTrue(FString::Printf(TEXT("Earliest root is 12.5 s (got %.4f)"), Earliest.Get_TimeToImpact().Get_Seconds()),
        FMath::IsNearlyEqual(Earliest.Get_TimeToImpact().Get_Seconds(), 12.5, 1.0e-3));
    TestTrue(FString::Printf(TEXT("Latest root is 50 s (got %.4f)"), Latest.Get_TimeToImpact().Get_Seconds()),
        FMath::IsNearlyEqual(Latest.Get_TimeToImpact().Get_Seconds(), 50.0, 1.0e-3));

    for (const auto& Solution : {Earliest, Latest})
    {
        ck_tests_firing_solution::VerifyInterceptIdentity(*this, Solution,
            FVector::ZeroVector, FVector::ZeroVector, TargetLocation, TargetVelocity, ProjectileSpeed);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_StationaryProjectileEdgeCases,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.StationaryProjectileEdgeCases",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_StationaryProjectileEdgeCases::RunTest(const FString& Parameters)
{
    // Zero-speed projectile (a mine): only a target whose path passes through the shooter connects
    const auto ThroughShooter = ck::pronav::Compute_FiringSolution(
        FVector::ZeroVector, FVector::ZeroVector,
        FVector{1000.0, 0.0, 0.0}, FVector{-100.0, 0.0, 0.0}, 0.0f);

    TestTrue(TEXT("Target passing through the shooter connects"),
        ThroughShooter.Get_Result() == ECk_SucceededFailed::Succeeded);
    TestTrue(FString::Printf(TEXT("Contact at t=10 s (got %.4f)"), ThroughShooter.Get_TimeToImpact().Get_Seconds()),
        FMath::IsNearlyEqual(ThroughShooter.Get_TimeToImpact().Get_Seconds(), 10.0, 1.0e-3));

    const auto PassingBy = ck::pronav::Compute_FiringSolution(
        FVector::ZeroVector, FVector::ZeroVector,
        FVector{1000.0, 200.0, 0.0}, FVector{-100.0, 0.0, 0.0}, 0.0f);

    TestTrue(TEXT("Target passing beside the shooter does not connect"),
        PassingBy.Get_Result() == ECk_SucceededFailed::Failed);

    const auto BothStationary = ck::pronav::Compute_FiringSolution(
        FVector::ZeroVector, FVector::ZeroVector,
        FVector{1000.0, 0.0, 0.0}, FVector::ZeroVector, 0.0f);

    TestTrue(TEXT("Both stationary cannot connect"),
        BothStationary.Get_Result() == ECk_SucceededFailed::Failed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_FiringSolution_CoincidentStartImmediateImpact,
    "CkTests.UnitTests.CkProjectile.Homing.FiringSolution.CoincidentStartImmediateImpact",
    kCkUnitTestFlags)

bool FCkTest_FiringSolution_CoincidentStartImmediateImpact::RunTest(const FString& Parameters)
{
    const auto SharedLocation = FVector{42.0, 42.0, 42.0};

    const auto Solution = ck::pronav::Compute_FiringSolution(
        SharedLocation, FVector::ZeroVector, SharedLocation, FVector{100.0, 0.0, 0.0}, 500.0f);

    TestTrue(TEXT("Coincident start is an immediate impact"),
        Solution.Get_Result() == ECk_SucceededFailed::Succeeded);
    TestTrue(TEXT("Time to impact is zero"),
        FMath::IsNearlyZero(Solution.Get_TimeToImpact().Get_Seconds(), 1.0e-9));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
