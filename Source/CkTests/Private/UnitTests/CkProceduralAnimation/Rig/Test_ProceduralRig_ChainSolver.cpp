#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkProceduralAnimation/CkProceduralAnimation_Utils.h"
#include "CkProceduralAnimation/Core/CkProceduralLegCurve.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"
#include "CkProceduralAnimation/Leg/CkProceduralLeg_Utils.h"
#include "CkProceduralAnimation/Rig/CkProceduralRig_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Misc/AutomationTest.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_rig_chain_solver
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr auto MatchTolerance = 0.1;
    constexpr auto DistinctFromCurve = 1.0;
    constexpr auto ReachTolerance = 2.0;
    constexpr auto ReachableFraction = 0.95;
    constexpr auto SolvesBeforeCheck = uint64{3};
    constexpr auto WaitSeconds = 10.0;
    const auto BodyLocation = FVector{0.0, 0.0, 2000.0};
    const auto AutoLegId = FName{TEXT("AutoThreeLinks")};
    const auto FabrikLegId = FName{TEXT("FabrikThreeLinks")};
    const auto CurveLegId = FName{TEXT("CurveTwoLinks")};

    struct FChainCase
    {
        FName LegId;
        ECk_ProceduralRig_ChainSolver Solver = ECk_ProceduralRig_ChainSolver::Auto;
        TArray<FCk_Handle_Transform> Segments;
    };

    struct FState
    {
        FCk_Handle Root;
        FCk_Handle_Transform Body;
        TArray<FChainCase> Cases;
    };

    auto
        MakeLeg(
            FName InId,
            const FVector& InHip,
            const FVector& InRest,
            float InPhaseOffset,
            TArray<float> InLengths)
        -> FCk_ProceduralLeg_Spec
    {
        auto Placement = FCk_ProceduralLeg_Placement{InHip, InRest};
        Placement.Set_PhaseOffset(InPhaseOffset);
        auto Chain = FCk_ProceduralLeg_ChainGeometry{MoveTemp(InLengths)};
        Chain.Set_PoleLocal(InHip + FVector{0.0, FMath::Sign(InHip.Y) * 40.0, 90.0});
        return FCk_ProceduralLeg_Spec{InId, Placement, Chain};
    }

    // Every rest foot sits at about 0.6 of its chain's length from the hip, inside the curve's closing range.
    auto
        MakeRig()
        -> UCk_ProceduralRig_Data*
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>{};
        Legs.Add(MakeLeg(AutoLegId, FVector{30.0, -25.0, 0.0}, FVector{30.0, -85.0, -60.0}, 0.0f, TArray<float>{40.0f, 40.0f, 60.0f}));
        Legs.Add(MakeLeg(FabrikLegId, FVector{30.0, 25.0, 0.0}, FVector{30.0, 85.0, -60.0}, 0.5f, TArray<float>{40.0f, 40.0f, 60.0f}));
        Legs.Add(MakeLeg(CurveLegId, FVector{-40.0, 0.0, 0.0}, FVector{-100.0, 0.0, -60.0}, 0.25f, TArray<float>{60.0f, 80.0f}));

        auto* Rig = NewObject<UCk_ProceduralRig_Data>();
        Rig->Set_Legs(Legs);
        return Rig;
    }

    auto
        MakeSegments(
            FCk_Handle_Transform& InBody,
            int32 InCount)
        -> TArray<FCk_Handle_Transform>
    {
        auto Segments = TArray<FCk_Handle_Transform>{};
        for (auto Index = 0; Index < InCount; ++Index)
        {
            auto Part = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InBody);
            Segments.Add(UCk_Utils_Transform_UE::Add(Part, FTransform{BodyLocation}, ECk_Replication::DoesNotReplicate));
        }
        return Segments;
    }

    // The drawn joints: the first segment's near end, then every segment's far end.
    auto
        Get_DrawnJoints(
            const TArray<FCk_Handle_Transform>& InSegments,
            const TArray<float>& InLengths)
        -> TArray<FVector>
    {
        auto Joints = TArray<FVector>{};
        for (auto Index = 0; Index < InSegments.Num(); ++Index)
        {
            const auto Segment = UCk_Utils_Transform_UE::Get_EntityCurrentTransform(InSegments[Index]);
            const auto HalfAxis = Segment.GetRotation().GetForwardVector() * (InLengths[Index] * 0.5);
            if (Index == 0)
            { Joints.Add(Segment.GetLocation() - HalfAxis); }
            Joints.Add(Segment.GetLocation() + HalfAxis);
        }
        return Joints;
    }

    auto
        Get_MaxJointGap(
            const TArray<FVector>& InA,
            const TArray<FVector>& InB)
        -> double
    {
        if (InA.Num() != InB.Num())
        { return TNumericLimits<double>::Max(); }

        auto Gap = 0.0;
        for (auto Index = 0; Index < InA.Num(); ++Index)
        { Gap = FMath::Max(Gap, FVector::Dist(InA[Index], InB[Index])); }
        return Gap;
    }

    auto
        Get_IsSettled(
            const TSharedRef<FState>& InState)
        -> bool
    {
        const auto Snapshot = UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InState->Root);
        return Snapshot.Get_Sample().Get_Sequence() >= SolvesBeforeCheck
            && Snapshot.Get_Status().Get_RigStatus() == ECk_ProceduralAnimation_Status::Ready
            && Snapshot.Get_Freshness().Get_RigMatchesGaitSequence()
            && NOT Snapshot.Get_Freshness().Get_RigPosePending();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralRigChainSolverTest,
    "Ck.ProceduralAnimation.Rig.AutoPicksCurveAndExplicitSolversApply",
    ck_test_procedural_rig_chain_solver::TestFlags)

