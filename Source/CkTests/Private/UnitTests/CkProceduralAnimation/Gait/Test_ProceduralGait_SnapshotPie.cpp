#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Algorithms/CkAlgorithms.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkJolt/Body/CkJoltBody_Utils.h"
#include "CkProceduralAnimation/CkProceduralAnimation_Utils.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"
#include "CkProceduralAnimation/Leg/CkProceduralLeg_Utils.h"
#include "CkProceduralAnimation/SurfaceMotion/CkSurfaceMotion_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Misc/AutomationTest.h"

// --------------------------------------------------------------------------------------------------------------------
// ECS paths no core test observes, read back through the gait's debug snapshot in a PIE world on /Engine/Maps/Entry: the
// probe under a swing's landing point and the lift it feeds, the yaw lead of the query point, and the surface-motion
// contact waiting out its confirmation. Courses are static Jolt boxes far from the map's own geometry.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_snapshot_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto PieReadySeconds = 30.0f;
    constexpr auto WaitSeconds = 15.0;
    constexpr auto SolvesBeforeDriving = uint64{30};
    constexpr auto ExactTolerance = 0.01;
    constexpr auto PositionTolerance = 0.5;
    constexpr auto NormalDot = 0.99;

    // Four 140 cm legs on an 80 by 60 cm hip rectangle, resting 30 cm outboard and 60 cm below their hips, in two phase
    // groups.
    constexpr auto BodyHeight = 60.0;

    auto
        MakeRig()
        -> UCk_ProceduralRig_Data*
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>{};
        const auto Corners = TArray<FVector2D>{{40.0, 30.0}, {40.0, -30.0}, {-40.0, 30.0}, {-40.0, -30.0}};
        for (auto Index = 0; Index < Corners.Num(); ++Index)
        {
            const auto& Corner = Corners[Index];
            auto Placement = FCk_ProceduralLeg_Placement{FVector{Corner.X, Corner.Y, 0.0},
                FVector{Corner.X, Corner.Y * 2.0, -BodyHeight}};
            Placement.Set_PhaseOffset(Index == 0 || Index == 3 ? 0.0f : 0.5f);
            Legs.Emplace(FName{*FString::Printf(TEXT("Leg%d"), Index)}, Placement, FCk_ProceduralLeg_ChainGeometry{TArray<float>{60.0f, 80.0f}});
        }

        auto* Rig = NewObject<UCk_ProceduralRig_Data>();
        Rig->Set_Legs(Legs);
        return Rig;
    }

    // --------------------------------------------------------------------------------------------------------------------

    struct FCourse
    {
        TArray<FCk_Handle> Entities;
        TArray<FCk_Handle_JoltBody> Bodies;
    };

    auto
        DoAdd_Box(
            UWorld* InWorld,
            FCourse& InOutCourse,
            const FVector& InCenter,
            const FVector& InHalfExtents)
        -> void
    {
        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
        UCk_Utils_Transform_UE::Add(Entity, FTransform{InCenter}, ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box};
        Shape.Set_HalfExtents(InHalfExtents);
        auto Spec = FCk_JoltBody_Spec{ECk_JoltBody_ShapeSource::ExplicitShape};
        Spec.Set_ShapeDimensions(Shape);
        Spec.Set_MotionType(ECk_MotionType::Static);
        Spec.Set_CollisionProfileName(TEXT("BlockAll"));

        InOutCourse.Bodies.Add(UCk_Utils_JoltBody_UE::Add(Entity, Spec));
        InOutCourse.Entities.Add(Entity);
    }

    auto
        Get_IsCourseReady(
            const FCourse& InCourse)
        -> bool
    {
        return NOT InCourse.Bodies.IsEmpty() && ck::algo::AllOf(InCourse.Bodies, [](const FCk_Handle_JoltBody& InBody)
        {
            return ck::IsValid(InBody) && UCk_Utils_JoltBody_UE::Get_IsBodyAdded(InBody);
        });
    }

    // --------------------------------------------------------------------------------------------------------------------

    struct FWalker
    {
        FCk_Handle Root;
        FCk_Handle_Transform Body;
        FCk_Handle_ProceduralGait Gait;
    };

    auto
        DoAdd_Walker(
            FAutomationTestBase* InTest,
            UWorld* InWorld,
            const FVector& InLocation)
        -> FWalker
    {
        auto Walker = FWalker{};
        Walker.Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
        if (NOT InTest->TestTrue(TEXT("PIE transient owner admits the walker root"), ck::IsValid(Walker.Root)))
        { return Walker; }

        Walker.Body = UCk_Utils_Transform_UE::Add(Walker.Root, FTransform{InLocation}, ECk_Replication::DoesNotReplicate);
        Walker.Gait = UCk_Utils_ProceduralAnimation_UE::Add_Walker(Walker.Body, MakeRig(), NewObject<UCk_ProceduralGait_Data>(), {}).Get_Gait();
        InTest->TestTrue(TEXT("The walker admits its gait"), ck::IsValid(Walker.Gait));
        return Walker;
    }

    auto
        Get_HasSolved(
            const FWalker& InWalker)
        -> bool
    {
        return UCk_Utils_ProceduralGait_UE::Get_Status(InWalker.Gait) == ECk_ProceduralAnimation_Status::Ready
            && UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InWalker.Root).Get_Sample().Get_Sequence() >= SolvesBeforeDriving;
    }

    // Runs InTick at the start of every tick of InWorld, before its actors and entities, with that tick's own delta time.
    auto
        DoStart_Drive(
            UWorld* InWorld,
            TFunction<void(UWorld*, float)> InTick)
        -> FDelegateHandle
    {
        const auto DrivenWorld = TWeakObjectPtr<UWorld>{InWorld};
        return FWorldDelegates::OnWorldPreActorTick.AddLambda(
            [DrivenWorld, Tick = MoveTemp(InTick)](UWorld* InTickingWorld, ELevelTick, float InDeltaSeconds)
            {
                if (InTickingWorld != DrivenWorld.Get())
                { return; }

                Tick(InTickingWorld, InDeltaSeconds);
            });
    }

    auto
        DoStop_Drive(
            FDelegateHandle& InOutHandle)
        -> void
    {
        if (NOT InOutHandle.IsValid())
        { return; }

        FWorldDelegates::OnWorldPreActorTick.Remove(InOutHandle);
        InOutHandle.Reset();
    }

    auto
        DoDestroy(
            const FWalker& InWalker,
            const FCourse& InCourse)
        -> void
    {
        auto Root = InWalker.Root;
        if (ck::IsValid(Root))
        { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Root); }

        for (auto Entity : InCourse.Entities)
        {
            if (ck::IsValid(Entity))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Entity); }
        }
    }

    // --------------------------------------------------------------------------------------------------------------------
    // The landing-lift course: a floor with eight 20 cm blocks, 50 cm long, 50 cm apart, walked over at a constant height by
    // a body the test moves, so every foot steps up onto a block and down again eight times. A swing lifts onto a block when
    // its frozen target lies on the floor and the stroke overshoot carries its landing point past the riser, about one riser
    // crossing in five; 32 crossings make at least one near certain.

    const auto LiftOrigin = FVector{0.0, 30000.0, 5000.0};
    constexpr auto BlockTop = 20.0;
    constexpr auto BlockLength = 50.0;
    constexpr auto BlockPitch = 100.0;
    constexpr auto BlockCount = 8;
    constexpr auto FirstBlockX = 200.0;
    constexpr auto WalkSpeed = 150.0;
    constexpr auto WalkEndX = FirstBlockX + BlockPitch * BlockCount + 150.0;
    constexpr auto WalkSeconds = 20.0;
    // The walk usually yields a single lifting touchdown, on the last block, and its swing can still be in flight when the
    // body stops: sampling goes on with the body still until that swing lands.
    constexpr auto FirstLiftedTouchdownSeconds = 3.0;
    // A lifted foot is not inside the block on its last swing frame: it rises onto the top before touchdown.
    constexpr auto LiftedFootBelowTopTolerance = 2.0;

    struct FLiftState
    {
        FWalker Walker;
        FCourse Course;
        FDelegateHandle Drive;
        double DrivenX = 0.0;
        bool Driving = false;
        bool Sampling = false;
        uint64 LastSequence = 0;
        double ProbeUp = 0.0;

        TArray<bool> WasSwinging;
        TArray<bool> LiftPending;
        TArray<FVector> LastSwingFoot;

        int32 Samples = 0;
        int32 ProbedSwingSamples = 0;
        double WorstProbeOffset = 0.0;
        double WorstProbeHeightError = 0.0;
        int32 LiftSamples = 0;
        int32 LiftedTouchdowns = 0;
        int32 LiftedTouchdownsOnTop = 0;
        double WorstLiftedPlantError = 0.0;
        int32 LiftedFeetInsideTheBlock = 0;
        double WorstLiftedFootDepth = 0.0;
        int32 TouchdownsOverTheTop = 0;
        int32 BuriedTouchdowns = 0;
        double WorstBuriedDepth = 0.0;
        double WorstHover = 0.0;
        int32 MissedLandingLifts = 0;
        int32 PublishedPlantedSamples = 0;
        double WorstPublishedFootPositionError = 0.0;
        double WorstPublishedFootNormalError = 0.0;
        double WorstPublishedFootRotationError = 0.0;
    };

    auto
        Get_IsOverABlock(
            double InLocalX)
        -> bool
    {
        for (auto Block = 0; Block < BlockCount; ++Block)
        {
            const auto Start = FirstBlockX + BlockPitch * Block;
            if (InLocalX >= Start && InLocalX <= Start + BlockLength)
            { return true; }
        }
        return false;
    }

    auto
        DoSample_Lift(
            FLiftState& InState)
        -> void
    {
        const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InState.Walker.Root);
        const auto Sequence = Snapshot.Get_Sample().Get_Sequence();
        if (NOT Snapshot.Get_Status().Get_HasAcceptedSample() || Sequence == InState.LastSequence)
        { return; }

        InState.LastSequence = Sequence;
        ++InState.Samples;
        const auto MissedBefore = InState.MissedLandingLifts;
        InState.MissedLandingLifts = Snapshot.Get_Gait().Get_MissedLandingLifts();
        const auto CountedAMiss = InState.MissedLandingLifts > MissedBefore;

        const auto& Legs = Snapshot.Get_Legs();
        const auto PublishedLegs = UCk_Utils_ProceduralGait_UE::Get_Legs(InState.Walker.Gait);
        InState.WasSwinging.SetNumZeroed(Legs.Num());
        InState.LiftPending.SetNumZeroed(Legs.Num());
        InState.LastSwingFoot.SetNumZeroed(Legs.Num());
        const auto TopZ = LiftOrigin.Z + BlockTop;
        for (auto Index = 0; Index < Legs.Num(); ++Index)
        {
            const auto& Leg = Legs[Index];
            const auto& Foot = Leg.Get_Foot();
            const auto& Probe = Leg.Get_LandingProbe();
            if (Foot.Get_Planted() && PublishedLegs.IsValidIndex(Index) && ck::IsValid(PublishedLegs[Index]))
            {
                const auto PublishedFoot = UCk_Utils_ProceduralLeg_UE::Get_Foot(PublishedLegs[Index]);
                ++InState.PublishedPlantedSamples;
                InState.WorstPublishedFootPositionError = FMath::Max(InState.WorstPublishedFootPositionError,
                    FVector::Dist(Foot.Get_Position(), PublishedFoot.Get_Position()));
                InState.WorstPublishedFootNormalError = FMath::Max(InState.WorstPublishedFootNormalError,
                    FVector::Dist(Foot.Get_Normal(), PublishedFoot.Get_Normal()));
                InState.WorstPublishedFootRotationError = FMath::Max(InState.WorstPublishedFootRotationError,
                    Foot.Get_Rotation().AngularDistance(PublishedFoot.Get_Rotation()));
            }
            const auto Probed = Probe.Get_AttemptCount() > 0;
            const auto ProbeFoundTheTop = Probed && Probe.Get_Hit() && FMath::Abs(Probe.Get_HitPosition().Z - TopZ) <= PositionTolerance;

            if (Probed)
            {
                const auto Landing = Leg.Get_LandingPointWorld();
                InState.WorstProbeOffset = FMath::Max(InState.WorstProbeOffset, FVector::Dist2D(Probe.Get_Start(), Landing));
                InState.WorstProbeHeightError = FMath::Max(InState.WorstProbeHeightError,
                    FMath::Abs(Probe.Get_Start().Z - Landing.Z - InState.ProbeUp));
            }

            if (NOT Foot.Get_Planted())
            {
                if (Probed)
                { ++InState.ProbedSwingSamples; }
                // Whether the swing is lifting as of this frame: the ground reported under its landing point is the block
                // top while its target lies below. A swing whose target later rises onto the top itself stops lifting.
                InState.LiftPending[Index] = ProbeFoundTheTop && Foot.Get_SwingTarget().Z < TopZ - 1.0;
                InState.LiftSamples += InState.LiftPending[Index] ? 1 : 0;
                InState.LastSwingFoot[Index] = Foot.Get_Position();
            }
            else if (InState.WasSwinging[Index])
            {
                // Every touchdown whose landing ground is the block top lands on it or above it (a climbing stroke's
                // overshoot rises past the top), unless the report came too late and the solver counted the miss.
                if (ProbeFoundTheTop)
                {
                    ++InState.TouchdownsOverTheTop;
                    const auto Depth = TopZ - Foot.Get_PlantedPosition().Z;
                    InState.WorstHover = FMath::Max(InState.WorstHover, -Depth);
                    if (Depth > PositionTolerance && NOT CountedAMiss)
                    {
                        ++InState.BuriedTouchdowns;
                        InState.WorstBuriedDepth = FMath::Max(InState.WorstBuriedDepth, Depth);
                    }
                }

                if (InState.LiftPending[Index] && ProbeFoundTheTop)
                {
                    ++InState.LiftedTouchdowns;
                    const auto PlantError = FMath::Abs(Foot.Get_PlantedPosition().Z - TopZ);
                    InState.WorstLiftedPlantError = FMath::Max(InState.WorstLiftedPlantError, PlantError);
                    InState.LiftedTouchdownsOnTop += PlantError <= PositionTolerance ? 1 : 0;

                    const auto& LastFoot = InState.LastSwingFoot[Index];
                    if (Get_IsOverABlock(LastFoot.X - LiftOrigin.X))
                    {
                        const auto Depth = TopZ - LastFoot.Z;
                        InState.WorstLiftedFootDepth = FMath::Max(InState.WorstLiftedFootDepth, Depth);
                        InState.LiftedFeetInsideTheBlock += Depth > LiftedFootBelowTopTolerance ? 1 : 0;
                    }
                }
                InState.LiftPending[Index] = false;
            }
            InState.WasSwinging[Index] = NOT Foot.Get_Planted();
        }
    }

    // --------------------------------------------------------------------------------------------------------------------
    // The yaw-lead body: no ground and no surface motion, turned in place by the test about its up.

    const auto YawOrigin = FVector{0.0, 34000.0, 5000.0};
    constexpr auto YawRateDegreesPerSecond = 90.0;
    constexpr auto YawPhaseSeconds = 1.0;
    // The yaw-rate tracker low-passes over 0.1 s; half a second into a turn it reads the rate within 1 %.
    constexpr auto YawSettleSeconds = 0.5;
    constexpr auto YawLeadTolerance = 0.15;
    constexpr auto MinYawSamples = 10;

    struct FYawPhase
    {
        double Direction = 1.0;
        int32 Samples = 0;
        int32 WrongSign = 0;
        double MinLeadDegrees = TNumericLimits<double>::Max();
        double MaxLeadDegrees = -TNumericLimits<double>::Max();
        double WorstRadiusChange = 0.0;
        double WorstHeightChange = 0.0;
    };

    struct FYawState
    {
        FWalker Walker;
        FDelegateHandle Drive;
        double DrivenYaw = 0.0;
        double Direction = 1.0;
        double PhaseStart = 0.0;
        uint64 LastSequence = 0;
        FYawPhase Phases[2];
        int32 Phase = 0;
    };

    auto
        DoSample_Yaw(
            FYawState& InState)
        -> void
    {
        const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InState.Walker.Root);
        const auto Sequence = Snapshot.Get_Sample().Get_Sequence();
        if (NOT Snapshot.Get_Status().Get_HasAcceptedSample() || Sequence == InState.LastSequence)
        { return; }

        InState.LastSequence = Sequence;
        if (Snapshot.Get_Sample().Get_Time().Get_Seconds() - InState.PhaseStart < YawSettleSeconds)
        { return; }

        auto& Phase = InState.Phases[InState.Phase];
        const auto Body = Snapshot.Get_Gait().Get_BodyTransform();
        const auto Pivot = Body.GetLocation();
        const auto Up = Body.GetRotation().GetUpVector();
        for (const auto& Leg : Snapshot.Get_Legs())
        {
            if (NOT Leg.Get_Enabled())
            { continue; }

            const auto Neutral = Leg.Get_Targeting().Get_NeutralWorld() - Pivot;
            const auto Query = Leg.Get_Targeting().Get_QueryTarget() - Pivot;
            const auto NeutralPlanar = FVector::VectorPlaneProject(Neutral, Up);
            const auto QueryPlanar = FVector::VectorPlaneProject(Query, Up);
            const auto Lead = FMath::RadiansToDegrees(FMath::Atan2(
                FVector::DotProduct(FVector::CrossProduct(NeutralPlanar, QueryPlanar), Up), FVector::DotProduct(NeutralPlanar, QueryPlanar)));

            ++Phase.Samples;
            Phase.WrongSign += Lead * Phase.Direction <= 0.0 ? 1 : 0;
            Phase.MinLeadDegrees = FMath::Min(Phase.MinLeadDegrees, Lead * Phase.Direction);
            Phase.MaxLeadDegrees = FMath::Max(Phase.MaxLeadDegrees, Lead * Phase.Direction);
            Phase.WorstRadiusChange = FMath::Max(Phase.WorstRadiusChange, FMath::Abs(QueryPlanar.Size() - NeutralPlanar.Size()));
            Phase.WorstHeightChange = FMath::Max(Phase.WorstHeightChange,
                FMath::Abs(FVector::DotProduct(Query - Neutral, Up)));
        }
    }

    // --------------------------------------------------------------------------------------------------------------------
    // The pending-contact course: a floor and a wall across it, walked into by a SurfaceMotion body.

    const auto WallOrigin = FVector{0.0, 38000.0, 5000.0};
    constexpr auto WallX = 400.0;
    constexpr auto SteerSpeed = 150.0f;
    constexpr auto SubstepSeconds = 0.016;

    struct FWallState
    {
        FWalker Walker;
        FCourse Course;
        FDelegateHandle Drive;
        uint64 LastSequence = 0;
        int32 PendingSamples = 0;
        int32 PendingWallSamples = 0;
        double MaxCandidateSeen = 0.0;
        bool WallAdopted = false;
        int32 PendingWallSamplesBeforeAdoption = 0;
        double CandidateSeenOnAdoption = -1.0;
    };

    auto
        DoSample_Wall(
            FWallState& InState)
        -> void
    {
        const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InState.Walker.Root);
        const auto Sequence = Snapshot.Get_Sample().Get_Sequence();
        if (NOT Snapshot.Get_Status().Get_HasAcceptedSample() || Sequence == InState.LastSequence || InState.WallAdopted)
        { return; }

        InState.LastSequence = Sequence;
        const auto& Motion = Snapshot.Get_Motion();
        const auto SupportNormal = Snapshot.Get_Gait().Get_SupportNormal();
        if (FVector::DotProduct(SupportNormal, FVector::BackwardVector) >= NormalDot)
        {
            InState.WallAdopted = true;
            InState.PendingWallSamplesBeforeAdoption = InState.PendingWallSamples;
            InState.CandidateSeenOnAdoption = Motion.Get_CandidateSeen().Get_Seconds();
            return;
        }

        if (Motion.Get_CandidateSeen() <= FCk_Time{})
        { return; }

        ++InState.PendingSamples;
        InState.MaxCandidateSeen = FMath::Max(InState.MaxCandidateSeen, Motion.Get_CandidateSeen().Get_Seconds());
        const auto WallPending = FVector::DotProduct(Motion.Get_CandidateNormal(), FVector::BackwardVector) >= NormalDot
            && FVector::DotProduct(SupportNormal, FVector::UpVector) >= NormalDot;
        InState.PendingWallSamples += WallPending ? 1 : 0;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitLandingProbeLiftsOntoAStepTest,
    "Ck.ProceduralAnimation.Gait.LandingProbeLiftsASwingOntoAStep",
    ck_test_procedural_gait_snapshot_pie::TestFlags)

