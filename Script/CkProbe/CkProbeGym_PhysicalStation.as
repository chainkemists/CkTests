//============================================================================
// PROBE GYM - PHYSICAL STATION
//
// Visual demo of raw Probe overlap: a visible box detector volume with three
// balls staggered-kicked on yoyo tweens that pass through it from different
// spokes. Each ball carries a Kinematic Sphere probe named after the Marker
// tag which the station's Static Box probe's Filter matches.
//
// Desync diagnostic (catches stuck-Jolt-body bugs): per ball, compare
// "is the ball's center geometrically inside the detector AABB?" (AS math)
// against "does the detector report overlap with this ball?" (probe query).
// Disagreement -> YELLOW ball. Brief boundary flicker is OK; persistent
// yellow == stuck Jolt body.
//
// Pawn also carries the same Marker probe - walk through and you'll register
// as the 4th entity.
//============================================================================

class UCk_EntityScript_ProbeGym_PhysicalStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Probe ProbeHandle;
    TArray<FCk_Handle> Balls;
    TArray<FCk_Handle_Tween> BallTweens;

    FVector StationWorldLocation;
    FVector ProbeHalfExtents = FVector(200.0f, 200.0f, 100.0f);
    float32 BallRadius = 40.0f;
    float32 BallAmplitude = 300.0f;

    int32 BallCount = 3;
    float32 BallTweenDuration = 3.0f;

    int32 NextBallToStart = 0;

    FString LastEventLine = "(none)";
    int32 EnterSignalCount = 0;
    int32 ExitSignalCount = 0;

    int32 DesyncCount = 0;

    // Persistent debug shapes - created once with infinite lifetime.
    // Detector box position is fixed; only respawned on color change.
    // Each ball has its own persistent sphere whose position is updated each
    // frame via Request_SetLocation, and is only destroyed + respawned when
    // its (color-encoded) state actually changes (basic-shape PMG has no
    // recolor request).
    FCk_Handle_Pmg_DebugShape DetectorShape;
    FLinearColor DetectorColorCached;
    TArray<FCk_Handle_Pmg_DebugShape> BallShapes;
    TArray<FLinearColor> BallColorsCached;

    FLinearColor DetectorColor_Empty = FLinearColor(0.2f, 0.4f, 1.0f, 0.15f);
    FLinearColor DetectorColor_Occupied = FLinearColor(1.0f, 0.2f, 0.2f, 0.15f);
    FLinearColor BallColor_Outside = FLinearColor(0.4f, 1.0f, 0.4f, 1.0f);
    FLinearColor BallColor_Inside = FLinearColor(1.0f, 0.4f, 0.7f, 1.0f);
    FLinearColor BallColor_Desync = FLinearColor(1.0f, 1.0f, 0.0f, 1.0f);

    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    FCkGym_AutoConfig AutoConfig;

    //------------------------------------------------------------------------
    // Construction
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        InHandle.Set_DebugName(n"PhysicalStation");
        auto TransformHandle = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_ProbeGym_PhysicalStation");
        StationWorldLocation = InitialTransform.Translation;

        // Detector: Static Box probe, Filter matches the Marker ProbeName the
        // balls and pawn carry.
        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Detector"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        ProbeParams.Set_Filter(Filter);

        auto DebugInfo = FCk_Probe_DebugInfo();
        ProbeHandle = utils_probe::Add_Box(TransformHandle, ProbeHalfExtents, ProbeParams, DebugInfo);

        // Spawn balls, each lifetime-owned by the station. Request_OverrideToSelf
        // is critical: default ContextOverlapPolicy = DifferentContextOnly so
        // without it the balls (child context = station) would be suppressed
        // from overlapping the station's own probe.
        auto BallDebugInfo = FCk_Probe_DebugInfo();

        for (int32 i = 0; i < BallCount; ++i)
        {
            auto Direction = GetBallAxisDirection(i);
            auto BallStart = StationWorldLocation - Direction * BallAmplitude;
            auto BallInitialTransform = FTransform(FRotator::ZeroRotator, BallStart);

            auto BallEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
            auto BallName = FName(f"Ball_{i}");
            BallEntity.Set_DebugName(BallName);
            BallEntity.Request_OverrideToSelf();

            auto BallTransformHandle = utils_transform::Add(
                BallEntity, BallInitialTransform, ECk_Replication::DoesNotReplicate);

            auto BallProbeParams = FCk_Fragment_Probe_ParamsData(
                utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
            BallProbeParams.Set_MotionType(ECk_MotionType::Kinematic);
            BallProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
            utils_probe::Add_Sphere(BallTransformHandle, BallRadius, BallProbeParams, BallDebugInfo);

            Balls.Add(BallEntity);
        }

        // Per-frame tick for visuals + display.
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description =
            "Walk pawn through the blue box,\n" +
            "or watch the balls tween through it.\n" +
            "YELLOW ball = visual vs probe state\n" +
            "mismatch. Brief flicker at boundaries\n" +
            "is expected; persistent yellow ==\n" +
            "stuck Jolt body bug.";
        AutoConfig.GlobalAutoCommand = "panel [G] auto on / [B] auto off";
        AutoConfig.PerStationAutoCommand = "panel [I] Physical station only";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Auto=ON resumes tweens; Auto=OFF pauses", 0, 0));
        AutoConfig.ManualCommands.Add("Walk pawn through box");
        AutoConfig.ManualCommands.Add("panel [G] / [B] resumes / pauses the balls");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_probe::BindTo_OnBeginOverlap(ProbeHandle,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnProbeBeginOverlap"));
        utils_probe::BindTo_OnEndOverlap(ProbeHandle,
            FCk_Delegate_Probe_OnEndOverlap(this, n"OnProbeEndOverlap"));

        // No BallInitialDelay gate - kick off immediately. The previous Probe
        // Setup FTag_Transform_Updated exclusion is being removed feature-side
        // (see BusterBlock commit b4c6ed72d), so there's no need to wait
        // before any ball's transform starts moving.
        StartNextBallTween();

        SpawnPersistentShapes();
    }

    private void SpawnPersistentShapes()
    {
        DetectorColorCached = DetectorColor_Empty;
        DetectorShape = utils_pmg_basic_shapes::DrawFilledBox(
            StationWorldLocation, ProbeHalfExtents, DetectorColorCached,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        for (int32 i = 0; i < Balls.Num(); ++i)
        {
            auto Ball = Balls[i];
            auto BallLoc = ck::IsValid(Ball)
                ? utils_transform::Get_EntityCurrentLocation(Ball)
                : StationWorldLocation;

            BallColorsCached.Add(BallColor_Outside);
            BallShapes.Add(utils_pmg_basic_shapes::DrawFilledSphere(
                BallLoc, BallRadius, 16, 16, BallColor_Outside,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f));
        }
    }

    private bool ColorIsDifferent(FLinearColor InA, FLinearColor InB)
    {
        return InA.R != InB.R || InA.G != InB.G || InA.B != InB.B || InA.A != InB.A;
    }

    //------------------------------------------------------------------------
    // Staggered tween kickoff
    //------------------------------------------------------------------------

    UFUNCTION()
    private void StartNextBallTween()
    {
        if (NextBallToStart >= Balls.Num())
        { return; }

        auto Ball = Balls[NextBallToStart];
        if (ck::IsValid(Ball))
        {
            auto BallTransform = Ball.As_Transform();
            auto Direction = GetBallAxisDirection(NextBallToStart);
            auto EndLocation = StationWorldLocation + Direction * BallAmplitude;

            auto NewTween = utils_tween::Create_TweenEntityLocation(
                BallTransform, EndLocation, BallTweenDuration,
                ECk_TweenEasing::InOutSine,
                ECk_TweenLoopType::Yoyo,
                -1,
                0.0f);

            if (!AutoRunning)
            { utils_tween::Pause(NewTween); }

            BallTweens.Add(NewTween);
        }

        NextBallToStart++;

        if (NextBallToStart < Balls.Num())
        {
            auto StaggerInterval = BallTweenDuration * 2.0f / float(BallCount);
            System::SetTimer(this, n"StartNextBallTween", StaggerInterval, false);
        }
    }

    //------------------------------------------------------------------------
    // Probe signal handlers
    //------------------------------------------------------------------------

    UFUNCTION()
    void OnProbeBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        EnterSignalCount++;
        auto Other = InPayload.Get_OtherEntity();
        LastEventLine = f"ENTER: {Other.ToString()}";
    }

    UFUNCTION()
    void OnProbeEndOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InPayload)
    {
        ExitSignalCount++;
        auto Other = InPayload.Get_OtherEntity();
        LastEventLine = f"EXIT:  {Other.ToString()}";
    }

    //------------------------------------------------------------------------
    // Auto
    //------------------------------------------------------------------------

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);

        for (int32 i = 0; i < BallTweens.Num(); ++i)
        {
            auto TweenHandle = BallTweens[i];
            if (ck::Is_NOT_Valid(TweenHandle))
            { continue; }

            if (AutoRunning)
            { utils_tween::Resume(TweenHandle); }
            else
            { utils_tween::Pause(TweenHandle); }
        }
    }

    //------------------------------------------------------------------------
    // Per-frame
    //------------------------------------------------------------------------

    UFUNCTION()
    private void FrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DrawVisuals();
        DisplayCurrentValues();
    }

    void DrawVisuals()
    {
        // Skip until DoBeginPlay has spawned the persistent shapes.
        if (ck::Is_NOT_Valid(DetectorShape))
        { return; }

        auto CurrentOverlaps = utils_probe::Get_CurrentOverlaps(ProbeHandle);
        auto ProbeOccupied = CurrentOverlaps.Num() > 0;
        auto BoxColor = ProbeOccupied ? DetectorColor_Occupied : DetectorColor_Empty;

        if (ColorIsDifferent(BoxColor, DetectorColorCached))
        {
            utils_entity_lifetime::Request_DestroyEntity(DetectorShape);
            DetectorColorCached = BoxColor;
            DetectorShape = utils_pmg_basic_shapes::DrawFilledBox(
                StationWorldLocation, ProbeHalfExtents, DetectorColorCached,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        }

        auto LocalDesyncCount = 0;
        auto BallShapeCount = BallShapes.Num();

        for (int32 i = 0; i < BallShapeCount; ++i)
        {
            auto Ball = Balls[i];
            if (ck::Is_NOT_Valid(Ball))
            { continue; }

            auto BallLoc = utils_transform::Get_EntityCurrentLocation(Ball);
            auto VisuallyInside = IsInsideAabb(BallLoc);
            auto ProbeKnowsInside = utils_probe::Get_IsOverlappingWith(ProbeHandle, Ball);

            FLinearColor BallColor;
            if (VisuallyInside != ProbeKnowsInside)
            {
                BallColor = BallColor_Desync;
                LocalDesyncCount++;
            }
            else if (VisuallyInside)
            {
                BallColor = BallColor_Inside;
            }
            else
            {
                BallColor = BallColor_Outside;
            }

            if (ColorIsDifferent(BallColor, BallColorsCached[i]))
            {
                utils_entity_lifetime::Request_DestroyEntity(BallShapes[i]);
                BallColorsCached[i] = BallColor;
                BallShapes[i] = utils_pmg_basic_shapes::DrawFilledSphere(
                    BallLoc, BallRadius, 16, 16, BallColor,
                    true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
            }
            else
            {
                utils_transform::Request_SetLocation(BallShapes[i], BallLoc, ECk_LocalWorld::World);
            }
        }

        DesyncCount = LocalDesyncCount;
    }

    bool IsInsideAabb(FVector InLocation)
    {
        auto Delta = InLocation - StationWorldLocation;
        return Math::Abs(Delta.X) <= ProbeHalfExtents.X
            && Math::Abs(Delta.Y) <= ProbeHalfExtents.Y
            && Math::Abs(Delta.Z) <= ProbeHalfExtents.Z;
    }

    // Math::PI not exposed - hardcode 2pi.
    FVector GetBallAxisDirection(int32 InBallIndex)
    {
        auto Angle = 6.28318530718f * float(InBallIndex) / float(BallCount);
        return FVector(Math::Cos(Angle), Math::Sin(Angle), 0.0f);
    }

    //------------------------------------------------------------------------
    // Display
    //------------------------------------------------------------------------

    void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto TitleText = f"PROBE PHYSICAL x{BallCount} ({NetworkRole})";

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = DisplayText + "===== Probe State =====\n";

        auto Count = utils_probe::Get_CurrentOverlaps(ProbeHandle).Num();
        auto StateLabel = Count > 0 ? FString("INSIDE") : FString("OUTSIDE");

        DisplayText = f"{DisplayText}Current overlaps: {Count}\n";
        DisplayText = f"{DisplayText}State: {StateLabel}\n";

        DisplayText = DisplayText + "\n";
        DisplayText = f"{DisplayText}Signals: enter={EnterSignalCount} exit={ExitSignalCount}\n";
        DisplayText = f"{DisplayText}Last event: {LastEventLine}\n";

        DisplayText = DisplayText + "\n";
        DisplayText = DisplayText + "===== Desync Diagnostic =====\n";
        if (BallCount > 1)
        {
            auto Cadence = BallTweenDuration * 2.0f / float(BallCount);
            DisplayText = f"{DisplayText}Active balls: {BallTweens.Num()} / {Balls.Num()} (stagger {Cadence}s)\n";
        }
        else
        {
            DisplayText = f"{DisplayText}Active balls: {BallTweens.Num()} / {Balls.Num()}\n";
        }
        DisplayText = f"{DisplayText}Desynced balls: {DesyncCount} / {BallTweens.Num()}\n";
        if (DesyncCount > 0)
        {
            DisplayText = DisplayText + "YELLOW = AABB vs probe mismatch.\n";
            DisplayText = DisplayText + "Boundary flicker is OK;\n";
            DisplayText = DisplayText + "persistent yellow == stuck Jolt body.\n";
        }

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(TitleText);
        Fragment.Description = FText::FromString(DisplayText);
    }
}

//============================================================================
// PROBE GYM - PHYSICAL STATION (SINGLE-BALL VARIANT)
//
// Thin subclass of the multi-ball physical station with BallCount=1 so the
// simplest case (one entity passes through the detector) is isolated from
// the multi-entity stress scenario. Mirrors BB_TriggerGym's _Single pattern.
//============================================================================

class UCk_EntityScript_ProbeGym_PhysicalStation_Single : UCk_EntityScript_ProbeGym_PhysicalStation
{
    default BallCount = 1;
}

