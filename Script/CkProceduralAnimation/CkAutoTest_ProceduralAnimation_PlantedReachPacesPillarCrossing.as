// Language=angelscript

// Real Jolt pillar tops exercise movement, foothold search and stance pacing together. A solver-only reach test cannot
// catch the body advancing while a trusted planted foot still anchors the previous top.
class UCk_AutoTest_ProceduralAnimation_PlantedReachPacesPillarCrossing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 70.0f;
    default _AutoStageOriginField = false;

    private FCkProceduralAnimationGym_Fixture _Fixture;
    private float _MaxSimulationExcess = 0.0;
    private float _MaxPresentationExcess = 0.0;
    private FString _WorstSimulation = "none";
    private FString _WorstPresentation = "none";
    private int32 _TrustedPlantedSamples = 0;
    private int32 _FieldSamples = 0;
    private float _LastTraceAt = -1.0;
    private float _MaxAllowedExcess = 0.5;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 320000.0, 600.0),
            ECkProceduralAnimationGym_Course::PillarCrossing, Roster, false) == false)
        {
            FinishFailure("The isolated real-Jolt pillar crossing could not be created");
            return;
        }
        Add_Step_WaitUntil("the tentacled walker crosses the pillar field and returns", n"Check_Traversal", 0, 50.0f);
        Add_Step("verify planted chains stayed reachable while the body advanced", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    void SampleReach()
    {
        if (_Fixture.Get_AllReady() == false || _Fixture.Crawlers.Num() != 1)
        {
            return;
        }
        auto Crawler = _Fixture.Crawlers[0];
        auto Simulation = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
        auto Posed = utils_procedural_body_pose::Get_Offset(Crawler.Handles.BodyPose) * Simulation;
        auto LocalX = Simulation.GetLocation().X - Crawler.Layout.Origin.X;
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
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            auto Reach = 0.0;
            for (auto Length : Lengths)
            {
                Reach += Length;
            }
            if (Reach <= 0.0)
            {
                continue;
            }
            auto HipLocal = utils_procedural_leg::Get_Placement(Leg).Get_HipLocal();
            auto SimulationExcess = (Foot.Get_Position() - Simulation.TransformPosition(HipLocal)).Size() - Reach;
            auto PresentationExcess = (Foot.Get_Position() - Posed.TransformPosition(HipLocal)).Size() - Reach;
            _TrustedPlantedSamples++;
            if (Math::Abs(LocalX) <= ck_procedural_gym::CrossingFieldHalfSpanX)
            {
                _FieldSamples++;
            }
            if (SimulationExcess > _MaxSimulationExcess)
            {
                _MaxSimulationExcess = SimulationExcess;
                _WorstSimulation = f"{utils_procedural_leg::Get_Id(Leg)} at x {LocalX :.1}, reach {Reach :.1}";
            }
            if (PresentationExcess > _MaxPresentationExcess)
            {
                _MaxPresentationExcess = PresentationExcess;
                _WorstPresentation = f"{utils_procedural_leg::Get_Id(Leg)} at x {LocalX :.1}, reach {Reach :.1}";
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
        SampleReach();
        auto Now = float(System::GetGameTimeInSeconds());
        if (_LastTraceAt < 0.0 || Now - _LastTraceAt >= 5.0)
        {
            _LastTraceAt = Now;
            auto Stage = _Fixture.Crawlers.Num() == 1 ? _Fixture.Crawlers[0].Progress.RouteStage : -1;
            auto Traversals = _Fixture.Crawlers.Num() == 1 ? _Fixture.Crawlers[0].Progress.Traversals : 0;
            ck::Trace(f"[PillarReach] stage {Stage}, traversals {Traversals}, trusted planted {_TrustedPlantedSamples}, field {_FieldSamples}, max sim excess {_MaxSimulationExcess :.2} cm, max posed excess {_MaxPresentationExcess :.2} cm",
                n"PillarReach", 0.0f);
        }
        auto Complete = _Fixture.Crawlers.Num() == 1 && _Fixture.Crawlers[0].Get_HasCompletedCourse() &&
            _Fixture.Get_HasObservedWalking();
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Fixture.Crawlers[0].Progress.Traversals > 0,
            "The tentacled body crossed the pillar field and returned rather than passing by stalling");
        Assert_True(_TrustedPlantedSamples > 100 && _FieldSamples > 20,
            "Trusted planted feet were observed while the body crossed the real Jolt pillar field");
        Assert_True(_MaxSimulationExcess <= _MaxAllowedExcess,
            f"Simulation hip never outran a trusted planted chain by more than {_MaxAllowedExcess :.1} cm; worst {_MaxSimulationExcess :.2} cm at {_WorstSimulation}");
        Assert_True(_MaxPresentationExcess <= _MaxAllowedExcess,
            f"Posed hip never outran a trusted planted chain by more than {_MaxAllowedExcess :.1} cm; worst {_MaxPresentationExcess :.2} cm at {_WorstPresentation}");
        Assert_True(_Fixture.Crawlers[0].Evidence.InvalidOutput == false,
            "The traversing gait and surface motion kept finite ready output");
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
