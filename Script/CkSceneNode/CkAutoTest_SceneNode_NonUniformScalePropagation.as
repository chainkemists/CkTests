// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: NON-UNIFORM PARENT SCALE PROPAGATION
//============================================================================
//
// Existing OffsetUpdates uses an identity-transform parent (parent at world
// origin, no rotation, scale 1) so the child's world == its local. That's
// fine for asserting the offset-mutation API, but it misses the case where
// a parent's non-identity transform (specifically: non-uniform scale)
// composes with the child's local offset.
//
// Setup:
//   Parent transform: Loc=(100,0,0), Rot=Identity, Scale=(0.5, 1.0, 2.0)
//   Child SceneNode local offset: Loc=(0, 100, 50), Rot=Identity, Scale=1
//
// Expected child world location (parent.Loc + parent.Scale * child.LocalLoc):
//   X: 100 + 0.5 * 0   =  100
//   Y:   0 + 1.0 * 100 =  100
//   Z:   0 + 2.0 * 50  =  100
//
// If non-uniform parent scale is incorrectly treated as uniform, or if the
// composition collapses to identity, the child world location will diverge
// from (100, 100, 100).
//
// Per memory `transform_rotation_precision`: use Math::Abs comparisons with
// tolerance, never `==` on floats.
//============================================================================

class UCk_AutoTest_SceneNode_NonUniformScalePropagation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector ParentLocation = FVector(100.0f, 0.0f, 0.0f);
    private const FVector ParentScale = FVector(0.5f, 1.0f, 2.0f);
    private const FVector ChildLocalLoc = FVector(0.0f, 100.0f, 50.0f);
    private const FVector ExpectedChildWorld = FVector(100.0f, 100.0f, 100.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle_Transform _ChildTransform;
    private float32 _Waited = 0.0f;
    private bool _Asserted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentXf = FTransform(FRotator::ZeroRotator, ParentLocation, ParentScale);
        auto ParentTransform = utils_transform::Add(ParentEntity, ParentXf, ECk_Replication::DoesNotReplicate);

        auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildLocalLoc, FVector::OneVector);
        auto ChildNode = utils_scene_node::Create(ParentTransform, ChildLocal);
        _ChildTransform = ChildNode.As_Transform();

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Asserted) { return; }

        _Waited += float32(InDeltaT.Get_Seconds());
        if (_Waited < PropagationWaitSeconds) { return; }
        _Asserted = true;

        auto ActualWorld = utils_transform::Get_EntityCurrentLocation(_ChildTransform);

        auto DX = Math::Abs(ActualWorld.X - ExpectedChildWorld.X);
        auto DY = Math::Abs(ActualWorld.Y - ExpectedChildWorld.Y);
        auto DZ = Math::Abs(ActualWorld.Z - ExpectedChildWorld.Z);

        Assert_True(DX < PositionToleranceCm,
            f"Child world X | parent.Scale.X={ParentScale.X}, child.LocalLoc.X={ChildLocalLoc.X}, expected world X={ExpectedChildWorld.X}, got {ActualWorld.X}");
        Assert_True(DY < PositionToleranceCm,
            f"Child world Y | parent.Scale.Y={ParentScale.Y}, child.LocalLoc.Y={ChildLocalLoc.Y}, expected world Y={ExpectedChildWorld.Y}, got {ActualWorld.Y}");
        Assert_True(DZ < PositionToleranceCm,
            f"Child world Z | parent.Scale.Z={ParentScale.Z}, child.LocalLoc.Z={ChildLocalLoc.Z}, expected world Z={ExpectedChildWorld.Z}, got {ActualWorld.Z}");

        FinishSuccess();
    }
}
