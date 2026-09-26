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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), Steer, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), Steer, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
            ck::StepProceduralSurfaceMotion(MakeSettings(), Steer, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
        ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
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
            ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, StoppedSpeed, Step, Cast, Body, State);
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

    ck::StepProceduralSurfaceMotion(MakeSettings(), FVector::ForwardVector, Speed, Step, Cast, Body, State);
    if (NOT TestTrue(FString::Printf(TEXT("Precondition: the ramp is pending and the support unchanged (seen %.4f s, normal %s)"),
            State.Get_CandidateSeen().Get_Seconds(), *State.Get_SupportNormal().ToString()),
            State.Get_CandidateSeen() > FCk_Time{} && State.Get_CandidateNormal().Equals(RampNormal, DistanceTolerance)
            && State.Get_SupportNormal().Equals(FVector::UpVector, DistanceTolerance)))
    { return false; }

    TestEqual(TEXT("The coasting substep keeps the last accepted source"), State.Get_ContactSource(), ck::EProceduralSurfaceContactSource::Fan);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
