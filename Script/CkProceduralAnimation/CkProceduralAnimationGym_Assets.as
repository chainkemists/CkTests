// Language=angelscript

namespace ck_procedural_gym_assets
{
    const float HipRadius = 30.0;
    const float RestRadius = 100.0;
    const float RestDrop = 65.0;
    const float SideHipOffset = 30.0;
    const float SideRestOffset = 100.0;
    const float SpiderRestDrop = 90.0;
    const float CentipedeRestDrop = 45.0;
    const float TentacledRestDrop = 55.0;
    const float BeastRestDrop = 80.0;

    TArray<float32> MakeSegmentLengths(int32 InSegmentCount)
    {
        auto Lengths = TArray<float32>();
        if (InSegmentCount == 3)
        {
            Lengths.Add(40.0f);
            Lengths.Add(40.0f);
            Lengths.Add(60.0f);
            return Lengths;
        }
        Lengths.Add(60.0f);
        Lengths.Add(80.0f);
        return Lengths;
    }

    FCk_ProceduralLeg_Spec MakeLegWithLengths(FName InId, FVector InHipLocal, FVector InRestFootLocal,
        FVector InPoleLocal, float32 InPhaseOffset, TArray<float32> InLengths)
    {
        auto Placement = FCk_ProceduralLeg_Placement(InHipLocal, InRestFootLocal);
        Placement.Set_PhaseOffset(InPhaseOffset);

        auto Chain = FCk_ProceduralLeg_ChainGeometry();
        Chain.Set_SegmentLengths(InLengths);
        Chain.Set_PoleLocal(InPoleLocal);

        return FCk_ProceduralLeg_Spec(InId, Placement, Chain);
    }

    FCk_ProceduralLeg_Spec MakeLeg(FName InId, FVector InHipLocal, FVector InRestFootLocal,
        FVector InPoleLocal, float32 InPhaseOffset, int32 InSegmentCount)
    {
        return MakeLegWithLengths(InId, InHipLocal, InRestFootLocal, InPoleLocal, InPhaseOffset, MakeSegmentLengths(InSegmentCount));
    }

    FVector Get_RadialDirection(int32 InLegIndex, int32 InLegCount)
    {
        auto Angle = Math::DegreesToRadians(360.0 * (InLegIndex + 0.5) / InLegCount);
        return FVector(Math::Cos(Angle), Math::Sin(Angle), 0.0);
    }

    FCk_ProceduralLeg_Spec MakeRadialLeg(int32 InLegIndex, int32 InLegCount, int32 InSegmentCount)
    {
        auto Radial = Get_RadialDirection(InLegIndex, InLegCount);
        auto Drop = FVector(0.0, 0.0, RestDrop);
        return MakeLeg(FName(f"Leg{InLegIndex}"), Radial * HipRadius, Radial * RestRadius - Drop,
            Radial * RestRadius + Drop, InLegIndex % 2 == 0 ? 0.0f : 0.5f, InSegmentCount);
    }

