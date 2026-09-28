// Language=angelscript

// A trusted planted foot must stay within the drawn hip's chain while the body pose conforms over posts.
class UCk_AutoTest_ProceduralAnimation_PostsBeastPosedReach : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 85.0f;
    default _AutoStageOriginField = false;

    private FCkProceduralAnimationGym_Fixture _Fixture;
    private int32 _TrustedPlantedSamples = 0;
    private int32 _PhysicalOverrideSamples = 0;
    private float _MaxSimulationExcess = 0.0f;
    private float _MaxPosedExcess = 0.0f;
    private FString _WorstPosed = "none";
    private float _LastTraceAt = -1.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Beast);
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 365000.0, 600.0),
            ECkProceduralAnimationGym_Course::Posts, Roster, false) == false)
        {
            FinishFailure("The isolated real-Jolt Beast posts course could not be created");
            return;
        }
        Add_Step_WaitUntil("the Beast crosses the posts and returns", n"Check_Traversal", 0, 65.0f);
        Add_Step("verify trusted planted posed reach", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    void Sample()
    {
        if (_Fixture.Get_AllReady() == false || _Fixture.Crawlers.Num() != 1)
        {
            return;
        }
        auto Crawler = _Fixture.Crawlers[0];
        auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
        auto Posed = utils_procedural_body_pose::Get_Offset(Crawler.Handles.BodyPose) * Body;
        if (utils_surface_motion::Get_ReachPaceState(Crawler.Handles.Motion) ==
            ECk_SurfaceMotion_ReachPaceState::PhysicalOverride)
        {
            _PhysicalOverrideSamples++;
        }
        for (auto Leg : Crawler.Handles.Legs)
        {
            if (ck::Is_NOT_Valid(Leg) || utils_procedural_leg::Get_EnableDisable(Leg) != ECk_EnableDisable::Enable)
            {
                continue;
            }
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            if (Foot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted ||
                Foot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted)
            {
                continue;
            }
            _TrustedPlantedSamples++;
            auto Reach = 0.0f;
            for (auto Length : utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths())
            {
                Reach += Length;
            }
            auto HipLocal = utils_procedural_leg::Get_Placement(Leg).Get_HipLocal();
            auto SimulationExcess = (Foot.Get_Position() - Body.TransformPosition(HipLocal)).Size() - Reach;
            auto PosedExcess = (Foot.Get_Position() - Posed.TransformPosition(HipLocal)).Size() - Reach;
            _MaxSimulationExcess = Math::Max(_MaxSimulationExcess, SimulationExcess);
            if (PosedExcess > _MaxPosedExcess)
            {
                _MaxPosedExcess = PosedExcess;
                auto LocalX = Body.GetLocation().X - Crawler.Layout.Origin.X;
                _WorstPosed = f"{utils_procedural_leg::Get_Id(Leg)} at x {LocalX :.1}";
            }
        }
    }

    UFUNCTION()
    private void Check_Traversal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        Sample();
        auto Now = float(System::GetGameTimeInSeconds());
        if (_LastTraceAt < 0.0f || Now - _LastTraceAt >= 5.0f)
        {
            _LastTraceAt = Now;
            auto Stage = _Fixture.Crawlers.Num() == 1 ? _Fixture.Crawlers[0].Progress.RouteStage : -1;
            auto Crawler = _Fixture.Crawlers[0];
            auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
            auto LocalX = Body.GetLocation().X - Crawler.Layout.Origin.X;
            auto Pace = utils_surface_motion::Get_ReachPaceScale(Crawler.Handles.Motion);
            auto PaceState = utils_surface_motion::Get_ReachPaceState(Crawler.Handles.Motion);
            auto Clock = utils_procedural_gait::Get_GaitClock(Crawler.Handles.Gait);
            ck::Trace(f"[PostsBeastPose] stage {Stage}, x {LocalX :.1}, pace {Pace :.2}/{PaceState}, clock {Clock :.2}, trusted plants {_TrustedPlantedSamples}, override {_PhysicalOverrideSamples}, max sim {_MaxSimulationExcess :.2}, max posed {_MaxPosedExcess :.2} at {_WorstPosed}",
                n"PostsBeastPose", 0.0f);
        }
        auto Complete = _Fixture.Crawlers.Num() == 1 && _Fixture.Crawlers[0].Get_HasCompletedCourse() &&
            _Fixture.Get_HasObservedWalking();
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        Assert_True(Crawler.Progress.Traversals > 0 && Crawler.Evidence.InvalidOutput == false,
            "The Beast completed the real posts route with finite ready output");
        Assert_True(_TrustedPlantedSamples > 100,
            f"Sampled trusted planted Beast feet throughout the posts route ({_TrustedPlantedSamples})");
        Assert_True(_MaxSimulationExcess <= 0.5f,
            f"Simulation hips retained chain reach (worst {_MaxSimulationExcess :.2} cm)");
        Assert_True(_MaxPosedExcess <= 0.5f,
            f"Drawn hips retained trusted planted chain reach (worst {_MaxPosedExcess :.2} cm at {_WorstPosed}; overrides {_PhysicalOverrideSamples})");
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
