#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkProceduralAnimation/Core/CkProceduralGaitSolver.h"

namespace CkProceduralGaitCatchStepTestLocal
{
    constexpr EAutomationTestFlags CatchStepTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::EngineFilter;

    constexpr FCk_Time CatchStepFrameDt{1.f / 60.f};

    struct FCatchStepGaitHarness
    {
        ck::FProceduralGaitSolver Solver;
        TArray<FVector> Neutrals;
        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;

        void Init(std::initializer_list<FVector> InNeutrals, std::initializer_list<float> PhaseOffsets)
        {
            Neutrals = InNeutrals;
            Inputs.SetNum(Neutrals.Num());
            Outputs.SetNum(Neutrals.Num());
            for (int32 i = 0; i < Neutrals.Num(); ++i)
            {
                Inputs[i].Get_IdealTarget() = Neutrals[i];
                Inputs[i].Get_PhaseOffset() = PhaseOffsets.begin()[i];
            }
            Solver.Reset(Neutrals);
        }

        void Tick(bool Airborne = false)
        {
            Solver.Step(CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs, Airborne);
        }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitCatchStepFiresTest,
    "Ck.ProceduralAnimation.Gait.CatchStepFiresOutsideWindow", CkProceduralGaitCatchStepTestLocal::CatchStepTestFlags)

auto
FCkProceduralGaitCatchStepFiresTest::RunTest(const FString& InParameters) -> bool
{
    {
        const FVector N0(30.f, 20.f, 0.f);
        const FVector N1(30.f, -20.f, 0.f);
        const FVector N2(-30.f, 20.f, 0.f);
        const FVector N3(-30.f, -20.f, 0.f);

        CkProceduralGaitCatchStepTestLocal::FCatchStepGaitHarness H;
        H.Init({ N0, N1, N2, N3 }, { 0.f, 0.5f, 0.5f, 0.f });

        for (int32 Frame = 0; Frame < 30; ++Frame)
        {
            H.Tick();
            for (int32 Leg = 0; Leg < 4; ++Leg)
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

        const FVector Target = N1 + FVector(40.f, 0.f, 0.f);
        TestTrue(TEXT("A request on a valid planted leg is accepted"), H.Solver.RequestStep(1, Target));
        TestTrue(TEXT("...and reads as pending until it is consumed"), H.Solver.HasPendingStep(1));

        int32 LiftFrame = INDEX_NONE;
        int32 PlantFrame = INDEX_NONE;

        double PeakLift = 0.0;
        FVector PlantPosition = FVector::ZeroVector;

        const int32 BoundFrames = FMath::CeilToInt32(
            (H.Solver.Get_Settings().Get_StepDuration() + FCk_Time{0.25f}) / CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt);
        for (int32 Frame = 0; Frame < BoundFrames; ++Frame)
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

            for (const int32 Other : { 0, 2, 3 })
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

        const auto SwingDuration = CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt * (PlantFrame - LiftFrame);
        TestTrue(FString::Printf(TEXT("The swing lasted about StepDuration (%.3f s vs %.3f s)"),
                SwingDuration.Get_Seconds(), H.Solver.Get_Settings().Get_StepDuration().Get_Seconds()),
            FMath::Abs((SwingDuration - H.Solver.Get_Settings().Get_StepDuration()) / CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt) <= 3.0);
        TestTrue(FString::Printf(TEXT("The foot arced rather than teleported (peak lift %.1f of %.1f)"),
                PeakLift, H.Solver.Get_Settings().Get_StepHeight()),
            PeakLift > 0.5f * H.Solver.Get_Settings().Get_StepHeight());

        TestTrue(FString::Printf(TEXT("The foot landed on the requested spot (%s vs %s)"),
                *PlantPosition.ToCompactString(), *Target.ToCompactString()),
            PlantPosition.Equals(Target, 1.f));

        TestFalse(TEXT("Leg 1's window is still shut after the step"), H.Solver.IsWindowOpen(0.5f));

        TestFalse(TEXT("The request was consumed, not left pending"), H.Solver.HasPendingStep(1));
    }

    {
        ck::FProceduralGaitSolver Solver;
        const FVector Stand(0.f, 0.f, 0.f);
        Solver.Reset({ Stand });

        TArray<ck::FProceduralGaitLegInput> Inputs;
        TArray<ck::FProceduralGaitLegOutput> Outputs;
        Inputs.SetNum(1);
        Outputs.SetNum(1);
        Inputs[0].Get_IdealTarget() = Stand;
        Inputs[0].Get_GroundNormal() = FVector(0.3f, 0.f, 1.f).GetSafeNormal();

        const FVector Ledge(50.f, 0.f, -40.f);
        TestTrue(TEXT("Ledge request accepted"), Solver.RequestStep(0, Ledge));

        FVector PlantPosition = FVector::ZeroVector;
        bool Planted = false;
        const int32 BoundFrames = FMath::CeilToInt32(
            (Solver.Get_Settings().Get_StepDuration() + FCk_Time{0.25f}) / CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt);
        bool Lifted = false;
        for (int32 Frame = 0; Frame < BoundFrames; ++Frame)
        {
            Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitCatchStepInhibitionTest,
    "Ck.ProceduralAnimation.Gait.CatchStepWaitsForInhibition", CkProceduralGaitCatchStepTestLocal::CatchStepTestFlags)

auto
FCkProceduralGaitCatchStepInhibitionTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;

    const FVector P0(0.f, 20.f, 0.f);
    const FVector P1(0.f, -20.f, 0.f);
    Solver.Reset({ P0, P1 });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Inputs.SetNum(2);
    Outputs.SetNum(2);
    Inputs[0].Get_PhaseOffset() = 0.f;
    Inputs[1].Get_PhaseOffset() = 0.5f;

    Inputs[0].Get_IdealTarget() = P0 + FVector(60.f, 0.f, 0.f);
    Inputs[1].Get_IdealTarget() = P1;

    Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestFalse(TEXT("Leg 0 emergency-stepped, so the opposing group is airborne"),
        Outputs[0].Get_Planted()))
    {
        return false;
    }

    const FVector Target = P1 + FVector(0.f, -35.f, 0.f);
    TestTrue(TEXT("Request accepted mid-inhibition"), Solver.RequestStep(1, Target));

    int32 Leg0LandFrame = INDEX_NONE;
    int32 Leg1LiftFrame = INDEX_NONE;
    int32 Leg1PlantFrame = INDEX_NONE;
    FVector Leg1Plant = FVector::ZeroVector;
    bool StillPendingDuringInhibition = false;

    const int32 BoundFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_StepDuration() * 2.f + FCk_Time{0.5f}) / CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt);
    for (int32 Frame = 0; Frame < BoundFrames; ++Frame)
    {
        Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);

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
        Leg1Plant.Equals(Target, 1.f));

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitCatchStepRefusalTest,
    "Ck.ProceduralAnimation.Gait.CatchStepRefusesInvalidLeg", CkProceduralGaitCatchStepTestLocal::CatchStepTestFlags)