auto
    FCkProceduralGaitLandingProbeLiftsOntoAStepTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_snapshot_pie;

    const auto State = MakeShared<FLiftState>();
    State->ProbeUp = FCk_ProceduralGait_Probe{}.Get_Up();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, PieReadySeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            DoAdd_Box(InWorld, State->Course, LiftOrigin + FVector{600.0, 0.0, -25.0}, FVector{900.0, 300.0, 25.0});
            for (auto Block = 0; Block < BlockCount; ++Block)
            {
                const auto CenterX = FirstBlockX + BlockPitch * Block + BlockLength * 0.5;
                DoAdd_Box(InWorld, State->Course, LiftOrigin + FVector{CenterX, 0.0, (BlockTop - 10.0) * 0.5},
                    FVector{BlockLength * 0.5, 300.0, (BlockTop + 10.0) * 0.5});
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return Get_IsCourseReady(State->Course); }),
        WaitSeconds, TEXT("The floor and blocks are in the Jolt world")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            State->Walker = DoAdd_Walker(this, InWorld, LiftOrigin + FVector{0.0, 0.0, BodyHeight});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return Get_HasSolved(State->Walker); }),
        WaitSeconds, TEXT("The walker's gait is ready and has solved")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            State->Driving = true;
            State->Sampling = true;
            const auto WeakState = TWeakPtr<FLiftState>{State};
            State->Drive = DoStart_Drive(InWorld, [WeakState](UWorld*, float InDeltaSeconds)
            {
                const auto Pinned = WeakState.Pin();
                if (NOT Pinned.IsValid() || NOT Pinned->Sampling)
                { return; }

                DoSample_Lift(*Pinned);
                if (NOT Pinned->Driving)
                { return; }

                Pinned->DrivenX = FMath::Min(Pinned->DrivenX + WalkSpeed * InDeltaSeconds, WalkEndX);
                Pinned->Driving = Pinned->DrivenX < WalkEndX;
                UCk_Utils_Transform_UE::Request_SetLocation(Pinned->Walker.Body,
                    FCk_Request_Transform_SetLocation{LiftOrigin + FVector{Pinned->DrivenX, 0.0, BodyHeight}}, {});
            });
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return NOT State->Driving; }),
        WalkSeconds, TEXT("The body walks over the three blocks")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return State->LiftedTouchdowns > 0; }),
        FirstLiftedTouchdownSeconds, TEXT("A swing lifting onto a block top touches down")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            State->Sampling = false;
            DoStop_Drive(State->Drive);
            AddInfo(FString::Printf(TEXT("%d solves sampled: %d swinging-foot samples with a landing probe, %d with the block top under "
                "the landing point and the target below it, %d touchdowns lifting on their last swing frame (%d on the top, worst plant "
                "error %.3f cm, worst last-swing-frame depth below the top %.2f cm); %d touchdowns over a block top (%d buried, worst "
                "%.2f cm; worst hover %.2f cm), %d missed landing lifts"), State->Samples, State->ProbedSwingSamples,
                State->LiftSamples, State->LiftedTouchdowns, State->LiftedTouchdownsOnTop, State->WorstLiftedPlantError,
                State->WorstLiftedFootDepth, State->TouchdownsOverTheTop, State->BuriedTouchdowns, State->WorstBuriedDepth,
                State->WorstHover, State->MissedLandingLifts));

            TestTrue(FString::Printf(TEXT("Swinging feet record the probe under their landing point (%d samples)"), State->ProbedSwingSamples),
                State->ProbedSwingSamples > 0);
            TestTrue(FString::Printf(TEXT("Every landing probe starts over the recorded landing point (worst %.4f cm off)"),
                State->WorstProbeOffset), State->WorstProbeOffset <= ExactTolerance);
            TestTrue(FString::Printf(TEXT("Every landing probe starts the probe's up distance above the landing point (worst error %.4f cm)"),
                State->WorstProbeHeightError), State->WorstProbeHeightError <= ExactTolerance);
            TestTrue(FString::Printf(TEXT("A swing learns of the block top under its landing point while its target lies below it, and "
                "lands lifting (%d samples, %d touchdowns)"), State->LiftSamples, State->LiftedTouchdowns),
                State->LiftSamples > 0 && State->LiftedTouchdowns > 0);
            TestTrue(FString::Printf(TEXT("Planted debug feet match the authoritative published foot pose (%d samples, worst "
                "position %.4f cm, normal %.4f, rotation %.4f rad)"), State->PublishedPlantedSamples,
                State->WorstPublishedFootPositionError, State->WorstPublishedFootNormalError,
                State->WorstPublishedFootRotationError),
                State->PublishedPlantedSamples > 0 && State->WorstPublishedFootPositionError <= ExactTolerance
                && State->WorstPublishedFootNormalError <= ExactTolerance
                && State->WorstPublishedFootRotationError <= ExactTolerance);
            TestEqual(FString::Printf(TEXT("Every swing still lifting at touchdown plants on the block top (worst error %.3f cm)"),
                State->WorstLiftedPlantError), State->LiftedTouchdownsOnTop, State->LiftedTouchdowns);
            TestEqual(FString::Printf(TEXT("No touchdown whose landing ground is a block top plants inside the block, bar a counted missed "
                "lift (%d of %d, worst %.2f cm)"), State->BuriedTouchdowns, State->TouchdownsOverTheTop, State->WorstBuriedDepth),
                State->BuriedTouchdowns, 0);
            TestEqual(FString::Printf(TEXT("Every such swing rises onto the block before touchdown: on its last swing frame over the block "
                "the foot is at most %.0f cm below the top (worst %.2f cm)"), LiftedFootBelowTopTolerance, State->WorstLiftedFootDepth),
                State->LiftedFeetInsideTheBlock, 0);

            DoDestroy(State->Walker, State->Course);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitYawLeadTurnsTheQueryTest,
    "Ck.ProceduralAnimation.Gait.YawLeadTurnsTheQueryAboutTheBody",
    ck_test_procedural_gait_snapshot_pie::TestFlags)

