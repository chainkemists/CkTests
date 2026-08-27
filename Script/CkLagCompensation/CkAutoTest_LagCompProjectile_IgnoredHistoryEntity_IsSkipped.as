// Language=angelscript

//============================================================================
// CK LAG COMP PROJECTILE - AUTOMATION TEST: IGNORED HISTORY ENTITY IS SKIPPED
//============================================================================
//
// Two stationary targets with recorded hitbox history sit dead on the shot
// line. The compensated launch names the NEAR one as the ignored history
// entity (the "shooter's own history" use case) - rewind validation must
// confirm exactly one hit, on the far target only.
//============================================================================

class UCk_AutoTest_LagCompProjectile_IgnoredHistoryEntity_IsSkipped : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _NearTarget;
    private FCk_Handle _FarTarget;
    private FCk_Handle_BallisticMotion _Projectile;
    private int32 _RewindHitSignals = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _NearTarget = CreateHistoryTarget(FVector(0.0, 0.0, 0.0));
        _FarTarget = CreateHistoryTarget(FVector(300.0, 0.0, 0.0));

        ScheduleMark(0.4, n"OnMark1");
    }

    private FCk_Handle CreateHistoryTarget(FVector InLocation)
    {
        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(
            Target, FTransform(FRotator::ZeroRotator, InLocation), ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0))));

        UCk_Utils_RewindHistory_UE::Add(Target, FCk_Fragment_RewindHistory_ParamsData(HitShapes));

        return Target;
    }

    private void ScheduleMark(float InDelaySeconds, FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(InDelaySeconds));
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

        _Projectile.BindTo_OnRewindHit(FCk_Delegate_LagCompProjectile_OnRewindHit(this, n"OnRewindHit"));
        _Projectile.BindTo_OnLaunchCompensated(FCk_Delegate_LagCompProjectile_OnLaunchCompensated(this, n"OnLaunchCompensated"));

        auto Request = FCk_Request_LagCompProjectile_LaunchCompensated(FVector(10000.0, 0.0, 0.0), FCk_Time(0.2));
        Request.Set_IgnoredHistoryEntity(_NearTarget);

        _Projectile.Request_LaunchCompensated(Request);
    }

    UFUNCTION()
    private void OnRewindHit(
        FCk_Handle_BallisticMotion InHandle,
        FCk_LagComp_RewindHit InHit)
    {
        if (IsFinished()) { return; }

        _RewindHitSignals++;

        Assert_True(InHit.Get_TargetEntity() == _FarTarget,
            "The only rewind hit should be on the far target - the near one is ignored");
    }

    UFUNCTION()
    private void OnLaunchCompensated(
        FCk_Handle_BallisticMotion InHandle,
        FCk_Ballistic_InitialConditions InInitialConditions,
        const TArray<FCk_LagComp_RewindHit>&in InRewindHits)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(InRewindHits.Num(), 1, "Exactly one rewind hit - the ignored target contributes none");
        Assert_Equals_Int(_RewindHitSignals, 1, "OnRewindHit fired exactly once");

        if (InRewindHits.Num() == 1)
        {
            Assert_True(InRewindHits[0].Get_TargetEntity() == _FarTarget,
                "The confirmed hit should reference the far target");
        }

        FinishSuccess();
    }
}
