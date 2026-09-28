#include "CkProceduralAnimation/Core/CkProceduralFootProbe.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralFootTouchdownAdmissionTest,
    "Ck.ProceduralAnimation.Gait.TouchdownAdmissionKeepsAvailableFallback",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralFootTouchdownAdmissionTest::
    RunTest(
        const FString&)
    -> bool
{
    constexpr auto HalfSpan = 10.0f;
    constexpr auto Reach = 100.0f;
    constexpr auto RadiusSquared = 4.0;
    const auto Plant = FVector{10.0, 0.0, 4.0};
    const auto Validated = FVector{40.0, 0.0, 4.0};
    const auto Occupied = FVector{10.0, 0.0, 0.0};
    const auto Available = FVector{40.0, 0.0, 0.0};
    const auto Hip = FVector::ZeroVector;
    const auto RayCast = [](const FVector& InStart, const FVector& InEnd) -> ck::FProceduralSurfaceHit
    {
        const auto Fraction = InStart.Z / (InStart.Z - InEnd.Z);
        return ck::FProceduralSurfaceHit{}.Set_Hit(true).Set_Position(FMath::Lerp(InStart, InEnd, Fraction))
            .Set_Normal(FVector::UpVector).Set_Fraction(static_cast<float>(Fraction));
    };

    {
        auto AdmissionCalls = 0;
        const auto Touchdown = ck::ResolveProceduralTouchdown(Plant, Validated, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, {}, Reach, [&](const FVector& InHit)
            {
                ++AdmissionCalls;
                TestTrue(TEXT("Admission sees the actual ground hit rather than its off-ground query point"),
                    FMath::IsNearlyZero(InHit.Z));
                return FVector::DistSquared(InHit, Occupied) >= RadiusSquared;
            });
        TestTrue(TEXT("An occupied original hit falls back to the available validated landing"),
            Touchdown.Get_Trusted() && Touchdown.Get_Position().Equals(Available));
        TestEqual(TEXT("Both actual touchdown hits receive admission"), AdmissionCalls, 2);
        TestEqual(TEXT("The available fallback costs exactly two rays"), Touchdown.Get_Rays(), 2);
    }
    {
        const auto Touchdown = ck::ResolveProceduralTouchdown(Plant, Validated, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, {}, Reach, [&](const FVector& InHit)
            {
                return FVector::DistSquared(InHit, Occupied) >= RadiusSquared
                    && FVector::DistSquared(InHit, Available) >= RadiusSquared;
            });
        TestFalse(TEXT("Two occupied ground hits do not publish a trusted plant"), Touchdown.Get_Trusted());
        TestTrue(TEXT("Rejected hits preserve the original untrusted plant and support normal"),
            Touchdown.Get_Position().Equals(Plant) && Touchdown.Get_Normal().Equals(FVector::UpVector));
        TestEqual(TEXT("Two rejected hits retain the bounded two-ray cost"), Touchdown.Get_Rays(), 2);
    }
    {
        auto AdmissionCalls = 0;
        const auto UnreachablePlant = FVector{140.0, 0.0, 4.0};
        const auto Touchdown = ck::ResolveProceduralTouchdown(UnreachablePlant, Validated, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, {}, Reach, [&](const FVector&)
            {
                ++AdmissionCalls;
                return true;
            });
        TestTrue(TEXT("Admission supplements physical reach rather than admitting an unreachable original hit"),
            Touchdown.Get_Trusted() && Touchdown.Get_Position().Equals(Available));
        TestEqual(TEXT("Only a physically reachable hit receives additional admission"), AdmissionCalls, 1);
        TestEqual(TEXT("A reach rejection still permits the validated-target ray"), Touchdown.Get_Rays(), 2);
    }
    {
        const auto PresentationHip = TOptional<FVector>{FVector{-80.0, 0.0, 0.0}};
        const auto Touchdown = ck::ResolveProceduralTouchdown(Plant, Validated, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, PresentationHip, Reach, [&](const FVector& InHit)
            { return FVector::DistSquared(InHit, Occupied) >= RadiusSquared; });
        TestFalse(TEXT("An available fallback beyond the presentation chain remains untrusted"), Touchdown.Get_Trusted());
        TestTrue(TEXT("Combined reservation and posed-reach rejection retains the original plant"),
            Touchdown.Get_Position().Equals(Plant));
    }
    {
        const auto Previous = ck::ResolveProceduralTouchdown(Plant, Validated, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, {}, Reach);
        const auto Admitted = ck::ResolveProceduralTouchdown(Plant, Validated, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, {}, Reach, [](const FVector&) { return true; });
        TestTrue(TEXT("Unrestricted admission preserves the existing reachable-touchdown contract"),
            Previous.Get_Position().Equals(Admitted.Get_Position()) && Previous.Get_Normal().Equals(Admitted.Get_Normal())
            && Previous.Get_Trusted() == Admitted.Get_Trusted() && Previous.Get_Rays() == Admitted.Get_Rays());
        const auto Rejected = ck::ResolveProceduralTouchdown(Plant, Plant, FVector::UpVector, FVector::UpVector,
            HalfSpan, RayCast, Hip, {}, Reach, [](const FVector&) { return false; });
        TestFalse(TEXT("An occupied coincident validated point remains untrusted"), Rejected.Get_Trusted());
        TestEqual(TEXT("A coincident validated point does not duplicate the query"), Rejected.Get_Rays(), 1);
    }
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
