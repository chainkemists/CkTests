#include "CkProceduralAnimation/Core/CkProceduralSurfaceMotion.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// Controlled cylinder geometry isolates recovery from an already displaced support frame; no feet plane is supplied.
namespace ck_test_procedural_lookahead_secant
{
    constexpr auto Radius = 90.0;
    constexpr auto Clearance = 90.0f;
    constexpr auto Ahead = 1.5 * Clearance;
    constexpr auto Step = FCk_Time{1.0 / 120.0};

    auto
        CylinderCast(
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        const auto Delta = InEnd - InStart;
        const auto A = Delta.X * Delta.X + Delta.Y * Delta.Y;
        const auto B = 2.0 * (InStart.X * Delta.X + InStart.Y * Delta.Y);
        const auto C = InStart.X * InStart.X + InStart.Y * InStart.Y - Radius * Radius;
        if (A <= UE_DOUBLE_SMALL_NUMBER)
        { return {}; }
        if (C <= 0.0)
        { return ck::FProceduralSurfaceHit{}.Set_Hit(true).Set_Position(InStart).Set_Fraction(0.0f); }
        const auto Discriminant = B * B - 4.0 * A * C;
        if (Discriminant < 0.0)
        { return {}; }
        const auto Fraction = (-B - FMath::Sqrt(Discriminant)) / (2.0 * A);
        if (Fraction < 0.0 || Fraction > 1.0)
        { return {}; }
        const auto Position = InStart + Delta * Fraction;
        return ck::FProceduralSurfaceHit{}
            .Set_Hit(true)
            .Set_Position(Position)
            .Set_Normal(FVector{Position.X, Position.Y, 0.0}.GetSafeNormal())
            .Set_Fraction(static_cast<float>(Fraction));
    }

    auto
        FlatCast(
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        // The same outward-facing wall at X=90, with no curvature or endcap.
        const auto Delta = InEnd - InStart;
        if (InStart.X <= Radius || Delta.X >= -UE_DOUBLE_SMALL_NUMBER)
        { return {}; }
        const auto Fraction = (Radius - InStart.X) / Delta.X;
        if (Fraction <= 0.0 || Fraction > 1.0)
        { return {}; }
        return ck::FProceduralSurfaceHit{}
            .Set_Hit(true)
            .Set_Position(InStart + Delta * Fraction)
            .Set_Normal(FVector::ForwardVector)
            .Set_Fraction(static_cast<float>(Fraction));
    }

    // The solid below the continuous heightfield: floor, 45-degree bevel, then a flat crest. Every plane is bounded in X;
    // Y is unbounded. Return the nearest entering intersection, never a farther plane's extrapolated contact.
    auto
        BevelHeight(
            double InX)
        -> double
    {
        return FMath::Clamp(100.0 + InX, 0.0, 200.0);
    }

    auto
        BevelCast(
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        if (InStart.ContainsNaN() || InEnd.ContainsNaN())
        { return {}; }
        if (InStart.Z <= BevelHeight(InStart.X))
        { return ck::FProceduralSurfaceHit{}.Set_Hit(true).Set_Position(InStart).Set_Fraction(0.0f); }

        const auto Delta = InEnd - InStart;
        auto Closest = ck::FProceduralSurfaceHit{};
        auto ClosestFraction = TNumericLimits<double>::Max();
        const auto TryPlane = [&](const FVector& InPoint, const FVector& InNormal, double InMinX, double InMaxX)
        {
            const auto Denominator = FVector::DotProduct(InNormal, Delta);
            if (Denominator >= -UE_DOUBLE_SMALL_NUMBER)
            { return; }
            const auto Fraction = FVector::DotProduct(InNormal, InPoint - InStart) / Denominator;
            if (NOT FMath::IsFinite(Fraction) || Fraction <= 0.0 || Fraction > 1.0 || Fraction >= ClosestFraction)
            { return; }
            const auto Position = InStart + Delta * Fraction;
            if (Position.X < InMinX || Position.X > InMaxX)
            { return; }
            ClosestFraction = Fraction;
            Closest.Set_Hit(true).Set_Position(Position).Set_Normal(InNormal).Set_Fraction(static_cast<float>(Fraction));
        };
        TryPlane(FVector::ZeroVector, FVector::UpVector, TNumericLimits<double>::Lowest(), -100.0);
        TryPlane(FVector{0.0, 0.0, 100.0}, FVector{-1.0, 0.0, 1.0}.GetSafeNormal(), -100.0, 100.0);
        TryPlane(FVector{0.0, 0.0, 200.0}, FVector::UpVector, 100.0, TNumericLimits<double>::Max());
        return Closest;
    }

