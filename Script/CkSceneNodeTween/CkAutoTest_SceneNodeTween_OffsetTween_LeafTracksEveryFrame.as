// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN - AUTOMATION TEST: OFFSET TWEEN, LEAF TRACKS EVERY FRAME
//============================================================================
//
// The offset-driven sibling of the Depth0/Depth1/Depth4 tests, which drive a
// WORLD-space root. This one drives a child SceneNode's OFFSET - the shape the
// Create_TweenSceneNodeOffset* API exists for, and the shape every animated
// piece of store furniture actually uses (the register's change tray, the
// credit card, the delivery truck's doors).
//
// It asserts two things that nothing else in the corpus asserted:
//
//   1. PROGRESSION. The tween must be observed at strictly-intermediate
//      offsets on several separate frames. Every existing test asserts only
//      that a tween was created, or that it LANDED - so a tween that jumps
//      straight to its end value in a single frame passes all of them. That
//      is a real player-visible defect (furniture that snaps instead of
//      animating) with, until now, no detector.
//
//   2. PROPAGATION UNDER A MOVING OFFSET. A leaf parented to the tweened node
//      must track the composed expectation on EVERY sampled frame, not just
//      after the tween completes. SceneNode propagation is sparse - nodes are
//      recomputed when queued, not scanned every frame - so a node that stops
//      being queued mid-motion goes still while its offset fragment keeps
//      advancing. That divergence is invisible to any assertion that only
//      reads the offset, and invisible to any assertion that only samples
//      after everything has settled.
//
// Both failures look identical in the offset fragment and completely
// different on screen, which is why this test reads the composed WORLD
// transform of the leaf rather than the offset it was driven from.
//============================================================================