    TArray<FCk_ProceduralLeg_Spec> MakeRadialLegs(int32 InLegCount, int32 InSegmentCount)
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>();
        for (auto LegIndex = 0; LegIndex < InLegCount; LegIndex++)
        {
            Legs.Add(MakeRadialLeg(LegIndex, InLegCount, InSegmentCount));
        }
        return Legs;
    }

    // Two legs on the body's lateral axis, the layout the admission and buried-probe tests assert against.
    FCk_ProceduralLeg_Spec MakeSideLeg(int32 InLegIndex)
    {
        auto Side = InLegIndex == 0 ? -1.0 : 1.0;
        auto Drop = FVector(0.0, 0.0, RestDrop);
        return MakeLeg(FName(f"Leg{InLegIndex}"), FVector(0.0, Side * SideHipOffset, 0.0),
            FVector(0.0, Side * SideRestOffset, 0.0) - Drop, FVector(0.0, Side * SideRestOffset, 0.0) + Drop,
            InLegIndex == 0 ? 0.0f : 0.5f, 2);
    }

    TArray<FCk_ProceduralLeg_Spec> MakeSideLegs()
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>();
        Legs.Add(MakeSideLeg(0));
        Legs.Add(MakeSideLeg(1));
        return Legs;
    }

    TArray<FCk_ProceduralLeg_Spec> MakeRadialLegsWithLengths(int32 InLegCount, float InHipRadius, float InRestRadius,
        float InRestDrop, float InPoleRadius, float InPoleHeight, TArray<float32> InLengths)
    {
        auto Legs = TArray<FCk_ProceduralLeg_Spec>();
        for (auto LegIndex = 0; LegIndex < InLegCount; LegIndex++)
        {
            auto Radial = Get_RadialDirection(LegIndex, InLegCount);
            Legs.Add(MakeLegWithLengths(FName(f"Leg{LegIndex}"), Radial * InHipRadius,
                Radial * InRestRadius - FVector(0.0, 0.0, InRestDrop), Radial * InPoleRadius + FVector(0.0, 0.0, InPoleHeight),
                LegIndex % 2 == 0 ? 0.0f : 0.5f, InLengths));
        }
        return Legs;
    }

    TArray<FCk_ProceduralLeg_Spec> MakeSpiderLegs()
    {
        auto Lengths = TArray<float32>();
        Lengths.Add(50.0f);
        Lengths.Add(60.0f);
        Lengths.Add(60.0f);
        Lengths.Add(50.0f);
        return MakeRadialLegsWithLengths(8, 35.0, 170.0, SpiderRestDrop, 85.0, 225.0, Lengths);
    }

    TArray<FCk_ProceduralLeg_Spec> MakeTentacledLegs()
    {
        auto Lengths = TArray<float32>();
        for (auto SegmentIndex = 0; SegmentIndex < 8; SegmentIndex++)
        {
            Lengths.Add(18.0f);
        }
        return MakeRadialLegsWithLengths(6, 32.0, 110.0, TentacledRestDrop, 50.0, 140.0, Lengths);
    }

    // Four phase groups of four legs, a quarter cycle apart: the gait only overlaps swings of legs that share an offset,
    // so four serialized groups must fit in one cycle. Each right leg is half a cycle behind its left.
    TArray<FCk_ProceduralLeg_Spec> MakeCentipedeLegs()
    {
        auto Lengths = TArray<float32>();
        Lengths.Add(45.0f);
        Lengths.Add(55.0f);
        auto Legs = TArray<FCk_ProceduralLeg_Spec>();
        for (auto Pair = 0; Pair < 8; Pair++)
        {
            auto HipX = 105.0 - 30.0 * Pair;
            for (auto SideIndex = 0; SideIndex < 2; SideIndex++)
            {
                auto Side = SideIndex == 0 ? -1.0 : 1.0;
                auto PhaseOffset = Math::Frac((Pair % 4) * 0.25 + (SideIndex == 0 ? 0.0 : 0.5));
                Legs.Add(MakeLegWithLengths(FName(SideIndex == 0 ? f"L{Pair}" : f"R{Pair}"), FVector(HipX, Side * 22.0, 0.0),
                    FVector(HipX, Side * 90.0, -CentipedeRestDrop), FVector(HipX, Side * 60.0, 80.0), float32(PhaseOffset), Lengths));
            }
        }
        return Legs;
    }

    FCk_ProceduralLeg_Spec MakeBeastLeg(FName InId, float InFore, float InSide, float32 InPhaseOffset, TArray<float32> InLengths)
    {
        auto HipX = InFore * 45.0;
        return MakeLegWithLengths(InId, FVector(HipX, InSide * 26.0, 0.0), FVector(InFore * 52.0, InSide * 60.0, -BeastRestDrop),
            FVector(HipX - InFore * 80.0, InSide * 40.0, -20.0), InPhaseOffset, InLengths);
    }

    TArray<FCk_ProceduralLeg_Spec> MakeBeastLegs()
    {
        auto FrontLengths = TArray<float32>();
        FrontLengths.Add(50.0f);
        FrontLengths.Add(50.0f);
        auto RearLengths = TArray<float32>();
        RearLengths.Add(30.0f);
        RearLengths.Add(35.0f);
        RearLengths.Add(30.0f);
        RearLengths.Add(25.0f);
        auto Legs = TArray<FCk_ProceduralLeg_Spec>();
        Legs.Add(MakeBeastLeg(n"FL", 1.0, -1.0, 0.0f, FrontLengths));
        Legs.Add(MakeBeastLeg(n"FR", 1.0, 1.0, 0.5f, FrontLengths));
        Legs.Add(MakeBeastLeg(n"RL", -1.0, -1.0, 0.5f, RearLengths));
        Legs.Add(MakeBeastLeg(n"RR", -1.0, 1.0, 0.0f, RearLengths));
        return Legs;
    }
}

