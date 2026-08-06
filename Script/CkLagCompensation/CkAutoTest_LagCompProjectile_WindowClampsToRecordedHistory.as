// Language=angelscript

//============================================================================
// CK LAG COMP PROJECTILE — AUTOMATION TEST: WINDOW CLAMPS TO RECORDED HISTORY
//============================================================================
//
// A compensated launch arrives with a compensation window (30s) that reaches
// far beyond the target's recorded history (<1s). The launch anchor honors
// the requested window — that is the deterministic trajectory contract — but
// the rewind sweep must only validate against the span the history actually
// recorded. The trajectory crossed the target's position ~30s ago in
// simulated time, when NO history existed, so:
//   - ZERO rewind hits are confirmed (the pre-fix code manufactured a hit
//     there by clamping ancient times to the oldest recorded pose), and
//   - the sweep terminates promptly (bounded by retention, not by the
//     window — the pre-fix code iterated the full 30s slice by slice).
//============================================================================

class UCk_AutoTest_LagCompProjectile_WindowClampsToRecordedHistory : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _TargetEntity;
    private FCk_Handle_RewindHistory _TargetHistory;
    private FCk_Handle_BallisticMotion _Projectile;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _TargetEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(
            _TargetEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0))));

        _TargetHistory = UCk_Utils_RewindHistory_UE::Add(_TargetEntity, FCk_Fragment_RewindHistory_ParamsData(HitShapes));

        ScheduleMark(0.4, n"OnMark1");
    }

    private void ScheduleMark(float InDelaySeconds, FName InCallbackName)
    {
        auto Params = FCk_Timer_Spec(FCk_Time(InDelaySeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_SelfHandle, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnMark1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, FVector(-400.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);

        auto TrajectoryParams = FCk_Ballistic_TrajectoryParams(FVector(0.0, 0.0, -100000.0));
        _Projectile = UCk_Utils_BallisticMotion_UE::Add(Projectile, FCk_Fragment_BallisticMotion_ParamsData(TrajectoryParams));

        _Projectile.BindTo_OnLaunchCompensated(FCk_Delegate_LagCompProjectile_OnLaunchCompensated(this, n"OnLaunchCompensated"));

        _Projectile.Request_LaunchCompensated(
            FCk_Request_LagCompProjectile_LaunchCompensated(FVector(10000.0, 0.0, 0.0), FCk_Time(30.0)));
    }

    UFUNCTION()
    private void OnLaunchCompensated(
        FCk_Handle_BallisticMotion InHandle,
        FCk_Ballistic_InitialConditions InInitialConditions,
        const TArray<FCk_LagComp_RewindHit>&in InRewindHits)
    {
        if (IsFinished()) { return; }

        auto NewestRecorded = _TargetHistory.Get_NewestFrameTime().Get_Seconds();

        // The launch anchor honors the request — 30s in the past (plus the fudge factor)
        Assert_True(InInitialConditions.Get_StartTime().Get_Seconds() < NewestRecorded - 29.0,
            f"Launch anchor should honor the requested window (start={InInitialConditions.Get_StartTime().Get_Seconds()}, newest={NewestRecorded})");

        // The trajectory passed the target's location ~30s before any history was recorded —
        // clamping ancient times to the oldest recorded pose must NOT manufacture a hit
        Assert_Equals_Int(InRewindHits.Num(), 0,
            "No rewind hits: the catch-up crossed the target in the pre-history era");

        FinishSuccess();
    }
}
