// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_SlidePolicyStopsAtLedge : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 340000.0, 600.0);
    // Valid for the crawler's 65 cm clearance and below the 150 cm ledge, so the ledge's face is a wall to it.
    private float _MaxStepHeight = 85.0;
    private float _WalkSeconds = 8.0;
    private float _StopShareOfClearance = 0.8;
    private float _StartTime = -1.0;
    private int32 _SampledFrames = 0;
    private int32 _WallFrames = 0;
    private ECk_SurfaceMotion_Obstruction _LastObstruction = ECk_SurfaceMotion_Obstruction::None;
    private FVector _LastObstructionNormal = FVector::ZeroVector;

    float Get_Clearance() const
    {
        return ck_procedural_gym::Get_SpeciesProfile(ECkProceduralAnimationGym_Species::Crawler8).Clearance;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        auto Walls = FCkProceduralAnimationGym_WallOverride();
        Walls.Source = ECkProceduralAnimationGym_WallSource::Override;
        Walls.WallPolicy = ECk_SurfaceMotion_WallPolicy::Slide;
        Walls.MaxStepHeight = _MaxStepHeight;
        auto Created = _Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Ledge, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::Species, 0.0, Walls);
        if (Created == false)
        {
            FinishFailure("The ledge fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the sliding crawler is composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("the crawler walks its route toward the ledge for 8 s while every frame is sampled", n"Check_Walked", 0, 12.0f);
        Add_Step("verify the body stopped before the ledge against a wall and stayed grounded", n"Step_Verify");
        Add_Step_WaitUntil("the fixture is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The crawler could not be composed: {_Fixture.CompositionError}");
            return;
        }
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AllReady());
    }

    UFUNCTION()
    private void Check_Walked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (_StartTime < 0.0)
        {
            _StartTime = float(System::GetGameTimeInSeconds());
        }
        _Fixture.Update();
        auto Motion = _Fixture.Crawlers[0].Handles.Motion;
        _SampledFrames++;
        _LastObstruction = utils_surface_motion::Get_Obstruction(Motion);
        _LastObstructionNormal = utils_surface_motion::Get_ObstructionNormal(Motion);
        if (_LastObstruction == ECk_SurfaceMotion_Obstruction::Wall)
        {
            _WallFrames++;
        }
        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _StartTime >= _WalkSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        auto Motion = Crawler.Handles.Motion;
        auto Local = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root) - _Origin;
        auto NearFaceX = -ck_procedural_gym::LedgeHalfLength;
        auto StopX = NearFaceX - _StopShareOfClearance * Get_Clearance();
        auto Source = int32(utils_surface_motion::Get_ContactSource(Motion));
        ck::Trace(f"[WALL-POLICY] ledge: body at ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1}), stop line {StopX :.1}; wall obstruction on {_WallFrames} of {_SampledFrames} frames, last normal ({_LastObstructionNormal.X :.2}, {_LastObstructionNormal.Y :.2}, {_LastObstructionNormal.Z :.2}); source {Source}");
        Assert_True(utils_surface_motion::Get_WallPolicy(Motion) == ECk_SurfaceMotion_WallPolicy::Slide, "Precondition: the crawler slides");
        Assert_True(Local.X < StopX, f"After 8 s the body is short of the ledge's near face by more than 0.8 clearance (x {Local.X :.1}, bound {StopX :.1})");
        Assert_True(_LastObstruction == ECk_SurfaceMotion_Obstruction::Wall, "On the last sampled frame the surface motion reports a Wall obstruction");
        Assert_True(utils_surface_motion::Get_Support(Motion) == ECk_SurfaceMotion_Support::Grounded, "The crawler is still grounded");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
