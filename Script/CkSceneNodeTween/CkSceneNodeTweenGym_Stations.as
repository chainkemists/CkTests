//============================================================================
// SCENE NODE + TWEEN GYM — STATIONS
//
// Three entity-script stations, each a scene-node parent chain of increasing
// depth with a Tween on the root. Compare AS-composed expected leaf positions
// against ECS-reported world transforms; if they diverge the gym is catching
// the same propagation bug as the Probe gym's NestedSceneNode station in
// isolation (without physics/Jolt/probes muddying the picture).
//
// VISUAL CONVENTIONS (shared across stations):
//   Root            = orange filled box, tweened along +Y
//   Intermediate    = cyan / purple / teal filled boxes, shrinking with depth
//   Leaf            = magenta filled sphere at expected pos / yellow on drift
//   Parent->child   = dashed line (one-frame PMG draw)
//============================================================================

namespace CkSceneNodeTweenGym_Vis
{
    FLinearColor RootColor()    { return FLinearColor(1.0f, 0.5f, 0.0f, 1.0f); }
    FLinearColor LeafAligned()  { return FLinearColor(1.0f, 0.2f, 1.0f, 0.9f); }
    FLinearColor LeafDrift()    { return FLinearColor(1.0f, 1.0f, 0.0f, 1.0f); }
    FLinearColor IntermediateColor(int32 Depth)
    {
        // Distinct hues so each chain link is unambiguous.
        if (Depth == 0) { return FLinearColor(0.2f, 0.9f, 1.0f, 1.0f); }
        if (Depth == 1) { return FLinearColor(0.7f, 0.3f, 1.0f, 1.0f); }
        if (Depth == 2) { return FLinearColor(0.3f, 1.0f, 0.6f, 1.0f); }
        if (Depth == 3) { return FLinearColor(1.0f, 0.7f, 0.2f, 1.0f); }
        return FLinearColor(0.5f, 0.5f, 1.0f, 1.0f);
    }
    FLinearColor EdgeColor(int32 Depth)
    {
        if (Depth == 0) { return FLinearColor(1.0f, 0.7f, 0.2f, 0.8f); }
        if (Depth == 1) { return FLinearColor(0.5f, 0.6f, 1.0f, 0.8f); }
        if (Depth == 2) { return FLinearColor(0.4f, 1.0f, 0.5f, 0.8f); }
        if (Depth == 3) { return FLinearColor(1.0f, 0.4f, 0.4f, 0.8f); }
        return FLinearColor(0.8f, 0.8f, 0.8f, 0.8f);
    }

    // One-frame parent->child dashed line. Redraw each frame to track movement.
    void DrawEdge(FVector InStart, FVector InEnd, int32 InDepth)
    {
        auto DashLen   = 15.0f;
        auto GapLen    = 10.0f;
        auto Thickness = 2.0f;
        auto OneFrame  = 0.0f;
        utils_pmg_directional_shapes::DrawDashedLine(
            InStart, InEnd,
            DashLen, GapLen, Thickness,
            EdgeColor(InDepth), ECk_Plane_Axis::XY, OneFrame);
    }
}

//============================================================================
// STATION 1 — SIMPLE (1 parent -> 1 child)
//============================================================================