auto
    FCkProceduralGaitYawLeadTurnsTheQueryTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_snapshot_pie;

    const auto State = MakeShared<FYawState>();
    State->Phases[0].Direction = 1.0;
    State->Phases[1].Direction = -1.0;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, PieReadySeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            State->Walker = DoAdd_Walker(this, InWorld, YawOrigin);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return Get_HasSolved(State->Walker); }),
        WaitSeconds, TEXT("The walker's gait is ready and has solved")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            State->PhaseStart = InWorld->GetTimeSeconds();
            const auto WeakState = TWeakPtr<FYawState>{State};
            State->Drive = DoStart_Drive(InWorld, [WeakState](UWorld*, float InDeltaSeconds)
            {
                const auto Pinned = WeakState.Pin();
                if (NOT Pinned.IsValid())
                { return; }

                DoSample_Yaw(*Pinned);
                Pinned->DrivenYaw += Pinned->Phases[Pinned->Phase].Direction * YawRateDegreesPerSecond * InDeltaSeconds;
                UCk_Utils_Transform_UE::Request_SetRotation(Pinned->Walker.Body,
                    FCk_Request_Transform_SetRotation{FRotator{0.0, Pinned->DrivenYaw, 0.0}}, {});
            });
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            const auto* World = ck::auto_test::net::Get_ServerWorld();
            return ck::IsValid(World, ck::IsValid_Policy_NullptrOnly{}) && World->GetTimeSeconds() - State->PhaseStart >= YawPhaseSeconds;
        }), WaitSeconds, TEXT("The body turns at +90 deg/s for a second")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            State->Phase = 1;
            State->PhaseStart = InWorld->GetTimeSeconds();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            const auto* World = ck::auto_test::net::Get_ServerWorld();
            return ck::IsValid(World, ck::IsValid_Policy_NullptrOnly{}) && World->GetTimeSeconds() - State->PhaseStart >= YawPhaseSeconds;
        }), WaitSeconds, TEXT("The body turns at -90 deg/s for a second")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            DoStop_Drive(State->Drive);

            const auto LeadTime = FCk_ProceduralGait_Timing{}.Get_StepDuration().Get_Seconds();
            const auto ExpectedLead = YawRateDegreesPerSecond * LeadTime;
            for (const auto& Phase : State->Phases)
            {
                const auto* Turn = Phase.Direction > 0.0 ? TEXT("at +90 deg/s") : TEXT("at -90 deg/s");
                AddInfo(FString::Printf(TEXT("Turning %s: %d query samples, lead %.3f to %.3f degrees in the turn's direction (expected %.3f), "
                    "worst radius change %.4f cm, worst height change %.4f cm"), Turn, Phase.Samples, Phase.MinLeadDegrees,
                    Phase.MaxLeadDegrees, ExpectedLead, Phase.WorstRadiusChange, Phase.WorstHeightChange));

                if (NOT TestTrue(FString::Printf(TEXT("Turning %s: the settled turn is sampled (%d samples)"), Turn, Phase.Samples),
                        Phase.Samples >= MinYawSamples))
                { continue; }

                TestEqual(FString::Printf(TEXT("Turning %s: every query point leads its neutral in the turn's direction"), Turn),
                    Phase.WrongSign, 0);
                TestTrue(FString::Printf(TEXT("Turning %s: the lead is the turn rate times the step duration, %.2f degrees within %.0f %% "
                    "(%.3f to %.3f)"), Turn, ExpectedLead, YawLeadTolerance * 100.0, Phase.MinLeadDegrees, Phase.MaxLeadDegrees),
                    Phase.MinLeadDegrees >= ExpectedLead * (1.0 - YawLeadTolerance)
                    && Phase.MaxLeadDegrees <= ExpectedLead * (1.0 + YawLeadTolerance));
                TestTrue(FString::Printf(TEXT("Turning %s: the query point turns about the body, keeping its distance from it (worst change "
                    "%.4f cm)"), Turn, Phase.WorstRadiusChange), Phase.WorstRadiusChange <= PositionTolerance);
                TestTrue(FString::Printf(TEXT("Turning %s: the query point turns about the body's up, keeping its height (worst change "
                    "%.4f cm)"), Turn, Phase.WorstHeightChange), Phase.WorstHeightChange <= PositionTolerance);
            }

            DoDestroy(State->Walker, FCourse{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralSurfaceMotionSnapshotShowsPendingContactTest,
    "Ck.ProceduralAnimation.SurfaceMotion.SnapshotShowsThePendingContact",
    ck_test_procedural_gait_snapshot_pie::TestFlags)

auto
    FCkProceduralSurfaceMotionSnapshotShowsPendingContactTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_snapshot_pie;

    const auto State = MakeShared<FWallState>();
    const auto Spec = FCk_SurfaceMotion_Spec{};
    const auto ConfirmTime = Spec.Get_Contact().Get_ConfirmTime().Get_Seconds();
    const auto Clearance = Spec.Get_Contact().Get_Clearance();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, PieReadySeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            DoAdd_Box(InWorld, State->Course, WallOrigin + FVector{300.0, 0.0, -25.0}, FVector{800.0, 300.0, 25.0});
            DoAdd_Box(InWorld, State->Course, WallOrigin + FVector{WallX + 150.0, 0.0, 150.0}, FVector{150.0, 300.0, 150.0});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return Get_IsCourseReady(State->Course); }),
        WaitSeconds, TEXT("The floor and wall are in the Jolt world")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, Spec, Clearance](UWorld* InWorld)
        {
            State->Walker = DoAdd_Walker(this, InWorld, WallOrigin + FVector{0.0, 0.0, Clearance});
            auto Motion = UCk_Utils_SurfaceMotion_UE::Add(State->Walker.Body, Spec);
            TestTrue(TEXT("The walker admits its surface motion"), ck::IsValid(Motion));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return Get_HasSolved(State->Walker); }),
        WaitSeconds, TEXT("The walker's gait is ready and has solved")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            auto Motion = UCk_Utils_SurfaceMotion_UE::Cast(State->Walker.Body);
            UCk_Utils_SurfaceMotion_UE::Request_Steering(Motion, FCk_Request_SurfaceMotion_Steering{FVector::ForwardVector, SteerSpeed}, {});

            const auto WeakState = TWeakPtr<FWallState>{State};
            State->Drive = DoStart_Drive(InWorld, [WeakState](UWorld*, float)
            {
                const auto Pinned = WeakState.Pin();
                if (Pinned.IsValid())
                { DoSample_Wall(*Pinned); }
            });
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State] { return State->WallAdopted; }),
        WaitSeconds, TEXT("The body walks into the wall and adopts it")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, ConfirmTime](UWorld*)
        {
            DoStop_Drive(State->Drive);
            AddInfo(FString::Printf(TEXT("%d solves showed a pending contact, %d of them the wall over the floor support, seen for up to "
                "%.4f s (confirm time %.4f s)"), State->PendingSamples, State->PendingWallSamples, State->MaxCandidateSeen, ConfirmTime));

            TestTrue(TEXT("The body adopts the wall"), State->WallAdopted);
            TestTrue(FString::Printf(TEXT("Before the wall is adopted, the snapshot shows it pending: its normal, the time it has been seen, "
                "and the floor still the support (%d solves)"), State->PendingWallSamplesBeforeAdoption),
                State->PendingWallSamplesBeforeAdoption > 0);
            TestTrue(FString::Printf(TEXT("A pending contact is shown for no longer than the confirm time and a substep (%.4f s)"),
                State->MaxCandidateSeen), State->MaxCandidateSeen <= ConfirmTime + SubstepSeconds + ExactTolerance);
            TestEqual(TEXT("Once the wall is adopted nothing is pending"), State->CandidateSeenOnAdoption, 0.0);

            auto Motion = UCk_Utils_SurfaceMotion_UE::Cast(State->Walker.Body);
            if (ck::IsValid(Motion))
            { UCk_Utils_SurfaceMotion_UE::Request_Steering(Motion, FCk_Request_SurfaceMotion_Steering{FVector::ForwardVector, 0.0f}, {}); }
            DoDestroy(State->Walker, State->Course);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
