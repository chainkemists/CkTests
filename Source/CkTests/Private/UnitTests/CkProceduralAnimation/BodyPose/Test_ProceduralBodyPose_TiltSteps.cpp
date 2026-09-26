#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Algorithms/CkAlgorithms.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkProceduralAnimation/BodyPose/CkProceduralBodyPose_Utils.h"
#include "CkProceduralAnimation/CkProceduralAnimation_Utils.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"
#include "CkProceduralAnimation/Leg/CkProceduralLeg_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Misc/AutomationTest.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_body_pose_tilt_steps
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr auto StepDegrees = 4.0;
    constexpr auto StepFrames = 5;
    constexpr auto SettleFramesAfterSteps = 40;
    // The drawn body's turn is measured over the world time between samples, so a sample that spans a long frame or two frames
    // reads the spring's rate, not the length of the frame: 1.5 degrees a frame at 60 fps.
    constexpr auto MaxPresentationRateDegreesPerSecond = 1.5 * 60.0;
    constexpr auto BodyStepToleranceDegrees = 0.01;
    constexpr auto SolvesBeforeStepping = uint64{30};
    constexpr auto WaitSeconds = 15.0;
    // Two TickWorlds updates span exactly one frame: the first returns in the frame the previous command finished.
    constexpr auto OneFrame = 2;

    // The sustained rotation turns the body at a rate, advanced by each world tick's own delta time, so the body's turn and
    // the springs integrate one clock and a long frame moves both alike. 240 degrees per second is 4 degrees a frame at 60
    // fps, SurfaceMotion's default turn rate; the per-frame bounds below are those at 60 fps, expressed per second.
    constexpr auto SustainedRateDegreesPerSecond = 240.0;
    constexpr auto SustainedTotalDegrees = 120.0;
    constexpr auto SustainedSamples = 120;
    constexpr auto MinSteadySamples = 20;
    constexpr auto NominalFrameSeconds = 1.0 / 60.0;
    constexpr auto BodyRateTolerance = 0.01;
    // The spring step that follows the transport may carry the drawn body up to a degree past its lag bound.
    constexpr auto TrailSlackDegrees = 1.0;
    constexpr auto PresentationRateSlackDegreesPerSecond = 0.25 / NominalFrameSeconds;
    constexpr auto MaxPresentationRateChangeDegreesPerSecond = 2.0 / NominalFrameSeconds;
    constexpr auto TargetOffsetTolerance = 0.01;
    constexpr auto TargetRateSlack = 1.01;

    // Disabling every leg but the first tilts the support pose by its whole max tilt toward the lost side in one frame.
    constexpr auto SupportJumpDegrees = 30.0;
    constexpr auto SupportJumpSampleFrames = 90;
    constexpr auto MinTargetJumpDegrees = 29.0;
    constexpr auto MaxSettledTrailDegrees = 1.0;

    struct FWalker
    {
        FString Name;
        ECk_ProceduralBodyPose_ConformMode Mode = ECk_ProceduralBodyPose_ConformMode::None;
        float SupportMaxTilt = FCk_ProceduralBodyPose_Support{}.Get_MaxTilt();
        FCk_Handle Root;
        FCk_Handle_Transform Body;
        FCk_Handle_Transform Presentation;
        FCk_Handle_ProceduralBodyPose BodyPose;
        TArray<FCk_Handle_ProceduralLeg> Legs;
        FVector LastBodyUp = FVector::UpVector;
        FVector LastPresentationUp = FVector::UpVector;
        FQuat LastTargetRotation = FQuat::Identity;
        double WorstPresentationRate = 0.0;
        int32 WorstFrame = INDEX_NONE;
        double WorstBodyStepError = 0.0;
        double WorstTrail = 0.0;
        int32 WorstTrailFrame = INDEX_NONE;
        double WorstTargetOffsetError = 0.0;
        double WorstTargetStep = 0.0;
        int32 WorstTargetStepFrame = INDEX_NONE;
        double LastTrail = 0.0;

        double LastPresentationRate = 0.0;
        bool LastSampleSteady = false;
        int32 SteadySamples = 0;
        double WorstBodyRateError = 0.0;
        double WorstPresentationRateExcess = 0.0;
        int32 WorstPresentationRateExcessSample = INDEX_NONE;
        double WorstPresentationRateChange = 0.0;
        int32 WorstPresentationRateChangeSample = INDEX_NONE;
        double WorstSteadyTrail = 0.0;
        int32 WorstSteadyTrailSample = INDEX_NONE;
        double WorstTargetRate = 0.0;
        int32 WorstTargetRateSample = INDEX_NONE;
    };

    struct FState
    {
        TArray<FWalker> Walkers;
        int32 Frame = 0;
        double LastDeltaSeconds = 0.0;

        TWeakObjectPtr<UWorld> DrivenWorld;
        FDelegateHandle DriveHandle;
        double DrivenPitch = 0.0;
        bool Driving = false;
        bool WasDriving = false;
        double LastSampleTime = 0.0;
    };

    auto
        Get_DefaultMaxAttitudeLag()
        -> double
    {
        return FCk_ProceduralBodyPose_Spring{}.Get_MaxAttitudeLag();
    }

    auto
        Get_DefaultMaxConformTiltRate()
        -> double
    {
        return FCk_ProceduralBodyPose_Conform{}.Get_MaxTiltRate();
    }

    auto
        MakeRig()
        -> UCk_ProceduralRig_Data*
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>{};
        const auto Corners = TArray<FVector2D>{{40.0, 30.0}, {40.0, -30.0}, {-40.0, 30.0}, {-40.0, -30.0}};
        for (auto Index = 0; Index < Corners.Num(); ++Index)
        {
            const auto& Corner = Corners[Index];
            auto Placement = FCk_ProceduralLeg_Placement{FVector{Corner.X, Corner.Y, 0.0}, FVector{Corner.X, Corner.Y * 2.0, -60.0}};
            Placement.Set_PhaseOffset(Index == 0 || Index == 3 ? 0.0f : 0.5f);
            Legs.Emplace(FName{*FString::Printf(TEXT("Leg%d"), Index)}, Placement, FCk_ProceduralLeg_ChainGeometry{TArray<float>{60.0f, 80.0f}});
        }

        auto* Rig = NewObject<UCk_ProceduralRig_Data>();
        Rig->Set_Legs(Legs);
        return Rig;
    }

    auto
        Get_Up(
            const FCk_Handle_Transform& InHandle)
        -> FVector
    {
        return UCk_Utils_Transform_UE::Get_EntityCurrentTransform(InHandle).GetRotation().GetUpVector();
    }

    auto
        Get_AngleDegrees(
            const FVector& InA,
            const FVector& InB)
        -> double
    {
        return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(InA, InB), -1.0, 1.0)));
    }

    auto
        Get_TargetRotation(
            const FWalker& InWalker)
        -> FQuat
    {
        return UCk_Utils_ProceduralBodyPose_UE::Get_TargetOffset(InWalker.BodyPose).GetRotation();
    }

    // Every leg supports, so the support-loss target is the identity and the target the springs follow is the applied conform
    // target alone (the held fit, slewed), or the identity without conform.
    auto
        Get_ExpectedTargetOffset(
            const FWalker& InWalker)
        -> FTransform
    {
        const auto BodyPose = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InWalker.Root).Get_BodyPose();
        return BodyPose.Get_Conforms() ? BodyPose.Get_AppliedConformTarget() : FTransform::Identity;
    }

    // How far the drawn body trails the pose its springs follow: the angle between the presentation and the body carrying
    // the target offset.
    auto
        Get_TrailDegrees(
            const FWalker& InWalker)
        -> double
    {
        const auto BodyRotation = UCk_Utils_Transform_UE::Get_EntityCurrentTransform(InWalker.Body).GetRotation();
        const auto PresentationRotation = UCk_Utils_Transform_UE::Get_EntityCurrentTransform(InWalker.Presentation).GetRotation();
        return FMath::RadiansToDegrees(PresentationRotation.AngularDistance(BodyRotation * Get_TargetRotation(InWalker)));
    }

    auto
        Get_TargetOffsetError(
            const FWalker& InWalker)
        -> double
    {
        const auto Reported = UCk_Utils_ProceduralBodyPose_UE::Get_TargetOffset(InWalker.BodyPose);
        const auto Expected = Get_ExpectedTargetOffset(InWalker);
        return FMath::Max(FMath::RadiansToDegrees(Reported.GetRotation().AngularDistance(Expected.GetRotation())),
            FVector::Distance(Reported.GetLocation(), Expected.GetLocation()));
    }

    auto
        DoBegin_Sampling(
            const TSharedRef<FState>& InState)
        -> void
    {
        for (auto& Walker : InState->Walkers)
        {
            Walker.LastBodyUp = Get_Up(Walker.Body);
            Walker.LastPresentationUp = Get_Up(Walker.Presentation);
            Walker.LastTargetRotation = Get_TargetRotation(Walker);
        }
    }

    // InExpectedBodyStep is the body's tilt since the last sample, InElapsed the world time since it.
    auto
        DoSample(
            const TSharedRef<FState>& InState,
            double InExpectedBodyStep,
            double InElapsed)
        -> void
    {
        const auto Frame = InState->Frame;
        for (auto& Walker : InState->Walkers)
        {
            const auto BodyUp = Get_Up(Walker.Body);
            const auto PresentationUp = Get_Up(Walker.Presentation);
            const auto TargetRotation = Get_TargetRotation(Walker);
            const auto PresentationRate = InElapsed > 0.0 ? Get_AngleDegrees(PresentationUp, Walker.LastPresentationUp) / InElapsed : 0.0;
            if (PresentationRate > Walker.WorstPresentationRate)
            {
                Walker.WorstPresentationRate = PresentationRate;
                Walker.WorstFrame = Frame;
            }

            Walker.LastTrail = Get_TrailDegrees(Walker);
            if (Walker.LastTrail > Walker.WorstTrail)
            {
                Walker.WorstTrail = Walker.LastTrail;
                Walker.WorstTrailFrame = Frame;
            }
            const auto TargetStep = FMath::RadiansToDegrees(TargetRotation.AngularDistance(Walker.LastTargetRotation));
            if (TargetStep > Walker.WorstTargetStep)
            {
                Walker.WorstTargetStep = TargetStep;
                Walker.WorstTargetStepFrame = Frame;
            }
            Walker.WorstBodyStepError = FMath::Max(Walker.WorstBodyStepError,
                FMath::Abs(Get_AngleDegrees(BodyUp, Walker.LastBodyUp) - InExpectedBodyStep));
            Walker.LastBodyUp = BodyUp;
            Walker.LastPresentationUp = PresentationUp;
            Walker.LastTargetRotation = TargetRotation;
        }
    }

    auto
        Request_Pitch(
            const TSharedRef<FState>& InState,
            double InDegrees)
        -> void
    {
        for (auto& Walker : InState->Walkers)
        {
            UCk_Utils_Transform_UE::Request_SetRotation(Walker.Body,
                FCk_Request_Transform_SetRotation{FRotator{InDegrees, 0.0, 0.0}}, {});
        }
    }

    // Composes InState's walkers high above an empty map, without ground and without surface motion, so their bodies move
    // only when a test turns them, and waits until their gaits have solved.
    auto
        DoEnqueue_Walkers(
            FAutomationTestBase* InTest,
            const TSharedRef<FState>& InState)
        -> void
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [InTest, InState](UWorld* InWorld)
            {
                for (auto Index = 0; Index < InState->Walkers.Num(); ++Index)
                {
                    auto& Walker = InState->Walkers[Index];
                    auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
                    if (NOT InTest->TestTrue(FString::Printf(TEXT("PIE transient owner admits the walker %s"), *Walker.Name), ck::IsValid(Root)))
                    { return; }

                    const auto Start = FTransform{FVector{0.0, 600.0 * Index, 2000.0}};
                    auto Body = UCk_Utils_Transform_UE::Add(Root, Start, ECk_Replication::DoesNotReplicate);
                    auto PresentationEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Body);
                    auto Presentation = UCk_Utils_Transform_UE::Add(PresentationEntity, Start, ECk_Replication::DoesNotReplicate);

                    const auto Walked = UCk_Utils_ProceduralAnimation_UE::Add_Walker(Body, MakeRig(), NewObject<UCk_ProceduralGait_Data>(), {});
                    auto Gait = Walked.Get_Gait();
                    if (NOT InTest->TestTrue(FString::Printf(TEXT("The walker %s admits its gait"), *Walker.Name), ck::IsValid(Gait)))
                    { return; }

                    auto Conform = FCk_ProceduralBodyPose_Conform{};
                    Conform.Set_Mode(Walker.Mode);
                    auto Support = FCk_ProceduralBodyPose_Support{};
                    Support.Set_MaxTilt(Walker.SupportMaxTilt);
                    auto Spec = FCk_ProceduralBodyPose_Spec{Presentation};
                    Spec.Set_Conform(Conform);
                    Spec.Set_Support(Support);
                    Walker.Root = Root;
                    Walker.Body = Body;
                    Walker.Presentation = Presentation;
                    Walker.Legs = Walked.Get_Legs();
                    Walker.BodyPose = UCk_Utils_ProceduralBodyPose_UE::Add(Gait, Spec);
                    InTest->TestTrue(FString::Printf(TEXT("The walker %s admits its body pose"), *Walker.Name), ck::IsValid(Walker.BodyPose));
                }
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(InTest,
            FCk_NetAutoTest_Condition::CreateLambda([InState]
            {
                return ck::algo::AllOf(InState->Walkers, [](const FWalker& InWalker)
                {
                    return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InWalker.Root).Get_Sample().Get_Sequence() >= SolvesBeforeStepping
                        && UCk_Utils_ProceduralBodyPose_UE::Get_Status(InWalker.BodyPose) == ECk_ProceduralAnimation_Status::Ready;
                });
            }), WaitSeconds, TEXT("Every walker's gait has solved and its body pose has settled")));
    }

    // Pitches every body StepDegrees on each of InStepFrames consecutive frames and samples every frame until
    // SettleFramesAfterSteps frames after the last step.
    auto
        DoEnqueue_PitchSteps(
            const TSharedRef<FState>& InState,
            int32 InStepFrames)
        -> void
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [InState](UWorld* InWorld)
            {
                DoBegin_Sampling(InState);
                InState->LastSampleTime = InWorld->GetTimeSeconds();
                Request_Pitch(InState, StepDegrees);
            })));
        for (auto Step = 1; Step <= InStepFrames + SettleFramesAfterSteps; ++Step)
        {
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(OneFrame));
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
                [InState, Step, InStepFrames](UWorld* InWorld)
                {
                    InState->Frame = Step;
                    InState->LastDeltaSeconds = InWorld->GetDeltaSeconds();
                    const auto Now = InWorld->GetTimeSeconds();
                    DoSample(InState, Step <= InStepFrames ? StepDegrees : 0.0, Now - InState->LastSampleTime);
                    InState->LastSampleTime = Now;
                    if (Step < InStepFrames)
                    { Request_Pitch(InState, StepDegrees * (Step + 1)); }
                })));
        }
    }

    // Starts turning every body at SustainedRateDegreesPerSecond from the next tick of InWorld until it has turned
    // SustainedTotalDegrees: each tick advances the pitch by the rate times that tick's own delta time, as the world hands it to
    // its tick groups.
    auto
        DoStart_SustainedRotation(
            const TSharedRef<FState>& InState,
            UWorld* InWorld)
        -> void
    {
        InState->DrivenWorld = InWorld;
        InState->DrivenPitch = 0.0;
        InState->Driving = true;
        InState->WasDriving = true;
        InState->LastSampleTime = InWorld->GetTimeSeconds();

        const auto WeakState = TWeakPtr<FState>{InState};
        InState->DriveHandle = FWorldDelegates::OnWorldPreActorTick.AddLambda(
            [WeakState](UWorld* InTickingWorld, ELevelTick, float InDeltaSeconds)
            {
                const auto State = WeakState.Pin();
                if (NOT State.IsValid() || NOT State->Driving || InTickingWorld != State->DrivenWorld.Get())
                { return; }

                State->DrivenPitch = FMath::Min(State->DrivenPitch + SustainedRateDegreesPerSecond * InDeltaSeconds, SustainedTotalDegrees);
                State->Driving = State->DrivenPitch < SustainedTotalDegrees;
                for (auto& Walker : State->Walkers)
                {
                    UCk_Utils_Transform_UE::Request_SetRotation(Walker.Body,
                        FCk_Request_Transform_SetRotation{FRotator{State->DrivenPitch, 0.0, 0.0}}, {});
                }
            });
    }

    // Rates are measured over the world time since the last sample. A sample is steady when the body turned at the rate
    // for the whole interval since the previous one.
    auto
        DoSample_Sustained(
            const TSharedRef<FState>& InState,
            UWorld* InWorld)
        -> void
    {
        const auto Now = InWorld->GetTimeSeconds();
        const auto Elapsed = Now - InState->LastSampleTime;
        if (Elapsed <= 0.0)
        { return; }

        InState->LastSampleTime = Now;
        const auto Steady = InState->WasDriving && InState->Driving;
        InState->WasDriving = InState->Driving;
        const auto Sample = ++InState->Frame;

        for (auto& Walker : InState->Walkers)
        {
            const auto BodyUp = Get_Up(Walker.Body);
            const auto PresentationUp = Get_Up(Walker.Presentation);
            const auto TargetRotation = Get_TargetRotation(Walker);
            const auto BodyRate = Get_AngleDegrees(BodyUp, Walker.LastBodyUp) / Elapsed;
            const auto PresentationRate = Get_AngleDegrees(PresentationUp, Walker.LastPresentationUp) / Elapsed;
            Walker.LastTrail = Get_TrailDegrees(Walker);

            if (Steady)
            {
                ++Walker.SteadySamples;
                Walker.WorstBodyRateError = FMath::Max(Walker.WorstBodyRateError, FMath::Abs(BodyRate - SustainedRateDegreesPerSecond));
                if (PresentationRate - BodyRate > Walker.WorstPresentationRateExcess)
                {
                    Walker.WorstPresentationRateExcess = PresentationRate - BodyRate;
                    Walker.WorstPresentationRateExcessSample = Sample;
                }
                const auto RateChange = FMath::Abs(PresentationRate - Walker.LastPresentationRate);
                if (Walker.LastSampleSteady && RateChange > Walker.WorstPresentationRateChange)
                {
                    Walker.WorstPresentationRateChange = RateChange;
                    Walker.WorstPresentationRateChangeSample = Sample;
                }
                if (Walker.LastTrail > Walker.WorstSteadyTrail)
                {
                    Walker.WorstSteadyTrail = Walker.LastTrail;
                    Walker.WorstSteadyTrailSample = Sample;
                }
            }

            if (Walker.LastTrail > Walker.WorstTrail)
            {
                Walker.WorstTrail = Walker.LastTrail;
                Walker.WorstTrailFrame = Sample;
            }
            Walker.WorstTargetOffsetError = FMath::Max(Walker.WorstTargetOffsetError, Get_TargetOffsetError(Walker));
            const auto TargetRate = FMath::RadiansToDegrees(TargetRotation.AngularDistance(Walker.LastTargetRotation)) / Elapsed;
            if (TargetRate > Walker.WorstTargetRate)
            {
                Walker.WorstTargetRate = TargetRate;
                Walker.WorstTargetRateSample = Sample;
            }

            Walker.LastBodyUp = BodyUp;
            Walker.LastPresentationUp = PresentationUp;
            Walker.LastTargetRotation = TargetRotation;
            Walker.LastPresentationRate = PresentationRate;
            Walker.LastSampleSteady = Steady;
        }
    }

    auto
        DoStop_SustainedRotation(
            const TSharedRef<FState>& InState)
        -> void
    {
        FWorldDelegates::OnWorldPreActorTick.Remove(InState->DriveHandle);
        InState->DriveHandle.Reset();
        InState->Driving = false;
    }

    auto
        DoEnqueue_SustainedRotation(
            const TSharedRef<FState>& InState)
        -> void
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [InState](UWorld* InWorld)
            {
                DoBegin_Sampling(InState);
                DoStart_SustainedRotation(InState, InWorld);
            })));
        for (auto Sample = 1; Sample <= SustainedSamples; ++Sample)
        {
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(OneFrame));
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
                [InState](UWorld* InWorld)
                {
                    DoSample_Sustained(InState, InWorld);
                })));
        }
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [InState](UWorld*)
            {
                DoStop_SustainedRotation(InState);
            })));
    }

    auto
        DoEnqueue_DestroyAndEndPie(
            const TSharedRef<FState>& InState)
        -> void
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [InState](UWorld*)
            {
                if (InState->DriveHandle.IsValid())
                { DoStop_SustainedRotation(InState); }

                for (const auto& Walker : InState->Walkers)
                {
                    auto Root = Walker.Root;
                    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Root);
                }
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    }

    auto
        MakeSteppedWalkers()
        -> TSharedRef<FState>
    {
        const auto State = MakeShared<FState>();
        State->Walkers.Add(FWalker{TEXT("without conform"), ECk_ProceduralBodyPose_ConformMode::None});
        State->Walkers.Add(FWalker{TEXT("with conform"), ECk_ProceduralBodyPose_ConformMode::PlantedFeet});
        return State;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyPoseTiltStepsTest,
    "Ck.ProceduralAnimation.BodyPose.PresentationStaysSmoothThroughBodyTiltSteps",
    ck_test_procedural_body_pose_tilt_steps::TestFlags)

