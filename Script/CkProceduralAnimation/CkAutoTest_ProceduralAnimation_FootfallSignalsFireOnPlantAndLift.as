// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FootfallSignalsFireOnPlantAndLift : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 92500.0, 600.0);
    private float _PhaseStart = 0.0;
    private TArray<FCk_ProceduralLeg_Footfall> _Plants;
    private int32 _LiftCount = 0;
    private int32 _PlantCountAtDetach = 0;
    private int32 _LiftCountAtDetach = 0;
    private FCk_Handle_ProceduralLeg _Leg;

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
        Add_Step("bind the footfall signals on leg 0", n"Step_Bind");
        Add_Step_WaitUntil("the walker walks for 3 s", n"Check_WalkedThreeSeconds", 0, 4.0f);
        Add_Step("verify the footfalls and detach leg 0", n"Step_VerifyAndDetach");
        Add_Step_WaitUntil("1 s passes after the detach", n"Check_OneSecondAfterDetach");
        Add_Step("verify the detached leg fired nothing", n"Step_VerifySilence");
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
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AllReady());
    }

    UFUNCTION()
    private void Step_Bind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Leg = _Fixture.Crawlers[0].Handles.Legs[0];
        auto Leg = _Leg;
        utils_procedural_leg::BindTo_OnPlanted(Leg, FCk_Delegate_ProceduralLeg_OnPlanted(this, n"OnPlanted"));
        utils_procedural_leg::BindTo_OnLifted(Leg, FCk_Delegate_ProceduralLeg_OnLifted(this, n"OnLifted"));
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void OnPlanted(FCk_Handle_ProceduralLeg InLeg, FCk_ProceduralLeg_Footfall InFootfall)
    {
        _Plants.Add(InFootfall);
    }

    UFUNCTION()
    private void OnLifted(FCk_Handle_ProceduralLeg InLeg, FCk_ProceduralLeg_Footfall InFootfall)
    {
        _LiftCount++;
    }

    UFUNCTION()
    private void Check_WalkedThreeSeconds(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 3.0);
    }

    UFUNCTION()
    private void Step_VerifyAndDetach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PlantCount = _Plants.Num();
        ck::Trace(f"[FOOTFALL] leg 0 over 3 s: {PlantCount} planted, {_LiftCount} lifted");
        Assert_True(PlantCount >= 2, f"Leg 0 plants at least twice in 3 s of walking ({PlantCount})");
        Assert_True(_LiftCount >= 2, f"Leg 0 lifts at least twice in 3 s of walking ({_LiftCount})");
        Assert_True(PlantCount - _LiftCount <= 1 && _LiftCount - PlantCount <= 1,
            f"Plants and lifts alternate ({PlantCount} planted, {_LiftCount} lifted)");

        // The Flat course's floor slab is authored with its top face at the fixture origin.
        auto FloorZ = _Origin.Z;
        for (auto Index = 0; Index < _Plants.Num(); Index++)
        {
            auto Footfall = _Plants[Index];
            auto Height = Footfall.Get_Position().Z - FloorZ;
            auto NormalDegrees = Math::RadiansToDegrees(Math::Acos(Math::Clamp(Footfall.Get_Normal().GetSafeNormal().Z, -1.0, 1.0)));
            Assert_True(Footfall.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted, f"Plant {Index} reports a trusted contact");
            Assert_True(Math::Abs(Height) <= 15.0, f"Plant {Index} lands on the floor ({Height :.2} cm from it)");
            Assert_True(NormalDegrees <= 10.0, f"Plant {Index} reports the floor's up normal ({NormalDegrees :.2} degrees off up)");
            Assert_True(Footfall.Get_LandingSpeed() >= 0.0, f"Plant {Index} reports a non-negative landing speed ({Footfall.Get_LandingSpeed() :.2} cm/s)");
        }

        _PlantCountAtDetach = PlantCount;
        _LiftCountAtDetach = _LiftCount;
        auto Leg = _Leg;
        utils_procedural_leg::Request_Detach(Leg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned));
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_OneSecondAfterDetach(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 1.0);
    }

    UFUNCTION()
    private void Step_VerifySilence(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(ck::Is_NOT_Valid(_Leg), "Leg 0 was detached");
        Assert_Equals_Int(_Plants.Num(), _PlantCountAtDetach, "A detached leg fires no further plant");
        Assert_Equals_Int(_LiftCount, _LiftCountAtDetach, "A detached leg fires no further lift");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
