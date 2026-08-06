// Language=angelscript

//============================================================================
// CK BALLISTIC MOTION — AUTOMATION TEST: IMPACT STOPS PROJECTILE
//============================================================================
//
// Verifies the probe-driven impact path (FProcessor_BallisticMotion_HandleImpacts):
//   1. Projectile: Transform + sphere shape + LinearCast kinematic probe +
//      BallisticMotion (ImpactResponse = Stop), launched at a static target.
//   2. Target: Transform + large sphere shape + static probe.
//   3. OnImpact fires with Outcome=Stopped and the analytic impact data;
//      OnStopped fires; the projectile clamps near the target surface and
//      leaves flight.
//============================================================================

namespace ck_ballistic_motion_test
{
    asset Asset_BallisticMotionTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.BallisticMotion.Projectile");
        GameplayTags.Add(n"CkTests.BallisticMotion.Target");
    }
}

class UCk_AutoTest_BallisticMotion_ImpactStopsProjectile : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_BallisticMotion _Motion;
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle _TargetEntity;

    private bool _ImpactObserved = false;
    private bool _StoppedObserved = false;

    private FVector _ProjectileStart = FVector(0.0, 0.0, 300.0);
    private FVector _TargetCenter = FVector(600.0, 0.0, 300.0);
    private float32 _TargetRadius = 150.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Target: static sphere probe the projectile can hit ----
        _TargetEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _TargetEntity.Request_OverrideToSelf();
        auto TargetTransform = utils_transform::Add(
            _TargetEntity, FTransform(FRotator::ZeroRotator, _TargetCenter), ECk_Replication::DoesNotReplicate);

        auto TargetProbeParams = FCk_Probe_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.BallisticMotion.Target"));
        TargetProbeParams.Set_MotionType(ECk_MotionType::Static);
        TargetProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        utils_probe::Add_Sphere(TargetTransform, _TargetRadius, TargetProbeParams, FCk_Probe_DebugInfo());

        // ---- Projectile: LinearCast kinematic probe + ballistic motion ----
        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Projectile.Request_OverrideToSelf();
        _ProjectileTransform = utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, _ProjectileStart), ECk_Replication::DoesNotReplicate);

        auto ProjectileProbeParams = FCk_Probe_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.BallisticMotion.Projectile"));
        ProjectileProbeParams.Set_MotionType(ECk_MotionType::Kinematic);
        ProjectileProbeParams.Set_MotionQuality(ECk_MotionQuality::LinearCast);
        ProjectileProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.BallisticMotion.Target"));
        ProjectileProbeParams.Set_Filter(Filter);

        utils_probe::Add_Sphere(_ProjectileTransform, 10.0, ProjectileProbeParams, FCk_Probe_DebugInfo());

        // Heavy terminal velocity ≈ negligible drag over the short hop; drop over 0.3s is ~44cm,
        // well inside the 150cm target radius
        auto TrajectoryParams = FCk_Ballistic_TrajectoryParams(FVector(0.0, 0.0, -100000.0));
        auto MotionParams = FCk_BallisticMotion_Spec(TrajectoryParams);
        MotionParams.Set_ImpactResponse(ECk_BallisticMotion_ImpactResponse::Stop);

        _Motion = UCk_Utils_BallisticMotion_UE::Add(Projectile, MotionParams);

        _Motion.BindTo_OnImpact(FCk_Delegate_BallisticMotion_OnImpact(this, n"OnImpact"));
        _Motion.BindTo_OnStopped(FCk_Delegate_BallisticMotion_OnStopped(this, n"OnStopped"));

        _Motion.Request_Launch(FCk_Request_BallisticMotion_Launch(FVector(2000.0, 0.0, 0.0)));
    }

    UFUNCTION()
    private void OnImpact(
        FCk_Handle_BallisticMotion InHandle,
        FCk_BallisticMotion_Payload_OnImpact InPayload)
    {
        if (IsFinished()) { return; }

        _ImpactObserved = true;

        Assert_True(InPayload.Get_OtherEntity() == _TargetEntity,
            "Impact payload should reference the target entity");
        Assert_True(InPayload.Get_Outcome() == ECk_BallisticMotion_ImpactOutcome::Stopped,
            "ImpactResponse=Stop should produce a Stopped outcome");
        Assert_True(InPayload.Get_ImpactVelocity().X > 1000.0,
            f"Impact velocity should be mostly forward (got X={InPayload.Get_ImpactVelocity().X})");

        // The analytic impact point should sit near the target sphere's surface facing the shooter
        auto DistanceToCenter = (InPayload.Get_ImpactLocation() - _TargetCenter).Size();
        Assert_True(Math::Abs(DistanceToCenter - _TargetRadius) < 75.0,
            f"Impact location should be near the target surface (distance to center={DistanceToCenter})");
    }

    UFUNCTION()
    private void OnStopped(
        FCk_Handle_BallisticMotion InHandle,
        FVector InFinalLocation)
    {
        if (IsFinished()) { return; }

        _StoppedObserved = true;

        Assert_True(_ImpactObserved, "OnImpact should fire before OnStopped");

        // Let the deferred transform clamp settle, then verify final state
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_StoppedObserved, "OnStopped should have fired");
        Assert_True(!_Motion.Get_IsInFlight(),
            "Projectile should no longer be in flight after a Stop impact");

        auto FinalLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
        auto DistanceToCenter = (FinalLocation - _TargetCenter).Size();
        Assert_True(DistanceToCenter < _TargetRadius + 75.0,
            f"Stopped projectile should rest at/inside the target surface (distance to center={DistanceToCenter})");

        FinishSuccess();
    }
}
