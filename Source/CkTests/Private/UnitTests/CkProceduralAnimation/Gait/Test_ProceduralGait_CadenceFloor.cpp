#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkProceduralAnimation/CkProceduralAnimation_Utils.h"
#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimation/Gait/CkProceduralGait_Utils.h"
#include "CkProceduralAnimation/Leg/CkProceduralLeg_Utils.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Misc/AutomationTest.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_cadence_floor
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    // Exactly representable, so the boundary leg below sits on the target radius without rounding.
    constexpr auto TargetReachFraction = 0.75f;
    constexpr auto ForceStepReachFraction = 0.875f;
    constexpr auto SegmentLength = 50.0f;
    constexpr auto LegReach = 2.0 * SegmentLength;
    constexpr auto StanceTravelShare = 0.85;
    constexpr auto AuthoredCadenceSpeedRef = 200.0f;
    constexpr auto LowAuthoredCadenceSpeedRef = 100.0f;
    constexpr auto RestDrop = 50.0;
    constexpr auto LimitingLateral = 40.0;
    constexpr auto NarrowLateral = 30.0;
    constexpr auto ExpectedSkippedLegs = 1;
    constexpr auto RefTolerance = 0.01f;
    constexpr auto SolvesPerChange = uint64{2};
    constexpr auto WaitSeconds = 10.0;
    const auto LimitingLegId = FName{TEXT("Limiting")};

    struct FState
    {
        FCk_Handle Root;
        FCk_Handle_ProceduralGait Gait;
        uint64 SequenceAtChange = 0;
    };

    // The chord a leg with this lateral offset can stride along body X, from the landing limit ahead to the force
    // limit behind.
    auto
        Get_ExpectedStride(
            double InLateral)
        -> double
    {
        const auto TargetRadiusSquared = FMath::Square(TargetReachFraction * LegReach) - FMath::Square(RestDrop);
        const auto ForceRadiusSquared = FMath::Square(ForceStepReachFraction * LegReach) - FMath::Square(RestDrop);
        return FMath::Sqrt(TargetRadiusSquared - FMath::Square(InLateral)) + FMath::Sqrt(ForceRadiusSquared - FMath::Square(InLateral));
    }

    auto
        Get_ExpectedFloor(
            double InLateral,
            FCk_Time InCycle,
            FCk_Time InStep)
        -> float
    {
        return static_cast<float>(StanceTravelShare * Get_ExpectedStride(InLateral) / (InCycle - InStep).Get_Seconds());
    }

    // Four 100 cm legs. "Limiting" has the widest stride-bounding lateral offset; "Boundary" lies exactly on the target
    // radius (45 cm lateral, 60 cm drop, 75 cm reach) so it cannot stride along X and is skipped.
    auto
        MakeRig()
        -> UCk_ProceduralRig_Data*
    {
        const auto MakeLeg = [](FName InId, const FVector& InHip, const FVector& InRest, float InPhaseOffset)
        {
            auto Placement = FCk_ProceduralLeg_Placement{InHip, InRest};
            Placement.Set_PhaseOffset(InPhaseOffset);
            return FCk_ProceduralLeg_Spec{InId, Placement, FCk_ProceduralLeg_ChainGeometry{TArray<float>{SegmentLength, SegmentLength}}};
        };

        auto Legs = TArray<FCk_ProceduralLeg_Spec>{};
        Legs.Add(MakeLeg(LimitingLegId, FVector{0.0, 20.0, 0.0}, FVector{0.0, 20.0 + LimitingLateral, -RestDrop}, 0.0f));
        Legs.Add(MakeLeg(TEXT("Narrow"), FVector{0.0, -20.0, 0.0}, FVector{0.0, -20.0 - NarrowLateral, -RestDrop}, 0.5f));
        Legs.Add(MakeLeg(TEXT("Boundary"), FVector{60.0, 20.0, 0.0}, FVector{60.0, 65.0, -60.0}, 0.5f));
        Legs.Add(MakeLeg(TEXT("NarrowRear"), FVector{60.0, -20.0, 0.0}, FVector{60.0, -20.0 - NarrowLateral, -RestDrop}, 0.0f));

        auto* Rig = NewObject<UCk_ProceduralRig_Data>();
        Rig->Set_Legs(Legs);
        return Rig;
    }

    auto
        MakeTiming(
            FCk_Time InCycle,
            FCk_Time InStep,
            float InCadenceSpeedRef)
        -> FCk_ProceduralGait_Timing
    {
        auto Timing = FCk_ProceduralGait_Timing{};
        Timing.Set_CycleDuration(InCycle);
        Timing.Set_StepDuration(InStep);
        Timing.Set_CadenceSpeedRef(InCadenceSpeedRef);
        return Timing;
    }

    auto
        MakeStep()
        -> FCk_ProceduralGait_Step
    {
        auto Step = FCk_ProceduralGait_Step{};
        Step.Set_TargetReachFraction(TargetReachFraction);
        Step.Set_ForceStepReachFraction(ForceStepReachFraction);
        return Step;
    }

    auto
        Get_DebugGait(
            const TSharedRef<FState>& InState)
        -> FCk_ProceduralAnimation_DebugGait
    {
        return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InState->Root).Get_Gait();
    }

    auto
        Get_Sequence(
            const TSharedRef<FState>& InState)
        -> uint64
    {
        return UCk_Utils_ProceduralAnimation_Debug_UE::Get_Snapshot(InState->Root).Get_Sample().Get_Sequence();
    }

    auto
        Get_HasSolvedSinceChange(
            const TSharedRef<FState>& InState)
        -> bool
    {
        return Get_Sequence(InState) >= InState->SequenceAtChange + SolvesPerChange;
    }

    auto
        DoApplyPreset(
            const TSharedRef<FState>& InState,
            FCk_Time InCycle,
            FCk_Time InStep,
            float InCadenceSpeedRef)
        -> void
    {
        InState->SequenceAtChange = Get_Sequence(InState);
        UCk_Utils_ProceduralGait_UE::Request_ApplyPreset(InState->Gait,
            FCk_Request_ProceduralGait_ApplyPreset{MakeTiming(InCycle, InStep, InCadenceSpeedRef), MakeStep(), FCk_ProceduralGait_Probe{}}, {});
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCadenceFloorFromReachTest,
    "Ck.ProceduralAnimation.Gait.CadenceFloorFromReach",
    ck_test_procedural_gait_cadence_floor::TestFlags)

