// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_RigSwivelsTheKneeAroundAPillar : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 310000.0, 600.0);
    // Walker A swivels, walker B is the control without a clearance policy; they stand 400 cm apart.
    private float _SwivelWalkerY = -200.0;
    private float _ControlWalkerY = 200.0;
    // The side rig's +Y hip is 30 cm out and its rest foot 100 cm out, 65 cm below the hip. The pillar's near face stands
    // 15 cm beyond the hip: its hip-to-rest line crosses the pillar, so the foot plants in front of it, and the leg folds
    // with the authored pole (up and out) lifting the knee into the pillar.
    private float _BodyHeight = 65.0;
    private float _HipY = 30.0;
    private float _NearFaceBeyondHip = 15.0;
    private FVector _PillarHalfExtents = FVector(20.0, 20.0, 100.0);
    private float _EndTolerance = 0.5;
    private float _CrossingMinFraction = 0.02;
    private float _CrossingMaxFraction = 0.98;
    private FCk_Handle_ProceduralGait _SwivelGait;
    private FCk_Handle_ProceduralGait _ControlGait;
    private FCk_Handle_ProceduralLeg _SwivelLeg;
    private FCk_Handle_ProceduralLeg _ControlLeg;
    private TArray<FCk_Handle_Transform> _SwivelSegments;
    private TArray<FCk_Handle_Transform> _ControlSegments;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated pillar fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the pillars are needed, and no crawler may spawn.
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto PillarY = _HipY + _NearFaceBeyondHip + _PillarHalfExtents.Y;
        _Fixture.AddSurface(FVector(0.0, _SwivelWalkerY + PillarY, _PillarHalfExtents.Z), FRotator::ZeroRotator, _PillarHalfExtents, Color);
        _Fixture.AddSurface(FVector(0.0, _ControlWalkerY + PillarY, _PillarHalfExtents.Z), FRotator::ZeroRotator, _PillarHalfExtents, Color);
        Add_Step_WaitUntil("the floor and the pillars are queryable", n"Check_SurfacesReady");
        Add_Step("compose a swivelling and a control side walker beside the pillars", n"Step_ComposeWalkers");
        Add_Step_WaitUntil("both gaits and their rigs are ready", n"Check_RigsReady");
        Add_Step_WaitUntil("both +Y chains are posed", n"Check_ChainsPosed");
        // The rig updates every frame; two more frames give the swivelling rig a solve that starts from its stored angle.
        Add_Step_WaitFrames("one more solve after the first pose", 2);
        Add_Step("verify the swivelled knee clears the pillar and the control knee does not", n"Step_CheckChains");
        Add_Step("retire the fixture and the walkers", n"Step_Destroy");
        Add_Step_WaitUntil("entities and collision are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    FCk_ProceduralWalker Compose(float InWalkerY, ECk_ProceduralRig_Clearance InClearance, TArray<FCk_Handle_Transform>& OutPlusSegments)
    {
        auto Owner = _Fixture.SceneRoot;
        auto Root = utils_entity_lifetime::Request_CreateEntity(Owner);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        auto BodyLocation = _Origin + FVector(0.0, InWalkerY, _BodyHeight);
        auto Body = utils_transform::Add(Root, FTransform(BodyLocation), ECk_Replication::DoesNotReplicate);

        auto Chains = TArray<FCk_ProceduralWalker_LegChain>();
        for (auto LegParams : ck::ProceduralTest_SideRig.Get_Legs())
        {
            auto Lengths = LegParams.Get_Chain().Get_SegmentLengths();
            auto Segments = TArray<FCk_Handle_Transform>();
            for (auto SegmentIndex = 0; SegmentIndex < Lengths.Num(); SegmentIndex++)
            {
                Segments.Add(_Fixture.AddVisual(Root, FTransform(BodyLocation),
                    ck_procedural_gym::Get_SegmentHalfExtents(Lengths, SegmentIndex), FLinearColor(0.1, 0.8, 0.85, 1.0)));
            }
            if (LegParams.Get_Placement().Get_HipLocal().Y > 0.0)
            {
                OutPlusSegments = Segments;
            }
            auto RigParams = FCk_ProceduralRig_Spec();
            RigParams.Set_Segments(Segments);
            RigParams.Set_Clearance(InClearance);
            Chains.Add(FCk_ProceduralWalker_LegChain(LegParams.Get_Id(), RigParams));
        }
        return utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, Chains);
    }

    FCk_Handle_ProceduralLeg Get_PlusLeg(FCk_ProceduralWalker InWalker)
    {
        for (auto Leg : InWalker.Get_Legs())
        {
            if (utils_procedural_leg::Get_Placement(Leg).Get_HipLocal().Y > 0.0)
            {
                return Leg;
            }
        }
        return FCk_Handle_ProceduralLeg();
    }

    UFUNCTION()
    private void Step_ComposeWalkers(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto SwivelWalker = Compose(_SwivelWalkerY, ECk_ProceduralRig_Clearance::Swivel, _SwivelSegments);
        auto ControlWalker = Compose(_ControlWalkerY, ECk_ProceduralRig_Clearance::None, _ControlSegments);
        _SwivelGait = SwivelWalker.Get_Gait();
        _ControlGait = ControlWalker.Get_Gait();
        _SwivelLeg = Get_PlusLeg(SwivelWalker);
        _ControlLeg = Get_PlusLeg(ControlWalker);
        Assert_True(ck::IsValid(_SwivelGait) && ck::IsValid(_ControlGait) && ck::IsValid(_SwivelLeg) && ck::IsValid(_ControlLeg)
            && _SwivelSegments.Num() == 2 && _ControlSegments.Num() == 2, "Both rigged side walkers are admitted");

        auto Hip = _Origin + FVector(0.0, _SwivelWalkerY + _HipY, _BodyHeight);
        auto Rest = _Origin + FVector(0.0, _SwivelWalkerY + 100.0, 0.0);
        auto HipToRest = utils_jolt_query::Get_RayCast(Hip, Rest, FCk_Jolt_QueryFilter());
        Assert_True(HipToRest.Get_HasHit() && HipToRest.Get_Fraction() > _CrossingMinFraction && HipToRest.Get_Fraction() < _CrossingMaxFraction,
            "Precondition: the pillar stands between the +Y hip and its rest foot");
    }

    UFUNCTION()
    private void Check_RigsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = ck::IsValid(_SwivelGait) && ck::IsValid(_ControlGait)
            && utils_procedural_gait::Get_Status(_SwivelGait) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_gait::Get_Status(_ControlGait) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_rig::Get_Status(utils_procedural_rig::DoCastChecked(_SwivelLeg)) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_rig::Get_Status(utils_procedural_rig::DoCastChecked(_ControlLeg)) == ECk_ProceduralAnimation_Status::Ready;
        auto Result = OutResult;
        Result.Set(Ready);
    }

    // Every part is created at its body; a posed segment has moved off it.
    bool Get_IsPosed(TArray<FCk_Handle_Transform> InSegments, float InWalkerY) const
    {
        auto BodyLocation = _Origin + FVector(0.0, InWalkerY, _BodyHeight);
        for (auto Segment : InSegments)
        {
            if (ck::Is_NOT_Valid(Segment) || (utils_transform::Get_EntityCurrentLocation(Segment) - BodyLocation).Size() < 1.0)
            {
                return false;
            }
        }
        return true;
    }

    UFUNCTION()
    private void Check_ChainsPosed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(Get_IsPosed(_SwivelSegments, _SwivelWalkerY) && Get_IsPosed(_ControlSegments, _ControlWalkerY));
    }

    // The drawn joints: the first segment's near end, then every segment's far end.
    TArray<FVector> Get_DrawnJoints(TArray<FCk_Handle_Transform> InSegments, FCk_Handle_ProceduralLeg InLeg) const
    {
        auto Lengths = utils_procedural_leg::Get_ChainGeometry(InLeg).Get_SegmentLengths();
        auto Joints = TArray<FVector>();
        for (auto Index = 0; Index < InSegments.Num() && Index < Lengths.Num(); Index++)
        {
            auto Segment = utils_transform::Get_EntityCurrentTransform(InSegments[Index]);
            auto HalfAxis = Segment.GetRotation().GetForwardVector() * (Lengths[Index] * 0.5);
            if (Index == 0)
            {
                Joints.Add(Segment.GetLocation() - HalfAxis);
            }
            Joints.Add(Segment.GetLocation() + HalfAxis);
        }
        return Joints;
    }

    // A link crosses a solid when a ray along it hits strictly inside it: a hit at its very start began inside a solid, and
    // one at its end is the foot resting on its contact surface.
    int32 Get_CrossingLinks(TArray<FVector> InJoints, FString& OutFirst) const
    {
        auto Crossing = 0;
        for (auto Index = 0; Index + 1 < InJoints.Num(); Index++)
        {
            auto Hit = utils_jolt_query::Get_RayCast(InJoints[Index], InJoints[Index + 1], FCk_Jolt_QueryFilter());
            if (Hit.Get_HasHit() && Hit.Get_Fraction() > _CrossingMinFraction && Hit.Get_Fraction() < _CrossingMaxFraction)
            {
                if (Crossing == 0)
                {
                    auto Fraction = Hit.Get_Fraction();
                    auto Local = Hit.Get_Position() - _Origin;
                    OutFirst = f"link {Index} at fraction {Fraction :.3} ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1})";
                }
                Crossing++;
            }
        }
        return Crossing;
    }

    UFUNCTION()
    private void Step_CheckChains(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto SwivelRig = utils_procedural_rig::DoCastChecked(_SwivelLeg);
        auto ControlRig = utils_procedural_rig::DoCastChecked(_ControlLeg);

        auto ControlJoints = Get_DrawnJoints(_ControlSegments, _ControlLeg);
        FString ControlFirst = "";
        auto ControlCrossing = Get_CrossingLinks(ControlJoints, ControlFirst);
        auto ControlFoot = utils_procedural_leg::Get_Foot(_ControlLeg).Get_Position() - _Origin;
        Assert_True(ControlJoints.Num() == 3 && ControlCrossing >= 1,
            f"Control: the +Y knee posed toward the authored pole passes a link through the pillar ({ControlCrossing} crossing; {ControlFirst}; foot at {ControlFoot.X :.1}, {ControlFoot.Y :.1}, {ControlFoot.Z :.1})");

        auto SwivelJoints = Get_DrawnJoints(_SwivelSegments, _SwivelLeg);
        FString SwivelFirst = "";
        auto SwivelCrossing = Get_CrossingLinks(SwivelJoints, SwivelFirst);
        Assert_True(SwivelJoints.Num() == 3 && SwivelCrossing == 0,
            f"Every link of the swivelled +Y leg is clear of the pillar ({SwivelCrossing} crossing; {SwivelFirst})");

        auto Foot = utils_procedural_leg::Get_Foot(_SwivelLeg).Get_Position();
        auto EndGap = SwivelJoints.Num() > 0 ? (SwivelJoints[SwivelJoints.Num() - 1] - Foot).Size() : 1000000.0;
        auto FootLocal = Foot - _Origin;
        Assert_True(EndGap <= _EndTolerance,
            f"The swivelled chain ends on the foot the gait put at ({FootLocal.X :.1}, {FootLocal.Y :.1}, {FootLocal.Z :.1}) (gap {EndGap :.3} cm)");
        Assert_True(utils_procedural_rig::Get_ChainState(SwivelRig) == ECk_ProceduralRig_ChainState::Clear,
            "The swivelling rig reports its chain Clear");
        auto Swivel = utils_procedural_rig::Get_SwivelDegrees(SwivelRig);
        Assert_True(Swivel != 0.0, f"The swivelling rig turned its knee off the authored pole (swivel {Swivel :.0} degrees)");
        Assert_True(utils_procedural_rig::Get_Clearance(SwivelRig) == ECk_ProceduralRig_Clearance::Swivel,
            "Walker A's rig reads the Swivel clearance");
        Assert_True(utils_procedural_rig::Get_Clearance(ControlRig) == ECk_ProceduralRig_Clearance::None,
            "Walker B's rig reads no clearance policy");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
