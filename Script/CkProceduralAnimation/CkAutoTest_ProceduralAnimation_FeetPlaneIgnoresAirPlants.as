// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FeetPlaneIgnoresAirPlants : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 322500.0, 600.0);
    // A thin plate high above the floor: past its edge no surface-motion ray and no gait probe finds anything, so the legs
    // that reach beyond it gather into the air and plant there, untrusted. Its edge is thinner than the quarter clearance
    // the feet's footprint reaches past the last trusted plant, so once the body leaves that footprint the fan finds
    // nothing either, or at most the plate's edge, off which it falls at once.
    private float _PlateTopZ = 300.0;
    private float _PlateHalfThickness = 5.0;
    private float _PlateMinX = -1500.0;
    private float _PlateEdgeX = -700.0;
    private float _PlateHalfWidth = 300.0;
    private float _FallWithinSeconds = 1.0;
    private float _MaxWaitSeconds = 10.0;
    private float _StartTime = -1.0;
    private float _EdgeCrossedTime = -1.0;
    private float _AirborneTime = -1.0;
    private float _FurthestGroundedPastEdge = 0.0;
    private int32 _FeetFramesPastEdge = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, Roster, false,
                ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::PlantedFeet, _PlateTopZ) == false)
        {
            FinishFailure("The plate fixture could not be created");
            return;
        }
        auto HalfLength = (_PlateEdgeX - _PlateMinX) * 0.5;
        _Fixture.AddSurface(FVector(_PlateMinX + HalfLength, 0.0, _PlateTopZ - _PlateHalfThickness), FRotator::ZeroRotator,
            FVector(HalfLength, _PlateHalfWidth, _PlateHalfThickness), FLinearColor(0.18, 0.25, 0.31, 1.0));
        Add_Step_WaitUntil("the walker is composed on the plate and evaluated", n"Check_Ready", 1200);
        Add_Step("steer the walker along +X at the gym speed", n"Step_Steer");
        Add_Step_WaitUntil("the walker walks off the plate's edge and the body leaves the plate", n"Check_Fell", 0, 12.0f);
        Add_Step("verify the body fell instead of riding the feet it gathered into the air", n"Step_Verify");
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

    // The fixture's own route is not updated from here on: the test steers.
    UFUNCTION()
    private void Step_Steer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Motion = _Fixture.Crawlers[0].Handles.Motion;
        Assert_True(utils_surface_motion::Get_HeightSource(Motion) == ECk_SurfaceMotion_HeightSource::PlantedFeet,
            "Precondition: the walker rides its planted feet");
        Assert_True(utils_surface_motion::Get_Support(Motion) == ECk_SurfaceMotion_Support::Grounded,
            "Precondition: the walker stands on the plate");
        utils_surface_motion::Request_Steering(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, ck_procedural_gym::TravelSpeed));
        _StartTime = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Fell(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Handles = _Fixture.Crawlers[0].Handles;
        auto Local = utils_transform::Get_EntityCurrentLocation(Handles.Root) - _Origin;
        auto Now = float(System::GetGameTimeInSeconds());
        auto Grounded = utils_surface_motion::Get_Support(Handles.Motion) == ECk_SurfaceMotion_Support::Grounded;
        if (_EdgeCrossedTime < 0.0 && Local.X > _PlateEdgeX)
        {
            _EdgeCrossedTime = Now;
        }
        if (_EdgeCrossedTime >= 0.0)
        {
            if (Grounded)
            {
                _FurthestGroundedPastEdge = Math::Max(_FurthestGroundedPastEdge, Local.X - _PlateEdgeX);
            }
            else if (_AirborneTime < 0.0)
            {
                _AirborneTime = Now;
            }
            if (utils_surface_motion::Get_ContactSource(Handles.Motion) == ECk_SurfaceMotion_ContactSource::Feet)
            {
                _FeetFramesPastEdge++;
            }
        }

        auto Result = OutResult;
        Result.Set(_AirborneTime >= 0.0 || Now - _StartTime >= _MaxWaitSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto FellAfter = _AirborneTime >= 0.0 ? _AirborneTime - _EdgeCrossedTime : -1.0;
        auto EdgeCrossed = _EdgeCrossedTime >= 0.0;
        ck::Trace(f"[AIR-PLANTS] edge crossed {EdgeCrossed}, airborne {FellAfter :.3} s after it, grounded up to {_FurthestGroundedPastEdge :.1} cm past the edge, feet contact on {_FeetFramesPastEdge} frames past it");
        Assert_True(EdgeCrossed, "The body's centre walked past the plate's edge");
        Assert_True(_AirborneTime >= 0.0 && FellAfter <= _FallWithinSeconds,
            f"The body falls within {_FallWithinSeconds :.1} s of passing the edge instead of riding its feet in the air (airborne after {FellAfter :.3} s, grounded up to {_FurthestGroundedPastEdge :.1} cm past the edge)");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
