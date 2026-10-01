// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_BodyPoseSagsTowardLostLegs : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 90000.0, 600.0);
    private float _PhaseStart = 0.0;
    private int32 _LegCount = 0;
    private int32 _RearCount = 0;
    private float _TiltDisabled = 0.0;
    private bool _TrackingOvershoot = false;
    private float _PeakOffsetZ = 0.0;

    FTransform Get_Body() const
    {
        return utils_transform::Get_EntityCurrentTransform(_Fixture.Crawlers[0].Handles.Root);
    }

    FTransform Get_Presentation() const
    {
        return utils_transform::Get_EntityCurrentTransform(_Fixture.Crawlers[0].Handles.Presentation);
    }

    FVector Get_PresentationLocal() const
    {
        return Get_Body().InverseTransformPosition(Get_Presentation().GetLocation());
    }

    float Get_TiltDegrees() const
    {
        return Math::RadiansToDegrees(Get_Presentation().GetRotation().AngularDistance(Get_Body().GetRotation()));
    }

    float Get_ForwardTiltDegrees() const
    {
        auto BodyForward = Get_Body().GetRotation().GetForwardVector();
        auto PresentationForward = Get_Presentation().GetRotation().GetForwardVector();
        return Math::RadiansToDegrees(Math::Acos(Math::Clamp(BodyForward.DotProduct(PresentationForward), -1.0, 1.0)));
    }

    float Get_OffsetZ() const
    {
        return utils_procedural_body_pose::Get_Offset(_Fixture.Crawlers[0].Handles.BodyPose).GetLocation().Z;
    }

    float Get_RearDrop() const
    {
        return ck_procedural_gym::BodyCollapseDrop * float(_RearCount) / float(_LegCount);
    }

    bool Get_IsRear(FCk_Handle_ProceduralLeg InLeg) const
    {
        return utils_procedural_leg::Get_Placement(InLeg).Get_HipLocal().X < 0.0;
    }

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Crawler4);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::None) == false)
        {
            FinishFailure("The isolated single-walker floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the walker and its body pose are composed and ready", n"Check_Ready", 1200);
        Add_Step_WaitUntil("the walker walks for 1 s", n"Check_WalkedOneSecond");
        Add_Step("verify no sag with every leg and disable the rear legs", n"Step_VerifyRestAndDisableRear");
        Add_Step_WaitUntil("the body sags toward the rear legs or 3 s pass", n"Check_RearSag", 0, 4.0f);
        Add_Step("verify the rear sag and pitch", n"Step_VerifyRearSag");
        Add_Step_WaitUntil("the disabled pose settles for 1.5 s", n"Check_SettleElapsed");
        Add_Step("record the disabled tilt and detach the rear legs", n"Step_RecordTiltAndDetachRear");
        Add_Step_WaitUntil("the rear legs stay detached for 1.5 s", n"Check_SettleElapsed");
        Add_Step("verify the detached tilt matches the disabled tilt, then detach the front legs", n"Step_VerifyDetachedTiltAndDetachFront");
        Add_Step_WaitUntil("the body collapses level or 3 s pass", n"Check_Collapsed", 0, 4.0f);
        Add_Step("verify the collapse carries no tilt", n"Step_VerifyCollapse");
        Add_Step_WaitUntil("the fixture is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The walker could not be composed: {_Fixture.CompositionError}");
            return;
        }
        auto Ready = _Fixture.Get_AllReady() &&
            utils_procedural_body_pose::Get_Status(_Fixture.Crawlers[0].Handles.BodyPose) == ECk_ProceduralAnimation_Status::Ready;
        if (Ready)
        {
            _LegCount = _Fixture.Crawlers[0].Layout.LegCount;
            _RearCount = 0;
            for (auto Leg : _Fixture.Crawlers[0].Handles.Legs)
            {
                if (Get_IsRear(Leg))
                {
                    _RearCount++;
                }
            }
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_WalkedOneSecond(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 1.0);
    }

    UFUNCTION()
    private void Step_VerifyRestAndDisableRear(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_RearCount > 0 && _RearCount < _LegCount, f"The walker has rear and front legs ({_RearCount} of {_LegCount} rear)");
        auto RestLocal = Get_PresentationLocal();
        ck::Trace(f"[BODY-POSE-SAGS] rest: drop {RestLocal.Z :.3} cm, tilt {Get_ForwardTiltDegrees() :.3} deg");
        Assert_True(Math::Abs(RestLocal.Z) < 1.0, f"With every leg supporting, the presentation sits on the body ({RestLocal.Z :.3} cm)");
        for (auto Leg : _Fixture.Crawlers[0].Handles.Legs)
        {
            if (Get_IsRear(Leg))
            {
                auto RearLeg = Leg;
                utils_procedural_leg::Request_EnableDisable(RearLeg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Disable));
            }
        }
        _TrackingOvershoot = true;
        _PeakOffsetZ = 0.0;
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    void Track_Overshoot()
    {
        if (_TrackingOvershoot)
        {
            _PeakOffsetZ = Math::Min(_PeakOffsetZ, Get_OffsetZ());
        }
    }

    UFUNCTION()
    private void Check_RearSag(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        Track_Overshoot();
        // The verify step reads the presentation's transform, which follows the offset through the transform settle.
        auto Result = OutResult;
        Result.Set(Get_PresentationLocal().Z <= -0.9 * Get_RearDrop() || Get_Elapsed() >= 3.0);
    }

    UFUNCTION()
    private void Step_VerifyRearSag(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto RearDrop = Get_RearDrop();
        auto Local = Get_PresentationLocal();
        auto Nose = Get_Body().InverseTransformVectorNoScale(Get_Presentation().GetRotation().GetForwardVector());
        ck::Trace(f"[BODY-POSE-SAGS] rear disabled: drop {Local.Z :.3} cm of {RearDrop :.3}, tilt {Get_ForwardTiltDegrees() :.3} deg, nose Z {Nose.Z :.4}");
        Assert_True(Local.Z <= -0.9 * RearDrop,
            f"The presentation settles at least 90% of the way to {RearDrop :.2} cm below the body ({Local.Z :.2} cm)");
        Assert_True(Nose.Z > 0.05, f"The nose rises over the supporting front legs (body-local forward Z {Nose.Z :.3})");
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_SettleElapsed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        Track_Overshoot();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 1.5);
    }

    UFUNCTION()
    private void Step_RecordTiltAndDetachRear(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TiltDisabled = Get_ForwardTiltDegrees();
        _TrackingOvershoot = false;
        auto Settled = Get_OffsetZ();
        auto Overshoot = Settled < -0.01 ? (Settled - _PeakOffsetZ) / -Settled : 0.0;
        ck::Trace(f"[BODY-POSE-SAGS] rear disabled, settled: drop {Get_PresentationLocal().Z :.3} cm, tilt {_TiltDisabled :.3} deg, peak {_PeakOffsetZ :.3} cm, overshoot {Overshoot * 100.0 :.2}%");
        Assert_True(Overshoot < 0.02, f"The critically damped body-pose spring does not overshoot its settled drop ({Overshoot * 100.0 :.2}%)");
        for (auto Leg : _Fixture.Crawlers[0].Handles.Legs)
        {
            if (ck::IsValid(Leg) && Get_IsRear(Leg))
            {
                auto RearLeg = Leg;
                utils_procedural_leg::Request_Detach(RearLeg,
                    FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned));
            }
        }
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Step_VerifyDetachedTiltAndDetachFront(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto TiltDetached = Get_ForwardTiltDegrees();
        ck::Trace(f"[BODY-POSE-SAGS] rear detached: drop {Get_PresentationLocal().Z :.3} cm, tilt {TiltDetached :.3} deg (disabled {_TiltDisabled :.3} deg)");
        Assert_True(Math::Abs(TiltDetached - _TiltDisabled) < 1.5,
            f"Detaching the disabled rear legs keeps the tilt toward them ({_TiltDisabled :.2} -> {TiltDetached :.2} degrees)");
        for (auto Leg : _Fixture.Crawlers[0].Handles.Legs)
        {
            if (ck::IsValid(Leg) && Get_IsRear(Leg) == false)
            {
                auto FrontLeg = Leg;
                utils_procedural_leg::Request_Detach(FrontLeg,
                    FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned));
            }
        }
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Collapsed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Collapsed = Get_OffsetZ() <= -0.9 * ck_procedural_gym::BodyCollapseDrop && Get_TiltDegrees() < 3.0;
        auto Result = OutResult;
        Result.Set(Collapsed || Get_Elapsed() >= 3.0);
    }

    UFUNCTION()
    private void Step_VerifyCollapse(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto CollapseDrop = ck_procedural_gym::BodyCollapseDrop;
        auto Local = Get_PresentationLocal();
        auto Tilt = Get_TiltDegrees();
        ck::Trace(f"[BODY-POSE-SAGS] collapsed: drop {Local.Z :.3} cm of {CollapseDrop :.3}, tilt {Tilt :.3} deg");
        Assert_True(Local.Z <= -0.9 * CollapseDrop,
            f"With no supporting leg the presentation drops at least 90% of {CollapseDrop :.1} cm ({Local.Z :.2} cm)");
        Assert_True(Tilt < 3.0, f"With no supporting leg the presentation carries no tilt ({Tilt :.2} degrees)");
        Assert_True(utils_procedural_body_pose::Get_Status(_Fixture.Crawlers[0].Handles.BodyPose) == ECk_ProceduralAnimation_Status::Ready,
            "Losing every leg does not fail the body pose");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
