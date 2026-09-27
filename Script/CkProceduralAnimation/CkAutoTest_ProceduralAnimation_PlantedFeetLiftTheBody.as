// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_PlantedFeetLiftTheBody : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Feet;
    private FCkProceduralAnimationGym_Fixture _Rays;
    private FVector _FeetOrigin = FVector(120000.0, 315000.0, 600.0);
    private FVector _RaysOrigin = FVector(120000.0, 317500.0, 600.0);
    // 150 cm pillars with 50 x 50 cm tops on a 120 cm pitch, 25 cm from each landing. Six columns along +X, five rows across
    // the lane so every foot of the walker has tops within reach. The 70 cm gaps are wider than the crawler's clearance,
    // so the control walker's rays can turn it onto a pillar's side and it dips into a gap.
    private float _TopZ = 150.0;
    private float _PillarHalfSize = 25.0;
    private float _Pitch = 120.0;
    private int32 _Columns = 6;
    private int32 _RowsPerSide = 2;
    private float _FirstColumnX = -950.0;
    // The walkers start at the fixture's StartX, on the first landing.
    private float _FirstLandingMinX = -1450.0;
    private float _LandingHalfWidth = 300.0;
    private float _SecondLandingLength = 400.0;
    private float _MaxWaitSeconds = 12.0;
    private float _FeetFloorClearances = 0.8;
    private float _RaysDipClearances = 0.5;
    private float _StartTime = -1.0;
    private float _FeetMinZ = 100000.0;
    private float _RaysMinZ = 100000.0;
    private FString _FeetMinAt;
    private int32 _SampledFrames = 0;
    private int32 _FeetSourceFrames = 0;
    // A trusted plant of the PlantedFeet walker between the landings must stand on a top: its XY within a top, give or take
    // this much. The control dips into the gaps as it must, onto their floor and the pillars' sides: only its trusted plants
    // in the air at the tops' height, off every top, are wrong.
    private float _TopTolerance = 1.0;
    private float _AirPlantMinZ = 145.0;
    private int32 _OffTopPlantFrames = 0;
    private FString _FirstOffTopPlant;
    private int32 _RaysAirPlantFrames = 0;
    private int32 _RaysGroundOffTopPlantFrames = 0;
    private FString _FirstRaysAirPlant;
    // Untrusted plants off a top (a leg tucked over a gap with nothing in reach) are counted and reported, not asserted.
    private int32 _UntrustedOffTopPlantFrames = 0;
    // Each trusted plant off a top is reported as it lands, up to this many, with where its target came from.
    private int32 _ReportedPlantsMax = 12;
    private int32 _ReportedPlants = 0;
    private TMap<FString, bool> _WasPlanted;
    // Riding the feet casts no ray of its own; only foothold searches may add a few.
    private float _RaysPerSolveMargin = 10.0;
    private float _FeetRaysSum = 0.0;
    private float _RaysRaysSum = 0.0;

    float Get_LastColumnFarX() const
    {
        return _FirstColumnX + _Pitch * (_Columns - 1) + _PillarHalfSize;
    }

    // Strictly between the two landings: the pillars, the gaps between them and the gaps next to the landings.
    bool Get_IsBetweenTheLandings(FVector InLocal) const
    {
        auto FirstLandingMaxX = _FirstColumnX - _PillarHalfSize - _PillarHalfSize;
        auto SecondLandingMinX = Get_LastColumnFarX() + _PillarHalfSize;
        return InLocal.X > FirstLandingMaxX + _TopTolerance && InLocal.X < SecondLandingMinX - _TopTolerance
            && Math::Abs(InLocal.Y) <= _LandingHalfWidth;
    }

    bool Get_IsOnATop(FVector InLocal) const
    {
        for (auto Column = 0; Column < _Columns; Column++)
        {
            for (auto Row = -_RowsPerSide; Row <= _RowsPerSide; Row++)
            {
                if (Math::Abs(InLocal.X - (_FirstColumnX + _Pitch * Column)) <= _PillarHalfSize + _TopTolerance
                    && Math::Abs(InLocal.Y - _Pitch * Row) <= _PillarHalfSize + _TopTolerance)
                {
                    return true;
                }
            }
        }
        return false;
    }

    void DoCheck_TrustedPlants(TArray<FCk_Handle_ProceduralLeg> InLegs, FVector InOrigin, FString InWalker)
    {
        for (auto Leg : InLegs)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto LegId = utils_procedural_leg::Get_Id(Leg);
            auto LegKey = f"{InWalker} {LegId}";
            auto Planted = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted;
            auto WasPlanted = true;
            _WasPlanted.Find(LegKey, WasPlanted);
            _WasPlanted.Add(LegKey, Planted);
            if (Planted == false)
            {
                continue;
            }
            auto Local = Foot.Get_Position() - InOrigin;
            if (Get_IsBetweenTheLandings(Local) == false || Get_IsOnATop(Local))
            {
                continue;
            }
            if (Foot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted)
            {
                _UntrustedOffTopPlantFrames++;
                continue;
            }
            if (InWalker == "Rays")
            {
                if (Local.Z < _AirPlantMinZ)
                {
                    _RaysGroundOffTopPlantFrames++;
                    continue;
                }
                _RaysAirPlantFrames++;
                if (_FirstRaysAirPlant.IsEmpty())
                {
                    _FirstRaysAirPlant = f"{LegId} at ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1})";
                }
                continue;
            }
            _OffTopPlantFrames++;
            if (_FirstOffTopPlant.IsEmpty())
            {
                _FirstOffTopPlant = f"{InWalker} {LegId} at ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1})";
            }
            if (WasPlanted == false && _ReportedPlants < _ReportedPlantsMax)
            {
                _ReportedPlants++;
                auto Source = int32(Foot.Get_Foothold());
                auto Verdict = int32(utils_procedural_leg::Get_IdealVerdict(Leg));
                auto Normal = Foot.Get_Normal();
                auto Elapsed = float(System::GetGameTimeInSeconds()) - _StartTime;
                ck::Trace(f"[PLANTED-FEET] trusted plant off a top: t {Elapsed :.3} {InWalker} {LegId} at ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1}), normal ({Normal.X :.2}, {Normal.Y :.2}, {Normal.Z :.2}), foothold {Source}, ideal verdict {Verdict}");
            }
        }
    }

    float Get_Clearance() const
    {
        return ck_procedural_gym::Get_SpeciesProfile(ECkProceduralAnimationGym_Species::Crawler8).Clearance;
    }

    void DoAdd_Crossing(FCkProceduralAnimationGym_Fixture& InOutFixture)
    {
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto HalfTop = _TopZ * 0.5;
        auto FirstLandingMaxX = _FirstColumnX - _PillarHalfSize - _PillarHalfSize;
        auto FirstLandingHalfLength = (FirstLandingMaxX - _FirstLandingMinX) * 0.5;
        InOutFixture.AddSurface(FVector(_FirstLandingMinX + FirstLandingHalfLength, 0.0, HalfTop), FRotator::ZeroRotator,
            FVector(FirstLandingHalfLength, _LandingHalfWidth, HalfTop), Color);
        for (auto Column = 0; Column < _Columns; Column++)
        {
            for (auto Row = -_RowsPerSide; Row <= _RowsPerSide; Row++)
            {
                InOutFixture.AddSurface(FVector(_FirstColumnX + _Pitch * Column, _Pitch * Row, HalfTop), FRotator::ZeroRotator,
                    FVector(_PillarHalfSize, _PillarHalfSize, HalfTop), Color);
            }
        }
        auto SecondLandingMinX = Get_LastColumnFarX() + _PillarHalfSize;
        InOutFixture.AddSurface(FVector(SecondLandingMinX + _SecondLandingLength * 0.5, 0.0, HalfTop), FRotator::ZeroRotator,
            FVector(_SecondLandingLength * 0.5, _LandingHalfWidth, HalfTop), Color);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        auto Created = _Feet.Create_WithRoster(InHandle, _FeetOrigin, ECkProceduralAnimationGym_Course::Flat, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::Species, _TopZ);
        Created = _Rays.Create_WithRoster(InHandle, _RaysOrigin, ECkProceduralAnimationGym_Course::Flat, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::Rays, _TopZ) && Created;
        if (Created == false)
        {
            FinishFailure("The two pillar-row fixtures could not be created");
            return;
        }
        DoAdd_Crossing(_Feet);
        DoAdd_Crossing(_Rays);
        Add_Step_WaitUntil("both walkers are composed on the first landing and evaluated", n"Check_Ready", 1200);
        Add_Step("steer both walkers along +X at the gym speed", n"Step_Steer");
        Add_Step_WaitUntil("the PlantedFeet walker passes the last pillar while both bodies are sampled", n"Check_Crossed", 0, 14.0f);
        Add_Step("verify the planted feet held the body over the gaps and the rays alone did not", n"Step_Verify");
        Add_Step_WaitUntil("the fixtures are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Feet.Update();
        _Rays.Update();
        if (_Feet.CompositionError.IsEmpty() == false || _Rays.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"A walker could not be composed: {_Feet.CompositionError}{_Rays.CompositionError}");
            return;
        }
        auto Result = OutResult;
        Result.Set(_Feet.Get_AllReady() && _Rays.Get_AllReady());
    }

    // The fixtures' own routes are not updated from here on: the test steers.
    UFUNCTION()
    private void Step_Steer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto FeetMotion = _Feet.Crawlers[0].Handles.Motion;
        auto RaysMotion = _Rays.Crawlers[0].Handles.Motion;
        Assert_True(utils_surface_motion::Get_HeightSource(FeetMotion) == ECk_SurfaceMotion_HeightSource::PlantedFeet,
            "Precondition: the first walker rides its planted feet");
        Assert_True(utils_surface_motion::Get_HeightSource(RaysMotion) == ECk_SurfaceMotion_HeightSource::Rays,
            "Precondition: the control walker keeps to its rays");
        utils_surface_motion::Request_Steering(FeetMotion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, ck_procedural_gym::TravelSpeed));
        utils_surface_motion::Request_Steering(RaysMotion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, ck_procedural_gym::TravelSpeed));
        _StartTime = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Crossed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Feet = _Feet.Crawlers[0].Handles;
        auto Rays = _Rays.Crawlers[0].Handles;
        auto FeetLocal = utils_transform::Get_EntityCurrentLocation(Feet.Root) - _FeetOrigin;
        auto RaysLocal = utils_transform::Get_EntityCurrentLocation(Rays.Root) - _RaysOrigin;
        _SampledFrames++;
        if (FeetLocal.Z < _FeetMinZ)
        {
            _FeetMinZ = FeetLocal.Z;
            _FeetMinAt = f"x {FeetLocal.X :.0}";
        }
        _RaysMinZ = Math::Min(_RaysMinZ, RaysLocal.Z);
        if (utils_surface_motion::Get_ContactSource(Feet.Motion) == ECk_SurfaceMotion_ContactSource::Feet)
        {
            _FeetSourceFrames++;
        }
        DoCheck_TrustedPlants(Feet.Legs, _FeetOrigin, "PlantedFeet");
        DoCheck_TrustedPlants(Rays.Legs, _RaysOrigin, "Rays");
        _FeetRaysSum += utils_procedural_animation_debug::Get_RaysLastSolve(Feet.Gait);
        _RaysRaysSum += utils_procedural_animation_debug::Get_RaysLastSolve(Rays.Gait);

        auto Elapsed = float(System::GetGameTimeInSeconds()) - _StartTime;
        auto Result = OutResult;
        Result.Set(FeetLocal.X > Get_LastColumnFarX() + Get_Clearance() || Elapsed >= _MaxWaitSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Clearance = Get_Clearance();
        auto FeetX = (utils_transform::Get_EntityCurrentLocation(_Feet.Crawlers[0].Handles.Root) - _FeetOrigin).X;
        auto FeetFloor = _TopZ + _FeetFloorClearances * Clearance;
        auto RaysDip = _TopZ + _RaysDipClearances * Clearance;
        ck::Trace(f"[PLANTED-FEET] PlantedFeet walker: lowest body z {_FeetMinZ :.1} ({_FeetMinAt}), floor {FeetFloor :.1}, final x {FeetX :.0}, feet contact on {_FeetSourceFrames} of {_SampledFrames} frames; Rays walker: lowest body z {_RaysMinZ :.1}, dip below {RaysDip :.1}");
        Assert_True(_SampledFrames > 0, "Precondition: the crossing was sampled");
        Assert_True(FeetX > Get_LastColumnFarX(), f"The PlantedFeet walker passed the last pillar (x {FeetX :.0}, last pillar ends at {Get_LastColumnFarX() :.0})");
        Assert_True(_FeetMinZ >= FeetFloor,
            f"The PlantedFeet walker's body never fell below the tops plus 0.8 clearance (lowest z {_FeetMinZ :.1} at {_FeetMinAt}, floor {FeetFloor :.1})");
        Assert_True(_FeetSourceFrames > 0, "The PlantedFeet walker's surface motion reported a Feet contact");
        Assert_True(_RaysMinZ < RaysDip,
            f"Control: the Rays walker's body fell below the tops plus half a clearance (lowest z {_RaysMinZ :.1}, threshold {RaysDip :.1})");
        Assert_True(_OffTopPlantFrames == 0,
            f"No trusted plant of the PlantedFeet walker stands off a top between the landings ({_OffTopPlantFrames} leg-frames; first: {_FirstOffTopPlant})");
        Assert_True(_RaysAirPlantFrames == 0,
            f"No trusted plant of the Rays walker stands in the air off a top between the landings ({_RaysAirPlantFrames} leg-frames; first: {_FirstRaysAirPlant})");
        auto FeetRaysPerSolve = _FeetRaysSum / Math::Max(_SampledFrames, 1);
        auto RaysRaysPerSolve = _RaysRaysSum / Math::Max(_SampledFrames, 1);
        ck::Trace(f"[PLANTED-FEET] rays per solve: PlantedFeet {FeetRaysPerSolve :.1}, Rays {RaysRaysPerSolve :.1}; off-top plant leg-frames: PlantedFeet trusted {_OffTopPlantFrames}, Rays trusted in the air {_RaysAirPlantFrames} and on the gaps' floor or the pillars' sides {_RaysGroundOffTopPlantFrames}, untrusted {_UntrustedOffTopPlantFrames}");
        Assert_True(FeetRaysPerSolve <= RaysRaysPerSolve + _RaysPerSolveMargin,
            f"The PlantedFeet walker's rays per solve stay within {_RaysPerSolveMargin :.0} of the Rays walker's ({FeetRaysPerSolve :.1} against {RaysRaysPerSolve :.1})");
        _Feet.Request_Destroy();
        _Rays.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Feet.Get_IsDestroyed() && _Rays.Get_IsDestroyed());
    }
}
