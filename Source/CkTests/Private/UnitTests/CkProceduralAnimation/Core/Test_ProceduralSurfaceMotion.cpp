#include "CkProceduralAnimation/Core/CkProceduralSurfaceMotion.h"

#include "../../CkUnitTest_Common.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_surface_motion
{
    constexpr auto Clearance = 65.0f;
    constexpr auto ProbeReach = 180.0f;
    constexpr auto Speed = 180.0f;
    constexpr auto ConfirmAngle = 30.0f;
    constexpr auto ConfirmTime = FCk_Time{0.075};
    constexpr auto Step = FCk_Time{1.0 / 120.0};
    constexpr auto DistanceTolerance = 1.0e-3;
    constexpr auto TimeTolerance = 1.0e-4;
    constexpr auto MaxSubsteps = 240;
    const auto NoFeet = TOptional<ck::FProceduralSurfaceFeetSupport>{};

    // A convex solid: the points where dot(Normal, X) <= Offset for every plane.
    struct FSolidFace
    {
        FVector Normal = FVector::UpVector;
        double Offset = 0.0;
    };

    using FSolid = TArray<FSolidFace>;

    auto
        MakeHalfSpace(
            const FVector& InOutwardNormal,
            const FVector& InPointOnFace)
        -> FSolid
    {
        const auto Normal = InOutwardNormal.GetSafeNormal();
        return FSolid{FSolidFace{Normal, FVector::DotProduct(Normal, InPointOnFace)}};
    }

    auto
        MakeBox(
            const FVector& InMin,
            const FVector& InMax)
        -> FSolid
    {
        return FSolid{
            FSolidFace{FVector::ForwardVector, InMax.X}, FSolidFace{FVector::BackwardVector, -InMin.X},
            FSolidFace{FVector::RightVector, InMax.Y}, FSolidFace{FVector::LeftVector, -InMin.Y},
            FSolidFace{FVector::UpVector, InMax.Z}, FSolidFace{FVector::DownVector, -InMin.Z}};
    }

    // The first entry into any solid along the segment, like a Jolt ray cast against solid convex shapes: a segment that
    // starts inside a solid hits at fraction 0.
    auto
        RayCast(
            TArrayView<const FSolid> InWorld,
            const FVector& InStart,
            const FVector& InEnd)
        -> ck::FProceduralSurfaceHit
    {
        const auto Delta = InEnd - InStart;
        auto Best = ck::FProceduralSurfaceHit{};
        auto BestFraction = TNumericLimits<double>::Max();
        for (const auto& Solid : InWorld)
        {
            auto Enter = 0.0;
            auto Exit = 1.0;
            auto EnterNormal = FVector::UpVector;
            auto Outside = false;
            for (const auto& Plane : Solid)
            {
                const auto Along = FVector::DotProduct(Plane.Normal, Delta);
                const auto Inside = Plane.Offset - FVector::DotProduct(Plane.Normal, InStart);
                if (FMath::IsNearlyZero(Along))
                {
                    Outside = Outside || Inside < 0.0;
                    continue;
                }
                const auto Fraction = Inside / Along;
                if (Along > 0.0)
                {
                    Exit = FMath::Min(Exit, Fraction);
                }
                else if (Fraction > Enter)
                {
                    Enter = Fraction;
                    EnterNormal = Plane.Normal;
                }
            }
            if (Outside || Enter > Exit || Enter >= BestFraction)
            { continue; }

            BestFraction = Enter;
            Best = ck::FProceduralSurfaceHit{}
                .Set_Hit(true)
                .Set_Position(InStart + Delta * Enter)
                .Set_Normal(EnterNormal)
                .Set_Fraction(static_cast<float>(Enter));
        }
        return Best;
    }

    auto
        MakeSettings()
        -> ck::FProceduralSurfaceMotionSettings
    {
        return ck::FProceduralSurfaceMotionSettings{}
            .Set_Clearance(Clearance)
            .Set_ProbeReach(ProbeReach)
            .Set_ContactGrace(FCk_Time{0.12})
            .Set_ConfirmAngleDegrees(ConfirmAngle)
            .Set_ConfirmTime(ConfirmTime)
            .Set_SurfaceTurnRateDegrees(240.0f)
            .Set_ClearanceSpeed(200.0f)
            .Set_Gravity(FVector{0.0, 0.0, -980.0})
            .Set_SteerFloor(0.4f);
    }

    auto
        MakeState(
            const FVector& InSupportNormal,
            const FVector& InTravelTangent,
            bool InGrounded)
        -> ck::FProceduralSurfaceMotionState
    {
        return ck::FProceduralSurfaceMotionState{}
            .Set_SupportNormal(InSupportNormal.GetSafeNormal())
            .Set_TravelTangent(InTravelTangent.GetSafeNormal())
            .Set_Grounded(InGrounded)
            .Set_ContactTrusted(InGrounded);
    }

    auto
        MakeBody(
            const FVector& InPosition,
            const FVector& InSupportNormal,
            const FVector& InTravelTangent)
        -> FTransform
    {
        return FTransform{FRotationMatrix::MakeFromZX(InSupportNormal, InTravelTangent).ToQuat(), InPosition};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFlatFloorTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FlatFloorHoldsClearanceFromTheDownRay",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFlatFloorTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto World = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{0.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 60;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the down ray keeps the body grounded at its clearance (z %.4f, source %d)"),
                Index, Body.GetLocation().Z, static_cast<int32>(State.Get_ContactSource())),
                State.Get_Grounded() && State.Get_ContactTrusted()
                && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down
                && FMath::IsNearlyEqual(Body.GetLocation().Z, Clearance, DistanceTolerance)))
        { return false; }
    }

    const auto Travelled = Speed * Step.Get_Seconds() * Substeps;
    TestTrue(FString::Printf(TEXT("The body travels at the steering speed (expected %.3f, got %.3f)"), Travelled, Body.GetLocation().X),
        FMath::IsNearlyEqual(Body.GetLocation().X, Travelled, DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionUndercutFacetTest,
    "Ck.ProceduralAnimation.SurfaceMotion.SteerFloorKeepsTheTangentOnAnUndercutFacet",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionUndercutFacetTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A log's lower facet faces the walker 17 degrees below the horizontal: the horizontal steering projects onto it as a
    // short vector pointing down into the wedge between the log and the floor (0.29 of its length, below the 0.4 floor).
    constexpr auto BelowHorizontalDegrees = 17.0;
    const auto FacetNormal = FVector{-FMath::Cos(FMath::DegreesToRadians(BelowHorizontalDegrees)), 0.0,
        -FMath::Sin(FMath::DegreesToRadians(BelowHorizontalDegrees))};
    const auto FacetPoint = FVector{0.0, 0.0, 100.0};
    const auto World = TArray<FSolid>{MakeHalfSpace(FacetNormal, FacetPoint)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };

    // The tangent the floor-to-facet transport leaves: the floor's forward turned about the corner, around and up.
    const auto Tangent = FQuat::FindBetweenNormals(FVector::UpVector, FacetNormal).RotateVector(FVector::ForwardVector);
    auto Body = MakeBody(FacetPoint + FacetNormal * Clearance, FacetNormal, Tangent);
    auto State = MakeState(FacetNormal, Tangent, true);
    if (NOT TestTrue(FString::Printf(TEXT("Precondition: the transported tangent climbs (z %.3f)"), Tangent.Z), Tangent.Z > 0.5))
    { return false; }

    constexpr auto Substeps = 30;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        const auto Before = Body.GetLocation();
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        const auto Kept = State.Get_TravelTangent();
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the kept tangent still climbs the facet (tangent %s, rise %.3f)"),
                Index, *Kept.ToString(), Body.GetLocation().Z - Before.Z),
                Kept.Z > 0.5 && Body.GetLocation().Z > Before.Z))
        { return false; }
    }

    const auto Height = FVector::DotProduct(Body.GetLocation() - FacetPoint, FacetNormal);
    TestTrue(FString::Printf(TEXT("The body stays at its clearance off the facet (got %.4f)"), Height),
        FMath::IsNearlyEqual(Height, Clearance, DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFallKeepsTangentTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FallLandingKeepsTheTravelTangent",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFallKeepsTangentTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto World = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };

    // A ceiling walker let go, so its down ray looks up and only the swept fall finds the floor. The steering turned while
    // it fell; the landing must not snap the heading onto it.
    const auto CeilingNormal = FVector::DownVector;
    const auto Predecessor = FVector::ForwardVector;
    auto Body = MakeBody(FVector{0.0, 0.0, 200.0}, CeilingNormal, Predecessor);
    auto State = MakeState(CeilingNormal, Predecessor, false);
    const auto Steer = FVector::RightVector;
    auto Landed = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Landed; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), Steer, Speed, Step, Cast, NoFeet, Body, State);
        Landed = State.Get_Grounded();
    }
    if (NOT TestTrue(TEXT("The body lands on the floor"), Landed))
    { return false; }

    const auto Tangent = State.Get_TravelTangent();
    TestTrue(FString::Printf(TEXT("The landing keeps the tangent's predecessor (dot %.4f, tangent %s)"),
        FVector::DotProduct(Tangent, Predecessor), *Tangent.ToString()), FVector::DotProduct(Tangent, Predecessor) >= 0.9);
    TestTrue(TEXT("The landed tangent is a unit vector in the floor"),
        FMath::IsNearlyEqual(Tangent.Size(), 1.0, DistanceTolerance) && FMath::IsNearlyZero(Tangent.Z, DistanceTolerance));
    TestTrue(TEXT("The landed body faces along its tangent"),
        FVector::DotProduct(Body.GetRotation().GetAxisX(), Tangent) >= 1.0 - DistanceTolerance);
    TestTrue(TEXT("The landing is reported as the fall's contact"), State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Fall);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFallFromWallTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FallFromAWallLandsAlongTheSteer",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFallFromWallTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto World = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };

    // A wall climber let go: its tangent points up the wall, along the floor's normal, so it has no direction in the
    // floor. The steering runs nearly into the wall, so on the wall it keeps its tangent.
    const auto WallNormal = FVector::BackwardVector;
    const auto Climb = FVector::UpVector;
    auto Body = MakeBody(FVector{0.0, 0.0, 200.0}, WallNormal, Climb);
    auto State = MakeState(WallNormal, Climb, false);
    const auto Steer = FVector{1.0, 0.3, 0.0}.GetSafeNormal();

    auto Landed = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Landed; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), Steer, Speed, Step, Cast, NoFeet, Body, State);
        Landed = State.Get_Grounded();
    }
    if (NOT TestTrue(TEXT("The body lands on the floor"), Landed))
    { return false; }

    const auto Tangent = State.Get_TravelTangent();
    const auto SteerOnFloor = FVector::VectorPlaneProject(Steer, FVector::UpVector).GetSafeNormal();
    TestTrue(FString::Printf(TEXT("The landed tangent follows the steering on the floor (dot %.4f, tangent %s)"),
        FVector::DotProduct(Tangent, SteerOnFloor), *Tangent.ToString()), FVector::DotProduct(Tangent, SteerOnFloor) >= 0.99);
    TestTrue(TEXT("The landed tangent is a unit vector in the floor"),
        FMath::IsNearlyEqual(Tangent.Size(), 1.0, DistanceTolerance) && FMath::IsNearlyZero(Tangent.Z, DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_surface_motion
{
    // A floor and a wall across the path, facing the walker, 100 cm ahead of the origin.
    constexpr auto WallX = 100.0;

    auto
        MakeFloorAndWall()
        -> TArray<FSolid>
    {
        return TArray<FSolid>{
            MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
            MakeBox(FVector{WallX, -500.0, -50.0}, FVector{WallX + 300.0, 500.0, 300.0})};
    }

    auto
        Get_IsOnWall(
            const ck::FProceduralSurfaceHit& InHit)
        -> bool
    {
        return InHit.Get_Hit() && InHit.Get_Normal().Equals(FVector::BackwardVector, DistanceTolerance)
            && FMath::IsNearlyEqual(InHit.Get_Position().X, WallX, DistanceTolerance);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionConfirmTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LargeTurnWaitsForConfirmation",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionConfirmTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto World = MakeFloorAndWall();
    auto SawWall = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawWall = SawWall || Get_IsOnWall(Hit);
        return Hit;
    };
    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto FirstSighting = int32{INDEX_NONE};
    auto Adopted = int32{INDEX_NONE};
    for (auto Index = 0; Index < MaxSubsteps && Adopted == INDEX_NONE; ++Index)
    {
        SawWall = false;
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (SawWall && FirstSighting == INDEX_NONE)
        { FirstSighting = Index; }
        if (State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance))
        {
            Adopted = Index;
            continue;
        }
        if (FirstSighting != INDEX_NONE)
        {
            TestTrue(FString::Printf(TEXT("Substep %d: while the wall is pending the floor stays the trusted support"), Index),
                State.Get_Grounded() && State.Get_ContactTrusted() && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance));
        }
    }
    if (NOT TestTrue(TEXT("The forward ray sees the wall and the body adopts it"), FirstSighting != INDEX_NONE && Adopted != INDEX_NONE))
    { return false; }

    const auto Seen = Step * (Adopted - FirstSighting + 1);
    TestTrue(FString::Printf(TEXT("The 90 degree turn is adopted after it is seen for the confirm time, not before (seen %.4f s, confirm %.4f s)"),
        Seen.Get_Seconds(), ConfirmTime.Get_Seconds()),
        Seen.Get_Seconds() >= ConfirmTime.Get_Seconds() - TimeTolerance
        && Seen.Get_Seconds() <= (ConfirmTime + Step).Get_Seconds() + TimeTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionPendingCoastsTest,
    "Ck.ProceduralAnimation.SurfaceMotion.PendingContactCoastsNoLongerThanTheConfirmTime",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionPendingCoastsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto World = MakeFloorAndWall();
    auto SawWall = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawWall = SawWall || Get_IsOnWall(Hit);
        return Hit;
    };

    // Head on and at a slant: once the wall is seen the body keeps walking the floor until the wall is confirmed, and
    // closes on the wall by no more than its speed times the confirm time.
    for (const auto& Steer : {FVector::ForwardVector, FVector{1.0, 0.6, 0.0}.GetSafeNormal()})
    {
        auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, Steer);
        auto State = MakeState(FVector::UpVector, Steer, true);
        auto SightedAt = TOptional<FVector>{};
        auto Adopted = false;
        for (auto Index = 0; Index < MaxSubsteps && NOT Adopted; ++Index)
        {
            SawWall = false;
            const auto Before = Body.GetLocation();
            ck::StepProceduralSurfaceMotion(MakeSettings(), Steer, Speed, Step, Cast, NoFeet, Body, State);
            if (SawWall && NOT SightedAt.IsSet())
            { SightedAt = Before; }
            Adopted = State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance);
            if (NOT SightedAt.IsSet() || Adopted)
            { continue; }

            const auto Advance = FVector::DotProduct(Body.GetLocation() - Before, Steer);
            if (NOT TestTrue(FString::Printf(TEXT("Steer %s, substep %d: the pending wall leaves the body walking the floor (advance %.4f, normal %s)"),
                    *Steer.ToString(), Index, Advance, *State.Get_SupportNormal().ToString()),
                    FMath::IsNearlyEqual(Advance, Speed * Step.Get_Seconds(), DistanceTolerance)
                    && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
            { return false; }
        }
        if (NOT TestTrue(FString::Printf(TEXT("Steer %s: the wall is seen and adopted"), *Steer.ToString()), SightedAt.IsSet() && Adopted))
        { return false; }

        const auto Closed = Body.GetLocation().X - SightedAt->X;
        const auto Bound = Speed * (ConfirmTime + Step).Get_Seconds() + DistanceTolerance;
        TestTrue(FString::Printf(TEXT("Steer %s: from the first sighting to the adoption the body closes %.3f cm on the wall, at most %.3f"),
            *Steer.ToString(), Closed, Bound), Closed <= Bound);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionGrazeTest,
    "Ck.ProceduralAnimation.SurfaceMotion.ShortGrazeIsNeverAdopted",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionGrazeTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The steep side of a tilted rock, 82 degrees off the floor and 3 cm wide seen from above: the down ray hits it on
    // two substeps as the body walks over it.
    const auto SideNormal = FVector{-0.99, 0.0, 0.14}.GetSafeNormal();
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        FSolid{FSolidFace{SideNormal, 0.0}, FSolidFace{FVector::ForwardVector, 3.0}, FSolidFace{FVector::DownVector, 10.0},
            FSolidFace{FVector::RightVector, 500.0}, FSolidFace{FVector::LeftVector, 500.0}}};
    auto SawSide = 0;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawSide += Hit.Get_Hit() && Hit.Get_Normal().Equals(SideNormal, DistanceTolerance) ? 1 : 0;
        return Hit;
    };
    auto Body = MakeBody(FVector{-30.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 60;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the floor stays the support (normal %s, z %.3f)"),
                Index, *State.Get_SupportNormal().ToString(), Body.GetLocation().Z),
                State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance) && State.Get_Grounded()
                && FMath::IsNearlyEqual(Body.GetLocation().Z, Clearance, 1.0)))
        { return false; }
    }
    TestTrue(FString::Printf(TEXT("Precondition: the down ray grazed the side (%d sightings)"), SawSide), SawSide >= 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionSeamGrazeTest,
    "Ck.ProceduralAnimation.SurfaceMotion.SeamGrazeKeepsThePendingContactPending",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionSeamGrazeTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // Three treads whose boxes share their riser planes: 10 cm up to x = 0, 35 cm up to x = 60, then 80 cm. The forward ray,
    // at the clearance over the first tread, grazes the third tread's riser a few substeps before the body steps onto the
    // second tread and rises over it. On the substep the down ray runs along the plane the first two treads share, the ray
    // cast reports that plane's face, perpendicular to the ray, as a physics engine does on such a seam.
    constexpr auto FirstTop = 10.0;
    constexpr auto SeamX = 0.0;
    constexpr auto RiserX = 60.0;
    const auto World = TArray<FSolid>{
        MakeBox(FVector{-1000.0, -500.0, -10.0}, FVector{SeamX, 500.0, FirstTop}),
        MakeBox(FVector{SeamX, -500.0, -10.0}, FVector{RiserX, 500.0, 35.0}),
        MakeBox(FVector{RiserX, -500.0, -10.0}, FVector{1000.0, 500.0, 80.0})};
    auto Grazed = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Down = FMath::IsNearlyEqual(InStart.X, InEnd.X) && FMath::IsNearlyEqual(InStart.Y, InEnd.Y) && InEnd.Z < InStart.Z;
        if (Down && FMath::Abs(InStart.X - SeamX) <= 0.75)
        {
            Grazed = true;
            return ck::FProceduralSurfaceHit{}
                .Set_Hit(true)
                .Set_Position(FVector{SeamX, InStart.Y, FirstTop})
                .Set_Normal(FVector::BackwardVector)
                .Set_Fraction(static_cast<float>((InStart.Z - FirstTop) / (InStart.Z - InEnd.Z)));
        }
        return RayCast(World, InStart, InEnd);
    };
    auto Body = MakeBody(FVector{-60.0, 0.0, FirstTop + Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 90;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the grazed riser never replaces the tread under the body (normal %s, x %.2f, z %.2f)"),
                Index, *State.Get_SupportNormal().ToString(), Body.GetLocation().X, Body.GetLocation().Z),
                State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
        { return false; }
    }
    TestTrue(TEXT("Precondition: the down ray met the seam"), Grazed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionStartInsideTest,
    "Ck.ProceduralAnimation.SurfaceMotion.DownRayStartingInsideASolidIsAMiss",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionStartInsideTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A body descending a pillar's far face toward the floor, its forward ray already seeing the floor. In a gap two
    // clearances wide its down ray, cast from one clearance off the face, starts on the next pillar's face: once it does,
    // the pending floor is adopted at once instead of waiting out the confirmation.
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeHalfSpace(FVector::ForwardVector, FVector::ZeroVector)};
    auto FloorSightings = 0;
    auto StartedInside = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Toward = (InEnd - InStart).GetSafeNormal();
        if (Toward.Equals(FVector::BackwardVector, DistanceTolerance) && FloorSightings >= 3)
        {
            StartedInside = true;
            return ck::FProceduralSurfaceHit{}
                .Set_Hit(true)
                .Set_Position(InStart)
                .Set_Normal(FVector::ForwardVector)
                .Set_Fraction(0.0f);
        }
        const auto Hit = RayCast(World, InStart, InEnd);
        if (Toward.Equals(FVector::DownVector, DistanceTolerance) && Hit.Get_Hit() && Hit.Get_Normal().Equals(FVector::UpVector, DistanceTolerance))
        { ++FloorSightings; }
        return Hit;
    };
    auto Body = MakeBody(FVector{Clearance, 0.0, 100.0}, FVector::ForwardVector, FVector::DownVector);
    auto State = MakeState(FVector::ForwardVector, FVector::DownVector, true);

    for (auto Index = 0; Index < MaxSubsteps; ++Index)
    {
        const auto WasInside = StartedInside;
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (StartedInside == WasInside)
        { continue; }

        TestTrue(FString::Printf(TEXT("On the substep the down ray first starts inside the next face, the pending floor is adopted after %d sightings (normal %s)"),
            FloorSightings, *State.Get_SupportNormal().ToString()),
            State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)
            && Step * FloorSightings < ConfirmTime && State.Get_Grounded());
        return true;
    }

    AddError(TEXT("The forward ray never saw the floor three times"));
    return false;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionLostSupportTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LostSupportAdoptsAtOnce",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionLostSupportTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A ledge top ending at x = 0 over a drop deeper than the probe reach.
    const auto World = TArray<FSolid>{MakeBox(FVector{-1000.0, -500.0, -600.0}, FVector{0.0, 500.0, 0.0})};
    auto DownMissed = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        const auto Vertical = FMath::IsNearlyEqual(InStart.X, InEnd.X) && FMath::IsNearlyEqual(InStart.Y, InEnd.Y) && InEnd.Z < InStart.Z;
        DownMissed = DownMissed || (Vertical && NOT Hit.Get_Hit());
        return Hit;
    };
    auto Body = MakeBody(FVector{-60.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    for (auto Index = 0; Index < MaxSubsteps; ++Index)
    {
        DownMissed = false;
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT DownMissed)
        { continue; }

        TestTrue(FString::Printf(TEXT("On the substep the down ray first misses, the fan's 90 degree face is adopted at once (normal %s, source %d)"),
            *State.Get_SupportNormal().ToString(), static_cast<int32>(State.Get_ContactSource())),
            State.Get_SupportNormal().Equals(FVector::ForwardVector, DistanceTolerance)
            && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Fan
            && State.Get_Grounded() && State.Get_ContactTrusted());
        return true;
    }

    AddError(TEXT("The down ray never missed past the ledge edge"));
    return false;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionLookAheadTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LookAheadCarriesOntoATopEdge",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionLookAheadTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // Where the fan leaves a body that climbed a face to a 90 degree top edge: on the top's plane, one clearance behind
    // the edge, with nothing under it within the probe reach.
    const auto World = TArray<FSolid>{MakeBox(FVector{0.0, -500.0, -600.0}, FVector{300.0, 500.0, 0.0})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{-Clearance, 0.0, 5.0}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 120;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the body stays grounded on the top (normal %s, z %.3f, source %d)"),
                Index, *State.Get_SupportNormal().ToString(), Body.GetLocation().Z, static_cast<int32>(State.Get_ContactSource())),
                State.Get_Grounded() && State.Get_ContactTrusted() && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
        { return false; }
    }

    TestTrue(FString::Printf(TEXT("The body walked onto the top (x %.2f) and rose toward its clearance (z %.2f)"),
        Body.GetLocation().X, Body.GetLocation().Z), Body.GetLocation().X > 0.0 && Body.GetLocation().Z > 5.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionLookAheadAfterFanTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LookAheadHoldsTheTopOverALowerFloor",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionLookAheadAfterFanTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // Where the fan leaves a body that climbed a 150 cm ledge: on the top's plane, one clearance behind the edge. The down
    // ray reaches the floor 152 cm below; the top lies ahead.
    constexpr auto TopZ = 150.0;
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeBox(FVector{0.0, -500.0, -10.0}, FVector{300.0, 500.0, TopZ})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{-Clearance, 0.0, TopZ + 2.0}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 120;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the body keeps the top, never sinking toward the floor (normal %s, z %.3f, source %d)"),
                Index, *State.Get_SupportNormal().ToString(), Body.GetLocation().Z, static_cast<int32>(State.Get_ContactSource())),
                State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance) && Body.GetLocation().Z >= TopZ))
        { return false; }
    }

    TestTrue(FString::Printf(TEXT("The body walked onto the top (x %.2f) and rose toward its clearance over it (z %.2f)"),
        Body.GetLocation().X, Body.GetLocation().Z), Body.GetLocation().X > 0.0 && Body.GetLocation().Z > TopZ + 2.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionWalkOffEdgeTest,
    "Ck.ProceduralAnimation.SurfaceMotion.WalkingOffAnEdgeFollowsTheLowerFloor",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionWalkOffEdgeTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A 60 cm platform ending at x = 0 over a floor: past the edge both the down ray and the look-ahead see the floor, so
    // the body settles onto it.
    constexpr auto TopZ = 60.0;
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeBox(FVector{-1000.0, -500.0, -10.0}, FVector{0.0, 500.0, TopZ})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{-30.0, 0.0, TopZ + Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 150;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the body follows the down ray (source %d, normal %s)"),
                Index, static_cast<int32>(State.Get_ContactSource()), *State.Get_SupportNormal().ToString()),
                State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down
                && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
        { return false; }
    }

    TestTrue(FString::Printf(TEXT("The body settled to its clearance over the floor (z %.3f)"), Body.GetLocation().Z),
        FMath::IsNearlyEqual(Body.GetLocation().Z, Clearance, 1.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionStepUpTest,
    "Ck.ProceduralAnimation.SurfaceMotion.SteppingUpFollowsTheDownRay",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionStepUpTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A 20 cm step at x = 50: the body holds its clearance over the floor until it is over the step, then rises onto it.
    constexpr auto StepX = 50.0;
    constexpr auto StepZ = 20.0;
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeBox(FVector{StepX, -500.0, -10.0}, FVector{1000.0, 500.0, StepZ})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 120;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (Body.GetLocation().X >= StepX)
        { continue; }

        if (NOT TestTrue(FString::Printf(TEXT("Substep %d, over the floor: the down ray holds the body at its clearance (z %.3f, source %d)"),
                Index, Body.GetLocation().Z, static_cast<int32>(State.Get_ContactSource())),
                State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down
                && FMath::IsNearlyEqual(Body.GetLocation().Z, Clearance, DistanceTolerance)))
        { return false; }
    }

    TestTrue(FString::Printf(TEXT("Over the step the body rises onto it (z %.3f)"), Body.GetLocation().Z),
        Body.GetLocation().Z > Clearance + StepZ - 5.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionStoppedPastACrestTest,
    "Ck.ProceduralAnimation.SurfaceMotion.StoppedBodyPastACrestKeepsTheTop",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionStoppedPastACrestTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // Where the fan leaves a body that climbed a ledge, one clearance behind its edge, and where the steering stops it. Over
    // the 150 cm ledge the down ray reaches the floor below; over the 250 cm one it reaches nothing. Stopped, the body still
    // looks ahead to the top it stands at.
    constexpr auto StoppedSpeed = 0.0f;
    constexpr double TopHeights[] = {150.0, 250.0};
    for (const auto TopZ : TopHeights)
    {
        const auto World = TArray<FSolid>{
            MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
            MakeBox(FVector{0.0, -500.0, -10.0}, FVector{300.0, 500.0, TopZ})};
        const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
        auto Body = MakeBody(FVector{-Clearance, 0.0, TopZ + 2.0}, FVector::UpVector, FVector::ForwardVector);
        auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

        constexpr auto Substeps = 120;
        for (auto Index = 0; Index < Substeps; ++Index)
        {
            ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, StoppedSpeed, Step, Cast, NoFeet, Body, State);
            if (NOT TestTrue(FString::Printf(TEXT("Ledge %.0f cm, substep %d: the stopped body keeps the top, neither sinking toward the "
                    "floor nor falling (normal %s, z %.3f, grounded %d, source %d)"), TopZ, Index, *State.Get_SupportNormal().ToString(),
                    Body.GetLocation().Z, State.Get_Grounded(), static_cast<int32>(State.Get_ContactSource())),
                    State.Get_Grounded() && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)
                    && Body.GetLocation().Z >= TopZ))
            { return false; }
        }

        TestTrue(FString::Printf(TEXT("Ledge %.0f cm: the stopped body stays where it stopped (x %.3f)"), TopZ, Body.GetLocation().X),
            FMath::IsNearlyEqual(Body.GetLocation().X, -Clearance, DistanceTolerance));
        TestTrue(FString::Printf(TEXT("Ledge %.0f cm: the stopped body rose toward its clearance over the top (z %.2f)"), TopZ,
            Body.GetLocation().Z), Body.GetLocation().Z > TopZ + 2.0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionCoastKeepsSourceTest,
    "Ck.ProceduralAnimation.SurfaceMotion.CoastKeepsTheLastAcceptedSource",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionCoastKeepsSourceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A body whose last substep adopted the fan's contact, now over a 45 degree ramp: the down ray proposes the ramp, a turn
    // beyond the confirm angle, and the body coasts along its support plane while the ramp waits for confirmation. A coasting
    // substep adopts nothing, so the source is still the fan's.
    const auto RampNormal = FVector{-1.0, 0.0, 1.0}.GetSafeNormal();
    const auto World = TArray<FSolid>{MakeHalfSpace(RampNormal, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{-100.0, 0.0, -30.0}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    State.Set_ContactSource(ck::EProceduralSurfaceContactSource::Fan);

    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
    if (NOT TestTrue(FString::Printf(TEXT("Precondition: the ramp is pending and the support unchanged (seen %.4f s, normal %s)"),
            State.Get_CandidateSeen().Get_Seconds(), *State.Get_SupportNormal().ToString()),
            State.Get_CandidateSeen() > FCk_Time{} && State.Get_CandidateNormal().Equals(RampNormal, DistanceTolerance)
            && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
    { return false; }

    TestEqual(TEXT("The coasting substep keeps the last accepted source"), State.Get_ContactSource(), ck::EProceduralSurfaceContactSource::Fan);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_surface_motion
{
    // A plane through the planted feet, published in the identity frame at InOrigin with a square footprint of InHalfSize.
    auto
        MakeFeetSupport(
            const FVector& InPoint,
            const FVector& InNormal,
            const FVector& InOrigin,
            double InHalfSize)
        -> TOptional<ck::FProceduralSurfaceFeetSupport>
    {
        return ck::FProceduralSurfaceFeetSupport{}
            .Set_Point(InPoint)
            .Set_Normal(InNormal.GetSafeNormal())
            .Set_Basis(FQuat::Identity)
            .Set_Origin(InOrigin)
            .Set_FootprintMin(FVector2D{-InHalfSize, -InHalfSize})
            .Set_FootprintMax(FVector2D{InHalfSize, InHalfSize});
    }

    auto
        MissEverything(
            const FVector&,
            const FVector&)
        -> ck::FProceduralSurfaceHit
    {
        return ck::FProceduralSurfaceHit{};
    }

    auto
        Get_SourceValue(
            const ck::FProceduralSurfaceMotionState& InState)
        -> int32
    {
        return static_cast<int32>(InState.Get_ContactSource());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetHoldOverAMissTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportHoldsTheBodyOverAMiss",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetHoldOverAMissTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // Every ray misses (a body over a gap between the pillar tops its feet stand on); the feet plane lies one clearance
    // below it with a footprint all round.
    constexpr auto BodyZ = 100.0;
    const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, BodyZ - Clearance}, FVector::UpVector, FVector{0.0, 0.0, BodyZ}, 200.0);
    auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 10;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, &MissEverything, Feet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the feet hold the body at its height, grounded on a trusted feet contact (z %.4f, "
                "source %d, grounded %d, missing %.4f s)"), Index, Body.GetLocation().Z, Get_SourceValue(State), State.Get_Grounded(),
                State.Get_MissingContact().Get_Seconds()),
                FMath::IsNearlyEqual(Body.GetLocation().Z, BodyZ, DistanceTolerance) && State.Get_Grounded() && State.Get_ContactTrusted()
                && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet && State.Get_MissingContact() == FCk_Time{}))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetSteepToSupportTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportIsIgnoredWhenThePlaneIsSteepToTheSupport",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetSteepToSupportTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A body on a wall (its support normal along -X) with a level feet plane under it: the plane lies 90 degrees from the
    // support, so it is no ground the body can ride from here, and with every ray missing the contact grace runs instead.
    constexpr auto BodyZ = 100.0;
    const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, BodyZ - Clearance}, FVector::UpVector, FVector{0.0, 0.0, BodyZ}, 200.0);
    auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::BackwardVector, FVector::UpVector);
    auto State = MakeState(FVector::BackwardVector, FVector::UpVector, true);

    constexpr auto Substeps = 10;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::UpVector, Speed, Step, &MissEverything, Feet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: a plane steep to the support never becomes the contact (source %d, missing %.4f s)"),
                Index, Get_SourceValue(State), State.Get_MissingContact().Get_Seconds()),
                State.Get_ContactSource() != ck::EProceduralSurfaceContactSource::Feet && State.Get_MissingContact() > FCk_Time{}))
        { return false; }
    }

    // The control: the same plane under a body whose support is up rides it.
    auto LevelBody = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
    auto LevelState = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, &MissEverything, Feet, LevelBody, LevelState);
    TestTrue(TEXT("Control: with the support up the same plane holds the body"),
        LevelState.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet && LevelState.Get_MissingContact() == FCk_Time{});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetLiftTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportLiftsTheBodyAboveALowerHit",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetLiftTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The down ray reaches a floor 150 cm below the body while the feet plane lies one clearance below it: the body stays
    // on the feet instead of sinking to the floor.
    constexpr auto BodyZ = 150.0;
    const auto World = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, BodyZ - Clearance}, FVector::UpVector, FVector{0.0, 0.0, BodyZ}, 500.0);
    auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 30;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Feet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the body stays one clearance above the feet plane, 150 cm over the floor (z %.4f, source %d)"),
                Index, Body.GetLocation().Z, Get_SourceValue(State)),
                FMath::IsNearlyEqual(Body.GetLocation().Z, BodyZ, DistanceTolerance)
                && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetNeverLowerTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportNeverLowersTheBody",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetNeverLowerTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The feet plane lies 50 cm below the floor the down ray finds (feet planted in a hole the body has not stepped into):
    // the floor keeps the body at its clearance.
    const auto World = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, -50.0}, FVector::UpVector, FVector{0.0, 0.0, Clearance}, 500.0);
    auto Body = MakeBody(FVector{0.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 30;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Feet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the down ray's floor keeps the body at its clearance (z %.4f, source %d)"),
                Index, Body.GetLocation().Z, Get_SourceValue(State)),
                FMath::IsNearlyEqual(Body.GetLocation().Z, Clearance, DistanceTolerance)
                && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down))
        { return false; }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetCarryRayNormalTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportCarriesTheDownRaysNormal",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetCarryRayNormalTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    constexpr auto BodyZ = 150.0;
    constexpr auto TiltDegrees = 20.0;
    constexpr auto NormalToleranceDegrees = 0.5;
    constexpr auto Substeps = 60;
    constexpr auto Still = 0.0f;
    const auto TiltedNormal = FQuat{FVector::RightVector, FMath::DegreesToRadians(TiltDegrees)}.RotateVector(FVector::UpVector);
    const auto DegreesBetween = [](const FVector& InA, const FVector& InB)
    {
        return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(InA.GetSafeNormal(), InB.GetSafeNormal()), -1.0, 1.0)));
    };

    // A floor tilted 20 degrees lies 150 cm under the body and the level feet plane one clearance under it: the feet hold the
    // height, and the support turns onto the floor the down ray hits.
    {
        const auto World = TArray<FSolid>{MakeHalfSpace(TiltedNormal, FVector::ZeroVector)};
        const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
        const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, BodyZ - Clearance}, FVector::UpVector, FVector{0.0, 0.0, BodyZ}, 500.0);
        auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
        auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

        for (auto Index = 0; Index < Substeps; ++Index)
        {
            ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Still, Step, Cast, Feet, Body, State);
            if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the feet hold the body over the floor the down ray hits (source %d)"),
                    Index, Get_SourceValue(State)), State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet))
            { return false; }
        }
        TestTrue(FString::Printf(TEXT("Under the feet contact the support turns onto the down ray's normal (support %s, %.3f degrees from it)"),
                *State.Get_SupportNormal().ToString(), DegreesBetween(State.Get_SupportNormal(), TiltedNormal)),
            DegreesBetween(State.Get_SupportNormal(), TiltedNormal) <= NormalToleranceDegrees);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetOverAMissCarryThePlanesNormalTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetContactOverAMissCarriesThePlanesNormal",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetOverAMissCarryThePlanesNormalTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    constexpr auto BodyZ = 150.0;
    constexpr auto TiltDegrees = 20.0;
    constexpr auto NormalToleranceDegrees = 0.5;
    constexpr auto Still = 0.0f;
    const auto TiltedNormal = FQuat{FVector::RightVector, FMath::DegreesToRadians(TiltDegrees)}.RotateVector(FVector::UpVector);
    const auto DegreesBetween = [](const FVector& InA, const FVector& InB)
    {
        return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(InA.GetSafeNormal(), InB.GetSafeNormal()), -1.0, 1.0)));
    };
    // A feet plane tilted 20 degrees from the support up, one clearance under the body; the turn stays under the confirm
    // angle, so the first substep adopts whatever normal the feet contact carries.
    const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, BodyZ - Clearance}, TiltedNormal, FVector{0.0, 0.0, BodyZ}, 200.0);

    // Every ray misses: the feet contact carries the plane's normal.
    {
        auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
        auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Still, Step, &MissEverything, Feet, Body, State);
        TestTrue(FString::Printf(TEXT("Over a miss the feet contact carries the plane's normal (source %d, support %s, %.3f degrees from it)"),
                Get_SourceValue(State), *State.Get_SupportNormal().ToString(), DegreesBetween(State.Get_SupportNormal(), TiltedNormal)),
            State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet
            && DegreesBetween(State.Get_SupportNormal(), TiltedNormal) <= NormalToleranceDegrees);
    }

    // A level floor 150 cm under the body: the feet contact, higher, carries the down ray's normal.
    {
        const auto World = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
        const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
        auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
        auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Still, Step, Cast, Feet, Body, State);
        TestTrue(FString::Printf(TEXT("Over a hit the feet contact carries the ray's normal (source %d, support %s)"), Get_SourceValue(State),
                *State.Get_SupportNormal().ToString()),
            State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet
            && DegreesBetween(State.Get_SupportNormal(), FVector::UpVector) <= NormalToleranceDegrees);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetFootprintTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportEndsAtTheFootprint",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetFootprintTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // Every ray misses; the feet stand within 50 cm of the start, so their plane counts up to a quarter clearance beyond.
    // Past it the body takes the rays' path: the contact grace, then the fall.
    constexpr auto BodyZ = 100.0;
    constexpr auto FootprintHalfSize = 50.0;
    const auto Reach = FootprintHalfSize + 0.25 * Clearance;
    const auto Feet = MakeFeetSupport(FVector{0.0, 0.0, BodyZ - Clearance}, FVector::UpVector, FVector{0.0, 0.0, BodyZ}, FootprintHalfSize);
    auto Body = MakeBody(FVector{0.0, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto InsideSubsteps = 0;
    auto FirstOutside = int32{INDEX_NONE};
    auto Fell = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Fell; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, &MissEverything, Feet, Body, State);
        const auto X = Body.GetLocation().X;
        const auto IsFeet = State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet;
        if (X <= Reach)
        {
            ++InsideSubsteps;
            if (NOT TestTrue(FString::Printf(TEXT("Substep %d, inside the footprint (x %.2f): the feet support the body (source %d)"),
                    Index, X, Get_SourceValue(State)), IsFeet && State.Get_Grounded()))
            { return false; }
            continue;
        }

        if (NOT TestFalse(FString::Printf(TEXT("Substep %d, outside the footprint (x %.2f): no feet contact (source %d)"),
                Index, X, Get_SourceValue(State)), IsFeet))
        { return false; }

        if (FirstOutside == INDEX_NONE)
        {
            FirstOutside = Index;
            TestTrue(FString::Printf(TEXT("The first substep outside starts the contact grace: grounded, nothing accepted (source %d, missing %.4f s)"),
                Get_SourceValue(State), State.Get_MissingContact().Get_Seconds()),
                State.Get_Grounded() && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::None
                && State.Get_MissingContact() > FCk_Time{});
        }
        Fell = NOT State.Get_Grounded();
    }

    TestTrue(FString::Printf(TEXT("Precondition: the body walked inside the footprint first (%d substeps)"), InsideSubsteps), InsideSubsteps > 0);
    TestTrue(TEXT("Past the footprint the grace runs out and the body falls"), FirstOutside != INDEX_NONE && Fell);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFeetTiltedPlaneTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FeetSupportHeightFollowsTheTiltedPlane",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFeetTiltedPlaneTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A plane rising 30 degrees toward +X, published at the origin; the body stands 40 cm up the slope from that point, one
    // clearance straight above the plane there (20 cm higher than the point). Every ray misses and the body stays put: the
    // feet carry their plane's normal, so the body turns onto it and settles one clearance from the plane along it.
    constexpr auto SlopeDegrees = 30.0;
    constexpr auto AlongSlope = 40.0;
    constexpr auto HeightTolerance = 0.5;
    constexpr auto NormalToleranceDegrees = 0.5;
    constexpr auto StoppedSpeed = 0.0f;
    const auto Normal = FQuat{FVector::RightVector, -FMath::DegreesToRadians(SlopeDegrees)}.RotateVector(FVector::UpVector);
    const auto X = AlongSlope * FMath::Cos(FMath::DegreesToRadians(SlopeDegrees));
    const auto PlaneZ = X * FMath::Tan(FMath::DegreesToRadians(SlopeDegrees));
    const auto BodyZ = PlaneZ + Clearance;
    const auto Feet = MakeFeetSupport(FVector::ZeroVector, Normal, FVector::ZeroVector, 200.0);
    auto Body = MakeBody(FVector{X, 0.0, BodyZ}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    constexpr auto Substeps = 120;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, StoppedSpeed, Step, &MissEverything, Feet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the feet hold the body (source %d)"), Index, Get_SourceValue(State)),
                State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Feet))
        { return false; }
    }

    const auto SupportDegrees = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(State.Get_SupportNormal(), Normal), -1.0, 1.0)));
    const auto Height = FVector::DotProduct(Body.GetLocation(), Normal);
    TestTrue(FString::Printf(TEXT("Over the miss the support has turned onto the plane's normal (%.3f degrees from it)"), SupportDegrees),
        SupportDegrees <= NormalToleranceDegrees);
    TestTrue(FString::Printf(TEXT("The body keeps its clearance from the plane under it along that normal (%.3f cm, expected %.1f)"), Height,
        Clearance), FMath::IsNearlyEqual(Height, static_cast<double>(Clearance), HeightTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionUnsetFeetTest,
    "Ck.ProceduralAnimation.SurfaceMotion.UnsetFeetSupportKeepsTheRayPath",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionUnsetFeetTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A floor, a 20 cm step, a drop back to the floor and a wall across the path: the body steps up, walks off, confirms and
    // climbs the wall. Once with no feet support, once with a support whose footprint lies 10 m away: every substep's body
    // and state are identical, bit for bit.
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeBox(FVector{50.0, -500.0, -10.0}, FVector{150.0, 500.0, 20.0}),
        MakeBox(FVector{300.0, -500.0, -50.0}, FVector{600.0, 500.0, 300.0})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto FarFeet = MakeFeetSupport(FVector{0.0, 0.0, 40.0}, FVector::UpVector, FVector{0.0, 1000.0, 0.0}, 100.0);

    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    auto FarBody = Body;
    auto FarState = State;

    constexpr auto Substeps = 300;
    auto SawWall = false;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, FarFeet, FarBody, FarState);
        SawWall = SawWall || State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance);

        const auto Same = Body.GetLocation() == FarBody.GetLocation() && Body.GetRotation() == FarBody.GetRotation()
            && State.Get_SupportNormal() == FarState.Get_SupportNormal() && State.Get_TravelTangent() == FarState.Get_TravelTangent()
            && State.Get_Velocity() == FarState.Get_Velocity() && State.Get_MissingContact() == FarState.Get_MissingContact()
            && State.Get_Grounded() == FarState.Get_Grounded() && State.Get_ContactTrusted() == FarState.Get_ContactTrusted()
            && State.Get_ContactSource() == FarState.Get_ContactSource() && State.Get_CandidateSeen() == FarState.Get_CandidateSeen()
            && State.Get_CandidateNormal() == FarState.Get_CandidateNormal();
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: a support whose footprint the body never enters changes nothing (%s vs %s)"),
                Index, *Body.GetLocation().ToString(), *FarBody.GetLocation().ToString()), Same))
        { return false; }
    }
    TestTrue(TEXT("Precondition: the sequence reaches the wall"), SawWall);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_surface_motion
{
    constexpr auto BlockX = 50.0;
    constexpr auto HalfSecondOfSubsteps = 60;

    auto
        MakeWallSettings(
            float InClearance,
            float InMaxStepHeight,
            ck::EProceduralSurfaceWallPolicy InWallPolicy)
        -> ck::FProceduralSurfaceMotionSettings
    {
        return MakeSettings()
            .Set_Clearance(InClearance)
            .Set_MaxStepHeight(InMaxStepHeight)
            .Set_WallPolicy(InWallPolicy);
    }

    // A floor and a block across the path from x = BlockX, InTop high.
    auto
        MakeFloorAndBlock(
            double InTop)
        -> TArray<FSolid>
    {
        return TArray<FSolid>{
            MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
            MakeBox(FVector{BlockX, -500.0, -10.0}, FVector{2000.0, 500.0, InTop})};
    }

    auto
        Get_DegreesFrom(
            const FVector& InA,
            const FVector& InB)
        -> double
    {
        return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(InA.GetSafeNormal(), InB.GetSafeNormal()), -1.0, 1.0)));
    }

    auto
        Get_IsOnBlockFace(
            const ck::FProceduralSurfaceHit& InHit)
        -> bool
    {
        return InHit.Get_Hit() && InHit.Get_Normal().Equals(FVector::BackwardVector, DistanceTolerance)
            && FMath::IsNearlyEqual(InHit.Get_Position().X, BlockX, DistanceTolerance);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionStepsOntoAFaceTest,
    "Ck.ProceduralAnimation.SurfaceMotion.StepsOntoAFaceAboveClearanceWithinStepHeight",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionStepsOntoAFaceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A 40 cm block ahead of a body 30 cm over the floor: the forward ray, at the body's height, meets the block's face,
    // whose top lies within the 45 cm step height of the floor under the body. The body rises onto the top without turning.
    constexpr auto StepClearance = 30.0f;
    constexpr auto StepHeight = 45.0f;
    constexpr auto BlockTop = 40.0;
    constexpr auto HeightTolerance = 1.0;
    constexpr auto MaxTiltDegrees = 10.0;
    const auto World = MakeFloorAndBlock(BlockTop);
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeWallSettings(StepClearance, StepHeight, ck::EProceduralSurfaceWallPolicy::Climb);
    auto Body = MakeBody(FVector{0.0, 0.0, StepClearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto StepSubsteps = 0;
    auto WorstTilt = 0.0;
    for (auto Index = 0; Index < HalfSecondOfSubsteps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        StepSubsteps += State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Step ? 1 : 0;
        WorstTilt = FMath::Max(WorstTilt, Get_DegreesFrom(State.Get_SupportNormal(), FVector::UpVector));
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the face is never adopted (source %d, normal %s)"), Index,
                static_cast<int32>(State.Get_ContactSource()), *State.Get_SupportNormal().ToString()),
                State.Get_ContactSource() != ck::EProceduralSurfaceContactSource::Forward))
        { return false; }
    }

    TestTrue(FString::Printf(TEXT("The step's contact carried the body onto the top (%d substeps with source Step)"), StepSubsteps),
        StepSubsteps > 0);
    TestTrue(FString::Printf(TEXT("No substep's support normal turned more than %.0f degrees from up (worst %.3f)"), MaxTiltDegrees,
        WorstTilt), WorstTilt <= MaxTiltDegrees);
    const auto Height = Body.GetLocation().Z - BlockTop;
    TestTrue(FString::Printf(TEXT("Within 0.5 s the body stands one clearance over the block's top (%.3f cm over it, x %.1f)"), Height,
        Body.GetLocation().X), FMath::IsNearlyEqual(Height, static_cast<double>(StepClearance), HeightTolerance));
    TestTrue(FString::Printf(TEXT("The support normal is still up (%s)"), *State.Get_SupportNormal().ToString()),
        State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionClimbsAboveStepHeightTest,
    "Ck.ProceduralAnimation.SurfaceMotion.ClimbsAFaceAboveStepHeight",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionClimbsAboveStepHeightTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A 100 cm face against a 45 cm step height: not a step, so the climbing body confirms and adopts it as before.
    constexpr auto StepClearance = 30.0f;
    constexpr auto StepHeight = 45.0f;
    constexpr auto FaceTop = 100.0;
    const auto World = MakeFloorAndBlock(FaceTop);
    auto SawFace = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawFace = SawFace || Get_IsOnBlockFace(Hit);
        return Hit;
    };
    const auto Settings = MakeWallSettings(StepClearance, StepHeight, ck::EProceduralSurfaceWallPolicy::Climb);
    auto Body = MakeBody(FVector{0.0, 0.0, StepClearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto FirstSighting = int32{INDEX_NONE};
    auto Adopted = int32{INDEX_NONE};
    for (auto Index = 0; Index < MaxSubsteps && Adopted == INDEX_NONE; ++Index)
    {
        SawFace = false;
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (SawFace && FirstSighting == INDEX_NONE)
        { FirstSighting = Index; }
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: a face above the step height is never a step"), Index),
                State.Get_ContactSource() != ck::EProceduralSurfaceContactSource::Step))
        { return false; }
        if (State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance))
        { Adopted = Index; }
    }
    if (NOT TestTrue(TEXT("The forward ray sees the face and the body adopts it"), FirstSighting != INDEX_NONE && Adopted != INDEX_NONE))
    { return false; }

    const auto Seen = Step * (Adopted - FirstSighting + 1);
    TestTrue(FString::Printf(TEXT("The face is adopted after it is seen for the confirm time, not before (seen %.4f s, confirm %.4f s)"),
        Seen.Get_Seconds(), ConfirmTime.Get_Seconds()),
        Seen.Get_Seconds() >= ConfirmTime.Get_Seconds() - TimeTolerance
        && Seen.Get_Seconds() <= (ConfirmTime + Step).Get_Seconds() + TimeTolerance);
    TestEqual(TEXT("The face is adopted from the forward ray"), State.Get_ContactSource(), ck::EProceduralSurfaceContactSource::Forward);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionStepHeightZeroTest,
    "Ck.ProceduralAnimation.SurfaceMotion.StepHeightZeroClimbsEveryFace",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionStepHeightZeroTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The 40 cm block a 45 cm step height steps onto, with the default step height of 0: the body climbs its face.
    constexpr auto StepClearance = 30.0f;
    constexpr auto BlockTop = 40.0;
    const auto World = MakeFloorAndBlock(BlockTop);
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeSettings().Set_Clearance(StepClearance);
    auto Body = MakeBody(FVector{0.0, 0.0, StepClearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto Adopted = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Adopted; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: no step without a step height (source %d)"), Index,
                static_cast<int32>(State.Get_ContactSource())), State.Get_ContactSource() != ck::EProceduralSurfaceContactSource::Step))
        { return false; }
        Adopted = State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance);
    }
    TestTrue(TEXT("The block's face is adopted as a wall"), Adopted);
    TestEqual(TEXT("The wall is adopted from the forward ray"), State.Get_ContactSource(), ck::EProceduralSurfaceContactSource::Forward);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionLowFaceUnseenTest,
    "Ck.ProceduralAnimation.SurfaceMotion.LowFaceIsNeverSeenByTheForwardRay",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionLowFaceUnseenTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A 40 cm riser under a body 65 cm over the floor: the forward ray passes over its top, and the down ray lifts the body
    // onto the tread once it is over it. With a step height of 0 and of 85 every substep is the same, bit for bit.
    constexpr auto RiserTop = 40.0;
    constexpr auto HighStepHeight = 85.0f;
    constexpr auto HeightTolerance = 1.0;
    constexpr auto Substeps = 150;
    const auto World = MakeFloorAndBlock(RiserTop);
    auto RiserHits = 0;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        RiserHits += Get_IsOnBlockFace(Hit) ? 1 : 0;
        return Hit;
    };
    const auto NoStepSettings = MakeSettings();
    const auto StepSettings = MakeWallSettings(Clearance, HighStepHeight, ck::EProceduralSurfaceWallPolicy::Climb);
    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    auto StepBody = Body;
    auto StepState = State;

    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(NoStepSettings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        ck::StepProceduralSurfaceMotion(StepSettings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, StepBody, StepState);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the down ray holds the body (source %d)"), Index,
                static_cast<int32>(State.Get_ContactSource())), State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down))
        { return false; }

        const auto Same = Body.GetLocation() == StepBody.GetLocation() && Body.GetRotation() == StepBody.GetRotation()
            && State.Get_SupportNormal() == StepState.Get_SupportNormal() && State.Get_TravelTangent() == StepState.Get_TravelTangent()
            && State.Get_Velocity() == StepState.Get_Velocity() && State.Get_ContactSource() == StepState.Get_ContactSource()
            && State.Get_CandidateSeen() == StepState.Get_CandidateSeen();
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the step height changes nothing (%s vs %s)"), Index,
                *Body.GetLocation().ToString(), *StepBody.GetLocation().ToString()), Same))
        { return false; }
    }

    TestEqual(TEXT("No ray ever met the riser's face"), RiserHits, 0);
    TestTrue(FString::Printf(TEXT("The body rose onto the tread (z %.3f, x %.1f)"), Body.GetLocation().Z, Body.GetLocation().X),
        FMath::IsNearlyEqual(Body.GetLocation().Z, RiserTop + Clearance, HeightTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_surface_motion
{
    // A wall at 30 degrees to the travel, facing a body that walks +X toward it on a floor.
    constexpr auto ObliqueWallDegrees = 30.0;
    const auto ObliqueWallPoint = FVector{100.0, 0.0, 0.0};

    auto
        Get_ObliqueWallNormal()
        -> FVector
    {
        return FVector{-FMath::Sin(FMath::DegreesToRadians(ObliqueWallDegrees)), FMath::Cos(FMath::DegreesToRadians(ObliqueWallDegrees)), 0.0};
    }

    auto
        Get_AlongObliqueWall()
        -> FVector
    {
        return FVector{FMath::Cos(FMath::DegreesToRadians(ObliqueWallDegrees)), FMath::Sin(FMath::DegreesToRadians(ObliqueWallDegrees)), 0.0};
    }

    auto
        MakeFloorAndObliqueWall()
        -> TArray<FSolid>
    {
        return TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector), MakeHalfSpace(Get_ObliqueWallNormal(), ObliqueWallPoint)};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionSlidesAlongObliqueWallTest,
    "Ck.ProceduralAnimation.SurfaceMotion.SlidesAlongAnObliqueWall",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionSlidesAlongObliqueWallTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The forward ray first meets a wall at 30 degrees to the travel when the body is a clearance x sin 30 from it. From
    // then on the body follows the wall: it slides along it at the travel's share along it, speed x cos 30, and eases out
    // to its clearance at the clearance speed, never jumping.
    constexpr auto SpeedTolerance = 0.05;
    constexpr auto NearestTolerance = 1.0;
    constexpr auto SettledShareOfClearance = 0.95;
    constexpr auto SettleSeconds = 0.3;
    constexpr auto Substeps = 240;
    constexpr auto ClearanceSpeed = 200.0;
    const auto WallNormal = Get_ObliqueWallNormal();
    const auto AlongWall = Get_AlongObliqueWall();
    const auto World = MakeFloorAndObliqueWall();
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeWallSettings(Clearance, 0.0f, ck::EProceduralSurfaceWallPolicy::Slide);
    auto Body = MakeBody(FVector{-100.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    const auto MaxStepAlongNormal = ClearanceSpeed * Step.Get_Seconds() + DistanceTolerance;

    auto FirstSighting = int32{INDEX_NONE};
    auto NearestToWall = TNumericLimits<double>::Max();
    auto NearestAt = int32{INDEX_NONE};
    auto FirstSightingToWall = 0.0;
    auto LargestAlongNormal = 0.0;
    auto NearestOnceSettled = TNumericLimits<double>::Max();
    auto HalfwayAlong = 0.0;
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        const auto Before = Body.GetLocation();
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        const auto ToWall = FVector::DotProduct(Body.GetLocation() - ObliqueWallPoint, WallNormal);
        const auto AlongNormal = FVector::DotProduct(Body.GetLocation() - Before, WallNormal);
        LargestAlongNormal = FMath::Max(LargestAlongNormal, FMath::Abs(AlongNormal));
        if (ToWall < NearestToWall)
        {
            NearestToWall = ToWall;
            NearestAt = Index;
        }
        if (Index == Substeps / 2 - 1)
        { HalfwayAlong = FVector::DotProduct(Body.GetLocation(), AlongWall); }
        if (FirstSighting == INDEX_NONE && State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall)
        {
            FirstSighting = Index;
            FirstSightingToWall = ToWall;
        }

        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the body moves along the wall's normal by at most the clearance speed's step (%.4f cm)"),
                Index, AlongNormal), FMath::Abs(AlongNormal) <= MaxStepAlongNormal))
        { return false; }
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the support normal stays up and the body grounded (%s)"), Index,
                *State.Get_SupportNormal().ToString()), State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance) && State.Get_Grounded()))
        { return false; }
        if (FirstSighting == INDEX_NONE)
        { continue; }

        if (NOT TestTrue(FString::Printf(TEXT("Substep %d, after the first sighting on %d: the obstruction reads Wall with the wall's normal (%d, %s)"),
                Index, FirstSighting, static_cast<int32>(State.Get_Obstruction()), *State.Get_ObstructionNormal().ToString()),
                State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall && State.Get_ObstructionNormal().Equals(WallNormal, DistanceTolerance)))
        { return false; }
        const auto Settled = (Step * (Index - FirstSighting)).Get_Seconds() >= SettleSeconds;
        if (Settled)
        { NearestOnceSettled = FMath::Min(NearestOnceSettled, ToWall); }
        if (Settled && NOT TestTrue(FString::Printf(TEXT("Substep %d, %.3f s after the first sighting: the body stands at least 0.95 clearance "
                "off the wall (%.3f cm)"), Index, (Step * (Index - FirstSighting)).Get_Seconds(), ToWall),
                ToWall >= SettledShareOfClearance * Clearance))
        { return false; }
    }

    if (NOT TestTrue(TEXT("The forward ray met the wall"), FirstSighting != INDEX_NONE))
    { return false; }
    const auto FirstSightingDistance = Clearance * FMath::Sin(FMath::DegreesToRadians(ObliqueWallDegrees));
    TestTrue(FString::Printf(TEXT("The nearest approach is the first sighting's, a clearance x sin 30 off the wall (nearest %.3f cm on substep %d, "
        "bound %.3f)"), NearestToWall, NearestAt, FirstSightingDistance - NearestTolerance), NearestToWall >= FirstSightingDistance - NearestTolerance);
    const auto AlongSpeed = (FVector::DotProduct(Body.GetLocation(), AlongWall) - HalfwayAlong) / (Step * (Substeps / 2)).Get_Seconds();
    const auto Expected = Speed * FMath::Cos(FMath::DegreesToRadians(ObliqueWallDegrees));
    TestTrue(FString::Printf(TEXT("Over the last second the body moves along the wall at speed x cos 30 (%.2f cm/s against %.2f)"), AlongSpeed,
        Expected), FMath::Abs(AlongSpeed - Expected) <= SpeedTolerance * Expected);
    AddInfo(FString::Printf(TEXT("Oblique wall: first sighting on substep %d at %.3f cm, nearest %.3f cm on substep %d, largest move along the "
        "normal %.4f cm (bound %.4f), nearest from %.1f s after the sighting on %.3f cm, speed along the wall %.2f cm/s (expected %.2f)"),
        FirstSighting, FirstSightingToWall, NearestToWall, NearestAt, LargestAlongNormal, MaxStepAlongNormal, SettleSeconds, NearestOnceSettled,
        AlongSpeed, Expected));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionWallFollowingEndsTest,
    "Ck.ProceduralAnimation.SurfaceMotion.WallFollowingEndsWhenTheSteeringTurnsAway",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionWallFollowingEndsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The oblique wall: once the body follows it, the steering turns parallel to it. The obstruction ends on the next
    // substep and the body walks on at its full speed.
    constexpr auto SpeedTolerance = 0.05;
    constexpr auto FollowSubsteps = 2 * HalfSecondOfSubsteps;
    const auto AlongWall = Get_AlongObliqueWall();
    const auto World = MakeFloorAndObliqueWall();
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeWallSettings(Clearance, 0.0f, ck::EProceduralSurfaceWallPolicy::Slide);
    auto Body = MakeBody(FVector{-100.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto FirstSighting = int32{INDEX_NONE};
    for (auto Index = 0; Index < MaxSubsteps && (FirstSighting == INDEX_NONE || Index < FirstSighting + FollowSubsteps); ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (FirstSighting == INDEX_NONE && State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall)
        { FirstSighting = Index; }
    }
    if (NOT TestTrue(FString::Printf(TEXT("Precondition: the body follows the wall (first sighting %d, obstruction %d)"), FirstSighting,
            static_cast<int32>(State.Get_Obstruction())), FirstSighting != INDEX_NONE && State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall))
    { return false; }

    ck::StepProceduralSurfaceMotion(Settings, AlongWall, Speed, Step, Cast, NoFeet, Body, State);
    TestTrue(FString::Printf(TEXT("On the first substep steered along the wall the obstruction ends (%d)"), static_cast<int32>(State.Get_Obstruction())),
        State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::None);

    const auto Start = Body.GetLocation();
    for (auto Index = 0; Index < HalfSecondOfSubsteps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, AlongWall, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d steered along the wall: no obstruction (%d)"), Index, static_cast<int32>(State.Get_Obstruction())),
                State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::None))
        { return false; }
    }
    const auto WalkedSpeed = FVector::DotProduct(Body.GetLocation() - Start, AlongWall) / (Step * HalfSecondOfSubsteps).Get_Seconds();
    TestTrue(FString::Printf(TEXT("The body walks along the wall at its full speed (%.2f cm/s against %.2f)"), WalkedSpeed, static_cast<double>(Speed)),
        FMath::Abs(WalkedSpeed - Speed) <= SpeedTolerance * Speed);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionSlideStopsHeadOnTest,
    "Ck.ProceduralAnimation.SurfaceMotion.StopsAgainstAHeadOnWallWithSlide",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionSlideStopsHeadOnTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A wall across the path: sliding takes the whole travel away, so the body stops in front of it and stays grounded.
    constexpr auto StillTolerance = 1.0;
    const auto World = MakeFloorAndWall();
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeWallSettings(Clearance, 0.0f, ck::EProceduralSurfaceWallPolicy::Slide);
    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto Obstructed = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Obstructed; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        Obstructed = State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall;
    }
    if (NOT TestTrue(TEXT("The body reaches the wall"), Obstructed))
    { return false; }

    const auto Stopped = Body.GetLocation();
    constexpr auto OneSecond = 2 * HalfSecondOfSubsteps;
    for (auto Index = 0; Index < OneSecond; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d after reaching it: grounded against the wall (obstruction %d, normal %s)"), Index,
                static_cast<int32>(State.Get_Obstruction()), *State.Get_ObstructionNormal().ToString()),
                State.Get_Grounded() && State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall
                && State.Get_ObstructionNormal().Equals(FVector::BackwardVector, DistanceTolerance)
                && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
        { return false; }
    }

    const auto Moved = FVector::Distance(Body.GetLocation(), Stopped);
    TestTrue(FString::Printf(TEXT("Over 1 s against the wall the body moves %.4f cm, under %.0f"), Moved, StillTolerance), Moved < StillTolerance);
    TestTrue(FString::Printf(TEXT("The body stands at least one clearance from the wall (x %.3f)"), Body.GetLocation().X),
        Body.GetLocation().X <= WallX - Clearance + DistanceTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionSlideNeverProposesTheFaceTest,
    "Ck.ProceduralAnimation.SurfaceMotion.SlideNeverProposesTheFace",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionSlideNeverProposesTheFaceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The floor and the wall the confirmation test climbs: with Slide the wall is never the body's contact.
    constexpr auto Substeps = 240;
    const auto World = MakeFloorAndWall();
    auto SawWall = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawWall = SawWall || Get_IsOnWall(Hit);
        return Hit;
    };
    const auto Settings = MakeWallSettings(Clearance, 0.0f, ck::EProceduralSurfaceWallPolicy::Slide);
    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the contact is never the forward ray's (source %d, normal %s)"), Index,
                static_cast<int32>(State.Get_ContactSource()), *State.Get_SupportNormal().ToString()),
                State.Get_ContactSource() != ck::EProceduralSurfaceContactSource::Forward))
        { return false; }
    }
    TestTrue(TEXT("Precondition: the forward ray met the wall"), SawWall);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionStepBeatsSlideTest,
    "Ck.ProceduralAnimation.SurfaceMotion.StepBeatsSlide",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionStepBeatsSlideTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The 40 cm block and the 45 cm step height with Slide: a step is not a wall, so the body steps up and nothing slides.
    constexpr auto StepClearance = 30.0f;
    constexpr auto StepHeight = 45.0f;
    constexpr auto BlockTop = 40.0;
    constexpr auto HeightTolerance = 1.0;
    const auto World = MakeFloorAndBlock(BlockTop);
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeWallSettings(StepClearance, StepHeight, ck::EProceduralSurfaceWallPolicy::Slide);
    auto Body = MakeBody(FVector{0.0, 0.0, StepClearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto StepSubsteps = 0;
    for (auto Index = 0; Index < HalfSecondOfSubsteps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        StepSubsteps += State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Step ? 1 : 0;
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: no obstruction (%d)"), Index, static_cast<int32>(State.Get_Obstruction())),
                State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::None))
        { return false; }
    }

    TestTrue(FString::Printf(TEXT("The body stepped up (%d substeps with source Step)"), StepSubsteps), StepSubsteps > 0);
    const auto Height = Body.GetLocation().Z - BlockTop;
    TestTrue(FString::Printf(TEXT("The body stands one clearance over the block's top (%.3f cm over it, x %.1f)"), Height,
        Body.GetLocation().X), FMath::IsNearlyEqual(Height, static_cast<double>(StepClearance), HeightTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_surface_motion
{
    // A first block whose top and face end at InFirstFaceX, 150 cm high, and a 50 cm wide, 150 cm pillar whose near face
    // stands at x = 50, both on a floor.
    constexpr auto FaceTop = 150.0;
    constexpr auto SecondFaceX = 50.0;
    constexpr auto PillarWidth = 50.0;

    auto
        MakeFacesAcrossAGap(
            double InFirstFaceX)
        -> TArray<FSolid>
    {
        return TArray<FSolid>{
            MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
            MakeBox(FVector{-1000.0, -500.0, -10.0}, FVector{InFirstFaceX, 500.0, FaceTop}),
            MakeBox(FVector{SecondFaceX, -500.0, -10.0}, FVector{SecondFaceX + PillarWidth, 500.0, FaceTop})};
    }

    auto
        Get_IsInside(
            const FVector& InPosition,
            double InFirstFaceX)
        -> bool
    {
        const auto BelowTops = InPosition.Z < FaceTop;
        return BelowTops && (InPosition.X < InFirstFaceX
            || (InPosition.X > SecondFaceX && InPosition.X < SecondFaceX + PillarWidth));
    }

    // A body that left the first top's edge 5 cm behind it, falling with no steering at 80 cm/s along +X. The probe reach
    // is just over the clearance, so the down ray cannot catch the body before the swept fall lands it.
    constexpr auto FallStartX = 5.0;
    constexpr auto FallSpeed = 80.0;
    constexpr auto ShortProbeReach = 66.0f;

    auto
        MakeFallingState()
        -> ck::FProceduralSurfaceMotionState
    {
        return MakeState(FVector::UpVector, FVector::ForwardVector, false).Set_Velocity(FVector{FallSpeed, 0.0, 0.0});
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFallRefusesTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FallRefusesAFaceWithoutRoom",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFallRefusesTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The gap between the faces is 50 cm, less than the 65 cm clearance: the fall meets the second face, but a body one
    // clearance off it would stand inside the first. The landing is refused and the body falls on to the gap's floor.
    constexpr auto FirstFaceX = 0.0;
    const auto World = MakeFacesAcrossAGap(FirstFaceX);
    auto SawSecondFace = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawSecondFace = SawSecondFace || (Hit.Get_Hit() && Hit.Get_Normal().Equals(FVector::BackwardVector, DistanceTolerance)
            && FMath::IsNearlyEqual(Hit.Get_Position().X, SecondFaceX, DistanceTolerance));
        return Hit;
    };
    const auto Settings = MakeSettings().Set_ProbeReach(ShortProbeReach);
    auto Body = MakeBody(FVector{FallStartX, 0.0, FaceTop + Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeFallingState();
    constexpr auto Coasting = 0.0f;

    auto Landed = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Landed; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Coasting, Step, Cast, NoFeet, Body, State);
        const auto Position = Body.GetLocation();
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the body stays inside the gap, above the floor (%s)"), Index, *Position.ToString()),
                Position.X > FirstFaceX && Position.X < SecondFaceX && Position.Z >= 0.0 && NOT Get_IsInside(Position, FirstFaceX)))
        { return false; }
        Landed = State.Get_Grounded();
    }

    TestTrue(TEXT("Precondition: the fall met the second face"), SawSecondFace);
    if (NOT TestTrue(TEXT("The body lands"), Landed))
    { return false; }
    TestTrue(FString::Printf(TEXT("It lands on the gap's floor from the fall, facing up (source %d, normal %s, z %.3f)"),
        static_cast<int32>(State.Get_ContactSource()), *State.Get_SupportNormal().ToString(), Body.GetLocation().Z),
        State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Fall
        && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)
        && FMath::IsNearlyEqual(Body.GetLocation().Z, static_cast<double>(Clearance), DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFallLandsWithRoomTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FallLandsOnAFaceWithRoom",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFallLandsWithRoomTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The same fall with the first face 200 cm back from the second: a clearance of free space lies off the second face,
    // and the body grabs it as a wall.
    constexpr auto FirstFaceX = SecondFaceX - 200.0;
    const auto World = MakeFacesAcrossAGap(FirstFaceX);
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeSettings().Set_ProbeReach(ShortProbeReach);
    auto Body = MakeBody(FVector{FallStartX, 0.0, FaceTop + Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeFallingState();
    constexpr auto Coasting = 0.0f;

    auto Landed = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Landed; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, Coasting, Step, Cast, NoFeet, Body, State);
        Landed = State.Get_Grounded();
    }

    if (NOT TestTrue(TEXT("The body lands"), Landed))
    { return false; }
    const auto OffFace = SecondFaceX - Body.GetLocation().X;
    TestTrue(FString::Printf(TEXT("It lands on the second face from the fall, one clearance off it (source %d, normal %s, %.3f cm off)"),
        static_cast<int32>(State.Get_ContactSource()), *State.Get_SupportNormal().ToString(), OffFace),
        State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Fall
        && State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance)
        && FMath::IsNearlyEqual(OffFace, static_cast<double>(Clearance), DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionFanRefusesTest,
    "Ck.ProceduralAnimation.SurfaceMotion.FanRefusesAFaceWithoutRoom",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionFanRefusesTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A body walking slowly off the first top toward a pillar 50 cm past its edge, less than its 65 cm clearance. Past the
    // edge the look-ahead lands beyond the pillar and misses, and the fan finds the first top's far face: a body one clearance
    // off it would stand inside the pillar, so the fan's contact is refused. The body coasts, falls and lands on the gap's
    // floor, where the pillar's near face, without room either, keeps it from walking on.
    constexpr auto FirstFaceX = 0.0;
    constexpr auto WalkSpeed = 30.0f;
    constexpr auto RefusedFaceDegrees = 30.0;
    constexpr auto HeightTolerance = 1.0;
    constexpr auto MaxWalkSubsteps = 600;
    constexpr auto StandSubsteps = 2 * HalfSecondOfSubsteps;
    const auto World = MakeFacesAcrossAGap(FirstFaceX);
    auto SawFarFace = false;
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd)
    {
        const auto Hit = RayCast(World, InStart, InEnd);
        SawFarFace = SawFarFace || (Hit.Get_Hit() && Hit.Get_Normal().Equals(FVector::ForwardVector, DistanceTolerance)
            && FMath::IsNearlyEqual(Hit.Get_Position().X, FirstFaceX, DistanceTolerance));
        return Hit;
    };
    const auto Settings = MakeSettings();
    auto Body = MakeBody(FVector{-10.0, 0.0, FaceTop + Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    const auto Check = [&](int32 InIndex) -> bool
    {
        const auto Position = Body.GetLocation();
        return TestTrue(FString::Printf(TEXT("Substep %d: the first top's far face is never the support and the body never stands inside a "
                "solid (%s, normal %s)"), InIndex, *Position.ToString(), *State.Get_SupportNormal().ToString()),
            Get_DegreesFrom(State.Get_SupportNormal(), FVector::ForwardVector) > RefusedFaceDegrees && NOT Get_IsInside(Position, FirstFaceX));
    };

    auto OnTheGapFloor = false;
    for (auto Index = 0; Index < MaxWalkSubsteps && NOT OnTheGapFloor; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, WalkSpeed, Step, Cast, NoFeet, Body, State);
        if (NOT Check(Index))
        { return false; }
        OnTheGapFloor = Body.GetLocation().X > FirstFaceX && State.Get_Grounded()
            && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down;
    }
    TestTrue(TEXT("Precondition: the fan met the first top's far face"), SawFarFace);
    if (NOT TestTrue(TEXT("The body comes down on the gap's floor"), OnTheGapFloor))
    { return false; }

    for (auto Index = 0; Index < StandSubsteps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, WalkSpeed, Step, Cast, NoFeet, Body, State);
        if (NOT Check(Index))
        { return false; }
    }
    const auto Position = Body.GetLocation();
    TestTrue(FString::Printf(TEXT("The body stands one clearance over the gap's floor, between the faces (%s, normal %s)"),
        *Position.ToString(), *State.Get_SupportNormal().ToString()),
        Position.X > FirstFaceX && Position.X < SecondFaceX && FMath::IsNearlyEqual(Position.Z, static_cast<double>(Clearance), HeightTolerance)
        && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionConcaveCornerTest,
    "Ck.ProceduralAnimation.SurfaceMotion.ConcaveCornerStillAdopts",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionConcaveCornerTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A floor meeting a wall at 90 degrees: the wall has a clearance of free space off it, so the climbing body confirms and
    // adopts it as before.
    const auto World = MakeFloorAndWall();
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto Adopted = false;
    for (auto Index = 0; Index < MaxSubsteps && NOT Adopted; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        Adopted = State.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance);
    }
    TestTrue(TEXT("The wall at the corner is adopted"), Adopted);
    TestEqual(TEXT("It is adopted from the forward ray"), State.Get_ContactSource(), ck::EProceduralSurfaceContactSource::Forward);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionRefusedFaceSlidTest,
    "Ck.ProceduralAnimation.SurfaceMotion.RefusedFaceIsSlidAlongUnderClimb",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionRefusedFaceSlidTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // A climbing body on the floor of a 50 cm corridor between two tall faces, walking into the one ahead. A body one
    // clearance off that face would stand inside the one behind, so it cannot be climbed: it is slid along instead.
    constexpr auto CorridorWidth = 50.0;
    constexpr auto FaceHeight = 300.0;
    constexpr auto Substeps = 2 * HalfSecondOfSubsteps;
    const auto World = TArray<FSolid>{
        MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeBox(FVector{-1000.0, -500.0, -10.0}, FVector{0.0, 500.0, FaceHeight}),
        MakeBox(FVector{CorridorWidth, -500.0, -10.0}, FVector{1000.0, 500.0, FaceHeight})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    auto Body = MakeBody(FVector{0.5 * CorridorWidth - 5.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto FirstSighting = int32{INDEX_NONE};
    for (auto Index = 0; Index < Substeps; ++Index)
    {
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, NoFeet, Body, State);
        const auto X = Body.GetLocation().X;
        if (NOT TestTrue(FString::Printf(TEXT("Substep %d: the face ahead is never the contact and the body stays in the corridor (source %d, x %.3f)"),
                Index, static_cast<int32>(State.Get_ContactSource()), X),
                State.Get_ContactSource() != ck::EProceduralSurfaceContactSource::Forward && X > 0.0 && X < CorridorWidth))
        { return false; }
        if (FirstSighting == INDEX_NONE && State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall)
        { FirstSighting = Index; }
        if (FirstSighting != INDEX_NONE && NOT TestTrue(FString::Printf(TEXT("Substep %d: the face ahead obstructs the body (%d, %s)"), Index,
                static_cast<int32>(State.Get_Obstruction()), *State.Get_ObstructionNormal().ToString()),
                State.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall
                && State.Get_ObstructionNormal().Equals(FVector::BackwardVector, DistanceTolerance)))
        { return false; }
    }
    TestTrue(TEXT("The face ahead became an obstruction"), FirstSighting != INDEX_NONE);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionNarrowGapStopsMidGapTest,
    "Ck.ProceduralAnimation.SurfaceMotion.NarrowGapSlideStopsMidGap",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionNarrowGapStopsMidGapTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // The fan's scene, climbing and sliding: the body walks off the first top into the 50 cm gap, narrower than its
    // clearance, and on toward the pillar. Whatever its wall policy it ends standing in the middle of the gap.
    constexpr auto FirstFaceX = 0.0;
    constexpr auto WalkSpeed = 30.0f;
    constexpr auto MiddleTolerance = 5.0;
    constexpr auto Substeps = 1200;
    const auto Middle = 0.5 * (FirstFaceX + SecondFaceX);
    const auto World = MakeFacesAcrossAGap(FirstFaceX);
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };

    for (const auto WallPolicy : {ck::EProceduralSurfaceWallPolicy::Climb, ck::EProceduralSurfaceWallPolicy::Slide})
    {
        const auto PolicyName = WallPolicy == ck::EProceduralSurfaceWallPolicy::Slide ? TEXT("Slide") : TEXT("Climb");
        const auto Settings = MakeSettings().Set_WallPolicy(WallPolicy);
        auto Body = MakeBody(FVector{-10.0, 0.0, FaceTop + Clearance}, FVector::UpVector, FVector::ForwardVector);
        auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
        for (auto Index = 0; Index < Substeps; ++Index)
        {
            ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, WalkSpeed, Step, Cast, NoFeet, Body, State);
            if (NOT TestTrue(FString::Printf(TEXT("%s, substep %d: the body never stands inside a solid (%s)"), PolicyName, Index,
                    *Body.GetLocation().ToString()), NOT Get_IsInside(Body.GetLocation(), FirstFaceX)))
            { return false; }
        }
        const auto Position = Body.GetLocation();
        AddInfo(FString::Printf(TEXT("%s: the body ends at %s, obstruction %d"), PolicyName, *Position.ToString(),
            static_cast<int32>(State.Get_Obstruction())));
        TestTrue(FString::Printf(TEXT("%s: the body ends on the gap's floor within %.0f cm of its middle (%s, normal %s)"), PolicyName,
            MiddleTolerance, *Position.ToString(), *State.Get_SupportNormal().ToString()),
            FMath::Abs(Position.X - Middle) <= MiddleTolerance && Position.Z < FaceTop && State.Get_Grounded()
            && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionVoluntaryPacePreservesPhysicsTest,
    "Ck.ProceduralAnimation.SurfaceMotion.VoluntaryPacePreservesPhysics",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionVoluntaryPacePreservesPhysicsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto Floor = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto FloorCast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(Floor, InStart, InEnd); };
    auto Body = MakeBody(FVector{-100.0, 0.0, Clearance + 10.0}, FVector::UpVector, FVector::ForwardVector);
    auto State = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    const auto Start = Body;
    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, FloorCast, NoFeet, Body, State, 0.0f);
    TestTrue(TEXT("Zero voluntary scale retains translation and rotation while refreshing trusted ground"),
        Body.Equals(Start, DistanceTolerance) && State.Get_Grounded() && State.Get_ContactTrusted()
        && State.Get_ContactSource() == ck::EProceduralSurfaceContactSource::Down
        && State.Get_Velocity().IsNearlyZero());

    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, FloorCast, NoFeet, Body, State, 1.0f);
    TestTrue(TEXT("Releasing the pace resumes travel and clearance correction"),
        Body.GetLocation().X > Start.GetLocation().X && Body.GetLocation().Z < Start.GetLocation().Z);

    const auto Wall = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector),
        MakeBox(FVector{0.0, -200.0, -10.0}, FVector{100.0, 200.0, 300.0})};
    const auto WallCast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(Wall, InStart, InEnd); };
    auto WallBody = MakeBody(FVector{-50.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto WallState = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    const auto WallStart = WallBody;
    for (auto Index = 0; Index < 16; ++Index)
    { ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, WallCast, NoFeet, WallBody, WallState, 0.0f); }
    TestTrue(TEXT("A paused walker keeps sensing and can confirm the wall without voluntary travel or turn"),
        WallBody.Equals(WallStart, DistanceTolerance) && WallState.Get_Grounded() && WallState.Get_ContactTrusted()
        && WallState.Get_SupportNormal().Equals(FVector::BackwardVector, DistanceTolerance));
    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, WallCast, NoFeet, WallBody, WallState, 1.0f);
    TestTrue(TEXT("The body turns toward the confirmed wall when pacing releases"),
        WallBody.GetRotation().AngularDistance(WallStart.GetRotation()) > 0.0);

    const auto Slide = MakeSettings().Set_WallPolicy(ck::EProceduralSurfaceWallPolicy::Slide);
    auto ObstructedBody = MakeBody(FVector{-2.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    auto ObstructedState = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    ck::StepProceduralSurfaceMotion(Slide, FVector::ForwardVector, Speed, Step, WallCast, NoFeet, ObstructedBody, ObstructedState, 0.0f);
    TestTrue(TEXT("Zero voluntary scale still lets a wall push the body out of its standoff"),
        ObstructedBody.GetLocation().X < -2.0 && ObstructedState.Get_Obstruction() == ck::EProceduralSurfaceObstruction::Wall);

    const auto Empty = TArray<FSolid>{};
    const auto Miss = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(Empty, InStart, InEnd); };
    auto FallingBody = MakeBody(FVector{0.0, 0.0, 200.0}, FVector::UpVector, FVector::ForwardVector);
    auto FallingState = MakeState(FVector::UpVector, FVector::ForwardVector, false);
    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Miss, NoFeet, FallingBody, FallingState, 0.0f);
    TestTrue(TEXT("Zero voluntary scale does not suppress gravity"), FallingBody.GetLocation().Z < 200.0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionTurnOnlyPaceDrivesStanceTest,
    "Ck.ProceduralAnimation.SurfaceMotion.TurnOnlyPaceReportsAttemptedStanceMotion",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionTurnOnlyPaceDrivesStanceTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    const auto Floor = TArray<FSolid>{MakeHalfSpace(FVector::UpVector, FVector::ZeroVector)};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(Floor, InStart, InEnd); };
    const auto Settings = MakeSettings();
    const auto StartBody = MakeBody(FVector{0.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    const auto StartState = MakeState(FVector::UpVector, FVector::ForwardVector, true);
    constexpr auto Reach = 65.0f;
    const auto Anchors = TArray<ck::FProceduralSurfaceReachPaceAnchor>{
        ck::FProceduralSurfaceReachPaceAnchor{FVector{40.0, -Reach, Clearance}, FVector{40.0, 0.0, 0.0}, Reach}};

    auto FullBody = StartBody;
    auto FullState = StartState;
    ck::StepProceduralSurfaceMotion(Settings, FVector::RightVector, 0.0f, Step, Cast, NoFeet, FullBody, FullState);
    auto ZeroBody = StartBody;
    auto ZeroState = StartState;
    ck::StepProceduralSurfaceMotion(Settings, FVector::RightVector, 0.0f, Step, Cast, NoFeet, ZeroBody, ZeroState, 0.0f);
    const auto HipLocal = Anchors[0].Get_HipLocal();
    const auto FootWorld = Anchors[0].Get_FootWorld();
    TestTrue(TEXT("A zero-speed steering command attempts a reach-breaking turn while zero voluntary scale holds"),
        FVector::Dist(FullBody.TransformPosition(HipLocal), FootWorld) > Reach + DistanceTolerance
        && FVector::Dist(ZeroBody.TransformPosition(HipLocal), FootWorld) <= Reach + DistanceTolerance
        && FullBody.GetRotation().AngularDistance(ZeroBody.GetRotation()) > DistanceTolerance);

    auto Body = StartBody;
    auto State = StartState;
    const auto Outcome = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::RightVector, 0.0f, Step, Cast, NoFeet,
        TArrayView<const ck::FProceduralSurfaceReachPaceAnchor>{Anchors}, TOptional<FTransform>{}, Body, State);
    TestTrue(TEXT("Turn-only reach pacing reports the attempted hip motion without moving the plant out of reach"),
        Outcome.Get_Scale() < 1.0f && Outcome.Get_AttemptedStanceSpeed() > 0.0f
        && State.Get_Grounded() && FVector::Dist(Body.TransformPosition(HipLocal), FootWorld) <= Reach + 0.01);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionPacedAirborneBaselineTest,
    "Ck.ProceduralAnimation.SurfaceMotion.PacedAirborneBaselineStillChecksReach",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralSurfaceMotionPacedAirborneBaselineTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_surface_motion;

    // At zero voluntary travel there is no floor, so the body falls toward its planted foot. Full travel reaches
    // a narrow floor patch but moves the hip beyond the chain. Falling is not permission to accept that full trial.
    const auto World = TArray<FSolid>{MakeBox(FVector{1.0, -100.0, -50.0}, FVector{5.0, 100.0, 0.0})};
    const auto Cast = [&](const FVector& InStart, const FVector& InEnd) { return RayCast(World, InStart, InEnd); };
    const auto Settings = MakeSettings().Set_ContactGrace(FCk_Time{});
    const auto PaceStep = FCk_Time{0.016};
    constexpr auto PaceSpeed = 125.0f;
    constexpr auto ChainReach = 65.0f;
    const auto StartBody = MakeBody(FVector{0.0, 0.0, Clearance}, FVector::UpVector, FVector::ForwardVector);
    const auto StartState = MakeState(FVector::UpVector, FVector::ForwardVector, true);

    auto ZeroBody = StartBody;
    auto ZeroState = StartState;
    ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, PaceSpeed, PaceStep, Cast, NoFeet,
        ZeroBody, ZeroState, 0.0f);
    auto FullBody = StartBody;
    auto FullState = StartState;
    ck::StepProceduralSurfaceMotion(Settings, FVector::ForwardVector, PaceSpeed, PaceStep, Cast, NoFeet,
        FullBody, FullState, 1.0f);
    if (NOT TestTrue(TEXT("The zero trial falls but remains in chain reach"),
            NOT ZeroState.Get_Grounded() && FVector::Dist(ZeroBody.GetLocation(), FVector::ZeroVector) <= ChainReach)
        || NOT TestTrue(TEXT("The full trial lands beyond chain reach"),
            FullState.Get_Grounded() && FVector::Dist(FullBody.GetLocation(), FVector::ZeroVector) > ChainReach + DistanceTolerance))
    { return false; }

    const auto Anchors = TArray<ck::FProceduralSurfaceReachPaceAnchor>{
        ck::FProceduralSurfaceReachPaceAnchor{FVector::ZeroVector, FVector::ZeroVector, ChainReach}};
    auto Body = StartBody;
    auto State = StartState;
    const auto Outcome = ck::StepProceduralSurfaceMotionPaced(Settings, FVector::ForwardVector, PaceSpeed,
        PaceStep, Cast, NoFeet, TArrayView<const ck::FProceduralSurfaceReachPaceAnchor>{Anchors},
        TOptional<FTransform>{}, Body, State);
    TestTrue(TEXT("A falling zero trial does not bypass the planted chain bound"),
        Outcome.Get_Scale() < 1.0f && NOT Outcome.Get_PhysicalOverride()
        && Outcome.Get_Trials() >= 2 && Outcome.Get_Trials() <= 8
        && FVector::Dist(Body.GetLocation(), FVector::ZeroVector) <= ChainReach + DistanceTolerance);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