class UCk_EntityScript_SceneNodeTweenGym_SimpleStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Transform RootTH;
    FCk_Handle_SceneNode Child;
    FVector RootStart;

    FVector ChildOffset = FVector(0.0f, 120.0f, 0.0f);

    FCk_Handle_Tween RootTween;
    float32 Amplitude = 250.0f;
    float32 Duration  = 3.0f;

    FCk_Handle_Pmg_DebugShape RootShape;
    FCk_Handle_Pmg_DebugShape ChildShape;
    FCk_Handle_Pmg_DebugShape LeafShape;
    FLinearColor LeafColorCached;

    bool AutoRunning = true;
    FCk_Handle_Timer AutoTimer;
    FCkGym_AutoConfig AutoConfig;

    float32 LastDrift = 0.0f;
    FVector LastExpected;
    FVector LastActual;
    FString StatusLabel = "OK";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TH = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_SceneNodeTweenGym_Station");
        utils_handle::Set_DebugName(InHandle, n"SceneNodeTweenGym_Simple_Station");

        RootStart = InitialTransform.Translation;

        auto RootNode = utils_scene_node::Create(TH, FTransform::Identity);
        RootTH = RootNode.As_Transform();
        utils_handle::Set_DebugName(RootTH.H(), n"SceneNodeTweenGym_Simple_Root");

        Child = utils_scene_node::Create(RootTH, FTransform(FRotator::ZeroRotator, ChildOffset, FVector(1,1,1)));
        utils_handle::Set_DebugName(Child.H(), n"SceneNodeTweenGym_Simple_Child");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto T = utils_timer::Add(InHandle, DisplayTimerParams);
        T.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

        AutoConfig.TotalSteps = 1;
        AutoConfig.Description = "Single child tracks tweened root.\nDrift > 5 = propagation broken.";
        AutoConfig.GlobalAutoCommand = "Ck_GymSceneNodeTween_Auto [0/1]";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Tween yoyo", 0, 0));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_SceneNodeTweenGym_Reset,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        RootShape  = utils_pmg_basic_shapes::DrawFilledBox(RootStart, FVector(30,30,30), CkSceneNodeTweenGym_Vis::RootColor(), true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        ChildShape = utils_pmg_basic_shapes::DrawFilledBox(RootStart + ChildOffset, FVector(20,20,20), CkSceneNodeTweenGym_Vis::IntermediateColor(0), true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        LeafColorCached = CkSceneNodeTweenGym_Vis::LeafAligned();
        LeafShape = utils_pmg_basic_shapes::DrawFilledSphere(RootStart + ChildOffset, 25.0f, 12, 12, LeafColorCached, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        StartTween();
    }

    private void StartTween()
    {
        auto End = RootStart + FVector(0.0f, Amplitude, 0.0f);
        RootTween = utils_tween::Create_TweenEntityLocation(
            RootTH, End, Duration,
            ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1, 0.0f);
        if (!AutoRunning) { utils_tween::Pause(RootTween); }
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) {}

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) {}

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
        if (ck::Is_NOT_Valid(RootTween)) { return; }
        if (AutoRunning) { utils_tween::Resume(RootTween); } else { utils_tween::Pause(RootTween); }
    }

    UFUNCTION()
    private void FrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(RootShape)) { return; }

        // Use the FULL root world transform (including rotation) for AS-side
        // composition — vector-add of offsets ignores rotation and produces
        // false DESYNCs when the station has a non-zero yaw.
        auto RootXform = utils_transform::Get_EntityCurrentTransform(RootTH);
        auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildOffset, FVector(1,1,1));
        auto ExpectedXform = ChildLocal * RootXform;
        auto RootWorld = RootXform.GetLocation();
        auto Expected  = ExpectedXform.GetLocation();
        LastExpected = Expected;
        auto Actual    = utils_transform::Get_EntityCurrentLocation(Child.As_Transform());
        LastActual = Actual;

        LastDrift = float32((Expected - Actual).Size());
        StatusLabel = LastDrift > 5.0f ? FString("DESYNC") : FString("OK");

        utils_transform::Request_SetLocation(RootShape,  RootWorld, ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(ChildShape, Expected,  ECk_LocalWorld::World);

        CkSceneNodeTweenGym_Vis::DrawEdge(RootWorld, Expected, 0);

        auto DesiredColor = LastDrift > 5.0f ? CkSceneNodeTweenGym_Vis::LeafDrift() : CkSceneNodeTweenGym_Vis::LeafAligned();
        if (ColorChanged(DesiredColor))
        {
            utils_entity_lifetime::Request_DestroyEntity(LeafShape);
            LeafColorCached = DesiredColor;
            LeafShape = utils_pmg_basic_shapes::DrawFilledSphere(Actual, 25.0f, 12, 12, LeafColorCached, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        }
        else
        {
            utils_transform::Request_SetLocation(LeafShape, Actual, ECk_LocalWorld::World);
        }

        Display();
    }

    private bool ColorChanged(FLinearColor InNew)
    {
        return InNew.R != LeafColorCached.R || InNew.G != LeafColorCached.G ||
               InNew.B != LeafColorCached.B || InNew.A != LeafColorCached.A;
    }

    private void Display()
    {
        auto TitleText = FString("TWEEN + SCENE NODE (SIMPLE)");
        auto Txt = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        Txt = Txt + "Expected sphere position:\n";
        Txt = Txt + " co-located with cyan child box\n";
        Txt = Txt + " (leaf IS the child).\n\n";
        Txt = f"{Txt}Expected: {LastExpected.X},{LastExpected.Y},{LastExpected.Z}\n";
        Txt = f"{Txt}Actual:   {LastActual.X},{LastActual.Y},{LastActual.Z}\n";
        Txt = f"{Txt}Drift:    {LastDrift}\n";
        Txt = f"{Txt}Status:   {StatusLabel}\n";
        if (StatusLabel == "DESYNC")
        { Txt = Txt + "Child not following tweened root.\n"; }
        Txt = Txt + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(ck::ToEntity(this));
        auto& F = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        F.Title = FText::FromString(TitleText);
        F.Description = FText::FromString(Txt);
    }
}

