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
    constexpr auto MaxPresentationStepDegrees = 1.5;
    constexpr auto BodyStepToleranceDegrees = 0.01;
    constexpr auto SolvesBeforeStepping = uint64{30};
    constexpr auto WaitSeconds = 15.0;
    // Two TickWorlds updates span exactly one frame: the first returns in the frame the previous command finished.
    constexpr auto OneFrame = 2;

    struct FWalker
    {
        FString Name;
        ECk_ProceduralBodyPose_ConformMode Mode = ECk_ProceduralBodyPose_ConformMode::None;
        FCk_Handle Root;
        FCk_Handle_Transform Body;
        FCk_Handle_Transform Presentation;
        FCk_Handle_ProceduralBodyPose BodyPose;
        FVector LastBodyUp = FVector::UpVector;
        FVector LastPresentationUp = FVector::UpVector;
        double WorstPresentationStep = 0.0;
        int32 WorstFrame = INDEX_NONE;
        double WorstBodyStepError = 0.0;
    };

    struct FState
    {
        TArray<FWalker> Walkers;
        int32 Frame = 0;
        double LastDeltaSeconds = 0.0;
    };

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
        DoSample(
            const TSharedRef<FState>& InState,
            bool InBodyStepped)
        -> void
    {
        for (auto& Walker : InState->Walkers)
        {
            const auto BodyUp = Get_Up(Walker.Body);
            const auto PresentationUp = Get_Up(Walker.Presentation);
            const auto PresentationStep = Get_AngleDegrees(PresentationUp, Walker.LastPresentationUp);
            if (PresentationStep > Walker.WorstPresentationStep)
            {
                Walker.WorstPresentationStep = PresentationStep;
                Walker.WorstFrame = InState->Frame;
            }
            const auto ExpectedBodyStep = InBodyStepped ? StepDegrees : 0.0;
            Walker.WorstBodyStepError = FMath::Max(Walker.WorstBodyStepError,
                FMath::Abs(Get_AngleDegrees(BodyUp, Walker.LastBodyUp) - ExpectedBodyStep));
            Walker.LastBodyUp = BodyUp;
            Walker.LastPresentationUp = PresentationUp;
        }
    }

    auto
        Request_Pitch(
            const TSharedRef<FState>& InState,
            int32 InStep)
        -> void
    {
        for (auto& Walker : InState->Walkers)
        {
            UCk_Utils_Transform_UE::Request_SetRotation(Walker.Body,
                FCk_Request_Transform_SetRotation{FRotator{StepDegrees * InStep, 0.0, 0.0}}, {});
        }
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

    const auto State = MakeShared<FState>();
    State->Walkers.Add(FWalker{TEXT("without conform"), ECk_ProceduralBodyPose_ConformMode::None});
    State->Walkers.Add(FWalker{TEXT("with conform"), ECk_ProceduralBodyPose_ConformMode::PlantedFeet});

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            for (auto Index = 0; Index < State->Walkers.Num(); ++Index)
            {
                auto& Walker = State->Walkers[Index];
                auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
                if (NOT TestTrue(FString::Printf(TEXT("PIE transient owner admits the walker %s"), *Walker.Name), ck::IsValid(Root)))
                { return; }

                const auto Start = FTransform{FVector{0.0, 600.0 * Index, 2000.0}};
                auto Body = UCk_Utils_Transform_UE::Add(Root, Start, ECk_Replication::DoesNotReplicate);
                auto PresentationEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Body);
                auto Presentation = UCk_Utils_Transform_UE::Add(PresentationEntity, Start, ECk_Replication::DoesNotReplicate);

                const auto Walked = UCk_Utils_ProceduralAnimation_UE::Add_Walker(Body, MakeRig(), NewObject<UCk_ProceduralGait_Data>(), {});
                auto Gait = Walked.Get_Gait();
                if (NOT TestTrue(FString::Printf(TEXT("The walker %s admits its gait"), *Walker.Name), ck::IsValid(Gait)))
                { return; }

                auto Conform = FCk_ProceduralBodyPose_Conform{};
                Conform.Set_Mode(Walker.Mode);
                auto Spec = FCk_ProceduralBodyPose_Spec{Presentation};
                Spec.Set_Conform(Conform);
                Walker.Root = Root;
                Walker.Body = Body;
                Walker.Presentation = Presentation;
                Walker.BodyPose = UCk_Utils_ProceduralBodyPose_UE::Add(Gait, Spec);
                TestTrue(FString::Printf(TEXT("The walker %s admits its body pose"), *Walker.Name), ck::IsValid(Walker.BodyPose));
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return ck::algo::AllOf(State->Walkers, [](const FWalker& InWalker)
            {
                return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InWalker.Root).Get_Sample().Get_Sequence() >= SolvesBeforeStepping
                    && UCk_Utils_ProceduralBodyPose_UE::Get_Status(InWalker.BodyPose) == ECk_ProceduralAnimation_Status::Ready;
            });
        }), WaitSeconds, TEXT("Both walkers' gaits have solved and their body poses have settled")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld*)
        {
            for (auto& Walker : State->Walkers)
            {
                Walker.LastBodyUp = Get_Up(Walker.Body);
                Walker.LastPresentationUp = Get_Up(Walker.Presentation);
            }
            Request_Pitch(State, 1);
        })));
    for (auto Step = 1; Step <= StepFrames + SettleFramesAfterSteps; ++Step)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(OneFrame));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [State, Step](UWorld* InWorld)
            {
                State->Frame = Step;
                State->LastDeltaSeconds = InWorld->GetDeltaSeconds();
                DoSample(State, Step <= StepFrames);
                if (Step < StepFrames)
                { Request_Pitch(State, Step + 1); }
            })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            for (const auto& Walker : State->Walkers)
            {
                TestTrue(FString::Printf(TEXT("The walker %s's body pitched %.0f degrees on each of %d frames, then held (worst error %.4f degrees)"),
                    *Walker.Name, StepDegrees, StepFrames, Walker.WorstBodyStepError), Walker.WorstBodyStepError < BodyStepToleranceDegrees);
                TestTrue(FString::Printf(TEXT("The walker %s's presentation up moves at most %.1f degrees per frame (worst %.4f at frame %d, last dt %.4f s)"),
                    *Walker.Name, MaxPresentationStepDegrees, Walker.WorstPresentationStep, Walker.WorstFrame, State->LastDeltaSeconds),
                    Walker.WorstPresentationStep <= MaxPresentationStepDegrees);
                TestEqual(FString::Printf(TEXT("The walker %s's body pose stays Ready"), *Walker.Name),
                    UCk_Utils_ProceduralBodyPose_UE::Get_Status(Walker.BodyPose), ECk_ProceduralAnimation_Status::Ready);
            }

            for (const auto& Walker : State->Walkers)
            {
                auto Root = Walker.Root;
                UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Root);
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
