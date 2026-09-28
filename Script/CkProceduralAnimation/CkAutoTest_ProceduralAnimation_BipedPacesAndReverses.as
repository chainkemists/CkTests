// Language=angelscript

// Real Jolt walking must let a two-leg gait wait for a stance, then resume through a full reversal.
class UCk_AutoTest_ProceduralAnimation_BipedPacesAndReverses : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 100.0f;
    default _AutoStageOriginField = false;

    private FCkProceduralAnimationGym_Fixture _Fixture;
    private float _MinPaceScale = 1.0;
    private float _MaxSimulationExcess = 0.0;
    private float _MaxPosedExcess = 0.0;
    private float _MaxX = -100000.0;
    private float _MinXAfterTurn = 100000.0;
    private int32 _TrustedPlantedSamples = 0;
    private int32 _PacedSamples = 0;
    private bool _SawReverse = false;
    private FString _WorstSimulation = "none";
    private FString _WorstPosed = "none";
    private float _LastTraceAt = -1.0;
    private int32 _ApplyCompletions = 0;
    private ECk_Request_OperationResult _ApplyResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Biped);
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 335000.0, 600.0),
            ECkProceduralAnimationGym_Course::Flat, Roster, false) == false)
        {
            FinishFailure("The isolated real-Jolt biped course could not be created");
            return;
        }
        Add_Step_WaitUntil("the biped is ready on the real Jolt floor", n"Check_Ready", 0, 10.0f);
        Add_Step("apply a slow, one-swing biped gait that requires stance pacing", n"Step_ApplyPacingPreset");
        Add_Step_WaitUntil("the pacing stress preset is accepted", n"Check_PresetApplied", 0, 10.0f);
        Add_Step_WaitUntil("the biped walks forward, reverses, and returns", n"Check_Traversal", 0, 80.0f);
        Add_Step("verify reach pacing, replants, and bounded chains", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AllReady());
    }

    UFUNCTION()
    private void Step_ApplyPacingPreset(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        UCk_ProceduralGait_Data BipedPreset = ck::ProceduralGym_GaitBiped;
        auto Timing = BipedPreset.Get_Timing();
        // One 1.5 s swing at 180 cm/s asks 270 cm of body travel while the other foot holds.
        // The 150 cm chain with a 90 cm rest drop has at most 240 cm of total horizontal span.
        Timing.Set_CycleDuration(FCk_Time(2.2));
        Timing.Set_StepDuration(FCk_Time(1.5));
        Timing.Set_MaxCadenceScale(1.0f);
        Timing.Set_MaxSimultaneousSwings(1);
        utils_procedural_gait::Request_ApplyPreset(_Fixture.Crawlers[0].Handles.Gait,
            FCk_Request_ProceduralGait_ApplyPreset(Timing, BipedPreset.Get_Step(), BipedPreset.Get_Probe(),
                BipedPreset.Get_Foothold()),
            FCk_Delegate_Request_OnCompleted(this, n"OnPresetApplied"));
    }

    UFUNCTION()
    private void OnPresetApplied(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ApplyCompletions++;
        _ApplyResult = InResult;
    }

    UFUNCTION()
    private void Check_PresetApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_ApplyCompletions > 0 && _ApplyResult != ECk_Request_OperationResult::Succeeded)
        {
            FinishFailure("The valid biped pacing stress preset was rejected");
            return;
        }
        auto Result = OutResult;
        Result.Set(_ApplyCompletions == 1 && _ApplyResult == ECk_Request_OperationResult::Succeeded);
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
        auto LocalX = Body.GetLocation().X - Crawler.Layout.Origin.X;
        _MaxX = Math::Max(_MaxX, LocalX);
        if (Crawler.Progress.RouteStage == 1)
        {
            _SawReverse = true;
        }
        if (_SawReverse)
        {
            _MinXAfterTurn = Math::Min(_MinXAfterTurn, LocalX);
        }
        auto Pace = utils_surface_motion::Get_ReachPaceScale(Crawler.Handles.Motion);
        auto PaceState = utils_surface_motion::Get_ReachPaceState(Crawler.Handles.Motion);
        if (Pace < 0.99 &&
            (PaceState == ECk_SurfaceMotion_ReachPaceState::Pacing ||
                PaceState == ECk_SurfaceMotion_ReachPaceState::Blocked))
        {
            _PacedSamples++;
            _MinPaceScale = Math::Min(_MinPaceScale, Pace);
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
            auto Reach = 0.0;
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            for (auto Length : Lengths)
            {
                Reach += Length;
            }
            if (Reach <= 0.0)
            {
                continue;
            }
            auto HipLocal = utils_procedural_leg::Get_Placement(Leg).Get_HipLocal();
            auto SimulationExcess = (Foot.Get_Position() - Body.TransformPosition(HipLocal)).Size() - Reach;
            auto PosedExcess = (Foot.Get_Position() - Posed.TransformPosition(HipLocal)).Size() - Reach;
            _TrustedPlantedSamples++;
            if (SimulationExcess > _MaxSimulationExcess)
            {
                _WorstSimulation = f"{utils_procedural_leg::Get_Id(Leg)} at x {LocalX :.1}";
            }
            if (PosedExcess > _MaxPosedExcess)
            {
                _WorstPosed = f"{utils_procedural_leg::Get_Id(Leg)} at x {LocalX :.1}";
            }
            _MaxSimulationExcess = Math::Max(_MaxSimulationExcess, SimulationExcess);
            _MaxPosedExcess = Math::Max(_MaxPosedExcess, PosedExcess);
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
        if (_LastTraceAt < 0.0 || Now - _LastTraceAt >= 5.0)
        {
            _LastTraceAt = Now;
            auto Stage = _Fixture.Crawlers.Num() == 1 ? _Fixture.Crawlers[0].Progress.RouteStage : -1;
            ck::Trace(f"[BipedPace] stage {Stage}, x {_MaxX :.1} to {_MinXAfterTurn :.1}, paced {_PacedSamples}, min scale {_MinPaceScale :.3}, planted {_TrustedPlantedSamples}, sim excess {_MaxSimulationExcess :.2}, posed excess {_MaxPosedExcess :.2}",
                n"BipedPace", 0.0f);
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
        Assert_True(_SawReverse && Crawler.Progress.Traversals > 0 &&
            _MaxX > ck_procedural_gym::TurnaroundX && _MinXAfterTurn < -ck_procedural_gym::TurnaroundX,
            f"The biped advanced through the turn and returned (x {_MaxX :.1} to {_MinXAfterTurn :.1})");
        Assert_Equals_Int(Crawler.Get_ReplantedCount(), 2, "Both biped legs replanted on trusted contact");
        Assert_True(_TrustedPlantedSamples > 100, "The real-Jolt traversal sampled trusted planted biped feet");
        Assert_True(_PacedSamples > 0 && _MinPaceScale < 0.99,
            f"The stance constraint reduced voluntary speed before releasing it ({_PacedSamples} samples, min {_MinPaceScale :.3})");
        Assert_Equals_Int(_ApplyCompletions, 1, "The test-local valid biped pacing preset completed exactly once");
        Assert_True(_MaxSimulationExcess <= 0.5,
            f"The simulation hip stayed within trusted planted chain reach (worst {_MaxSimulationExcess :.2} cm, {_WorstSimulation})");
        Assert_True(_MaxPosedExcess <= 0.5,
            f"The posed hip stayed within trusted planted chain reach (worst {_MaxPosedExcess :.2} cm, {_WorstPosed})");
        Assert_True(Crawler.Evidence.InvalidOutput == false, "Pacing and reversal kept finite ready output");
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
