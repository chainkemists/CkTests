// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: ROTATED GRID PIVOT WORLD ROTATION
//============================================================================
//
// Pins that Request_UpdatePivot propagates rotation into the grid's pivot
// world transform.
//
// Setup:
//   3x3 grid of 100x100 cells, identity pivot.
//
// Procedure:
//   1. Capture Get_Pivot(World).Yaw - should be ~0.
//   2. Request_UpdatePivot with FRotator(0, 90, 0) (90-degree yaw offset).
//   3. Tick-poll until Get_Pivot(World).Yaw reflects the change.
//   4. Assert that Get_Pivot(World).Yaw is now ~90deg, NOT ~0.
//
// Per memory `transform_rotation_precision`: rotator round-trips through
// quaternions lose precision; use Math::Abs(A-B) < tolerance comparisons,
// never `==`. AS namespace is Math::, not FMath::.
//============================================================================

class UCk_AutoTest_Grid_RotationLocalCoordMapping : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const float32 PropagationWaitSeconds = 0.25f;
    private const float32 RotationToleranceDeg = 1.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private float32 _Waited = 0.0f;
    private bool _Asserted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridTransform = utils_transform::Add(
            Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        Params.Set_DefaultCellState(ECk_EnableDisable::Enable);
        _Grid = utils_2d_grid_system::Add(GridTransform, Params);

        // Baseline: pivot world rotation at identity grid transform.
        auto BaselineYaw = utils_2d_grid_system::Get_Pivot(_Grid, ECk_LocalWorld::World).Rotator().Yaw;
        Assert_True(Math::Abs(BaselineYaw) < RotationToleranceDeg,
            f"Baseline pivot world yaw should be ~0 at identity (got {BaselineYaw})");

        // Rotate the grid pivot by 90 degrees yaw.
        utils_2d_grid_system::Request_UpdatePivot(_Grid, FVector::ZeroVector, FRotator(0.0f, 90.0f, 0.0f));

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

        auto RotatedYaw = utils_2d_grid_system::Get_Pivot(_Grid, ECk_LocalWorld::World).Rotator().Yaw;

        // After a 90deg yaw offset, the world pivot rotation should reflect
        // the change. Regression target: pivot update silently no-ops or the
        // request never lands on the grid fragment.
        auto YawDelta = Math::Abs(RotatedYaw - 90.0f);
        Assert_True(YawDelta < RotationToleranceDeg,
            f"After Request_UpdatePivot(yaw=90deg), Get_Pivot(World) yaw should be ~90deg (got {RotatedYaw})");

        FinishSuccess();
    }
}
