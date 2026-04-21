//============================================================================
// PROBE GYM — NESTED SCENE-NODE STATION
//
// Stress-tests transform composition when a Kinematic Probe is attached at
// the end of a nested scene-node chain. Catches bugs where:
//   (a) The probe stays stuck at the root's raw world position
//   (b) Rotations don't compose through the chain (only the last link's
//       rotation or only the first link's rotation is applied)
//   (c) Jolt body desyncs from the ECS-composed world transform
//
// Hierarchy built in DoConstruct:
//   Root            — own entity, tweened along +Y axis
//    └─ SceneNodeA  — +150 along X, 45° yaw (Z rotation)
//         └─ SceneNodeB — +100 along Y (in A's frame), 30° roll (X rotation)
//              └─ ChainedProbe — Kinematic Sphere, ProbeName = Marker
//
// Static Detector (Box, Filter=Marker) placed so the chained probe crosses
// it twice per yoyo period. Detector overlap count is the ground truth.
//
// Display compares AS-composed expected position against ECS-reported
// position. If the transform processor works, these match. If Jolt body
// is stuck, position is still correct but Detector hits won't fire on
// schedule (the "persistent desync, zero hits" symptom).
//============================================================================

class UCk_EntityScript_ProbeGym_NestedSceneNodeStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    // Entities
    FCk_Handle RootEntity;
    FCk_Handle_Transform RootTransformHandle;
    FCk_Handle_SceneNode NodeA;
    FCk_Handle_SceneNode NodeB;
    FCk_Handle_Probe ChainedProbe;

    FCk_Handle DetectorEntity;
    FCk_Handle_Probe DetectorProbe;

    // Chain geometry (all in world-axis since Root has identity rotation)
    FVector StationWorldLocation;
    FVector RootStartWorldLocation;
    FVector OffsetA_Local = FVector(150.0f, 0.0f, 0.0f);
    FRotator RotA_Local   = FRotator(0.0f, 45.0f, 0.0f);    // yaw 45 (Z)
    FVector OffsetB_Local = FVector(0.0f, 100.0f, 0.0f);
    FRotator RotB_Local   = FRotator(0.0f, 0.0f, 30.0f);    // roll 30 (X)

    float32 ProbeRadius = 40.0f;
    FVector DetectorHalfExtents = FVector(50.0f, 50.0f, 50.0f);
    FVector DetectorWorldLocation;

    // Motion
    FCk_Handle_Tween RootTween;
    float32 RootAmplitude = 300.0f;
    float32 RootTweenDuration = 4.0f;

    // Diagnostics
    int32 DetectorHitCount = 0;
    FString LastDetectorEventLine = "(none)";
    float32 ElapsedSeconds = 0.0f;
    float32 LastDriftMagnitude = 0.0f;
    FString StatusLabel = "OK";

    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    FCkGym_AutoConfig AutoConfig;

    //------------------------------------------------------------------------
    // Construction
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto TransformHandle = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_ProbeGym_NestedSceneNodeStation");
        StationWorldLocation = InitialTransform.Translation;

        // ---- Root entity (identity rotation; tweened along +Y) ----
        // Its parent-lifetime owner is this station so it cleans up with us.
        // Request_OverrideToSelf so probes in the chain aren't suppressed by
        // the default DifferentContextOnly policy when overlapping the
        // Detector (also under this station's context).
        RootEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        RootEntity.Request_OverrideToSelf();

        RootStartWorldLocation = StationWorldLocation;
        auto RootInitial = FTransform(FRotator::ZeroRotator, RootStartWorldLocation);
        RootTransformHandle = utils_transform::Add(RootEntity, RootInitial, ECk_Replication::DoesNotReplicate);

        // ---- Scene-node chain ----
        // utils_scene_node::Create internally creates a child entity under the
        // parent transform, adds a Transform fragment, and wires it as a scene
        // node. The child's world transform is composed from parent * local
        // each frame by the scene-node processor.
        auto NodeA_Local = FTransform(RotA_Local, OffsetA_Local, FVector(1.0f, 1.0f, 1.0f));
        NodeA = utils_scene_node::Create(RootTransformHandle, NodeA_Local);
        auto NodeA_TH = NodeA.As_Transform();

        auto NodeB_Local = FTransform(RotB_Local, OffsetB_Local, FVector(1.0f, 1.0f, 1.0f));
        NodeB = utils_scene_node::Create(NodeA_TH, NodeB_Local);
        auto NodeB_TH = NodeB.As_Transform();

        // ---- Chained probe at end of chain ----
        auto ChainedParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        ChainedParams.Set_MotionType(ECk_MotionType::Kinematic);
        ChainedParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);

        auto ChainedDebug = FCk_Probe_DebugInfo();
        ChainedProbe = utils_probe::Add_Sphere(NodeB_TH, ProbeRadius, ChainedParams, ChainedDebug);

        // ---- Detector placement ----
        // Compute expected world location at root's START position (root Y0),
        // then shift the detector up along Y by half the root amplitude so
        // the chained probe passes through once each half-yoyo direction.
        auto ExpectedAtStart = ComputeExpectedChainedLocation(RootStartWorldLocation);
        DetectorWorldLocation = ExpectedAtStart + FVector(0.0f, RootAmplitude * 0.5f, 0.0f);

        DetectorEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        DetectorEntity.Request_OverrideToSelf();

        auto DetectorInitial = FTransform(FRotator::ZeroRotator, DetectorWorldLocation);
        auto DetectorTransformHandle = utils_transform::Add(
            DetectorEntity, DetectorInitial, ECk_Replication::DoesNotReplicate);

        auto DetectorParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Detector"));
        DetectorParams.Set_MotionType(ECk_MotionType::Static);
        DetectorParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto DetectorFilter = FGameplayTagContainer();
        DetectorFilter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        DetectorParams.Set_Filter(DetectorFilter);

        auto DetectorDebug = FCk_Probe_DebugInfo();
        DetectorProbe = utils_probe::Add_Box(
            DetectorTransformHandle, DetectorHalfExtents, DetectorParams, DetectorDebug);

        // Per-frame tick for visuals + display.
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description =
            "Nested scene-node probe stress test.\n" +
            "Root tween drives chained probe through\n" +
            "Z45 -> X30 offset chain.\n" +
            "Detector should fire twice per yoyo.";
        AutoConfig.GlobalAutoCommand = "Ck_GymProbe_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymProbe_AutoNested";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Auto=ON runs tween; Auto=OFF pauses", 0, 0));
        AutoConfig.ManualCommands.Add("Ck_GymProbe_NestedReset");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        utils_probe::BindTo_OnBeginOverlap(DetectorProbe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnDetectorBeginOverlap"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ProbeGym_NestedReset,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnNestedResetMsg"));

        StartRootTween();
    }

    //------------------------------------------------------------------------
    // Tween
    //------------------------------------------------------------------------

    private void StartRootTween()
    {
        auto EndLocation = RootStartWorldLocation + FVector(0.0f, RootAmplitude, 0.0f);
        RootTween = utils_tween::Create_TweenEntityLocation(
            RootTransformHandle, EndLocation, RootTweenDuration,
            ECk_TweenEasing::InOutSine,
            ECk_TweenLoopType::Yoyo,
            -1,
            0.0f);

        if (!AutoRunning)
        { utils_tween::Pause(RootTween); }
    }

    //------------------------------------------------------------------------
    // Signal handler
    //------------------------------------------------------------------------

    UFUNCTION()
    void OnDetectorBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        DetectorHitCount++;
        LastDetectorEventLine = f"HIT @ t={ElapsedSeconds}";
    }

    UFUNCTION()
    private void OnNestedResetMsg(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        // Counter-only reset — the yoyo tween keeps running uninterrupted so
        // we don't need to worry about tween teardown / re-create ordering.
        DetectorHitCount = 0;
        ElapsedSeconds = 0.0f;
        LastDetectorEventLine = "(reset)";
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

        if (ck::Is_NOT_Valid(RootTween))
        { return; }

        if (AutoRunning)
        { utils_tween::Resume(RootTween); }
        else
        { utils_tween::Pause(RootTween); }
    }

    //------------------------------------------------------------------------
    // Per-frame
    //------------------------------------------------------------------------

    UFUNCTION()
    private void FrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (AutoRunning)
        { ElapsedSeconds = ElapsedSeconds + float32(InDeltaT.Get_Seconds()); }

        DrawVisuals();
        DisplayCurrentValues();
    }

    //------------------------------------------------------------------------
    // Expected-position math — composes FTransforms the same way the ECS
    // scene-node processor should. If processor is correct, ECS reports
    // an identical world transform.
    //------------------------------------------------------------------------

    FTransform ComputeExpectedNodeAWorld(FVector InRootWorldLocation)
    {
        auto RootXform = FTransform(FRotator::ZeroRotator, InRootWorldLocation, FVector(1.0f, 1.0f, 1.0f));
        auto NodeA_Local = FTransform(RotA_Local, OffsetA_Local, FVector(1.0f, 1.0f, 1.0f));
        return NodeA_Local * RootXform;
    }

    FTransform ComputeExpectedNodeBWorld(FVector InRootWorldLocation)
    {
        auto NodeA_World = ComputeExpectedNodeAWorld(InRootWorldLocation);
        auto NodeB_Local = FTransform(RotB_Local, OffsetB_Local, FVector(1.0f, 1.0f, 1.0f));
        return NodeB_Local * NodeA_World;
    }

    FVector ComputeExpectedChainedLocation(FVector InRootWorldLocation)
    {
        return ComputeExpectedNodeBWorld(InRootWorldLocation).GetLocation();
    }

    void DrawVisuals()
    {
        auto RootPos = utils_transform::Get_EntityCurrentLocation(RootEntity);

        // Hierarchy cubes are drawn at AS-composed world positions so the
        // chain follows Root regardless of whether the ECS scene-node
        // processor propagates the tween. The "Actual" sphere below shows
        // where the ECS thinks the probe is — if it diverges from the
        // composed chain, that IS the bug this station exists to expose.
        auto ExpectedNodeA = ComputeExpectedNodeAWorld(RootPos).GetLocation();
        auto ExpectedNodeB = ComputeExpectedNodeBWorld(RootPos).GetLocation();
        auto Expected = ExpectedNodeB;

        // Actual ECS-reported position of the probe entity (NodeB). On a
        // correctly-propagating chain this matches ExpectedNodeB exactly.
        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());

        // Root (ORANGE cube, biggest) — the tweened ancestor. Moves along
        // +Y; everything below it should follow.
        utils_pmg_basic_shapes::DrawFilledBox(
            RootPos, FVector(30.0f, 30.0f, 30.0f),
            FLinearColor(1.0f, 0.5f, 0.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, 0.1f);

        // NodeA (CYAN cube) drawn at AS-composed world. Child of Root via
        // local +150 X, yaw 45°.
        utils_pmg_basic_shapes::DrawFilledBox(
            ExpectedNodeA, FVector(20.0f, 20.0f, 20.0f),
            FLinearColor(0.2f, 0.9f, 1.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, 0.1f);

        // NodeB (PURPLE cube) drawn at AS-composed world. Child of NodeA
        // via local +100 Y (in A's rotated frame), roll 30°. The chained
        // probe is composed on NodeB's transform.
        utils_pmg_basic_shapes::DrawFilledBox(
            ExpectedNodeB, FVector(14.0f, 14.0f, 14.0f),
            FLinearColor(0.7f, 0.3f, 1.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, 0.1f);

        // Actual probe body position (what the ECS reports) —
        //   MAGENTA when aligned with Expected
        //   YELLOW on desync (Drift > 5 units) — this is the bug state
        auto Drift = (Expected - Actual).Size();
        LastDriftMagnitude = float32(Drift);
        auto ActualColor = Drift > 5.0f
            ? FLinearColor(1.0f, 1.0f, 0.0f, 1.0f)
            : FLinearColor(1.0f, 0.2f, 1.0f, 0.8f);
        utils_pmg_basic_shapes::DrawFilledSphere(
            Actual, ProbeRadius, 16, 16, ActualColor,
            true, 2.0f, ECk_Plane_Axis::XY, 0.1f);

        // Breadcrumb dashes along Root→NodeA and NodeA→NodeB so the chain
        // is visible (PMG exposes no DrawLine helper in AS).
        DrawChainBreadcrumbs(RootPos, ExpectedNodeA, FLinearColor(1.0f, 0.7f, 0.2f, 0.6f));
        DrawChainBreadcrumbs(ExpectedNodeA, ExpectedNodeB, FLinearColor(0.5f, 0.6f, 1.0f, 0.6f));

        // Detector (GREEN empty / RED occupied). NOT part of the chain — a
        // standalone static probe; the chained probe should sweep through
        // it twice per yoyo period when the hierarchy propagates motion.
        auto DetectorOccupied = utils_probe::Get_CurrentOverlaps(DetectorProbe).Num() > 0;
        auto DetectorColor = DetectorOccupied
            ? FLinearColor(1.0f, 0.2f, 0.2f, 0.25f)
            : FLinearColor(0.2f, 1.0f, 0.4f, 0.15f);
        utils_pmg_basic_shapes::DrawFilledBox(
            DetectorWorldLocation, DetectorHalfExtents, DetectorColor,
            true, 2.0f, ECk_Plane_Axis::XY, 0.1f);
    }

    // Paints tiny cubes along the segment from InStart to InEnd so the
    // parent-to-child relationship is visible as a dashed line.
    void DrawChainBreadcrumbs(FVector InStart, FVector InEnd, FLinearColor InColor)
    {
        auto Steps = 4;
        for (int32 i = 1; i < Steps; ++i)
        {
            auto T = float(i) / float(Steps);
            auto Pos = InStart + (InEnd - InStart) * T;
            utils_pmg_basic_shapes::DrawFilledBox(
                Pos, FVector(4.0f, 4.0f, 4.0f), InColor,
                true, 2.0f, ECk_Plane_Axis::XY, 0.1f);
        }
    }

    //------------------------------------------------------------------------
    // Display
    //------------------------------------------------------------------------

    void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto TitleText = f"PROBE NESTED ({NetworkRole})";

        auto RootPos = utils_transform::Get_EntityCurrentLocation(RootEntity);
        auto ExpectedNodeA = ComputeExpectedNodeAWorld(RootPos).GetLocation();
        auto Expected = ComputeExpectedChainedLocation(RootPos);
        // Actual = what the ECS reports for the probe entity. If the scene-
        // node processor propagates Root's tween to descendants, this should
        // equal Expected each frame.
        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());
        auto Drift = (Expected - Actual).Size();

        StatusLabel = Drift > 5.0f ? FString("DESYNC") : FString("OK");

        // Expected detector hits: every full yoyo (2*duration) crosses
        // detector twice.
        auto FullYoyoSeconds = RootTweenDuration * 2.0f;
        auto ExpectedHits = int32((ElapsedSeconds / FullYoyoSeconds) * 2.0f);

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = DisplayText + "===== Hierarchy =====\n";
        DisplayText = DisplayText + "Root (orange) tweens along +Y.\n";
        DisplayText = DisplayText + " -> NodeA (cyan) +150 X, yaw 45\n";
        DisplayText = DisplayText + "   -> NodeB (purple) +100 Y, roll 30\n";
        DisplayText = DisplayText + "      -> Probe (magenta/yellow sphere)\n";
        DisplayText = DisplayText + "Cubes drawn at AS-composed world pos,\n";
        DisplayText = DisplayText + "sphere drawn at ECS-reported pos.\n";
        DisplayText = DisplayText + "Detector (green/red box, NOT in chain)\n";
        DisplayText = DisplayText + "\n";

        DisplayText = DisplayText + "===== Chain State =====\n";
        DisplayText = f"{DisplayText}Root (live):    {RootPos.X},{RootPos.Y}\n";
        DisplayText = f"{DisplayText}NodeA (AS):     {ExpectedNodeA.X},{ExpectedNodeA.Y}\n";
        DisplayText = f"{DisplayText}NodeB AS-exp:   {Expected.X},{Expected.Y}\n";
        DisplayText = f"{DisplayText}NodeB ECS-act:  {Actual.X},{Actual.Y}\n";
        DisplayText = f"{DisplayText}Drift:          {Drift}\n";
        DisplayText = DisplayText + "\n";
        DisplayText = DisplayText + "===== Detector =====\n";
        DisplayText = DisplayText + "(static box; fires when chained probe\n";
        DisplayText = DisplayText + " sweeps through its volume)\n";
        DisplayText = f"{DisplayText}Hits:     {DetectorHitCount}\n";
        DisplayText = f"{DisplayText}Expected: ~{ExpectedHits}\n";
        DisplayText = f"{DisplayText}Last:     {LastDetectorEventLine}\n";
        DisplayText = DisplayText + "\n";
        DisplayText = f"{DisplayText}Status:   {StatusLabel}\n";
        if (StatusLabel == "DESYNC")
        {
            DisplayText = DisplayText + "ECS probe pos != AS-expected ->\n";
            DisplayText = DisplayText + "scene-node motion not propagating\n";
            DisplayText = DisplayText + "through chain from tweened Root.\n";
        }
        if (ElapsedSeconds > FullYoyoSeconds && DetectorHitCount == 0)
        {
            DisplayText = DisplayText + "Zero detector hits after 1+ yoyo -\n";
            DisplayText = DisplayText + "Jolt body stuck; overlap won't fire.\n";
        }

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(TitleText);
        Fragment.Description = FText::FromString(DisplayText);
    }
}