class UCk_AutoTest_SceneNodeTween_OffsetTween_LeafTracksEveryFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    // The pivot's closed/open offsets, and the leaf carried by it. Deliberately
    // non-axis-aligned so a dropped composition cannot coincidentally match.
    private const FVector PivotClosedLocal = FVector(30.0f, -10.0f, 15.0f);
    private const FVector PivotOpenLocal   = FVector(30.0f, 90.0f, 15.0f);
    private const FVector LeafLocal        = FVector(0.0f, 0.0f, 25.0f);
    private const FRotator LeafLocalRot    = FRotator(0.0f, 20.0f, 0.0f);

    // 1.0s rather than the ~0.25s the gameplay call sites use: a full-suite run
    // spreads tests across concurrent editors, so a fixed number of seconds buys
    // far fewer frames than it does in isolation. At 1.0s the progression
    // assertion below still holds at any frame time under ~0.33s.
    private const float32 TweenDurationSec = 1.0f;
    private const float32 DriftToleranceCm = 1.0f;
    private const float32 EndToleranceCm = 1.0f;
    private const int32 MinIntermediateSamples = 3;

    private FCk_Handle _TestEntity;
    private FCk_Handle_Transform _PivotTH;
    private FCk_Handle_SceneNode _PivotNode;
    private FCk_Handle_SceneNode _LeafNode;
    private FCk_Handle_Tween _Tween;

    // The pivot's visual. This is the consumer the player actually sees: a mesh added to the
    // tweened node, pushed by FProcessor_UnrealComponent_PushTransform, which requires
    // FTag_Transform_Updated in the main pass. Asserting only on ECS transforms would pass while
    // every piece of furniture sat frozen on screen, so the component's own world transform is
    // checked against the ECS transform it is supposed to mirror.
    private FCk_Handle_UnrealComponent _PivotComp;
    private float32 _MaxCompMismatch = 0.0f;
    private int32 _CompSamples = 0;

    private float32 _MaxDrift = 0.0f;
    private int32 _SampleCount = 0;
    private int32 _IntermediateSamples = 0;
    private bool _TweenComplete = false;

    // How far each end of the chain actually travelled, in world space, while the tween ran.
    // Reported in the failure message so a stall names WHICH link stopped: a pivot that moved
    // and a leaf that did not is a propagation failure; neither moving is a tween failure.
    private FVector _FirstPivotWorld;
    private FVector _FirstLeafWorld;
    private bool _FirstWorldCaptured = false;
    private float32 _PivotWorldTravel = 0.0f;
    private float32 _LeafWorldTravel = 0.0f;

    // Largest single-frame jump each link made. This is what separates the two failure shapes:
    // smooth motion steps by roughly amplitude/frames (~1.7cm here), while a link that sits
    // still and then teleports to its final pose steps by nearly the whole amplitude at once.
    private FVector _PrevLeafWorld;
    private FVector _PrevPivotWorld;
    private float32 _MaxLeafStep = 0.0f;
    private float32 _MaxPivotStep = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _TestEntity = InHandle;

        // The fixture root: a plain world-space Transform, standing in for the
        // placed actor that owns the furniture. It never moves in this test, so
        // any leaf motion observed below came through the pivot's offset.
        auto RootEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto RootTransform = utils_transform::Add(RootEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(RootTransform))
        {
            FinishFailure("Failed to add Transform feature to fixture root entity");
            return;
        }

        auto PivotLocal = FTransform(FRotator::ZeroRotator, PivotClosedLocal, FVector::OneVector);
        _PivotNode = utils_scene_node::Create(RootTransform, PivotLocal);
        if (ck::Is_NOT_Valid(_PivotNode))
        {
            FinishFailure("Failed to create pivot SceneNode (the tweened node)");
            return;
        }
        _PivotTH = _PivotNode.As_Transform();

        auto LeafXf = FTransform(LeafLocalRot, LeafLocal, FVector::OneVector);
        _LeafNode = utils_scene_node::Create(_PivotTH, LeafXf);
        if (ck::Is_NOT_Valid(_LeafNode))
        {
            FinishFailure("Failed to create leaf SceneNode under the pivot");
            return;
        }

        auto PivotEntity = FCk_Handle(_PivotTH);
        const auto CompParams = utils_unreal_component::Make_Params(
            USceneComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"OffsetTweenPivotVisual");
        _PivotComp = utils_unreal_component::Add(PivotEntity, CompParams);
        if (ck::Is_NOT_Valid(_PivotComp))
        {
            FinishFailure("Failed to add the pivot's UnrealComponent (the visual under test)");
            return;
        }

        // The live component is created a frame later by the setup processor, so the tween cannot
        // start until it exists - otherwise the first frames of motion are unobservable and the
        // component assertion silently measures nothing.
        WaitUntil(n"Check_ComponentReady", n"OnComponentReady");
    }

    UFUNCTION()
    private void Check_ComponentReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_unreal_component::Get_Component(_PivotComp)));
    }

    UFUNCTION()
    private void OnComponentReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Tween = utils_tween::Create_TweenSceneNodeOffsetLocation(
            _PivotNode, PivotOpenLocal, TweenDurationSec,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        // Fail loudly here rather than time out silently: a refused tween is the
        // exact failure the world-space guard produces, and a bare timeout does
        // not say which of the two happened.
        if (ck::Is_NOT_Valid(_Tween))
        {
            FinishFailure("Create_TweenSceneNodeOffsetLocation refused a legitimate parent-driven SceneNode");
            return;
        }

        utils_tween::BindTo_OnComplete(_Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));

        utils_timer::Create_Tick(_TestEntity, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _SampleCount += 1;
        // Skip the first sample: the SceneNode features were composed this same
        // tick and need one processor pass to publish the leaf's world transform.
        if (_SampleCount < 2) { return; }

        // Composed from the pivot's WORLD transform, which is itself derived
        // from the offset the tween writes - so this compares the leaf against
        // the chain that actually drives it, not against a replayed prediction.
        auto PivotWorld = utils_transform::Get_EntityCurrentTransform(_PivotTH);
        auto LeafXf = FTransform(LeafLocalRot, LeafLocal, FVector::OneVector);
        auto Expected = (LeafXf * PivotWorld).GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(_LeafNode.As_Transform());

        auto DX = Math::Abs(Expected.X - Actual.X);
        auto DY = Math::Abs(Expected.Y - Actual.Y);
        auto DZ = Math::Abs(Expected.Z - Actual.Z);
        auto Drift = Math::Max(Math::Max(DX, DY), DZ);
        if (Drift > _MaxDrift) { _MaxDrift = float32(Drift); }

        auto PivotWorldLoc = PivotWorld.GetLocation();
        if (!_FirstWorldCaptured)
        {
            _FirstPivotWorld = PivotWorldLoc;
            _FirstLeafWorld = Actual;
            _PrevPivotWorld = PivotWorldLoc;
            _PrevLeafWorld = Actual;
            _FirstWorldCaptured = true;
        }
        else
        {
            auto LeafStep = (Actual - _PrevLeafWorld).Size();
            auto PivotStep = (PivotWorldLoc - _PrevPivotWorld).Size();
            if (LeafStep > _MaxLeafStep) { _MaxLeafStep = float32(LeafStep); }
            if (PivotStep > _MaxPivotStep) { _MaxPivotStep = float32(PivotStep); }
            _PrevLeafWorld = Actual;
            _PrevPivotWorld = PivotWorldLoc;
        }
        auto PivotTravel = (PivotWorldLoc - _FirstPivotWorld).Size();
        auto LeafTravel = (Actual - _FirstLeafWorld).Size();
        if (PivotTravel > _PivotWorldTravel) { _PivotWorldTravel = float32(PivotTravel); }
        if (LeafTravel > _LeafWorldTravel) { _LeafWorldTravel = float32(LeafTravel); }

        // The visual consumer: the component must mirror the ECS transform it is driven from.
        auto PivotSceneComp = Cast<USceneComponent>(utils_unreal_component::Get_Component(_PivotComp));
        if (ck::IsValid(PivotSceneComp))
        {
            _CompSamples += 1;
            auto CompMismatch = (PivotSceneComp.GetWorldLocation() - PivotWorldLoc).Size();
            if (CompMismatch > _MaxCompMismatch) { _MaxCompMismatch = float32(CompMismatch); }
        }

        // Progression: the pivot must be caught strictly between its endpoints.
        // Y is the only axis the tween moves, so a sample that is neither closed
        // nor open is genuine intermediate motion.
        auto PivotOffsetY = utils_scene_node::Get_Offset_Location(_PivotNode).Y;
        auto IsAtClosed = Math::Abs(PivotOffsetY - PivotClosedLocal.Y) < EndToleranceCm;
        auto IsAtOpen = Math::Abs(PivotOffsetY - PivotOpenLocal.Y) < EndToleranceCm;
        if (!IsAtClosed && !IsAtOpen)
        { _IntermediateSamples += 1; }
    }

    UFUNCTION()
    private void OnTweenComplete(FCk_Handle_Tween InHandle, FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }
        _TweenComplete = true;
        WaitUntil(n"Check_LeafReachedOpenPose", n"OnFinalSettle");
    }

    // OnComplete fires from the tween's update pass; the final offset write and the leaf's
    // recomposition land in later passes. This is a genuine positive condition - it is false
    // until that chain has actually run - so a propagation that never arrives is reported as
    // this named condition rather than as an anonymous timeout.
    UFUNCTION()
    private void Check_LeafReachedOpenPose(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto PivotWorld = utils_transform::Get_EntityCurrentTransform(_PivotTH);
        auto LeafXf = FTransform(LeafLocalRot, LeafLocal, FVector::OneVector);
        auto ExpectedLeaf = (LeafXf * PivotWorld).GetLocation();
        auto ActualLeaf = utils_transform::Get_EntityCurrentLocation(_LeafNode.As_Transform());

        auto OffsetY = utils_scene_node::Get_Offset_Location(_PivotNode).Y;

        auto Res = OutResult;
        Res.Set(Math::Abs(OffsetY - PivotOpenLocal.Y) < EndToleranceCm
             && ActualLeaf.Equals(ExpectedLeaf, DriftToleranceCm));
    }

    UFUNCTION()
    private void OnFinalSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_TweenComplete, "Tween OnComplete must fire before the final assert");

        Assert_True(_IntermediateSamples >= MinIntermediateSamples,
            f"Offset tween must be observed mid-motion on at least {MinIntermediateSamples} frames over its {TweenDurationSec}s duration - a tween that reaches its end value in one frame is a snap, not an animation (intermediate samples: {_IntermediateSamples} of {_SampleCount})");

        auto FinalOffset = utils_scene_node::Get_Offset_Location(_PivotNode);
        Assert_True(Math::Abs(FinalOffset.Y - PivotOpenLocal.Y) < EndToleranceCm,
            f"Pivot offset must land on the tween end value (expected Y {PivotOpenLocal.Y}, got {FinalOffset.Y})");

        Assert_True(_MaxDrift < DriftToleranceCm,
            f"Leaf world location must track the pivot's composed world transform within {DriftToleranceCm}cm on EVERY sampled frame - a leaf that only catches up after the tween ends is a stalled propagation (max drift observed: {_MaxDrift}cm; world travel during the tween: pivot {_PivotWorldTravel}cm vs leaf {_LeafWorldTravel}cm; largest single-frame jump: pivot {_MaxPivotStep}cm vs leaf {_MaxLeafStep}cm)");

        Assert_True(_CompSamples >= MinIntermediateSamples,
            f"The pivot's component must have been sampled on several frames (got {_CompSamples})");

        Assert_True(_MaxCompMismatch < DriftToleranceCm,
            f"The pivot's UnrealComponent must mirror the pivot's ECS world transform within {DriftToleranceCm}cm on EVERY sampled frame - a component that stops following is furniture frozen on screen while the ECS thinks it moved (max mismatch observed: {_MaxCompMismatch}cm over {_CompSamples} samples)");

        FinishSuccess();
    }
}