auto
    FCkProceduralGaitCadenceFloorFromReachTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_cadence_floor;

    const auto AddCycle = FCk_Time{0.8};
    const auto PresetCycle = FCk_Time{1.0};
    const auto StepDuration = FCk_Time{0.3};
    const auto State = MakeShared<FState>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, AddCycle, StepDuration](UWorld* InWorld)
        {
            auto Root = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("PIE transient owner admits the walker root"), ck::IsValid(Root)))
            { return; }

            auto Body = UCk_Utils_Transform_UE::Add(Root, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            auto* Gait = NewObject<UCk_ProceduralGait_Data>();
            Gait->Set_Timing(MakeTiming(AddCycle, StepDuration, AuthoredCadenceSpeedRef));
            Gait->Set_Step(MakeStep());
            const auto Walker = UCk_Utils_ProceduralAnimation_UE::Add_Walker(Body, MakeRig(), Gait, {});
            TestTrue(TEXT("The walker admits every leg, the boundary leg included"), ck::IsValid(Walker.Get_Gait()));
            State->Root = Root;
            State->Gait = Walker.Get_Gait();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return Get_HasSolvedSinceChange(State);
        }), WaitSeconds, TEXT("The walker's gait accepts its first solves")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, AddCycle, PresetCycle, StepDuration](UWorld*)
        {
            const auto DebugGait = Get_DebugGait(State);
            const auto ExpectedFloor = Get_ExpectedFloor(LimitingLateral, AddCycle, StepDuration);
            TestEqual(TEXT("Add: the floor comes from the limiting leg's stride"), DebugGait.Get_ReachCadenceFloor(), ExpectedFloor, RefTolerance);
            TestEqual(TEXT("Add: the floor is below the authored reference, so the solver runs with it"),
                DebugGait.Get_CadenceSpeedRef(), FMath::Min(ExpectedFloor, AuthoredCadenceSpeedRef), RefTolerance);
            TestEqual(TEXT("Add: the boundary leg is skipped"), DebugGait.Get_ReachSkippedLegs(), ExpectedSkippedLegs);

            DoApplyPreset(State, PresetCycle, StepDuration, AuthoredCadenceSpeedRef);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return Get_HasSolvedSinceChange(State);
        }), WaitSeconds, TEXT("The gait solves after the preset is applied")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, PresetCycle, StepDuration](UWorld*)
        {
            const auto ExpectedFloor = Get_ExpectedFloor(LimitingLateral, PresetCycle, StepDuration);
            TestEqual(TEXT("ApplyPreset: a longer stance time lowers the floor"), Get_DebugGait(State).Get_CadenceSpeedRef(),
                FMath::Min(ExpectedFloor, AuthoredCadenceSpeedRef), RefTolerance);

            auto Limiting = UCk_Utils_ProceduralLeg_UE::TryGet_Leg(State->Root, LimitingLegId);
            if (NOT TestTrue(TEXT("The limiting leg is found by Id"), ck::IsValid(Limiting)))
            { return; }
            State->SequenceAtChange = Get_Sequence(State);
            UCk_Utils_ProceduralLeg_UE::Request_EnableDisable(Limiting,
                FCk_Request_ProceduralLeg_EnableDisable{ECk_EnableDisable::Disable}, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return Get_HasSolvedSinceChange(State);
        }), WaitSeconds, TEXT("The gait solves after the limiting leg is disabled")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, PresetCycle, StepDuration](UWorld*)
        {
            const auto DebugGait = Get_DebugGait(State);
            const auto ExpectedFloor = Get_ExpectedFloor(NarrowLateral, PresetCycle, StepDuration);
            TestEqual(TEXT("Enabled-set change: the floor comes from the remaining legs"), DebugGait.Get_ReachCadenceFloor(),
                ExpectedFloor, RefTolerance);
            TestEqual(TEXT("Enabled-set change: the solver runs with the raised floor"), DebugGait.Get_CadenceSpeedRef(),
                FMath::Min(ExpectedFloor, AuthoredCadenceSpeedRef), RefTolerance);
            TestEqual(TEXT("Enabled-set change: the boundary leg is still skipped"), DebugGait.Get_ReachSkippedLegs(), ExpectedSkippedLegs);

            DoApplyPreset(State, PresetCycle, StepDuration, LowAuthoredCadenceSpeedRef);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            return Get_HasSolvedSinceChange(State);
        }), WaitSeconds, TEXT("The gait solves after the low-reference preset is applied")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State, PresetCycle, StepDuration](UWorld*)
        {
            const auto DebugGait = Get_DebugGait(State);
            TestEqual(TEXT("An authored reference below the floor is kept"), DebugGait.Get_CadenceSpeedRef(), LowAuthoredCadenceSpeedRef,
                RefTolerance);
            TestEqual(TEXT("The floor is still reported when the authored reference wins"), DebugGait.Get_ReachCadenceFloor(),
                Get_ExpectedFloor(NarrowLateral, PresetCycle, StepDuration), RefTolerance);

            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->Root);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
