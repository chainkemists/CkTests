// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_DisableLegFreezesBodyRelative : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 70000.0, 600.0);
    private float _PhaseStart = 0.0;
    private FVector _FrozenLocal;
    private bool _HasFrozenReference = false;
    private FVector _BodyAtFreeze;
    private TArray<FVector> _SegmentsAtFreeze;
    private float _MaxLocalDrift = 0.0;
    private bool _PlantedWhileFrozen = true;
    private FVector _LastFrozenFoot;
    private bool _ReenableObserved = false;
    private float _ReenableJump = 0.0;
    private bool _SwungAfterReenable = false;

    FCk_Handle_ProceduralLeg Get_Leg() const
    {
        return _Fixture.Crawlers[0].Legs[0];
    }

    FTransform Get_Body() const
    {
        return utils_transform::Get_EntityCurrentTransform(_Fixture.Crawlers[0].Root);
    }

    TArray<FVector> Get_SegmentLocations() const
    {
        auto Locations = TArray<FVector>();
        auto Chain = utils_procedural_rig::Get_Chain(utils_procedural_rig::DoCastChecked(Get_Leg()));
        for (auto Segment : Chain.Get_Segments())
        {
            Locations.Add(utils_transform::Get_EntityCurrentLocation(Segment));
        }
        return Locations;
    }

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated single-walker floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the walker is composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("the walker walks for 1 s", n"Check_WalkedOneSecond");
        Add_Step("disable leg 0", n"Step_Disable");
        Add_Step_WaitUntil("leg 0 reads disabled with its frozen pose published", n"Check_Disabled");
        Add_Step_WaitUntil("the body walks 2 s while leg 0 stays frozen", n"Check_FrozenWalk");
        Add_Step("verify the frozen leg and re-enable it", n"Step_VerifyFrozenAndEnable");
        Add_Step_WaitUntil("leg 0 swings again or 1 s passes", n"Check_Reenabled");
        Add_Step("verify the re-enabled leg started where it was drawn", n"Step_VerifyReenable");
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
        auto Ready = _Fixture.Get_IsReady();
        if (Ready)
        {
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
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Leg = Get_Leg();
        utils_procedural_leg::Request_EnableDisable(Leg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION()
    private void Check_Disabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Disabled = utils_procedural_leg::Get_IsEnabled(Get_Leg()) == false;
        if (Disabled)
        {
            _BodyAtFreeze = Get_Body().GetLocation();
            _SegmentsAtFreeze = Get_SegmentLocations();
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Disabled);
    }

    UFUNCTION()
    private void Check_FrozenWalk(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Foot = utils_procedural_leg::Get_Foot(Get_Leg());
        auto Local = Get_Body().InverseTransformPosition(Foot.Get_Position());
        // The reference is taken in the window's own sampling phase: a read on the disable-transition frame
        // sits one frame of body travel off the steady-state body-relative pose.
        if (_HasFrozenReference == false)
        {
            _FrozenLocal = Local;
            _HasFrozenReference = true;
        }
        _MaxLocalDrift = Math::Max(_MaxLocalDrift, (Local - _FrozenLocal).Size());
        _PlantedWhileFrozen = _PlantedWhileFrozen && Foot.Get_Planted();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 2.0);
    }

    UFUNCTION()
    private void Step_VerifyFrozenAndEnable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Leg = Get_Leg();
        Assert_False(utils_procedural_leg::Get_IsEnabled(Leg), "Leg 0 reads disabled");
        Assert_True(_PlantedWhileFrozen, "The disabled foot reports planted on every sampled frame");
        Assert_True(_MaxLocalDrift < 1.0, f"The frozen foot stays body-relative (max drift {_MaxLocalDrift :.3} cm)");
        auto Travel = (Get_Body().GetLocation() - _BodyAtFreeze).Size();
        Assert_True(Travel > 100.0, f"The body moved more than 100 cm while the leg was frozen ({Travel :.1} cm)");
        auto Segments = Get_SegmentLocations();
        Assert_Equals_Int(Segments.Num(), _SegmentsAtFreeze.Num(), "The rig still binds every segment of the disabled leg");
        for (auto Index = 0; Index < Segments.Num() && Index < _SegmentsAtFreeze.Num(); Index++)
        {
            auto Moved = (Segments[Index] - _SegmentsAtFreeze[Index]).Size();
            Assert_True(Moved > Travel * 0.5, f"Segment {Index} of the disabled leg rides with the body ({Moved :.1} cm)");
        }
        _LastFrozenFoot = utils_procedural_leg::Get_Foot(Leg).Get_Position();
        _PhaseStart = float(System::GetGameTimeInSeconds());
        utils_procedural_leg::Request_EnableDisable(Leg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Enable));
    }

    UFUNCTION()
    private void Check_Reenabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Foot = utils_procedural_leg::Get_Foot(Get_Leg());
        if (_ReenableObserved == false)
        {
            if (utils_procedural_leg::Get_IsEnabled(Get_Leg()))
            {
                _ReenableObserved = true;
                _ReenableJump = (Foot.Get_Position() - _LastFrozenFoot).Size();
            }
            else
            {
                _LastFrozenFoot = Foot.Get_Position();
            }
        }
        _SwungAfterReenable = _SwungAfterReenable || (_ReenableObserved && Foot.Get_SwingAlpha() > 0.0);
        auto Result = OutResult;
        Result.Set(_SwungAfterReenable || Get_Elapsed() >= 1.0);
    }

    UFUNCTION()
    private void Step_VerifyReenable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto StepHeight = _Fixture.Crawlers[0].GaitPreset.Get_Step().Get_Height();
        Assert_True(_ReenableObserved, "Leg 0 reads enabled after the enable request");
        Assert_True(_ReenableJump < StepHeight,
            f"On the re-enable frame the foot is within a step height of its last frozen pose (moved {_ReenableJump :.2} cm)");
        Assert_True(_SwungAfterReenable, "Leg 0 swings within 1 s of being re-enabled");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
