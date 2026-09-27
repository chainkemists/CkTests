// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_OccludedPlantSteps : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 300000.0, 600.0);
    // A 60 cm post 30 cm to +Y of the lane, 150 cm ahead of the start: the +Y hips pass over it at the 65 cm clearance
    // while the feet they planted beyond it stay on the floor.
    private FVector _PostHalfExtents = FVector(20.0, 20.0, 30.0);
    private float _PostOffsetY = 30.0;
    private float _PostAhead = 150.0;
    // At the gym's 180 cm/s a plant's stance ends before its hip has carried it past the post; at 60 cm/s the cadence is
    // unscaled and a stance (0.58 s) outlasts 1.5 steps, so only the occluded-plant Emergency frees the foot in time.
    private float _DriveSpeed = 60.0;
    private float _PassedBeyondPost = 150.0;
    private float _OcclusionTolerance = 3.0;
    private float _StartInsideFraction = 0.0001;
    private float _MaxOccludedStepDurations = 1.5;
    private TArray<float> _OccludedSince;
    private float _LongestOccluded = 0.0;
    private FString _LongestOccludedAt;
    private int32 _OccludedSamples = 0;

    float Get_PostX() const
    {
        return ck_procedural_gym::StartX + _PostAhead;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, Roster, false) == false)
        {
            FinishFailure("The isolated post fixture could not be created");
            return;
        }
        _Fixture.AddSurface(FVector(Get_PostX(), _PostOffsetY, _PostHalfExtents.Z), FRotator::ZeroRotator, _PostHalfExtents,
            FLinearColor(0.18, 0.25, 0.31, 1.0));
        Add_Step_WaitUntil("the walker is composed and evaluated", n"Check_Ready", 1200);
        Add_Step("drive the walker +X past the post", n"Step_Drive");
        Add_Step_WaitUntil("the walker walks past the post while every planted foot's hip-to-foot ray is watched", n"Check_PassedPost", 1800);
        Add_Step("verify no planted foot stayed occluded for long", n"Step_Verify");
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

    // The fixture's own route would steer at the gym's travel speed, so from here on the test steers and the fixture is not
    // updated.
    UFUNCTION()
    private void Step_Drive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Motion = _Fixture.Crawlers[0].Handles.Motion;
        utils_surface_motion::Request_Steering(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, _DriveSpeed));
    }

    UFUNCTION()
    private void Check_PassedPost(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
        auto Now = float(System::GetGameTimeInSeconds());
        while (_OccludedSince.Num() < Crawler.Handles.Legs.Num())
        {
            _OccludedSince.Add(-1.0);
        }
        for (auto Index = 0; Index < Crawler.Handles.Legs.Num(); Index++)
        {
            auto Leg = Crawler.Handles.Legs[Index];
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto Occluded = false;
            if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted)
            {
                auto Hip = Body.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal());
                auto Sight = utils_jolt_query::Get_RayCast(Hip, Foot.Get_Position(), FCk_Jolt_QueryFilter());
                Occluded = Sight.Get_HasHit() && Sight.Get_Fraction() > _StartInsideFraction
                    && (Sight.Get_Position() - Foot.Get_Position()).Size() > _OcclusionTolerance;
            }
            if (Occluded == false)
            {
                _OccludedSince[Index] = -1.0;
                continue;
            }
            _OccludedSamples++;
            if (_OccludedSince[Index] < 0.0)
            {
                _OccludedSince[Index] = Now;
            }
            auto Duration = Now - _OccludedSince[Index];
            if (Duration > _LongestOccluded)
            {
                _LongestOccluded = Duration;
                auto LegId = utils_procedural_leg::Get_Id(Leg);
                auto X = Body.GetLocation().X - _Origin.X;
                _LongestOccludedAt = f"leg {LegId} at body X {X :.0}";
            }
        }
        auto Result = OutResult;
        Result.Set(Body.GetLocation().X - _Origin.X > Get_PostX() + _PassedBeyondPost);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        auto BodyX = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root).X - _Origin.X;
        Assert_True(BodyX > Get_PostX() + _PassedBeyondPost, f"The walker passes the post (body X {BodyX :.0})");
        auto StepSeconds = Crawler.Layout.GaitPreset.Get_Timing().Get_StepDuration().Get_Seconds();
        auto Limit = _MaxOccludedStepDurations * StepSeconds;
        // No occluded sample at all is a pass: a plant the post occludes usually lifts in the solve that finds it, before
        // this poll sees it. Without the occluded-plant Emergency this course keeps a plant occluded for most of a stance.
        ck::Trace(f"[OCCLUDED-PLANT] longest occluded stance {_LongestOccluded :.3} s ({_LongestOccludedAt}), limit {Limit :.3} s, occluded samples {_OccludedSamples}");
        Assert_True(_LongestOccluded <= Limit,
            f"No planted foot stays occluded longer than {Limit :.3} s (longest {_LongestOccluded :.3} s, {_LongestOccludedAt})");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
