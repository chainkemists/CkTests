// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: VIEW-ANCHOR DESCENDANTS SETTLE SAME FRAME
//============================================================================
//
// Camera composition runs after the primary Transform pass and publishes the
// rendered pose to Get_ViewAnchor() through an ordinary transform request. The
// complete view-anchor SceneNode hierarchy must settle before Transform_Finalize:
// a tail-of-scheduler pump is too late for downstream consumers.
//
// This test hangs depth-1, depth-2, and depth-10 branches from the view anchor.
// A Gameplay_Camera probe (after Transform_Finalize, before the global pump)
// captures ViewInfo and every leaf during the exact frame a new director pose
// was requested. The captured leaves must equal local-chain * composed-view in
// that same frame.
//============================================================================

struct FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult
{
    bool Completed = false;
    bool Succeeded = false;

    int64 StimulusFrame = -1;
    int64 ProbeFrame = -1;

    FCk_Handle_Transform Depth1Leaf;
    FCk_Handle_Transform Depth2Leaf;
    FCk_Handle_Transform Depth10Leaf;

    FTransform ViewTransform;
    FTransform TargetDirectorTransform;
    FTransform Depth1Actual;
    FTransform Depth2Actual;
    FTransform Depth10Actual;
}

struct FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeMarker {}
struct FCk_Fragment_TESTONLY_CameraViewAnchorSettleProducerMarker {}

// The AutoTest continuation can execute after the primary Transform drain. A
// dedicated early-frame producer removes that timing ambiguity: it stamps the
// exact scheduler frame and queues the director request before Transform runs.
class UCk_TESTONLY_Processor_CameraViewAnchorSettleProducer : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_TimeDelta";

    UFUNCTION(BlueprintOverride)
    void Configure(FCk_ScriptProcessorQuery& Query)
    {
        Query.Require(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProducerMarker);
        Query.Require(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);
    }

    UFUNCTION(BlueprintOverride)
    void ForEachBatch(FCk_ScriptQueryBatch Batch, FCk_Time InDeltaT)
    {
        for (int32 Index = 0; Index < Batch.Num(); ++Index)
        {
            auto Entity = Batch.GetHandle(Index);
            auto& Probe = Entity.Get_Fragment(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);
            if (Probe.StimulusFrame >= 0)
            { continue; }

            Probe.StimulusFrame = utils_time::Get_FrameCounter();
            auto Director = Entity.As_Transform(ECk_SanityCheck::UnChecked);
            utils_transform::Request_SetTransform(Director, Probe.TargetDirectorTransform);
            Entity.Request_TryRemove(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProducerMarker);
        }
    }
}

// Gameplay_Camera is the first post-finalize observation slot. Capturing here
// distinguishes a true transform-local settle from the scheduler's global pump,
// which runs only after the complete main graph.
class UCk_TESTONLY_Processor_CameraViewAnchorSettleProbe : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_Camera";
    default _MarkedDirtyBy = FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeMarker;

    UFUNCTION(BlueprintOverride)
    void Configure(FCk_ScriptProcessorQuery& Query)
    {
        Query.Require(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeMarker);
        Query.Require(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);
    }

    UFUNCTION(BlueprintOverride)
    void ForEachBatch(FCk_ScriptQueryBatch Batch, FCk_Time InDeltaT)
    {
        for (int32 Index = 0; Index < Batch.Num(); ++Index)
        {
            auto Entity = Batch.GetHandle(Index);
            auto& Probe = Entity.Get_Fragment(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);
            if (Probe.Completed)
            { continue; }

            // The probe is armed before the early-frame producer gets its next
            // main-pass opportunity. Ignore that partial frame.
            if (Probe.StimulusFrame < 0)
            { continue; }

            auto Camera = Entity.As_Camera(ECk_SanityCheck::UnChecked);
            Probe.Succeeded = ck::IsValid(Camera)
                && ck::IsValid(Probe.Depth1Leaf)
                && ck::IsValid(Probe.Depth2Leaf)
                && ck::IsValid(Probe.Depth10Leaf);

            if (Probe.Succeeded)
            {
                const auto ViewInfo = Camera.Get_ViewInfo();
                Probe.ViewTransform = FTransform(ViewInfo.Rotation, ViewInfo.Location, FVector::OneVector);
                Probe.Depth1Actual = utils_transform::Get_EntityCurrentTransform(Probe.Depth1Leaf);
                Probe.Depth2Actual = utils_transform::Get_EntityCurrentTransform(Probe.Depth2Leaf);
                Probe.Depth10Actual = utils_transform::Get_EntityCurrentTransform(Probe.Depth10Leaf);
            }

            Probe.ProbeFrame = utils_time::Get_FrameCounter();
            Probe.Completed = true;
            Entity.Request_TryRemove(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeMarker);
        }
    }
}

