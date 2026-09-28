// Language=angelscript

// Diagnostic A/B: two colocated Spider walkers share the original three-cylinder geometry.
// Only SurfaceMotion height source differs. A passing test proves observation, not a fix.
class UCk_AutoTest_ProceduralAnimation_CylinderHeightSourceDiagnostics : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private float _StartedAt = -1.0;
    private float _LastObservationAt = -1.0;
    private float _LastTraceAt = -1.0;
    private TArray<int32> _Samples;
    private TArray<int32> _MiddleSamples;
    private TArray<int32> _AirPlants;
    private TArray<float> _MaximumRadius;
    private TArray<float> _MinimumUpAlignment;
    private TArray<bool> _CapturedAir;
    private TArray<bool> _CapturedDrift;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = ck_procedural_gym::Get_StressRoster(ECkProceduralAnimationGym_Course::Cylinder);
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 310000.0, 600.0),
            ECkProceduralAnimationGym_Course::Cylinder, Roster, false) == false)
        {
            FinishFailure("The shared cylinder geometry could not be created");
            return;
        }
        for (auto Index = 0; Index < 2; Index++)
        {
            _Samples.Add(0);
            _MiddleSamples.Add(0);
            _AirPlants.Add(0);
            _MaximumRadius.Add(0.0);
            _MinimumUpAlignment.Add(1.0);
            _CapturedAir.Add(false);
            _CapturedDrift.Add(false);
        }
        Add_Step_WaitUntil("observe feet and rays on the same physical cylinder", n"Check_Observe", 0, 25.0f);
        Add_Step("report the height-source observations", n"Step_Report");
        Add_Step("retire both walkers and shared geometry", n"Step_Destroy");
        Add_Step_WaitUntil("shared fixture subtree and collision are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Observe(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (_Fixture.Spawn.Pending && _Fixture.Get_AreSurfacesReady())
        {
            _Fixture.Spawn.HeightSource = ECkProceduralAnimationGym_HeightSource::PlantedFeet;
            _Fixture.SpawnCrawler(0);
            _Fixture.Spawn.HeightSource = ECkProceduralAnimationGym_HeightSource::Rays;
            _Fixture.SpawnCrawler(0);
            _Fixture.Spawn.Pending = false;
        }
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        if (_Fixture.Crawlers.Num() != 2 || _Fixture.Get_AreSurfacesReady() == false)
        {
            return;
        }
        for (auto Crawler : _Fixture.Crawlers)
        {
            if (Crawler.Get_AllReady() == false)
            {
                return;
            }
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartedAt < 0.0)
        {
            _StartedAt = Now;
        }
        if (Now != _LastObservationAt)
        {
            _LastObservationAt = Now;
            auto Trace = _LastTraceAt < 0.0 || Now - _LastTraceAt >= 0.2;
            for (auto Index = 0; Index < 2; Index++)
            {
                auto Crawler = _Fixture.Crawlers[Index];
                auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
                auto Local = Body.GetLocation() - Crawler.Layout.Origin;
                auto Radial = FVector(Local.X, Local.Y - Crawler.Layout.LaneY, 0.0);
                auto Radius = Radial.Size();
                auto Alignment = Body.GetRotation().GetUpVector().DotProduct(Radial.GetSafeNormal());
                auto Middle = Crawler.Progress.RouteStage >= 1 && Crawler.Progress.RouteStage <= 2 &&
                    Local.Z >= ck_procedural_gym::HelixBottomZ + 30.0 && Local.Z <= ck_procedural_gym::HelixTopZ - 30.0;
                _Samples[Index]++;
                if (Middle)
                {
                    _MiddleSamples[Index]++;
                    if (Radius > Crawler.Layout.CylinderRadius + ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species).Clearance + 5.0 &&
                        _CapturedDrift[Index] == false)
                    {
                        _CapturedDrift[Index] = true;
                        auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                            Crawler.Handles.Root, utils_procedural_leg::Get_Id(Crawler.Handles.Legs[0]), Crawler.Layout.Origin);
                        ck::Trace(f"[CylinderHeightDrift] mode {Index} t {Now - _StartedAt :.6} radius {Radius :.6} {Snapshot}");
                    }
                    _MaximumRadius[Index] = Math::Max(_MaximumRadius[Index], Radius);
                    _MinimumUpAlignment[Index] = Math::Min(_MinimumUpAlignment[Index], Alignment);
                    for (auto Leg : Crawler.Handles.Legs)
                    {
                        auto Foot = utils_procedural_leg::Get_Foot(Leg);
                        auto FootLocal = Foot.Get_Position() - Crawler.Layout.Origin;
                        auto FootRadius = FVector(FootLocal.X, FootLocal.Y - Crawler.Layout.LaneY, 0.0).Size();
                        // The middle-height restriction excludes cylinder caps and approach-floor plants.
                        auto Air = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                            Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Guessed &&
                            FootRadius > Crawler.Layout.CylinderRadius + 5.0 && FootLocal.Z > 5.0 &&
                            FootLocal.Z < ck_procedural_gym::CylinderHeight - 5.0;
                        if (Air)
                        {
                            _AirPlants[Index]++;
                            if (_CapturedAir[Index] == false)
                            {
                                _CapturedAir[Index] = true;
                                ck::Trace(f"[CylinderHeightAir] mode {Index} t {Now - _StartedAt :.6} radius {Radius :.6} upRadial {Alignment :.6}");
                                for (auto OtherLeg : Crawler.Handles.Legs)
                                {
                                    auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                                        Crawler.Handles.Root, utils_procedural_leg::Get_Id(OtherLeg), Crawler.Layout.Origin);
                                    ck::Trace(f"[CylinderHeightAir] mode {Index} {Snapshot}");
                                }
                            }
                        }
                    }
                }
                if (Trace)
                {
                    auto Query = int32(utils_surface_motion::Get_ContactQuery(Crawler.Handles.Motion));
                    auto Source = int32(utils_surface_motion::Get_ContactSource(Crawler.Handles.Motion));
                    auto Normal = utils_surface_motion::Get_SupportNormal(Crawler.Handles.Motion);
                    ck::Trace(f"[CylinderHeight] mode {Index} t {Now - _StartedAt :.6} stage {Crawler.Progress.RouteStage} angle {Crawler.Progress.HelixAngle :.6} loops {Crawler.Progress.Traversals} local ({Local.X :.6},{Local.Y :.6},{Local.Z :.6}) radius {Radius :.6} upRadial {Alignment :.6} query {Query} source {Source} normal ({Normal.X :.6},{Normal.Y :.6},{Normal.Z :.6})");
                }
            }
            if (Trace)
            {
                _LastTraceAt = Now;
            }
        }
        auto Result = OutResult;
        Result.Set(Now - _StartedAt >= 20.0);
    }

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < 2; Index++)
        {
            auto Crawler = _Fixture.Crawlers[Index];
            auto Source = utils_surface_motion::Get_HeightSource(Crawler.Handles.Motion);
            Assert_True(Source == (Index == 0 ? ECk_SurfaceMotion_HeightSource::PlantedFeet : ECk_SurfaceMotion_HeightSource::Rays),
                f"Mode {Index} exercises its authored height source");
            Assert_True(_Samples[Index] > 100 && _MiddleSamples[Index] > 0,
                f"Mode {Index} observes actual ready middle-cylinder traversal ({_Samples[Index]}/{_MiddleSamples[Index]})");
            ck::Trace(f"[CylinderHeightSummary] mode {Index} samples {_Samples[Index]} middle {_MiddleSamples[Index]} airPlants {_AirPlants[Index]} maxRadius {_MaximumRadius[Index] :.6} minUpRadial {_MinimumUpAlignment[Index] :.6} angle {Crawler.Progress.HelixAngle :.6} loops {Crawler.Progress.Traversals}");
        }
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