// The data assets bind CK_PROPERTY setters, so a direct property assignment here is an ambiguous write;
// the blocks fill their fields through field method calls instead.
namespace ck
{
    asset ProceduralGym_Gait of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(0.8));
        _Timing.Set_StepDuration(FCk_Time(0.22));
        _Step.Set_Height(24.0f);
        _Step.Set_Threshold(30.0f);
    }

    asset ProceduralGym_GaitRedistribute of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(0.8));
        _Timing.Set_StepDuration(FCk_Time(0.22));
        _Timing.Set_LegLossPolicy(ECk_ProceduralGait_LegLossPolicy::RedistributeOffsets);
        _Step.Set_Height(24.0f);
        _Step.Set_Threshold(30.0f);
    }

    asset ProceduralGym_GaitSlow of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(1.2));
        _Timing.Set_StepDuration(FCk_Time(0.3));
        _Step.Set_Height(24.0f);
        _Step.Set_Threshold(30.0f);
    }

    asset ProceduralGym_GaitSpider of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(1.0));
        _Timing.Set_StepDuration(FCk_Time(0.3));
        _Step.Set_Height(40.0f);
        _Step.Set_Threshold(50.0f);
    }

    asset ProceduralGym_GaitCentipede of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(1.0));
        _Timing.Set_StepDuration(FCk_Time(0.2));
        _Timing.Set_CadenceSpeedRef(60.0f);
        _Step.Set_Height(16.0f);
        _Step.Set_Threshold(25.0f);
    }

    asset ProceduralGym_GaitTentacled of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(1.1));
        _Timing.Set_StepDuration(FCk_Time(0.35));
        _Timing.Set_LegLossPolicy(ECk_ProceduralGait_LegLossPolicy::RedistributeOffsets);
        _Step.Set_Height(30.0f);
        _Step.Set_Threshold(35.0f);
    }

    asset ProceduralGym_GaitBeast of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(0.7));
        _Timing.Set_StepDuration(FCk_Time(0.24));
        _Timing.Set_LegLossPolicy(ECk_ProceduralGait_LegLossPolicy::RedistributeOffsets);
        _Step.Set_Height(26.0f);
        _Step.Set_Threshold(35.0f);
    }

    asset ProceduralGym_Rig4 of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeRadialLegs(4, 2));
    }

    asset ProceduralGym_Rig6 of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeRadialLegs(6, 3));
    }

    asset ProceduralGym_Rig8 of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeRadialLegs(8, 2));
    }

    asset ProceduralGym_RigSpider of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeSpiderLegs());
    }

    asset ProceduralGym_RigCentipede of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeCentipedeLegs());
    }

    asset ProceduralGym_RigTentacled of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeTentacledLegs());
    }

    asset ProceduralGym_RigBeast of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeBeastLegs());
    }

    asset ProceduralTest_SideRig of UCk_ProceduralRig_Data
    {
        _Legs.Append(ck_procedural_gym_assets::MakeSideLegs());
    }

    // The first two rays start inside the buried-probe test's floor; only the widened retries reach its exterior.
    asset ProceduralTest_BuriedProbeGait of UCk_ProceduralGait_Data
    {
        _Timing.Set_CycleDuration(FCk_Time(0.8));
        _Timing.Set_StepDuration(FCk_Time(0.22));
        _Step.Set_Height(24.0f);
        _Step.Set_Threshold(30.0f);
        _Probe.Set_Up(10.0f);
        _Probe.Set_Down(200.0f);
        _Probe.Set_OutwardLean(0.0f);
    }

    asset ProceduralTest_ZeroStepDurationGait of UCk_ProceduralGait_Data
    {
        _Timing.Set_StepDuration(FCk_Time(0.0));
    }
}