auto
FCkProceduralGaitCatchStepRefusalTest::RunTest(const FString& InParameters) -> bool
{
    const FVector N0(30.f, 20.f, 0.f);
    const FVector N1(30.f, -20.f, 0.f);
    const FVector N2(-30.f, 0.f, 0.f);

    CkProceduralGaitCatchStepTestLocal::FCatchStepGaitHarness H;
    H.Init({ N0, N1, N2 }, { 0.f, 0.5f, 0.5f });
    for (int32 Frame = 0; Frame < 30; ++Frame)
    {
        H.Tick();
    }

    const FVector Target = N1 + FVector(40.f, 0.f, 0.f);

    TestFalse(TEXT("A negative leg index is refused"), H.Solver.RequestStep(-1, Target));
    TestFalse(TEXT("An index past the last leg is refused"), H.Solver.RequestStep(3, Target));

    volatile float NegativeOne = -1.f;
    const float NaNValue = FMath::Sqrt(NegativeOne);
    TestFalse(TEXT("A non-finite target is refused"),
        H.Solver.RequestStep(0, FVector(NaNValue, 0.f, 0.f)));
    TestFalse(TEXT("A refused request leaves nothing pending"), H.Solver.HasPendingStep(0));

    for (int32 Frame = 0; Frame < 120; ++Frame)
    {
        H.Tick();
        for (int32 Leg = 0; Leg < 3; ++Leg)
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

    H.Solver.Reset({ N0, N1 });
    TestFalse(TEXT("Reset drops the pending request with the leg set it was indexed against"),
        H.Solver.HasPendingStep(0));
    TestFalse(TEXT("...on every surviving leg"), H.Solver.HasPendingStep(1));
    TestFalse(TEXT("...and the departed index is simply invalid"), H.Solver.HasPendingStep(2));
    TestFalse(TEXT("A request on the departed index is refused"), H.Solver.RequestStep(2, Target));

    TArray<ck::FProceduralGaitLegInput> Inputs;
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Inputs.SetNum(2);
    Outputs.SetNum(2);
    Inputs[0].Get_IdealTarget() = N0;
    Inputs[0].Get_PhaseOffset() = 0.f;
    Inputs[1].Get_IdealTarget() = N1;
    Inputs[1].Get_PhaseOffset() = 0.5f;
    for (int32 Frame = 0; Frame < 120; ++Frame)
    {
        H.Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        if (NOT Outputs[0].Get_Planted() || NOT Outputs[1].Get_Planted())
        {
            AddError(FString::Printf(
                TEXT("A survivor stepped after the dropped request (frame %d)"), Frame));
            return false;
        }
    }

    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkProceduralGaitCatchStepExpiryTest,
    "Ck.ProceduralAnimation.Gait.CatchStepExpiresUnfired", CkProceduralGaitCatchStepTestLocal::CatchStepTestFlags)

auto
FCkProceduralGaitCatchStepExpiryTest::RunTest(const FString& InParameters) -> bool
{
    ck::FProceduralGaitSolver Solver;
    Solver.Get_Settings().Get_StepDuration() = FCk_Time{1.f};
    Solver.Get_Settings().Get_CatchStepLifetime() = FCk_Time{0.2f};

    const FVector Stand(0.f, 0.f, 0.f);
    Solver.Reset({ Stand });

    TArray<ck::FProceduralGaitLegInput> Inputs;
    TArray<ck::FProceduralGaitLegOutput> Outputs;
    Inputs.SetNum(1);
    Outputs.SetNum(1);

    Inputs[0].Get_IdealTarget() = Stand + FVector(60.f, 0.f, 0.f);

    Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    if (NOT TestFalse(TEXT("The leg is mid-swing when the request arrives"), Outputs[0].Get_Planted()))
    {
        return false;
    }

    const FVector Target = Stand + FVector(0.f, 120.f, 0.f);
    TestTrue(TEXT("The request is accepted even though it cannot fire yet"),
        Solver.RequestStep(0, Target));

    const int32 ExpiryFrames = FMath::CeilToInt32(Solver.Get_Settings().Get_CatchStepLifetime() / CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt) + 1;
    for (int32 Frame = 0; Frame < ExpiryFrames; ++Frame)
    {
        Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
    }
    TestFalse(TEXT("The request expired while the leg was still in the air"),
        Solver.HasPendingStep(0));

    double WorstY = 0.0;
    bool EverPlanted = false;
    for (int32 Frame = 0; Frame < 300; ++Frame)
    {
        Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
        EverPlanted = EverPlanted || Outputs[0].Get_Planted();
        WorstY = FMath::Max(WorstY, FMath::Abs(Outputs[0].Get_Position().Y));
    }

    TestTrue(TEXT("The leg completed the stride it was already taking"), EverPlanted);
    TestTrue(FString::Printf(TEXT("The expired request never fired late (worst |Y| %.2f)"), WorstY),
        WorstY < 1.f);

    TestTrue(TEXT("A fresh request after the expiry is accepted"), Solver.RequestStep(0, Target));

    FVector FinalPlant = FVector::ZeroVector;
    bool Lifted = false;
    bool Landed = false;
    const int32 BoundFrames = FMath::CeilToInt32(
        (Solver.Get_Settings().Get_StepDuration() + FCk_Time{0.25f}) / CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt);
    for (int32 Frame = 0; Frame < BoundFrames; ++Frame)
    {
        Solver.Step(CkProceduralGaitCatchStepTestLocal::CatchStepFrameDt, 0.f, FVector::ZeroVector, Inputs, Outputs);
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
        FinalPlant.Equals(Target, 1.f));

    return true;
}

#endif
