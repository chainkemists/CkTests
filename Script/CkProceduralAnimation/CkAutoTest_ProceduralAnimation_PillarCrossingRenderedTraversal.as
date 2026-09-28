// Language=angelscript

// Rendered thirty-FPS discriminator for the interactive Spider pillar-crossing route.
// Preserve all three roster walkers; low-progress windows retain full Spider snapshots.
class UCk_AutoTest_ProceduralAnimation_PillarCrossingRenderedTraversal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 100.0f;
    default _AutoStageOriginField = false;

    private TArray<FCkProceduralAnimationGym_Fixture> _Fixtures;
    private TArray<FString> _Names;
    private TArray<int32> _SpiderIndices;
    private TArray<FVector> _WindowPosition;
    private TArray<float> _WindowStart;
    private TArray<int32> _WindowStage;
    private TArray<int32> _WindowTraversals;
    private TArray<bool> _CandidateStall;
    private TArray<int32> _Samples;
    private float _StartTime = -1.0;
    private float _LastSummary = -5.0;
    UPROPERTY()
    private APawn _CameraPawn;
    UPROPERTY()
    private APlayerController _CameraController;
    private FTransform _OriginalPawnTransform = FTransform::Identity;
    private FRotator _OriginalControlRotation = FRotator::ZeroRotator;
    private float _OriginalFieldOfView = -1.0;
    private bool _CameraCaptured = false;
    private bool _CameraTopDown = false;
    private int32 _CapturesTaken = 0;
    private float _CaptureArmedAt = -1.0;
    private TArray<float32> _MetricsRadii;
    private int64 _LastAcceptedSequence = -1;
    private int64 _FirstAcceptedSequence = -1;
    private int32 _DistinctAcceptedSamples = 0;
    private int32 _SequenceGaps = 0;
    private int32 _SequenceRegressions = 0;
    private int32 _MetricsNotReadyPolls = 0;
    private float _FirstAcceptedTime = -1.0;
    private float _LastAcceptedTime = -1.0;
    private float _MaximumAcceptedDelta = 0.0;
    private float _NextViewEarliestAt = -1.0;
    private bool _WasBlocked = false;
    private float _BlockStartedAt = -1.0;
    private int32 _BlockedOrZeroSamples = 0;
    private int32 _BlockedStateSamples = 0;
    private int32 _ZeroPaceSamples = 0;
    private float _TotalBlockedSeconds = 0.0;
    private float _LongestBlockedSeconds = 0.0;
    private int32 _LastBlockedSwinging = 0;
    private int32 _SwingingAtLongestBlock = 0;
    private float _LongestBlockStartedAt = -1.0;
    private TArray<FString> _CurrentBlockSnapshots;
    private TArray<FString> _LongestBlockSnapshots;
    private TArray<FString> _CurrentBlockTimeline;
    private TArray<FString> _LongestBlockTimeline;
    private int32 _CurrentBlockTraceFrames = 0;


    private bool DoAdd_Fixture(FCk_Handle InOwner, FString InName, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin,
        TArray<ECkProceduralAnimationGym_Species> InRoster, int32 InSpiderIndex)
    {
        if (InRoster.Num() != 3 || InSpiderIndex < 0 || InSpiderIndex >= InRoster.Num())
        {
            return false;
        }
        if (InRoster[InSpiderIndex] != ECkProceduralAnimationGym_Species::Spider)
        {
            return false;
        }
        auto Fixture = FCkProceduralAnimationGym_Fixture();
        if (Fixture.Create_WithRoster(InOwner, InOrigin, InCourse, InRoster, true) == false)
        {
            return false;
        }
        _Fixtures.Add(Fixture);
        _Names.Add(InName);
        _SpiderIndices.Add(InSpiderIndex);
        _WindowPosition.Add(FVector::ZeroVector);
        _WindowStart.Add(-1.0);
        _WindowStage.Add(0);
        _WindowTraversals.Add(0);
        _CandidateStall.Add(false);
        _Samples.Add(0);
        return true;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _CameraPawn = Gameplay::GetPlayerPawn(0);
        _CameraController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(_CameraPawn) || ck::Is_NOT_Valid(_CameraController) ||
            ck::Is_NOT_Valid(_CameraController.PlayerCameraManager))
        {
            FinishFailure("The rendered test requires a valid pawn, controller and camera manager");
            return;
        }
        _OriginalPawnTransform = _CameraPawn.GetActorTransform();
        _OriginalControlRotation = _CameraController.GetControlRotation();
        _OriginalFieldOfView = _CameraController.PlayerCameraManager.DefaultFOV;
        _CameraCaptured = true;
        _CameraController.PlayerCameraManager.DefaultFOV = 55.0;
        System::ExecuteConsoleCommand("viewmode unlit");
        Snapshot_CVarForTest(n"r.ForceLOD");
        Snapshot_CVarForTest(n"r.SceneColorFormat");
        Snapshot_CVarForTest(n"r.PostProcessingColorFormat");
        // The base restores the exact prior cap on success and failure; do not hardcode a reset value.
        Set_CVarForTest(n"t.MaxFPS", "30");
        auto Created = DoAdd_Fixture(InHandle, "PillarCrossingRendered30", ECkProceduralAnimationGym_Course::PillarCrossing,
            FVector(120000.0, 510000.0, 600.0),
            ck_procedural_gym::Get_StressRoster(ECkProceduralAnimationGym_Course::PillarCrossing), 2);
        if (Created == false)
        {
            DoRestore_Camera();
            FinishFailure("The rendered three-walker pillar-crossing fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("observe two rendered thirty-FPS Spider traversals", n"Check_Observe", 0, 85.0f);
        Add_Step("verify two complete traversals and intact coverage", n"Step_Check");
        Add_Step("retire diagnostic fixtures", n"Step_Destroy");
        Add_Step_WaitUntil("diagnostic lifetime subtrees are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        // Normal completion restores before teardown; this also covers timeout and early-failure cleanup.
        DoRestore_Camera();
    }

    private void DoRestore_Camera()
    {
        if (_CameraCaptured == false)
        {
            return;
        }
        if (ck::IsValid(_CameraPawn))
        {
            _CameraPawn.SetActorTransform(_OriginalPawnTransform);
        }
        if (ck::IsValid(_CameraController))
        {
            _CameraController.SetControlRotation(_OriginalControlRotation);
            if (ck::IsValid(_CameraController.PlayerCameraManager))
            {
                _CameraController.PlayerCameraManager.DefaultFOV = _OriginalFieldOfView;
            }
        }
        System::ExecuteConsoleCommand("viewmode lit");
        _CameraCaptured = false;
    }

    private void DoFollow_Camera(const FCkProceduralAnimationGym_Crawler& InCrawler)
    {
        if (_CameraCaptured == false || ck::Is_NOT_Valid(_CameraPawn) || ck::Is_NOT_Valid(_CameraController))
        {
            return;
        }
        auto Target = utils_transform::Get_EntityCurrentLocation(InCrawler.Handles.Root) - FVector::UpVector * 40.0;
        // Spider is the +380cm outer lane; this oblique view looks inward from its own outer side.
        auto Eye = Target + (_CameraTopDown ? FVector(-1.0, 0.0, 650.0) : FVector(-150.0, 650.0, 180.0));
        _CameraPawn.SetActorLocation(Eye);
        _CameraController.SetControlRotation(FRotator::MakeFromX(Target - Eye));
    }

    private int32 Get_TrustedPillarPlants(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        auto Count = 0;
        auto Rows = Math::FloorToInt((ck_procedural_gym::Get_CourseHalfWidth(InCrawler.Layout.Course) -
            ck_procedural_gym::CrossingPillarHalfSize) / ck_procedural_gym::CrossingPillarPitch);
        auto Columns = Math::RoundToInt(2.0 * ck_procedural_gym::CrossingFieldHalfSpanX /
            ck_procedural_gym::CrossingPillarPitch);
        for (auto Leg : InCrawler.Handles.Legs)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            if (Foot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted ||
                Foot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted || Foot.Get_Normal().Z < 0.99)
            {
                continue;
            }
            auto Local = Foot.Get_Position() - InCrawler.Layout.Origin;
            auto Column = Math::RoundToInt((Local.X + ck_procedural_gym::CrossingFieldHalfSpanX) /
                ck_procedural_gym::CrossingPillarPitch);
            auto Row = Math::RoundToInt(Local.Y / ck_procedural_gym::CrossingPillarPitch);
            if (Column < 0 || Column > Columns || Math::Abs(Row) > Rows)
            {
                continue;
            }
            auto CenterX = -ck_procedural_gym::CrossingFieldHalfSpanX +
                ck_procedural_gym::CrossingPillarPitch * Column;
            auto CenterY = ck_procedural_gym::CrossingPillarPitch * Row;
            if (Math::Abs(Local.X - CenterX) <= ck_procedural_gym::CrossingPillarHalfSize + 1.0 &&
                Math::Abs(Local.Y - CenterY) <= ck_procedural_gym::CrossingPillarHalfSize + 1.0 &&
                Math::Abs(Local.Z - ck_procedural_gym::CrossingHeight) <= 1.0)
            {
                Count++;
            }
        }
        return Count;
    }

    private void DoCapture_PillarViews(const FCkProceduralAnimationGym_Crawler& InCrawler, float InElapsed)
    {
        if (_CapturesTaken >= 2)
        {
            return;
        }
        if (_CapturesTaken == 1 && _CameraTopDown == false)
        {
            // HighResShot is deferred. Keep the side view through duplicate same-frame polls and several render frames.
            if (InElapsed < _NextViewEarliestAt)
            {
                return;
            }
            _CameraTopDown = true;
            _CaptureArmedAt = -1.0;
        }
        auto Local = utils_transform::Get_EntityCurrentLocation(InCrawler.Handles.Root) - InCrawler.Layout.Origin;
        auto TopPlants = Get_TrustedPillarPlants(InCrawler);
        auto Eligible = InCrawler.Progress.RouteStage == 0 && Math::Abs(Local.X) <= 350.0 && TopPlants > 0;
        if (Eligible == false)
        {
            _CaptureArmedAt = -1.0;
            return;
        }
        if (_CaptureArmedAt < 0.0)
        {
            _CaptureArmedAt = InElapsed;
            return;
        }
        // Settle by elapsed time, rather than treating duplicate predicate polls as render frames.
        if (InElapsed - _CaptureArmedAt < 0.35)
        {
            return;
        }
        FString View = _CameraTopDown ? "top" : "side";
        FString Open = "{";
        FString Close = "}";
        ck::Trace(f"[PAVIZ-SHOT] {Open}\"index\":{_CapturesTaken},\"plan\":{_CapturesTaken},\"course\":\"PillarCrossing\",\"species\":\"Spider\",\"walker\":2,\"phase\":\"actual-pillar-tops\",\"view\":\"{View}\",\"x\":{Local.X :.1},\"z\":{Local.Z :.1},\"t\":{InElapsed :.3},\"fov\":55.0{Close}", n"PAVIZ.Shot", 0.0f);
        ck::Trace(f"[PILLAR-RENDER-CONTACT] view {View} t {InElapsed :.6} trustedGridTopPlants {TopPlants}");
        DoDump_Spider(0, InElapsed, f"capture-{View}");
        System::ExecuteConsoleCommand("HighResShot 1280x720");
        _CapturesTaken++;
        _CaptureArmedAt = -1.0;
        _NextViewEarliestAt = InElapsed + 0.1;
        // Keep the captured view unchanged here; the next view is chosen only after the deferred-capture hold.
    }

    private void DoMeasure_Cadence(const FCkProceduralAnimationGym_Crawler& InCrawler, float InElapsed)
    {
        if (_MetricsRadii.IsEmpty())
        {
            for (auto Leg : InCrawler.Handles.Legs)
            {
                auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
                for (auto Length : Lengths)
                {
                    // Geometry is irrelevant to cadence; zero radii still require a fresh, complete published rig sample.
                    _MetricsRadii.Add(0.0);
                }
            }
        }
        auto Metrics = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationRigMetrics(InCrawler.Handles.Root, _MetricsRadii);
        if (Metrics.Get_Ready() == false)
        {
            _MetricsNotReadyPolls++;
            return;
        }
        auto Sequence = Metrics.Get_SampleSequence();
        if (Sequence == _LastAcceptedSequence)
        {
            return;
        }
        if (_LastAcceptedSequence >= 0 && Sequence < _LastAcceptedSequence)
        {
            _SequenceRegressions++;
            return;
        }
        DoMeasure_Blockage(InCrawler, InElapsed);
        if (_DistinctAcceptedSamples == 0)
        {
            _FirstAcceptedSequence = Sequence;
            _FirstAcceptedTime = InElapsed;
        }
        else
        {
            _SequenceGaps += int32(Sequence - _LastAcceptedSequence - 1);
            _MaximumAcceptedDelta = Math::Max(_MaximumAcceptedDelta, InElapsed - _LastAcceptedTime);
        }
        _LastAcceptedSequence = Sequence;
        _LastAcceptedTime = InElapsed;
        _DistinctAcceptedSamples++;
    }

    private void DoMeasure_Blockage(const FCkProceduralAnimationGym_Crawler& InCrawler, float InElapsed)
    {
        auto PaceState = utils_surface_motion::Get_ReachPaceState(InCrawler.Handles.Motion);
        auto PaceScale = utils_surface_motion::Get_ReachPaceScale(InCrawler.Handles.Motion);
        auto StateBlocked = PaceState == ECk_SurfaceMotion_ReachPaceState::Blocked;
        auto ZeroPace = PaceScale <= 0.0;
        auto Blocked = StateBlocked || ZeroPace;
        auto Swinging = 0;
        for (auto Leg : InCrawler.Handles.Legs)
        {
            if (utils_procedural_leg::Get_Foot(Leg).Get_Phase() == ECk_ProceduralLeg_FootPhase::Swinging)
            {
                Swinging++;
            }
        }
        // Read-only diagnostic transcript: at most 64 accepted blocked frames plus the recovery frame, all eight legs.
        // The existing acceptance/cadence gate calls this once per solve. No fixture, steering or gameplay state changes.
        if (Blocked && _WasBlocked == false)
        {
            _CurrentBlockTimeline.Empty();
            _CurrentBlockTraceFrames = 0;
        }
        if ((Blocked || _WasBlocked) && (_CurrentBlockTraceFrames < 64 || Blocked == false))
        {
            auto Kind = Blocked ? "blocked" : "recovered";
            for (auto Leg : InCrawler.Handles.Legs)
            {
                auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                    InCrawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), InCrawler.Layout.Origin);
                _CurrentBlockTimeline.Add(f"[PILLAR-RENDER-BLOCK-FRAME] t {InElapsed :.6} kind {Kind} pace {PaceScale :.6} swinging {Swinging} {Snapshot}");
            }
            _CurrentBlockTraceFrames++;
        }
        if (_WasBlocked && _LastAcceptedTime >= 0.0)
        {
            // Attribute each accepted-sample interval to its starting state; report this sampling boundary explicitly.
            _TotalBlockedSeconds += InElapsed - _LastAcceptedTime;
            auto Duration = InElapsed - _BlockStartedAt;
            if (Duration > _LongestBlockedSeconds)
            {
                _LongestBlockedSeconds = Duration;
                _SwingingAtLongestBlock = Blocked ? Swinging : _LastBlockedSwinging;
                _LongestBlockStartedAt = _BlockStartedAt;
                _LongestBlockSnapshots = _CurrentBlockSnapshots;
                _LongestBlockTimeline = _CurrentBlockTimeline;
            }
        }
        if (Blocked)
        {
            _BlockedOrZeroSamples++;
            if (StateBlocked)
            {
                _BlockedStateSamples++;
            }
            if (ZeroPace)
            {
                _ZeroPaceSamples++;
            }
            if (_WasBlocked == false)
            {
                _BlockStartedAt = InElapsed;
                _CurrentBlockSnapshots.Empty();
                // Preserve the actual onset for the longest observed episode rather than dumping an unrelated end-of-test pose.
                for (auto Leg : InCrawler.Handles.Legs)
                {
                    _CurrentBlockSnapshots.Add(UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                        InCrawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), InCrawler.Layout.Origin));
                }
            }
            _LastBlockedSwinging = Swinging;
        }
        _WasBlocked = Blocked;
    }

    private void DoReport_Blockage()
    {
        ck::Trace(f"[PILLAR-RENDER-BLOCKAGE] acceptedBlockedOrZeroSamples {_BlockedOrZeroSamples} stateBlockedSamples {_BlockedStateSamples} zeroPaceSamples {_ZeroPaceSamples} totalIntervalSeconds {_TotalBlockedSeconds :.6} longestIntervalSeconds {_LongestBlockedSeconds :.6} longestOnset {_LongestBlockStartedAt :.6} swingingAtLongest {_SwingingAtLongestBlock} ongoing {_WasBlocked}");
        if (_LongestBlockedSeconds > 0.0)
        {
            for (auto Snapshot : _LongestBlockSnapshots)
            {
                ck::Trace(f"[PILLAR-RENDER-BLOCK-WITNESS] capturedOnset {_LongestBlockStartedAt :.6} longestInterval {_LongestBlockedSeconds :.6} {Snapshot}");
            }
            ck::Trace(f"[PILLAR-RENDER-BLOCK-TRANSCRIPT] onset {_LongestBlockStartedAt :.6} duration {_LongestBlockedSeconds :.6} rows {_LongestBlockTimeline.Num()} cap 64 blocked frames plus recovery");
            for (auto Frame : _LongestBlockTimeline)
            {
                ck::Trace(Frame);
            }
        }
    }

    private void DoReport_Cadence(float InElapsed)
    {
        auto Span = _LastAcceptedTime - _FirstAcceptedTime;
        auto AcceptedHz = Span > 0.0 ? (_DistinctAcceptedSamples - 1) / Span : 0.0;
        ck::Trace(f"[PILLAR-RENDER-CADENCE] t {InElapsed :.6} acceptedHz {AcceptedHz :.6} uniqueSamples {_DistinctAcceptedSamples} firstSeq {_FirstAcceptedSequence} lastSeq {_LastAcceptedSequence} skippedSequences {_SequenceGaps} notReadyPolls {_MetricsNotReadyPolls} maxAcceptedDelta {_MaximumAcceptedDelta :.6}");
    }

    private void DoDump_Spider(int32 InIndex, float InElapsed, FString InEvent)
    {
        auto Crawler = _Fixtures[InIndex].Crawlers[_SpiderIndices[InIndex]];
        for (auto Leg : Crawler.Handles.Legs)
        {
            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                Crawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), Crawler.Layout.Origin);
            ck::Trace(f"[SPIDER-PILLAR-30] course {_Names[InIndex]} walker {_SpiderIndices[InIndex]} lane {Crawler.Layout.LaneY :.1} t {InElapsed :.6} event {InEvent} stage {Crawler.Progress.RouteStage} traversals {Crawler.Progress.Traversals} {Snapshot}");
        }
    }

    UFUNCTION()
    private void Check_Observe(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Update();
            if (_Fixtures[Index].CompositionError.IsEmpty() == false)
            {
                DoRestore_Camera();
                FinishFailure(_Fixtures[Index].CompositionError);
                return;
            }
            Ready = Ready && _Fixtures[Index].Get_AllReady();
        }
        if (Ready == false)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartTime < 0.0)
        {
            _StartTime = Now;
        }
        auto Elapsed = Now - _StartTime;
        auto Summary = Elapsed - _LastSummary >= 5.0;
        auto TrackedCrawler = _Fixtures[0].Crawlers[_SpiderIndices[0]];
        DoFollow_Camera(TrackedCrawler);
        DoCapture_PillarViews(TrackedCrawler, Elapsed);
        DoMeasure_Cadence(TrackedCrawler, Elapsed);
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            auto Crawler = _Fixtures[Index].Crawlers[_SpiderIndices[Index]];
            auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
            auto Local = Body.GetLocation() - Crawler.Layout.Origin;
            auto Stage = Crawler.Progress.RouteStage;
            auto Traversals = Crawler.Progress.Traversals;
            auto ChangedRoute = Stage != _WindowStage[Index] || Traversals != _WindowTraversals[Index];
            if (_WindowStart[Index] < 0.0 || ChangedRoute)
            {
                if (_CandidateStall[Index])
                {
                    DoDump_Spider(Index, Elapsed, "route-recovered");
                    _CandidateStall[Index] = false;
                }
                _WindowStart[Index] = Elapsed;
                _WindowPosition[Index] = Local;
                _WindowStage[Index] = Stage;
                _WindowTraversals[Index] = Traversals;
            }
            if (Elapsed - _WindowStart[Index] >= 2.0)
            {
                // This course patrols X. Lateral jitter and vertical motion cannot hide absent longitudinal progress.
                auto SignedProgress = (Local.X - _WindowPosition[Index].X) * (Stage == 0 ? 1.0 : -1.0);
                auto Candidate = SignedProgress < 2.0;
                auto Delta3D = (Local - _WindowPosition[Index]).Size();
                if (Candidate && _CandidateStall[Index] == false)
                {
                    ck::Trace(f"[SPIDER-PILLAR-30-WINDOW] course {_Names[Index]} walker {_SpiderIndices[Index]} lane {Crawler.Layout.LaneY :.1} t {Elapsed :.6} signedX {SignedProgress :.6} delta3D {Delta3D :.6} stage {Stage} traversals {Traversals}");
                    DoDump_Spider(Index, Elapsed, "onset");
                }
                else if (Candidate == false && _CandidateStall[Index])
                {
                    DoDump_Spider(Index, Elapsed, "progress-recovered");
                }
                _CandidateStall[Index] = Candidate;
                _WindowStart[Index] = Elapsed;
                _WindowPosition[Index] = Local;
            }
            _Samples[Index]++;
            if (Summary)
            {
                auto PaceScale = utils_surface_motion::Get_ReachPaceScale(Crawler.Handles.Motion);
                auto PaceState = int32(utils_surface_motion::Get_ReachPaceState(Crawler.Handles.Motion));
                auto Swinging = 0;
                auto TrustedPlants = 0;
                for (auto Leg : Crawler.Handles.Legs)
                {
                    auto Foot = utils_procedural_leg::Get_Foot(Leg);
                    if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Swinging)
                    {
                        Swinging++;
                    }
                    else if (Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted)
                    {
                        TrustedPlants++;
                    }
                }
                ck::Trace(f"[SPIDER-PILLAR-30-SUMMARY] course {_Names[Index]} walker {_SpiderIndices[Index]} lane {Crawler.Layout.LaneY :.1} t {Elapsed :.6} body ({Local.X :.6},{Local.Y :.6},{Local.Z :.6}) stage {Stage} traversals {Traversals} pace {PaceScale :.6}/{PaceState} swinging {Swinging} trustedPlants {TrustedPlants} candidate {_CandidateStall[Index]} invalid {Crawler.Evidence.InvalidOutput}");
            }
        }
        if (Summary)
        {
            DoReport_Cadence(Elapsed);
            _LastSummary = Elapsed;
        }
        auto Result = OutResult;
        Result.Set(Elapsed >= 60.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoReport_Cadence(60.0);
        DoReport_Blockage();
        Assert_Equals_Int(_CapturesTaken, 2, "Both outer-side and top pillar-contact views were captured");
        Assert_True(_DistinctAcceptedSamples > 100 && _SequenceRegressions == 0,
            f"Accepted animation cadence was measured from unique fresh samples ({_DistinctAcceptedSamples} samples)");
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            auto Crawler = _Fixtures[Index].Crawlers[_SpiderIndices[Index]];
            Assert_True(_Samples[Index] > 100 && Crawler.Evidence.InvalidOutput == false,
                f"{_Names[Index]} produced finite intact route observations ({_Samples[Index]})");
            auto Enabled = 0;
            for (auto Leg : Crawler.Handles.Legs)
            {
                if (utils_procedural_leg::Get_EnableDisable(Leg) == ECk_EnableDisable::Enable)
                {
                    Enabled++;
                }
            }
            Assert_True(Enabled == 8, f"{_Names[Index]} retained all eight authored legs");
            auto Local = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root) - Crawler.Layout.Origin;
            auto Traversals = Crawler.Progress.Traversals;
            ck::Trace(f"[SPIDER-PILLAR-30-RESULT] course {_Names[Index]} walker {_SpiderIndices[Index]} lane {Crawler.Layout.LaneY :.1} samples {_Samples[Index]} traversals {Traversals} body ({Local.X :.3},{Local.Y :.3},{Local.Z :.3}) stage {Crawler.Progress.RouteStage} candidate {_CandidateStall[Index]}");
            auto Completed = Traversals >= 2 && Crawler.Get_HasCompletedCourse();
            if (Completed == false)
            {
                DoDump_Spider(Index, 60.0, "liveness-failure");
            }
            Assert_True(Completed,
                f"{_Names[Index]} completed two route traversals with every leg replanted ({Traversals} traversals, {Crawler.Get_ReplantedCount()}/8 legs)");
            if (_CandidateStall[Index])
            {
                DoDump_Spider(Index, 60.0, "still-candidate-at-end");
            }
        }
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoRestore_Camera();
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Request_Destroy();
        }
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Destroyed = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            Destroyed = Destroyed && _Fixtures[Index].Get_IsDestroyed();
        }
        auto Result = OutResult;
        Result.Set(Destroyed);
    }
}