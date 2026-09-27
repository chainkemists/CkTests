// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_StepUpOntoABlockAboveClearance : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Stepping;
    private FCkProceduralAnimationGym_Fixture _Blocked;
    private FVector _SteppingOrigin = FVector(120000.0, 342500.0, 600.0);
    private FVector _BlockedOrigin = FVector(120000.0, 345000.0, 600.0);
    // A 75 cm block, 120 cm long and as wide as the lane, 400 cm ahead of the walkers' start: taller than the crawler's
    // 65 cm clearance, so its forward ray meets the face, and within the 85 cm step height.
    private float _BlockTop = 75.0;
    private float _BlockNearX = -800.0;
    private float _BlockLength = 120.0;
    private float _BlockHalfWidth = 300.0;
    private float _MaxStepHeight = 85.0;
    private float _NoStepHeight = 0.0;
    private float _WalkSeconds = 6.0;
    private float _ReachShareOfClearance = 0.8;
    private float _UprightMinZ = 0.95;
    private float _StartTime = -1.0;
    private int32 _SampledFrames = 0;
    private float _SteppingMaxZ = -100000.0;
    private float _SteppingMinNormalZ = 1.0;
    private FString _SteppingMinNormalAt;
    private int32 _StepFrames = 0;
    private int32 _SteppingWallFrames = 0;
    private int32 _BlockedWallFrames = 0;
    private ECk_SurfaceMotion_Obstruction _BlockedLastObstruction = ECk_SurfaceMotion_Obstruction::None;

    float Get_Clearance() const
    {
        return ck_procedural_gym::Get_SpeciesProfile(ECkProceduralAnimationGym_Species::Crawler8).Clearance;
    }

    void DoAdd_Block(FCkProceduralAnimationGym_Fixture& InOutFixture)
    {
        auto HalfTop = _BlockTop * 0.5;
        auto HalfLength = _BlockLength * 0.5;
        InOutFixture.AddSurface(FVector(_BlockNearX + HalfLength, 0.0, HalfTop), FRotator::ZeroRotator,
            FVector(HalfLength, _BlockHalfWidth, HalfTop), FLinearColor(0.18, 0.25, 0.31, 1.0));
    }

    // The walkers keep to their rays: planted feet on the block's top could carry the body over it before its forward ray
    // ever met the face.
    bool DoCreate(FCkProceduralAnimationGym_Fixture& InOutFixture, FCk_Handle InOwner, FVector InOrigin, float InMaxStepHeight)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        auto Walls = FCkProceduralAnimationGym_WallOverride();
        Walls.Source = ECkProceduralAnimationGym_WallSource::Override;
        Walls.WallPolicy = ECk_SurfaceMotion_WallPolicy::Slide;
        Walls.MaxStepHeight = InMaxStepHeight;
        return InOutFixture.Create_WithRoster(InOwner, InOrigin, ECkProceduralAnimationGym_Course::Flat, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::Rays, 0.0, Walls);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = DoCreate(_Stepping, InHandle, _SteppingOrigin, _MaxStepHeight);
        Created = DoCreate(_Blocked, InHandle, _BlockedOrigin, _NoStepHeight) && Created;
        if (Created == false)
        {
            FinishFailure("The two block fixtures could not be created");
            return;
        }
        DoAdd_Block(_Stepping);
        DoAdd_Block(_Blocked);
        Add_Step_WaitUntil("both sliding crawlers are composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("both crawlers walk their routes toward the block for 6 s while every frame is sampled", n"Check_Walked", 0, 10.0f);
        Add_Step("verify the stepping crawler stepped onto the block upright and the other stopped at its face", n"Step_Verify");
        Add_Step_WaitUntil("the fixtures are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Stepping.Update();
        _Blocked.Update();
        if (_Stepping.CompositionError.IsEmpty() == false || _Blocked.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"A crawler could not be composed: {_Stepping.CompositionError}{_Blocked.CompositionError}");
            return;
        }
        auto Result = OutResult;
        Result.Set(_Stepping.Get_AllReady() && _Blocked.Get_AllReady());
    }

    UFUNCTION()
    private void Check_Walked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (_StartTime < 0.0)
        {
            _StartTime = float(System::GetGameTimeInSeconds());
        }
        _Stepping.Update();
        _Blocked.Update();
        _SampledFrames++;

        auto SteppingMotion = _Stepping.Crawlers[0].Handles.Motion;
        auto SteppingLocal = utils_transform::Get_EntityCurrentLocation(_Stepping.Crawlers[0].Handles.Root) - _SteppingOrigin;
        _SteppingMaxZ = Math::Max(_SteppingMaxZ, SteppingLocal.Z);
        auto NormalZ = utils_surface_motion::Get_SupportNormal(SteppingMotion).Z;
        if (NormalZ < _SteppingMinNormalZ)
        {
            _SteppingMinNormalZ = NormalZ;
            _SteppingMinNormalAt = f"x {SteppingLocal.X :.1}, z {SteppingLocal.Z :.1}";
        }
        if (utils_surface_motion::Get_ContactSource(SteppingMotion) == ECk_SurfaceMotion_ContactSource::Step)
        {
            _StepFrames++;
        }
        if (utils_surface_motion::Get_Obstruction(SteppingMotion) == ECk_SurfaceMotion_Obstruction::Wall)
        {
            _SteppingWallFrames++;
        }

        _BlockedLastObstruction = utils_surface_motion::Get_Obstruction(_Blocked.Crawlers[0].Handles.Motion);
        if (_BlockedLastObstruction == ECk_SurfaceMotion_Obstruction::Wall)
        {
            _BlockedWallFrames++;
        }

        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _StartTime >= _WalkSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Clearance = Get_Clearance();
        auto ReachZ = _BlockTop + _ReachShareOfClearance * Clearance;
        auto StopX = _BlockNearX - _ReachShareOfClearance * Clearance;
        auto BlockedLocal = utils_transform::Get_EntityCurrentLocation(_Blocked.Crawlers[0].Handles.Root) - _BlockedOrigin;
        ck::Trace(f"[WALL-POLICY] block: stepping crawler highest body z {_SteppingMaxZ :.1} (bound {ReachZ :.1}), lowest support normal z {_SteppingMinNormalZ :.3} at {_SteppingMinNormalAt}, Step source on {_StepFrames} and Wall obstruction on {_SteppingWallFrames} of {_SampledFrames} frames; blocked crawler at x {BlockedLocal.X :.1} (bound {StopX :.1}), Wall on {_BlockedWallFrames} frames");
        Assert_True(_SampledFrames > 0, "Precondition: the walk was sampled");
        Assert_True(_SteppingMinNormalZ > _UprightMinZ,
            f"The stepping crawler's support normal stays upright on every frame (lowest z {_SteppingMinNormalZ :.3} at {_SteppingMinNormalAt})");
        Assert_True(_SteppingMaxZ >= ReachZ,
            f"Within 6 s the stepping crawler's body reaches the block's top plus 0.8 clearance (highest z {_SteppingMaxZ :.1}, bound {ReachZ :.1})");
        Assert_True(_StepFrames > 0, "The stepping crawler's surface motion reported a Step contact");
        Assert_True(_SteppingWallFrames == 0, f"The stepping crawler never reported a Wall obstruction ({_SteppingWallFrames} frames)");
        Assert_True(_BlockedLastObstruction == ECk_SurfaceMotion_Obstruction::Wall,
            "The crawler without a step height reports a Wall obstruction on the last sampled frame");
        Assert_True(BlockedLocal.X < StopX,
            f"After 6 s the crawler without a step height is short of the block by more than 0.8 clearance (x {BlockedLocal.X :.1}, bound {StopX :.1})");
        _Stepping.Request_Destroy();
        _Blocked.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Stepping.Get_IsDestroyed() && _Blocked.Get_IsDestroyed());
    }
}
