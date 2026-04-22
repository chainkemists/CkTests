//============================================================================
// PROBE GYM — STATIONARY HIERARCHY STATION
//
// Companion to the Nested SceneNode stress station, but with NO motion:
// verifies that a Kinematic Probe composed on the end of a scene-node chain
// is correctly placed at the composed world transform at setup time.
//
// Hierarchy (same layout as the tweened Nested station):
//   Root (static)
//    └─ SceneNodeA  — +150 X, yaw 45°
//         └─ SceneNodeB — +100 Y (in A's frame), roll 30°
//              └─ ChainedProbe — Kinematic Sphere, ProbeName = Marker
//
// A Static Box detector is placed at the AS-composed expected world
// position of the chained probe with extent sized to comfortably include
// the probe's sphere. If hierarchy composition at setup works:
//   - Detector.Get_CurrentOverlaps() returns 1 immediately after setup
//   - OnBeginOverlap fires once
//   - HUD shows Drift = 0 (ECS-reported probe pos == AS-composed)
//   - Detector box renders RED (occupied)
//
// If any of those fail, the bug is more fundamental than "motion doesn't
// propagate": it's "composition doesn't happen at all" or "only partial
// links compose". The per-link world positions in the HUD pinpoint which
// link is wrong.
//============================================================================