auto
    FCkProceduralBodyPoseTiltStepsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_pose_tilt_steps;

    const auto State = MakeSteppedWalkers();
    DoEnqueue_Walkers(this, State);
    DoEnqueue_PitchSteps(State, StepFrames);
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            for (const auto& Walker : State->Walkers)
            {
                TestTrue(FString::Printf(TEXT("The walker %s's body pitched %.0f degrees on each of %d frames, then held (worst error %.4f degrees)"),
                    *Walker.Name, StepDegrees, StepFrames, Walker.WorstBodyStepError), Walker.WorstBodyStepError < BodyStepToleranceDegrees);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation up turns at most %.0f degrees per second (worst %.2f at frame %d, last dt %.4f s)"),
                    *Walker.Name, MaxPresentationRateDegreesPerSecond, Walker.WorstPresentationRate, Walker.WorstFrame, State->LastDeltaSeconds),
                    Walker.WorstPresentationRate <= MaxPresentationRateDegreesPerSecond);
                TestEqual(FString::Printf(TEXT("The walker %s's body pose stays Ready"), *Walker.Name),
                    UCk_Utils_ProceduralBodyPose_UE::Get_Status(Walker.BodyPose), ECk_ProceduralAnimation_Status::Ready);
            }
        })));
    DoEnqueue_DestroyAndEndPie(State);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyPoseSustainedRotationTest,
    "Ck.ProceduralAnimation.BodyPose.PresentationLagIsBoundedThroughSustainedRotation",
    ck_test_procedural_body_pose_tilt_steps::TestFlags)

