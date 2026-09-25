// Language=angelscript

namespace ck_procedural_gym_assets
{
    const float HipRadius = 30.0;
    const float RestRadius = 100.0;
    const float RestDrop = 65.0;
    const float SideHipOffset = 30.0;
    const float SideRestOffset = 100.0;

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

    FCk_Fragment_ProceduralLeg_ParamsData MakeLeg(FName InId, FVector InHipLocal, FVector InRestFootLocal,
        FVector InPoleLocal, float32 InPhaseOffset, int32 InSegmentCount)
    {
        auto Placement = FCk_ProceduralLeg_Placement(InHipLocal, InRestFootLocal);
        Placement.Set_PhaseOffset(InPhaseOffset);

        auto Chain = FCk_ProceduralLeg_ChainGeometry();
        Chain.Set_SegmentLengths(MakeSegmentLengths(InSegmentCount));
        Chain.Set_PoleLocal(InPoleLocal);

        return FCk_Fragment_ProceduralLeg_ParamsData(InId, Placement, Chain);
    }

    FCk_Fragment_ProceduralLeg_ParamsData MakeRadialLeg(int32 InLegIndex, int32 InLegCount, int32 InSegmentCount)
    {
        auto Angle = Math::DegreesToRadians(360.0 * (InLegIndex + 0.5) / InLegCount);
        auto Radial = FVector(Math::Cos(Angle), Math::Sin(Angle), 0.0);
        auto Drop = FVector(0.0, 0.0, RestDrop);
        return MakeLeg(FName(f"Leg{InLegIndex}"), Radial * HipRadius, Radial * RestRadius - Drop,
            Radial * RestRadius + Drop, InLegIndex % 2 == 0 ? 0.0f : 0.5f, InSegmentCount);
    }

    TArray<FCk_Fragment_ProceduralLeg_ParamsData> MakeRadialLegs(int32 InLegCount, int32 InSegmentCount)
    {
        auto Legs = TArray<FCk_Fragment_ProceduralLeg_ParamsData>();
        for (auto LegIndex = 0; LegIndex < InLegCount; LegIndex++)
        {
            Legs.Add(MakeRadialLeg(LegIndex, InLegCount, InSegmentCount));
        }
        return Legs;
    }

    // Two legs on the body's lateral axis, the layout the admission and buried-probe tests assert against.
    FCk_Fragment_ProceduralLeg_ParamsData MakeSideLeg(int32 InLegIndex)
    {
        auto Side = InLegIndex == 0 ? -1.0 : 1.0;
        auto Drop = FVector(0.0, 0.0, RestDrop);
        return MakeLeg(FName(f"Leg{InLegIndex}"), FVector(0.0, Side * SideHipOffset, 0.0),
            FVector(0.0, Side * SideRestOffset, 0.0) - Drop, FVector(0.0, Side * SideRestOffset, 0.0) + Drop,
            InLegIndex == 0 ? 0.0f : 0.5f, 2);
    }

    TArray<FCk_Fragment_ProceduralLeg_ParamsData> MakeSideLegs()
    {
        auto Legs = TArray<FCk_Fragment_ProceduralLeg_ParamsData>();
        Legs.Add(MakeSideLeg(0));
        Legs.Add(MakeSideLeg(1));
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
