// Language=angelscript

//============================================================================
// CK LAG COMP PROJECTILE — AUTOMATION TEST: COMPENSATED LAUNCH HITS PAST POSE
//============================================================================
//
// The full MWO scenario, single-world:
//   1. Target (Body sphere, RewindHistory) sits at A while the server records.
//   2. Target strafes to B (perpendicular to the shot axis).
//   3. A 'late' fire request arrives: Request_LaunchCompensated with a window
//      reaching back into the A era — exactly what a laggy shooter saw.
//   4. The rewind validation must confirm the hit on the PAST pose (target is
//      long gone from A at fire time) and report it via OnRewindHit /
//      OnLaunchCompensated with the analytic hit time inside the A era.
//============================================================================

class UCk_AutoTest_LagCompProjectile_CompensatedLaunchHitsPastPose : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _TargetEntity;
    private FCk_Handle_RewindHistory _TargetHistory;
    private FCk_Handle_Transform _TargetTransform;
    private FCk_Handle_BallisticMotion _Projectile;

    private FVector _PoseA = FVector(0.0, 0.0, 0.0);
    private FVector _PoseB = FVector(0.0, 1000.0, 0.0);
    private FVector _ShooterLocation = FVector(-400.0, 0.0, 0.0);

    private float _TimeAtA = 0.0;
    private int32 _RewindHitSignals = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _TargetEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _TargetTransform = utils_transform::Add(
            _TargetEntity, FTransform(FRotator::ZeroRotator, _PoseA), ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0))));

        _TargetHistory = UCk_Utils_RewindHistory_UE::Add(_TargetEntity, FCk_RewindHistory_Spec(HitShapes));

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

        _TimeAtA = _TargetHistory.Get_NewestFrameTime().Get_Seconds();

        utils_transform::Request_SetLocation(_TargetTransform, FCk_Request_Transform_SetLocation(_PoseB));

        ScheduleMark(0.4, n"OnMark2");
    }

    UFUNCTION()
    private void OnMark2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // The 'late' shot: fired (in the shooter's reality) while the target was still at A.
        // Window reaches back to T_A − 0.04; the fudge factor pushes it slightly further.
        // 10000 cm/s from X=-400 crosses the sphere surface ~3.5ms after launch — inside the
        // catch-up window and inside the A era of the recorded history
        auto NowApprox = _TargetHistory.Get_NewestFrameTime().Get_Seconds();
        auto Window = NowApprox - (_TimeAtA - 0.04);

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        auto ProjectileTransform = utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, _ShooterLocation), ECk_Replication::DoesNotReplicate);

        auto TrajectoryParams = FCk_Ballistic_TrajectoryParams(FVector(0.0, 0.0, -100000.0));
        _Projectile = UCk_Utils_BallisticMotion_UE::Add(Projectile, FCk_BallisticMotion_Spec(TrajectoryParams));

        _Projectile.BindTo_OnRewindHit(FCk_Delegate_LagCompProjectile_OnRewindHit(this, n"OnRewindHit"));
        _Projectile.BindTo_OnLaunchCompensated(FCk_Delegate_LagCompProjectile_OnLaunchCompensated(this, n"OnLaunchCompensated"));

        _Projectile.Request_LaunchCompensated(
            FCk_Request_LagCompProjectile_LaunchCompensated(FVector(10000.0, 0.0, 0.0), FCk_Time(Window)));
    }

    UFUNCTION()
    private void OnRewindHit(
        FCk_Handle_BallisticMotion InHandle,
        FCk_LagComp_RewindHit InHit)
    {
        if (IsFinished()) { return; }

        _RewindHitSignals++;

        Assert_True(InHit.Get_TargetEntity() == _TargetEntity,
            "Rewind hit should reference the target entity");
        Assert_True(InHit.Get_HitShapeLabel() == utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            "Rewind hit should carry the 'Body' label");
    }

    UFUNCTION()
    private void OnLaunchCompensated(
        FCk_Handle_BallisticMotion InHandle,
        FCk_Ballistic_InitialConditions InInitialConditions,
        const TArray<FCk_LagComp_RewindHit>&in InRewindHits)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(InRewindHits.Num(), 1, "Exactly one rewind hit confirmed");
        Assert_Equals_Int(_RewindHitSignals, 1, "OnRewindHit fired exactly once");

        Assert_True(InInitialConditions.Get_StartTime().Get_Seconds() < _TimeAtA,
            "Trajectory should be anchored in the past, before the target left A");

        if (InRewindHits.Num() == 1)
        {
            auto Hit = InRewindHits[0];

            Assert_True(Hit.Get_HitWorldTime().Get_Seconds() < _TimeAtA + 0.01,
                f"Hit time should fall inside the A era (hit={Hit.Get_HitWorldTime().Get_Seconds()}, T_A={_TimeAtA})");

            // Entry point of the shot into the (50+5)-inflated sphere at A is x≈-55
            Assert_True((Hit.Get_HitLocation() - FVector(-55.0, 0.0, 0.0)).Size() < 25.0,
                f"Hit location should be at the sphere entry point (got {Hit.Get_HitLocation()})");
        }

        // The target is at B NOW — the hit was only possible through the rewound history
        auto TargetNow = utils_transform::Get_EntityCurrentLocation(_TargetTransform);
        Assert_True((TargetNow - _PoseB).Size() < 5.0,
            "Target must already be at B when the compensated shot is validated");

        FinishSuccess();
    }
}