    auto
        MakeSettings()
        -> ck::FProceduralSurfaceMotionSettings
    {
        return ck::FProceduralSurfaceMotionSettings{}
            .Set_Clearance(Clearance)
            .Set_ProbeReach(220.0f)
            .Set_SurfaceTurnRateDegrees(240.0f)
            .Set_ClearanceSpeed(200.0f)
            .Set_ContactGrace(FCk_Time{0.12});
    }

    auto
        MakeState()
        -> ck::FProceduralSurfaceMotionState
    {
        return ck::FProceduralSurfaceMotionState{}
            .Set_Grounded(true)
            .Set_ContactTrusted(true)
            .Set_SupportNormal(FVector::ForwardVector)
            .Set_TravelTangent(FVector::RightVector);
    }

    auto
        MakeBody(
            const FVector& InPosition)
        -> FTransform
    {
        return FTransform{FRotationMatrix::MakeFromZX(FVector::ForwardVector, FVector::RightVector).ToQuat(), InPosition};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionLookAheadSecantRecoveryTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LookAheadRecoversCylinderSecant",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionLookAheadSecantRecoveryTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_lookahead_secant;
    using ESource = ck::EProceduralSurfaceContactSource;
    const auto NoFeet = TOptional<ck::FProceduralSurfaceFeetSupport>{};

    // Both cylinder bodies start with attachment up +X. The healthy radial body has a down hit; the secant's -135 cm tangent
    // offset makes that ray miss. Its +135 cm look-ahead cancels the offset and hits the same +X cylinder facet.
    const auto RadialStart = FVector{Radius + Clearance, 0.0, 200.0};
    const auto SecantStart = FVector{Radius + Clearance, -Ahead, 200.0};
    auto RadialBody = MakeBody(RadialStart);
    auto SecantBody = MakeBody(SecantStart);
    auto FlatBody = MakeBody(SecantStart);
    auto RadialState = MakeState();
    auto SecantState = MakeState();
    auto FlatState = MakeState();
    const auto ExpectedRadius = FMath::Sqrt(FMath::Square(Radius + Clearance) + FMath::Square(Ahead));
    const auto ExpectedAngle = FMath::RadiansToDegrees(FMath::Atan2(Ahead, Radius + Clearance));
    TestTrue(TEXT("The controlled geometry predicts radius225 and angle36.86989765 degrees"),
        FMath::IsNearlyEqual(ExpectedRadius, 225.0, 1.0e-6)
        && FMath::IsNearlyEqual(ExpectedAngle, 36.86989765, 1.0e-6));

    for (auto Index = 0; Index < 120; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::RightVector, 0.0f, Step, &CylinderCast,
            NoFeet, RadialBody, RadialState);
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::RightVector, 0.0f, Step, &CylinderCast,
            NoFeet, SecantBody, SecantState);
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::RightVector, 0.0f, Step, &FlatCast,
            NoFeet, FlatBody, FlatState);
    }
    TestTrue(TEXT("Without feet support the healthy radial body remains on its actual down contact"),
        RadialState.Get_ContactSource() == ESource::Down && RadialState.Get_ContactTrusted()
        && RadialBody.GetLocation().Equals(RadialStart, 1.0e-4));
    TestTrue(TEXT("The flat wall keeps its trusted down support and authored clearance despite the tangent offset"),
        FlatState.Get_ContactSource() == ESource::Down && FlatState.Get_ContactTrusted()
        && FlatBody.GetLocation().Equals(SecantStart, 1.0e-4));
    const auto ActualRadius = FVector2D{SecantBody.GetLocation().X, SecantBody.GetLocation().Y}.Size();
    const auto ActualRadial = FVector{SecantBody.GetLocation().X, SecantBody.GetLocation().Y, 0.0}.GetSafeNormal();
    TestTrue(FString::Printf(TEXT("Within one second the seeded secant recovers trusted actual down support; source=%d radius=%.6f"),
        static_cast<int32>(SecantState.Get_ContactSource()), ActualRadius),
        SecantState.Get_ContactSource() == ESource::Down && SecantState.Get_ContactTrusted()
        && SecantState.Get_Grounded() && SecantState.Get_MissingContact() == FCk_Time{}
        && FMath::IsNearlyEqual(ActualRadius, Radius + Clearance, 1.0e-3));
    TestTrue(TEXT("Recovered support faces the actual cylinder radial normal without vertical travel"),
        FVector::DotProduct(SecantState.Get_SupportNormal(), ActualRadial) > 0.9999
        && FMath::IsNearlyEqual(SecantBody.GetLocation().Z, SecantStart.Z, 1.0e-4));

    // This intentionally seeds an already displaced state to isolate recovery. It does not establish the entry path of
    // a live walker, and existing crest tests independently protect look-ahead support over a lower floor or down miss.
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionLookAheadBeveledCrestTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LookAheadLocalizesBeveledCrest",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionLookAheadBeveledCrestTest::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_test_procedural_lookahead_secant;
    const auto Start = FVector{-30.0, 0.0, 290.0};
    const auto BevelNormal = FVector{-1.0, 0.0, 1.0}.GetSafeNormal();
    const auto Settings = MakeSettings();
    const auto AheadStart = Start + FVector::ForwardVector * Ahead;
    const auto AheadHit = BevelCast(AheadStart, AheadStart - FVector::UpVector * Settings.Get_ProbeReach());
    TestTrue(TEXT("Precondition: original look-ahead reaches the horizontal crest ahead of the body"),
        AheadHit.Get_Hit() && AheadHit.Get_Position().Equals(FVector{105.0, 0.0, 200.0}, 1.0e-6)
        && AheadHit.Get_Normal().Equals(FVector::UpVector, 1.0e-6));
    const auto LocalHit = BevelCast(Start, AheadHit.Get_Position() - AheadHit.Get_Normal() * Clearance);
    TestTrue(TEXT("Precondition: localization first meets the bounded bevel rather than extrapolating either flat plane"),
        LocalHit.Get_Hit() && LocalHit.Get_Fraction() > 0.0f && LocalHit.Get_Fraction() <= 1.0f
        && LocalHit.Get_Position().Equals(FVector{64.285714285714, 0.0, 164.285714285714}, 1.0e-6)
        && LocalHit.Get_Normal().Equals(BevelNormal, 1.0e-6));
    const auto InsideHit = BevelCast(FVector{0.0, 0.0, 90.0}, FVector{0.0, 0.0, 300.0});
    TestTrue(TEXT("A ray starting in the heightfield solid reports fraction zero"),
        InsideHit.Get_Hit() && InsideHit.Get_Fraction() == 0.0f);
    TestFalse(TEXT("A segment stopping above its bounded surface does not report a fraction past its endpoint"),
        BevelCast(Start, Start - FVector::UpVector * 10.0).Get_Hit());
    TestFalse(TEXT("An outward segment does not claim an entering support"),
        BevelCast(Start, Start + FVector::UpVector * 100.0).Get_Hit());

    auto Body = FTransform{Start};
    auto State = ck::FProceduralSurfaceMotionState{}
        .Set_Grounded(true).Set_ContactTrusted(true).Set_SupportNormal(FVector::UpVector)
        .Set_TravelTangent(FVector::ForwardVector);
    const auto NoFeet = TOptional<ck::FProceduralSurfaceFeetSupport>{};
    auto WorstStepDistance = 0.0;
    auto LowestPlaneDistance = TNumericLimits<double>::Max();
    auto EnteredSolid = false;
    for (auto Index = 0; Index < 120; ++Index)
    {
        const auto Previous = Body.GetLocation();
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, 0.0f, Step, &BevelCast, NoFeet, Body, State);
        WorstStepDistance = FMath::Max(WorstStepDistance, FVector::Dist(Previous, Body.GetLocation()));
        LowestPlaneDistance = FMath::Min(LowestPlaneDistance,
            FVector::DotProduct(Body.GetLocation() - FVector{0.0, 0.0, 100.0}, BevelNormal));
        EnteredSolid |= Body.GetLocation().Z <= BevelHeight(Body.GetLocation().X);
    }
    const auto FinalDistance = FVector::DotProduct(Body.GetLocation() - FVector{0.0, 0.0, 100.0}, BevelNormal);
    TestTrue(TEXT("Within one second the body grounds on the actual bevel with its normal and authored clearance"),
        State.Get_Grounded() && State.Get_ContactTrusted()
        && FVector::DotProduct(State.Get_SupportNormal(), BevelNormal) > 0.9999
        && FMath::IsNearlyEqual(FinalDistance, static_cast<double>(Clearance), 1.0e-3));
    TestTrue(TEXT("The localized bevel remains below the body throughout bounded correction, without tunnelling"),
        NOT EnteredSolid && LowestPlaneDistance >= Clearance - 1.0e-3);
    TestTrue(FString::Printf(TEXT("Each correction obeys ClearanceSpeed times the real step, without a position jump (worst %.6fcm)"),
        WorstStepDistance), WorstStepDistance <= Settings.Get_ClearanceSpeed() * Step.Get_Seconds() + 1.0e-4);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