class UCk_AutoTest_GameplayCamera_ViewAnchorDescendantsSettleSameFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private const float32 TransformTolerance = 0.5f;

    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera _Camera;
    private FCk_Handle_Transform _Director;
    private FCk_Handle_Transform _Depth1Leaf;
    private FCk_Handle_Transform _Depth2Leaf;
    private FCk_Handle_Transform _Depth10Leaf;

    private FVector _InitialViewLocation = FVector::ZeroVector;
    private FTransform _BootstrapView;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _Helper = Cast<ACkAutoTest_GameplayCamera_Helper>(SpawnActor(
            ACkAutoTest_GameplayCamera_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        { FinishFailure("Failed to spawn GameplayCamera helper"); return; }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        _Director = OwnedEntity.As_Transform();
        _Camera = utils_camera::Add(
            _Director, FCk_Fragment_Camera_ParamsData(_Helper.CameraComponent));

        if (ck::Is_NOT_Valid(_Camera))
        { FinishFailure("Failed to add GameplayCamera"); return; }

        auto ViewAnchor = _Camera.Get_ViewAnchor();
        if (ck::Is_NOT_Valid(ViewAnchor))
        { FinishFailure("GameplayCamera returned an invalid view anchor"); return; }

        _Depth1Leaf = CreateBranch(ViewAnchor, 1, 0.0f);
        _Depth2Leaf = CreateBranch(ViewAnchor, 2, 150.0f);
        _Depth10Leaf = CreateBranch(ViewAnchor, 10, 300.0f);
        if (IsFinished()) { return; }

        _InitialViewLocation = Get_ViewTransform().GetLocation();

        // Establish a non-default composed state before arming the measured
        // transition, so the completion predicate cannot pass vacuously.
        utils_transform::Request_SetTransform(_Director, FTransform(
            FRotator(0.0f, 25.0f, 0.0f),
            FVector(400.0f, -200.0f, 150.0f),
            FVector::OneVector));

        WaitUntil(n"Check_BootstrapComposed", n"OnBootstrapComposed");
    }

    private FCk_Handle_Transform CreateBranch(
        FCk_Handle_Transform InParent,
        int32 InDepth,
        float32 InYOffset)
    {
        auto Parent = InParent;
        for (int32 Index = 0; Index < InDepth; ++Index)
        {
            const auto Local = MakeLocalTransform(Index, InYOffset);
            auto Node = utils_scene_node::Create(Parent, Local);
            if (ck::Is_NOT_Valid(Node))
            {
                FinishFailure(f"Failed to create SceneNode branch depth {InDepth}, link {Index}");
                return FCk_Handle_Transform();
            }
            Parent = Node.As_Transform();
        }
        return Parent;
    }

    private FTransform MakeLocalTransform(int32 InIndex, float32 InYOffset) const
    {
        return FTransform(
            FRotator(0.0f, float32((InIndex + 1) * 7), 0.0f),
            FVector(40.0f + float32(InIndex * 5), InYOffset, 10.0f),
            FVector::OneVector);
    }

    private FTransform ComposeExpected(
        FTransform InParent,
        int32 InDepth,
        float32 InYOffset) const
    {
        auto Result = InParent;
        for (int32 Index = 0; Index < InDepth; ++Index)
        {
            Result = MakeLocalTransform(Index, InYOffset) * Result;
        }
        return Result;
    }

    private FTransform Get_ViewTransform() const
    {
        const auto ViewInfo = _Camera.Get_ViewInfo();
        return FTransform(ViewInfo.Rotation, ViewInfo.Location, FVector::OneVector);
    }

    UFUNCTION()
    private void Check_BootstrapComposed(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        if (ck::Is_NOT_Valid(_Camera))
        { Res.Set(false); return; }

        const auto View = Get_ViewTransform();
        const auto ViewMoved = float32((View.GetLocation() - _InitialViewLocation).Size()) > 100.0f;
        const auto Depth1Ready = utils_transform::Get_EntityCurrentTransform(_Depth1Leaf).Equals(
            ComposeExpected(View, 1, 0.0f), TransformTolerance);
        const auto Depth2Ready = utils_transform::Get_EntityCurrentTransform(_Depth2Leaf).Equals(
            ComposeExpected(View, 2, 150.0f), TransformTolerance);
        const auto Depth10Ready = utils_transform::Get_EntityCurrentTransform(_Depth10Leaf).Equals(
            ComposeExpected(View, 10, 300.0f), TransformTolerance);

        Res.Set(ViewMoved && Depth1Ready && Depth2Ready && Depth10Ready);
    }

    UFUNCTION()
    private void OnBootstrapComposed(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _BootstrapView = Get_ViewTransform();

        auto CameraEntity = FCk_Handle(_Camera);
        auto& Probe = CameraEntity.AddOrGet_Fragment(
            FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);
        Probe.Completed = false;
        Probe.Succeeded = false;
        Probe.StimulusFrame = -1;
        Probe.ProbeFrame = -1;
        Probe.Depth1Leaf = _Depth1Leaf;
        Probe.Depth2Leaf = _Depth2Leaf;
        Probe.Depth10Leaf = _Depth10Leaf;
        Probe.TargetDirectorTransform = FTransform(
            FRotator(0.0f, -40.0f, 0.0f),
            FVector(-350.0f, 500.0f, 275.0f),
            FVector::OneVector);
        CameraEntity.AddOrGet_Fragment(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProducerMarker);
        CameraEntity.AddOrGet_Fragment(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeMarker);

        WaitUntil(n"Check_ProbeCompleted", n"OnProbeCompleted");
    }

    UFUNCTION()
    private void Check_ProbeCompleted(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto CameraEntity = FCk_Handle(_Camera);
        if (CameraEntity.Has_Fragment(FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult) == false)
        { Res.Set(false); return; }

        const auto& Probe = CameraEntity.Get_Fragment(
            FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);
        Res.Set(Probe.Completed);
    }

    UFUNCTION()
    private void OnProbeCompleted(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto CameraEntity = FCk_Handle(_Camera);
        const auto& Probe = CameraEntity.Get_Fragment(
            FCk_Fragment_TESTONLY_CameraViewAnchorSettleProbeResult);

        Assert_True(Probe.Succeeded,
            "Gameplay_Camera probe must resolve the camera and all three descendant leaves");
        Assert_True(Probe.ProbeFrame == Probe.StimulusFrame,
            f"View-anchor descendants must be observable after Transform_Finalize in the stimulus frame; stimulus [{Probe.StimulusFrame}], probe [{Probe.ProbeFrame}]");
        Assert_True(float32((Probe.ViewTransform.GetLocation() - _BootstrapView.GetLocation()).Size()) > 100.0f,
            "The measured camera view must differ from the bootstrap view, or the timing assertion is vacuous");

        const auto Depth1Expected = ComposeExpected(Probe.ViewTransform, 1, 0.0f);
        const auto Depth2Expected = ComposeExpected(Probe.ViewTransform, 2, 150.0f);
        const auto Depth10Expected = ComposeExpected(Probe.ViewTransform, 10, 300.0f);

        Assert_True(Probe.Depth1Actual.Equals(Depth1Expected, TransformTolerance),
            f"Depth-1 view-anchor child must settle before Transform_Finalize; expected [{Depth1Expected}], actual [{Probe.Depth1Actual}]");
        Assert_True(Probe.Depth2Actual.Equals(Depth2Expected, TransformTolerance),
            f"Depth-2 view-anchor leaf must settle before Transform_Finalize; expected [{Depth2Expected}], actual [{Probe.Depth2Actual}]");
        Assert_True(Probe.Depth10Actual.Equals(Depth10Expected, TransformTolerance),
            f"Depth-10 view-anchor leaf must settle before Transform_Finalize; expected [{Depth10Expected}], actual [{Probe.Depth10Actual}]");

        FinishSuccess();
    }
}

class ACk_AutoTest_GameplayCamera_ViewAnchorDescendantsSettleSameFrame_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_GameplayCamera_ViewAnchorDescendantsSettleSameFrame;
    default _TimeoutSeconds = 10.0f;
}