//============================================================================
// STATION 2 — CHAIN (root -> A -> B)
//============================================================================

class UCk_EntityScript_SceneNodeTweenGym_ChainStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Transform RootTH;
    FCk_Handle_SceneNode NodeA;
    FCk_Handle_SceneNode NodeB;
    FVector RootStart;

    FVector OffsetA = FVector(120.0f, 0.0f, 0.0f);
    FRotator RotA   = FRotator(0.0f, 45.0f, 0.0f);
    FVector OffsetB = FVector(0.0f, 100.0f, 0.0f);
    FRotator RotB   = FRotator(0.0f, 0.0f, 30.0f);

    FCk_Handle_Tween RootTween;
    float32 Amplitude = 250.0f;
    float32 Duration  = 3.0f;

    FCk_Handle_Pmg_DebugShape RootShape;
    FCk_Handle_Pmg_DebugShape ShapeA;
    FCk_Handle_Pmg_DebugShape ShapeB;
    FCk_Handle_Pmg_DebugShape LeafShape;
    FLinearColor LeafColorCached;

    bool AutoRunning = true;
    FCk_Handle_Timer AutoTimer;
    FCkGym_AutoConfig AutoConfig;

    float32 LastDrift = 0.0f;
    FVector LastExpected;
    FVector LastActual;
    FString StatusLabel = "OK";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TH = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_SceneNodeTweenGym_Station");
        utils_handle::Set_DebugName(InHandle, n"SceneNodeTweenGym_Chain_Station");
        RootStart = InitialTransform.Translation;

        auto RootNode = utils_scene_node::Create(TH, FTransform::Identity);
        RootTH = RootNode.As_Transform();

        NodeA = utils_scene_node::Create(RootTH, FTransform(RotA, OffsetA, FVector(1,1,1)));
        NodeB = utils_scene_node::Create(NodeA.As_Transform(), FTransform(RotB, OffsetB, FVector(1,1,1)));

        auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));
        AutoConfig.TotalSteps = 1;
        AutoConfig.Description = "Root -> A -> B chain.\nTween drives root along +Y.";
        AutoConfig.GlobalAutoCommand = "Ck_GymSceneNodeTween_Auto [0/1]";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Tween yoyo", 0, 0));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_SceneNodeTweenGym_Reset,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        auto RootXform = utils_transform::Get_EntityCurrentTransform(RootTH);
        auto A = Compose_A(RootXform);
        auto B = Compose_B(RootXform);

        RootShape = utils_pmg_basic_shapes::DrawFilledBox(RootStart, FVector(30,30,30), CkSceneNodeTweenGym_Vis::RootColor(), true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        ShapeA    = utils_pmg_basic_shapes::DrawFilledBox(A.GetLocation(), FVector(22,22,22), CkSceneNodeTweenGym_Vis::IntermediateColor(0), true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        ShapeB    = utils_pmg_basic_shapes::DrawFilledBox(B.GetLocation(), FVector(16,16,16), CkSceneNodeTweenGym_Vis::IntermediateColor(1), true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        LeafColorCached = CkSceneNodeTweenGym_Vis::LeafAligned();
        LeafShape = utils_pmg_basic_shapes::DrawFilledSphere(B.GetLocation(), 25.0f, 12, 12, LeafColorCached, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        auto End = RootStart + FVector(0.0f, Amplitude, 0.0f);
        RootTween = utils_tween::Create_TweenEntityLocation(RootTH, End, Duration, ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1, 0.0f);
        if (!AutoRunning) { utils_tween::Pause(RootTween); }
    }

    // Takes the full Root world transform so station/root rotation is honored.
    // A raw vector-origin build produces false DESYNCs on rotated stations.
    private FTransform Compose_A(FTransform InRootWorld)
    {
        auto Local = FTransform(RotA, OffsetA, FVector(1,1,1));
        return Local * InRootWorld;
    }

    private FTransform Compose_B(FTransform InRootWorld)
    {
        auto A = Compose_A(InRootWorld);
        auto Local = FTransform(RotB, OffsetB, FVector(1,1,1));
        return Local * A;
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) {}

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) {}

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
        if (ck::Is_NOT_Valid(RootTween)) { return; }
        if (AutoRunning) { utils_tween::Resume(RootTween); } else { utils_tween::Pause(RootTween); }
    }

    UFUNCTION()
    private void FrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(RootShape)) { return; }

        auto RootXform = utils_transform::Get_EntityCurrentTransform(RootTH);
        auto RootWorld = RootXform.GetLocation();
        auto A = Compose_A(RootXform).GetLocation();
        auto B = Compose_B(RootXform).GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(NodeB.As_Transform());
        LastExpected = B;
        LastActual = Actual;

        LastDrift = float32((B - Actual).Size());
        StatusLabel = LastDrift > 5.0f ? FString("DESYNC") : FString("OK");

        utils_transform::Request_SetLocation(RootShape, RootWorld, ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(ShapeA,    A,         ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(ShapeB,    B,         ECk_LocalWorld::World);

        CkSceneNodeTweenGym_Vis::DrawEdge(RootWorld, A, 0);
        CkSceneNodeTweenGym_Vis::DrawEdge(A,         B, 1);

        auto DesiredColor = LastDrift > 5.0f ? CkSceneNodeTweenGym_Vis::LeafDrift() : CkSceneNodeTweenGym_Vis::LeafAligned();
        if (ColorChanged(DesiredColor))
        {
            utils_entity_lifetime::Request_DestroyEntity(LeafShape);
            LeafColorCached = DesiredColor;
            LeafShape = utils_pmg_basic_shapes::DrawFilledSphere(Actual, 25.0f, 12, 12, LeafColorCached, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        }
        else
        {
            utils_transform::Request_SetLocation(LeafShape, Actual, ECk_LocalWorld::World);
        }

        Display();
    }

    private bool ColorChanged(FLinearColor InNew)
    {
        return InNew.R != LeafColorCached.R || InNew.G != LeafColorCached.G ||
               InNew.B != LeafColorCached.B || InNew.A != LeafColorCached.A;
    }

    private void Display()
    {
        auto Txt = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        Txt = Txt + "Expected sphere position:\n";
        Txt = Txt + " co-located with purple B box\n";
        Txt = Txt + " (leaf IS node B at end of chain).\n\n";
        Txt = f"{Txt}Expected: {LastExpected.X},{LastExpected.Y},{LastExpected.Z}\n";
        Txt = f"{Txt}Actual:   {LastActual.X},{LastActual.Y},{LastActual.Z}\n";
        Txt = f"{Txt}Drift:    {LastDrift}\n";
        Txt = f"{Txt}Status:   {StatusLabel}\n";
        if (StatusLabel == "DESYNC")
        { Txt = Txt + "Chain leaf not following root.\n"; }
        Txt = Txt + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(ck::ToEntity(this));
        auto& F = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        F.Title = FText::FromString("TWEEN + SCENE NODE (CHAIN)");
        F.Description = FText::FromString(Txt);
    }
}

//============================================================================
// STATION 3 — DEEP (root -> L0 -> L1 -> L2 -> L3 -> leaf)
//============================================================================

class UCk_EntityScript_SceneNodeTweenGym_DeepStation : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Transform RootTH;
    TArray<FCk_Handle_SceneNode> Chain;     // 5 links, Chain.Last() is the leaf
    TArray<FTransform> LocalOffsets;         // matching local transforms per link
    FVector RootStart;

    FCk_Handle_Tween RootTween;
    float32 Amplitude = 300.0f;
    float32 Duration  = 4.0f;

    FCk_Handle_Pmg_DebugShape RootShape;
    TArray<FCk_Handle_Pmg_DebugShape> LinkShapes;
    FCk_Handle_Pmg_DebugShape LeafShape;
    FLinearColor LeafColorCached;

    bool AutoRunning = true;
    FCk_Handle_Timer AutoTimer;
    FCkGym_AutoConfig AutoConfig;

    float32 LastDrift = 0.0f;
    FVector LastExpected;
    FVector LastActual;
    FString StatusLabel = "OK";

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TH = utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_SceneNodeTweenGym_Station");
        utils_handle::Set_DebugName(InHandle, n"SceneNodeTweenGym_Deep_Station");
        RootStart = InitialTransform.Translation;

        auto RootNode = utils_scene_node::Create(TH, FTransform::Identity);
        RootTH = RootNode.As_Transform();

        // Build a 5-link chain. Each link is a small offset with a mild rotation
        // so the accumulated transform depends on every preceding level.
        LocalOffsets.Add(FTransform(FRotator(0,  30, 0), FVector(100,  0, 0), FVector(1,1,1)));
        LocalOffsets.Add(FTransform(FRotator(0, -20, 0), FVector( 80, 20, 0), FVector(1,1,1)));
        LocalOffsets.Add(FTransform(FRotator(0,  15, 0), FVector( 60,  0, 0), FVector(1,1,1)));
        LocalOffsets.Add(FTransform(FRotator(0, -10, 0), FVector( 40, 20, 0), FVector(1,1,1)));
        LocalOffsets.Add(FTransform(FRotator(0,   5, 0), FVector( 30,  0, 0), FVector(1,1,1)));

        auto ParentTH = RootTH;
        for (int32 i = 0; i < LocalOffsets.Num(); ++i)
        {
            auto Link = utils_scene_node::Create(ParentTH, LocalOffsets[i]);
            Chain.Add(Link);
            ParentTH = Link.As_Transform();
        }

        auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"FrameTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));
        AutoConfig.TotalSteps = 1;
        AutoConfig.Description = "5-level chain under a tweened root.\nStresses propagation depth.";
        AutoConfig.GlobalAutoCommand = "Ck_GymSceneNodeTween_Auto [0/1]";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Tween yoyo", 0, 0));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_SceneNodeTweenGym_Reset,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        auto RootXformAtStart = utils_transform::Get_EntityCurrentTransform(RootTH);
        auto Positions = ComposeAll(RootXformAtStart);

        RootShape = utils_pmg_basic_shapes::DrawFilledBox(RootStart, FVector(30,30,30), CkSceneNodeTweenGym_Vis::RootColor(), true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        // Skip last — it gets the sphere-leaf treatment below.
        for (int32 i = 0; i < Positions.Num() - 1; ++i)
        {
            auto Size = Math::Max(8.0f, 22.0f - float(i) * 3.0f);
            auto S = utils_pmg_basic_shapes::DrawFilledBox(
                Positions[i], FVector(Size, Size, Size),
                CkSceneNodeTweenGym_Vis::IntermediateColor(i),
                true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
            LinkShapes.Add(S);
        }

        auto LeafExpected = Positions[Positions.Num() - 1];
        LeafColorCached = CkSceneNodeTweenGym_Vis::LeafAligned();
        LeafShape = utils_pmg_basic_shapes::DrawFilledSphere(LeafExpected, 22.0f, 12, 12, LeafColorCached, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        auto End = RootStart + FVector(0.0f, Amplitude, 0.0f);
        RootTween = utils_tween::Create_TweenEntityLocation(RootTH, End, Duration, ECk_TweenEasing::InOutSine, ECk_TweenLoopType::Yoyo, -1, 0.0f);
        if (!AutoRunning) { utils_tween::Pause(RootTween); }
    }

    // Returns the AS-composed world locations for each link, in chain order.
    // Takes the full Root world transform so station/root rotation is honored.
    private TArray<FVector> ComposeAll(FTransform InRootWorld)
    {
        auto Out = TArray<FVector>();
        auto Acc = InRootWorld;
        for (int32 i = 0; i < LocalOffsets.Num(); ++i)
        {
            Acc = LocalOffsets[i] * Acc;
            Out.Add(Acc.GetLocation());
        }
        return Out;
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) {}

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) {}

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
        if (ck::Is_NOT_Valid(RootTween)) { return; }
        if (AutoRunning) { utils_tween::Resume(RootTween); } else { utils_tween::Pause(RootTween); }
    }

    UFUNCTION()
    private void FrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(RootShape)) { return; }

        auto RootXform = utils_transform::Get_EntityCurrentTransform(RootTH);
        auto RootWorld = RootXform.GetLocation();
        auto Expected = ComposeAll(RootXform);
        auto LeafNode = Chain[Chain.Num() - 1];
        auto LeafActual = utils_transform::Get_EntityCurrentLocation(LeafNode.As_Transform());
        auto LeafExpected = Expected[Expected.Num() - 1];
        LastExpected = LeafExpected;
        LastActual = LeafActual;

        LastDrift = float32((LeafExpected - LeafActual).Size());
        StatusLabel = LastDrift > 5.0f ? FString("DESYNC") : FString("OK");

        utils_transform::Request_SetLocation(RootShape, RootWorld, ECk_LocalWorld::World);
        for (int32 i = 0; i < LinkShapes.Num(); ++i)
        { utils_transform::Request_SetLocation(LinkShapes[i], Expected[i], ECk_LocalWorld::World); }

        // Edges: Root -> link 0, then link i -> link i+1.
        CkSceneNodeTweenGym_Vis::DrawEdge(RootWorld, Expected[0], 0);
        for (int32 i = 0; i < Expected.Num() - 1; ++i)
        { CkSceneNodeTweenGym_Vis::DrawEdge(Expected[i], Expected[i + 1], i + 1); }

        auto DesiredColor = LastDrift > 5.0f ? CkSceneNodeTweenGym_Vis::LeafDrift() : CkSceneNodeTweenGym_Vis::LeafAligned();
        if (ColorChanged(DesiredColor))
        {
            utils_entity_lifetime::Request_DestroyEntity(LeafShape);
            LeafColorCached = DesiredColor;
            LeafShape = utils_pmg_basic_shapes::DrawFilledSphere(LeafActual, 22.0f, 12, 12, LeafColorCached, true, 2.0f, ECk_Plane_Axis::XY, -1.0f);
        }
        else
        {
            utils_transform::Request_SetLocation(LeafShape, LeafActual, ECk_LocalWorld::World);
        }

        Display();
    }

    private bool ColorChanged(FLinearColor InNew)
    {
        return InNew.R != LeafColorCached.R || InNew.G != LeafColorCached.G ||
               InNew.B != LeafColorCached.B || InNew.A != LeafColorCached.A;
    }

    private void Display()
    {
        auto Txt = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        Txt = Txt + "Expected sphere position:\n";
        Txt = Txt + " OFFSET from the last box. Sphere\n";
        Txt = Txt + " sits past link 4 by the 5th local\n";
        Txt = Txt + " offset (it IS the 5th link).\n\n";
        Txt = f"{Txt}Expected (leaf): {LastExpected.X},{LastExpected.Y},{LastExpected.Z}\n";
        Txt = f"{Txt}Actual (leaf):   {LastActual.X},{LastActual.Y},{LastActual.Z}\n";
        Txt = f"{Txt}Drift (leaf):    {LastDrift}\n";
        Txt = f"{Txt}Status:          {StatusLabel}\n";
        if (StatusLabel == "DESYNC")
        { Txt = Txt + "Leaf not following through chain.\n"; }
        Txt = Txt + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(ck::ToEntity(this));
        auto& F = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        F.Title = FText::FromString("TWEEN + SCENE NODE (DEEP)");
        F.Description = FText::FromString(Txt);
    }
}
