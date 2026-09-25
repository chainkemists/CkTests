#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_gait_catch_step
{
    constexpr auto FrameDt = FCk_Time{1.0f / 60.0f};
    constexpr auto NaN = std::numeric_limits<float>::quiet_NaN();

    struct FCatchStepGaitHarness
    {
        ck::FProceduralGaitSolver Solver;
        TArray<FVector> Neutrals;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        auto
            Init(
                TArrayView<const FVector> InNeutrals,
                TArrayView<const float> InPhaseOffsets)
            -> void
        {
            Neutrals = TArray<FVector>{InNeutrals};
            Inputs.SetNum(Neutrals.Num());
            Outputs.SetNum(Neutrals.Num());
            for (auto Index = 0; Index < Neutrals.Num(); ++Index)
            {
                Inputs[Index].Set_IdealTarget(Neutrals[Index]).Set_PhaseOffset(InPhaseOffsets[Index]);
            }
            Solver.Reset(Neutrals);
        }

        auto
            Tick()
            -> void
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCatchStepFiresTest,
    "Ck.ProceduralAnimation.Gait.CatchStepFiresOutsideWindow",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitCatchStepFiresTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_catch_step;

    {
        const auto N0 = FVector{30.0, 20.0, 0.0};
        const auto N1 = FVector{30.0, -20.0, 0.0};
        const auto N2 = FVector{-30.0, 20.0, 0.0};
        const auto N3 = FVector{-30.0, -20.0, 0.0};

        auto H = FCatchStepGaitHarness{};
        H.Init({N0, N1, N2, N3}, {0.0f, 0.5f, 0.5f, 0.0f});

        for (auto Frame = 0; Frame < 30; ++Frame)
        {
            H.Tick();
            for (auto Leg = 0; Leg < 4; ++Leg)
            {
                if (NOT H.Outputs[Leg].Get_Planted())
                {
                    AddError(FString::Printf(TEXT("Leg %d stepped while standing (frame %d)"), Leg, Frame));
                    return false;
                }
            }
        }

        if (NOT TestFalse(TEXT("Leg 1's phase window is shut before the request"),
            H.Solver.IsWindowOpen(0.5f)))
        {
            return false;
        }

        const auto Target = N1 + FVector{40.0, 0.0, 0.0};
        TestTrue(TEXT("A request on a valid planted leg is accepted"), H.Solver.RequestStep(1, Target));
        TestTrue(TEXT("...and reads as pending until it is consumed"), H.Solver.HasPendingStep(1));

        auto LiftFrame = int32{INDEX_NONE};
        auto PlantFrame = int32{INDEX_NONE};

        auto PeakLift = 0.0;
        auto PlantPosition = FVector::ZeroVector;

        const auto BoundFrames = FMath::CeilToInt32(
            (H.Solver.Get_Settings().Get_StepDuration() + FCk_Time{0.25f}) / FrameDt);
        for (auto Frame = 0; Frame < BoundFrames; ++Frame)
        {
            H.Tick();

            if (NOT H.Outputs[1].Get_Planted())
            {
                if (LiftFrame == INDEX_NONE)
                {
                    LiftFrame = Frame;
                }
                PeakLift = FMath::Max(PeakLift, H.Outputs[1].Get_Position().Z - N1.Z);
            }
            else if (LiftFrame != INDEX_NONE)
            {
                PlantFrame = Frame;
                PlantPosition = H.Outputs[1].Get_Position();
                break;
            }

            for (const auto Other : {0, 2, 3})
            {
                if (NOT H.Outputs[Other].Get_Planted())
                {
                    AddError(FString::Printf(
                        TEXT("Leg %d stepped as a side effect of leg 1's catch step (frame %d)"), Other, Frame));
                    return false;
                }
            }
        }

        if (NOT TestTrue(TEXT("The catch step fired with the window shut"), LiftFrame != INDEX_NONE))
        {
            return false;
        }
        TestTrue(FString::Printf(TEXT("...on the next frame or two (frame %d)"), LiftFrame),
            LiftFrame <= 2);
        if (NOT TestTrue(TEXT("...and the foot planted again"), PlantFrame != INDEX_NONE))
        {
            return false;
        }

        const auto SwingDuration = FrameDt * (PlantFrame - LiftFrame);
        TestTrue(FString::Printf(TEXT("The swing lasted about StepDuration (%.3f s vs %.3f s)"),
                SwingDuration.Get_Seconds(), H.Solver.Get_Settings().Get_StepDuration().Get_Seconds()),
            FMath::Abs((SwingDuration - H.Solver.Get_Settings().Get_StepDuration()) / FrameDt) <= 3.0);
        TestTrue(FString::Printf(TEXT("The foot arced rather than teleported (peak lift %.1f of %.1f)"),
                PeakLift, H.Solver.Get_Settings().Get_StepHeight()),
            PeakLift > 0.5f * H.Solver.Get_Settings().Get_StepHeight());

        TestTrue(FString::Printf(TEXT("The foot landed on the requested spot (%s vs %s)"),
                *PlantPosition.ToCompactString(), *Target.ToCompactString()),
            PlantPosition.Equals(Target, 1.0f));

        TestFalse(TEXT("Leg 1's window is still shut after the step"), H.Solver.IsWindowOpen(0.5f));

        TestFalse(TEXT("The request was consumed, not left pending"), H.Solver.HasPendingStep(1));
    }

    {
        auto Solver = ck::FProceduralGaitSolver{};
        const auto Stand = FVector{0.0, 0.0, 0.0};
        Solver.Reset({Stand});

        auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
        auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
        Inputs.SetNum(1);
        Outputs.SetNum(1);
        Inputs[0].Set_IdealTarget(Stand).Set_GroundNormal(FVector{0.3f, 0.0f, 1.0f}.GetSafeNormal());

        const auto Ledge = FVector{50.0, 0.0, -40.0};
        TestTrue(TEXT("Ledge request accepted"), Solver.RequestStep(0, Ledge));

        auto PlantPosition = FVector::ZeroVector;
        auto Planted = false;
        const auto BoundFrames = FMath::CeilToInt32(
            (Solver.Get_Settings().Get_StepDuration() + FCk_Time{0.25f}) / FrameDt);
        auto Lifted = false;
        for (auto Frame = 0; Frame < BoundFrames; ++Frame)
        {
            Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
            Lifted = Lifted || NOT Outputs[0].Get_Planted();
            if (Lifted && Outputs[0].Get_Planted())
            {
                PlantPosition = Outputs[0].Get_Position();
                Planted = true;
                break;
            }
        }

        if (NOT TestTrue(TEXT("The step-down catch step completed"), Planted))
        {
            return false;
        }
        TestTrue(FString::Printf(TEXT("It landed ON the ledge, not on the stance plane (%s vs %s)"),
                *PlantPosition.ToCompactString(), *Ledge.ToCompactString()),
            PlantPosition.Equals(Ledge, 0.5f));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCatchStepInhibitionTest,
    "Ck.ProceduralAnimation.Gait.CatchStepWaitsForInhibition",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitCatchStepInhibitionTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_catch_step;

    auto Solver = ck::FProceduralGaitSolver{};

    const auto P0 = FVector{0.0, 20.0, 0.0};
    const auto P1 = FVector{0.0, -20.0, 0.0};
    Solver.Reset({P0, P1});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Inputs.SetNum(2);
    Outputs.SetNum(2);
    Inputs[0].Set_PhaseOffset(0.0f).Set_IdealTarget(P0 + FVector{60.0, 0.0, 0.0});
    Inputs[1].Set_PhaseOffset(0.5f).Set_IdealTarget(P1);

    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestFalse(TEXT("Leg 0 emergency-stepped, so the opposing group is airborne"),
        Outputs[0].Get_Planted()))
    {
        return false;
    }

    const auto Target = P1 + FVector{0.0, -35.0, 0.0};
    TestTrue(TEXT("Request accepted mid-inhibition"), Solver.RequestStep(1, Target));

    auto Leg0LandFrame = int32{INDEX_NONE};
    auto Leg1LiftFrame = int32{INDEX_NONE};
    auto Leg1PlantFrame = int32{INDEX_NONE};
    auto Leg1Plant = FVector::ZeroVector;
    auto StillPendingDuringInhibition = false;

    const auto BoundFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_StepDuration() * 2.0f + FCk_Time{0.5f}) / FrameDt);
    for (auto Frame = 0; Frame < BoundFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);

        if (NOT Outputs[0].Get_Planted() && NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(
                TEXT("Both feet airborne at frame %d — the catch step bypassed inhibition"), Frame));
            return false;
        }

        if (Leg0LandFrame == INDEX_NONE)
        {
            StillPendingDuringInhibition = Solver.HasPendingStep(1);
            if (Outputs[0].Get_Planted())
            {
                Leg0LandFrame = Frame;
            }
        }

        if (NOT Outputs[1].Get_Planted())
        {
            if (Leg1LiftFrame == INDEX_NONE)
            {
                Leg1LiftFrame = Frame;
            }
        }
        else if (Leg1LiftFrame != INDEX_NONE)
        {
            Leg1PlantFrame = Frame;
            Leg1Plant = Outputs[1].Get_Position();
            break;
        }
    }

    TestTrue(TEXT("The request survived the wait instead of being dropped"),
        StillPendingDuringInhibition);

    if (NOT TestTrue(TEXT("Leg 0 finished its swing"), Leg0LandFrame != INDEX_NONE))
    {
        return false;
    }
    if (NOT TestTrue(TEXT("Leg 1 eventually took its catch step"), Leg1LiftFrame != INDEX_NONE))
    {
        return false;
    }
    TestTrue(FString::Printf(
            TEXT("Leg 1 waited for leg 0 to land (lift frame %d, land frame %d)"),
            Leg1LiftFrame, Leg0LandFrame),
        Leg1LiftFrame > Leg0LandFrame);

    if (NOT TestTrue(TEXT("Leg 1's catch step completed"), Leg1PlantFrame != INDEX_NONE))
    {
        return false;
    }
    TestTrue(FString::Printf(TEXT("Leg 1 landed on the requested spot (%s vs %s)"),
            *Leg1Plant.ToCompactString(), *Target.ToCompactString()),
        Leg1Plant.Equals(Target, 1.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCatchStepRefusalTest,
    "Ck.ProceduralAnimation.Gait.CatchStepRefusesInvalidLeg",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitCatchStepRefusalTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_catch_step;

    const auto N0 = FVector{30.0, 20.0, 0.0};
    const auto N1 = FVector{30.0, -20.0, 0.0};
    const auto N2 = FVector{-30.0, 0.0, 0.0};

    auto H = FCatchStepGaitHarness{};
    H.Init({N0, N1, N2}, {0.0f, 0.5f, 0.5f});
    for (auto Frame = 0; Frame < 30; ++Frame)
    {
        H.Tick();
    }

    const auto Target = N1 + FVector{40.0, 0.0, 0.0};

    TestFalse(TEXT("A negative leg index is refused"), H.Solver.RequestStep(-1, Target));
    TestFalse(TEXT("An index past the last leg is refused"), H.Solver.RequestStep(3, Target));

    TestFalse(TEXT("A non-finite target is refused"),
        H.Solver.RequestStep(0, FVector{NaN, 0.0f, 0.0f}));
    TestFalse(TEXT("A refused request leaves nothing pending"), H.Solver.HasPendingStep(0));

    for (auto Frame = 0; Frame < 120; ++Frame)
    {
        H.Tick();
        for (auto Leg = 0; Leg < 3; ++Leg)
        {
            if (NOT H.Outputs[Leg].Get_Planted() || NOT H.Outputs[Leg].Get_Position().Equals(H.Neutrals[Leg], KINDA_SMALL_NUMBER))
            {
                AddError(FString::Printf(
                    TEXT("Leg %d moved after a refused request (frame %d, at %s)"),
                    Leg, Frame, *H.Outputs[Leg].Get_Position().ToCompactString()));
                return false;
            }
        }
    }

    TestTrue(TEXT("A live request on the third leg is accepted while it exists"),
        H.Solver.RequestStep(2, Target));

    H.Solver.Reset({N0, N1});
    TestFalse(TEXT("Reset drops the pending request with the leg set it was indexed against"),
        H.Solver.HasPendingStep(0));
    TestFalse(TEXT("...on every surviving leg"), H.Solver.HasPendingStep(1));
    TestFalse(TEXT("...and the departed index is simply invalid"), H.Solver.HasPendingStep(2));
    TestFalse(TEXT("A request on the departed index is refused"), H.Solver.RequestStep(2, Target));

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Inputs.SetNum(2);
    Outputs.SetNum(2);
    Inputs[0].Set_IdealTarget(N0).Set_PhaseOffset(0.0f);
    Inputs[1].Set_IdealTarget(N1).Set_PhaseOffset(0.5f);
    for (auto Frame = 0; Frame < 120; ++Frame)
    {
        H.Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted() || NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(
                TEXT("A survivor stepped after the dropped request (frame %d)"), Frame));
            return false;
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralGaitCatchStepExpiryTest,
    "Ck.ProceduralAnimation.Gait.CatchStepExpiresUnfired",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralGaitCatchStepExpiryTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_gait_catch_step;

    auto Solver = ck::FProceduralGaitSolver{};
    Solver.Get_Settings().Set_StepDuration(FCk_Time{1.0f}).Set_CatchStepLifetime(FCk_Time{0.2f});

    const auto Stand = FVector{0.0, 0.0, 0.0};
    Solver.Reset({Stand});

    auto Inputs = TArray<ck::FProceduralGaitLegInput>{};
    auto Outputs = TArray<ck::FProceduralGaitLegOutput>{};
    Inputs.SetNum(1);
    Outputs.SetNum(1);

    Inputs[0].Set_IdealTarget(Stand + FVector{60.0, 0.0, 0.0});

    Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestFalse(TEXT("The leg is mid-swing when the request arrives"), Outputs[0].Get_Planted()))
    {
        return false;
    }

    const auto Target = Stand + FVector{0.0, 120.0, 0.0};
    TestTrue(TEXT("The request is accepted even though it cannot fire yet"),
        Solver.RequestStep(0, Target));

    const auto ExpiryFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_CatchStepLifetime() / FrameDt) + 1;
    for (auto Frame = 0; Frame < ExpiryFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
    }
    TestFalse(TEXT("The request expired while the leg was still in the air"),
        Solver.HasPendingStep(0));

    auto WorstY = 0.0;
    auto EverPlanted = false;
    for (auto Frame = 0; Frame < 300; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        EverPlanted = EverPlanted || Outputs[0].Get_Planted();
        WorstY = FMath::Max(WorstY, FMath::Abs(Outputs[0].Get_Position().Y));
    }

    TestTrue(TEXT("The leg completed the stride it was already taking"), EverPlanted);
    TestTrue(FString::Printf(TEXT("The expired request never fired late (worst |Y| %.2f)"), WorstY),
        WorstY < 1.0);

    TestTrue(TEXT("A fresh request after the expiry is accepted"), Solver.RequestStep(0, Target));

    auto FinalPlant = FVector::ZeroVector;
    auto Lifted = false;
    auto Landed = false;
    const auto BoundFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_StepDuration() + FCk_Time{0.25f}) / FrameDt);
    for (auto Frame = 0; Frame < BoundFrames; ++Frame)
    {
        Solver.Step(FrameDt, 0.0f, FVector::ZeroVector, Inputs, Outputs);
        Lifted = Lifted || NOT Outputs[0].Get_Planted();
        if (Lifted && Outputs[0].Get_Planted())
        {
            FinalPlant = Outputs[0].Get_Position();
            Landed = true;
            break;
        }
    }

    if (NOT TestTrue(TEXT("The fresh request fired"), Landed))
    {
        return false;
    }
    TestTrue(FString::Printf(TEXT("...and landed on the requested spot (%s vs %s)"),
            *FinalPlant.ToCompactString(), *Target.ToCompactString()),
        FinalPlant.Equals(Target, 1.0f));

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
