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
    FCk_Handle StationEntity;
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

    // Persistent debug shapes for the static-color elements of the chain.
    // Created once with infinite lifetime in DoBeginPlay and re-positioned
    // each frame in DrawVisuals. Only Actual (drift-colored) and Detector
    // (overlap-colored) are still recreated per-tick — basic-shape PMG has
    // no recolor API, so swapping colors requires a fresh shape.
    FCk_Handle_Pmg_DebugShape RootShape;
    FCk_Handle_Pmg_DebugShape NodeAShape;
    FCk_Handle_Pmg_DebugShape NodeBShape;

    // Parent->child relationships are shown as dashed lines redrawn each frame
    // (Duration=0 PMG draws live for one frame, no persistent entity churn beyond
    //  the one-frame-lifetime entity which is cleaned up automatically).
    FLinearColor LineColor_RootToA = FLinearColor(1.0f, 0.7f, 0.2f, 0.8f);
    FLinearColor LineColor_AToB    = FLinearColor(0.5f, 0.6f, 1.0f, 0.8f);

    // Color-flipping shapes — kept persistent, position updated each frame,
    // and only destroyed + respawned when the desired color actually changes.
    FCk_Handle_Pmg_DebugShape ActualShape;
    FLinearColor ActualColorCached;
    FCk_Handle_Pmg_DebugShape DetectorShape;
    FLinearColor DetectorColorCached;

    FLinearColor ActualColor_Aligned = FLinearColor(1.0f, 0.2f, 1.0f, 0.8f);
    FLinearColor ActualColor_Drift   = FLinearColor(1.0f, 1.0f, 0.0f, 1.0f);
    FLinearColor DetectorColor_Empty = FLinearColor(0.2f, 1.0f, 0.4f, 0.15f);
    FLinearColor DetectorColor_Hit   = FLinearColor(1.0f, 0.2f, 0.2f, 0.25f);

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
        StationEntity = InHandle;
        utils_handle::Set_DebugName(StationEntity, n"ProbeGym_Nested_Station");

        // ---- Root entity (scene node under the station; tweened along +Y) ----
        // Making Root itself a scene-node child of the station ensures the
        // tween's world-space writes propagate through the chain below it.
        // Without this, Root has a plain transform and NodeA/B compose off a
        // static parent — the chained probe never moves.
        // Request_OverrideToSelf so probes in the chain aren't suppressed by
        // the default DifferentContextOnly policy when overlapping the
        // Detector (also under this station's context).
        RootStartWorldLocation = StationWorldLocation;
        auto RootLocal = FTransform(FRotator::ZeroRotator, FVector::ZeroVector);
        auto RootNode = utils_scene_node::Create(TransformHandle, RootLocal);
        RootTransformHandle = RootNode.As_Transform();
        RootEntity = RootTransformHandle.H();
        RootEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(RootEntity, n"ProbeGym_Nested_Root");

        // ---- Scene-node chain ----
        // utils_scene_node::Create internally creates a child entity under the
        // parent transform, adds a Transform fragment, and wires it as a scene
        // node. The child's world transform is composed from parent * local
        // each frame by the scene-node processor.
        auto NodeA_Local = FTransform(RotA_Local, OffsetA_Local, FVector(1.0f, 1.0f, 1.0f));
        NodeA = utils_scene_node::Create(RootTransformHandle, NodeA_Local);
        auto NodeA_TH = NodeA.As_Transform();
        utils_handle::Set_DebugName(NodeA_TH.H(), n"ProbeGym_Nested_NodeA");

        auto NodeB_Local = FTransform(RotB_Local, OffsetB_Local, FVector(1.0f, 1.0f, 1.0f));
        NodeB = utils_scene_node::Create(NodeA_TH, NodeB_Local);
        auto NodeB_TH = NodeB.As_Transform();
        utils_handle::Set_DebugName(NodeB_TH.H(), n"ProbeGym_Nested_NodeB");

        // ---- Chained probe at end of chain ----
        auto ChainedParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        ChainedParams.Set_MotionType(ECk_MotionType::Kinematic);
        ChainedParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);

        auto ChainedDebug = FCk_Probe_DebugInfo();
        ChainedProbe = utils_probe::Add_Sphere(NodeB_TH, ProbeRadius, ChainedParams, ChainedDebug);
        utils_handle::Set_DebugName(ChainedProbe.H(), n"ProbeGym_Nested_ChainedProbe");

        // ---- Detector placement ----
        // Compute expected world location at root's START position (root Y0),
        // then shift the detector up along Y by half the root amplitude so
        // the chained probe passes through once each half-yoyo direction.
        auto ExpectedAtStart = ComputeExpectedChainedLocation(RootStartWorldLocation);
        DetectorWorldLocation = ExpectedAtStart + FVector(0.0f, RootAmplitude * 0.5f, 0.0f);

        DetectorEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        DetectorEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(DetectorEntity, n"ProbeGym_Nested_Detector");

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
        utils_handle::Set_DebugName(DetectorProbe.H(), n"ProbeGym_Nested_DetectorProbe");

        // Per-frame tick for visuals + display.
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));
        utils_handle::Set_DebugName(DisplayTimer.H(), n"ProbeGym_Nested_DisplayTimer");

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));
        utils_handle::Set_DebugName(AutoTimer.H(), n"ProbeGym_Nested_AutoTimer");

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

        SpawnPersistentShapes();
        StartRootTween();
    }

    private void SpawnPersistentShapes()
    {
        auto RootPos = utils_transform::Get_EntityCurrentLocation(RootEntity);
        auto ExpectedNodeA = ComputeExpectedNodeAWorld(RootPos).GetLocation();
        auto ExpectedNodeB = ComputeExpectedNodeBWorld(RootPos).GetLocation();

        // Duration = -1.0 -> PMG CheckDuration processor early-outs and
        // never destroys the shape. Per-frame work only moves them.
        RootShape = utils_pmg_basic_shapes::DrawFilledBox(
            RootPos, FVector(30.0f, 30.0f, 30.0f),
            FLinearColor(1.0f, 0.5f, 0.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        utils_handle::Set_DebugName(RootShape.H(), n"ProbeGym_Nested_RootShape");

        NodeAShape = utils_pmg_basic_shapes::DrawFilledBox(
            ExpectedNodeA, FVector(20.0f, 20.0f, 20.0f),
            FLinearColor(0.2f, 0.9f, 1.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        utils_handle::Set_DebugName(NodeAShape.H(), n"ProbeGym_Nested_NodeAShape");

        NodeBShape = utils_pmg_basic_shapes::DrawFilledBox(
            ExpectedNodeB, FVector(14.0f, 14.0f, 14.0f),
            FLinearColor(0.7f, 0.3f, 1.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        utils_handle::Set_DebugName(NodeBShape.H(), n"ProbeGym_Nested_NodeBShape");

        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());
        ActualColorCached = ActualColor_Aligned;
        ActualShape = utils_pmg_basic_shapes::DrawFilledSphere(
            Actual, ProbeRadius, 16, 16, ActualColorCached,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        utils_handle::Set_DebugName(ActualShape.H(), n"ProbeGym_Nested_ActualShape");

        DetectorColorCached = DetectorColor_Empty;
        DetectorShape = utils_pmg_basic_shapes::DrawFilledBox(
            DetectorWorldLocation, DetectorHalfExtents, DetectorColorCached,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        utils_handle::Set_DebugName(DetectorShape.H(), n"ProbeGym_Nested_DetectorShape");
    }

    private bool ColorIsDifferent(FLinearColor InA, FLinearColor InB)
    {
        return InA.R != InB.R || InA.G != InB.G || InA.B != InB.B || InA.A != InB.A;
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
        utils_handle::Set_DebugName(RootTween.H(), n"ProbeGym_Nested_RootTween");

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
        // FrameTick can fire before DoBeginPlay (and thus before
        // SpawnPersistentShapes); skip until the persistent shapes exist.
        if (ck::Is_NOT_Valid(RootShape))
        { return; }

        auto RootPos = utils_transform::Get_EntityCurrentLocation(RootEntity);

        // Hierarchy cubes track the AS-composed world positions so the
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

        // Move persistent shapes to their new composed positions. These were
        // spawned once with infinite lifetime in SpawnPersistentShapes().
        utils_transform::Request_SetLocation(RootShape,  RootPos,        ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(NodeAShape, ExpectedNodeA, ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(NodeBShape, ExpectedNodeB, ECk_LocalWorld::World);

        // Parent->child edges (dashed lines, one-frame PMG draws). Much lower
        // visual noise than breadcrumb cubes and makes the hierarchy obvious.
        auto DashLen   = 15.0f;
        auto GapLen    = 10.0f;
        auto Thickness = 2.0f;
        auto OneFrame  = 0.0f;
        utils_pmg_directional_shapes::DrawDashedLine(
            RootPos, ExpectedNodeA,
            DashLen, GapLen, Thickness,
            LineColor_RootToA, ECk_Plane_Axis::XY, OneFrame);
        utils_pmg_directional_shapes::DrawDashedLine(
            ExpectedNodeA, ExpectedNodeB,
            DashLen, GapLen, Thickness,
            LineColor_AToB, ECk_Plane_Axis::XY, OneFrame);

        // Actual probe body position (what the ECS reports) —
        //   MAGENTA when aligned with Expected
        //   YELLOW on desync (Drift > 5 units) — this is the bug state
        // Basic-shape PMG has no recolor request, so on color flip we
        // destroy + respawn the shape; otherwise just move it.
        auto Drift = (Expected - Actual).Size();
        LastDriftMagnitude = float32(Drift);
        auto ActualColor = Drift > 5.0f ? ActualColor_Drift : ActualColor_Aligned;
        if (ColorIsDifferent(ActualColor, ActualColorCached))
        {
            utils_entity_lifetime::Request_DestroyEntity(ActualShape);
            ActualColorCached = ActualColor;
            ActualShape = utils_pmg_basic_shapes::DrawFilledSphere(
                Actual, ProbeRadius, 16, 16, ActualColorCached,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
            utils_handle::Set_DebugName(ActualShape.H(), n"ProbeGym_Nested_ActualShape");
        }
        else
        {
            utils_transform::Request_SetLocation(ActualShape, Actual, ECk_LocalWorld::World);
        }

        // Detector (GREEN empty / RED occupied). NOT part of the chain — a
        // standalone static probe; the chained probe should sweep through
        // it twice per yoyo period when the hierarchy propagates motion.
        // Position is fixed; only respawn on color change.
        auto DetectorOccupied = utils_probe::Get_CurrentOverlaps(DetectorProbe).Num() > 0;
        auto DetectorColor = DetectorOccupied ? DetectorColor_Hit : DetectorColor_Empty;
        if (ColorIsDifferent(DetectorColor, DetectorColorCached))
        {
            utils_entity_lifetime::Request_DestroyEntity(DetectorShape);
            DetectorColorCached = DetectorColor;
            DetectorShape = utils_pmg_basic_shapes::DrawFilledBox(
                DetectorWorldLocation, DetectorHalfExtents, DetectorColorCached,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
            utils_handle::Set_DebugName(DetectorShape.H(), n"ProbeGym_Nested_DetectorShape");
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
