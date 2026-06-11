// C++ unit tests for ck::pronav — the proportional-navigation guidance math behind the Homing
// feature.
//
// These tests are headless (no ticking world): the guidance law is a pure mapping of
// (GuidanceState, Kinematics, Settings, DeltaT) → Acceleration. Closed-loop scenarios integrate
// the law by hand to prove intercept behavior; world-dependent behavior (processors, signals)
// is covered by the AS AutoTest harness instead.
//
// Surface in Session Frontend: CkTests.UnitTests.CkProjectile.Homing.<scenario>

#include "Misc/AutomationTest.h"

#include "CkProjectile/Homing/CkHoming_ProNav.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_homing
{
    struct FSimConfig
    {
        FVector PursuerLocation = FVector::ZeroVector;
        FVector PursuerVelocity = FVector::ZeroVector;
        FVector TargetLocation = FVector::ZeroVector;
        FVector TargetVelocity = FVector::ZeroVector;
        FCk_Homing_GuidanceSettings Settings = FCk_Homing_GuidanceSettings{2000.0f};
        FVector ExternalAcceleration = FVector::ZeroVector;
        TFunction<FVector(double)> TargetAcceleration;
        double DeltaT = 1.0 / 120.0;
        double MaxTime = 30.0;
        double SpeedClamp = 0.0;

        // When > 0, the sim ends as soon as the pursuer gets this close — assertions then measure
        // the approach itself, not the post-flyby turnaround dynamics
        double StopAtDistance = 0.0;
    };

    struct FSimResult
    {
        double MinMissDistance = TNumericLimits<double>::Max();
        double TimeOfClosestApproach = 0.0;
        double MaxAbsZ = 0.0;
        bool Intercepted = false;
    };

    // Hand-integrated closed loop: each step evaluates the guidance law exactly the way the
    // Homing processor will (external + homing acceleration → velocity → position)
    inline auto Simulate(const FSimConfig& InConfig) -> FSimResult
    {
        auto PursuerLocation = InConfig.PursuerLocation;
        auto PursuerVelocity = InConfig.PursuerVelocity;
        auto TargetLocation = InConfig.TargetLocation;
        auto TargetVelocity = InConfig.TargetVelocity;
        auto Settings = InConfig.Settings;

        const auto InitialDesiredTimeToImpact = Settings.Get_DesiredTimeToImpact().Get_Seconds();

        auto Result = FSimResult{};

        for (auto Time = 0.0; Time < InConfig.MaxTime; Time += InConfig.DeltaT)
        {
            if (Settings.Get_ImpactTiming() == ECk_Homing_ImpactTiming::ArriveAtDesiredTime)
            {
                Settings.Set_DesiredTimeToImpact(FCk_Time{InitialDesiredTimeToImpact - Time});
            }

            const auto Kinematics = FCk_Homing_Kinematics{
                PursuerLocation, PursuerVelocity, TargetLocation, TargetVelocity};
            const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

            const auto HomingAcceleration = ck::pronav::Compute_HomingAcceleration(
                State, Kinematics, Settings, InConfig.ExternalAcceleration, FCk_Time{InConfig.DeltaT});

            PursuerVelocity += (InConfig.ExternalAcceleration + HomingAcceleration) * InConfig.DeltaT;

            if (InConfig.SpeedClamp > 0.0)
            {
                PursuerVelocity = PursuerVelocity.GetClampedToMaxSize(InConfig.SpeedClamp);
            }

            PursuerLocation += PursuerVelocity * InConfig.DeltaT;

            if (InConfig.TargetAcceleration)
            {
                TargetVelocity += InConfig.TargetAcceleration(Time) * InConfig.DeltaT;
            }

            TargetLocation += TargetVelocity * InConfig.DeltaT;

            const auto Distance = FVector::Dist(PursuerLocation, TargetLocation);

            if (Distance < Result.MinMissDistance)
            {
                Result.MinMissDistance = Distance;
                Result.TimeOfClosestApproach = Time;
            }

            Result.MaxAbsZ = FMath::Max(Result.MaxAbsZ, FMath::Abs(PursuerLocation.Z));

            if (InConfig.StopAtDistance > 0.0 && Distance < InConfig.StopAtDistance)
            {
                Result.Intercepted = true;
                break;
            }
        }

        return Result;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_GuidanceStateMatchesDefinition,
    "CkTests.UnitTests.CkProjectile.Homing.GuidanceStateMatchesDefinition",
    kCkUnitTestFlags)

bool FCkTest_Homing_GuidanceStateMatchesDefinition::RunTest(const FString& Parameters)
{
    const auto Kinematics = FCk_Homing_Kinematics{
        FVector{0.0, 0.0, 0.0}, FVector{500.0, 100.0, 0.0},
        FVector{2000.0, 500.0, 300.0}, FVector{-100.0, 250.0, 50.0}};

    const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

    const auto LineOfSight = Kinematics.Get_TargetLocation() - Kinematics.Get_PursuerLocation();

    TestTrue(TEXT("LOS direction is the normalized pursuer→target vector"),
        State.Get_LineOfSightDirection().Equals(LineOfSight.GetSafeNormal(), 1.0e-9));
    TestTrue(TEXT("LOS distance is |target − pursuer|"),
        FMath::IsNearlyEqual(State.Get_LineOfSightDistance(), LineOfSight.Size(), 1.0e-6));

    const auto RelativeVelocity = Kinematics.Get_TargetVelocity() - Kinematics.Get_PursuerVelocity();
    const auto ExpectedClosingSpeed = -RelativeVelocity.Dot(State.Get_LineOfSightDirection());

    TestTrue(TEXT("Closing speed is the negated range rate"),
        FMath::IsNearlyEqual(State.Get_ClosingSpeed(), ExpectedClosingSpeed, 1.0e-6));

    // The analytic Ω must match the finite-difference rotation of the LOS over a tiny step
    constexpr auto H = 1.0e-5;
    const auto LineOfSightAfterStep =
        (Kinematics.Get_TargetLocation() + Kinematics.Get_TargetVelocity() * H) -
        (Kinematics.Get_PursuerLocation() + Kinematics.Get_PursuerVelocity() * H);

    const auto DirectionBefore = LineOfSight.GetSafeNormal();
    const auto DirectionAfter = LineOfSightAfterStep.GetSafeNormal();

    const auto FiniteDifferenceAngularSpeed =
        FMath::Acos(FMath::Clamp(DirectionBefore.Dot(DirectionAfter), -1.0, 1.0)) / H;

    // The cross of two near-identical unit vectors is ~ω·H in length (1e-6 here) — far below
    // GetSafeNormal's default squared-length tolerance, which would zero it out. Normalize manually
    const auto FiniteDifferenceCross = DirectionBefore.Cross(DirectionAfter);
    const auto FiniteDifferenceAxis = FiniteDifferenceCross / FiniteDifferenceCross.Size();

    const auto AnalyticAngularSpeed = State.Get_LineOfSightAngularVelocity().Size();

    TestTrue(FString::Printf(TEXT("|Ω| matches finite-difference LOS rotation rate (got %.8f expected %.8f)"),
            AnalyticAngularSpeed, FiniteDifferenceAngularSpeed),
        FMath::IsNearlyEqual(AnalyticAngularSpeed, FiniteDifferenceAngularSpeed, FiniteDifferenceAngularSpeed * 0.001));

    TestTrue(TEXT("Ω axis matches the finite-difference rotation axis"),
        State.Get_LineOfSightAngularVelocity().GetSafeNormal().Dot(FiniteDifferenceAxis) > 0.999);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_TrueProNavPerpendicularToLOS,
    "CkTests.UnitTests.CkProjectile.Homing.TrueProNavPerpendicularToLOS",
    kCkUnitTestFlags)

bool FCkTest_Homing_TrueProNavPerpendicularToLOS::RunTest(const FString& Parameters)
{
    const auto Kinematics = FCk_Homing_Kinematics{
        FVector{0.0, 0.0, 0.0}, FVector{900.0, 0.0, 0.0},
        FVector{3000.0, 1500.0, -400.0}, FVector{0.0, -350.0, 120.0}};

    const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

    constexpr auto Gain = 4.0f;
    const auto Acceleration = ck::pronav::Compute_TrueProNav_Acceleration(State, Gain);

    TestTrue(TEXT("True ProNav acceleration is perpendicular to the LOS"),
        FMath::IsNearlyZero(Acceleration.Dot(State.Get_LineOfSightDirection()), 1.0e-6 * Acceleration.Size() + 1.0e-9));

    // Ω is always perpendicular to the LOS, so |Ω × R̂| = |Ω| and the classical N·ω·Vc holds exactly
    const auto ExpectedMagnitude = Gain *
        State.Get_LineOfSightAngularVelocity().Size() * State.Get_ClosingSpeed();

    TestTrue(FString::Printf(TEXT("Magnitude is N·ω·Vc (got %.6f expected %.6f)"),
            Acceleration.Size(), ExpectedMagnitude),
        FMath::IsNearlyEqual(Acceleration.Size(), ExpectedMagnitude, ExpectedMagnitude * 0.001));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_PureProNavPerpendicularToVelocity,
    "CkTests.UnitTests.CkProjectile.Homing.PureProNavPerpendicularToVelocity",
    kCkUnitTestFlags)

bool FCkTest_Homing_PureProNavPerpendicularToVelocity::RunTest(const FString& Parameters)
{
    const auto Kinematics = FCk_Homing_Kinematics{
        FVector{0.0, 0.0, 0.0}, FVector{700.0, 250.0, -100.0},
        FVector{2500.0, -900.0, 600.0}, FVector{150.0, 300.0, 0.0}};

    const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

    const auto Acceleration = ck::pronav::Compute_PureProNav_Acceleration(
        State, Kinematics.Get_PursuerVelocity(), 4.0f);

    // a = N·(Ω × V) is perpendicular to V by construction — speed is preserved to first order
    TestTrue(TEXT("Pure ProNav acceleration is perpendicular to the velocity"),
        FMath::IsNearlyZero(Acceleration.Dot(Kinematics.Get_PursuerVelocity()),
            1.0e-6 * Acceleration.Size() * Kinematics.Get_PursuerVelocity().Size() + 1.0e-9));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_GravityCompensationKeepsCourse,
    "CkTests.UnitTests.CkProjectile.Homing.GravityCompensationKeepsCourse",
    kCkUnitTestFlags)

bool FCkTest_Homing_GravityCompensationKeepsCourse::RunTest(const FString& Parameters)
{
    // Target dead ahead, no LOS rotation — the entire commanded acceleration must be the
    // counter to gravity's perpendicular component, leaving (external + homing) along the velocity
    const auto Kinematics = FCk_Homing_Kinematics{
        FVector{0.0, 0.0, 0.0}, FVector{800.0, 0.0, 0.0},
        FVector{5000.0, 0.0, 0.0}, FVector::ZeroVector};

    const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

    auto Settings = FCk_Homing_GuidanceSettings{3000.0f};
    Settings.Set_SpeedControl(ECk_Homing_SpeedControl::TurnOnly);

    const auto Gravity = FVector{0.0, 0.0, -980.0};

    const auto Acceleration = ck::pronav::Compute_HomingAcceleration(
        State, Kinematics, Settings, Gravity, FCk_Time{1.0 / 60.0});

    const auto TotalApplied = Acceleration + Gravity;
    const auto VelocityDirection = Kinematics.Get_PursuerVelocity().GetSafeNormal();
    const auto TotalPerpendicular = TotalApplied - TotalApplied.Dot(VelocityDirection) * VelocityDirection;

    TestTrue(FString::Printf(TEXT("Total applied acceleration has no off-course component (got %s)"),
            *TotalPerpendicular.ToString()),
        TotalPerpendicular.IsNearlyZero(1.0e-6));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_AccelerationClampedToBudget,
    "CkTests.UnitTests.CkProjectile.Homing.AccelerationClampedToBudget",
    kCkUnitTestFlags)

bool FCkTest_Homing_AccelerationClampedToBudget::RunTest(const FString& Parameters)
{
    // Violent LOS rotation at point-blank range — the commanded acceleration must never
    // exceed the budget in either speed-control mode
    const auto Kinematics = FCk_Homing_Kinematics{
        FVector{0.0, 0.0, 0.0}, FVector{2000.0, 0.0, 0.0},
        FVector{150.0, 80.0, 0.0}, FVector{0.0, -4000.0, 500.0}};

    const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

    constexpr auto MaxAcceleration = 1500.0f;

    for (const auto SpeedControl : {ECk_Homing_SpeedControl::TurnOnly, ECk_Homing_SpeedControl::TurnAndThrust})
    {
        auto Settings = FCk_Homing_GuidanceSettings{MaxAcceleration};
        Settings.Set_SpeedControl(SpeedControl);
        Settings.Set_NavigationGain(5.0f);

        const auto Acceleration = ck::pronav::Compute_HomingAcceleration(
            State, Kinematics, Settings, FVector{0.0, 0.0, -980.0}, FCk_Time{1.0 / 60.0});

        TestTrue(FString::Printf(TEXT("Mode %d acceleration %.2f within budget %.2f"),
                static_cast<int32>(SpeedControl), Acceleration.Size(), MaxAcceleration),
            Acceleration.Size() <= MaxAcceleration * 1.0001);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_DeadOnCourseThrustsAlongLOS,
    "CkTests.UnitTests.CkProjectile.Homing.DeadOnCourseThrustsAlongLOS",
    kCkUnitTestFlags)

bool FCkTest_Homing_DeadOnCourseThrustsAlongLOS::RunTest(const FString& Parameters)
{
    // Zero LOS rotation and no external forces — TurnAndThrust should pour the whole budget
    // into closing the distance
    const auto Kinematics = FCk_Homing_Kinematics{
        FVector{0.0, 0.0, 0.0}, FVector{600.0, 0.0, 0.0},
        FVector{4000.0, 0.0, 0.0}, FVector::ZeroVector};

    const auto State = ck::pronav::Compute_GuidanceState(Kinematics);

    constexpr auto MaxAcceleration = 2000.0f;
    const auto Settings = FCk_Homing_GuidanceSettings{MaxAcceleration};

    const auto Acceleration = ck::pronav::Compute_HomingAcceleration(
        State, Kinematics, Settings, FVector::ZeroVector, FCk_Time{1.0 / 60.0});

    TestTrue(FString::Printf(TEXT("Acceleration is MaxAcceleration along the LOS (got %s)"), *Acceleration.ToString()),
        Acceleration.Equals(MaxAcceleration * State.Get_LineOfSightDirection(), 1.0e-3));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopCrossingTargetIntercepts,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopCrossingTargetIntercepts",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopCrossingTargetIntercepts::RunTest(const FString& Parameters)
{
    auto Config = ck_tests_homing::FSimConfig{};
    Config.PursuerVelocity = FVector{600.0, 0.0, 0.0};
    Config.TargetLocation = FVector{3000.0, 2000.0, 0.0};
    Config.TargetVelocity = FVector{0.0, -300.0, 0.0};
    Config.Settings = FCk_Homing_GuidanceSettings{2000.0f};
    Config.Settings.Set_MaxSpeed(1200.0f);
    Config.SpeedClamp = 1200.0;

    const auto Result = ck_tests_homing::Simulate(Config);

    TestTrue(FString::Printf(TEXT("Crossing target intercepted (min miss %.2f cm at t=%.2f)"),
            Result.MinMissDistance, Result.TimeOfClosestApproach),
        Result.MinMissDistance < 50.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopTurnOnlyIntercepts,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopTurnOnlyIntercepts",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopTurnOnlyIntercepts::RunTest(const FString& Parameters)
{
    // Fin-steered projectile: speed is fixed, only the direction may change
    auto Config = ck_tests_homing::FSimConfig{};
    Config.PursuerVelocity = FVector{800.0, 0.0, 0.0};
    Config.TargetLocation = FVector{4000.0, 800.0, 0.0};
    Config.TargetVelocity = FVector{0.0, -150.0, 0.0};
    Config.Settings = FCk_Homing_GuidanceSettings{2500.0f};
    Config.Settings.Set_SpeedControl(ECk_Homing_SpeedControl::TurnOnly);

    const auto Result = ck_tests_homing::Simulate(Config);

    TestTrue(FString::Printf(TEXT("TurnOnly intercepts the crossing target (min miss %.2f cm)"),
            Result.MinMissDistance),
        Result.MinMissDistance < 100.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopWeavingTargetIntercepts,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopWeavingTargetIntercepts",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopWeavingTargetIntercepts::RunTest(const FString& Parameters)
{
    // Sinusoidally juking target — proportional navigation's reason to exist
    auto Config = ck_tests_homing::FSimConfig{};
    Config.PursuerVelocity = FVector{700.0, 0.0, 0.0};
    Config.TargetLocation = FVector{4500.0, 1200.0, 0.0};
    Config.TargetVelocity = FVector{0.0, -250.0, 0.0};
    Config.TargetAcceleration = [](double InTime) -> FVector
    {
        return FVector{0.0, 350.0 * FMath::Sin(InTime * 2.0), 200.0 * FMath::Cos(InTime * 1.5)};
    };
    Config.Settings = FCk_Homing_GuidanceSettings{2500.0f};
    Config.Settings.Set_NavigationGain(4.0f);
    Config.Settings.Set_MaxSpeed(1400.0f);
    Config.SpeedClamp = 1400.0;

    const auto Result = ck_tests_homing::Simulate(Config);

    TestTrue(FString::Printf(TEXT("Weaving target intercepted (min miss %.2f cm)"), Result.MinMissDistance),
        Result.MinMissDistance < 100.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopFramerateRobust,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopFramerateRobust",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopFramerateRobust::RunTest(const FString& Parameters)
{
    // The analytic guidance state (no finite differences) is what makes the law behave the same
    // at 30 Hz and 240 Hz — both must intercept and agree on when
    const auto RunAtRate = [](double InDeltaT) -> ck_tests_homing::FSimResult
    {
        auto Config = ck_tests_homing::FSimConfig{};
        Config.PursuerVelocity = FVector{600.0, 0.0, 0.0};
        Config.TargetLocation = FVector{3500.0, 1500.0, 500.0};
        Config.TargetVelocity = FVector{-100.0, -280.0, -50.0};
        Config.Settings = FCk_Homing_GuidanceSettings{2200.0f};
        Config.Settings.Set_MaxSpeed(1300.0f);
        Config.SpeedClamp = 1300.0;
        Config.DeltaT = InDeltaT;
        Config.MaxTime = 15.0;
        Config.StopAtDistance = 100.0;

        return ck_tests_homing::Simulate(Config);
    };

    const auto At30Hz = RunAtRate(1.0 / 30.0);
    const auto At240Hz = RunAtRate(1.0 / 240.0);

    TestTrue(FString::Printf(TEXT("30 Hz intercepts on the first approach (min miss %.2f cm)"), At30Hz.MinMissDistance),
        At30Hz.Intercepted);
    TestTrue(FString::Printf(TEXT("240 Hz intercepts on the first approach (min miss %.2f cm)"), At240Hz.MinMissDistance),
        At240Hz.Intercepted);

    TestTrue(FString::Printf(TEXT("Intercept times agree across framerates (%.3f vs %.3f)"),
            At30Hz.TimeOfClosestApproach, At240Hz.TimeOfClosestApproach),
        FMath::IsNearlyEqual(At30Hz.TimeOfClosestApproach, At240Hz.TimeOfClosestApproach, 1.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopRecedingTargetTurnsAround,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopRecedingTargetTurnsAround",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopRecedingTargetTurnsAround::RunTest(const FString& Parameters)
{
    // Launched directly away from the target — the receding branch must swing the velocity
    // around and still land the intercept
    auto Config = ck_tests_homing::FSimConfig{};
    Config.PursuerVelocity = FVector{-600.0, 0.0, 0.0};
    Config.TargetLocation = FVector{2000.0, 0.0, 0.0};
    Config.Settings = FCk_Homing_GuidanceSettings{2000.0f};
    Config.Settings.Set_MaxSpeed(900.0f);
    Config.SpeedClamp = 900.0;
    Config.MaxTime = 15.0;

    const auto Result = ck_tests_homing::Simulate(Config);

    TestTrue(FString::Printf(TEXT("Receding pursuer turns around and intercepts (min miss %.2f cm at t=%.2f)"),
            Result.MinMissDistance, Result.TimeOfClosestApproach),
        Result.MinMissDistance < 50.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopDesiredImpactTime,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopDesiredImpactTime",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopDesiredImpactTime::RunTest(const FString& Parameters)
{
    // Cruise speed would arrive in 10 s; the timing controller must spend thrust to land it in ~5 s
    constexpr auto DesiredTime = 5.0;

    auto Config = ck_tests_homing::FSimConfig{};
    Config.PursuerVelocity = FVector{600.0, 0.0, 0.0};
    Config.TargetLocation = FVector{6000.0, 0.0, 0.0};
    Config.Settings = FCk_Homing_GuidanceSettings{1500.0f};
    Config.Settings.Set_ImpactTiming(ECk_Homing_ImpactTiming::ArriveAtDesiredTime);
    Config.Settings.Set_DesiredTimeToImpact(FCk_Time{DesiredTime});
    Config.MaxTime = 12.0;
    Config.StopAtDistance = 30.0;

    const auto Result = ck_tests_homing::Simulate(Config);

    TestTrue(FString::Printf(TEXT("Intercept happened (min miss %.2f cm)"), Result.MinMissDistance),
        Result.Intercepted);

    TestTrue(FString::Printf(TEXT("Arrival near the desired time (t=%.3f desired %.1f)"),
            Result.TimeOfClosestApproach, DesiredTime),
        FMath::IsNearlyEqual(Result.TimeOfClosestApproach, DesiredTime, DesiredTime * 0.1));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Homing_ClosedLoopGravitySagCompensated,
    "CkTests.UnitTests.CkProjectile.Homing.ClosedLoopGravitySagCompensated",
    kCkUnitTestFlags)

bool FCkTest_Homing_ClosedLoopGravitySagCompensated::RunTest(const FString& Parameters)
{
    // Level shot under gravity: compensation must cancel the perpendicular pull so the
    // projectile neither sags nor misses
    auto Config = ck_tests_homing::FSimConfig{};
    Config.PursuerVelocity = FVector{700.0, 0.0, 0.0};
    Config.TargetLocation = FVector{5000.0, 0.0, 0.0};
    Config.ExternalAcceleration = FVector{0.0, 0.0, -980.0};
    Config.Settings = FCk_Homing_GuidanceSettings{2500.0f};
    Config.MaxTime = 10.0;
    Config.StopAtDistance = 50.0;

    const auto Result = ck_tests_homing::Simulate(Config);

    TestTrue(FString::Printf(TEXT("Intercept under gravity (min miss %.2f cm)"), Result.MinMissDistance),
        Result.Intercepted);

    TestTrue(FString::Printf(TEXT("No gravity sag along the way (max |z| %.2f cm)"), Result.MaxAbsZ),
        Result.MaxAbsZ < 10.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