auto
    FCkProceduralRigChainSolverTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_rig_chain_solver;

    const auto State = MakeShared<FState>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld* InWorld)
        {
            auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("PIE transient owner admits the walker root"), ck::IsValid(Root)))
            { return; }

            auto Body = UCk_Utils_Transform_UE::Add(Root, FTransform{BodyLocation}, ECk_Replication::DoesNotReplicate);
            State->Root = Root;
            State->Body = Body;
            State->Cases.Add(FChainCase{AutoLegId, ECk_ProceduralRig_ChainSolver::Auto, MakeSegments(Body, 3)});
            State->Cases.Add(FChainCase{FabrikLegId, ECk_ProceduralRig_ChainSolver::Fabrik, MakeSegments(Body, 3)});
            State->Cases.Add(FChainCase{CurveLegId, ECk_ProceduralRig_ChainSolver::Curve, MakeSegments(Body, 2)});

            auto Chains = TArray<FCk_ProceduralWalker_LegChain>{};
            for (const auto& Case : State->Cases)
            {
                auto Rig = FCk_ProceduralRig_Spec{Case.Segments};
                Rig.Set_Solver(Case.Solver);
                Chains.Emplace(Case.LegId, Rig);
            }

            const auto Walker = UCk_Utils_ProceduralAnimation_UE::Add_Walker(Body, MakeRig(), NewObject<UCk_ProceduralGait_Data>(), Chains);
            TestTrue(TEXT("The walker admits an Auto, a Fabrik and a Curve chain"), ck::IsValid(Walker.Get_Gait()));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return Get_IsSettled(State);
        }), WaitSeconds, TEXT("The rigs are Ready and have posed the latest accepted solve")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            const auto Body = UCk_Utils_Transform_UE::Get_EntityCurrentTransform(State->Body);
            for (const auto& Case : State->Cases)
            {
                const auto Leg = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(State->Root, Case.LegId);
                if (NOT TestTrue(FString::Printf(TEXT("Leg %s is found by Id"), *Case.LegId.ToString()), ck::IsValid(Leg)))
                { continue; }

                const auto Placement = UCk_Utils_ProceduralLeg_UE::Get_Placement(Leg);
                const auto Chain = UCk_Utils_ProceduralLeg_UE::Get_ChainGeometry(Leg);
                const auto& Lengths = Chain.Get_SegmentLengths();
                const auto Hip = Body.TransformPosition(Placement.Get_HipLocal());
                const auto Pole = Body.TransformPosition(Chain.Get_PoleLocal());
                const auto Foot = UCk_Utils_ProceduralLeg_UE::Get_Foot(Leg).Get_Position();

                auto CurveJoints = TArray<FVector>{};
                CurveJoints.SetNumZeroed(Lengths.Num() + 1);
                const auto CurveSolved = ck::SolveProceduralLegCurve(Hip, Foot, Pole - Hip, Lengths, CurveJoints);
                TestTrue(FString::Printf(TEXT("Leg %s: the reference curve solves for the drawn hip, foot and pole"), *Case.LegId.ToString()),
                    CurveSolved);

                const auto Drawn = Get_DrawnJoints(Case.Segments, Lengths);
                const auto GapToCurve = Get_MaxJointGap(Drawn, CurveJoints);
                if (Case.Solver == ECk_ProceduralRig_ChainSolver::Fabrik)
                {
                    TestTrue(FString::Printf(TEXT("Leg %s: an explicit Fabrik chain is not posed by the curve (max joint gap %.3f cm)"),
                        *Case.LegId.ToString(), GapToCurve), GapToCurve > DistinctFromCurve);

                    auto Length = 0.0;
                    for (const auto Segment : Lengths)
                    { Length += Segment; }
                    const auto Reachable = FVector::Dist(Hip, Foot) <= ReachableFraction * Length;
                    const auto EndGap = Drawn.Num() > 0 ? FVector::Dist(Drawn.Last(), Foot) : TNumericLimits<double>::Max();
                    TestTrue(FString::Printf(TEXT("Leg %s: the reference foot is reachable (hip to foot %.1f of %.1f cm)"),
                        *Case.LegId.ToString(), FVector::Dist(Hip, Foot), Length), Reachable);
                    TestTrue(FString::Printf(TEXT("Leg %s: the explicit Fabrik chain ends on its foot (gap %.3f cm)"), *Case.LegId.ToString(), EndGap),
                        EndGap < ReachTolerance);
                }
                else
                {
                    const auto* SolverName = Case.Solver == ECk_ProceduralRig_ChainSolver::Auto ? TEXT("Auto") : TEXT("explicit Curve");
                    TestTrue(FString::Printf(TEXT("Leg %s: the %s chain is posed by the curve (max joint gap %.4f cm)"),
                        *Case.LegId.ToString(), SolverName, GapToCurve), GapToCurve < MatchTolerance);
                }

                const auto Rig = UCk_Utils_ProceduralRig_UE::Cast(Leg);
                TestEqual(FString::Printf(TEXT("Leg %s: the rig stays Ready"), *Case.LegId.ToString()),
                    UCk_Utils_ProceduralRig_UE::Get_Status(Rig), ECk_ProceduralAnimation_Status::Ready);
            }

            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->Root);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