auto
    FCkProceduralBodyPoseSustainedRotationTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_pose_tilt_steps;

    const auto State = MakeSteppedWalkers();
    DoEnqueue_Walkers(this, State);
    DoEnqueue_SustainedRotation(State);
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            const auto MaxTrail = Get_DefaultMaxAttitudeLag() + TrailSlackDegrees;
            const auto MaxTargetRate = Get_DefaultMaxConformTiltRate() * TargetRateSlack;
            TestEqual(TEXT("The bodies turned the whole sustained rotation"), State->DrivenPitch, SustainedTotalDegrees, BodyStepToleranceDegrees);
            for (const auto& Walker : State->Walkers)
            {
                // Once the body stops, the offset reaches its target only through the spring, so a target the conform fit moves
                // then may trail by more than the bound: the bound covers the samples the body turns.
                AddInfo(FString::Printf(TEXT("The walker %s trailed its target pose by at most %.4f degrees while turning (sample %d) and %.4f "
                    "overall (sample %d); over %d steady samples its presentation outran the body by at most %.2f degrees per second (sample %d) "
                    "and its rate changed by at most %.2f degrees per second between samples (sample %d); its target turned at most %.2f "
                    "degrees per second (sample %d)"),
                    *Walker.Name, Walker.WorstSteadyTrail, Walker.WorstSteadyTrailSample, Walker.WorstTrail, Walker.WorstTrailFrame,
                    Walker.SteadySamples, Walker.WorstPresentationRateExcess, Walker.WorstPresentationRateExcessSample,
                    Walker.WorstPresentationRateChange, Walker.WorstPresentationRateChangeSample, Walker.WorstTargetRate,
                    Walker.WorstTargetRateSample));
                TestTrue(FString::Printf(TEXT("The walker %s's body turned steadily over at least %d samples (%d)"), *Walker.Name,
                    MinSteadySamples, Walker.SteadySamples), Walker.SteadySamples >= MinSteadySamples);
                TestTrue(FString::Printf(TEXT("The walker %s's body turned at %.0f degrees per second while steady (worst error %.4f)"),
                    *Walker.Name, SustainedRateDegreesPerSecond, Walker.WorstBodyRateError),
                    Walker.WorstBodyRateError <= SustainedRateDegreesPerSecond * BodyRateTolerance);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation trails its target pose by at most %.1f degrees while the body turns "
                    "(worst %.4f at sample %d)"), *Walker.Name, MaxTrail, Walker.WorstSteadyTrail, Walker.WorstSteadyTrailSample),
                    Walker.WorstSteadyTrail <= MaxTrail);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation up turns at most %.0f degrees per second faster than the body "
                    "(worst %.2f at sample %d)"), *Walker.Name, PresentationRateSlackDegreesPerSecond, Walker.WorstPresentationRateExcess,
                    Walker.WorstPresentationRateExcessSample), Walker.WorstPresentationRateExcess <= PresentationRateSlackDegreesPerSecond);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation rate changes by at most %.0f degrees per second between samples "
                    "while the body turns steadily (worst %.2f at sample %d)"), *Walker.Name, MaxPresentationRateChangeDegreesPerSecond,
                    Walker.WorstPresentationRateChange, Walker.WorstPresentationRateChangeSample),
                    Walker.WorstPresentationRateChange <= MaxPresentationRateChangeDegreesPerSecond);
                TestTrue(FString::Printf(TEXT("The walker %s's reported target offset is its applied conform target times the identity "
                    "support pose (worst error %.5f degrees or cm)"), *Walker.Name, Walker.WorstTargetOffsetError),
                    Walker.WorstTargetOffsetError < TargetOffsetTolerance);
                TestTrue(FString::Printf(TEXT("The walker %s's target offset turns at most the conform's %.0f degrees per second (worst %.2f "
                    "at sample %d)"), *Walker.Name, Get_DefaultMaxConformTiltRate(), Walker.WorstTargetRate, Walker.WorstTargetRateSample),
                    Walker.WorstTargetRate <= MaxTargetRate);
                TestEqual(FString::Printf(TEXT("The walker %s's body pose stays Ready"), *Walker.Name),
                    UCk_Utils_ProceduralBodyPose_UE::Get_Status(Walker.BodyPose), ECk_ProceduralAnimation_Status::Ready);
            }
        })));
    DoEnqueue_DestroyAndEndPie(State);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralBodyPoseSupportTiltJumpTest,
    "Ck.ProceduralAnimation.BodyPose.PresentationEasesSupportTiltJumpWithBodyStill",
    ck_test_procedural_body_pose_tilt_steps::TestFlags)