class UCk_EntityScript_ProbeGym_StationaryHierarchyStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle RootEntity;
    FCk_Handle_Transform RootTransformHandle;
    FCk_Handle_SceneNode NodeA;
    FCk_Handle_SceneNode NodeB;
    FCk_Handle_Probe ChainedProbe;

    FCk_Handle DetectorEntity;
    FCk_Handle_Probe DetectorProbe;

    FVector StationWorldLocation;
    FVector RootWorldLocation;
    FVector OffsetA_Local = FVector(150.0f, 0.0f, 0.0f);
    FRotator RotA_Local   = FRotator(0.0f, 45.0f, 0.0f);    // yaw 45 (Z)
    FVector OffsetB_Local = FVector(0.0f, 100.0f, 0.0f);
    FRotator RotB_Local   = FRotator(0.0f, 0.0f, 30.0f);    // roll 30 (X)

    float32 ProbeRadius = 40.0f;
    FVector DetectorHalfExtents = FVector(60.0f, 60.0f, 60.0f);
    FVector DetectorWorldLocation;

    int32 DetectorHitCount = 0;
    FString LastDetectorEventLine = "(none)";

    // Persistent debug shapes — chain is stationary, so the hierarchy cubes
    // and breadcrumbs are spawned once with infinite lifetime and never moved.
    // Actual sphere and Detector box are only destroyed + respawned when
    // their (color-encoded) state actually changes; basic-shape PMG has no
    // recolor request.
    FCk_Handle_Pmg_DebugShape RootShape;
    FCk_Handle_Pmg_DebugShape NodeAShape;
    FCk_Handle_Pmg_DebugShape NodeBShape;
    TArray<FCk_Handle_Pmg_DebugShape> BreadcrumbsA;
    TArray<FCk_Handle_Pmg_DebugShape> BreadcrumbsB;
    int32 BreadcrumbSteps = 4;

    FCk_Handle_Pmg_DebugShape ActualShape;
    FLinearColor ActualColorCached;
    FCk_Handle_Pmg_DebugShape DetectorShape;
    FLinearColor DetectorColorCached;

    FLinearColor ActualColor_Aligned = FLinearColor(1.0f, 0.2f, 1.0f, 0.8f);
    FLinearColor ActualColor_Drift   = FLinearColor(1.0f, 1.0f, 0.0f, 1.0f);
    FLinearColor DetectorColor_Empty = FLinearColor(0.2f, 1.0f, 0.4f, 0.15f);
    FLinearColor DetectorColor_Hit   = FLinearColor(1.0f, 0.2f, 0.2f, 0.25f);

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
        utils_entity_tag::Add(InHandle, n"TAG_ProbeGym_StationaryHierarchyStation");
        StationWorldLocation = InitialTransform.Translation;

        // ---- Root (static, identity rotation) ----
        RootEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        RootEntity.Request_OverrideToSelf();

        RootWorldLocation = StationWorldLocation;
        auto RootInitial = FTransform(FRotator::ZeroRotator, RootWorldLocation);
        RootTransformHandle = utils_transform::Add(RootEntity, RootInitial, ECk_Replication::DoesNotReplicate);

        // ---- Scene-node chain ----
        auto NodeA_Local = FTransform(RotA_Local, OffsetA_Local, FVector(1.0f, 1.0f, 1.0f));
        NodeA = utils_scene_node::Create(RootTransformHandle, NodeA_Local);

        auto NodeB_Local = FTransform(RotB_Local, OffsetB_Local, FVector(1.0f, 1.0f, 1.0f));
        NodeB = utils_scene_node::Create(NodeA.As_Transform(), NodeB_Local);

        // ---- Chained probe at end of chain ----
        auto ChainedParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.Gym.Marker"));
        ChainedParams.Set_MotionType(ECk_MotionType::Kinematic);
        ChainedParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);

        auto ChainedDebug = FCk_Probe_DebugInfo();
        ChainedProbe = utils_probe::Add_Sphere(NodeB.As_Transform(), ProbeRadius, ChainedParams, ChainedDebug);

        // ---- Detector at AS-composed expected probe world position ----
        // If hierarchy composition works at setup, the chained probe sits
        // exactly inside this box and the detector fires OnBeginOverlap once.
        DetectorWorldLocation = ComputeExpectedChainedLocation();

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

        // Per-frame display tick
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description =
            "Static Z45 -> X30 hierarchy, no motion.\n" +
            "Proves probe is placed at composed\n" +
            "world location on setup, and detector\n" +
            "overlaps it immediately. Drift == 0 and\n" +
            "Hits >= 1 means hierarchy composition\n" +
            "itself works (the Nested station's\n" +
            "'frozen position' bug is motion-only).";
        AutoConfig.GlobalAutoCommand = "";
        AutoConfig.PerStationAutoCommand = "";
        AutoConfig.Steps.Add(FCkGym_AutoStep("No motion - overlap should fire at setup", 0, 0));
        AutoConfig.ManualCommands.Add("(no manual commands - pure at-rest test)");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        utils_probe::BindTo_OnBeginOverlap(DetectorProbe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnDetectorBeginOverlap"));

        SpawnPersistentShapes();
    }

    private void SpawnPersistentShapes()
    {
        auto RootPos = utils_transform::Get_EntityCurrentLocation(RootEntity);
        auto ExpectedNodeA = ComputeExpectedNodeAWorld().GetLocation();
        auto ExpectedNodeB = ComputeExpectedNodeBWorld().GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());

        RootShape = utils_pmg_basic_shapes::DrawFilledBox(
            RootPos, FVector(30.0f, 30.0f, 30.0f),
            FLinearColor(1.0f, 0.5f, 0.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        NodeAShape = utils_pmg_basic_shapes::DrawFilledBox(
            ExpectedNodeA, FVector(20.0f, 20.0f, 20.0f),
            FLinearColor(0.2f, 0.9f, 1.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        NodeBShape = utils_pmg_basic_shapes::DrawFilledBox(
            ExpectedNodeB, FVector(14.0f, 14.0f, 14.0f),
            FLinearColor(0.7f, 0.3f, 1.0f, 1.0f),
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        auto BreadcrumbColorA = FLinearColor(1.0f, 0.7f, 0.2f, 0.6f);
        auto BreadcrumbColorB = FLinearColor(0.5f, 0.6f, 1.0f, 0.6f);
        for (int32 i = 1; i < BreadcrumbSteps; ++i)
        {
            auto T = float(i) / float(BreadcrumbSteps);
            auto PosA = RootPos + (ExpectedNodeA - RootPos) * T;
            auto PosB = ExpectedNodeA + (ExpectedNodeB - ExpectedNodeA) * T;

            BreadcrumbsA.Add(utils_pmg_basic_shapes::DrawFilledBox(
                PosA, FVector(4.0f, 4.0f, 4.0f), BreadcrumbColorA,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f));
            BreadcrumbsB.Add(utils_pmg_basic_shapes::DrawFilledBox(
                PosB, FVector(4.0f, 4.0f, 4.0f), BreadcrumbColorB,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f));
        }

        ActualColorCached = ActualColor_Aligned;
        ActualShape = utils_pmg_basic_shapes::DrawFilledSphere(
            Actual, ProbeRadius, 16, 16, ActualColorCached,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        DetectorColorCached = DetectorColor_Empty;
        DetectorShape = utils_pmg_basic_shapes::DrawFilledBox(
            DetectorWorldLocation, DetectorHalfExtents, DetectorColorCached,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
    }

    private bool ColorIsDifferent(FLinearColor InA, FLinearColor InB)
    {
        return InA.R != InB.R || InA.G != InB.G || InA.B != InB.B || InA.A != InB.A;
    }

    //------------------------------------------------------------------------
    // Signals / auto
    //------------------------------------------------------------------------

    UFUNCTION()
    void OnDetectorBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        DetectorHitCount++;
        LastDetectorEventLine = f"HIT x{DetectorHitCount}";
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
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

    //------------------------------------------------------------------------
    // AS-composed world positions (same math as Nested station)
    //------------------------------------------------------------------------

    FTransform ComputeExpectedNodeAWorld()
    {
        auto RootXform = FTransform(FRotator::ZeroRotator, RootWorldLocation, FVector(1.0f, 1.0f, 1.0f));
        auto NodeA_Local = FTransform(RotA_Local, OffsetA_Local, FVector(1.0f, 1.0f, 1.0f));
        return NodeA_Local * RootXform;
    }

    FTransform ComputeExpectedNodeBWorld()
    {
        auto NodeA_World = ComputeExpectedNodeAWorld();
        auto NodeB_Local = FTransform(RotB_Local, OffsetB_Local, FVector(1.0f, 1.0f, 1.0f));
        return NodeB_Local * NodeA_World;
    }

    FVector ComputeExpectedChainedLocation()
    {
        return ComputeExpectedNodeBWorld().GetLocation();
    }

    //------------------------------------------------------------------------
    // Draw
    //------------------------------------------------------------------------

    void DrawVisuals()
    {
        // Skip until DoBeginPlay has spawned the persistent shapes.
        if (ck::Is_NOT_Valid(RootShape))
        { return; }

        // Hierarchy is stationary; only Actual + Detector might change color.
        auto ExpectedNodeB = ComputeExpectedNodeBWorld().GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());

        auto Drift = (ExpectedNodeB - Actual).Size();
        auto ActualColor = Drift > 5.0f ? ActualColor_Drift : ActualColor_Aligned;
        if (ColorIsDifferent(ActualColor, ActualColorCached))
        {
            utils_entity_lifetime::Request_DestroyEntity(ActualShape);
            ActualColorCached = ActualColor;
            ActualShape = utils_pmg_basic_shapes::DrawFilledSphere(
                Actual, ProbeRadius, 16, 16, ActualColorCached,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        }
        else
        {
            // Even on a stationary chain, Actual can drift if a bug occurs.
            utils_transform::Request_SetLocation(ActualShape, Actual, ECk_LocalWorld::World);
        }

        auto DetectorOccupied = utils_probe::Get_CurrentOverlaps(DetectorProbe).Num() > 0;
        auto DetectorColor = DetectorOccupied ? DetectorColor_Hit : DetectorColor_Empty;
        if (ColorIsDifferent(DetectorColor, DetectorColorCached))
        {
            utils_entity_lifetime::Request_DestroyEntity(DetectorShape);
            DetectorColorCached = DetectorColor;
            DetectorShape = utils_pmg_basic_shapes::DrawFilledBox(
                DetectorWorldLocation, DetectorHalfExtents, DetectorColorCached,
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        }
    }

    //------------------------------------------------------------------------
    // Display
    //------------------------------------------------------------------------

    void DisplayCurrentValues()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto TitleText = f"PROBE STATIC HIER ({NetworkRole})";

        auto RootPos = utils_transform::Get_EntityCurrentLocation(RootEntity);
        auto ExpectedNodeA = ComputeExpectedNodeAWorld().GetLocation();
        auto Expected = ComputeExpectedNodeBWorld().GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());
        auto Drift = (Expected - Actual).Size();

        auto CompositionStatus = Drift > 5.0f ? FString("BROKEN") : FString("OK");
        auto OverlapStatus = DetectorHitCount > 0 ? FString("FIRED") : FString("silent");

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = DisplayText + "===== Hierarchy (stationary) =====\n";
        DisplayText = DisplayText + "Root (orange) - static\n";
        DisplayText = DisplayText + " -> NodeA (cyan) +150 X, yaw 45\n";
        DisplayText = DisplayText + "   -> NodeB (purple) +100 Y, roll 30\n";
        DisplayText = DisplayText + "      -> Probe (magenta sphere)\n";
        DisplayText = DisplayText + "Detector positioned AT expected probe\n";
        DisplayText = DisplayText + "world location - should overlap at setup.\n";
        DisplayText = DisplayText + "\n";

        DisplayText = DisplayText + "===== Composition Check =====\n";
        DisplayText = f"{DisplayText}Root:           {RootPos.X},{RootPos.Y}\n";
        DisplayText = f"{DisplayText}NodeA AS-exp:   {ExpectedNodeA.X},{ExpectedNodeA.Y}\n";
        DisplayText = f"{DisplayText}NodeB AS-exp:   {Expected.X},{Expected.Y}\n";
        DisplayText = f"{DisplayText}NodeB ECS-act:  {Actual.X},{Actual.Y}\n";
        DisplayText = f"{DisplayText}Drift:          {Drift}\n";
        DisplayText = f"{DisplayText}Composition:    {CompositionStatus}\n";
        DisplayText = DisplayText + "\n";

        DisplayText = DisplayText + "===== Detector =====\n";
        DisplayText = f"{DisplayText}Overlap:        {OverlapStatus}\n";
        DisplayText = f"{DisplayText}Hits:           {DetectorHitCount}\n";
        DisplayText = f"{DisplayText}Last:           {LastDetectorEventLine}\n";
        DisplayText = DisplayText + "\n";

        if (CompositionStatus == "OK" && OverlapStatus == "FIRED")
        {
            DisplayText = DisplayText + "Hierarchy composition works at rest.\n";
            DisplayText = DisplayText + "The Nested station's drift is a\n";
            DisplayText = DisplayText + "motion-propagation bug, not a setup\n";
            DisplayText = DisplayText + "composition bug.\n";
        }
        else if (CompositionStatus != "OK")
        {
            DisplayText = DisplayText + "Setup composition itself broken.\n";
            DisplayText = DisplayText + "Compare NodeB AS-exp vs ECS-act to\n";
            DisplayText = DisplayText + "see which link is wrong.\n";
        }
        else if (OverlapStatus != "FIRED")
        {
            DisplayText = DisplayText + "Composition OK but Jolt body never\n";
            DisplayText = DisplayText + "ended up at composed position. The\n";
            DisplayText = DisplayText + "ECS-Jolt handoff is broken.\n";
        }

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(TitleText);
        Fragment.Description = FText::FromString(DisplayText);
    }
}