auto
    FCkProceduralBodyPoseSupportTiltJumpTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_body_pose_tilt_steps;

    const auto State = MakeShared<FState>();
    auto Walker = FWalker{TEXT("losing three legs")};
    Walker.SupportMaxTilt = SupportJumpDegrees;
    State->Walkers.Add(Walker);

    DoEnqueue_Walkers(this, State);
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* InWorld)
        {
            DoBegin_Sampling(State);
            State->LastSampleTime = InWorld->GetTimeSeconds();
            for (auto& LostWalker : State->Walkers)
            {
                for (auto Index = 1; Index < LostWalker.Legs.Num(); ++Index)
                {
                    UCk_Utils_ProceduralLeg_UE::Request_EnableDisable(LostWalker.Legs[Index],
                        FCk_Request_ProceduralLeg_EnableDisable{ECk_EnableDisable::Disable}, {});
                }
            }
        })));
    for (auto Frame = 1; Frame <= SupportJumpSampleFrames; ++Frame)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(OneFrame));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [State, Frame](UWorld* InWorld)
            {
                State->Frame = Frame;
                State->LastDeltaSeconds = InWorld->GetDeltaSeconds();
                const auto Now = InWorld->GetTimeSeconds();
                constexpr auto BodyStill = 0.0;
                DoSample(State, BodyStill, Now - State->LastSampleTime);
                State->LastSampleTime = Now;
            })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            for (const auto& JumpWalker : State->Walkers)
            {
                TestTrue(FString::Printf(TEXT("The walker %s's body stays still (worst tilt step %.4f degrees)"), *JumpWalker.Name,
                    JumpWalker.WorstBodyStepError), JumpWalker.WorstBodyStepError < BodyStepToleranceDegrees);
                TestTrue(FString::Printf(TEXT("The walker %s's target pose tilts about %.0f degrees in one frame (worst step %.4f degrees)"),
                    *JumpWalker.Name, SupportJumpDegrees, JumpWalker.WorstTargetStep), JumpWalker.WorstTargetStep >= MinTargetJumpDegrees);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation up turns at most %.0f degrees per second (worst %.2f at frame %d, "
                    "last dt %.4f s)"), *JumpWalker.Name, MaxPresentationRateDegreesPerSecond, JumpWalker.WorstPresentationRate, JumpWalker.WorstFrame,
                    State->LastDeltaSeconds), JumpWalker.WorstPresentationRate <= MaxPresentationRateDegreesPerSecond);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation reaches its target pose within %d frames (trail %.4f degrees)"),
                    *JumpWalker.Name, SupportJumpSampleFrames, JumpWalker.LastTrail), JumpWalker.LastTrail < MaxSettledTrailDegrees);
                TestEqual(FString::Printf(TEXT("The walker %s's body pose stays Ready"), *JumpWalker.Name),
                    UCk_Utils_ProceduralBodyPose_UE::Get_Status(JumpWalker.BodyPose), ECk_ProceduralAnimation_Status::Ready);
            }
        })));
    DoEnqueue_DestroyAndEndPie(State);
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
